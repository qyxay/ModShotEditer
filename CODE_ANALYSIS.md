# ModShot-mkxp-z 代码功能全解析

> **项目**：ModShot-mkxp-z — OneShot 游戏的 mkxp-z 引擎 mod 分支
> **分析范围**：项目中全部 Ruby 代码（mod 脚本 15 个 + 游戏脚本 111 个 + 分析工具 80+ 个 + 根目录工具 5 个）
> **分析方式**：纯静态代码阅读，未启动游戏或执行任何脚本
> **生成时间**：2026-09-07

---

## 一、项目总览

### 1.1 项目定位

ModShot-mkxp-z 是基于 **mkxp-z**（自编译的 RPG Maker XP 运行时）的 OneShot 游戏 mod 项目。核心目标是在**不修改原版游戏数据**（`xScripts.rxdata`）的前提下，通过 **preload 注入 + Module#prepend** 的方式为游戏添加开发者功能（跳地图、跳过对话/事件/过场、碰撞调试、随时退出等）。

### 1.2 技术栈

| 组件 | 说明 |
|------|------|
| 引擎 | mkxp-z（ModShot 自编译分支），RGSS 运行时 |
| Ruby | 3.1.5（`runtime/bin/ruby.exe`，标准库位于 `runtime/lib/ruby/3.1.0/`） |
| 游戏 | OneShot（RPG Maker XP 游戏，元叙事解谜） |
| 补丁机制 | `TracePoint(:end)` 等待类定义 + `Module#prepend` 挂载补丁 |
| 配置 | `config.json`（11 个功能开关） |

### 1.3 代码分层架构

```
┌─────────────────────────────────────────────────────────┐
│                    根目录工具脚本 (5个)                    │
│  pack/unpack_xscripts.rb  _dump_scripts.rb               │
│  _inspect_maps.rb  _verify_jump.rb                       │
│  功能：脚本解包/打包、地图数据检查、跳跃验证               │
├─────────────────────────────────────────────────────────┤
│                   _analyze/ 分析工具 (80+个)              │
│  一次性逆向分析脚本：公共事件分析、通行性检测、             │
│  传送链分析、门扫描、剧情追踪、补丁验证                     │
│  共享模块：oneshot_data.rb（地图加载/通行性判定）          │
├─────────────────────────────────────────────────────────┤
│                   mod 脚本 (15个) — 核心                   │
│  位置：OneShot/mods/mod/Scripts/                          │
│  入口：mod.rb（preload 自动加载同目录全部 .rb）            │
│  基础设施：_config.rb / _patch_helper.rb / _status_log.rb │
│  功能模块：跳地图、跳过对话/事件/图片、快捷键、             │
│           碰撞调试、随时退出、标题控制、开发者设置           │
│  注入方式：全部通过 Module#prepend，不修改原版数据          │
├─────────────────────────────────────────────────────────┤
│                  xscripts/ 游戏脚本 (111个)                │
│  位置：从 xScripts.rxdata 解包的明文脚本                   │
│  标准 RGSS 脚本（~90个）+ OneShot 定制脚本（~21个）        │
│  分类：核心数据层 / 精灵渲染层 / 窗口UI层 /                │
│        事件解释器 / 场景管理层 / OneShot定制层 / 入口      │
├─────────────────────────────────────────────────────────┤
│                  引擎层（C++，不在本项目分析范围）           │
│  mkxp-z / ModShot：Graphics / Input / Audio / Oneshot 模块 │
└─────────────────────────────────────────────────────────┘
```

### 1.4 mod 注入机制详解

mod 脚本的注入是整个项目的核心设计，分为三层：

**第一层：preload 入口**
- `modshot.json` 的 `preloadScript` 配置指定 `mod.rb` 为预加载脚本
- `mod.rb` 在游戏脚本（`xScripts.rxdata`）执行之前运行
- 它将 Ruby 标准库路径加入 `$LOAD_PATH`，然后按文件名字典序 `load` 同目录下所有 `.rb`

**第二层：等待类定义（PatchHelper）**
- mod 脚本运行时，游戏类（`Interpreter`、`Scene_Map`、`Game_Event` 等）尚未定义
- `PatchHelper.install(class_name, methods: [...])` 使用 `TracePoint.trace(:end)` 异步监听
- 当目标类定义完成且指定方法就绪后，触发 block 执行 `k.prepend(PatchModule)`

**第三层：Module#prepend 补丁**
- 补丁模块通过 `prepend` 插入到目标类的祖先链最前端
- 补丁方法中调用 `super` 即可执行原版方法，实现"环绕通知"
- 多个补丁 prepend 到同一方法时，**后加载的在更外层**（先被调用）

### 1.5 代码统计

| 区域 | 文件数 | 总大小 | 性质 |
|------|--------|--------|------|
| mod 脚本 | 15 | ~75KB | 项目核心，需逐文件详解 |
| xscripts 游戏脚本 | 111 | ~622KB | 原版+定制，分类概述 |
| _analyze 分析工具 | 80+ | ~200KB | 一次性工具，分类概述 |
| 根目录工具脚本 | 5 | ~15KB | 工作流工具，逐个详解 |
| **合计** | **210+** | **~910KB** | |

---

## 二、mod 脚本详解（核心）


> 分析范围：`OneShot/mods/mod/Scripts/` 下 15 个 Ruby 文件 + `config.json`
> 分析方式：纯静态代码阅读，未运行游戏或 Ruby 解释器
> 生成时间：2026-09-07

---

### 目录与加载顺序

`mod.rb` 通过 `Dir.glob(File.join(script_dir, '*.rb')).sort.each { |path| load path }` 按文件名字典序自动加载，排除自身。实际加载顺序（`_` 开头 ASCII 码最小，最先加载）：

| 序号 | 文件名 | 说明 |
|------|--------|------|
| 1 | `_config.rb` | 配置加载（最先，因 `_c` < `_p` < `_s`） |
| 2 | `_patch_helper.rb` | PatchHelper 工具 |
| 3 | `_status_log.rb` | StatusLog 工具 |
| 4 | `debug_map.rb` | 碰撞调试图层 |
| 5 | `dev_settings.rb` | 开发者设置子界面 |
| 6 | `dev_settings_patch.rb` | 设置页补丁 |
| 7 | `event_twitch.rb` | 角色抽搐防护 |
| 8 | `jump_map.rb` | 跳地图界面 |
| 9 | `picture_skip.rb` | 图片过场跳过 |
| 10 | `quit_all_time.rb` | 随时退出 |
| 11 | `shortcut_keys.rb` | 全局快捷键 |
| 12 | `skip_dialogue.rb` | 跳过对话 |
| 13 | `skip_event.rb` | 事件跳过（三态） |
| 14 | `title_screen.rb` | 标题界面控制 |

> **确定内容**：`mod.rb` 自身不被 `load`（第31行 `next if File.absolute_path(path) == File.absolute_path(__FILE__)`），它是 preload 入口。
> **注意**：`_config.rb` 加载时 `_status_log.rb` 尚未加载，因此 `_config.rb` 不能使用 `StatusLog`，只能自包含写文件（第26-27行注释明确说明）。

---

### config.json 总览

```json
{
    "skip_pictures":  true,
    "quit_all_time":  true,
    "skip_dialogue":  true,
    "skip_choice":  true,
    "skip_uneasy":  true,
    "skip_event":  "block",
    "always_travel":  true,
    "always_settings":  true,
    "unshow_title":  true,
    "is_developer":  true
}
```

共 11 个配置键，全部为布尔值，仅 `skip_event` 为三态字符串（`off`/`block`/`fast`）。

---

### mod.rb

### 功能描述
preload 入口加载器。modshot 的 `preloadScript` 不支持通配符，只能指定具体文件。本文件作为唯一入口，完成两件事：
1. 将 Ruby 3.1.5 运行时标准库路径加入 `$LOAD_PATH`，使 `require 'json'` 等可用
2. 自动加载同目录下所有 `.rb` 文件（排除自身），按文件名排序

新增脚本只需放入此目录，无需修改 `modshot.json`。

### 关键类/模块/方法
无类/模块定义。顶层脚本逻辑。

### 实现机制
- **直接定义**：顶层执行，非 patch/hook
- `load path`（非 `require`）：每次加载完整执行文件，不做去重

### 依赖关系
- 依赖文件系统：`runtime/lib/ruby/3.1.0/` 和 `x64-mingw64/` 目录
- 无全局变量依赖（它是第一个执行的脚本）

### 与其他脚本的交互
- **被调用**：由 modshot 的 preloadScript 机制调用（`modshot.json` 中指定）
- **调用**：`load` 同目录下其余 14 个 `.rb` 文件
- 写加载日志到 `mods/mod/logs/preload_loaded.txt`

### 配置项
无。

### 关键代码
```ruby
# 第17-23行：添加运行时标准库路径
runtime_lib = File.absolute_path(File.join(script_dir, '..', '..', '..', '..', 'runtime', 'lib', 'ruby', '3.1.0'))
runtime_arch = File.join(runtime_lib, 'x64-mingw64')
if File.exist?(runtime_lib)
  $LOAD_PATH.unshift(runtime_lib)
  $LOAD_PATH.unshift(runtime_arch) if File.exist?(runtime_arch)
end

# 第29-38行：自动加载
Dir.glob(File.join(script_dir, '*.rb')).sort.each do |path|
  next if File.absolute_path(path) == File.absolute_path(__FILE__)
  begin
    load path
    loaded << File.basename(path)
  rescue => e
    errors << "#{File.basename(path)}: #{e.class}: #{e.message}"
  end
end
```

> **确定内容**：使用 `load` 而非 `require`，且每个文件独立 `begin/rescue`，单个文件加载失败不影响其他文件。
> **不确定**：`modshot.json` 中 preloadScript 的具体配置值未在本项目中查看，需进一步验证。

---

### _config.rb

### 功能描述
统一配置加载器。所有 mod 脚本共享同一个 `config.json`。本文件按文件名排序最先加载（`_` 开头 ASCII 码最小），读取配置后存入全局变量 `$mod_config`。其他脚本直接使用 `$mod_config["key"]`，不再各自读取文件。

### 关键类/模块/方法
无类/模块定义。顶层脚本逻辑。

### 实现机制
- **直接定义**：顶层执行
- `require 'json'`：依赖 mod.rb 添加的标准库路径

### 依赖关系
- 依赖 `json` 标准库（由 mod.rb 提前加入 `$LOAD_PATH`）
- 依赖文件：`mods/mod/config.json`
- 无全局变量前置依赖

### 与其他脚本的交互
- **被依赖**：所有读取 `$mod_config` 的脚本（picture_skip、quit_all_time、skip_dialogue、skip_event、shortcut_keys、title_screen、dev_settings）
- 写状态文件到 `mods/mod/logs/config_loaded.txt`（自包含，不使用 StatusLog）

### 配置项
读取整个 `config.json`，不针对特定 key。解析失败或文件不存在时 `$mod_config = {}`。

### 关键代码
```ruby
# 第14-23行：配置加载与容错
$mod_config = if File.exist?(config_path)
  begin
    parsed = JSON.parse(File.read(config_path))
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end
else
  {}
end
```

> **确定内容**：`_config.rb` 是加载链最前端，不能依赖 `StatusLog`（尚未加载），故第26-27行注释明确说明保持自包含。
> **确定内容**：`parsed.is_a?(Hash) ? parsed : {}` 确保 `$mod_config` 始终是 Hash，即使 JSON 顶层是数组也降级为空 Hash。

---

### _patch_helper.rb

### 功能描述
统一补丁安装工具（`PatchHelper`）。各 mod 脚本需要"等待某个游戏类定义完成后，用 `Module#prepend` 挂上补丁模块"。原实现每个文件重复一份 `TracePoint(:end)` 样板，本文件统一封装。

### 关键类/模块/方法

| 方法 | 签名 | 说明 |
|------|------|------|
| `PatchHelper.install` | `self.install(class_name, methods: [], &block)` | 等待指定类定义完成且指定方法就绪后执行 block |

### 实现机制
- **直接定义模块**：`module PatchHelper`
- **TracePoint(:end)**：异步监听类定义结束事件
- **Module#prepend**：由调用方在 block 中执行（如 `k.prepend(SomePatch)`）

### 依赖关系
- 无外部依赖（纯 Ruby 标准库 `TracePoint`）
- 无全局变量依赖

### 与其他脚本的交互
- **被调用**：debug_map、dev_settings_patch、event_twitch、picture_skip、quit_all_time、shortcut_keys、skip_dialogue、skip_event、title_screen 共 10 个文件使用
- 不调用其他脚本

### 配置项
无。

### 关键代码
```ruby
# 第25-38行：核心实现
def self.install(class_name, methods: [], &block)
  trace = TracePoint.trace(:end) do |tp|
    begin
      if tp.self.is_a?(Class) && tp.self.name == class_name &&
         methods.all? { |m| tp.self.method_defined?(m) }
        block.call(tp.self)
        trace.disable
      end
    rescue StandardError
      # 忽略异常, 继续监听
    end
  end
  trace
end
```

> **确定内容**：触发条件有三：(1) `tp.self` 是 Class；(2) 类名完全匹配 `class_name` 字符串；(3) `methods` 数组中所有方法都已 `method_defined?`。三者缺一不触发。
> **确定内容**：触发后执行 block 并 `trace.disable` 停止监听，即每个 `install` 只生效一次。
> **确定内容**：`rescue StandardError` 吞掉所有异常，包括 block 中的异常——这意味着补丁安装失败时游戏不会崩溃，但也不会有明显报错（仅靠 StatusLog 状态文件排查）。
> **不确定**：`TracePoint.trace(:end)` 在 mkxp-z 环境下的行为是否与标准 CRuby 完全一致，需进一步验证。

---

### _status_log.rb

### 功能描述
统一状态文件写入工具（`StatusLog`）。各 mod 脚本启动时都会往 `mods/mod/logs/` 写一份状态文件，记录开关值/配置/补丁方式/加载时间，方便排查。原实现每个文件重复一份 `Dir.mkdir + File.open` 样板，本文件统一封装。

### 关键类/模块/方法

| 方法 | 签名 | 说明 |
|------|------|------|
| `StatusLog.write` | `self.write(name, lines)` | 覆盖写入 `mods/mod/logs/<name>`，内容为 lines 逐行 |
| `StatusLog.append` | `self.append(name, msg)` | 追加一行到 `mods/mod/logs/<name>`，带时间戳 `[HH:MM:SS.mmm]` |

### 实现机制
- **直接定义模块**：`module StatusLog`
- 所有操作 `rescue StandardError` 静默失败，不影响游戏

### 依赖关系
- 无外部依赖
- 无全局变量依赖

### 与其他脚本的交互
- **被调用**：除 `_config.rb`（加载更早，无法使用）和 `mod.rb`（自包含）外，其余 12 个文件均在末尾调用 `StatusLog.write` 写状态文件
- `picture_skip.rb`、`skip_dialogue.rb`、`skip_event.rb` 在运行时调用 `StatusLog.append` 写 trace 日志到 `skip_trace.log`

### 配置项
无。

### 关键代码
```ruby
# 第19-29行：write
def self.write(name, lines)
  path = File.join(__dir__, '..', 'logs', name)
  begin
    dir = File.dirname(path)
    Dir.mkdir(dir) unless File.directory?(dir)
    File.open(path, 'w') do |f|
      lines.each { |l| f.puts(l) }
    end
  rescue StandardError
  end
end

# 第31-41行：append（带时间戳）
def self.append(name, msg)
  path = File.join(__dir__, '..', 'logs', name)
  begin
    dir = File.dirname(path)
    Dir.mkdir(dir) unless File.directory?(dir)
    File.open(path, 'a') do |f|
      f.puts("[#{Time.now.strftime('%H:%M:%S.%L')}] #{msg}")
    end
  rescue StandardError
  end
end
```

> **确定内容**：日志目录固定为 `Scripts/../logs/`，即 `mods/mod/logs/`。
> **确定内容**：`append` 使用 `File.open(path, 'a')` 追加模式，时间戳精确到毫秒。

---

### debug_map.rb

### 功能描述
调试显示：在地图上叠加半透明图层，显示碰撞（可通行性）和事件位置。
- **碰撞**：红色（不透明90）= 四方向全不可通行；橙色（不透明70）= 部分方向不可通行；透明 = 可通行
- **事件**：蓝色半透明块 + 事件 ID，同格多事件以 `|` 分隔
- 快捷键：**Ctrl+G** 切换显示/隐藏（需 `is_developer: true`）
- 图层 viewport z=250，位于光照层（z=200）之上、图片层（z=500）之下

### 关键类/模块/方法

| 类/模块 | 方法 | 签名 | 说明 |
|---------|------|------|------|
| `DebugMapOverlay` | `initialize` | `initialize` | 创建 viewport/sprite/bitmap |
| | `visible?` | `visible?` | 返回 `@visible` |
| | `toggle` | `toggle` | 切换显示/隐藏，显示时重绘 |
| | `update` | `update` | 每帧检测镜头移动，变化时重绘 |
| | `redraw` (private) | `redraw` | 重绘当前可视区域的碰撞+事件 |
| `DebugMapPatch` | `update` | `update` | Scene_Map 补丁：Ctrl+G 切换 + 每帧更新 |
| | `debug_map_overlay` (private) | `debug_map_overlay` | 惰性创建 `$debug_map_overlay` |
| | `debug_toggle_triggered?` (private) | `debug_toggle_triggered?` | Ctrl+G 按键检测（仅开发者模式） |

### 实现机制
- **直接定义类**：`class DebugMapOverlay`（自定义 UI 类）
- **Module#prepend**：`DebugMapPatch` 通过 `PatchHelper.install('Scene_Map', methods: [:update])`  prepend 到 `Scene_Map`
- **惰性创建**：`$debug_map_overlay` 初始为 `nil`，首次 Ctrl+G 时才实例化（preload 阶段 Graphics 未初始化）

### 依赖关系
- 依赖全局变量：`$dev_settings_enabled`（由 dev_settings.rb 设置）、`$debug_map_overlay`
- 依赖游戏全局：`$game_map`、`$game_system`、`$data_system`
- 依赖 mkxp-z 扩展：`Input.pressex?`、`Input.triggerex?`
- 依赖 RPG Maker 类：`Viewport`、`Sprite`、`Bitmap`、`Color`
- 依赖工具：`PatchHelper`、`StatusLog`

### 与其他脚本的交互
- **被调用**：无直接调用，通过 Scene_Map#update 的 prepend 链自动生效
- **调用**：`PatchHelper.install`、`StatusLog.write`
- **修改原版行为**：`Scene_Map#update`——在 super 前插入 Ctrl+G 检测和 overlay 更新
- 与 `quit_all_time.rb`、`shortcut_keys.rb`、`skip_event.rb` 共享 `Scene_Map#update` 的 prepend 链（见依赖关系图）

### 配置项
间接依赖 `config.json` 的 `is_developer`（通过 `$dev_settings_enabled`）。无自身直接读取的配置 key。

### 关键代码
```ruby
# 第98-103行：碰撞判定（四向不可通行数）
blocked = [2, 4, 6, 8].count { |d| !map.passable?(x, y, d) }
if blocked == 4
  bmp.fill_rect(px, py, TILE, TILE, Color.new(255, 0, 0, 90))
elsif blocked > 0
  bmp.fill_rect(px, py, TILE, TILE, Color.new(255, 165, 0, 70))
end

# 第144-151行：Ctrl+G 检测
def debug_toggle_triggered?
  return false unless $dev_settings_enabled
  return false unless Input.respond_to?(:triggerex?)
  return false unless Input.respond_to?(:pressex?)
  (Input.pressex?(:LCTRL) || Input.pressex?(:RCTRL)) && Input.triggerex?(:G)
rescue StandardError
  false
end
```

> **确定内容**：`redraw` 仅在镜头移动（`map.display_x/display_y` 变化）时触发，通过 `@last_redraw_key` 缓存比较，避免每帧重绘。
> **确定内容**：事件显示过滤掉 `@erased` 的事件（第86行 `next if ev.instance_variable_get(:@erased)`）。
> **确定内容**：`DebugMapPatch#update` 的异常被 `rescue StandardError` 吞掉，调试层异常不影响主流程。
> **不确定**：`map.passable?` 在 OneShot 定制版本中是否与标准 RPG Maker XP 行为一致，需进一步验证。

---

### dev_settings.rb

### 功能描述
开发者设置子界面（`Window_DevSettings`）。进入后列出 `config.json` 中的所有布尔开关，可在游戏内实时切换并写回 `config.json`，同时同步对应 mod 的全局开关变量（实现不重启即生效）。

入口来源：
1. `dev_settings_patch.rb`：`Window_Settings` 最下方追加"开发者设置"栏
2. `shortcut_keys.rb`：Ctrl+D 快捷键直接打开

功能条目（`EXTRA_ACTIONS`）：非布尔开关的可执行动作，如 Jump Map。
三态枚举键（`ENUM_KEYS`）：`skip_event` 由布尔升级为 `off|block|fast` 三态。

### 关键类/模块/方法

| 类/模块 | 方法 | 签名 | 说明 |
|---------|------|------|------|
| `Window_DevSettings` | `initialize` | `initialize` | 创建 viewport/bg/title/flash_sprite，设置 `$dev_settings_instance = self` |
| | `display_items` | `display_items` | 返回 `@keys + @enum_keys + @extra_items` |
| | `open` | `open` | 重载配置、重建列表 sprite、显示界面 |
| | `reload_config` | `reload_config` | 从 `config.json` 重新读取，分离布尔键和枚举键 |
| | `redraw` | `redraw(spr, i)` | 重绘单个条目（键名 + 值/箭头） |
| | `redraw_all` | `redraw_all` | 重绘所有条目 |
| | `update` | `update` | 光标动画、上下移动、确认切换/执行、取消关闭 |
| | `run_action` | `run_action(display_name)` | 执行功能动作（如 `:jump_map` → `open_jump_map`） |
| | `flash` | `flash(msg)` | 短暂显示动作结果提示（120帧） |
| | `toggle` | `toggle(i)` | 切换开关（布尔取反/三态循环），同步全局变量，写回 config |
| | `open_jump_map` | `open_jump_map` | 打开跳地图子界面，注入跳转成功回调 |
| | `dispose` | `dispose` | 释放所有 sprite/viewport |
| | `apply_global` (private) | `apply_global(key, val)` | 白名单同步 mod 全局开关变量 |
| | `save_config` (private) | `save_config` | 写回 `config.json`，已知键固定顺序 |

