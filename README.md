# ModShotEditer — OneShot 修改开发环境

> 基于 **ModShot**（mkxp-z 分支的 RGSS 兼容引擎）为游戏 **OneShot**（RPG Maker XP 解谜冒险游戏）搭建的一整套**修改/开发环境**：内置引擎、游戏本体、运行时补丁层（preload mod）、地图热重载同步工具与调试工具，全部代码无侵入式地以 `TracePoint + Module#prepend` 挂载，不修改游戏原始文件。

---

## 目录

1. [项目是什么](#1-项目是什么)
2. [技术栈](#2-技术栈)
3. [顶层目录结构](#3-顶层目录结构)
4. [快速开始](#4-快速开始)
5. [运行链路详解](#5-运行链路详解)
6. [引擎配置（modshot.json）](#6-引擎配置modshotjson)
7. [Mod 架构](#7-mod-架构)
8. [config.json 全部开关](#8-configjson-全部开关)
9. [快捷键总表](#9-快捷键总表)
10. [mod 脚本逐个详解（18 个）](#10-mod-脚本逐个详解18-个)
11. [游戏脚本 xscripts 全表（111 个）](#11-游戏脚本-xscripts-全表111-个)
12. [地图与数据](#12-地图与数据)
13. [地图同步工作流](#13-地图同步工作流)
14. [实时更新协议（live update）](#14-实时更新协议live-update)
15. [语言与本地化](#15-语言与本地化)
16. [日志体系](#16-日志体系)
17. [构建与运行时](#17-构建与运行时)
18. [开发工作流建议](#18-开发工作流建议)
19. [已知问题与注意事项](#19-已知问题与注意事项)
20. [许可证](#20-许可证)
21. [附录：核心术语](#21-附录核心术语)

---

## 1. 项目是什么

一句话概括：**这是一个可运行的 OneShot 修改研究/开发套件** —— 用开源的 ModShot 引擎直接跑游戏，引擎在加载原版游戏脚本（`Data/Scripts.rxdata`）**之前**先执行一份 preload 脚本层（`OneShot/mods/mod/Scripts/`），该脚本层在游戏类定义完成后用 `Module#prepend` 给游戏打补丁，实现跳对话、跳过场、飞行、跳地图、实时改图热重载等能力；配合 `sync_maps.ps1` 把 RMXP 工程里改好的地图同步进补丁数据层，游戏内无需重启即可看到修改结果。

项目的角色分层：

| 层 | 内容 | 位置 |
|---|---|---|
| 引擎层 | ModShot 可执行文件 + 配置 | `build/modshot.exe`、`build/modshot.json` |
| 运行时层 | 嵌入式 Ruby 3.1 标准库（使 preload 脚本能 `require 'json'` 等） | `runtime/` |
| 游戏层 | OneShot 游戏本体（数据/图形/音频/多语言）+ 解包脚本 | `OneShot/`、`xscripts/` |
| 补丁层 | 18 个 preload 脚本 + 配置 + 补丁数据 + 日志 | `OneShot/mods/mod/` |
| 工具层 | 地图同步脚本（手动/监听）、批处理入口、po 解析调试脚本 | `sync_maps.ps1`、`同步地图.bat`、`Languages/_parse_po.py` |

---

## 2. 技术栈

| 项 | 内容 |
|---|---|
| 游戏引擎 | **ModShot**（`mkxp-z` 分支，MKXP / RGSS 兼容开源引擎），C++ 构建（meson/ninja，release），GPL-2.0-or-later |
| 游戏 | **OneShot**（原版引擎即 MKXP 的一个 fork），RPG Maker XP 工程（`Game.rxproj` → RPGXP 1.03），脚本语言 **Ruby**（RGSS） |
| 脚本语言 | Ruby（游戏脚本 + mod 脚本均为 Ruby） |
| 嵌入式运行时 | Ruby 3.1.x 标准库 + gems，位于 `runtime/lib/ruby/3.1.0`（含 `x64-mingw64` 架构目录） |
| 脚本打包格式 | `.rxdata`（Ruby Marshal 序列化；地图、数据库、脚本存档共用此格式） |
| 补丁机制 | Ruby `TracePoint(:end)` 监听类定义完成 + `Module#prepend` 前置挂载（无侵入，不改原文件） |
| 配置格式 | JSON（引擎配置 `modshot.json`、mod 配置 `config.json`、跳点覆盖 `jump_points.json`（可选）） |
| 同步工具 | PowerShell 脚本（`sync_maps.ps1`）+ cmd 批处理（`同步地图.bat`），内部用 `robocopy /MIR` |
| 本地化 | 类 GNU gettext 的 `.po` 文件（crc32(msgid) → msgstr 查表），10 种语言 |
| 许可证 | 仓库 LICENSE 为 **GPL v2**；OneShot 本体引擎为 MKXP fork（GPL v3） |

---

## 3. 顶层目录结构

```
ModShotEditer/
├── modshot.exe.lnk          # 指向 build\modshot.exe 的桌面快捷方式
├── modshot.json             # 引擎配置【模板】：全注释的默认配置（所有选项被注释，未生效）
├── build/                   # ★ 引擎构建产物（meson 输出）
│   ├── modshot.exe          # ★ 实际运行的可执行引擎（游戏入口）
│   ├── modshot.json         # ★ 生效的引擎配置（gameFolder=../OneShot, patches=mods/mod）
│   ├── x64-msvcrt-ruby310.dll   # 引擎内嵌的 Ruby 3.1 运行时 DLL
│   ├── libgcc_s_seh-1.dll / libstdc++-6.dll / libwinpthread-1.dll  # MinGW 运行库
│   ├── .vs/ modshot.exe.p/ windows/   # 构建中间产物
│   └── meson-info/ meson-logs/ meson-private/  # meson 构建元数据（版本 2.0.0）
├── runtime/                 # ★ 嵌入式 Ruby 3.1 标准库 + gems
│   ├── bin/                 # ruby.exe / rubyw.exe / gem / irb / erb / 等工具 + 依赖 DLL
│   └── lib/ruby/3.1.0/      # 标准库（json、fileutils 等）+ x64-mingw64 架构目录
├── OneShot/                 # ★ 游戏本体（= 引擎 gameFolder）
│   ├── Game.exe             # 原版 RPG Maker 播放器（RGSS103J）
│   ├── oneshot.exe / _______.exe   # 旧版 MKXP 引擎可执行文件
│   ├── steamshim.exe / steam_api64.dll / steam_appid.txt  # Steam 集成
│   ├── Game.ini             # RGSS 配置：Library=RGSS103J.dll, Scripts=Data\Scripts.rxdata
│   ├── Game.rxproj          # RPG Maker XP 工程标记（内容: "RPGXP 1.03"）
│   ├── Data/                # 游戏数据：263 张地图 Map001-263 + 数据库 + 脚本包
│   ├── Graphics/            # 角色/脸图/图块/自动图块/图标/雾/日志/动画/标题等
│   ├── Audio/               # BGM(62) BGS(3) ME(13) SE(110)
│   ├── Fonts/               # Terminus TTF / HigashiOme Gothic / WenQuanYi Micro Hei 等
│   ├── Languages/           # 10 语言 .po 翻译 + internal 编译表 + safetext 谜题文本
│   ├── Wallpaper/           # 游戏"壁纸"特性资源（按语言分子目录）
│   ├── CREDITS.txt / README.txt
│   └── mods/mod/            # ★★ mod 层（见下）
├── xscripts/                # ★ 解包后的游戏脚本源码（111 个 .rb，0000-0110）
├── sync_maps.ps1            # ★ 地图同步工具（手动同步 / 自动监听 / 交互菜单）
├── 同步地图.bat             # sync_maps.ps1 的双击入口（中文菜单）
└── .gitignore / LICENSE     # GPL v2
```

### `OneShot/mods/mod/` —— mod 层详解

```
OneShot/mods/mod/
├── config.json              # ★ mod 全部开关（12 个键，详见 §8）
├── Scripts/                 # ★ preload 脚本目录（18 个 .rb，mod.rb 为入口）
├── Data/                    # ★ 补丁数据层：OneShot/Data 的镜像（同步工具维护）
│                             #   （游戏通过引擎 patches 配置优先加载这里的地图）
├── jump_points.json         # 跳点覆盖层（可选：存在才生效，落点缺省时动态计算）
├── settings/                # 运行时信号文件
│   ├── map_update.signal    #   ★ 热重载信号（时间戳 + 变化的 map id 列表 / ALL）
│   └── .gitkeep
├── backup/                  # 备份
│   ├── data_sync/<时间戳>/  #   ★ robocopy 同步前对补丁 Data 的整包备份
│   └── jump_points.backup{1,2,3}.json
└── logs/                    # ★ 运行时状态日志（18 个文件，详见 §16）
```

---

## 4. 快速开始

### 4.1 直接玩（带 mod 的游戏）

```bat
build\modshot.exe
```

或双击根目录 `modshot.exe.lnk`。引擎按 `build/modshot.json` 加载：游戏目录 `../OneShot`，补丁层 `mods/mod`，preload 脚本 `mods/mod/Scripts/mod.rb`。

> 注意：**不要**用 `OneShot\Game.exe`（原版 RGSS 播放器）或 RMXP 的 F12 测试来跑这个 mod —— preload 补丁只在 ModShot 引擎下生效（见 `sync_maps.ps1` 第 88 行注释 "Test the game with: build\modshot.exe (NOT RMXP playtest)"）。

### 4.2 在游戏内体验 mod 功能

- 按 **Ctrl+D** 打开「开发者设置」子界面（需 `is_developer: true`）—— 可实时切换全部布尔开关并写回 `config.json`；
- 按 **Ctrl+J** 打开「跳地图」（263 张地图书页式列表）；
- 按 **Ctrl+F** 切换飞行模式（Niko 穿墙 + 2 倍速 + 置顶显示 + FLY 徽标）；
- 按 **Ctrl+G** 打开碰撞/事件调试覆盖层（红=完全阻挡，橙=部分阻挡，蓝块=事件锚点+ID）。

### 4.3 改图 → 热重载（核心工作流）

1. 在 RMXP 工程（`OneShot/Data`）里编辑地图并保存；
2. 运行 `同步地图.bat` → 选 `[1]` 手动同步（或 `[2]` 自动监听）；
3. 回到游戏，当前地图被 **live_update** 自动热重载（不传送玩家），若玩家站在障碍物上会自动飞行脱困。

### 4.4 常用命令

```powershell
# 手动同步一次（备份 + 镜像 + 写 ALL 信号）
powershell -NoProfile -ExecutionPolicy Bypass -File sync_maps.ps1 -Mode Manual

# 自动监听（轮询 RMXP 保存，静默 3 秒后同步并写精确信号）
powershell -NoProfile -ExecutionPolicy Bypass -File sync_maps.ps1 -Mode Watch
```

> ✅ 已修复：`sync_maps.ps1` 的源/目标/备份路径已改为基于脚本自身位置（`$PSScriptRoot`）的相对路径，仓库移动到任何目录均可直接运行。详见 §13.3。

---

## 5. 运行链路详解

ModShot（mkxp-z）启动时的事件顺序：

```
build\modshot.exe
  │  读取 build\modshot.json
  │    gameFolder  = ../OneShot        （相对 exe 所在目录）
  │    patches     = ["mods/mod"]      （补丁层，优先于原游戏资源）
  │    preloadScript = ["mods/mod/Scripts/mod.rb"]
  ▼
① mod.rb（preload，在游戏脚本之前执行）
  │  1) 把 runtime/lib/ruby/3.1.0(+x64-mingw64) 加入 $LOAD_PATH
  │     （否则 require 'json' 会失败——引擎默认 $LOAD_PATH 只有 gameFolder）
  │  2) 按文件名 ASCII 排序 load Scripts/ 下所有 .rb（排除自身，共 17 个）
  │  3) 写 logs/preload_loaded.txt（记录加载清单与错误）
  ▼
② 按顺序执行 preload 脚本（_config → _patch_helper → _status_log → 各功能模块）
  │  各脚本读取 $mod_config，设置全局开关变量，
  │  并用 PatchHelper.install(...) 注册 TracePoint 监听器
  ▼
③ 引擎加载并执行 Data/Scripts.rxdata（游戏脚本，0110_Main.rb 为入口）
  │  游戏各 Class 定义完成时，②中注册的 TracePoint(:end) 触发，
  │  对目标类 Module#prepend 挂上补丁模块
  ▼
④ 游戏运行：Scene_Title → Scene_Map …（补丁已生效）
```

**关键点**：

- **preload 先于游戏脚本**：所以补丁脚本只能"注册监听"，等游戏类定义完成后再挂载，不能直接引用游戏类。
- **`_` 开头文件最先加载**：文件名按 ASCII 排序，`_config.rb` < `_patch_helper.rb` < `_status_log.rb` < 各功能模块，保证基础设施先就绪。
- **patches 目录的优先级**：引擎虚拟文件系统优先解析补丁层覆盖文件，所以 `mods/mod/Data/MapXXX.rxdata` 会覆盖 `OneShot/Data/MapXXX.rxdata`；这也正是"同步地图 → 热重载"能生效的机制。
- **实时更新信号**：live_update 每 5 帧读一次 `mods/mod/settings/map_update.signal`（真实磁盘路径，`File.mtime+size`，O(1)），检测到变化就 `load_data` 重载当前地图。

---

## 6. 引擎配置（modshot.json）

### 6.1 `build/modshot.json` —— 实际生效配置

```jsonc
{
  "gameFolder": "../OneShot",          // 游戏目录（相对 build\modshot.exe 所在目录解析）
  "dataPathOrg": "OneShotMods",        // 存档/设置目录的组织名（默认 "Oneshot"）
  "dataPathApp": "OneShotMod",         // 存档/设置目录的应用名（默认 "Oneshot"）
  "patches": [ "mods/mod" ],           // 补丁层：相对 gameFolder 解析，优先于原文件
  "preloadScript": [ "mods/mod/Scripts/mod.rb" ]  // 游戏脚本之前执行的 Ruby 脚本
}
```

- `dataPathOrg/dataPathApp`：引擎存放存档、键位绑定、`persistent.dat` 等游戏数据的目录；本仓库把它从默认的 `Oneshot/Oneshot` 改成 `OneShotMods/OneShotMod`，避免污染原版存档。
- `patches` 可加载文件夹、zip、RGSS 加密档案（PhysicsFS 支持格式），本仓库用文件夹 `mods/mod`。

### 6.2 根目录 `modshot.json` —— 配置模板

全文件由注释组成，所有选项保持默认值（未生效）。它是 ModShot 官方配置的完整参考文档。常用选项摘录：

| 选项 | 默认 | 说明 |
|---|---|---|
| `displayFPS` / `printFPS` | false | 窗口标题/控制台显示平均 FPS（运行时 F2 可切换前者） |
| `fullscreen` | false | 启动全屏（运行时 Alt+Enter 切换） |
| `fixedAspectRatio` | true | 保持宽高比，不拉伸 |
| `smoothScaling` | 0 | 放大插值：0 最近邻 / 1 双线性 / 2 双三次 / 3 Lanczos3 / 4 xBRZ(GPLv3 构建) |
| `winResizable` | false | 窗口可缩放 |
| `defScreenW/H` | 640×480 | 窗口初始尺寸（0=按 RGSS 版本默认） |
| `fixedFramerate` | 0 | 强制固定帧率（0=关闭） |
| `frameSkip` | false | 落后时跳帧 |
| `vsync` | true | 垂直同步 |
| `enableSettings` | true | F1 键位设置菜单 |
| `enableReset` | false | F12 软重置（RGSSReset） |
| `anyAltToggleFS` | false | 左/右 Alt+Enter 切全屏 |
| `solidFonts` | — | 禁用 alpha 混合的字体列表 |
| `pathCache` | true | 用小写路径索引资源（模拟 Windows 大小写不敏感） |
| `gameFolder` | exe 所在目录 | 游戏根目录；若以 `-DWORKDIR_CURRENT` 编译则相对当前工作目录 |
| `RTP` | — | 额外资源搜索路径（文件夹/RGSS 档案/zip） |
| `patches` | — | 类似 RTP，但优先于游戏目录加载，用于增量更新或 mod |
| `preloadScript` | — | 游戏脚本执行前运行的 Ruby 脚本数组 |
| `fontSub` | — | 字体替换表，如 `"Arial>Open Sans"` |
| `rubyLoadpath` | — | MRI 后端额外 `$LOAD_PATH` |
| `JITEnable` / `YJITEnable` | false | Ruby JIT 开关（YJIT 需 Ruby 3.1+） |
| `SESourceCount` / `BGMTrackCount` | 6 / 1 | OpenAL 音源/音轨数量 |
| `dumpAtlas` | false | 调试：导出图块集 atlas |
| `MKXPZ_WINDOWS_CONSOLE` | 环境变量 | Windows 调试模式控制台开关 |
| `MKXPZ_FOLDER_SELECT` | 环境变量 | 启动时手动选择游戏目录（仅 macOS） |

---

## 7. Mod 架构

### 7.1 统一配置加载（`_config.rb`）

所有 mod 脚本共享同一个 `mods/mod/config.json`。`_config.rb` 因文件名排序最先加载，把配置读入全局 `$mod_config`：

```ruby
$mod_config = JSON.parse(File.read(config_path))   # 容错后为 Hash
```

容错处理：
- **UTF-8 BOM**：PowerShell `Set-Content` 等工具会写入 BOM，Ruby `JSON.parse` 对 BOM 直接抛 `ParserError` —— 读取后 `force_encoding('UTF-8')` 并剥离 `\uFEFF`；
- 文件不存在 / 解析失败 / 非 Hash → 回退 `{}`；
- 各功能模块用 `default_config.merge($mod_config || {})` 取值，保证缺键时使用内置默认值。

### 7.2 统一补丁安装（`_patch_helper.rb`）

所有补丁统一走 `PatchHelper.install`，替代原来每个文件重复的 TracePoint 样板：

```ruby
PatchHelper.install('Scene_Map', methods: [:update]) do |k|
  k.prepend(FlyModeScenePatch)
end
```

语义（与原样板完全一致）：
- `TracePoint(:end)` 异步监听类定义结束事件；
- 目标类**定义完成**且**指定方法全部就绪**后才执行 block（通常 `k.prepend(补丁模块)`）；
- 触发后 `trace.disable` 停止监听；
- block 内任何异常被吞掉（不影响游戏启动）。

所有 mod 补丁的通用模式：

```ruby
module 某Patch
  def 某方法
    # 前置逻辑
    super   # 调用原版方法
  end
end
```

即用 prepend 实现"方法前置增强"，原版方法不受影响。

### 7.3 统一状态日志（`_status_log.rb`）

- `StatusLog.write(name, lines)`：写 `mods/mod/logs/<name>`（覆盖），记录开关值/配置/补丁方式/加载时间；
- `StatusLog.append(name, msg)`：追加带 `HH:MM:SS.mmm` 时间戳的 trace 行，供诊断（如 `skip_trace.log`、`live_update_trace.log`）；
- 内部异常全部吞掉（日志失败不影响游戏）。

### 7.4 全局开关变量约定

每个功能模块把对应配置键映射为全局变量，例如：

| 配置键 | 全局变量 | 定义文件 |
|---|---|---|
| `skip_pictures` | `$is_skip_picture` | picture_skip.rb |
| `quit_all_time` | `$quit_all_time_enabled` | quit_all_time.rb |
| `skip_dialogue` | `$skip_dialogue_enabled` | skip_dialogue.rb |
| `skip_choice` | `$skip_choice_enabled` | skip_dialogue.rb |
| `skip_uneasy` | `$skip_uneasy_enabled` | skip_dialogue.rb |
| `always_settings` | `$always_settings_enabled` | shortcut_keys.rb |
| `always_travel` | `$always_travel_enabled` | shortcut_keys.rb |
| `unshow_title` | `$unshow_title_enabled` | title_screen.rb |
| `is_developer` | `$dev_settings_enabled` | dev_settings.rb |
| `fly_mode` | `$fly_mode_enabled` | fly_mode.rb / live_update.rb |
| `live_update` | `$live_update_enabled` | live_update.rb |
| `skip_event` | `$skip_event_mode`（三态字符串） | skip_event.rb |

> 这样设计使**游戏内切换开关可即时生效**：dev_settings 的 `apply_global` 直接改这些全局变量，无需重启。

---

## 8. config.json 全部开关

当前 `OneShot/mods/mod/config.json` 的实际值：

```jsonc
{
  "skip_pictures": true,      // 跳过过场图片（含教学演出）
  "quit_all_time": true,      // 随时可退出/打开菜单（无视过场限制）
  "skip_dialogue": false,     // 跳过对话文字
  "skip_choice": false,       // 自动选第一个选项
  "skip_uneasy": true,        // 跳过读档的 "Niko feels uneasy." 提示
  "always_travel": true,      // 事件/对话进行中也可 Ctrl+J 跳地图
  "always_settings": true,    // 事件/对话进行中也可 Ctrl+D 开设置
  "unshow_title": true,       // 跳过标题界面，直接进游戏
  "is_developer": true,       // 开发者模式（解锁全部快捷键）
  "fly_mode": false,          // 飞行模式（可在游戏内 Ctrl+F 切换并写回）
  "live_update": true         // 实时更新（地图热重载 + 障碍物自动飞行）
}
```

完整开关清单（含可手写但当前未写入的键）：

| 键 | 类型 | 默认 | 作用 | 生效范围 |
|---|---|---|---|---|
| `skip_pictures` | bool | true | 跳过图片过场/教学演出（详见 picture_skip） | 补丁级 |
| `quit_all_time` | bool | true | 过场中也允许菜单键/退出键/窗口 X 关闭（详见 quit_all_time） | 补丁级 |
| `skip_dialogue` | bool | false | 跳过所有对话文字（101/401 整段） | 补丁级 |
| `skip_choice` | bool | false | 遇选项自动选第一个 | 补丁级 |
| `skip_uneasy` | bool | true | 只跳过读档提示 "Niko feels uneasy." 这一句 | 补丁级 |
| `always_travel` | bool | true | 事件运行中放行 Ctrl+J | 快捷键 |
| `always_settings` | bool | true | 事件运行中放行 Ctrl+D | 快捷键 |
| `unshow_title` | bool | true | 跳过标题界面（上下文敏感实现） | 补丁级 |
| `is_developer` | bool | true | 开发者模式：设置页显示「开发者设置」栏 + 解锁 Ctrl+D/J/F/G | 界面 + 快捷键 |
| `fly_mode` | bool | false | 飞行模式初始状态/常驻飞行基准 | 补丁级 |
| `live_update` | bool | true | 地图热重载 + 障碍物自动飞行总开关 | 补丁级 |
| `skip_event` | string | `"off"` | 三态：`"off"` 正常 / `"block"` 整体阻止演出事件（自由探索）/ `"fast"` 快进保留功能命令 | 补丁级 |

> 说明：`skip_event` 是**字符串三态键**，不显示在开发者设置界面（`ENUM_KEYS = {}` 已预留枚举机制但未启用），当前配置未含此键 → 实际为 `off`。需要时手动写入 `"skip_event": "block"` 或 `"fast"`。

### 配置写入顺序

`dev_settings.rb` / `fly_mode.rb` 写回 config.json 时保持固定键序（`skip_pictures → quit_all_time → skip_dialogue → skip_choice → skip_uneasy → always_travel → always_settings → unshow_title → is_developer → fly_mode → live_update`），未知键追加在尾部。

---

## 9. 快捷键总表

| 快捷键 | 功能 | 前置条件 | 文件 |
|---|---|---|---|
| `Ctrl+D` | 打开「开发者设置」子界面 | `is_developer: true`；事件运行中需 `always_settings: true` | shortcut_keys.rb |
| `Ctrl+J` | 打开「跳地图」 | `is_developer: true`；事件运行中需 `always_travel: true` | shortcut_keys.rb / jump_map.rb |
| `Ctrl+F` | 切换飞行模式 | `is_developer: true`；转场/传送中禁用 | fly_mode.rb |
| `Ctrl+G` | 切换碰撞/事件调试覆盖层 | `is_developer: true` | debug_map.rb |
| `F1` | 引擎键位设置菜单 | 引擎配置 `enableSettings` | 引擎内置 |
| `F2` | 窗口标题 FPS 显示 | 引擎内置 | 引擎内置 |
| `Alt+Enter` | 全屏切换 | 引擎配置 `anyAltToggleFS` | 引擎内置 |

> 输入 API：快捷键基于 mkxp-z 扩展 `Input.pressex?` / `Input.triggerex?`（接受 SDL scancode 符号如 `:LCTRL`、`:RCTRL`、`:D`、`:J`）；运行时若无该扩展则回退标准 `Input.press?(Input::CTRL)`，此时 Ctrl+字母快捷键不可用（状态日志 `shortcut_keys_status.txt` 会记录 API 探测结果）。

---

## 10. mod 脚本逐个详解（18 个）

按加载顺序（文件名 ASCII 排序）排列。`mod.rb` 为入口，其余 17 个由它 load。

### 10.0 `mod.rb` — preload 入口加载器

- **职责**：① 注入 runtime 标准库路径；② 自动加载同目录所有 `.rb`；③ 写加载日志。
- **关键实现**：
  ```ruby
  runtime_lib = File.absolute_path(File.join(script_dir, '..', '..', '..', '..', 'runtime', 'lib', 'ruby', '3.1.0'))
  # script_dir = OneShot/mods/mod/Scripts → 上溯 4 级到仓库根 → /runtime/lib/ruby/3.1.0
  $LOAD_PATH.unshift(runtime_lib)
  $LOAD_PATH.unshift(runtime_arch) if File.exist?(runtime_arch)   # x64-mingw64
  ```
- **容错**：单个脚本 load 失败记录到 `preload_loaded.txt` 的 errors 段，不中断其他脚本。
- **注意**：preloadScript 不支持通配符，新增脚本只需放入此目录，无需改引擎配置。

### 10.1 `_config.rb` — 统一配置加载器

- 见 §7.1。写 `logs/config_loaded.txt` 记录实际加载的配置快照。
- 自包含日志（不依赖 StatusLog，因为它自身先于 StatusLog 加载）。

### 10.2 `_patch_helper.rb` — 统一补丁安装工具

- 见 §7.2。

### 10.3 `_status_log.rb` — 统一状态文件写入工具

- 见 §7.3。

### 10.4 `picture_skip.rb` — 图片过场跳过

- **开关**：`skip_pictures`（默认 true）。
- **补丁**：`Interpreter#execute_command`（prepend）+ 拦截 `clear` 重置状态。
- **核心逻辑**（状态机式跳过模式）：
  - 遇到 `231`（显示图片）→ 进入跳过模式，返回 true（由 `Interpreter#update` 末尾统一 `@index += 1` 跳过）；
  - 跳过模式中按命令码分类：
    - `101` 对话 → **退出**跳过模式，正常执行（对话不能被吞）；
    - `112` 循环开始 → 跳到第一个 `413`（循环结束），整个教学循环自动跳过——解决"只跳图片会黑屏还得按键"和"跳 105 会死循环"两个问题；
    - 命中 `SKIP_CODES` → 跳过（return true，靠 update 的 +1 前进）；
    - 其他命令（条件分支/开关/传送/脚本）→ 正常执行，保持跳过模式；
    - 列表末尾 → `command_end` 结束事件。
- **SKIP_CODES**：`106`（等待）、`207/208/210/211/212/213/214/215`（图片显示/移动/删除/色调/旋转/透明）、`221-225`（背景/转场）、`232-236`（图片操作）、`241`（播放 BGM）。
- **关键陷阱（注释明确警告）**：
  - `105`（按键输入）**不能跳**——教学/等待按键的 `112 Loop + 105 + 111 判断` 依赖它，跳过会吞掉按键捕获导致死循环黑屏；
  - `209`（删除图片）**不能跳**——必须执行，否则图片永不消失残留覆盖屏幕（故 209 不在 SKIP_CODES 中）；
  - **不能手动 `@index += 1`**：`Interpreter#update` 在 `execute_command` 返回后统一 `@index += 1`，手动 +1 会叠加多跳，跳过被跳命令后的下一条逻辑命令（如 111/122/201）。
- 与 skip_dialogue 的联动：101 被 skip_dialogue 吞掉时，picture_skip 看不到 101 来退出跳过模式，会一路 `command_end` 提前截断含演出的事件——skip_dialogue 代为清除 `@pic_skip_mode` 解决。

### 10.5 `skip_dialogue.rb` — 跳过对话 / 自动选项 / 跳过 uneasy

- **开关**：`skip_dialogue`（101/401 文字）、`skip_choice`（102 自动第一项）、`skip_uneasy`（"Niko feels uneasy." 单句）。
- **补丁**：`Interpreter#execute_command`。
- **跳过对话**：把 `@index` 移到**最后一个 `401`**（保持在该行上），靠 update 的 +1 自然越过整段文字。**不能**跳到"第一个非 401"，否则 update 的 +1 会再越过一条；多行对话（101+401+401）必须这样才不会丢后续命令（如关自开关 123 / 给物品 126）。
- **跳过选项**：`@branch[0] = 0`（选择索引），后续 `402 (When[**])` 据此走第一个分支；同样不手动 +1。
- **uneasy 检测**：OneShot 的 101 把 face+文本合并进 `parameters[0]`（如 `"@ed [Niko feels uneasy.]"`，无独立 401 行），故先查 101 自身参数、再向后扫 401 行。
- **不跳过**：`103/104/105/106`（消息暂停/选择/按键/等待）——跳过会导致事件时序混乱、音效反复触发甚至死循环。

### 10.6 `skip_event.rb` — 事件跳过三态模式（最复杂）

- **开关**：`skip_event` = `"off" | "block" | "fast"`；另有自由浏览模式 `$jump_map_free_mode`（Ctrl+J 跳关后置 true）与 block 共用同一套规则。
- **事件分类** `skip_event_classify(map_id, event_id)`（带缓存）：
  - `map1 ev1 "init"`（开场总控）→ `:partial`：必须执行到 real_load 后终止，不能整体阻止（否则无法读档/开新档）；其演出命令由 execute_command 补丁在 block/fast 下跳过；
  - autorun(trigger 3) 或 parallel(trigger 4) **且第一页无条件** 且 **锁玩家特征** → `:block`；
  - 其余 → `:allow`。
- **锁玩家特征** `skip_event_lock_player?`：含 101 对话 / 105 按键输入 / 209/212 作用于玩家（参数[0] = -1）的移动路线 / 106 等待超过 5 次。
- **六个补丁**：
  1. `Game_Event#check_event_trigger_auto`：block 模式阻止锁玩家的 autorun 事件启动（玩家触发事件天然放行，不走此方法）；
  2. `Game_Event#update`：block 模式整体静止锁玩家的 parallel 事件（parallel 在 refresh 时创建独立子解释器，不走补丁 1）；
  3. `Interpreter#setup`：阻止演出类公共事件——`CE15 "Instructions"`（操作教学）与 `CE42 "Load Save"`（读档苏醒演出），覆盖三条路径：自动 trigger1 / `common_event_id 42`（real_load 设置）/ 手动 117 调用；
  4. `Interpreter#execute_command`：fast 模式全部事件、block 模式仅 map1 ev1，跳过演出命令 `101/401/102/105/106/230/231/232/209(-1)`（BGM 241 仅开场拦截），保留传送/开关/变量/调 CE/脚本等功能命令；**每帧限步** `FAST_MAX_STEPS_PER_FRAME = 60`，本帧跳满即返回 false 暂停下帧继续——事件跨帧完成，给 real_load 的场景切换留帧间隙，防一帧跑完事件覆盖读档状态；105 按键输入模拟"已按确认键"（设参数变量为 5）防依赖按键的 loop 死循环；
  5. `real_load`（Object.prepend）——**铁律（无条件生效，与模式无关）**：读档完成后立即清空主事件解释器 `map_interpreter.clear` + `@list = nil`，并清残留开场 CG、停开场 BGM。这是修复"重启后进度丢失"的核心：存档快照若带着运行中的 map1 ev1 解释器状态，事件流会从该状态继续跑到"新游戏"分支（传送 map2）覆盖读档位置；
  6. `Scene_Map#update`：每帧兜底清残留开场 CG（`CG_PICTURE_RE = /cg_wake|cg_tower|instruction|felix|cg_niko_in_bed|^black$|^white$/i`）+ 停止开场 BGM（`SomeplaceIKnow`）。

### 10.7 `quit_all_time.rb` — 随时退出 / 随时开菜单

- **开关**：`quit_all_time`（默认 true）。
- **两个层面**：
  1. **窗口 X 按钮**：覆盖引擎 C 方法 `Oneshot.allow_exit`——开启时始终传 `true`（原版过场中会调 `allow_exit(false)` 禁关闭）；
  2. **游戏内退出键/菜单键**：补丁 `Scene_Map#update`——
     - `Input.quit?` 时：设置 `common_event_id = 35`（公共事件"保存并退出"），临时把 `Input.quit?` 定义为返回 false 再 super（阻止 super 中的限制提示 "You cannot perform this action during cutscenes."），ensure 恢复原方法（即使 super 抛异常也恢复）；
     - 菜单键：忽略 `$game_system.menu_disabled` 与 `map_interpreter.running?` 两个限制，**保留**其余限制：消息窗口显示中、快速旅行/设置窗口打开中、`menu_calling`/`item_menu_calling` 进行中。

### 10.8 `title_screen.rb` — 跳过标题（方案 B：上下文敏感）

- **开关**：`unshow_title`（默认 true）。
- **背景**：旧方案 A 用 Object.prepend 全局劫持 `save_exists`，`unshow_title=true` 时永远返回 true，导致真实无存档时 map1 ev1 idx9 条件误判为真 → 执行 real_load 读不存在的存档 → 游戏卡住。
- **方案 B**：
  - 补丁 `Scene_Title#main`：进入时置 `$title_screen_context = true`（ensure 复位）；
  - `Object.prepend(TitleScreenSaveExistsPatch)`：`save_exists` 在"标题画面上下文 + unshow_title"时返回 true（跳过标题），其余场合走 super 原版 `FileTest.exist?(SAVE_FILE_NAME)` 真实检查。
- 原版 save_exists 位于 `0102_SaveLoad.rb:258`。

### 10.9 `fly_mode.rb` — Niko 飞行行走模式

- **开关**：`fly_mode`（初始状态；Ctrl+F 切换并写回 config.json）。
- **三个补丁**：
  1. `Scene_Map#update`：Ctrl+F 切换 + FLY 徽标同步（z=20000，全图层之上）；转场/传送中禁用切换；切换时置/恢复 `@always_on_top`（飞行中 Niko 显示在所有图层之上）；
  2. `Game_Player#passable?`：飞行时绕过碰撞判定，但**地图边界仍生效**（不飞出地图）；**保留传送/接触事件**——目标格存在可触发接触事件（trigger 1/2、非 over_trigger?）时视为不可通行，使 move_* 走原版 else 分支触发 `check_event_trigger_touch`（飞行不会让传送/门失效）；
  3. `Game_Player#update_move`：飞行时速度 = run 模式的 2 倍（开关 251 关闭时 run=4→5=32px/帧；251 反转时 run=3→4=16px/帧）。
- **生效范围**：`FlyMode.active?` 只在玩家自由行走时返回 true——转场、传送、地图事件解释器运行中、消息窗口、菜单、强制移动路线中均不生效，不干扰演出脚本。
- **与 live_update 的关系**：`live_update.rb` 也会读 `fly_mode` 作为"手动常驻飞行基准"。

### 10.10 `debug_map.rb` — 碰撞/事件调试覆盖层

- **快捷键**：Ctrl+G（需 is_developer）。
- **图层**：`DebugMapOverlay`，viewport z=250（在光照层 z=200 之上、图片层 z=500 之下）；640×480 加各多一列 32px（防镜头左移时右侧露白）。
- **显示内容**：
  - 碰撞：四向都不可通行 → 红色（不透明 90）；部分方向不可通行 → 橙色（70）；可通行 → 透明；
  - 事件：锚点格蓝色半透明块 + 事件 ID（同格多事件以 `|` 分隔）。
- **性能优化（A+B，注释明确说明这是 Ctrl+G 卡顿的根因修复）**：
  - A. 格子级重绘：以 `display_x/128, display_y/128` 为 key，只有镜头跨过整格才重绘；像素级滚动由 `@sprite.x = -(dx % TILE)` 补偿；
  - B. 可通行性静态缓存：换图时一次性计算全图 tileset 静态通行表（`rebuild_cache`），redraw 只查表；事件层用锚点索引 O(1) 判断。逻辑**完全复刻** `Game_Map#passable?`（`xscripts/0016_Game_Map.rb:359-388`）的 tileset 层判定（含 blank 三空层逻辑），精度零损失。
- 惰性创建：首次 Ctrl+G 才实例化（preload 阶段 Graphics 未初始化）。

### 10.11 `dev_settings.rb` — 开发者设置子界面（Window_DevSettings）

- **界面**：全屏不透明黑底（完全遮住下层设置窗口文字），viewport z=9999，标题字号 40。
- **内容**：`display_items` = 所有布尔开关（来自 config.json 的 bool 键）+ 三态枚举键（`ENUM_KEYS`，当前为空，预留）+ 固定功能条目（`EXTRA_ACTIONS`，当前为 `[:jump_map, "Jump Map"]`）。
- **分页**：`PAGE_SIZE = 8`，超出自动翻页；页码在右下角；UP/DOWN 页内移动（跨页自动重建），LEFT/RIGHT 翻页（页数 >1 时），保持页内相对位置。
- **切换即生效**：`toggle(i)` → 取反/循环 → `apply_global(key, val)`（11 键白名单显式赋值给全局变量）→ `$mod_config[key] = val` → `save_config`（固定键序 JSON 写回）→ 播放 SE → 重绘。
- **跳地图集成**：`open_jump_map` 创建 `Window_JumpMap`，`on_transfer` 回调关闭跳地图 + 开发者设置 + 外层设置窗口；**不能隐藏自身**（Window_Settings 的补丁只在 `@dev_settings.visible` 为 true 时才驱动其 update，否则界面冻结），靠 JumpMap 更高的 z（10000）盖住，视觉等效。
- **动作反馈**：`flash(msg)` 在底部显示 120 帧的提示。
- 全局实例 `$dev_settings_instance = self`，供快捷键补丁免 ObjectSpace 扫描直接引用。

### 10.12 `dev_settings_patch.rb` — 设置页「开发者设置」栏

- **补丁**：`Window_Settings#open/update/dispose`。
- **open**：先 dispose 清空旧 `@data_sprites`（**关键修复**：原版 open 每次新建 sprite 不清旧，反复进出设置页会残留堆积），再 super；若 `$dev_settings_enabled`，在列表最下方追加「开发者设置」栏（含 i18n 文本注册 `Language.register_text_sprite`）。
- **update**：若 `@dev_settings.visible` → 只驱动子界面并 return；否则 super；检测到光标在该栏 + ACTION → 创建/打开 `Window_DevSettings`（注入 `parent_settings = self`；经设置菜单打开时 `on_closed = nil`，按 CANCEL 只关子界面回到设置窗口，不误关设置窗口）。
- **dispose**：清理子界面实例并置 nil（防止复用已 dispose 的对象）。

### 10.13 `shortcut_keys.rb` — 全局快捷键（Ctrl+D / Ctrl+J）

- **前置**：`is_developer: true`；事件/对话运行中需 `always_settings`（Ctrl+D）或 `always_travel`（Ctrl+J）。
- **实现要点**：
  - 监听点：`Scene_Map#update` 开头（prepend）；
  - **界面打开时拦截**：若 dev_settings 可见（含 jump_map 子界面），直接 `ds.update + return`，不调用 super —— 事件解释器/玩家/地图/消息窗口全部暂停（事件不会在后台继续推进）；关闭后 super 恢复执行，事件从暂停处续跑；
  - **兜底驱动**：jump_map 可见但 dev_settings 不可见（异常残留状态）时直接驱动 jump_map，保证界面始终响应输入（ESC/确认都能收回），不冻结；
  - 打开方式：把 `Window_DevSettings` 实例挂到 `@window_settings` 的 dev_settings 槽位，设置窗口置可见（复用 Scene_Map 的"菜单屏蔽 + 玩家停止"逻辑，dev_settings 全屏盖住）；
  - 关闭：dev_settings 按 CANCEL → `on_closed` 回调恢复设置窗口（visible=false + 清槽位），不残留。
- 快捷键 API 见 §9 附注。

### 10.14 `jump_map.rb` — 跳地图界面（Window_JumpMap）

- **入口**：开发者设置中的「Jump Map」栏 / Ctrl+J 快捷键。
- **数据（2026-09 重构，不再依赖手工 JSON）**：
  - 地图列表：运行时读 `Data/MapInfos.rxdata`（惰性缓存），新增/改名/删除自动同步；与历史行为一致过滤放开，全量列出（263 张）；
  - 落点解析优先级（跳转确认时，`JumpPoints.landing`）：
    1. 可选覆盖层 `jump_points.json`（有效 x/y ≥ 0，人工微调）；
    2. **原游戏入口落点**——首次打开跳地图界面时预构建索引（`JumpPoints.entrances`，约 1-3s 一次性，缓存复用）：遍历全部地图事件页 + 公共事件，收集所有 `Transfer Player`（201 指令，即门事件/切换地图时玩家实际出现的位置）指向本图的坐标，取第一个仍可通行者；
    3. **地图中心**——中心格不可通行时 BFS 环形扩张找最近可通行格（`center_landing`）；
    4. 全图不可通行/读取失败 → 回退 (0,0)（live_update 自动飞行兜底）。
    通行判定由 `static_passable?` 完成（复刻 `Game_Map#passable?` tileset 层，与 debug_map.rb 同源）；入口索引构建失败自动降级为空索引（全部回退中心），不阻塞跳图界面。
- **界面**：全黑不透明底（z=10000，盖住 dev_settings 9999），书页式列表每页 10 条（`JUMP_MAP_PER_PAGE`），左右翻页、上下页内循环，页码 "当前页 / 总页数"；淡入淡出只作用于文字层（背景保持全黑，`Graphics.freeze` 冻结的是纯黑画面）。
- **传送链**（模仿原版 FastTravel）：
  ```ruby
  $game_temp.player_transferring = true
  $game_temp.player_new_map_id = @transfer_player[:id]
  $game_temp.player_new_x = ... ; player_new_y = ... ; player_new_direction = ...
  Graphics.freeze
  $game_temp.transition_processing = true
  $game_temp.transition_name = "black"
  ```
- **自由浏览模式**：`JUMP_MAP_FREEZE_AUTORUN = true` → 跳转成功置 `$jump_map_free_mode = true`，并清掉 transfer 过程中可能残留的地图事件解释器；该模式下 skip_event.rb 的事件级阻止规则生效（演出事件整体不启动，玩家自由行动），持续到游戏重启。
- **落点回退链**：覆盖层有效 → 入口落点（首个可通行）→ 地图中心（不可通行时 BFS 扩张）→ (0,0)；跳转后若仍不可通行（如事件层挡路），由 live_update 的障碍物自动飞行（@through）脱困。
- **异常兜底**：`update` 捕获所有异常写入 `jump_map_runtime.txt`（含 backtrace 前 6 行），绝不让界面因异常冻结。
- **地图定位**：打开时若当前地图在列表中则定位到对应页并选中。
- 运行时日志 `jlog`：记录 open/ACTION/fade_out/transfer/CANCEL 关键事件，用于定位"传送后不收回"类问题。

### 10.15 `event_twitch.rb` — "角色抽搐"防护

- **现象**：跳关后，部分"玩家接触触发 + 推玩家"事件（楼梯/门槛）会反复触发——玩家站在触发格上，事件 move route 试图推开玩家但方向不可达（墙/边界/跳关后状态错位）→ 移动失败 → 玩家没被推走 → 事件每帧反复触发 → 角色抽搐且玩家被"挡住"进不去。
- **修复**：对含"作用于玩家的 move route"（命令 209/212，参数[0] = -1）的事件做触发抑制：
  - 懒检测（`@twitch_guard_checked`）标记事件是否含推玩家命令；
  - `start`：若玩家位置与上次触发时相同（说明移动失败）→ 抑制（return，不 super）；否则记录位置并正常触发；
  - `update`：玩家主动移动（位置变化）→ 解除抑制。
- **补丁**：`Game_Event#start/update`。
- **不影响**：正常游戏（事件成功推走玩家 / 对话等非推人事件）不受影响。

### 10.16 `i18n_mod.rb` — mod 界面文本中文化

- **内容**：`MOD_TRANSLATIONS` 12 组中英对照（开发者设置/跳地图/11 个开关名）。
- **原理**：OneShot 的 `Language.set` 加载 `Languages/<lang>.po` 并重建 `@data(crc32(msgid) → msgstr)` 哈希，`tr()` 按 crc32 查表。本脚本在 `Language` 单例类定义完成后 prepend `set`，在 super（原版加载 .po）之后、仅当语言为 zh 系列（`zh_CN`/`zh_CHT`/`zh`）时把翻译注入 `@data`。
- **实现细节**：`Language.set` 是类方法（`class << self`），`PatchHelper` 的 `method_defined?` 只查实例方法，故用**独立 TracePoint** 挂单例类（`tp.self.singleton_class.prepend(...)`）。
- **不重复注入**：ON/OFF/Yes/No/Settings 等原版已翻译的键。
- 依赖：运行时 `tr()` 由游戏脚本 `0091_i18n_Language.rb` 提供。

### 10.17 `live_update.rb` — 实时更新：地图热重载 + 障碍物自动飞行

（详见 §14 协议说明，这里列实现要点）

- **开关**：`live_update`（总开关，热重载 + 自动飞行一并生效）；`fly_mode` 作为自动飞行恢复的基准。
- **主通道（信号）**：每 5 帧（`SIGNAL_POLL_FRAMES`，~83ms）检查 `mods/mod/settings/map_update.signal` 的 `File.mtime+size`（O(1)，真实磁盘路径不依赖虚拟 FS）；变化且命中当前地图 → `reload_map` → 成功后 `consume_signal` 更新游标（失败保留旧游标自动重试）。
- **兜底通道**：每 30 帧（`FALLBACK_CHECK_FRAMES`，0.5s）自检当前地图文件的 `mtime+size`（真实路径）；探测失败永久降级为 `load_data + Marshal.dump` 内容对比。信号机制失效时仍能秒级响应。
- **忙判定**：传送中/消息窗口/菜单可见/玩家移动中/事件解释器运行中 → 跳过本轮检测（等空闲再检）。
- **换图重置**：`map_id` 变化（传送/读档/初始）→ 重置基线、探测信号游标（**不重载**——避免"启动时残留信号"被误判而打断刚进图的开场演出）、复位自动飞行。
- **reload_map 的保真**：
  - 记录并恢复地图定制：bg/particles/ambient/wrap/pan_offset_y；
  - 记录并恢复 erased 事件（`@erased`）；
  - 记录重载前在跑的 parallel 事件 id（抑制窗口结束后按原 id 恢复）；
  - 钳制玩家坐标（地图可能缩小）并 `moveto` 重新居中；
  - 重建精灵组（复刻 `Scene_Map#transfer_player` 模式：dispose 旧 spriteset → 新建 `Spriteset_Map` → update）；
  - 抑制窗口（`SUPPRESS_FRAMES = 40` 帧 ~0.67s）内抑制 autorun(trigger3)/parallel(trigger4) 自动启动——map1 ev1 开场等演出不会被重放。
- **自动飞行状态机**：玩家站上障碍物（出界 或 四向全不可通行）→ `@through = true` 穿墙可走；走出障碍物 → 恢复基准（config `fly_mode` 的值）；手动飞行（Ctrl+F）接管时复位自动飞行不干预。
- **补丁**：`Scene_Map#update`（每帧 tick + 徽标同步）、`Game_Event#check_event_trigger_auto`（抑制自动触发）、`Game_Event#refresh`（清除 setup 期间创建的 parallel 解释器）。
- **限制**：重载过的地图，其 autorun/parallel 需离开地图（传送/跳图）或重启游戏后才恢复自动执行。

### 10.18 `_parse_po.py`（位于 Languages/，不是 mod 脚本）

调试辅助脚本：尝试 `utf-8-sig / utf-8 / gbk` 三种编码解码 `zh_CN.po`，打印文件大小、头部、前若干条 msgid/msgstr，用于排查 po 文件编码问题。✅ 已修复：路径改为基于脚本自身位置解析（`os.path.dirname(__file__)` + `zh_CN.po`），不再依赖机器路径。

---

## 11. 游戏脚本 xscripts 全表（111 个）

`xscripts/` 是游戏脚本的解包源码（编号 0000-0110，与 RMXP 脚本编辑器顺序一致），是 `Data/Scripts.rxdata` / `Data/xScripts.rxdata` 的可读形态（打包工具 `pack_xscripts.rb` 在注释中被引用，未包含在本仓库中，见 §19）。

### 11.1 数据层 Game_*（0000-0026）

| 文件 | 类/内容 | 说明 |
|---|---|---|
| `0000_RPG.rb` | `module RPG::Cache` + `Tone` | 资源缓存扩展：character/face 小写化、开关 160 把 niko 换 en、4 月 1 日愚人节换 af、菜单/光照/杂项缓存；Tone 的 +/* 运算与 blank? |
| `0001_Game_Temp.rb` | `Game_Temp` | 临时游戏状态（转场、传送、菜单调用、消息、prompt_wait、bgm_fadein 等） |
| `0002_Game_System.rb` | `Game_System` | 系统设置、BGM/BGS 播放与记忆、保存计数、魔法数、菜单禁用等 |
| `0003_Game_Switches.rb` | `Game_Switches` | 开关数组 |
| `0004_Game_Variables.rb` | `Game_Variables` | 变量数组 |
| `0005_Game_SelfSwitches.rb` | `Game_SelfSwitches` | 独立开关（"地图id,事件id" 键） |
| `0006_Game_Screen.rb` | `Game_Screen` | 屏幕色调/闪烁/震动、天气、图片管理 |
| `0007_Game_Picture.rb` | `Game_Picture` | 图片属性（位置/缩放/旋转/色调/透明） |
| `0008_Game_Battler_1.rb` | `Game_Battler` | 战斗者基础（属性、能力值） |
| `0009_Game_Battler_2.rb` | `Game_Battler` | 战斗者状态（HP/SP、状态效果） |
| `0010_Game_Battler_3.rb` | `Game_Battler` | 战斗者技能/行动 |
| `0011_Game_BattleAction.rb` | `Game_BattleAction` | 战斗行动 |
| `0012_Game_Actor.rb` | `Game_Actor` | 角色（等级/经验/装备） |
| `0013_Game_Enemy.rb` | `Game_Enemy` | 敌人 |
| `0014_Game_Actors.rb` | `Game_Actors` | 角色数据库访问 |
| `0015_Game_Party.rb` | `Game_Party` | 队伍（成员、物品、步数） |
| `0016_Game_Map.rb` | `Game_Map` | ★ 地图：tileset/视差/雾/事件、通行判定 `passable?`（mod debug_map 精确复刻其逻辑）、滚动、`setup`、地图定制（bg/particles/ambient/wrap/pan） |
| `0017_Game_CommonEvent.rb` | `Game_CommonEvent` | 公共事件 |
| `0018_Game_Character_1.rb` | `Game_Character` | 角色基础（坐标/方向/图案/移动） |
| `0019_Game_Character_2.rb` | `Game_Character` | 角色移动路线/跳跃 |
| `0020_Game_Character_3.rb` | `Game_Character` | 角色移动与碰撞 |
| `0021_Game_Event.rb` | `Game_Event` | ★ 地图事件：页判定 `refresh`、触发 `check_event_trigger_*`、解释器（mod 大量补丁目标） |
| `0022_Game_Player.rb` | `Game_Player` | ★ 玩家：移动/通行/触发事件（mod fly_mode 补丁目标） |
| `0023_Game_Oneshot.rb` | `Game_Oneshot` + `Wallpaper` | OneShot 定制：玩家名（系统用户名首词）、壁纸状态与持久化设置/重置 |
| `0024_Game_Light.rb` | `Game_Light` | 光照数据（文件名/强度/坐标） |
| `0025_Game_Follower.rb` | `Game_Follower` | 跟随者（领队链） |
| `0026_Game_FastTravel.rb` | `Game_FastTravel` | 快速旅行解锁数据 |

### 11.2 精灵层 Sprite_*（0027-0036）

| 文件 | 类 | 说明 |
|---|---|---|
| `0027_Sprite_Character.rb` | `Sprite_Character` | 角色精灵（动画、雾、透明） |
| `0028_Sprite_Battler.rb` | `Sprite_Battler` | 战斗者精灵 |
| `0029_Sprite_Picture.rb` | `Sprite_Picture` | 图片精灵 |
| `0030_Sprite_Timer.rb` | `Sprite_Timer` | 计时器精灵 |
| `0031_Sprite_Light.rb` | `Sprite_Light` | 光照精灵（OneShot 定制） |
| `0032_Sprite_Footprint.rb` | `Sprite_Footprint` | 脚印精灵（OneShot 定制，足迹系统） |
| `0033_Sprite_Footsplash.rb` | `Sprite_Footsplash` | 水花精灵（踩水花） |
| `0034_Sprite_MapText.rb` | `Sprite_MapText` | 地图上漂浮文本（OneShot 定制） |
| `0035_Spriteset_Map.rb` | `Spriteset_Map` | 地图精灵组（图块/视差/雾/角色/足迹/光/文本）——live_update 重建的目标 |
| `0036_FastTravel.rb` | `FastTravel` | 快速旅行界面（书页式菜单、传送链、按区域 ZONES 分组）——mod jump_map 的界面与传送链参考 |

### 11.3 窗口层 Window_*（0037-0069）

| 文件 | 类 | 说明 |
|---|---|---|
| `0037_Window_Base.rb` | `Window_Base` | 窗口基类（边框、文字绘制） |
| `0038_Window_Selectable.rb` | `Window_Selectable` | 可选项窗口基类 |
| `0039_Window_Command.rb` | `Window_Command` | 命令窗口 |
| `0040_Window_Help.rb` | `Window_Help` | 帮助窗口 |
| `0041_Window_Gold.rb` | `Window_Gold` | 金钱窗口 |
| `0042_Window_PlayTime.rb` | `Window_PlayTime` | 游戏时间窗口 |
| `0043_Window_Steps.rb` | `Window_Steps` | 步数窗口 |
| `0044_Window_MenuStatus.rb` | `Window_MenuStatus` | 菜单状态窗口 |
| `0045_Window_Item.rb` | `Window_Item` | 物品窗口 |
| `0046_Window_Skill.rb` | `Window_Skill` | 技能窗口 |
| `0047_Window_SkillStatus.rb` | `Window_SkillStatus` | 技能状态窗口 |
| `0048_Window_Target.rb` | `Window_Target` | 目标选择窗口 |
| `0049_Window_EquipLeft.rb` | `Window_EquipLeft` | 装备左侧窗口 |
| `0050_Window_EquipRight.rb` | `Window_EquipRight` | 装备右侧窗口 |
| `0051_Window_EquipItem.rb` | `Window_EquipItem` | 装备物品窗口 |
| `0052_Window_Status.rb` | `Window_Status` | 状态窗口 |
| `0053_Window_SaveFile.rb` | `Window_SaveFile` | 存档文件窗口 |
| `0054_Window_Settings.rb` | `Window_Settings` | ★ 设置窗口（mod dev_settings_patch 补丁目标：追加「开发者设置」栏、open 防 sprite 堆积） |
| `0055_Window_ShopCommand.rb` | `Window_ShopCommand` | 商店命令窗口 |
| `0056_Window_ShopBuy.rb` | `Window_ShopBuy` | 商店购买窗口 |
| `0057_Window_ShopSell.rb` | `Window_ShopSell` | 商店出售窗口 |
| `0058_Window_ShopNumber.rb` | `Window_ShopNumber` | 商店数量窗口 |
| `0059_Window_ShopStatus.rb` | `Window_ShopStatus` | 商店状态窗口 |
| `0060_Window_NameEdit.rb` | `Window_NameEdit` | 名字编辑窗口 |
| `0061_Window_NameInput.rb` | `Window_NameInput` | 名字输入窗口 |
| `0062_Window_InputNumber.rb` | `Window_InputNumber` | 数字输入窗口 |
| `0063_Window_Message.rb` | `Window_Message` | 消息窗口 |
| `0064_Window_PartyCommand.rb` | `Window_PartyCommand` | 队伍命令窗口 |
| `0065_Window_BattleStatus.rb` | `Window_BattleStatus` | 战斗状态窗口 |
| `0066_Window_BattleResult.rb` | `Window_BattleResult` | 战斗结果窗口 |
| `0067_Window_DebugLeft.rb` | `Window_DebugLeft` | 调试左侧窗口 |
| `0068_Window_DebugRight.rb` | `Window_DebugRight` | 调试右侧窗口 |
| `0069_Window_MainMenu.rb` | `Window_MainMenu` | ★ OneShot 主菜单（Scene_Map 使用） |

### 11.4 事件解释器 Interpreter（0070-0076）

| 文件 | 内容 |
|---|---|
| `0070_Interpreter_1.rb` | 解释器基类：setup/update/命令分发 `execute_command`（mod 补丁的核心目标） |
| `0071_Interpreter_2.rb` | 命令 101-134（对话/选项/开关/变量/传送/等待/公共事件/脚本等） |
| `0072_Interpreter_3.rb` | 命令 201-231（移动路线/图片/转场等） |
| `0073_Interpreter_4.rb` | 命令 232-250（图片操作/BGM 等） |
| `0074_Interpreter_5.rb` | 命令 251-302（BGM/数值输入/战斗/商店等） |
| `0075_Interpreter_6.rb` | 命令 303-412（战斗处理/循环/分支） |
| `0076_Interpreter_7.rb` | 命令 413-417（循环结束/分支结束） |

> mod 大量依赖本层：`execute_command`（picture_skip / skip_dialogue / skip_event）、`setup`（skip_event 公共事件拦截）、`clear`。

### 11.5 场景层 Scene_*（0077-0089）

| 文件 | 类 | 说明 |
|---|---|---|
| `0077_Scene_Title.rb` | `Scene_Title` | 标题画面（mod title_screen 补丁 `main`；含 Start/Settings/Exit/隐藏项、debug_tester 道具、标题 BGM、`save_exists` 判定决定是否跳过标题） |
| `0078_Scene_Map.rb` | `Scene_Map` | ★ 地图主场景（mod 补丁最多的类：quit/fly/debug/shortcut/live_update/skip_event 全部挂 `update`）。含游戏内计时器、消息窗口族、主菜单/物品菜单、快速旅行、设置窗口、黑屏转场、物品图标（四叶草闪烁）、公共事件 35（退出）处理 |
| `0079_Scene_Menu.rb` | `Scene_Menu` | 菜单场景 |
| `0080_Scene_Item.rb` | `Scene_Item` | 物品场景 |
| `0081_Scene_Skill.rb` | `Scene_Skill` | 技能场景 |
| `0082_Scene_Equip.rb` | `Scene_Equip` | 装备场景 |
| `0083_Scene_Status.rb` | `Scene_Status` | 状态场景 |
| `0084_Scene_File.rb` | `Scene_File` | 存档/读档场景基类 |
| `0085_Scene_Save.rb` | `Scene_Save` | 存档场景 |
| `0086_Scene_Load.rb` | `Scene_Load` | 读档场景 |
| `0087_Scene_End.rb` | `Scene_End` | 退出场景 |
| `0088_Scene_Name.rb` | `Scene_Name` | 改名场景 |
| `0089_Scene_Debug.rb` | `Scene_Debug` | 调试场景 |

### 11.6 OneShot 定制层（0090-0110）

| 文件 | 类/模块 | 说明 |
|---|---|---|
| `0090_Persistent.rb` | `LanguageCode` + `Persistent` | 跨存档持久数据：语言代码解析、语言持久化（`persistent.dat`）、Steam 语言探测、`zh_CN.ver` 强制中文 |
| `0091_i18n_Language.rb` | `Language` + `TrString` + `tr()` | ★ 翻译系统：`set` 加载 `Languages/<lang>.po`（按行解析 msgid/msgstr），`@data[crc32(msgid)] = msgstr` 查表；`loadFontMap` 读 `language_fonts.ini`；`register_text_sprite`/`reset_fonts` 语言切换字体刷新；`initialize_database` 把数据库名变成可翻译串（mod i18n_mod 的注入目标） |
| `0092_i18n_English.rb` | — | 英文语言兜底/定义 |
| `0093_Data_Item.rb` | `module Item` | ★ 物品合成表 `COMBINATIONS`（如 酒精+干树枝→湿树枝、相机+螺丝刀→镜头、胶棒+照片→粘性照片、锡罐+剪刀→按钮 等，含"不能合成"的结果项 100-104）与合成判定逻辑 |
| `0094_Data_Footsteps.rb` | — | 脚步声 SFX 表（按区域/地面类型映射 `step_*` 音效，含带概率的条目） |
| `0095_Data_SpecialEventData.rb` | `SpecialEventData` | 特殊事件数据：泳池等大型物体的碰撞偏移表（flags + collision 相对坐标） |
| `0096_Data_FastTravel.rb` | `FastTravel::Zone` | 快速旅行区域表：红区（The Refuge 地表/地下）、绿区（The Glen）、蓝区（The Barrens），每区列可旅行地点 |
| `0097_Script.rb` | `module Script` + 顶层函数 | ★ OneShot 事件脚本工具库：玩家/事件坐标取整、名字判定（脏话/Niko/像 Niko/像妈妈爸爸/恶心名）、暴力破解计时（2 分钟 × 63014 次）、物品全丢、密码纸复制（`Fogs/_/scenario{1,2}/<lang>/pw*.png` → 文档目录）、四叶草日记的桌面入口/盒子/钥匙（Portal1-3、BigPortal、keyB/G/R.txt）、倒计时（2017-03-27）、Niko 倒影镜像更新、临时开关/变量槽（TMP_INDEX=22）、相机、BGM 淡入、地图定制辅助函数（bg/particles/ambient/wrap/pan_offset_y）、快速旅行解锁、watcher 报时、plight 计时、阳台判定等 |
| `0098_Puzzle_Sokoban.rb` | 推箱子谜题 | 正确 RAM 位置表 `CORRECT_RAM_POSITIONS`、完整性校验写临时开关 |
| `0099_Puzzle_Pixel.rb` | 像素谜题 | 正确像素图矩阵 `CORRECT_PIXEL_PUZZLE`（5×6）、空白/各阶段模板（S1/S2… 11×11 布尔矩阵） |
| `0100_Puzzle_Film.rb` | 胶片谜题 | `film_puzzle_begin/end`：显示数字表图片（`numbersheet`，obscured 遮罩，z=9999） |
| `0101_Puzzle_Safe.rb` | 保险箱谜题 | 把解密文本写到用户文档目录 `DOCUMENT.oneshot.txt`（`Languages/safetext/<lang>/safe1.txt|safe2.txt` + 变量 20），普通/后日谈两个版本 |
| `0102_SaveLoad.rb` | — | ★ 存档系统：`SAVE_FILE_NAME`（save.dat）、`PERMA_FLAGS_NAME`（p-settings.dat，永久标记开关 151-175 + 变量 76-100 + 玩家名）、假存档（`save_progress.oneshot`）、5 层轮转备份（save1-5.bk）、`save`/`load`/`real_load`/`save_exists`（mod skip_event 铁律、title_screen 上下文、quit_all_time 公共事件 35 的落点） |
| `0103_Ed_Message.rb` | `Ed_Message` | Ed 的对话框（半透明黑底遮罩 + 文字区，viewport z=9999，淡入淡出） |
| `0104_Doc_Message.rb` | `Doc_Message` | 文档/信件对话框 |
| `0105_Desktop_Message.rb` | `Desktop_Message` | 桌面消息框（游戏内嵌"桌面"界面） |
| `0106_Credits_Message.rb` | `Credits_Message` | 制作人员字幕框 |
| `0107_Particles.rb` | `Particle` | 粒子系统（随机位置、环绕屏幕循环、速度/重力/生命期） |
| `0108_Demo.rb` | — | Demo 模式逻辑 |
| `0109_EdText.rb` | `module EdText` | 引擎级消息框（info/yesno/err/blue_understand，msgbox 全屏退出+对话框，恢复全屏） |
| `0110_Main.rb` | `Main` | ★ 主入口：`Persistent.load` → `Graphics.freeze` → `$scene = Scene_Title.new` → 主循环 `while $scene; $scene.main; end`；`at_exit` 自动存档（开关 99 / 解释器运行中 / 非 Scene_Map 时跳过） |

---

## 12. 地图与数据

### 12.1 `OneShot/Data/`（279 个 .rxdata）

- **263 张地图**：`Map001.rxdata` ~ `Map263.rxdata`（RGSS Marshal 序列化的 RPG::Map 对象）。
- **16 个数据库/脚本文件**：`Actors / Animations / Armors / Classes / CommonEvents / Enemies / Items / MapInfos / Scripts / Skills / States / System / Tilesets / Troops / Weapons / xScripts`。
- 全部按 RGSS 标准 `load_data` 加载，由 `Data/MapInfos.rxdata` 提供地图名/父级/顺序信息。

### 12.2 补丁数据层 `OneShot/mods/mod/Data/`

- 由 `sync_maps.ps1` 用 `robocopy /MIR` 从工程 `OneShot/Data` 镜像而来（**排除** `Scripts.rxdata` 与 `xScripts.rxdata`——脚本走 `xscripts\` + 打包工具管理）。
- 引擎配置 `patches: ["mods/mod"]` 使该目录优先级高于原 `Data/`，因此**同步后的地图立即被游戏加载**（结合 live_update 无需重启）。
- `live_update.rb` 的兜底检测路径就是这里：`mods/mod/Data/Map%03d.rxdata`（真实磁盘路径）。

### 12.3 跳点覆盖层 `jump_points.json`（可选）

> 2026-09 起 jump 机制已重构为**动态数据源**（地图列表 = MapInfos；落点 = 覆盖层 → 原游戏入口落点（全图 201 传送指令索引）→ 地图中心），本文件降级为**可选覆盖层**：存在才被读取，且仅对其中"有有效落点（x/y ≥ 0）"的条目生效；缺失/无效条目自动回退动态落点。删除本文件后功能完全自洽（全动态）。

- 原格式：263 条（id 1-263），每条 `{ "name": 地图名, "x": 落点 x, "y": 落点 y, "dir": 朝向 }`，name 字段现已冗余（列表名取自 MapInfos）；
- 保留它的意义：继续沿用旧数据里的人工落点（如特定出生/剧情位置），避免跳转位置变化；
- `backup/jump_points.backup{1,2,3}.json` 为历史备份，当前 jump_map.rb 只读不写。

### 12.4 音频资源（4 个目录、188 个文件）

| 类别 | 数量 | 说明 |
|---|---|---|
| BGM | 62 | `.ogg` 为主（1 个 `puzzle-solved-remix.wav`）；Nightmargin 作曲，含钢琴变奏（`*_piano`）、扩展版（`NavigateExtended`/`SonderExtended` 等）、氛围（`ambience1-4`） |
| BGS | 3 | 背景音（robot_room.mp3 / teleport_boop.wav / tv_static.ogg） |
| ME | 13 | 音乐效果（get_item / phone_dialtone / sheep_victory 等） |
| SE | 110 | 音效（step_* 脚步声系 / door / elevator / camera / robot / cat / menu 等） |

### 12.5 图形资源（`OneShot/Graphics/`）

- `Characters/`（角色行走图，含 niko/en 双版本与 `it/ru` 语言子目录、DOORS、portal、roomba、vehicle 矿车/船等）
- `Faces/`（脸图：niko/en 全表情系、乔治 6 兄弟、cedric、alula、calamus、rue、silver、proto 等）
- `Tilesets/`、`Autotiles/`（图块：红/绿/蓝/起点四区域 + 塔 + 废墟等）
- `Icons/`（物品图标：镜头/电池/日记/按钮/照片等 + 多语言子目录）
- `Fogs/_/scenario1|2/<lang>/pw*.png`（密码纸，多语言）、`Fogs/fog.png`
- `Journal/`（四叶草日记封面/条目位图，多语言）、`Animations/`、`Lightmaps/`、`Lights/`、`Menus/`、`Misc/`、`Panoramas/`、`Titles/`、`Wallpaper/`（按语言）
- `Fonts/`（TerminusTTF-Bold、HigashiOme-Gothic、SourceHanSansHWSC、wqy-microhei）

---

## 13. 地图同步工作流

### 13.1 `sync_maps.ps1`（三种模式）

```
同步地图.bat（双击）→ powershell -NoProfile -ExecutionPolicy Bypass -File sync_maps.ps1
                      └─ 交互菜单: [1] 手动同步  [2] 自动监听  [3] 退出
```

**模式 1：手动同步（Sync-Manual）**
1. 备份当前补丁 Data 到 `backup/data_sync/<时间戳>/`（robocopy /E）；
2. `robocopy /MIR` 镜像工程 Data → 补丁 Data（`/XF Scripts.rxdata xScripts.rxdata`，排除脚本；`/R:2 /W:1` 重试 2 次等待 1s）；
3. 写 `settings/map_update.signal`（行 1=时间戳，行 2=`ALL`）→ 游戏内热重载全部命中。

**模式 2：自动监听（Start-Watch）**
- 每 800ms 轮询工程 Data 的 `*.rxdata`（按文件名记录 `LastWriteTimeUtc.Ticks + Length`）；
- 检测到变化 → 静默 3 秒（捕获静默期内再次保存）→ 再次对比 → 镜像同步 → 写**精确信号**（只含变化的 map id 列表，逗号分隔）；
- 循环直到关窗。

**模式 3：交互菜单**：数字选择上述模式。

### 13.2 信号写入（Write-Signal）

- 内容格式：
  ```
  20260913_101227_185       ← 行1: yyyyMMdd_HHmmss_fff 时间戳
  2                         ← 行2: 'ALL' 或逗号分隔的 map id（如 "2,17,31"）
  ```
- 无匹配的 `Map(\d{3}).rxdata` 文件名时跳过写入。
- 实时示例（当前仓库 `settings/map_update.signal`）：`20260913_101227_185` / `2` —— 表明最近一次同步命中地图 2。

### 13.3 ✅ 相对路径方案（已修复原硬编码问题）

原版 `sync_maps.ps1` 第 24-26 行把 `$src/$dst/$bak` 硬编码为 `C:\Users\Qyxay\Desktop\onehsot\ModShot-mkxp-z\...`（旧机器路径），与本仓库位置不一致，直接运行报 `[ERROR] Source not found`。

现改为基于**脚本自身位置**的相对路径，仓库可整体移动/复制到任意目录：

```powershell
$root   = $PSScriptRoot                           # 仓库根（脚本与 OneShot/ 同级）
$src    = Join-Path $root 'OneShot\Data'          # 工程数据（源）
$dst    = Join-Path $root 'OneShot\mods\mod\Data' # 补丁数据层（目标）
$bak    = Join-Path $root 'OneShot\mods\mod\backup\data_sync'
$sigDir = Join-Path $root 'OneShot\mods\mod\settings'   # 信号目录（原为 Join-Path $dst '..\settings'，语义等价）
```

- `$PSScriptRoot` 在 PowerShell 3.0+ 中始终为脚本所在目录的绝对路径（通过 `同步地图.bat` 或 `-File` 方式运行均正确解析），不依赖当前工作目录；
- 信号文件路径不变：`mods/mod/settings/map_update.signal`（live_update.rb 的检测路径无需改动）。

---

## 14. 实时更新协议（live update）

### 14.1 架构（事件驱动，双冗余，不做地图文件轮询）

```
[RMXP 工程 OneShot\Data]  ←改图并保存
        │
        │  sync_maps.ps1 (Manual/Watch) robocopy /MIR
        ▼
[补丁层 OneShot\mods\mod\Data\MapXXX.rxdata]
        │
        │  写入 settings\map_update.signal（时间戳 + map id 列表 / ALL）
        ▼
[游戏内 live_update.rb]（Scene_Map#update 每帧钩子）
    ├─ 主通道: 每 5 帧(~83ms) 查信号文件 File.mtime+size (O(1), 真实路径)
    │    变化且命中当前地图 → load_data 热重载 → consume_signal 更新游标
    └─ 兜底通道: 每 0.5s 自检当前地图文件 mtime+size（失败降级内容对比）
          变化 → 同样热重载
```

### 14.2 热重载行为（reload_map）

| 方面 | 行为 |
|---|---|
| 玩家 | 不传送；坐标越界自动钳制回地图内，镜头重新居中 |
| 地图定制 | 恢复 bg / particles / ambient / wrap / pan_offset_y |
| 事件状态 | 恢复 erased 事件；重载前在跑的 parallel 事件在抑制窗口结束后按原 id 恢复 |
| 演出 | 重载后该地图会话内抑制 autorun(trigger3)/parallel(trigger4) 自动启动（开场不会被重放） |
| 精灵组 | dispose 后重建（复刻 transfer_player 模式） |
| 失败处理 | 重载失败保留旧游标/元数据，自动重试；所有异常吞掉不影响主流程 |

### 14.3 障碍物自动飞行

- 玩家站上障碍物（出界 或 脚下四向全不可通行）→ `@through = true`（穿墙可走），日志 `FLY ON (player on obstacle)`；
- 走出障碍物（任一方向可通行）→ 恢复基准模式（基准 = config 的 `fly_mode`：true=常驻飞行，false=正常），日志 `FLY OFF (restored base=…)`；
- 手动飞行（Ctrl+F）开启时接管，自动飞行状态复位不干预。

### 14.4 忙判定（不重载的时机）

传送中 / 消息窗口显示 / 菜单可见 / 玩家移动中 / 地图事件解释器运行中 → 跳过本轮检测，空闲后再检。

### 14.5 信号检测降级链

1. `File.mtime + File.size`（快速，O(1)）——首选；
2. 失败 → 读文件内容对比（同样 O(1)）；
3. 信号文件首次出现（运行中创建）→ 视为变化。

---

## 15. 语言与本地化

### 15.1 语言文件（`OneShot/Languages/`）

| 语言 | .po | .loc |
|---|---|---|
| English | en.po | en.loc |
| Français | fr.po | fr.loc |
| Español | es.po | es.loc |
| Italiano | it.po | it.loc |
| 日本語 | ja.po | ja.loc |
| 한국어 | ko.po | ko.loc |
| Português (BR) | pt_BR.po | pt_BR.loc |
| Русский | ru.po | — |
| 简体中文 | zh_CN.po | zh_CN.loc |
| 繁體中文 | zh_CHT.po | — |

- `internal/`：同一套 po + 编译用表（`trstr.h` C 头、`language_sizes.ini`）+ `zh_CN.loc` 等。
- `language_fonts.ini`：语言 → 字体映射（en/fr/pt_BR/es/ru/it → `Terminus (TTF)`；ko/zh_CN → `WenQuanYi Micro Hei`；ja → `HigashiOme Gothic regular`）。
- `safetext/`：保险箱谜题的多语言文本（`safe1.txt` / `safe2.txt`，按语言子目录 + 英文兜底）。
- `en.loc` / `zh_CN.loc` 等为二进制编译产物（Read 无法直接读取）。
- 语言探测链（`0090_Persistent.rb`）：Steam 语言（`Steam::LANG`）→ 引擎 `Oneshot::LANG` → 若存在 `zh_CN.ver` 文件强制中文 → 非 Steam 时默认 `en`。

### 15.2 翻译机制（`0091_i18n_Language.rb`）

- `Language.set(lc)`：按 `lc.full` / `lc.lang` 找 `Languages/<name>.po` → `load_pot` 解析 → `@data[crc32(msgid)] = msgstr` → 设置字体 → `reset_fonts` 刷新已注册文字精灵 → `Oneshot.set_yes_no(tr('Yes'), tr('No'))`。
- `tr(text)` 返回 `TrString`（to_s 时查表），数据库名/描述经 `initialize_database` 包装成可翻译串。
- mod 的 i18n_mod.rb 在该机制之上注入 mod 界面文本的中文翻译（仅 zh 语言）。

### 15.3 `_parse_po.py`（调试工具）

解码测试 `zh_CN.po`（utf-8-sig/utf-8/gbk 依次尝试），打印大小/头部/前 5 条 msgid→msgstr，用于排查 po 编码问题。✅ 已修复：路径基于脚本自身位置解析，不再硬编码机器路径。

---

## 16. 日志体系

`OneShot/mods/mod/logs/` 运行时生成（`.gitignore` 排除，不纳入版本控制）。每个 mod 模块启动时写一份 status 文件；诊断类用 append 追加 trace。

| 文件 | 写入者 | 内容 |
|---|---|---|
| `preload_loaded.txt` | mod.rb | 加载时间、script_dir、runtime 路径探测、$LOAD_PATH、已加载脚本清单（17 个）、错误清单 |
| `config_loaded.txt` | _config.rb | 配置路径 + `$mod_config` 全量快照 + 加载时间 |
| `skip_pictures_status.txt` | picture_skip.rb | 开关值、配置、补丁方式 |
| `skip_dialogue_status.txt` | skip_dialogue.rb | 三个开关值、被跳/不跳命令说明 |
| `skip_event_status.txt` | skip_event.rb | 模式、block/fast 规则、铁律、每帧限步数 |
| `skip_trace.log` | skip_dialogue / picture_skip / skip_event | 追加式：SKIP_DLG / PIC_SKIP / SE_BLOCK / SE_FAST / SE_CLEAR_AFTER_LOAD 等详细 trace |
| `quit_all_time_status.txt` | quit_all_time.rb | 开关、绕过的限制、保留的限制、覆盖的方法 |
| `title_screen_status.txt` | title_screen.rb | 开关、方案 B 上下文敏感说明 |
| `fly_mode_status.txt` | fly_mode.rb | 开关、快捷键、补丁点、每次 Ctrl+F 切换追加一行 toggle=ON/OFF |
| `debug_map_status.txt` | debug_map.rb | 快捷键、图层 z、A+B 优化说明 |
| `dev_settings_status.txt` | dev_settings.rb | 开关、同步键清单、分页配置 |
| `dev_settings_patch_status.txt` | dev_settings_patch.rb | 补丁方法、依赖 |
| `shortcut_keys_status.txt` | shortcut_keys.rb | 快捷键、always_* 开关、输入 API 探测结果 |
| `jump_map_status.txt` | jump_map.rb | 数据路径、过滤状态、分页、传送链说明 |
| `jump_map_runtime.txt` | jump_map.rb | 追加式：open/ACTION/transfer/CANCEL/异常，定位"传送后不收回"类问题 |
| `live_update_status.txt` | live_update.rb | 开关、信号/兜底检测器说明、抑制/忙判定 |
| `live_update_trace.log` | live_update.rb | 追加式：信号/兜底探测器选定、RELOAD（地图/坐标/erased/parallel）、FLY ON/OFF、RESUME |

---

## 17. 构建与运行时

### 17.1 `build/`（引擎构建产物）

- meson 项目：`meson-info/intro-projectinfo.json` 版本 `2.0.0`，项目名 **ModShot**，许可证 `GPL-2.0 or later`。
- 构建类型 `release`，后端 ninja（`intro-buildoptions.json`）。
- 产物：`modshot.exe` + Ruby 运行时 DLL（`x64-msvcrt-ruby310.dll`）+ MinGW 运行库（`libgcc_s_seh-1.dll`、`libstdc++-6.dll`、`libwinpthread-1.dll`）。
- `build/windows/`、`build/meson-private/`、`build/meson-logs/`：构建中间产物与日志。
- **modshot.json 中提到的编译选项**：`-DWORKDIR_CURRENT`（gameFolder 相对当前工作目录解析，默认相对 exe 目录）；GPLv3 构建才有的 xBRZ 缩放（`smoothScaling: 4`）。

### 17.2 `runtime/`（嵌入式 Ruby 3.1）

- 完整 Ruby 3.1.x 标准库（`lib/ruby/3.1.0/` 含 `x64-mingw64` 架构目录），使 preload 脚本能 `require 'json'` 等标准库（引擎默认 `$LOAD_PATH` 只有 gameFolder）。
- `bin/`：`ruby.exe`、`rubyw.exe`、`gem`、`irb`、`erb`、`rake`、`rdoc`、`rdbg`、`openssl`、`iconv`、`xxd`、`cjpeg/djpeg/jpegtran`、`fluidsynth` 等工具 + 依赖 DLL（`libgcc_s_seh-1.dll` 等）。
- `lib/ruby/gems/3.1.0/gems/`：bundled gems（rbs 2.7.0、rexml 3.2.5 等）。
- 注：`runtime/` 与 `build/` 中的 MinGW 运行库各自独立一份（引擎 exe 与 ruby.exe 分别依赖）。

### 17.3 原版游戏可执行文件（`OneShot/`）

- `Game.exe`：原版 RGSS103J 播放器（`Game.ini` → `Library=RGSS103J.dll`）。
- `oneshot.exe` / `_______.exe`：旧版 MKXP 引擎构建（Steam 版用 `steamshim.exe` + `steam_api64.dll` + `steam_appid.txt`）。
- 本仓库运行 mod 使用的是 `build/modshot.exe`，而非以上任一。

---

## 18. 开发工作流建议

### 18.1 改地图（推荐流程）

```
① 用 RPG Maker XP 打开工程（Game.rxproj）编辑地图
② 保存
③ 同步：同步地图.bat → [1] 手动 或 [2] 自动监听（建议 [2]，保存即自动同步）
④ 回到游戏：当前地图被 live_update 热重载（无需重启）
   - 若玩家卡在障碍物上会自动飞行脱困
   - 重载过的地图 autorun/parallel 需离图或重启才恢复自动执行
⑤ 用 build\modshot.exe 测试（不要用 RMXP playtest / Game.exe）
```

### 18.2 改脚本

- 游戏脚本：编辑 `xscripts/*.rb`，打包为 `Data/xScripts.rxdata`（或 `Scripts.rxdata`，取决于 Game.ini 的 `Scripts=` 与打包工具约定；`sync_maps.ps1` 注释提到 `pack_xscripts.rb`，该文件不在仓库中——见 §19）。同步工具会排除这两个脚本包，避免被地图镜像覆盖。
- mod 脚本：编辑 `OneShot/mods/mod/Scripts/*.rb`，**新增文件无需改任何配置**（mod.rb 自动按文件名排序加载）。改完重启游戏生效（preload 阶段执行）。
- 注意加载顺序依赖：基础设施文件保持 `_` 前缀（`_config` < `_patch_helper` < `_status_log`），功能模块不得依赖尚未加载的模块。

### 18.3 改配置

- 编辑 `OneShot/mods/mod/config.json`（键序可乱，保存时按固定序重排）。
- 或在游戏内 Ctrl+D 开发者设置中实时切换（写回 config.json，无需重启）。
- `skip_event` 三态键需手写（不在开发者设置界面中）。

### 18.4 调试辅助

- `logs/` 全部状态文件 + trace 日志（见 §16）。
- Ctrl+G 碰撞/事件调试覆盖层（检查事件触发/通行问题）。
- `jump_map_runtime.txt` 定位跳转问题；`live_update_trace.log` 定位热重载问题。

---

## 19. 已知问题与注意事项

1. ~~**`sync_maps.ps1` 硬编码路径失效**~~ ✅ 已修复：`$src/$dst/$bak` 已改为基于 `$PSScriptRoot` 的相对路径（见 §13.3），仓库移动位置后无需再改。
2. ~~**`Languages/_parse_po.py` 硬编码路径**~~ ✅ 已修复：改为基于脚本自身位置解析 `zh_CN.po`（与脚本同目录），仓库移动后无需再改。
3. **`pack_xscripts.rb` 不在仓库中**：`sync_maps.ps1` 注释引用了它（"scripts use xscripts\ + pack_xscripts.rb"），但仓库内未找到该文件——脚本打包工具需自行准备/找回。**不确定**其确切行为（打包到 `Scripts.rxdata` 还是 `xScripts.rxdata`）。
4. **脚本包加载歧义**（需验证）：`Game.ini` 的 `Scripts=Data\Scripts.rxdata` 指向 `Scripts.rxdata`，而 `Data/` 下同时存在 `Scripts.rxdata` 与 `xScripts.rxdata` 两个脚本包。当前游戏实际加载哪一个取决于打包工作流是否改过 Game.ini，需实际运行/比对验证。
5. **重载过的地图演出不自动恢复**：live_update 热重载的地图，其 autorun/parallel 需要离开地图（传送/跳图）或重启游戏后才恢复自动执行（设计如此，见 live_update.rb 注释）。
6. **快捷键依赖 mkxp-z 扩展输入 API**：`Input.pressex?/triggerex?` 在无该扩展的运行时下 Ctrl+D/J/F/G 不可用（状态日志会记录 API 探测结果）。
7. **`skip_event` 不在开发者设置界面**：三态键需手写 config.json；当前配置未含该键（默认 off）。
8. **mod 开关即时生效的边界**：`apply_global` 只同步已定义的 11 个布尔键全局变量；新增开关需在 `apply_global` 的 case 中补分支（白名单机制，注释有说明）。
9. **存档路径变更**：引擎配置 `dataPathOrg/dataPathApp = OneShotMods/OneShotMod` 会把引擎侧数据（含 save.dat、persistent.dat）从原版 `Oneshot/Oneshot` 移到新目录——与原版存档不互通（设计如此，避免污染原档）。
10. **备份目录增长**：`backup/data_sync/<时间戳>/` 每次手动同步都全量备份补丁 Data（279+ 个 rxdata），长期使用会占用磁盘空间。
11. **`.gitignore` 引用的 `graph.json` 不存在**：`settings/graph.json`（"静态预扫描的门连接图数据，构建产物"）在 `.gitignore` 中显式排除规则，但当前工作树中不存在该文件——推测是未提交的构建产物。
12. ~~**jump_points.json 生成工具缺失、不可维护**~~ ✅ 已解决（2026-09）：jump 机制重构为动态数据源——地图列表运行时读 MapInfos；落点按「覆盖层 → 原游戏入口落点（首次打开时预构建全图 Transfer 201 传送索引）→ 地图中心（不可通行时 BFS 扩张）」解析，jump_points.json 降级为可选覆盖层（存在才生效，保留人工微调；删除后全动态自洽）。新增/改名/删除地图自动同步，落点自动规避障碍。详见 §10.14 / §12.3。**注意**：重构后 `jump_map.rb` 需实际运行验证（本环境无法执行 Ruby 语法检查，已做静态结构审查）。

---

## 20. 许可证

- 本仓库 `LICENSE`：**GNU GPL v2**（1991 年 6 月版全文）。
- 游戏本体引擎：OneShot 的引擎是 MKXP 的 fork（GPL v3，见 `CREDITS.txt`）。
- 其他组件许可（摘自 `OneShot/CREDITS.txt`）：Ruby（Ruby License）、steamshim（Zlib License）、MKXP（GPL v3）、字体（Terminus: OFL；WenQuanYi Micro Hei: Apache-2.0 或 GPL v3；Jenna Sue 免费；RM Typerighter: CC BY-ND）、FreeSound 采样（CC0 / CC BY 3.0）、wildtextures/Textures.com 纹理（可商用）。
- 传播/分发本项目时请同时遵守游戏本体与引擎的许可条款。

---

## 21. 附录：核心术语

| 术语 | 含义 |
|---|---|
| RGSS | RPG Maker 的 Ruby 脚本系统（本作 RGSS1，分辨率 640×480） |
| ModShot | mkxp-z 分支的开源 RGSS 兼容引擎（本项目运行时引擎） |
| MKXP | 原版开源 RGSS 引擎（mkxp），OneShot 原版引擎即其 fork |
| preloadScript | 引擎配置项：在游戏脚本执行前运行的 Ruby 脚本 |
| patches | 引擎配置项：优先于游戏目录加载的补丁层（文件夹/zip/档案） |
| .rxdata | Ruby Marshal 序列化数据（地图/数据库/脚本包/存档） |
| TracePoint | Ruby 运行时钩子（:end 事件监听类定义结束） |
| Module#prepend | Ruby 方法前置注入（补丁模块的方法先于原方法执行，super 调原版） |
| autorun / parallel | RMXP 事件触发类型：自动执行（trigger 3）/ 并行处理（trigger 4） |
| CE | Common Event 公共事件（本 mod 涉及 CE15 Instructions、CE35 保存退出、CE42 Load Save） |
| 自由浏览模式 | Ctrl+J 跳关后置 `$jump_map_free_mode`，演出事件不启动、玩家自由行动 |
| 铁律 | skip_event 对 real_load 后清空事件解释器的无条件规则（修复进度丢失） |
| map_update.signal | 同步工具写给 live_update 的热重载信号文件 |
| 自动飞行 | live_update 检测玩家站上障碍物后置 `@through=true` 的脱困机制 |

---

*本文档由通读全部源码（18 个 mod 脚本、111 个游戏脚本、引擎配置、同步工具、构建与运行时结构）整理而成。*