常量：
- `EXTRA_ACTIONS = [[:jump_map, 'Jump Map']]`
- `ENUM_KEYS = { 'skip_event' => %w[off block fast] }`
- `CONFIG_PATH = File.join(__dir__, '..', 'config.json')`

### 实现机制
- **直接定义类**：`class Window_DevSettings`（自定义 UI 类，非继承自 RPG Maker 的 Window 基类）
- 手动管理 `Sprite`/`Bitmap`/`Viewport`，模拟 Window_Settings 的视觉风格
- `$dev_settings_instance = self`：全局实例引用，供 `shortcut_keys.rb` 和 `jump_map.rb` 访问

### 依赖关系
- 依赖全局变量：`$mod_config`、`$dev_settings_enabled`、`$dev_settings_instance`
- 依赖游戏全局：`$game_system`、`$data_system`
- 依赖 RPG Maker 类：`Viewport`、`Sprite`、`Bitmap`、`Color`
- 依赖 `tr()` 方法（OneShot 国际化函数）
- 依赖 `Window_JumpMap`（由 jump_map.rb 定义，在 `open_jump_map` 中使用）
- 依赖工具：`StatusLog`
- `require 'json'`

### 与其他脚本的交互
- **被调用**：
  - `dev_settings_patch.rb`：`Window_DevSettings.new` 创建实例，`.open` 打开
  - `shortcut_keys.rb`：`$dev_settings_instance` 访问，`.open` 打开，`.open_jump_map` 打开跳地图
- **调用**：
  - `jump_map.rb`：`Window_JumpMap.new`、`@jump_map.open`
  - `StatusLog.write`
- **修改原版行为**：不直接修改原版类，但通过 `apply_global` 修改全局开关变量间接影响所有 mod 的行为
- `apply_global` 白名单覆盖 10 个配置键：`skip_pictures`、`quit_all_time`、`skip_dialogue`、`skip_choice`、`skip_uneasy`、`skip_event`、`always_settings`、`always_travel`、`unshow_title`、`is_developer`

### 配置项
直接读取 `config.json`（`reload_config` 中 `JSON.parse(File.read(CONFIG_PATH))`），但初始值来自 `$mod_config`。

| 配置 key | 默认值 | 用途 |
|----------|--------|------|
| `is_developer` | `false` | 控制设置页是否显示"开发者设置"栏 |

其余配置键由 `reload_config` 动态发现（所有布尔键 + `ENUM_KEYS` 中的键），不硬编码。

### 关键代码
```ruby
# 第297-310行：apply_global 白名单同步
def apply_global(key, val)
  case key
  when 'skip_pictures'   then $is_skip_picture = val
  when 'quit_all_time'   then $quit_all_time_enabled = val
  when 'skip_dialogue'   then $skip_dialogue_enabled = val
  when 'skip_choice'     then $skip_choice_enabled = val
  when 'skip_uneasy'     then $skip_uneasy_enabled = val
  when 'skip_event'      then $skip_event_mode = val
  when 'always_settings' then $always_settings_enabled = val
  when 'always_travel'   then $always_travel_enabled = val
  when 'unshow_title'    then $unshow_title_enabled = val
  when 'is_developer'    then $dev_settings_enabled = val
  end
end

# 第313-323行：save_config 固定顺序写回
def save_config
  $mod_config ||= @config
  ordered = {}
  %w[skip_pictures quit_all_time skip_dialogue skip_choice skip_uneasy skip_event always_travel always_settings unshow_title is_developer].each do |k|
    ordered[k] = @config[k] if @config.key?(k)
  end
  @config.each do |k, v|
    ordered[k] = v unless ordered.key?(k)
  end
  File.write(CONFIG_PATH, JSON.pretty_generate(ordered) + "\n")
end
```

> **确定内容**：`open_jump_map` 不隐藏自身（`visible=false`），因为 `WindowSettingsDevPatch#update` 只在 `@dev_settings.visible` 为 true 时才调用其 update；靠 JumpMap 更高的 viewport z（10000）盖住本界面（第271-273行注释）。
> **确定内容**：`toggle` 中三态枚举的循环逻辑：`vals[(idx || -1) + 1] || vals[0]`，即当前值找不到时从第一个开始。
> **确定内容**：`@flash_timer = 120` 对应约 2 秒（60fps）。
> **不确定**：`tr()` 函数的具体实现位置（OneShot 国际化模块），未在本项目中验证。

---

### dev_settings_patch.rb

### 功能描述
给 `Window_Settings` 打补丁：
1. `open` 时在设置列表最下方追加"开发者设置"栏
2. `update` 时检测到在该栏上按确认键 → 打开 `Window_DevSettings` 子界面
3. `dispose` 时清理子界面实例，防止复用已 dispose 的对象

同时修复了原版 `Window_Settings#open` 的一个 bug：原版每次 open 新建 sprite 到 `@data_sprites` 且不清旧，反复进出设置页会残留堆积。本补丁在调用 super 前先 dispose 清空。

### 关键类/模块/方法

| 模块 | 方法 | 签名 | 说明 |
|------|------|------|------|
| `WindowSettingsDevPatch` | `open` | `open` | 清旧 sprite → super → 追加"开发者设置"栏 |
| | `update` | `update` | 子界面打开时接管输入 → super → 检测确认键打开子界面 |
| | `dispose` | `dispose` | 清理 `@dev_settings` 实例 → super |

### 实现机制
- **Module#prepend**：通过 `PatchHelper.install('Window_Settings', methods: [:open, :update])` prepend 到 `Window_Settings`
- 注意：`methods: [:open, :update]` 只检查这两个方法就绪，但补丁也覆盖了 `dispose`（`dispose` 是 `Window_Settings` 继承来的方法，`method_defined?` 在类上也返回 true）

### 依赖关系
- 依赖全局变量：`$dev_settings_enabled`
- 依赖 `Window_DevSettings` 类（由 dev_settings.rb 定义）
- 依赖 `Window_Settings` 的常量：`ITEM_SPACING`、`MARGIN`、`TITLE_MARGIN`、`TITLE_TOP_MARGIN`
- 依赖 `Language.register_text_sprite`（OneShot 国际化注册）
- 依赖 `redraw_setting`（Window_Settings 实例方法）
- 依赖工具：`PatchHelper`、`StatusLog`

### 与其他脚本的交互
- **被调用**：无直接调用，通过 `Window_Settings` 的方法链自动生效
- **调用**：
  - `dev_settings.rb`：`Window_DevSettings.new`、`@dev_settings.open`、`@dev_settings.parent_settings =`、`@dev_settings.on_closed =`
  - `PatchHelper.install`、`StatusLog.write`
- **修改原版行为**：
  - `Window_Settings#open`：追加"开发者设置"栏到 `@data` 和 `@data_sprites`
  - `Window_Settings#update`：在最后一栏按确认键时打开子界面；子界面可见时接管输入并 `return`（不执行 super）
  - `Window_Settings#dispose`：清理子界面实例

### 配置项
间接依赖 `config.json` 的 `is_developer`（通过 `$dev_settings_enabled`）。

### 关键代码
```ruby
# 第20-42行：open 补丁（含原版 bug 修复）
def open
  if @data_sprites
    @data_sprites.each { |spr| spr.dispose if spr }
    @data_sprites = []
  end
  super
  if $dev_settings_enabled
    @data << tr('Developer Settings')
    i = @data.size - 1
    spr = Sprite.new(@viewport)
    spr.bitmap = Bitmap.new(400, self.class::ITEM_SPACING)
    spr.x = self.class::MARGIN
    spr.y = self.class::TITLE_MARGIN + self.class::TITLE_TOP_MARGIN + self.class::ITEM_SPACING * i
    spr.opacity = 0
    Language.register_text_sprite(self.class.name + "_option_#{i}", spr)
    redraw_setting(spr, i)
    @data_sprites << spr
  end
end

# 第44-61行：update 补丁
def update
  if @dev_settings && @dev_settings.visible
    @dev_settings.update
    return
  end
  super
  if $dev_settings_enabled && @visible && !@fade_in && !@fade_out &&
     @data && @index == @data.size - 1 && Input.trigger?(Input::ACTION)
    @dev_settings ||= Window_DevSettings.new
    @dev_settings.parent_settings = self
    @dev_settings.on_closed = nil
    @dev_settings.open
  end
end
```

> **确定内容**：经设置菜单打开时 `@dev_settings.on_closed = nil`，因为按 CANCEL 只应关开发者设置回到设置窗口，不应误关设置窗口本身（与 shortcut_keys 的快捷键打开方式区分）。
> **确定内容**：`@index == @data.size - 1` 检测光标是否在最后一栏（即"开发者设置"栏），因为该栏总是追加在最末尾。
> **不确定**：`Window_Settings#dispose` 是否在 `methods: [:open, :update]` 检查时已就绪——`dispose` 可能继承自父类，`method_defined?` 在 Ruby 中对继承方法也返回 true，所以应该没问题，但需验证。

---

### event_twitch.rb

### 功能描述
"角色抽搐"防护（事件反复触发抑制）。

**现象**：跳关后，部分"玩家接触触发 + 推玩家"的事件（如楼梯/门槛）会反复触发：玩家站在触发格上，事件 move route 试图把玩家推开，但推的方向不可达（墙/边界/跳关后状态错位）→ 移动失败 → 玩家没被推走 → 还在触发格上 → 事件又触发 → 又推（失败）→ 每帧反复 → 角色抽搐，且玩家被"挡住"进不去。

**修复**：对含"作用于玩家的 move route"（命令码 209/212，目标=-1）的事件做触发抑制——若玩家位置与上次触发时相同（说明事件没把玩家推走，移动失败），抑制后续触发，直到玩家主动移动（位置变化）后才解除。

### 关键类/模块/方法

| 模块 | 方法 | 签名 | 说明 |
|------|------|------|------|
| `EventTwitchGuardPatch` | `start` | `start` | 懒检测事件是否含推玩家 move route；位置相同则抑制，否则记录位置并 super |
| | `update` | `update` | 玩家主动移动（位置变化）→ 解除抑制 → super |

### 实现机制
- **Module#prepend**：通过 `PatchHelper.install('Game_Event', methods: [:start, :update])` prepend 到 `Game_Event`
- **懒检测**：`@twitch_guard_checked` 标记，首次 `start` 时扫描 `@list` 检测是否含 209/212 目标=-1 的命令

### 依赖关系
- 依赖游戏全局：`$game_player`（`.x`、`.y`）
- 依赖 `Game_Event` 的 `@list`（事件命令列表）、`@erased` 等实例变量
- 依赖工具：`PatchHelper`、`StatusLog`

### 与其他脚本的交互
- **被调用**：无直接调用，通过 `Game_Event#start/update` 的 prepend 链自动生效
- **调用**：`PatchHelper.install`、`StatusLog.write`
- **修改原版行为**：
  - `Game_Event#start`：对含推玩家 move route 的事件，若玩家位置未变则 `return`（不触发）
  - `Game_Event#update`：检测玩家位置变化，解除抑制
- 与 `skip_event.rb` 共享 `Game_Event` 的 prepend 链（`SkipEventAutoRunPatch` 和 `SkipEventParallelPatch` 也 prepend 到 Game_Event）

### 配置项
无。该功能无条件生效（不依赖 config.json 开关）。

### 关键代码
```ruby
# 第20-50行：start 补丁（核心抑制逻辑）
def start
  unless defined?(@twitch_guard_checked)
    @twitch_guard_checked = true
    @twitch_guard_push = false
    if @list
      @list.each do |cmd|
        if cmd && [209, 212].include?(cmd.code)
          params = begin
            cmd.parameters
          rescue StandardError
            []
          end
          if params.is_a?(Array) && params[0].to_i == -1
            @twitch_guard_push = true
            break
          end
        end
      end
    end
  end
  if @twitch_guard_push
    pos = [$game_player.x, $game_player.y]
    if @twitch_guard_pos == pos && @twitch_guard_pos
      return
    end
    @twitch_guard_pos = pos
  end
  super
end
```

> **确定内容**：命令码 209 = "Set Move Route"（设置移动路线），212 = "Move Event"（移动事件）？需进一步验证具体命令码含义。代码注释称 209/212 为"作用于玩家的 move route"，`parameters[0].to_i == -1` 表示目标为玩家（-1 在 RPG Maker 中通常表示玩家）。
> **确定内容**：`@twitch_guard_pos == pos && @twitch_guard_pos` 中的 `&& @twitch_guard_pos` 是为了排除 `nil` 情况（首次触发时 `@twitch_guard_pos` 为 nil，不抑制）。
> **确定内容**：`update` 中 `cur != @twitch_guard_pos` 时置 `nil` 解除抑制，而非直接更新为新位置——这样下次 `start` 时会重新记录位置。
> **不确定**：命令码 209/212 在 OneShot 定制版本中的精确含义，需对照 RPG Maker XP 命令码表验证。

---

### jump_map.rb

### 功能描述
"Jump Map" 跳地图界面（`Window_JumpMap`）。在开发者设置中作为 "Jump Map" 栏进入，也可通过 Ctrl+J 快捷键直接打开。列出可跳地图（过滤内部/debug/测试图），选中即模仿原版 FastTravel 的传送链做黑屏转场跳转。书页式列表，每页 10 条，左右键翻页，上下键页内选择。

跳转成功后进入自由浏览模式（`$jump_map_free_mode = true`），该模式下 `skip_event.rb` 的事件级阻止规则生效，演出事件整体不启动，玩家自由行动，模式持续到游戏重启。

### 关键类/模块/方法

| 类/模块 | 方法 | 签名 | 说明 |
|---------|------|------|------|
| `Window_JumpMap` | `initialize` | `initialize` | 创建 viewport/bg/title/page_sprite，viewport z=10000 |
| | `open` | `open` | 加载地图列表、定位当前地图、淡入显示 |
| | `update` | `update` | 淡入→选择→淡出→设置传送 flags 的状态机 |
| | `dispose` | `dispose` | 释放所有 sprite/viewport |
| | `page_count` (private) | `page_count` | 总页数 |
| | `mapinfos` (private) | `mapinfos` | 惰性加载 `Data/MapInfos.rxdata` |
| | `ancestor_blacklisted?` (private) | `ancestor_blacklisted?(id)` | 祖先链是否含内部图标记 |
| | `locate_current_map` (private) | `locate_current_map` | 当前地图在可跳列表中的索引 |
| | `load_maps` (private) | `load_maps` | 从 `jump_points.json` 加载并过滤可跳地图（缓存） |
| | `refresh_list` (private) | `refresh_list` | 重建当前页列表 sprite + 更新页码 |

常量：
- `JUMP_MAP_FREEZE_AUTORUN = true`
- `JUMP_POINTS_PATH = File.join(__dir__, '..', 'jump_points.json')`
- `JUMP_MAP_FILTER = /IGNORE|DEBUG|INTERNAL|UNUSED|\bTEST\b|^INIT\b|TELEPORT|DEMO|PROTOWALK|PSHOT|LANGUAGE\s?DEBUG|LANG\s?DEBUG/i`
- `JUMP_MAP_NAME_PATTERN = /^[TCS]\d+$/i`
- `JUMP_MAP_PARENT_FILTER = /IGNORE|DEBUG|UNUSED|INTERNAL|\bTEST\b|^INIT\b|TELEPORT/i`
- `JUMP_MAP_PER_PAGE = 10`

### 实现机制
- **直接定义类**：`class Window_JumpMap`（自定义 UI 类）
- 不使用 PatchHelper（不修改原版类），纯新增类
- 背景全程不透明黑色，淡入淡出只作用于文字层（避免跳转时露出下层设置菜单）

### 依赖关系
- 依赖全局变量：`$jump_map_free_mode`
- 依赖游戏全局：`$game_map`、`$game_temp`、`$game_system`、`$game_screen`
- 依赖文件：`mods/mod/jump_points.json`（预扫描生成的落点数据）、`Data/MapInfos.rxdata`
- 依赖 `load_data`（RPG Maker 数据加载函数）
- 依赖 `Graphics.freeze`、`Audio.bgm_stop`
- 依赖 `tr()` 国际化函数
- 依赖 RPG Maker 类：`Viewport`、`Sprite`、`Bitmap`、`Color`
- 依赖工具：`StatusLog`
- `require 'json'`

### 与其他脚本的交互
- **被调用**：
  - `dev_settings.rb`：`Window_JumpMap.new`、`@jump_map.open`、`@jump_map.on_transfer =`、`@jump_map.visible =`
  - `shortcut_keys.rb`：`$dev_settings_instance.open_jump_map`（间接调用）
- **调用**：
  - `skip_event.rb`：设置 `$jump_map_free_mode = true`（skip_event 读取此变量生效事件阻止规则）
  - `StatusLog.write`
- **修改原版行为**：不直接修改原版类，但通过设置 `$game_temp.player_transferring` 等标志触发原版 `Scene_Map#update` 的传送逻辑
- 跳转成功回调 `@on_transfer` 由外层（dev_settings）注入，用于关闭设置窗口

### 配置项
间接依赖 `config.json` 的 `is_developer`（通过开发者设置入口）。无自身直接读取的配置 key。

### 关键代码
```ruby
# 第155-177行：淡出结束后设置传送 flags（核心跳转逻辑）
if @transfer_player
  if JUMP_MAP_FREEZE_AUTORUN
    $jump_map_free_mode = true
    if $game_system && $game_system.map_interpreter
      $game_system.map_interpreter.clear
      $game_system.map_interpreter.instance_variable_set(:@list, nil)
    end
  end
  # 模仿原版 FastTravel 的传送链
  $game_temp.player_transferring = true
  $game_temp.player_new_map_id = @transfer_player[:id]
  $game_temp.player_new_x = @transfer_player[:x]
  $game_temp.player_new_y = @transfer_player[:y]
  $game_temp.player_new_direction = @transfer_player[:dir]
  Graphics.freeze
  $game_temp.transition_processing = true
  $game_temp.transition_name = "black"
  @on_transfer.call if @on_transfer
  @transfer_player = nil
end

# 第298-322行：load_maps 过滤逻辑
def load_maps
  @maps = @maps_cache
  return if @maps
  @maps = []
  data = begin
    JSON.parse(File.read(JUMP_POINTS_PATH))
  rescue StandardError
    {}
  end
  data.each do |id, m|
    next unless m.is_a?(Hash)
    x = m['x'].to_i
    y = m['y'].to_i
    next if x < 0 || y < 0            # 无落点
    name = m['name'].to_s
    next if name =~ JUMP_MAP_FILTER               # 名字黑名单
    next if name =~ JUMP_MAP_NAME_PATTERN         # 纯代号测试图
    next if ancestor_blacklisted?(id.to_i)        # 祖先链内部图
    @maps << { id: id.to_i, x: x, y: y, dir: m['dir'].to_i, name: name }
  end
  @maps.sort_by! { |mm| mm[:id] }
  @maps_cache = @maps
end
```

> **确定内容**：`JUMP_MAP_FREEZE_AUTORUN = true` 是硬编码常量，跳转后无条件进入自由浏览模式。
> **确定内容**：`@maps_cache` 缓存机制——`jump_points.json` 运行期间不变，首次加载后复用，避免每次 Ctrl+J 都重复读文件+过滤+排序。
> **确定内容**：三层过滤：(1) 名字黑名单正则；(2) 纯代号测试图（T1/C1/S1...）；(3) 祖先链黑名单（父级地图名含内部标记）。
> **确定内容**：`locate_current_map` 定位当前所在地图，若在可跳列表中则跳到对应页并选中，否则回退到第 0 页首项。
> **不确定**：`jump_points.json` 的生成方式——注释称"预扫描生成"，但生成脚本未在本项目中找到，需进一步验证。

---

### picture_skip.rb

### 功能描述
图片过场跳过 mod。遇到 `ShowPicture`（命令码 231）时进入"跳过模式"，在跳过模式中跳过等待、图片操作、转场、BGM 等演出命令，遇到对话（101）或列表末尾时退出跳过模式。教学事件中的循环（112 Loop + 105 按键输入）直接跳到循环结束，整个教学自动跳过。

### 关键类/模块/方法

| 模块 | 方法 | 签名 | 说明 |
|------|------|------|------|
| `PictureSkipPatch` | `_trace_log` | `_trace_log(msg)` | 写 trace 到 `skip_trace.log` |
| | `clear` | `clear` | 重置 `@pic_skip_mode = false` → super |
| | `execute_command` | `execute_command` | 核心：231 进入跳过模式，跳过模式中按命令码处理 |

常量：
- `SKIP_CODES = [106, 207, 208, 210, 211, 212, 213, 214, 215, 221, 222, 223, 224, 225, 232, 233, 234, 235, 236, 241].freeze`

### 实现机制
- **Module#prepend**：通过 `PatchHelper.install('Interpreter', methods: [:execute_command])` prepend 到 `Interpreter`
- 状态机：`@pic_skip_mode` 实例变量标记是否处于跳过模式
- 关键设计：不手动 `@index += 1`，靠 `Interpreter#update` 在 `execute_command` 返回后统一 `@index += 1`

### 依赖关系
- 依赖全局变量：`$is_skip_picture`、`$mod_config`
- 依赖 `Interpreter` 的实例变量：`@index`、`@list`、`@event_id`
- 依赖工具：`PatchHelper`、`StatusLog`
- `require 'json'`

### 与其他脚本的交互
- **被调用**：无直接调用，通过 `Interpreter#execute_command` 的 prepend 链自动生效
- **调用**：`PatchHelper.install`、`StatusLog.write`、`StatusLog.append`
- **修改原版行为**：
  - `Interpreter#execute_command`：231 进入跳过模式并 `return true`（跳过 ShowPicture 本身）；跳过模式中 SKIP_CODES 的命令 `return true`（跳过执行）；112 Loop 跳到循环结束；101 对话退出跳过模式
  - `Interpreter#clear`：重置 `@pic_skip_mode`
- 与 `skip_dialogue.rb`、`skip_event.rb` 共享 `Interpreter#execute_command` 的 prepend 链
- **跨模块交互**：`skip_dialogue.rb` 在跳过 101 时会清除 `@pic_skip_mode`（因为 picture_skip 看不到被吞掉的 101），见 skip_dialogue 第89-92行

### 配置项

| 配置 key | 默认值 | 全局变量 | 用途 |
|----------|--------|----------|------|
| `skip_pictures` | `true` | `$is_skip_picture` | 开启/关闭图片过场跳过 |

### 关键代码
```ruby
# 第33-37行：SKIP_CODES（注意 209 被排除——209 是删除图片，必须执行）
SKIP_CODES = [106,
              207, 208, 210, 211, 212, 213, 214, 215,
              221, 222, 223, 224, 225,
              232, 233, 234, 235, 236,
              241].freeze

# 第48-105行：execute_command 核心逻辑
def execute_command
  if $is_skip_picture
    # 遇到 ShowPicture(231) 进入跳过模式
    if @index < @list.size && @list[@index] && @list[@index].code == 231
      @pic_skip_mode = true
      return true  # Interpreter#update 末尾统一 @index += 1 会跳过 231
    end

    if @pic_skip_mode
      if @index >= @list.size - 1
        @pic_skip_mode = false
        command_end
        return true
      end
      code = @list[@index].code
      if code == 101
        @pic_skip_mode = false  # 遇到对话退出跳过模式
      elsif code == 112
        # 跳过整个循环体（教学事件）
        indent = @list[@index].indent
        j = @index + 1
        while j < @list.size
          if @list[j].code == 413 && @list[j].indent <= indent
            @index = j
            break
          end
          j += 1
        end
        return true
      elsif SKIP_CODES.include?(code)
        return true  # 跳过，靠 update 的 +1 前进
      end
    end
  end
  super
end
```

> **确定内容**：命令码 105（按键输入）不在 SKIP_CODES 中——注释明确说明跳过会吞掉按键捕获，导致教学循环死循环黑屏。教学循环通过 112 Loop 整体跳过来处理。
> **确定内容**：命令码 209（删除图片）不在 SKIP_CODES 中——跳过会导致图片永不消失、残留覆盖屏幕。
> **确定内容**：`return true` 表示命令执行成功，`Interpreter#update` 会 `@index += 1` 前进到下一条；不手动 `@index += 1` 避免叠加多跳。
> **确定内容**：112 Loop 跳过时 `@index = j` 停在 413（Loop End）上，靠 update 的 +1 跳到循环后第一条。
> **不确定**：命令码 231 是否确为 ShowPicture，需对照 RPG Maker XP 命令码表验证。

---

### quit_all_time.rb

### 功能描述
随时退出 mod。取消 OneShot 中"部分情况下无法退出/打开菜单"的限制。原始游戏在图片过场等场景中会设置 `menu_disabled=true` 或事件运行中禁止打开菜单。本 mod 忽略这两个限制，让玩家随时按菜单键打开菜单退出。

同时覆盖 `Oneshot.allow_exit`（引擎 C 方法，控制窗口右上角 X 按钮），开启时始终传入 `true` 允许随时关闭。

### 关键类/模块/方法

| 模块/方法 | 签名 | 说明 |
|-----------|------|------|
| `QuitAllTimePatch#update` | `update` | Scene_Map 补丁：处理退出键 + 菜单键 |
| `Oneshot.allow_exit` (覆盖) | `allow_exit(arg)` | 开启时始终 `qat_orig_allow_exit(true)` |
| `Input.quit?` (临时覆盖) | `quit?` | 在 super 调用期间临时返回 false，阻止原版限制检查 |

### 实现机制
- **Module#prepend**：`QuitAllTimePatch` 通过 `PatchHelper.install('Scene_Map', methods: [:update])` prepend 到 `Scene_Map`
- **alias + define_singleton_method**：覆盖 `Oneshot.allow_exit`（`alias_method :qat_orig_allow_exit, :allow_exit` 然后 `define_singleton_method`）
- **临时 alias**：在 `update` 中检测到 `Input.quit?` 时，临时覆盖 `Input.quit?` 返回 false，调用 super 后在 `ensure` 中恢复

### 依赖关系
- 依赖全局变量：`$quit_all_time_enabled`、`$mod_config`
- 依赖游戏全局：`$game_temp`（`common_event_id`、`message_window_showing`、`menu_calling`、`item_menu_calling`）、`$game_system`（`menu_disabled`）
- 依赖 `Scene_Map` 的实例变量：`@ed_message`、`@doc_message`、`@desktop_message`、`@credits_message`、`@fast_travel`、`@window_settings`、`@menu`
- 依赖 `Oneshot.allow_exit`（引擎 C 方法）
- 依赖 `Input.quit?`、`Input.trigger?(Input::MENU)`
- 依赖工具：`PatchHelper`、`StatusLog`
- `require 'json'`

### 与其他脚本的交互
- **被调用**：无直接调用，通过 `Scene_Map#update` 的 prepend 链自动生效
- **调用**：`PatchHelper.install`、`StatusLog.write`
- **修改原版行为**：
  - `Scene_Map#update`：忽略 `$game_system.menu_disabled` 和 `map_interpreter.running?` 限制，允许随时打开菜单；检测到退出键时设置公共事件 35（保存并退出）并临时覆盖 `Input.quit?`
  - `Oneshot.allow_exit`：开启时始终允许窗口关闭
  - `Input.quit?`：临时覆盖（仅在 super 调用期间）
- 与 `debug_map.rb`、`shortcut_keys.rb`、`skip_event.rb` 共享 `Scene_Map#update` 的 prepend 链

### 配置项

| 配置 key | 默认值 | 全局变量 | 用途 |
|----------|--------|----------|------|
| `quit_all_time` | `true` | `$quit_all_time_enabled` | 开启/关闭随时退出 |

### 关键代码
```ruby
# 第30-39行：覆盖 Oneshot.allow_exit
if defined?(Oneshot) && Oneshot.respond_to?(:allow_exit)
  Oneshot.singleton_class.alias_method(:qat_orig_allow_exit, :allow_exit)
  Oneshot.define_singleton_method(:allow_exit) do |arg|
    if $quit_all_time_enabled
      Oneshot.qat_orig_allow_exit(true)
    else
      Oneshot.qat_orig_allow_exit(arg)
    end
  end
end

# 第42-82行：QuitAllTimePatch#update
module QuitAllTimePatch
  def update
    if $quit_all_time_enabled
      if Input.quit?
        $game_temp.common_event_id = 35
        begin
          Input.singleton_class.alias_method(:qat_orig_quit?, :quit?)
          Input.define_singleton_method(:quit?) { false }
          return super
        ensure
          Input.singleton_class.alias_method(:quit?, :qat_orig_quit?)
        end
      end

      message_showing = $game_temp.message_window_showing ||
                        @ed_message.visible || @doc_message.visible ||
                        @desktop_message.visible || @credits_message.visible

      unless message_showing ||
             @fast_travel.visible || @window_settings.visible ||
             $game_temp.menu_calling == true ||
             $game_temp.item_menu_calling == true
        if !@menu.visible && Input.trigger?(Input::MENU)
          $game_temp.menu_calling = true
          $game_temp.menu_beep = true
        end
      end
    end
    super
  end
end
```

> **确定内容**：公共事件 35 是"保存并退出"（注释说明）。
> **确定内容**：临时覆盖 `Input.quit?` 的目的是阻止 super 中的限制检查（原版会弹出 "You cannot perform this action during cutscenes."），同时让 super 处理公共事件 35。
> **确定内容**：`ensure` 块保证即使 super 抛异常也会恢复 `Input.quit?`。
> **确定内容**：保留的限制包括：消息窗口显示中、快速旅行界面、设置窗口、菜单调用中、物品菜单调用中——这些场景下不拦截菜单键。
> **不确定**：`@ed_message`、`@doc_message`、`@desktop_message`、`@credits_message` 是否都是 `Scene_Map` 的实例变量，需对照原版 Scene_Map 代码验证。

---

### shortcut_keys.rb

### 功能描述
全局快捷键（Ctrl+D / Ctrl+J）。
- **Ctrl+D** → 打开开发者设置（需 `is_developer: true`）
- **Ctrl+J** → 打开跳地图

基于 mkxp-z 扩展 `Input.pressex?/triggerex?`（SDL scancode 符号）。

事件/对话运行中可用性由 config 开关控制：
- `always_settings: true` → 任何事件/对话进行中都可 Ctrl+D
- `always_travel: true` → 任何事件/对话进行中都可 Ctrl+J

界面打开后拦截 `Scene_Map#update` 的 super，暂停游戏（事件/玩家/地图/消息窗口），只更新 dev_settings/jump_map 界面；关闭后事件从暂停处继续。转场/传送中仍禁用。

### 关键类/模块/方法

| 模块 | 方法 | 签名 | 说明 |
|------|------|------|------|
| `ShortcutKeysPatch` | `update` | `update` | dev_settings 可见时接管输入 → shortcut_handle → super |
| | `shortcut_handle` (private) | `shortcut_handle` | Ctrl+D/Ctrl+J 检测与分发 |
| | `shortcut_available?` (private) | `shortcut_available?` | 基础可响应条件（在地图上、非转场/传送中） |
| | `event_running?` (private) | `event_running?` | 是否处于事件/对话运行中 |
| | `ctrl_pressed?` (private) | `ctrl_pressed?` | Ctrl 按住检测（优先 mkxp-z 扩展，回退标准 API） |
| | `key_triggered?` (private) | `key_triggered?(sym)` | 字母键按下检测（SDL scancode 符号） |
| | `open_dev_settings_shortcut` (private) | `open_dev_settings_shortcut` | 快捷键方式打开开发者设置 |
| | `open_jump_map_shortcut` (private) | `open_jump_map_shortcut` | 快捷键方式打开跳地图（先开 dev_settings 再 open_jump_map） |

### 实现机制
- **Module#prepend**：通过 `PatchHelper.install('Scene_Map', methods: [:update])` prepend 到 `Scene_Map`
- 打开方式：把 `Window_DevSettings` 实例挂到 `@window_settings` 的 `dev_settings` 槽位，同时把设置窗口置可见；dev_settings 全屏不透明黑底盖住下层
- 关闭：dev_settings 按 CANCEL → `on_closed` 回调恢复设置窗口（visible=false 并清槽位）

### 依赖关系
- 依赖全局变量：`$always_settings_enabled`、`$always_travel_enabled`、`$dev_settings_enabled`、`$dev_settings_instance`、`$mod_config`
- 依赖游戏全局：`$game_map`、`$game_player`、`$game_temp`（`transition_processing`、`player_transferring`、`message_window_showing`）、`$game_system`（`map_interpreter`）
- 依赖 `Scene_Map` 的实例变量：`@window_settings`、`@message_window`、`@ed_message`
- 依赖 `Window_DevSettings`（dev_settings.rb）
- 依赖 mkxp-z 扩展：`Input.pressex?`、`Input.triggerex?`
- 依赖工具：`PatchHelper`、`StatusLog`

### 与其他脚本的交互
- **被调用**：无直接调用，通过 `Scene_Map#update` 的 prepend 链自动生效
- **调用**：
  - `dev_settings.rb`：`Window_DevSettings.new`、`$dev_settings_instance.open`、`$dev_settings_instance.open_jump_map`、`$dev_settings_instance.parent_settings =`、`$dev_settings_instance.on_closed =`
  - `PatchHelper.install`、`StatusLog.write`
- **修改原版行为**：
  - `Scene_Map#update`：dev_settings 可见时 `ds.update + return`（不调用 super，暂停游戏）；否则检测 Ctrl+D/Ctrl+J
- 与 `debug_map.rb`、`quit_all_time.rb`、`skip_event.rb` 共享 `Scene_Map#update` 的 prepend 链
- **关键交互**：shortcut_keys 在 prepend 链中位于 skip_event 之后、quit_all_time 和 debug_map 之前（加载顺序决定），所以 shortcut_keys 的 `return`（dev_settings 可见时）会阻止 quit_all_time 和 debug_map 的 update 执行——这是设计意图（界面打开时暂停游戏）

### 配置项

| 配置 key | 默认值 | 全局变量 | 用途 |
|----------|--------|----------|------|
| `always_settings` | `false`（实际代码无默认，`nil` → false） | `$always_settings_enabled` | 事件/对话运行中是否允许 Ctrl+D |
| `always_travel` | `false`（同上） | `$always_travel_enabled` | 事件/对话运行中是否允许 Ctrl+J |

间接依赖 `is_developer`（通过 `$dev_settings_enabled` 控制 Ctrl+D 是否可用）。

### 关键代码
```ruby
# 第44-58行：update 补丁（核心拦截逻辑）
module ShortcutKeysPatch
  def update
    begin
      ds = $dev_settings_instance
      if ds && ds.visible
        # dev_settings 打开中(含 jump_map 子界面): 暂停游戏, 只更新界面输入
        ds.update
        return
      end
      shortcut_handle
    rescue StandardError
      # 快捷键异常不影响主流程
    end
    super
  end

# 第125-141行：open_dev_settings_shortcut
def open_dev_settings_shortcut
  ds = $dev_settings_instance ||= Window_DevSettings.new
  ds.parent_settings = @window_settings
  ds.on_closed = proc {
    @window_settings.visible = false
    @window_settings.instance_variable_set(:@dev_settings, nil)
  }
  @window_settings.open unless @window_settings.visible
  @window_settings.instance_variable_set(:@dev_settings, ds)
  @window_settings.visible = true
  ds.open
end
```

> **确定内容**：`open_dev_settings_shortcut` 注入的 `on_closed` 回调会恢复被借用的设置窗口（visible=false + 清槽位），这与 dev_settings_patch 中经设置菜单打开时 `on_closed = nil` 形成对比。
> **确定内容**：`@window_settings.open unless @window_settings.visible`——设置窗口未初始化时先 open 一次（初始化 sprite/数据），已打开则保持原状态。
> **确定内容**：`shortcut_available?` 排除转场/传送中（`transition_processing` / `player_transferring`），避免干扰 `Graphics.freeze/transition` 流程。
> **确定内容**：`event_running?` 检测四种情况：`message_window_showing`、`@message_window.visible`、`@ed_message.visible`、`map_interpreter.running?`。
> **不确定**：`Input.pressex?` 和 `Input.triggerex?` 在非 mkxp-z 环境下的回退行为——代码有 `respond_to?` 检查，但回退到 `Input.press?(Input::CTRL)` 后 Ctrl+D/J 仍不可用（因为字母键检测只走 triggerex?）。

---

### skip_dialogue.rb

### 功能描述
跳过所有对话 mod。允许玩家直接跳过所有对话文字：
- 遇到 Show Text（101）时跳过整段文字（含后续 401 行）
- 遇到 Show Choices（102）时自动选择第一个选项
- "Niko feels uneasy." 消息独立开关（`skip_uneasy`），仅跳过这一句读档提示

三个独立开关：`skip_dialogue`、`skip_choice`、`skip_uneasy`。

### 关键类/模块/方法

| 模块 | 方法 | 签名 | 说明 |
|------|------|------|------|
| `SkipAllDialoguePatch` | `_trace_log` | `_trace_log(msg)` | 写 trace 到 `skip_trace.log` |
| | `uneasy_line?` | `uneasy_line?(list, idx)` | 检测当前 101 及其后续 401 是否含 "Niko feels uneasy" |
| | `execute_command` | `execute_command` | 核心：101/401 跳过对话，102 自动选第一项 |

### 实现机制
- **Module#prepend**：通过 `PatchHelper.install('Interpreter', methods: [:execute_command])` prepend 到 `Interpreter`
- 关键设计：不手动 `@index += 1`，靠 `Interpreter#update` 统一 `@index += 1`；只把 `@index` 移到"最后一个 401"，靠 update 的 +1 自然越过整段文字

### 依赖关系
- 依赖全局变量：`$skip_dialogue_enabled`、`$skip_choice_enabled`、`$skip_uneasy_enabled`、`$mod_config`
- 依赖 `Interpreter` 的实例变量：`@index`、`@list`、`@event_id`、`@branch`、`@pic_skip_mode`（跨模块交互，由 picture_skip.rb 定义）
- 依赖工具：`PatchHelper`、`StatusLog`
- `require 'json'`

### 与其他脚本的交互
- **被调用**：无直接调用，通过 `Interpreter#execute_command` 的 prepend 链自动生效
- **调用**：`PatchHelper.install`、`StatusLog.write`、`StatusLog.append`
- **修改原版行为**：
  - `Interpreter#execute_command`：101/401 跳过整段对话文字；102 设置 `@branch[0] = 0` 自动选第一个选项
- 与 `picture_skip.rb`、`skip_event.rb` 共享 `Interpreter#execute_command` 的 prepend 链
- **跨模块交互（关键）**：
  - 跳过 101 时代为清除 `@pic_skip_mode`（第89-92行），因为 101 被这里吞掉后 `PictureSkipPatch` 看不到它来退出"跳过图片"模式，会一路 `command_end` 提前截断含演出的事件
  - `skip_uneasy` 命中时也清除 `@pic_skip_mode`（第68-70行）

### 配置项

| 配置 key | 默认值 | 全局变量 | 用途 |
|----------|--------|----------|------|
| `skip_dialogue` | `false` | `$skip_dialogue_enabled` | 跳过对话文字（101/401） |
| `skip_choice` | `false` | `$skip_choice_enabled` | 自动选择第一个选项（102） |
| `skip_uneasy` | `false` | `$skip_uneasy_enabled` | 仅跳过 "Niko feels uneasy." 读档提示 |

### 关键代码
```ruby
# 第47-57行：uneasy_line? 检测（OneShot 101 把 face+文本合并进 parameters[0]）
def uneasy_line?(list, idx)
  if list[idx].parameters[0].to_s =~ /Niko feels uneasy/i
    return true
  end
  i = idx + 1
  while i < list.size && list[i].code == 401
    return true if list[i].parameters[0].to_s =~ /Niko feels uneasy/i
    i += 1
  end
  false
end

# 第78-96行：skip_dialogue 跳过 101/401（含跨模块 @pic_skip_mode 清除）
if $skip_dialogue_enabled
  if defined?(@pic_skip_mode) && @pic_skip_mode
    @pic_skip_mode = false
    _trace_log("SKIP_DLG clear_pic ev=#{@event_id} idx=#{@index}")
  end
  text = (@list[@index].parameters[0].to_s rescue '').gsub("\n", ' ')
  _trace_log("SKIP_DLG c#{code} ev=#{@event_id} idx=#{@index} \"#{text[0, 18]}\"")
  @index += 1 while @index < @list.size - 1 && @list[@index + 1].code == 401
  return true
end

# 第99-108行：skip_choice 自动选第一个选项
when 102
  if $skip_choice_enabled
    _trace_log("SKIP_CHOICE c102 ev=#{@event_id} idx=#{@index}")
    @branch[0] = 0
    return true
  end
```

> **确定内容**：`@index += 1 while @index < @list.size - 1 && @list[@index + 1].code == 401`——把 `@index` 移到最后一个 401 上，靠 update 的 +1 越过整段。条件 `@index < @list.size - 1` 防止越界。
> **确定内容**：`@branch[0] = 0` 设置选择索引为 0（第一个选项），后续 402（When [**]）会据此判断分支。
> **确定内容**：不跳过 103/104/105/106（注释说明保留事件时序，避免音效反复触发和死循环）。
> **确定内容**：`uneasy_line?` 先查 101 自身参数（OneShot 把 face+文本合并进 `parameters[0]`，如 `@ed [Niko feels uneasy.]`），再查后续 401 行。
> **不确定**：`@branch` 数组的结构和索引含义，需对照 RPG Maker XP Interpreter 源码验证。

---

### skip_event.rb

### 功能描述
事件跳过（skip_event）三态模式，是整个 mod 中最复杂的文件。

**config `skip_event`: `"off" | "block" | "fast"`**
- **off** → 正常游玩：所有事件照常触发执行
- **block** → A模式"整体阻止"（自由探索）：识别"限制角色行动的演出事件"（进图自动触发 + 第一页无条件 + 含对话/按键/玩家移动路线/长等待），整个事件不启动；玩家主动触发与 CE9 出口传送放行。剧情不推进，玩家自由行动。
- **fast** → B模式"跳过演出保功能"：事件照常触发，但跳过演出命令（对话/选项/按键/等待/图片/玩家移动路线），保留功能命令（传送/开关/变量/调CE/脚本）。每帧限步 60 条，事件跨帧完成。

自由浏览模式（`$jump_map_free_mode`，Ctrl+J 跳关后进入）与 block 共用同一套"事件级阻止"规则。

**铁律**（block/fast/off 共有）：读档（real_load）完成后立即清空主事件解释器——修复"重启后进度丢失"。

### 关键类/模块/方法

**顶层方法（定义在 Object 上，全局可用）：**

| 方法 | 签名 | 说明 |
|------|------|------|
| `skip_event_trace` | `skip_event_trace(msg)` | 写 trace 到 `skip_trace.log` |
| `skip_event_active?` | `skip_event_active?` | `$skip_event_mode != 'off' \|\| $jump_map_free_mode` |
| `skip_event_block_mode?` | `skip_event_block_mode?` | `$skip_event_mode == 'block' \|\| $jump_map_free_mode` |
| `skip_event_classify` | `skip_event_classify(map_id, event_id)` | 事件分类：`:block`/`:partial`/`:allow`（缓存） |
| `skip_event_lock_player?` | `skip_event_lock_player?(list)` | 检测命令列表是否含锁玩家特征 |
| `skip_event_is_map1_ev1?` | `skip_event_is_map1_ev1?` | 当前解释器是否在跑 map1 ev1 |
| `skip_event_clear_cg_pictures` | `skip_event_clear_cg_pictures(tag)` | 清除残留开场 CG 图片 |

**补丁模块（6个）：**

| 模块 | prepend 目标 | 覆盖方法 | 说明 |
|------|-------------|----------|------|
| `SkipEventAutoRunPatch` | `Game_Event` | `check_event_trigger_auto` | block 模式阻止 autorun 演出事件 |
| `SkipEventParallelPatch` | `Game_Event` | `update` | block 模式阻止并行演出事件 |
| `SkipEventCommonEventPatch` | `Interpreter` | `setup` | 阻止 CE15 Instructions / CE42 Load Save |
| `SkipEventFastForwardPatch` | `Interpreter` | `execute_command` | fast 模式跳过演出命令（每帧限步60） |
| `SkipEventRealLoadPatch` | `Object` | `real_load` | 读档后清空主解释器（铁律） |
| `SkipEventCgCleanerPatch` | `Scene_Map` | `update` | 每帧兜底清除残留 CG + 停止开场 BGM |

常量：
- `FAST_MAX_STEPS_PER_FRAME = 60`
- `CG_PICTURE_RE = %r{cg_wake|cg_tower|instruction|felix|cg_niko_in_bed|^black$|^white$}i`

### 实现机制
- **Module#prepend**：5 个补丁通过 `PatchHelper.install` prepend，1 个（`SkipEventRealLoadPatch`）直接 `Object.prepend`
- **事件分类缓存**：`$skip_event_class_cache = {}`，按 `[map_id, event_id]` 缓存分类结果
- **fast 限步**：`@skip_fast_frame` / `@skip_fast_steps` 跟踪当前帧已跳步数，超过 60 则 `return false` 暂停，下一帧继续
- **铁律**：`real_load` 后无条件清空 `map_interpreter`，不依赖 skip_event 模式

### 依赖关系
- 依赖全局变量：`$skip_event_mode`、`$jump_map_free_mode`、`$skip_event_class_cache`、`$mod_config`
- 依赖游戏全局：`$game_map`、`$game_player`、`$game_system`（`map_interpreter`、`playing_bgm`）、`$game_temp`、`$game_screen`（`pictures`）、`$game_variables`
- 依赖 `Game_Event` 的实例变量：`@trigger`、`@list`、`@erased`
- 依赖 `Interpreter` 的实例变量：`@index`、`@list`、`@event_id`、`@button_input_variable_id`
- 依赖 `Audio.bgm_stop`、`Graphics.frame_count`
- 依赖工具：`PatchHelper`、`StatusLog`

### 与其他脚本的交互
- **被调用**：
  - `jump_map.rb`：设置 `$jump_map_free_mode = true`（skip_event 读取此变量）
- **调用**：`PatchHelper.install`（5次）、`StatusLog.write`、`StatusLog.append`
- **修改原版行为**：
  - `Game_Event#check_event_trigger_auto`：block 模式下分类为 `:block` 的 autorun 事件 `return`（不触发）
  - `Game_Event#update`：block 模式下分类为 `:block` 的并行事件 `return`（不更新）
  - `Interpreter#setup`：`skip_event_active?` 时阻止 CE15/CE42（`list = nil`）
  - `Interpreter#execute_command`：fast 模式跳过演出命令；block 模式仅 map1 ev1 跳过演出命令
  - `Object#real_load`：读档后清空主解释器 + 清残留 CG + 停止 BGM
  - `Scene_Map#update`：每帧兜底清除残留 CG + 停止特定 BGM（SomeplaceIKnow）
- 与 `event_twitch.rb` 共享 `Game_Event` 的 prepend 链
- 与 `picture_skip.rb`、`skip_dialogue.rb` 共享 `Interpreter#execute_command` 的 prepend 链
- 与 `debug_map.rb`、`quit_all_time.rb`、`shortcut_keys.rb` 共享 `Scene_Map#update` 的 prepend 链

### 配置项

| 配置 key | 默认值 | 全局变量 | 用途 |
|----------|--------|----------|------|
| `skip_event` | `'off'` | `$skip_event_mode` | 三态：off/block/fast |

`$skip_event_mode` 校验：`'off' unless %w[off block fast].include?($skip_event_mode)`，非法值降级为 `'off'`。

### 关键代码
```ruby
# 第65-91行：skip_event_classify（事件分类，map1 ev1 特殊处理）
def skip_event_classify(map_id, event_id)
  return :partial if map_id == 1 && event_id == 1  # 开场总控：部分执行
  key = [map_id, event_id]
  return $skip_event_class_cache[key] if $skip_event_class_cache.key?(key)
  result = :allow
  begin
    ev = $game_map && $game_map.events && $game_map.events[event_id]
    if ev
      page = ev.event.pages[0]
      if page && (page.trigger == 3 || page.trigger == 4)  # autorun / parallel
        cond = page.condition
        if cond && !cond.switch1_valid && !cond.switch2_valid &&
           !cond.variable_valid && !cond.self_switch_valid        # 第一页无条件
          result = :block if skip_event_lock_player?(page.list)
        end
      end
    end
  rescue StandardError
    result = :allow
  end
  $skip_event_class_cache[key] = result
end

# 第170-237行：SkipEventFastForwardPatch#execute_command（fast 模式核心）
module SkipEventFastForwardPatch
  def execute_command
    if skip_event_active? && @index < @list.size && @list[@index]
      code = @list[@index].code
      if skip_event_fast_this_event?
        if skip_event_skip_code?(code)
          frame = Graphics.frame_count
          if @skip_fast_frame != frame
            @skip_fast_frame = frame
            @skip_fast_steps = 0
          end
          @skip_fast_steps += 1
          if @skip_fast_steps > FAST_MAX_STEPS_PER_FRAME
            return false  # 本帧限步：暂停，下帧重试同一条
          end
          # 105 按键输入：模拟"已按确认键"
          if code == 105
            var_id = @list[@index].parameters[0].to_i
            $game_variables[var_id] = 5 if var_id > 0 && $game_variables
            @button_input_variable_id = 0 if defined?(@button_input_variable_id)
          end
          # map1 ev1 开场 BGM 拦截
          if code == 241 && skip_event_is_map1_ev1?
            # ... BGM 停止逻辑
          end
          return true
        end
      end
    end
    super
  end

# 第245-266行：SkipEventRealLoadPatch（铁律）
module SkipEventRealLoadPatch
  def real_load
    result = super
    begin
      if $game_system && $game_system.map_interpreter
        $game_system.map_interpreter.clear
        $game_system.map_interpreter.instance_variable_set(:@list, nil)
        skip_event_trace('SE_CLEAR_AFTER_REAL_LOAD')
      end
      skip_event_clear_cg_pictures('SE_CLEAR_AFTER_LOAD') if $game_screen
      if skip_event_active? && Audio.respond_to?(:bgm_stop)
        Audio.bgm_stop
        skip_event_trace('SE_STOP_BGM_AFTER_LOAD')
      end
    rescue StandardError
    end
    result
  end
end
Object.prepend(SkipEventRealLoadPatch)
```

> **确定内容**：map1 ev1（开场总控）分类为 `:partial`——必须执行到 real_load（读档）后终止，不能整体阻止（否则无法读档/开新档）；其演出命令由 execute_command 补丁在 block/fast 模式下跳过。
> **确定内容**：`skip_event_lock_player?` 检测四种锁玩家特征：101（对话）、105（按键输入）、209/212 目标=-1（玩家移动路线）、等待累计 >5 帧。
> **确定内容**：公共事件拦截覆盖三条路径：自动 trigger1（CE15）、common_event_id（CE42，real_load 设置）、手动 117 调用（map1 ev1 调 CE15）——统一在 `Interpreter#setup` 的 `common_event_name` 参数拦截。
> **确定内容**：fast 模式 105 按键输入模拟"已按确认键"（设变量=5），防止依赖按键的 loop 死循环（CE15 Instructions 的开场 loop 依赖变量）。
> **确定内容**：`return false` 在 `Interpreter#update` 中表示"命令未完成，下一帧继续"，用于限步暂停。
> **确定内容**：铁律（real_load 清空解释器）在 off 模式下也必须生效——注释明确说明"此铁律不依赖 skip_event 模式，off 模式下也必须生效"。
> **不确定**：`Object.prepend(SkipEventRealLoadPatch)` 是否能正确 prepend 到 `real_load` 方法——`real_load` 可能定义在某个特定类/模块上而非 Object 上，`Object.prepend` 会影响所有对象的 `real_load` 调用，需验证 `real_load` 的实际定义位置。

---

### title_screen.rb

### 功能描述
标题界面控制（方案B：上下文敏感）。

**问题（旧方案A）**：`Object.prepend` 全局劫持 `save_exists`，`unshow_title=true` 时 `save_exists` 永远返回 true，即使真实没有存档。导致 map1 ev1 idx9 条件误判为真 → 执行 real_load 读不存在的存档 → 游戏卡住。

**方案B**：`save_exists` 恢复原版真实文件检查（`FileTest.exist?`），单独 patch `Scene_Title#main` 置上下文标记 `$title_screen_context`，`save_exists` 在标题画面上下文里按 `unshow_title` 返回 true（跳过标题），其余场合（如 map1 ev1 事件命令 111 条件）返回原版真实检查。

### 关键类/模块/方法

| 模块 | 方法 | 签名 | 说明 |
|------|------|------|------|
| `TitleScreenMainContextPatch` | `main` | `main` | 置 `$title_screen_context = true` → super → ensure 中置 false |
| `TitleScreenSaveExistsPatch` | `save_exists` | `save_exists` | 标题上下文 + unshow_title → true；其余 → super |

### 实现机制
- **Module#prepend**：`TitleScreenMainContextPatch` 通过 `PatchHelper.install('Scene_Title', methods: [:main])` prepend 到 `Scene_Title`
- **Object.prepend**：`TitleScreenSaveExistsPatch` 直接 `Object.prepend`（全局劫持，但上下文敏感）
- 上下文标记：`$title_screen_context` 全局变量

### 依赖关系
- 依赖全局变量：`$unshow_title_enabled`、`$title_screen_context`、`$mod_config`
- 依赖原版 `save_exists` 方法（`FileTest.exist?(SAVE_FILE_NAME)`，0102_SaveLoad.rb:258）
- 依赖工具：`PatchHelper`、`StatusLog`

### 与其他脚本的交互
- **被调用**：无直接调用，通过 `Scene_Title#main` 和 `save_exists` 的方法链自动生效
- **调用**：`PatchHelper.install`、`StatusLog.write`
- **修改原版行为**：
  - `Scene_Title#main`：执行期间置 `$title_screen_context = true`
  - `save_exists`（全局）：标题上下文 + unshow_title 时返回 true（跳过标题界面），其余返回原版真实检查
- 与 `skip_event.rb` 的 `SkipEventRealLoadPatch` 都使用 `Object.prepend`

### 配置项

| 配置 key | 默认值 | 全局变量 | 用途 |
|----------|--------|----------|------|
| `unshow_title` | `false` | `$unshow_title_enabled` | 不展示标题，直接进游戏 |

### 关键代码
```ruby
# 第28-41行：Scene_Title#main 上下文标记
module TitleScreenMainContextPatch
  def main
    $title_screen_context = true
    begin
      super
    ensure
      $title_screen_context = false
    end
  end
end
PatchHelper.install('Scene_Title', methods: [:main]) do |k|
  k.prepend(TitleScreenMainContextPatch)
end

# 第46-56行：save_exists 上下文敏感补丁
module TitleScreenSaveExistsPatch
  def save_exists
    if $title_screen_context && $unshow_title_enabled
      true
    else
      super
    end
  end
end
Object.prepend(TitleScreenSaveExistsPatch)
```

> **确定内容**：`ensure` 块保证即使 super 抛异常也会清除 `$title_screen_context`。
> **确定内容**：`Object.prepend` 影响所有对象的 `save_exists` 调用，但只有在 `$title_screen_context && $unshow_title_enabled` 时才返回 true，其余走 super（原版真实文件检查）。
> **确定内容**：原版 `save_exists = FileTest.exist?(SAVE_FILE_NAME)`（0102_SaveLoad.rb:258，注释中引用）。
> **不确定**：`save_exists` 方法的实际定义位置——注释称在 0102_SaveLoad.rb:258，但 `Object.prepend` 是否能正确拦截该方法调用取决于方法查找链，需验证。

---

### mod 脚本依赖关系图

### 一、全局变量依赖矩阵

| 全局变量 | 设置者 | 读取者 |
|----------|--------|--------|
| `$mod_config` | `_config.rb` | 所有读取配置的脚本 |
| `$is_skip_picture` | `picture_skip.rb`、`dev_settings.rb`(apply_global) | `picture_skip.rb` |
| `$quit_all_time_enabled` | `quit_all_time.rb`、`dev_settings.rb` | `quit_all_time.rb` |
| `$skip_dialogue_enabled` | `skip_dialogue.rb`、`dev_settings.rb` | `skip_dialogue.rb` |
| `$skip_choice_enabled` | `skip_dialogue.rb`、`dev_settings.rb` | `skip_dialogue.rb` |
| `$skip_uneasy_enabled` | `skip_dialogue.rb`、`dev_settings.rb` | `skip_dialogue.rb` |
| `$skip_event_mode` | `skip_event.rb`、`dev_settings.rb` | `skip_event.rb` |
| `$jump_map_free_mode` | `jump_map.rb`、`skip_event.rb`(初始化) | `skip_event.rb` |
| `$always_settings_enabled` | `shortcut_keys.rb`、`dev_settings.rb` | `shortcut_keys.rb` |
| `$always_travel_enabled` | `shortcut_keys.rb`、`dev_settings.rb` | `shortcut_keys.rb` |
| `$unshow_title_enabled` | `title_screen.rb`、`dev_settings.rb` | `title_screen.rb` |
| `$dev_settings_enabled` | `dev_settings.rb` | `debug_map.rb`、`dev_settings_patch.rb`、`shortcut_keys.rb` |
| `$dev_settings_instance` | `dev_settings.rb` | `shortcut_keys.rb` |
| `$debug_map_overlay` | `debug_map.rb` | `debug_map.rb` |
| `$title_screen_context` | `title_screen.rb` | `title_screen.rb` |
| `$skip_event_class_cache` | `skip_event.rb` | `skip_event.rb` |

### 二、文件间直接调用关系

```
mod.rb (入口, load 所有文件)
  ├─ _config.rb → $mod_config
  ├─ _patch_helper.rb → PatchHelper
  ├─ _status_log.rb → StatusLog
  ├─ debug_map.rb ──────────────→ PatchHelper, StatusLog
  │   └─ 读取 $dev_settings_enabled (dev_settings.rb)
  ├─ dev_settings.rb ───────────→ StatusLog
  │   ├─ 定义 Window_DevSettings, $dev_settings_instance
  │   └─ 调用 Window_JumpMap (jump_map.rb)
  ├─ dev_settings_patch.rb ─────→ PatchHelper, StatusLog
  │   └─ 调用 Window_DevSettings (dev_settings.rb)
  ├─ event_twitch.rb ────────────→ PatchHelper, StatusLog
  ├─ jump_map.rb ───────────────→ StatusLog
  │   ├─ 定义 Window_JumpMap
  │   └─ 设置 $jump_map_free_mode (被 skip_event.rb 读取)
  ├─ picture_skip.rb ───────────→ PatchHelper, StatusLog
  ├─ quit_all_time.rb ───────────→ PatchHelper, StatusLog
  ├─ shortcut_keys.rb ───────────→ PatchHelper, StatusLog
  │   └─ 调用 Window_DevSettings (dev_settings.rb), $dev_settings_instance
  ├─ skip_dialogue.rb ───────────→ PatchHelper, StatusLog
  │   └─ 跨模块清除 @pic_skip_mode (picture_skip.rb 的实例变量)
  ├─ skip_event.rb ─────────────→ PatchHelper(5次), StatusLog
  │   └─ 读取 $jump_map_free_mode (jump_map.rb 设置)
  └─ title_screen.rb ────────────→ PatchHelper, StatusLog
```

### 三、prepend 链（同一方法多个补丁的调用顺序）

> **规则**：`Module#prepend` 后 prepend 的模块在祖先链中更靠前（先被调用）。加载顺序决定 prepend 顺序。

#### Interpreter#execute_command（3个补丁）

加载顺序：`picture_skip.rb` → `skip_dialogue.rb` → `skip_event.rb`

调用链（外→内）：
```
SkipEventFastForwardPatch (skip_event.rb, 最后加载=最外层)
  └─ SkipAllDialoguePatch (skip_dialogue.rb)
      └─ PictureSkipPatch (picture_skip.rb, 最先加载=最内层)
          └─ 原版 Interpreter#execute_command
```

**关键交互**：
- fast 模式下 `SkipEventFastForwardPatch` 对演出命令 `return true`，`SkipAllDialoguePatch` 和 `PictureSkipPatch` 看不到这些命令
- block 模式下 `SkipEventFastForwardPatch` 只对 map1 ev1 跳过演出，其他事件的 101 会传到 `SkipAllDialoguePatch`
- `SkipAllDialoguePatch` 跳过 101 时清除 `@pic_skip_mode`（因为 `PictureSkipPatch` 看不到被吞掉的 101）

#### Scene_Map#update（4个补丁）

加载顺序：`debug_map.rb` → `quit_all_time.rb` → `shortcut_keys.rb` → `skip_event.rb`

调用链（外→内）：
```
SkipEventCgCleanerPatch (skip_event.rb, 最外层)
  └─ ShortcutKeysPatch (shortcut_keys.rb)
      └─ QuitAllTimePatch (quit_all_time.rb)
          └─ DebugMapPatch (debug_map.rb, 最内层)
              └─ 原版 Scene_Map#update
```

**关键交互**：
- `ShortcutKeysPatch` 在 dev_settings 可见时 `ds.update + return`，阻止 `QuitAllTimePatch` 和 `DebugMapPatch` 执行（界面打开时暂停游戏）
- `SkipEventCgCleanerPatch` 总是先执行（清 CG + 停 BGM），然后 `super` 到内层

#### Game_Event（3个补丁，分布在不同方法）

| 方法 | 补丁 | 加载顺序 |
|------|------|----------|
| `start` | `EventTwitchGuardPatch` (event_twitch.rb) | 唯一 |
| `update` | `SkipEventParallelPatch` (skip_event.rb) | 唯一 |
| `check_event_trigger_auto` | `SkipEventAutoRunPatch` (skip_event.rb) | 唯一 |

> Game_Event 的三个补丁分别覆盖不同方法，无直接冲突。

### 四、配置键 → 脚本 → 全局变量映射

| config key | 默认值 | 读取脚本 | 全局变量 |
|------------|--------|----------|----------|
| `skip_pictures` | `true` | picture_skip.rb | `$is_skip_picture` |
| `quit_all_time` | `true` | quit_all_time.rb | `$quit_all_time_enabled` |
| `skip_dialogue` | `false` | skip_dialogue.rb | `$skip_dialogue_enabled` |
| `skip_choice` | `false` | skip_dialogue.rb | `$skip_choice_enabled` |
| `skip_uneasy` | `false` | skip_dialogue.rb | `$skip_uneasy_enabled` |
| `skip_event` | `'off'` | skip_event.rb | `$skip_event_mode` |
| `always_travel` | `false` | shortcut_keys.rb | `$always_travel_enabled` |
| `always_settings` | `false` | shortcut_keys.rb | `$always_settings_enabled` |
| `unshow_title` | `false` | title_screen.rb | `$unshow_title_enabled` |
| `is_developer` | `false` | dev_settings.rb | `$dev_settings_enabled` |

### 五、工具层依赖

```
所有脚本 ──→ StatusLog (_status_log.rb) [除 _config.rb(加载更早)]
所有补丁脚本 ──→ PatchHelper (_patch_helper.rb)
所有配置读取 ──→ $mod_config (_config.rb)
所有 require 'json' ──→ 标准库 (mod.rb 添加 $LOAD_PATH)
```

---

### 总结与验证备注

### 已验证的架构假设
1. **mod.rb 是 preload 入口，自动加载同目录全部 .rb** — 确认（第29-38行 `Dir.glob.sort.each { load }`）
2. **_config.rb 读 config.json → $mod_config** — 确认（第14-23行）
3. **_patch_helper.rb 提供 PatchHelper（等待类定义 + Module#prepend）** — 确认（`TracePoint.trace(:end)` + `block.call(tp.self)`）
4. **_status_log.rb 提供 StatusLog（写 logs/）** — 确认（`write`/`append`）
5. **mod 脚本全部通过 preload 注入，不修改原版 xScripts.rxdata** — 确认（所有修改均通过 `Module#prepend` 或 `alias`/`define_singleton_method`）
6. **config.json 控制功能开关** — 确认（11个配置键）
7. **快捷键 Ctrl+D/Ctrl+J/Ctrl+G** — 确认（shortcut_keys.rb: Ctrl+D/Ctrl+J；debug_map.rb: Ctrl+G）

### 需进一步验证的事项
1. `modshot.json` 中 preloadScript 的具体配置值（确认 mod.rb 确实是入口）
2. `jump_points.json` 的生成方式和脚本位置
3. `Object.prepend` 在 `real_load` 和 `save_exists` 上的实际拦截效果（取决于方法定义位置）
4. RPG Maker XP 命令码 209/211/212/231 等在 OneShot 定制版本中的精确含义
5. `TracePoint.trace(:end)` 在 mkxp-z 环境下的行为是否与标准 CRuby 完全一致
6. `Window_Settings#dispose` 是否在 `methods: [:open, :update]` 检查时已就绪（继承方法的 `method_defined?` 行为）
7. `tr()` 国际化函数的具体实现位置

### 设计亮点
1. **加载顺序的精确控制**：`_` 前缀文件最先加载，确保工具类（config/patch_helper/status_log）在使用方之前就绪
2. **prepend 链的跨模块协作**：skip_dialogue 清除 picture_skip 的 `@pic_skip_mode`，体现了对 prepend 调用顺序的深刻理解
3. **上下文敏感的 save_exists**：title_screen.rb 方案B 优雅解决了全局劫持导致的无存档卡死问题
4. **铁律设计**：skip_event.rb 的 real_load 清空解释器不依赖模式开关，确保 off 模式下也修复进度丢失
5. **限步机制**：fast 模式每帧 60 步上限，避免一帧跑完事件覆盖读档状态

---

## 三、游戏脚本（xscripts）分类概述


> **分析对象**：`xscripts/` 目录下全部 111 个 Ruby 脚本（编号 0000–0110）
> **引擎**：RPG Maker XP (RGSS)，运行于 mkxp-z 运行时
> **游戏**：OneShot（元叙事解谜游戏）的 ModShot 分支
> **分析方式**：静态代码阅读，未执行任何脚本
> **文件说明**：INDEX.txt 中编号 0110 对应 `0110_example.rb`（缺失），编号 0111 对应 `0111_Main.rb`；实际目录中文件名为 `0110_Main.rb`（即 Main 入口脚本）。

---

### 一、核心数据层（Game_*）

**整体职责**：管理游戏运行时的全部全局状态，包括临时数据、系统配置、开关/变量、屏幕效果、图片、战斗单位、角色、队伍、地图、公共事件、玩家，以及 OneShot 特有的游戏状态、光源、跟随者和快速旅行数据。这些对象通过 `$game_*` 全局变量访问，是存档序列化的核心。

### 文件清单与说明

| 编号 | 文件 | 类型 | 功能说明 |
|------|------|------|----------|
| 0001 | `Game_Temp.rb` | **RGSS标准+OneShot定制** | 临时数据容器（不存入存档）。RGSS标准字段含消息文本、选择项、战斗调用、场景切换等；OneShot新增字段：`message_ed_text`/`message_doc_text`/`message_desktop_text`/`message_credits_text`（四种定制消息框文本）、`travel_menu_calling`/`window_settings_calling`（快速旅行/设置菜单调用标志）、`footstep_sfx`（当前地形脚步声效数组）、`filmsprite`（胶片谜题精灵）、`menus_visible`、`target_bgm_vol_level`/`bgm_fadein_speed`（BGM淡入控制）、`prompt_wait`、`countdown_password`、`igt_timer_visible` |
| 0002 | `Game_System.rb` | RGSS标准（基于RGSS常识推断） | 系统级数据：BGM/BGS播放与记忆、SE播放、计时器、存档计数、魔法数字、遇敌率等。OneShot可能在此扩展了部分音频控制 |
| 0003 | `Game_Switches.rb` | RGSS标准 | 全局开关数组（`$game_switches`），通过 `[]`/`[]=` 访问，写入时触发 `$game_map.need_refresh`。OneShot大量使用高编号开关（151–175为跨周目永久标志，251–253为设置项） |
| 0004 | `Game_Variables.rb` | RGSS标准 | 全局变量数组（`$game_variables`），机制同开关。OneShot使用76–100为跨周目永久变量，26–30为暴力破解密码位，101–110为倒计时显示位，7–8为Niko位置 |
| 0005 | `Game_SelfSwitches.rb` | RGSS标准 | 事件独立开关（`[map_id, event_id, 'A'/'B'/'C'/'D']`），像素谜题等大量使用 |
| 0006 | `Game_Screen.rb` | RGSS标准（基于RGSS常识推断） | 屏幕效果管理：色调变更、闪烁、震动、天气、图片管理 |
| 0007 | `Game_Picture.rb` | RGSS标准（基于RGSS常识推断） | 单张图片的数据对象：名称、原点、坐标、缩放、旋转、透明度、合成方式 |
| 0008–0010 | `Game_Battler_1~3.rb` | RGSS标准（基于RGSS常识推断） | 战斗单位基类，分三文件。含属性（HP/SP/状态/参数）、伤害计算、状态效果、动作判定等。OneShot为纯解谜游戏，战斗系统基本未使用 |
| 0011 | `Game_BattleAction.rb` | RGSS标准（基于RGSS常识推断） | 战斗动作数据：速度、类型、技能ID、物品ID、目标索引 |
| 0012 | `Game_Actor.rb` | RGSS标准（基于RGSS常识推断） | 玩家角色数据：等级、经验、技能、装备、状态。OneShot中Niko为唯一角色 |
| 0013 | `Game_Enemy.rb` | RGSS标准（基于RGSS常识推断） | 敌方角色数据。OneShot基本无战斗，此文件保留但可能未实际使用 |
| 0014 | `Game_Actors.rb` | RGSS标准 | 角色数据容器（`$game_actors`），按ID索引 `Game_Actor` 实例 |
| 0015 | `Game_Party.rb` | RGSS标准（基于RGSS常识推断） | 队伍管理：成员、金币、物品、技能。OneShot物品系统 heavily used（道具组合是核心解谜机制） |
| 0016 | `Game_Map.rb` | **RGSS标准+OneShot深度定制** | 地图数据与逻辑。标准字段含图块、通行判定、事件、滚动、雾、全景图；OneShot大量新增：`bg_name`（自定义背景图）、`particles_type`（粒子类型）、`ambient`（环境光Tone）、`wrapping`（地图循环滚动）、`clamped_x/clamped_y`（全景图钳制）、`always_moving`/`pan_move_offset`/`pan_onetoone`/`pan_animate`/`pan_fade_animate`/`pan_zoom`/`pan_offset_y`（全景图高级动画控制）、`wrap_x/wrap_y`（循环显示坐标）。`setup` 方法中根据地图ID设置脚步声效数组和环境光 |
| 0017 | `Game_CommonEvent.rb` | RGSS标准（基于RGSS常识推断） | 公共事件数据与解释器实例。OneShot使用公共事件15（笔记/Journal）、42（读档后恢复）等 |
| 0018–0020 | `Game_Character_1~3.rb` | **RGSS标准+OneShot定制** | 角色基类（玩家/事件/跟随者的父类），分三文件。标准功能：移动、路径、动画、方向、移动路线、跳跃；OneShot可能扩展了移动速度处理和与脚印系统的集成 |
| 0021 | `Game_Event.rb` | RGSS标准（基于RGSS常识推断） | 地图事件：页面条件、事件解释器、触发判定。OneShot事件命名规范（如 `sokoram A`、`pixel`、`niko reflection`、`FAST TRAVEL`）被脚本系统大量引用 |
| 0022 | `Game_Player.rb` | **RGSS标准+OneShot定制** | 玩家角色控制。标准功能：移动、镜头居中、步数、事件触发；OneShot新增：`emit_footstep`/`emit_footsplash` 方法（根据地形标签播放脚步声效并生成脚印/水花精灵）、`@footstep_timer` 计时器（走/跑不同频率）、`refresh` 中根据开关251（默认跑步）调整移动速度。移动时自动生成脚印和水花特效 |
| 0023 | `Game_Oneshot.rb` | **OneShot定制** | OneShot全局游戏状态。字段：`player_name`（玩家操作系统用户名，用于元叙事对话中称呼玩家）、`plight_timer`（困境场景计时起点）、`bruteforce_start`（保险箱暴力破解计时起点）、`wallpaper`/`wallpaper_color`（当前桌面壁纸设置）。`get_user_name` 从 `Oneshot::USER_NAME` 提取用户名首词（特殊处理 "the"/"a" 开头的名称）。内含 `Wallpaper` 模块：`set_persistent` 设置桌面壁纸（支持本地化路径，自动退出全屏，macOS特殊延迟），`reset_persistent` 恢复默认壁纸 |
| 0024 | `Game_Light.rb` | **OneShot定制** | 光源数据对象，极简类。字段：`filename`（光效图片名）、`intensity`（强度）、`x`/`y`（地图坐标）。仅作为数据容器，实际渲染由 `Light` 精灵类（0031）处理 |
| 0025 | `Game_Follower.rb` | **OneShot定制** | 跟随者角色（Niko身后的实体，如灯泡形态的同伴）。继承 `Game_Character`，字段 `leader`（跟随目标）。重写 `passable?` 始终返回true（不阻挡）、禁用事件触发。`update` 中记录leader的上一位置 `@lox/@loy`，当leader移动时沿相同方向追赶，形成拖尾效果。`actor=` 设置角色图像和色调 |
| 0026 | `Game_FastTravel.rb` | **OneShot定制** | 快速旅行数据模型。内含 `Map` 内部类（记录目标地图ID、x、y、朝向）。字段：`@unlocked`（按zone分组的已解锁地图哈希）、`zone`（当前区域）、`enabled`（是否允许快速旅行）。`unlock` 方法在当前zone下解锁指定地图点，`unlocked_maps` 返回当前zone的所有解锁点 |

---

### 二、精灵渲染层（Sprite_*、Spriteset_Map）

**整体职责**：负责地图场景中所有可见元素的渲染，包括角色精灵、战斗精灵、图片精灵、计时器精灵，以及 OneShot 特有的光源、脚印、水花、地图文字精灵。`Spriteset_Map` 是地图精灵的总管理器，整合图块层、角色层、图片层和所有定制特效层。

### 文件清单与说明

| 编号 | 文件 | 类型 | 功能说明 |
|------|------|------|----------|
| 0027 | `Sprite_Character.rb` | RGSS标准（基于RGSS常识推断） | 角色精灵渲染：根据 `Game_Character` 数据绘制行走图、动画帧、方向、透明度、跳跃偏移 |
| 0028 | `Sprite_Battler.rb` | RGSS标准（基于RGSS常识推断） | 战斗单位精灵：伤害弹出、状态动画、攻击动作。OneShot基本未使用战斗 |
| 0029 | `Sprite_Picture.rb` | RGSS标准（基于RGSS常识推断） | 图片精灵：根据 `Game_Picture` 数据渲染，支持缩放旋转 |
| 0030 | `Sprite_Timer.rb` | RGSS标准（基于RGSS常识推断） | 计时器显示精灵 |
| 0031 | `Sprite_Light.rb` | **OneShot定制** | 光源精灵（类名 `Light`，继承 `RPG::Sprite`）。构造时加载光效图片（`RPG::Cache.light`），设置 `lightmap` 和 `intensity` 属性（mkxp-z扩展的着色器属性），z=9999顶层显示。`update` 中根据地图滚动偏移计算屏幕坐标，实现光源跟随地图视差移动 |
| 0032 | `Sprite_Footprint.rb` | **OneShot定制** | 脚印精灵。从 `footprints` 图集中按方向选取16x16帧，2倍缩放。记录真实坐标 `@real_x/@real_y`，`update` 中随地图滚动更新屏幕位置，同时每帧透明度减4，归零后自动dispose，形成脚印渐隐效果。`correctX/correctY` 用于传送时修正坐标 |
| 0033 | `Sprite_Footsplash.rb` | **OneShot定制** | 踏水/水花精灵。使用80x80的 `foot_splash` 精灵表（4x5共20帧动画），2倍缩放。根据移动方向偏移生成位置，`update` 中按透明度计算当前帧索引（`frameIndex = 20 - opacity/13`），播放水花动画后自动消失。用于水面/湿地地形 |
| 0034 | `Sprite_MapText.rb` | **OneShot定制** | 地图浮动文字精灵。在指定地图坐标上方渲染文字（紫色 `Color.new(81,33,129)`），自动计算文字宽度创建Bitmap，根据字体类型调整缩放（西文字体2x，其他1.5x）。`oy=24` 使文字显示在坐标点上方。用于地图名称、交互提示等 |
| 0035 | `Spriteset_Map.rb` | **RGSS标准+OneShot深度定制** | 地图精灵集总管理器。标准功能：创建图块层、角色精灵数组、图片精灵、全景图、雾、天气；OneShot新增：`add_follower`/`remove_follower`（管理跟随者精灵）、`add_light`/`del_light`/`clear_lights`（光源管理，代码中部分被注释）、`new_footprint`/`new_footsplash`/`new_maptext`（工厂方法创建对应特效精灵并加入更新循环）、`fix_footsplashes`（传送时批量修正所有脚印/水花坐标）。`update` 中扩展了对粒子层、脚印、水花等定制元素的更新 |

---

### 三、窗口UI层（Window_*）

**整体职责**：所有基于 `Window_Base` 的UI窗口类，构成游戏的菜单、物品、技能、装备、状态、商店、存档、命名、消息、战斗、调试等界面。OneShot 在此层新增了设置窗口和主菜单窗口，并深度定制了消息窗口以支持头像替换、玩家名插入、自动跳过等功能。

### 文件清单与说明

| 编号 | 文件 | 类型 | 功能说明 |
|------|------|------|----------|
| 0037 | `Window_Base.rb` | RGSS标准（基于RGSS常识推断） | 所有窗口的基类：绘制角色、物品、技能、状态、HP/SP、金币、文字颜色系统 |
| 0038 | `Window_Selectable.rb` | RGSS标准（基于RGSS常识推断） | 可选择窗口基类：光标移动、滚动、列数/行数管理、帮助窗口关联 |
| 0039 | `Window_Command.rb` | RGSS标准（基于RGSS常识推断） | 命令选择窗口：通用的纵向命令列表 |
| 0040 | `Window_Help.rb` | RGSS标准（基于RGSS常识推断） | 帮助文本窗口：显示物品/技能描述 |
| 0041 | `Window_Gold.rb` | RGSS标准（基于RGSS常识推断） | 金币显示窗口 |
| 0042 | `Window_PlayTime.rb` | RGSS标准（基于RGSS常识推断） | 游戏时间显示窗口 |
| 0043 | `Window_Steps.rb` | RGSS标准（基于RGSS常识推断） | 步数显示窗口 |
| 0044 | `Window_MenuStatus.rb` | RGSS标准（基于RGSS常识推断） | 菜单状态窗口：显示队伍成员状态。OneShot可能简化为单角色 |
| 0045 | `Window_Item.rb` | RGSS标准（基于RGSS常识推断） | 物品选择窗口。OneShot物品系统核心界面，支持道具组合 |
| 0046 | `Window_Skill.rb` | RGSS标准（基于RGSS常识推断） | 技能选择窗口 |
| 0047 | `Window_SkillStatus.rb` | RGSS标准（基于RGSS常识推断） | 技能目标状态窗口 |
| 0048 | `Window_Target.rb` | RGSS标准（基于RGSS常识推断） | 目标选择窗口（物品/技能使用时选择角色） |
| 0049 | `Window_EquipLeft.rb` | RGSS标准（基于RGSS常识推断） | 装备窗口左侧：当前装备槽位 |
| 0050 | `Window_EquipRight.rb` | RGSS标准（基于RGSS常识推断） | 装备窗口右侧：可装备物品列表 |
| 0051 | `Window_EquipItem.rb` | RGSS标准（基于RGSS常识推断） | 装备物品选择窗口 |
| 0052 | `Window_Status.rb` | RGSS标准（基于RGSS常识推断） | 角色详细状态窗口 |
| 0053 | `Window_SaveFile.rb` | RGSS标准（基于RGSS常识推断） | 存档文件选择窗口：显示存档预览（角色图、游戏时间、地图名） |
| 0054 | `Window_Settings.rb` | **OneShot定制** | 设置菜单（非Window继承，使用Sprite+Viewport自绘）。功能项：BGM音量、SFX音量、全屏切换、默认移动方式（走/跑，开关251）、色盲模式（开关252）、跳过文本R键（开关253）、跳帧、语言切换、按键配置（提示按F1）。支持左右键长按连续调节音量，语言切换实时调用 `$persistent.lang=` 触发 `Language.set`。`save_settings` 持久化到 `settings.conf`，`load_settings` 为类方法从文件读取。版本号显示在左下角（`POT_VERSION`） |
| 0055 | `Window_ShopCommand.rb` | RGSS标准（基于RGSS常识推断） | 商店命令窗口（买/卖/取消） |
| 0056 | `Window_ShopBuy.rb` | RGSS标准（基于RGSS常识推断） | 商店购买窗口 |
| 0057 | `Window_ShopSell.rb` | RGSS标准（基于RGSS常识推断） | 商店出售窗口 |
| 0058 | `Window_ShopNumber.rb` | RGSS标准（基于RGSS常识推断） | 商店数量输入窗口 |
| 0059 | `Window_ShopStatus.rb` | RGSS标准（基于RGSS常识推断） | 商店物品状态对比窗口 |
| 0060 | `Window_NameEdit.rb` | RGSS标准（基于RGSS常识推断） | 名字编辑窗口：显示当前输入的名字 |
| 0061 | `Window_NameInput.rb` | **RGSS标准+OneShot定制** | 名字输入键盘。OneShot通过 `Language.create_input` 方法按语言动态配置字符表：默认英文（大写/小写两页）、日文（英字/平假名/片假名三页）、俄文（英文/西里尔字母两页）。支持 `ok_text`、`set_mode_buttons`、`character_tables`、`table_height` 等可配置属性 |
| 0062 | `Window_InputNumber.rb` | RGSS标准（基于RGSS常识推断） | 数字输入窗口 |
| 0063 | `Window_Message.rb` | **RGSS标准+OneShot深度定制** | 消息窗口（对话框）。OneShot大量定制：(1) `\p` 转义符插入玩家用户名（西文直接插入，亚洲语言前加空格）；(2) 防毒面具头像替换——当玩家穿戴防毒面具且消息头像以"niko"/"en"开头时，自动替换为 `niko_gasmask`/`en_gasmask`；(3) `@skip_text` 支持R键快速跳过文本（开关253控制）；(4) `@skip_message_proc` 标志避免选择项/数字输入时误触发消息回调；(5) 注册到 `Language.register_text_sprite` 以支持语言切换时重绘；(6) 头像忽略新脸图的逻辑 |
| 0064 | `Window_PartyCommand.rb` | RGSS标准（基于RGSS常识推断） | 战斗队伍命令窗口（攻击/防御/逃跑）。OneShot未使用战斗 |
| 0065 | `Window_BattleStatus.rb` | RGSS标准（基于RGSS常识推断） | 战斗状态窗口。未使用 |
| 0066 | `Window_BattleResult.rb` | RGSS标准（基于RGSS常识推断） | 战斗结果窗口。未使用 |
| 0067 | `Window_DebugLeft.rb` | RGSS标准（基于RGSS常识推断） | 调试窗口左侧：开关/变量分类选择 |
| 0068 | `Window_DebugRight.rb` | RGSS标准（基于RGSS常识推断） | 调试窗口右侧：具体开关/变量值修改 |
| 0069 | `Window_MainMenu.rb` | **OneShot定制** | 主菜单窗口（继承 `Window_Selectable`）。横向三列布局：Travel（快速旅行）、Notes（笔记，触发公共事件15）、Settings（设置）。打开时淡入动画，选择Travel时检查 `$game_fasttravel.enabled?`，未解锁则显示Ed消息提示。z=9998顶层显示。支持 `Input::ITEMS` 键快速开关菜单 |

---

### 四、事件解释器（Interpreter_1~7）

**整体职责**：RGSS 事件指令的执行引擎，将 RPG Maker XP 编辑器中配置的事件页指令（显示文字、开关操作、变量操作、移动路线、条件分支、循环、公共事件调用、脚本调用等）逐条解释执行。分7个文件按指令编号范围组织，是游戏逻辑的核心驱动。

### 文件清单与说明

| 编号 | 文件 | 类型 | 功能说明 |
|------|------|------|----------|
| 0070 | `Interpreter_1.rb` | RGSS标准（基于RGSS常识推断） | 解释器基类与核心循环：`main` 方法逐帧执行指令、`execute_command` 分发到 `command_xxx` 方法、事件页启动/结束、等待处理、公共事件调用 |
| 0071 | `Interpreter_2.rb` | RGSS标准（基于RGSS常识推断） | 指令100–119：显示文字（101）、显示选择项（102）、请求数字输入（103）、更改文章选项（104）、按钮输入处理（105）、等待（106）、条件分支（111）、循环（112）、中断循环（113）、中止事件（115）、暂时消除事件（116）、完全消除事件（117）、呼叫公共事件（119） |
| 0072 | `Interpreter_3.rb` | RGSS标准（基于RGSS常识推断） | 指令121–149及401–413：开关操作（121）、变量操作（122）、更改计时器（124）、增减金钱（125）、增减物品（126）、增减武器（127）、增减防具（128）、替换角色（129/130）、更改窗口透明度（131）、更改战斗BGM（132）、更改胜利BGM（133）、保存（134）、暂停画面处理（135）、准备过渡（136）、执行过渡（137）、返回标题（138）、脚本（139，OneShot大量使用此指令调用定制函数） |
| 0073 | `Interpreter_4.rb` | RGSS标准（基于RGSS常识推断） | 指令151–199：更改角色图形（151）、更改角色透明度（152）、更改伙伴图形（153）、显示动画（154）、显示伤害（155）、角色消失/出现（156/157）、跟随者操作（158/159）、设置移动路线（160）、移动开始/结束（161/162）、开关移动动画（163/164）、更改移动速度/频率（165/166）、步行/跑步动画开关（167/168）、朝向固定/解放（169/170）、跳跃（171）、等待移动结束（172） |
| 0074 | `Interpreter_5.rb` | RGSS标准（基于RGSS常识推断） | 指令201–249：地图设置（201，更改地图图块组/背景/雾/BGM/BGS）、更改车辆图形（202）、设置事件位置（203）、交换事件位置（204）、地图滚动（205）、更改地图色调（206）、闪烁（207）、震动（208）、显示图片（209）、移动图片（210）、旋转图片（211）、更改图片色调（212）、消除图片（213）、设置天气（214）、调用战斗（215）、商店（216）、命名（217）、更改HP/SP/状态（218–224）、完全恢复（225）、增减EXP/等级/参数（226–231）、更改技能/装备（232/233）、更改角色名/称号/图形（234–236） |
| 0075 | `Interpreter_6.rb` | RGSS标准（基于RGSS常识推断） | 指令250–299及301–355：更改敌人状态/HP/SP（251–253）、敌人完全恢复（254）、敌人隐身/出现（255/256）、更改敌人属性（257）、行动强制（258）、中止战斗（259）、调用公共事件（260）、标签/跳转（261/262）、循环（263）、增减变量（264）、重复次数（265）、断点（266）、游戏结束（267）、返回标题（268）、脚本调用（355，与139类似） |
| 0076 | `Interpreter_7.rb` | RGSS标准（基于RGSS常识推断） | 指令301–355及辅助方法：战斗事件解释器的特殊处理、`setup`/`start`/`update`/`refresh` 等生命周期方法、事件触发判定辅助。OneShot可能在此扩展了对定制消息框的触发支持 |

> **注**：Interpreter 系列为 RGSS 标准实现，OneShot 的定制逻辑主要通过事件指令139/355（脚本调用）来触发 `Script` 模块（0097）和全局函数中的定制功能，而非修改解释器本身的指令分发逻辑。

---

### 五、场景管理层（Scene_*）

**整体职责**：游戏场景状态机，每个 `Scene_*` 类代表一个独立的游戏界面（标题、地图、菜单、物品、技能、装备、状态、存档、结束、命名、调试）。通过 `$scene` 全局变量切换场景，每个场景的 `main` 方法包含初始化→主循环（输入更新+画面更新）→释放资源的标准流程。

### 文件清单与说明

| 编号 | 文件 | 类型 | 功能说明 |
|------|------|------|----------|
| 0077 | `Scene_Title.rb` | **RGSS标准+OneShot定制** | 标题画面。OneShot定制：(1) 继续游戏的判定使用 `save_exists`（自定义存档检测）而非标准的存档文件存在检查；(2) 标题画面名称支持本地化路径 `#{$persistent.langcode}/#{$data_system.title_name}`；(3) `new_game` 中初始化 `$game_oneshot`、`$game_fasttravel`、`$game_followers` 等OneShot全局对象；(4) 集成 `Oneshot.allow_exit`/`Oneshot.exiting` 退出控制；(5) 设置命令入口；(6) `$demo`/`$GDC` 标志控制演示模式 |
| 0078 | `Scene_Map.rb` | **RGSS标准+OneShot深度定制** | 地图场景（游戏主场景）。OneShot大量扩展：(1) 创建四种定制消息框 `@ed_message`/`@doc_message`/`@desktop_message`/`@credits_message` 并在每帧更新；(2) `$game_followers` 跟随者更新；(3) `call_travel_menu`/`call_window_settings` 定制菜单调用；(4) `transfer_player` 中同步玩家和所有跟随者的位置；(5) `add_light`/`del_light`/`clear_lights` 光源管理委托；(6) `particles=` 粒子类型设置；(7) `add_follower`/`remove_follower` 跟随者精灵管理；(8) `bg=` 自定义背景设置；(9) `new_footprint`/`new_footsplash`/`new_maptext`/`fix_footsplashes` 特效工厂方法；(10) `menu_open?` 查询菜单是否打开；(11) 消息窗口可见性检查扩展为包含所有五种消息框 |
| 0079 | `Scene_Menu.rb` | RGSS标准（基于RGSS常识推断） | 菜单场景。OneShot可能简化为使用 `Window_MainMenu` 替代标准菜单命令窗口 |
| 0080 | `Scene_Item.rb` | RGSS标准（基于RGSS常识推断） | 物品菜单场景。OneShot物品组合功能可能在此扩展 |
| 0081 | `Scene_Skill.rb` | RGSS标准（基于RGSS常识推断） | 技能菜单场景 |
| 0082 | `Scene_Equip.rb` | RGSS标准（基于RGSS常识推断） | 装备菜单场景 |
| 0083 | `Scene_Status.rb` | RGSS标准（基于RGSS常识推断） | 状态查看场景 |
| 0084 | `Scene_File.rb` | RGSS标准（基于RGSS常识推断） | 存档/读档场景基类：存档文件列表、选择 |
| 0085 | `Scene_Save.rb` | **RGSS标准+OneShot定制** | 存档场景。OneShot使用自定义 `save` 函数（0102）替代标准存档逻辑，支持备份轮转和永久标志 |
| 0086 | `Scene_Load.rb` | **RGSS标准+OneShot定制** | 读档场景。OneShot使用 `real_load` 函数（0102），支持损坏存档的备份恢复、跟随者链重建、壁纸恢复、BGM恢复 |
| 0087 | `Scene_End.rb` | RGSS标准（基于RGSS常识推断） | 结束游戏场景（返回标题/退出） |
| 0088 | `Scene_Name.rb` | **RGSS标准+OneShot定制** | 命名场景。OneShot通过 `Language.create_input` 按语言创建不同的输入键盘配置 |
| 0089 | `Scene_Debug.rb` | RGSS标准（基于RGSS常识推断） | 调试场景：开关/变量即时修改。OneShot扩展了 `loadQASave` 测试存档加载功能（在0097中定义） |

---

### 六、OneShot 定制层

**整体职责**：OneShot 游戏的核心机制实现，涵盖跨周目持久化数据、国际化系统、自定义数据定义（物品组合、脚步声、特殊事件碰撞、快速旅行区域）、通用脚本工具库、四种谜题逻辑、自定义存档系统、四种元叙事消息框、粒子系统、编辑器文本工具。这一层是 OneShot 区别于标准 RGSS 游戏的核心。

### 6.1 持久化与国际化

| 编号 | 文件 | 功能说明 |
|------|------|----------|
| 0090 | `Persistent.rb` | **跨周目持久化数据核心**。`LanguageCode` 类解析语言代码（如 `zh_CN` → lang=:zh, region=:CN, full=:zh_CN）。`Persistent` 类存储 `lang`（当前语言），序列化到 `Oneshot::SAVE_PATH/persistent.dat`。初始化时优先级：`zh_CN.ver` 文件存在→中文；Steam语言→Steam设置；否则英文。`lang=` 设置时自动调用 `Language.set` 触发语言切换。`marshal_dump`/`marshal_load` 支持Ruby序列化。这是OneShot"游戏记住你"机制的基础——语言设置独立于存档存在 |
| 0091 | `i18n_Language.rb` | **国际化系统核心**。`Language` 类实现类gettext翻译：(1) `load_pot` 解析 `.po` 文件（msgid/msgstr格式，支持多行字符串），用 `Oneshot::crc32(msgid)` 作为哈希键存储；(2) `tr(string)` 按CRC32查找翻译，未找到返回原文；(3) `set(lc)` 按语言代码加载 `.po` 文件、设置字体（从 `language_fonts.ini` 读取语言→字体映射）、调用 `Journal.setLang`、重置所有已注册文本精灵的字体；(4) `register_text_sprite(key, spr)` 注册需要在语言切换时重绘的精灵/Bitmap；(5) `initialize_database` 将数据库中的角色名/物品名/描述包装为 `TrString`（惰性翻译字符串类，`to_s` 时才调用 `Language.tr`）；(6) 全局函数 `tr(text)` 创建 `TrString`。字体常量：西文 `Terminus (TTF)`，日文 `HigashiOme Gothic regular` |
| 0092 | `i18n_English.rb` | **英文本地化配置与名字输入键盘定义**。设置默认字体为西文字体。`Language.create_input` 方法按当前语言创建 `Window_NameInput` 配置：(1) 日文模式（字体为日文字体时）：英字/平假名/片假名三页，完整五十音图；(2) 俄文模式（langcode为ru时）：英文/西里尔字母两页；(3) 默认英文模式：大写/小写两页。每页字符表为5行x18列布局 |

### 6.2 数据定义

| 编号 | 文件 | 功能说明 |
|------|------|----------|
| 0093 | `Data_Item.rb` | **物品组合配方表**。`Item::COMBINATIONS` 哈希定义了约40组道具组合规则，键为 `[物品ID_a, 物品ID_b]`（已排序），值为结果物品ID。特殊值100–104表示"无法组合"的不同提示类型。组合示例：酒精+干树枝→湿树枝、相机+螺丝刀→镜头、灯泡+空电池→充能电池、海绵+酸瓶→湿海绵、羽毛+墨水瓶→笔、胶棒+Niko照片→粘性照片（支持10种不同的Niko照片变体）。`Item.combine(item_a, item_b)` 方法排序后查表 |
| 0094 | `Data_Footsteps.rb` | **脚步声效配置表**。`FOOTSTEP_SFX` 数组按地形标签（terrain tag）索引，每个元素为该地形可能播放的脚步声效名称数组（随机选取）。覆盖约25种地形：起始区（木/瓷砖）、蓝色区（砾石/木）、蓝色室内（瓷砖/木/金属）、绿色区（草地/木/砾石/船）、红色区（格栅/金属）、塔区（水花）、工厂区（金属，音量0.5）等。`FOOTSTEP_AMT` 定义某些声效的变体数量（金属/瓷砖有4种变体随机播放避免重复感） |
| 0095 | `Data_SpecialEventData.rb` | **特殊事件碰撞数据**。`SpecialEventData` 类存储 `flags`（特殊属性，如 `:bottom` 表示仅底部可交互）和 `collision`（相对于事件原点的碰撞格坐标数组）。`SPECIAL_EVENTS` 哈希定义了10种特殊事件：大水池（5x7不规则碰撞区）、小水池、特殊水池、发电机（3x4梯形碰撞区）、机器、故障（glitch）、床、售货机、镜头等。`SpecialEventData.get(name)` 按名称查询。用于非矩形碰撞区域的交互判定 |
| 0096 | `Data_FastTravel.rb` | **快速旅行区域数据**。`FastTravel::Zone` 类存储区域显示名和地图名映射。`ZONES` 哈希定义4大区域：(1) `red_ground`——The Refuge (Surface)，5个地点（电梯街、小贩街、后巷、图书馆、工厂）；(2) `red`——The Refuge，7个地点（花园、城门、电梯层、公寓、咖啡馆、办公室、观景台）；(3) `green`——The Glen，8个地点（村庄、遗迹、森林、大门、码头、庭院、研究站、墓地）；(4) `blue`——The Barrens，9个地点（入口、前哨、悬崖、矿井入口、旧工厂、宿舍、虾沼泽、码头、瞭望点）。所有名称通过 `tr()` 包装支持翻译 |

### 6.3 脚本工具库

| 编号 | 文件 | 功能说明 |
|------|------|----------|
| 0097 | `Script.rb` | **通用脚本工具库（23KB，最大的定制脚本）**。`Script` 模块提供大量被事件指令调用的工具函数，分类如下：<br>**(A) 玩家名检测**：`is_name_swear`（脏话检测，从翻译表 `NAME_SWEARS` 读取）、`is_name_niko`/`is_name_like_niko`（名字是否为Niko/类似Niko）、`is_name_like_mom_dad`（类似父母称呼）、`is_name_gross`（令人不适的名字）。用于元叙事对话中根据玩家用户名做出不同反应<br>**(B) 暴力破解模拟**：`start_bruteforce`/`check_bruteforce`/`skip_bruteforce`/`bruteforce_vars`——模拟保险箱密码暴力破解，按帧计数生成5位数字密码的尝试进度（每2帧尝试一个组合，约63014帧=17.5小时"破解"完），结果写入变量26–30<br>**(C) 倒计时系统**：`countdown_over`/`countdown_extend_over`/`cdown_update`/`countdown_update`/`countdown_update_rue`——基于真实时间（2017年3月27日春分点）的倒计时，将天/时/分/秒拆解为单个数字写入变量101–110，用于游戏内"世界末日"倒计时显示。Rue版本使用6秒短倒计时<br>**(D) Niko倒影**：`niko_reflection_update`/`niko_reflection_enc_update`/`niko_reflection_peng_update`——控制名为"niko reflection"的事件镜像玩家移动（上下翻转、方向反转），三个版本对应不同地图的反射面边界约束<br>**(E) 玩家/事件位置工具**：`px`/`py`（带插值的逻辑位置计算）、`eve_x`/`eve_y`（按事件名查坐标）、`move_player`/`move_player_relative`（精确移动玩家并同步镜头和real坐标）、`set_cam`<br>**(F) 桌面文件操作（元叙事核心）**：`copy_journal`——将游戏内的Journal（三叶草/ clover）复制到用户文档目录，Linux下创建 `.desktop` 入口和图标；`create_boxes`——在文档目录创建 Portal1/2/3 和 BigPortal 文件夹；`put_key_in_box`——将NPC角色图和头像复制到对应Portal文件夹并写入密钥文本；`is_key_in_box`/`is_key_in_bigbox`——检查文件是否存在（玩家需要手动将文件移入文件夹）；`clear_boxes`——清理Portal文件夹；`password1`/`password2`——将密码提示图片复制到文档目录；`copy_file`/`copy_file_chmod`/`write_key`/`delete_if_exists`——文件操作工具<br>**(G) 临时变量**：`tmp_s1~s3`/`tmp_v1~v3`——写入开关/变量22–24，用于事件脚本间传递临时结果<br>**(H) 全局辅助函数**：`has_lightbulb?`、`button_pressed?`、`enter_name`、`check_exit`（出口区域判定）、`loadQASave`（加载QA测试存档）、`kill_perma_flags`、`bg`/`particles`/`ambient`/`clear_ambient`（地图设置快捷函数）、`enable_travel`/`disable_travel`/`unlock_map`（快速旅行快捷函数）、`watcher_tell_time`（按真实时间返回时段）、`plight_start_timer`/`plight_update_timer`（困境计时）、`activate_balcony?`（阳台交互判定） |

### 6.4 谜题系统

| 编号 | 文件 | 功能说明 |
|------|------|----------|
| 0098 | `Puzzle_Sokoban.rb` | **推箱子谜题（RAM完整性检查）**。`CORRECT_RAM_POSITIONS` 定义5个RAM模块（sokoram A–E）的正确坐标位置。`ram_integrity_check` 遍历当前地图所有名称匹配 `/^sokoram [ABCDE]$/` 的事件，检查其坐标是否在正确位置列表中，结果写入 `Script.tmp_s1`。这是Refuge工厂区的推箱子谜题——玩家需要将5个RAM模块推到正确位置以修复计算机 |
| 0099 | `Puzzle_Pixel.rb` | **像素画谜题（最复杂的谜题脚本）**。定义6套11x11像素图案：`CORRECT_PIXEL_PUZZLE`（5x5+额外一行的正确答案，X=暗/O=亮）、`BLANK_PXL_PZZLE`（全暗）、`S1~S5_PXL_PZZLE`（5个提示图案：竖线、圆环、半填充、单点、同心圆）。`pixel_puzzle_check` 检查5x5主谜题（坐标偏移31,34），将名为"pixel"的事件的自开关A状态与正确图案逐格比对。`puzzle_check(puzzle)` 检查11x11提示谜题（坐标偏移5,2），支持s1–s5五种图案。`pixel_puzzle_niko_correct(puzzle)` 在像素房间中寻找最近的亮格，将Niko传送到该位置（螺旋搜索算法）。`lightbulb_room_fix` 防止玩家离开像素房间边界。`pixel_puzzle_reset` 重置所有pixel事件的自开关 |
| 0100 | `Puzzle_Film.rb` | **胶片谜题**。`film_puzzle_begin` 创建一个全屏精灵显示 `numbersheet` 图片（胶片数字表），设置 `obscured=true`（mkxp-z的模糊/暗化属性），z=9999顶层，存入 `$game_temp.filmsprite`。`film_puzzle_end` 释放该精灵。这是Barrens矿井中的胶片谜题——玩家需要在暗化的数字表中找到密码 |
| 0101 | `Puzzle_Safe.rb` | **保险箱谜题（文档写入）**。`safe_puzzle_write` 从 `Languages/safetext/{langcode}/safe1.txt` 读取保险箱文档模板（英文为fallback），将玩家输入的密码（变量20）追加到文本末尾，写入用户文档目录的 `DOCUMENT.oneshot.txt`。`safe_puzzle_postgame_write` 同理但使用 `safe2.txt`（二周目版本）。这是OneShot元叙事机制的一部分——游戏将密码线索写入玩家的真实文档文件夹，玩家需要在游戏外打开文件查看 |

### 6.5 存档系统

| 编号 | 文件 | 功能说明 |
|------|------|----------|
| 0102 | `SaveLoad.rb` | **自定义存档/读档系统**。替代RGSS标准存档机制。<br>**存档**：`save` 函数（变量3为0时不保存，即序章未完成不存档）→ `write_save` 序列化14个全局对象到 `save.dat`（frame_count、game_system、switches、variables、self_switches、screen、actors、party、map、player、followers、oneshot、fasttravel、footstep_sfx）→ `write_perma_flags` 将开关151–175和变量76–100及玩家名序列化到 `p-settings.dat`（跨周目永久数据）→ 维护5级备份轮转（save1.bk→save2.bk→...→save5.bk删除）。`fake_save` 写入游戏目录下的 `save_progress.oneshot`（假存档，用于标题画面检测是否有进度）。`erase_game` 删除主存档<br>**读档**：`real_load` → `load(SAVE_FILE_NAME)` 反序列化所有对象，magic_number不匹配时重新setup地图，重建跟随者链（leader指针链式指向）→ `load_perma_flags` 恢复永久开关/变量/玩家名 → 恢复BGM/BGS（特定开关时不恢复，如梦境场景）→ 切换到Scene_Map → 触发公共事件42（非检查点存档时）→ 恢复壁纸。**损坏恢复**：`load` 和 `load_perma_flags` 均有 `rescue TypeError/ArgumentError` 机制，主存档损坏时依次尝试备份1–6，全部损坏则删除存档并abort退出。`save_exists`/`fake_save_exists` 查询存档存在性。`quit_game_bed`（床上睡觉存档退出）、`quit_game_no_save`（不存档直接退出） |

### 6.6 元叙事消息框系统

| 编号 | 文件 | 功能说明 |
|------|------|----------|
| 0103 | `Ed_Message.rb` | **Ed消息框（世界实体/God角色的消息）**。半透明黑色背景+居中白色文字，160px高度，最多4行，自动按词换行并居中对齐。支持 `\v[n]`（变量）、`\n[n]`（角色名）、`\p`（玩家名）、`\c[n]`（颜色）转义符。淡入淡出动画，ACTION/CANCEL/R键（开关253）关闭。通过 `$game_temp.message_ed_text` 触发。Ed是OneShot中引导玩家的"世界实体"角色，其消息使用与普通对话框不同的全屏居中样式 |
| 0104 | `Doc_Message.rb` | **文档消息框（可滚动纸张样式）**。使用 `lined_paper_blue`/`lined_paper_red` 图片作为背景（开关124切换红蓝），2倍缩放，模拟笔记本纸张。文字区域200x216，蓝色/红色墨水色，16px字体，支持上下滚动（`@y_offset`，滚动指示器箭头显示在右侧）。打开时播放翻页SE。通过 `$game_temp.message_doc_text` 触发。用于显示游戏内书籍、笔记、文档等长文本 |
| 0105 | `Desktop_Message.rb` | **桌面消息框（模拟操作系统弹窗）**。使用 `cg_desktop_messagebox` 图片作为背景（模拟桌面弹窗外观），2倍缩放，深紫色文字 `Color.new(44,37,54)`，居中对齐。打开时播放 `pc_messagebox.wav` 系统提示音。快速淡入淡出（每帧±200透明度）。通过 `$game_temp.message_desktop_text` 触发。用于模拟"游戏外"的系统弹窗消息，增强元叙事感 |
| 0106 | `Credits_Message.rb` | **制作人员名单消息框**。全屏黑/白背景（开关104切换），320x240文字区域2倍缩放居中。支持 `\l`（左对齐，x=16）和 `\r`（右对齐，自动计算右边界）转义符，用于制作人员名单的左右分栏布局。首行字体24px（标题），其余16px。150帧（2.5秒）后自动关闭。慢速淡入淡出（每帧±5）。通过 `$game_temp.message_credits_text` 触发。用于章节标题卡和制作人员名单展示 |

### 6.7 其他定制

| 编号 | 文件 | 功能说明 |
|------|------|----------|
| 0107 | `Particles.rb` | **粒子系统**。`Particle` 基类包装Sprite，提供x/y/scale/opacity属性，x/y超出屏幕边界时循环到对侧。`Particle_Firefly`（萤火虫）：使用 `firefly` 图片，随机相位/波长/速度，正弦函数控制透明度闪烁，additive混合（blend_type=1）。`Particle_Shrimp`（虾）：使用 `shrimp` 图片，随机角度/速度，每帧有概率改变方向或加速/减速，模拟浮游生物运动。`ParticleLayer` 粒子层：管理N个粒子实例，`update` 中根据地图滚动偏移调整所有粒子位置（实现粒子与地图视差同步），支持 `dispose` 批量释放。由 `$game_map.particles_type` 控制当前地图使用哪种粒子 |
| 0109 | `EdText.rb` | **编辑器文本/消息框工具**。`EdText` 模块提供 `info`/`yesno`/`err`/`blue_understand` 等方法，统一调用 `msgbox(type, text)`。`msgbox` 方法：(1) 如果全屏则先退出全屏（macOS延迟0.65s，其他0.2s）；(2) 对文本进行翻译预处理（去除未转义换行用于翻译查找，再去除转义换行用于显示）；(3) 在独立线程中调用 `Oneshot.msgbox`（mkxp-z的原生系统消息框），主线程持续 `Graphics.update` 避免卡死；(4) 支持 `\p` 玩家名替换。类型常量：`Oneshot::Msg::INFO`/`YESNO`/`ERR`。用于游戏运行中弹出系统级消息框（如存档损坏警告、错误提示） |

---

### 七、入口与工具

**整体职责**：游戏启动入口、RGSS模块扩展、演示模式脚本。

| 编号 | 文件 | 类型 | 功能说明 |
|------|------|------|----------|
| 0000 | `RPG.rb` | **RGSS模块扩展+OneShot定制** | `RPG::Cache` 模块扩展：(1) `character`——角色图加载时自动小写化文件名，开关160（Niko变为"en"形态，即世界之实体形态）时将"niko"开头的文件名替换为"en"；(2) `face`——头像加载时小写化，4月1日愚人节时将"niko"开头替换为"af"（愚人节特供头像），开关160时同样替换为"en"；(3) 新增缓存路径方法：`menu`（Graphics/Menus/）、`lightmap`（Graphics/Lightmaps/）、`light`（Graphics/Lights/）、`misc`（Graphics/Misc/）。`Tone` 类扩展：`+`（色调相加）、`*`（色调缩放）、`blank?`（是否为零值），用于环境光计算 |
| 0108 | `Demo.rb` | **OneShot定制** | 演示模式结局消息。`demo_entity_message` 函数连续弹出4个系统消息框：从 "[...Who am I kidding. Of course I don't.]" 到 "[I'm so tired.]" 到 "[Goodbye.]"，使用玩家名占位符 `\p`。这是演示版（Demo）的专属结局文本——世界实体对玩家告别 |
| 0110 | `Main.rb` | **RGSS标准+OneShot定制** | 游戏主入口。`at_exit` 钩子：退出时恢复壁纸（`Wallpaper.reset`），并在非调试/非事件运行/当前为地图场景时自动调用 `save` 保存。主流程：(1) 设置帧率60、默认字体大小20；(2) `Persistent.load` 加载跨周目数据；(3) 初始化 `$demo=false`、`$GDC=false`；(4) 创建 `Scene_Title` 标题场景；(5) `Oneshot.allow_exit false` 禁止窗口关闭（OneShot机制：游戏内特定时刻禁止玩家退出）；(6) 主循环 `while $scene != nil; $scene.main`；(7) 退出时 `Oneshot.exiting true`、过渡20帧、清空Journal、允许退出。`Errno::ENOENT` 异常处理：文件未找到时打印提示 |

---

### 附录：OneShot 核心机制总结

### 元叙事（Metafiction）机制
1. **玩家用户名获取**：`Game_Oneshot.get_user_name` 从操作系统读取用户名，游戏内角色直接称呼玩家
2. **桌面文件操作**：`Script.copy_journal`/`create_boxes`/`put_key_in_box`/`password1/2` 将游戏内物品（Journal程序、NPC图片、密钥文本、密码图片）写入玩家真实文档目录，玩家需要在游戏外操作文件来推进剧情
3. **壁纸更改**：`Wallpaper.set_persistent` 更改玩家桌面壁纸（需退出全屏）
4. **系统消息框**：`EdText.msgbox` 调用原生系统弹窗，模糊游戏内外边界
5. **文档写入**：`Puzzle_Safe` 将密码线索写入 `DOCUMENT.oneshot.txt`

### 跨周目持久化
- `Persistent`（语言设置）独立于存档
- `p-settings.dat` 存储开关151–175、变量76–100、玩家名，新周目自动恢复
- `persistent.dat` 存储语言偏好

### 存档安全
- 5级备份轮转（save1.bk–save5.bk）
- 损坏时自动尝试备份恢复，全部损坏则删除并退出
- 序章未完成（变量3=0）时不自动存档

### 定制渲染管线
- 光源系统（`Light` 精灵 + lightmap/intensity 着色器属性）
- 脚印/水花系统（随移动自动生成，渐隐动画）
- 粒子系统（萤火虫/虾，地图视差同步）
- 地图浮动文字
- 四种定制消息框样式

---

## 四、根目录工具脚本


> 分析范围：根目录 5 个工具脚本 + `_analyze/` 目录 80+ 个分析脚本
> 分析方式：纯静态代码阅读，未执行任何脚本
> 生成时间：2026-09-07

---

### 第一部分：根目录工具脚本（5 个）

### 1. `pack_xscripts.rb`

**功能描述**：将 `xscripts/` 目录下的明文 `.rb` 脚本文件打包回 RPG Maker XP 格式的 `xScripts.rxdata` 二进制文件。这是 mod 开发工作流的"编译"步骤——开发者编辑明文脚本后，用此脚本生成可被 mkxp 引擎加载的 rxdata 包。

**关键方法/逻辑**：
- 按文件名前缀的数字编号排序（`/\A(\d+)_/`），无编号的排到末尾（99999）
- 每个脚本条目结构为 `[magic=0, script_name, zlib_compressed_content]`
- 使用 `Zlib::Deflate.deflate` 压缩脚本源码
- 最终通过 `Marshal.dump` 序列化整个数组

**输入**：`xscripts/*.rb`（明文 Ruby 脚本，文件名格式 `NNNN_Name.rb`）

**输出**：默认 `OneShot/mods/mod/Data/xScripts.rxdata`，可通过 `ARGV[0]` 指定输出路径

**依赖库**：`zlib`、`fileutils`（标准库）

**依赖数据文件**：无（纯文件操作）

**使用场景**：修改 `xscripts/` 下的游戏脚本后，重新打包供 modshot patches 覆盖加载。是 mod 开发迭代的核心工具。

---

### 2. `unpack_xscripts.rb`

**功能描述**：`pack_xscripts.rb` 的逆操作——将 `xScripts.rxdata` 二进制文件解包为 `xscripts/` 目录下的明文 `.rb` 文件。用于从原始游戏数据中提取脚本进行阅读和修改。

**关键方法/逻辑**：
- 通过 `Marshal.load` 反序列化 rxdata 文件
- 每个条目 `[magic, script_name, compressed]`，用 `Zlib::Inflate.inflate` 解压
- 输出文件名格式为 `%04d_%s.rb`（4 位序号 + 脚本名）
- 优先读取 `.bak` 备份文件（若存在），避免污染原始数据

**输入**：默认 `OneShot/Data/xScripts.rxdata`（或 `.bak`），可通过 `ARGV[0]` 指定

**输出**：默认 `xscripts/` 目录，可通过 `ARGV[1]` 指定

**依赖库**：`zlib`、`fileutils`

**依赖数据文件**：`xScripts.rxdata`

**使用场景**：首次从游戏原始数据提取脚本、或从备份恢复脚本明文。与 `pack_xscripts.rb` 组成完整的解包/打包工作流。

---

### 3. `_dump_scripts.rb`

**功能描述**：轻量级脚本转储工具，将 `xScripts.rxdata` 中的所有脚本解压并写入 `_scripts_dump/` 目录。功能与 `unpack_xscripts.rb` 类似但更简化，文件名使用 3 位序号并对脚本名做安全字符替换。

**关键方法/逻辑**：
- 检测压缩标识（首字节 `0x78` 为 zlib 魔数），有则解压，无则直接使用
- 文件名：`%03d_%s.rb`，脚本名中非 `[0-9A-Za-z_.-]` 的字符替换为 `_`
- 无排序逻辑，按 rxdata 中的原始顺序输出

**输入**：`OneShot/Data/xScripts.rxdata`（硬编码路径）

**输出**：`_scripts_dump/` 目录

**依赖库**：`zlib`

**依赖数据文件**：`xScripts.rxdata`

**使用场景**：快速转储脚本用于一次性查阅。文件名以 `_` 开头，表明这是临时/调试脚本，不纳入正式工作流。

---

### 4. `_inspect_maps.rb`

**功能描述**：地图数据检查与安全落点生成工具。扫描游戏中所有地图，为每张地图确定一个"安全落点"（玩家传送/跳跃后站立的位置），并输出为 `jump_points.json`。这是自由跳跃（jump_map）功能的核心数据生成脚本。

**关键方法/逻辑**：
- 内联定义了完整的 RPG Maker XP 数据类（`Table`、`Color`、`Tone`、`RPG::Map`、`RPG::Event`、`RPG::Tileset` 等），用于 `Marshal.load` 反序列化
- **Table 解析**：`dim(int32) + x/y/zsize(int32) + cell_count(int32) + data(uint16[])`
- **落点策略（三级回退）**：
  1. 优先使用地图事件中 `code==201`（传送命令）的直接指定目标点（`method==0`）
  2. 无传送点则扫描地图 tile，找 `passages & 0x0F != 0 || passages & 0x80 != 0` 的可站立格
  3. 全无则标记 `x=-1, y=-1`
- 变量式传送（`method!=0`，map_id/x/y 为变量 ID）无法离线解析，标记为 nil 仍需地面扫描

**输入**：
- `OneShot/Data/Tilesets.rxdata`（图块集通行性表）
- `OneShot/Data/MapInfos.rxdata`（地图名称映射）
- `OneShot/Data/Map*.rxdata`（所有地图数据）

**输出**：`OneShot/mods/mod/jump_points.json`（JSON 格式，含地图 ID、名称、x/y 坐标、朝向）

**依赖库**：`json`、`zlib`（间接）

**依赖数据文件**：Tilesets.rxdata、MapInfos.rxdata、所有 Map*.rxdata

**使用场景**：为自由跳跃 mod 生成每张地图的安全传送点数据。文件名以 `_` 开头，是开发阶段的数据生成工具。

---

### 5. `_verify_jump.rb`

**功能描述**：验证 `jump_map.rb` 中 `load_maps` 过滤逻辑的正确性。读取 `jump_points.json`，模拟过滤规则，统计可跳跃地图数和被排除地图数，并打印详情。

**关键方法/逻辑**：
- **过滤规则**：
  - 坐标无效（`x < 0 || y < 0`）→ 排除（no-spot）
  - 地图名匹配 `/IGNORE|DEBUG|INTERNAL|UNUSED|\bTEST\b|^INIT$/i` → 排除（filtered）
- 输出三类统计：total in json、jumpable（可跳）、excluded（排除）
- 打印排除列表和前 20/后 5 个可跳地图

**输入**：`OneShot/mods/mod/jump_points.json`

**输出**：控制台打印（无文件输出）

**依赖库**：`json`

**依赖数据文件**：jump_points.json

**使用场景**：验证跳跃地图过滤结果是否符合预期，排查哪些地图被意外排除或包含。文件名以 `_` 开头，临时验证脚本。

---


---

## 五、分析工具脚本（_analyze/）分类概述

##：`_analyze/` 目录工具脚本（分类概述）

`_analyze/` 目录包含约 80 个 `.rb` 分析脚本、1 个 `.py` 脚本、3 个输出 `.txt` 文件，以及 `scripts/` 子目录（111 个解包游戏脚本片段）。这些脚本绝大多数是**一次性分析/调试工具**，用于逆向理解 OneShot 游戏的事件逻辑、通行性判定、传送链、剧情流程等，为 mod 开发（特别是自由跳跃功能）提供数据支撑。

### 共享基础设施

#### `oneshot_data.rb` — 共享数据加载模块（详细分析）

这是 `_analyze/` 目录中**唯一的可复用模块**，被大量分析脚本通过 `require_relative 'oneshot_data'` 引用。

**提供的方法**：

| 方法 | 功能 |
|------|------|
| `os_load_map(mid)` | 按地图 ID 加载 `Map%03d.rxdata`，返回反序列化的 `RPG::Map` 对象 |
| `os_load_tilesets` | 加载 `Tilesets.rxdata`，返回 `{tileset_id => passages_table}` 哈希，只保留有有效通行性数据的图块集 |
| `os_dir_passable(map, passages, x, y, d)` | 判断格 (x,y) 朝方向 d 是否可通行。遍历 z=0,1,2 三层 tile，检查 `passages[tile]` 的方向位（下=1/左=2/右=4/上=8），`0x0F` 为四向全阻挡 |
| `os_standable?(map, passages, x, y)` | 判断格是否可站立：四向中至少一个方向可通行，且坐标在地图范围内 |
| `os_event_blocker?(map, x, y)` | 检查同格是否有阻挡事件：非 through、图形非空、且页面条件无条件（switch1/2/variable/self_switch 均无效）的事件视为阻挡 |
| `os_safe_landing?(map, passages, x, y)` | 安全落点判定 = `os_standable?` + `!os_event_blocker?` |

**内联定义的类**：`Table`（mkxp 格式 uint16 数据解析）、`Color`、`Tone`、`Rect`（空壳 `_load`）、`RPG::Map`、`RPG::Event`、`RPG::EventCommand`、`RPG::Tileset` 等（仅 attr_accessor 桩，供 Marshal 反序列化）。

**常量**：`ROOT`（项目根目录）、`DATA`（`OneShot/Data` 路径）。

---

#### `rmxpm.py` — Python 版 Ruby Marshal 解码器

**功能**：纯 Python 实现的 Ruby Marshal 4.8 格式解码器，专门用于解析 OneShot/RPG Maker XP 的 `.rxdata` 数据文件，无需 Ruby 环境即可读取游戏数据。

**关键实现**：
- `rf(buf, pos)`：解码 Ruby Fixnum（整数），支持 0x00/0x01-0x7F/0x80-0x83（1/2/4/8 字节）/0x84-0xFF（负数）
- `rv(buf, pos, sym, depth)`：递归解码任意 Ruby 值类型，支持：
  - `0x22` String、`0x3A` Symbol(new)、`0x3B` Symbol link
  - `0x69` Fixnum、`0x6C` Bignum、`0x72` Regexp
  - `0x5B` Array、`0x7B` Hash、`0x49` IVar（编码包装）
  - `0x6F` Object（返回 `(class_name, ivar_dict)` 元组）
  - `0x00` nil、`0x54` true、`0x46` false、`0x3C` class、`0x3D` module、`0x6D` module/class of
- `load(path)`：入口函数，校验魔数 `\x04\x08`，预注册 `:EOS`/`:encoding` 符号
- 主程序：递归格式化打印解码结果，列表截断前 200 项，字符串截断 80 字符

**输入**：命令行参数指定的 `.rxdata` 文件路径

**输出**：格式化的解码结构打印到 stdout

**依赖**：Python 标准库 `sys`、`zlib`

**使用场景**：在没有 Ruby 环境时快速查看 rxdata 文件结构，或用于 Python 生态的数据分析流水线。

---

#### `scripts/` 子目录（111 个文件）

**性质**：从 `xScripts.rxdata` 解包出的游戏脚本片段，**非分析工具**。

- 文件命名：`NNN_offXXXXXX.rb`（3 位序号 + 原始数据中的字节偏移量）
- 共 111 个文件，总计约 622 KB
- 内容：OneShot 游戏的 RGSS 脚本源码，包括 `RPG::Cache` 扩展、`Window_*` 类、`Scene_*` 类等
- 用途：供分析脚本通过 `Dir.glob('xscripts/*.rb')` 或直接读取进行文本搜索（如 `_scan_intro.rb`、`_scan_splash.rb`、`_check_interp.rb` 等）

---

### 分类 1：公共事件（CE）分析工具

**整体目的**：分析 RPG Maker XP 的 `CommonEvents.rxdata` 公共事件系统，重点关注 trigger=1（自动执行）和 trigger=2（并行处理）的公共事件，以及它们在自由跳跃模式下的拦截/放行逻辑。OneShot 中 CE#9（"Exit Transition"）是出口传送链的核心，CE#42 是读档/开场逻辑。

| 文件 | 说明 | 临时脚本 |
|------|------|----------|
| `ce9_callers.rb` | 扫描所有地图事件，找出调用公共事件 #9（`code==117` 调 CE）的位置，同时列出 trigger=1 的 CE 名称 | 否 |
| `ce9_condition.rb` | 列出所有 trigger==1 公共事件及其触发条件（switch1/switch2/variable/self_switch） | 否 |
| `ce9_cond_dump.rb` | 精确 dump 公共事件 #9 的 condition 原始对象字段值 | 否 |
| `ce9_full.rb` | 打印 CE#9 完整命令列表（条件分支/设变量/传送/调CE/开关/脚本），并扫描所有地图中设置变量 6/7/9 的事件 | 否 |
| `ce9_raw.rb` | 原始反序列化公共事件，精确查看 #9 的 condition 结构（使用最小化类定义） | 否 |
| `inspect_ce_610.rb` | 分析公共事件 6/10（south exit 传送链）及其他传送相关 CE | 否 |
| `inspect_ce_parallel.rb` | 分析 trigger==2（PARALLEL）的公共事件及其命令内容 | 否 |
| `inspect_common_events.rb` | 找出所有 trigger==1（autorun）的公共事件 | 否 |
| `verify_ce_whitelist.rb` | 模拟 `JumpMapCommonEventPatch` 核心逻辑：自由模式下拦截 trigger=1 的 CE，仅放行白名单 `[9]`，验证拦截/恢复逻辑 | 否 |
| `_ce42_721.rb` | dump CE#42 命令列表 [700]-[735] 区间（结尾设置部分） | 是 |
| `_ce42_head.rb` | dump CE#42 命令列表 [0]-[92]（头部逻辑） | 是 |
| `_ce_names.rb` | 查看 CE#15 和 CE#42 的名称、trigger、switch_id | 是 |
| `_dump_ces.rb` | dump CE#1/2/9/15/40/42 的完整命令列表（过滤 code=0） | 是 |

---

### 分类 2：地图通行性/碰撞检测工具

**整体目的**：理解和验证 OneShot/mkxp 引擎的 tile 通行性判定逻辑。RMXP 通行性表 `passages[tile_id]` 是 uint16 位掩码：低 4 位 `0x0F` 分别对应下/左/右/上四个方向的阻挡位，`0x0F` 表示四向全不可通行。这些工具用于验证 `jump_points.json` 中落点的可通行性。

| 文件 | 说明 | 临时脚本 |
|------|------|----------|
| `check_pass.rb` | 检查 Tilesets passages 的真实数据格式（原始字节级验证） | 否 |
| `check_passability.rb` | 检查三张 Livingroom 地图（4/64/182）指定落点四周的可通行性，使用 mkxp Table 真实解析（int32 数据格式） | 否 |
| `scan_passability.rb` | 全量扫描所有可跳地图的落点是否可通行（mkxp Table 真实解析） | 否 |
| `check_tile_bits.rb` | 检查 start 点 (15,17) 及床区域的 tile ID + 通行性 bits 值 | 否 |
| `check_obs.rb` | RGSS1 Table 解码 + 分析 observation deck（瞭望甲板）落点通行性 | 否 |
| `check_move.rb` | 模拟玩家在 start（地图2）落点 (15,17) 四个方向的移动可行性，使用真实 Game_Character/Game_Event 通行性逻辑 | 否 |

---

### 分类 3：地图数据检查工具

**整体目的**：针对特定地图或特定数据结构进行验证性检查，包括 Table 序列化格式、事件列表属性、开关变量、触发器类型、旅行点等。多数是在开发过程中为确认某个假设而写的一次性检查脚本。

| 文件 | 说明 | 临时脚本 |
|------|------|----------|
| `check_bed.rb` | 精确检查地图2 (15,17) 及周围通行性（含事件图形阻挡） | 否 |
| `check_living.rb` | 从 jump_points.json 中筛选名称含 "living" 的地图及其落点 | 否 |
| `check_exits_type.rb` | 检查地图 2/3/5/119/120/225 中 exit/door/transfer 事件的类型（是否含 201 传送/check_exit 脚本/VAR6/117 调CE） | 否 |
| `check_table.rb` | 检查 Table 解析是否正确（对比地图2 vs 地图4） | 否 |
| `check_table2.rb` | 检查 Table 真实序列化格式（打印 `_load` 收到的原始 bytes） | 否 |
| `check_table3.rb` | OneShot/mkxp Table 正确解析验证（uint16 data，头格式 dim+sizes+cell_count+data） | 否 |
| `check_sw22.rb` | 检查开关 #22 相关逻辑（含 Input/Viewport/Sprite/Bitmap 等引擎类桩，模拟运行环境） | 否 |
| `check_trig.rb` | 查看地图事件的 trigger/页面属性（判断转移点事件的触发类型） | 否 |
| `check_travel_pts.rb` | 检查地图 4/120 中 FAST TRAVEL/unlock_map/enable_travel/check_exit 等旅行相关脚本调用 | 否 |
| `check_ev_list.rb` | 验证真实 Game_Event 是否有 `list` 方法 / 101（显示文字）检测方式 | 否 |
| `check_start_pass.rb` | 用正确解析检查 start (15,17) 四向通行性 + tile 386 的 bits 值 | 否 |

---

### 分类 4：地图转储/查看工具

**整体目的**：将地图数据以可读格式输出，或按特定条件筛选查看地图信息。包括通用地图 dump 工具、针对特定地图的深度检查、以及 jump_points.json 的查询工具。

| 文件 | 说明 | 临时脚本 |
|------|------|----------|
| `dump_map.rb` | 通用地图事件 dump 工具。用法 `ruby dump_map.rb Map004 [maxpages]`，打印地图尺寸、所有事件的名称/坐标/页数/每页 trigger/前 8 条命令码。内联完整 RGSS 类定义（含 `_dump`/`_load`） | 否 |
| `find_start.rb` | 从 jump_points.json 中查找名称为 "start" 或含 "start" 的地图，以及前 15 个可跳地图 | 否 |
| `rescan_points.rb` | 全量重扫 jump_points.json：用 RMXP 通行判定逻辑为每张地图重新找安全落点（内联 Table 类，uint16 数据解析） | 否 |
| `show_jp.rb` | 显示 jump_points.json 中指定地图（2/4/64/120/182/22/113）的落点数据 | 否 |
| `inspect_intro.rb` | 分析地图2 intro / Map Events 事件的完整命令 | 否 |
| `inspect_livingroom.rb` | 解析 Map004（Livingroom），重点关注事件触发器（autorun/parallel/player touch）和落点附近事件 | 否 |
| `inspect_lr_multi.rb` | 对比三张 Livingroom 地图（4/64/182）的事件结构 | 否 |
| `inspect_maps_2.rb` | 分析地图2（north door 传送目标）的事件 | 否 |
| `inspect_parallel.rb` | 分析地图 2/120 的 PARALLEL 事件命令（是否含 101 对话锁玩家） | 否 |
| `inspect_beds.rb` | 分析地图2 落点同格事件 bed bottom right (#4) 的命令 | 否 |
| `inspect_deck.rb` | 分析地图 120/225（observation deck）事件结构，重点：门/传送/出口事件 + 自开关页条件 | 否 |
| `inspect_deck120.rb` | 地图120 传送机制分析：mark/Map Events/south exit/FAST TRAVEL | 否 |
| `inspect_deck2.rb` | 地图225 EV001/EV004 完整命令 + 相关开关语义 | 否 |
| `inspect_doors.rb` | 分析门事件传送目标 + 目标地图 AUTORUN 的变量条件 | 否 |
| `inspect_exit_full.rb` | dump 地图120 south exit（EV#2）完整命令，并扫描全地图中读取变量 6/8/9 的传送逻辑 | 否 |

---

### 分类 5：传送/跳转分析工具

**整体目的**：分析 OneShot 中的传送（`code==201`）系统，包括直接传送和变量式传送，验证传送链的完整性，以及修正 jump_points.json 中的不安全落点。OneShot 大量使用变量 6/8/9 存储传送目标地图 ID/坐标，出口传送链通过 CE#9 串联。

| 文件 | 说明 | 临时脚本 |
|------|------|----------|
| `scan_ce_transfer.rb` | 扫描所有公共事件中的 201 传送命令、变量 6/9/8 判断、以及 117（调CE）链 | 否 |
| `scan_var_transfer.rb` | 找出用变量做传送目标的 201 事件（map_id >= 10000 表示变量 ID = map_id-10000），以及判断变量 6 的并行事件 | 否 |
| `verify_exit_chain.rb` | 综合验证瞭望甲板出口传送链 + 三个补丁（CE 白名单/地图事件拦截/玩家触发拦截）的放行逻辑 | 否 |
| `scan_landing.rb` | 扫描所有可跳地图的落点，检查同格/相邻是否有会触发的故事件（避免跳跃后立即触发剧情） | 否 |
| `verify_landings.rb` | 验证 jump_points.json 中所有落点的安全性（可站立 + 同格无事件），应用名称过滤规则 | 否 |
| `fix_landings.rb` | 修正 jump_points.json 落点：BFS 搜索移到最近安全位置（安全格=同格无事件+tile 至少1方向可通行+地图内） | 否 |
| `fix_landings2.rb` | 用正确通行性扫描+修正 jump_points.json 落点（安全格=可站立+同格无阻挡事件，不安全→BFS 最近安全格） | 否 |
| `fix_landings3.rb` | 严格修正 jump_points.json 落点 v3（安全格=可站立+同格无任何事件，避免站在床/家具/NPC 上） | 否 |
| `verify_points.rb` | 验证 jump_points.json 落点可通行性（复用完整 Table 类定义，独立运行不依赖 oneshot_data） | 否 |

---

### 分类 6：门/出口分析工具

**整体目的**：分析 OneShot 中的门/锁/出口事件机制。OneShot 的门事件通常包含对话（101）、条件分支（111）、开关控制（121）和传送（201），部分门通过 `check_exit` 脚本函数和变量 6 实现动态出口逻辑。

| 文件 | 说明 | 临时脚本 |
|------|------|----------|
| `scan_doors.rb` | 全量扫描 OneShot 地图事件，分析门/锁/对话/剧情机制。使用 mkxp 运行时 Ruby，内建类空壳供 Marshal 反序列化。输出到 `scan_doors_out.txt` | 否 |
| `scan_lock_switches.rb` | 扫描所有门/锁类事件引用的条件开关号 + 对话事件统计。输出到 `scan_lock_out.txt` | 否 |
| `inspect_doors.rb` | 分析门事件传送目标 + 目标地图 AUTORUN 的变量条件 | 否 |
| `inspect_exit_full.rb` | （与分类 4 交叉）dump 地图120 south exit 完整命令 + 变量 6/8/9 传送逻辑扫描 | 否 |
| `check_exits_type.rb` | （与分类 3 交叉）检查指定地图 exit/door/transfer 事件的类型特征 | 否 |

---

### 分类 7：冻结/补丁验证工具

**整体目的**：验证 `jump_map.rb` 中"冻结补丁"的有效性。自由跳跃模式需要在玩家浏览地图时冻结（暂停）所有地图事件和公共事件的执行，防止剧情自动触发。这些脚本通过逐步加载真实 xscripts 源码 + 模拟 Interpreter 来验证 TracePoint/prepend 补丁是否按预期工作。

| 文件 | 说明 | 临时脚本 |
|------|------|----------|
| `verify_freeze_patch.rb` | 验证 jump_map.rb 的冻结补丁（TracePoint prepend）是否生效。场景：load jump_map.rb 时 Game_Event 尚未定义（与真实加载顺序一致） | 否 |
| `verify_freeze_v2.rb` | v2：用真实 xscripts 源码验证冻结补丁。加载顺序与真实一致：先 load jump_map.rb（TracePoint），再 load 真实的 Game_Character/Game_Event 源码 | 否 |
| `verify_freeze_v3.rb` | v3：修改后的 jump_map.rb（冻结所有地图 + 公共事件拦截），用真实 Game_Character/Game_Event 源码 + 模拟 Interpreter 验证 | 否 |
| `verify_freeze_v4.rb` | v4：Game_Player 触发拦截补丁，用真实 Game_Character/Game_Event/Game_Player 源码验证玩家触发的事件也被冻结 | 否 |

---

### 分类 8：开场/剧情追踪工具

**整体目的**：逆向分析 OneShot 的开场（intro）/醒来（wake）/标题（splash）等剧情流程。这些脚本大多以 `_` 开头，是针对特定剧情段的一次性追踪工具，包括扫描 xscripts 源码中的关键词、dump 特定公共事件/地图事件的命令区间、以及分析运行时日志（skip_trace.log）。

| 文件 | 说明 | 临时脚本 |
|------|------|----------|
| `_opening_events.rb` | dump CE#42（Load Save）完整命令（重点结尾设置 SW198/190/306/121），以及 CE#42 结尾 [700-834] | 是 |
| `_opening_events2.rb` | 分析 map1 init 事件 [49]-[56]（调用 CE15 的条件），以及地图 2/188 的 intro 事件（含 241/250/245 声音命令） | 是 |
| `_scan_intro.rb` | 在 xscripts/*.rb 中搜索 "intro/Intro" 关键词，按文件分组显示命中行 | 是 |
| `_scan_wake.rb` | 在 xscripts 中搜索 "cg_wake/panorama" 关键词，并扫描所有地图的 panorama_name（远景图） | 是 |
| `_scan_splash.rb` | 在 xscripts 中搜索 "splash/logo/Asteristic/intro/Opening/wake/blackfade" 关键词 | 是 |
| `_scan_anim.rb` | 扫描所有地图事件的 207（动画）/221-225/355 命令，找非 231 的 CG 显示机制 | 是 |
| `_scan_pictures.rb` | 扫描所有 Scene 类（不确定，头部注释仅写 "1) 所有 Scene 类"） | 是 |
| `_scan_cg231.rb` | 扫描所有地图事件中 `code==231`（显示图片）且图片名含 "cg_wake" 的命令 | 是 |
| `_trace_2035.rb` | 从 `skip_trace.log` 中筛选时间戳含 "20:35:" 的日志行 | 是 |
| `_trace_2035b.rb` | 从 skip_trace.log 第 10675 行起筛选 "20:35:" 的日志（续查） | 是 |
| `_trace_cg.rb` | 从 skip_trace.log 中筛选 "instruction/cg_wake/felix/black/white" 相关行，并打印尾部 20 行 | 是 |
| `_trace_segment.rb` | 从 skip_trace.log 中筛选时间戳 "20:17-20:19" 的日志段 | 是 |
| `_map2_cg.rb` | 分析地图 2/188 中含 `cg_wake` 图片显示（code 231）的事件完整命令（过滤 231/235/106/105/101/112/413） | 是 |
| `_dump_map1_init.rb` | 重新 dump map1 init 事件完整命令，检查非 231 的 CG 路径（355 脚本调用等） | 是 |
| `inspect_intro.rb` | （与分类 4 交叉）分析地图2 intro / Map Events 完整命令 | 否 |

---

### 分类 9：后期游戏分析工具

**整体目的**：分析 OneShot 后期/结局区域的事件逻辑，包括瞭望甲板（observation deck，地图 120/225）、后记/结局地图（198/207/227/243）等。这些区域有复杂的多页事件和自开关条件，是自由跳跃功能中容易出问题的区域。

| 文件 | 说明 | 临时脚本 |
|------|------|----------|
| `scan_postgame.rb` | 找进入后记/结局地图（198/207/227/243）的传送事件及其前置开关条件。输出到 `scan_postgame_out.txt` | 否 |
| `inspect_deck.rb` | （与分类 4 交叉）分析地图 120/225 observation deck 事件结构 | 否 |
| `inspect_deck120.rb` | （与分类 4 交叉）地图120 传送机制分析 | 否 |
| `inspect_deck2.rb` | （与分类 4 交叉）地图225 EV001/EV004 完整命令 | 否 |
| `inspect_livingroom.rb` | （与分类 4 交叉）解析 Map004 Livingroom 事件 | 否 |
| `inspect_lr_multi.rb` | （与分类 4 交叉）对比三张 Livingroom 地图 | 否 |
| `inspect_maps_2.rb` | （与分类 4 交叉）分析地图2 事件 | 否 |
| `inspect_parallel.rb` | （与分类 4 交叉）分析地图 2/120 PARALLEL 事件 | 否 |
| `inspect_beds.rb` | （与分类 4 交叉）分析地图2 bed 事件 | 否 |

---

### 分类 10：数据/配置工具

**整体目的**：跨分类的辅助工具，包括共享数据模块（oneshot_data.rb）、Python Marshal 解码器（rmxpm.py）、xscripts 源码文本搜索、以及快捷键补丁验证。

| 文件 | 说明 | 临时脚本 |
|------|------|----------|
| `oneshot_data.rb` | 共享数据加载模块（详见上方"共享基础设施"），提供地图加载、通行性判定、安全落点检测等方法 | 否 |
| `rmxpm.py` | Python 版 Ruby Marshal 4.8 解码器（详见上方"共享基础设施"） | 否 |
| `_check_interp.rb` | 在 xscripts/*.rb 中搜索 `setup_common_event`/`@event_id=`/`common_event_id` 关键词，分析 Interpreter 对公共事件的处理逻辑 | 是 |
| `verify_shortcut_keys.rb` | 离线验证快捷键补丁（Ctrl+D 开发者设置 / Ctrl+J 跳跃）。加载 dev_settings.rb + jump_map.rb，用桩 Scene_Map/Input 验证 ShortcutKeysPatch 的 prepend 和快捷键触发逻辑 | 否 |

---

### 输出文件（非脚本）

| 文件 | 说明 |
|------|------|
| `scan_doors_out.txt` | `scan_doors.rb` 的输出结果 |
| `scan_lock_out.txt` | `scan_lock_switches.rb` 的输出结果 |
| `scan_postgame_out.txt` | `scan_postgame.rb` 的输出结果 |

---

### 总结

### 脚本性质分布

- **可复用模块**：1 个（`oneshot_data.rb`）
- **正式工具脚本**（非 `_` 开头）：约 55 个，涵盖 CE 分析、通行性检测、地图 dump、传送链分析、门扫描、补丁验证等
- **一次性调试脚本**（`_` 开头）：约 25 个，主要用于开场剧情追踪、特定 CE 区间 dump、日志分析等
- **外部语言工具**：1 个（`rmxpm.py`，Python Marshal 解码器）
- **解包数据**：`scripts/` 子目录 111 个游戏脚本片段

### 核心技术主题

1. **RPG Maker XP 数据格式逆向**：Table（uint16/int32 变体）、Marshal 序列化、rxdata 二进制结构
2. **通行性判定**：RMXP passages 位掩码（0x0F 四向阻挡）、多层 tile 优先级、事件阻挡
3. **传送系统**：201 命令直接/变量模式、CE#9 出口链、变量 6/8/9 动态目标
4. **自由跳跃 mod 开发**：jump_points.json 生成/验证/修正、事件冻结补丁、CE 白名单、快捷键
5. **剧情逆向**：开场 CE#42、intro/wake/splash 流程、CG 显示机制（231 命令）

### 依赖关系

- 大多数分析脚本依赖 `oneshot_data.rb`（`require_relative 'oneshot_data'`）
- 数据来源：`OneShot/Data/*.rxdata`（地图、图块集、公共事件、地图信息）
- 跳跃数据：`OneShot/mods/mod/jump_points.json`
- 脚本源码：`xscripts/*.rb`（用于文本搜索类脚本）
- 运行时：部分脚本使用 `runtime/bin/ruby.exe`（mkxp 内置 Ruby）或添加 `runtime/lib/ruby/3.1.0` 到 `$LOAD_PATH`

---

## 六、全局变量与配置汇总

### 6.1 config.json 配置项

| 配置键 | 类型 | 默认值 | 全局变量 | 控制功能 | 所属脚本 |
|--------|------|--------|----------|----------|----------|
| `skip_pictures` | bool | `true` | `$is_skip_picture` | 图片过场自动跳过 | picture_skip.rb |
| `quit_all_time` | bool | `true` | `$quit_all_time_enabled` | 随时打开菜单/退出 | quit_all_time.rb |
| `skip_dialogue` | bool | `false` | `$skip_dialogue_enabled` | 跳过所有对话文字 | skip_dialogue.rb |
| `skip_choice` | bool | `false` | `$skip_choice_enabled` | 自动选择第一个选项 | skip_dialogue.rb |
| `skip_uneasy` | bool | `false` | `$skip_uneasy_enabled` | 跳过 "Niko feels uneasy" 提示 | skip_dialogue.rb |
| `skip_event` | enum | `"off"` | `$skip_event_mode` | 事件跳过三态：off/block/fast | skip_event.rb |
| `always_travel` | bool | `false` | `$always_travel_enabled` | 事件/对话中允许 Ctrl+J 跳地图 | shortcut_keys.rb |
| `always_settings` | bool | `false` | `$always_settings_enabled` | 事件/对话中允许 Ctrl+D 开发者设置 | shortcut_keys.rb |
| `unshow_title` | bool | `false` | `$unshow_title_enabled` | 跳过标题界面直接进游戏 | title_screen.rb |
| `is_developer` | bool | `false` | `$dev_settings_enabled` | 显示开发者设置栏 + Ctrl+G 碰撞调试 | dev_settings.rb |

### 6.2 mod 全局变量清单

| 全局变量 | 设置者 | 读取者 | 用途 |
|----------|--------|--------|------|
| `$mod_config` | _config.rb | 所有配置读取脚本 | 配置哈希 |
| `$is_skip_picture` | picture_skip.rb, dev_settings.rb | picture_skip.rb | 图片跳过开关 |
| `$quit_all_time_enabled` | quit_all_time.rb, dev_settings.rb | quit_all_time.rb | 随时退出开关 |
| `$skip_dialogue_enabled` | skip_dialogue.rb, dev_settings.rb | skip_dialogue.rb | 对话跳过开关 |
| `$skip_choice_enabled` | skip_dialogue.rb, dev_settings.rb | skip_dialogue.rb | 选项自动选择开关 |
| `$skip_uneasy_enabled` | skip_dialogue.rb, dev_settings.rb | skip_dialogue.rb | uneasy 提示跳过开关 |
| `$skip_event_mode` | skip_event.rb, dev_settings.rb | skip_event.rb | 事件跳过模式 |
| `$jump_map_free_mode` | jump_map.rb | skip_event.rb | 自由浏览模式（跳关后激活） |
| `$always_settings_enabled` | shortcut_keys.rb, dev_settings.rb | shortcut_keys.rb | 事件中 Ctrl+D 允许 |
| `$always_travel_enabled` | shortcut_keys.rb, dev_settings.rb | shortcut_keys.rb | 事件中 Ctrl+J 允许 |
| `$unshow_title_enabled` | title_screen.rb, dev_settings.rb | title_screen.rb | 跳过标题开关 |
| `$dev_settings_enabled` | dev_settings.rb | debug_map.rb, dev_settings_patch.rb, shortcut_keys.rb | 开发者模式总开关 |
| `$dev_settings_instance` | dev_settings.rb | shortcut_keys.rb | 开发者设置窗口实例 |
| `$debug_map_overlay` | debug_map.rb | debug_map.rb | 碰撞调试图层实例 |
| `$title_screen_context` | title_screen.rb | title_screen.rb | 标题画面上下文标记 |
| `$skip_event_class_cache` | skip_event.rb | skip_event.rb | 事件分类缓存 |

### 6.3 prepend 链汇总

mod 脚本通过 `Module#prepend` 修改了以下原版方法，同一方法上的多个补丁按加载顺序形成调用链（后加载=更外层）：

#### Interpreter#execute_command（3 层补丁）

```
SkipEventFastForwardPatch (skip_event.rb, 最外层)
  └─ SkipAllDialoguePatch (skip_dialogue.rb)
      └─ PictureSkipPatch (picture_skip.rb, 最内层)
          └─ 原版 Interpreter#execute_command
```

**关键协作**：skip_dialogue 跳过 101 时主动清除 picture_skip 的 `@pic_skip_mode`（因为 picture_skip 看不到被吞掉的 101）。

#### Scene_Map#update（4 层补丁）

```
SkipEventCgCleanerPatch (skip_event.rb, 最外层)
  └─ ShortcutKeysPatch (shortcut_keys.rb)
      └─ QuitAllTimePatch (quit_all_time.rb)
          └─ DebugMapPatch (debug_map.rb, 最内层)
              └─ 原版 Scene_Map#update
```

**关键协作**：shortcut_keys 在 dev_settings 可见时 `return`，阻断内层 quit_all_time 和 debug_map 的执行（界面打开时暂停游戏）。

#### Game_Event（3 个补丁，不同方法）

| 方法 | 补丁模块 | 所属文件 |
|------|----------|----------|
| `start` | EventTwitchGuardPatch | event_twitch.rb |
| `update` | SkipEventParallelPatch | skip_event.rb |
| `check_event_trigger_auto` | SkipEventAutoRunPatch | skip_event.rb |

#### 其他 prepend 目标

| 目标类/方法 | 补丁模块 | 所属文件 |
|-------------|----------|----------|
| Window_Settings#open/update/dispose | WindowSettingsDevPatch | dev_settings_patch.rb |
| Interpreter#setup | SkipEventCommonEventPatch | skip_event.rb |
| Interpreter#clear | PictureSkipPatch#clear | picture_skip.rb |
| Scene_Title#main | TitleScreenMainContextPatch | title_screen.rb |
| Object#real_load | SkipEventRealLoadPatch | skip_event.rb（直接 Object.prepend） |
| Object#save_exists | TitleScreenSaveExistsPatch | title_screen.rb（直接 Object.prepend） |

### 6.4 非 prepend 的修改方式

| 目标 | 方式 | 所属文件 |
|------|------|----------|
| `Oneshot.allow_exit` | alias + define_singleton_method | quit_all_time.rb |
| `Input.quit?` | 临时 alias（super 期间） | quit_all_time.rb |

### 6.5 关键数据文件

| 文件 | 位置 | 用途 | 生成者 |
|------|------|------|--------|
| `config.json` | `OneShot/mods/mod/` | mod 功能开关配置 | 开发者手动 / dev_settings 写回 |
| `jump_points.json` | `OneShot/mods/mod/` | 每张地图的安全落点数据（跳地图用） | `_inspect_maps.rb` |
| `xScripts.rxdata` | `OneShot/mods/mod/Data/` | mod 覆盖用的游戏脚本包 | `pack_xscripts.rb` |
| `preload_loaded.txt` | `OneShot/mods/mod/logs/` | mod 加载日志 | mod.rb |
| `config_loaded.txt` | `OneShot/mods/mod/logs/` | 配置加载状态 | _config.rb |
| `skip_trace.log` | `OneShot/mods/mod/logs/` | 跳过功能运行时 trace | picture_skip/skip_dialogue/skip_event |

### 6.6 依赖关系总览

```
mod.rb (入口)
  ├─ 添加 $LOAD_PATH (runtime 标准库)
  └─ load 同目录 14 个 .rb (按字典序)
       ├─ _config.rb → $mod_config (最先加载)
       ├─ _patch_helper.rb → PatchHelper
       ├─ _status_log.rb → StatusLog
       ├─ [功能脚本] → 依赖 PatchHelper + StatusLog + $mod_config
       │    ├─ debug_map.rb → prepend Scene_Map#update
       │    ├─ dev_settings.rb → 定义 Window_DevSettings
       │    ├─ dev_settings_patch.rb → prepend Window_Settings
       │    ├─ event_twitch.rb → prepend Game_Event#start
       │    ├─ jump_map.rb → 定义 Window_JumpMap, 设置 $jump_map_free_mode
       │    ├─ picture_skip.rb → prepend Interpreter#execute_command
       │    ├─ quit_all_time.rb → prepend Scene_Map#update + alias Oneshot.allow_exit
       │    ├─ shortcut_keys.rb → prepend Scene_Map#update
       │    ├─ skip_dialogue.rb → prepend Interpreter#execute_command
       │    ├─ skip_event.rb → prepend 5个目标 + Object.prepend real_load
       │    └─ title_screen.rb → prepend Scene_Title#main + Object.prepend save_exists
       └─ 所有脚本 → StatusLog.write 写状态文件到 logs/
```

---

## 七、不确定事项汇总

以下内容在静态分析中无法完全确认，需运行时验证或对照更多资料：

1. **`modshot.json` 的 preloadScript 配置值**：当前文件中该配置被注释，实际运行时的入口配置需确认
2. **`Object.prepend` 的拦截效果**：`real_load` 和 `save_exists` 的实际定义位置决定了 `Object.prepend` 是否能正确拦截
3. **RPG Maker XP 命令码精确含义**：209/211/212/231 等命令码在 OneShot 定制版本中的精确语义
4. **`TracePoint.trace(:end)` 在 mkxp-z 环境下的行为**：是否与标准 CRuby 完全一致
5. **`tr()` 国际化函数的实现位置**：在 xscripts 的 i18n 模块中，但具体调用链需验证
6. **`jump_points.json` 的生成流程**：`_inspect_maps.rb` 可生成但是否为实际使用的生成脚本需确认
7. **战斗系统的实际使用情况**：OneShot 为纯解谜游戏，Game_Battler/Scene_Battle 等战斗相关脚本可能完全未被调用

---

*本文档基于 2026-09-07 的项目代码快照进行静态分析。所有标注"确定"的结论均有代码行级依据，标注"不确定"的内容需进一步验证。*
