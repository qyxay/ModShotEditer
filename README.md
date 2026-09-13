# OneShot Mod 工作台 (ModShot)

基于自编译 [mkxp-z](https://github.com/mkxp-z/mkxp-z) 引擎（命名 **ModShot**）的 OneShot mod 开发/调试工作区。包含完整的游戏副本、mod 本体、脚本解包/打包工具和数据导出，全部脚本注入均通过 `preloadScript` 实现，**不修改原版 `xScripts.rxdata`**（游戏脚本本体除外）。

## 快速开始

双击 `build\modshot.exe`（或根目录的 `modshot.exe - 快捷方式.lnk`）即可运行带 mod 的 OneShot。

引擎配置已指向游戏副本与 mod：

```json
// build/modshot.json (实际生效)
{
  "gameFolder": "../OneShot",
  "dataPathOrg": "OneShotMods",
  "dataPathApp": "OneShotMod",
  "patches": [ "mods/mod" ],
  "preloadScript": [ "mods/mod/Scripts/mod.rb" ]
}
```

- `gameFolder` — 游戏副本目录
- `patches` — 让 `mods/mod` 覆盖原版资源（最高优先级）
- `preloadScript` — 在游戏脚本执行前注入 mod 入口

## 目录结构

```
ModShot-mkxp-z/
├── build/                    # ModShot 引擎编译产物 (meson 构建)
│   ├── modshot.exe           # 自编译 mkxp-z 引擎 (RGSS 运行时)
│   ├── modshot.json          # 实际生效的引擎配置 (见上)
│   ├── libgcc_s_seh-1.dll / libstdc++-6.dll / libwinpthread-1.dll
│   ├── x64-msvcrt-ruby310.dll   # Ruby 3.1 解释器 (内嵌引擎)
│   ├── src/  shader/  assets/  binding/  windows/   # 编译中间产物
│   └── meson-info/  meson-logs/  meson-private/  modshot.exe.p/
├── OneShot/                  # 完整游戏副本
│   ├── oneshot.exe           # 原版可执行 (工作区中未被使用)
│   ├── Data/                 # 游戏数据 (.rxdata, 含 xScripts.rxdata 游戏脚本)
│   ├── Graphics/  Audio/  Fonts/  Languages/  Wallpaper/
│   └── mods/mod/             # ★ mod 本体 (通过 patches + preload 加载)
│       ├── Scripts/          # mod 脚本 (mod.rb 自动加载全部)
│       ├── config.json       # mod 功能开关 (游戏内可实时切换)
│       ├── Data/             # pack_xscripts.rb 的输出位置 (xScripts.rxdata)
│       ├── logs/             # 运行时状态日志 (每次启动重写, 已 gitignore)
│       ├── settings/         # 运行时设置/状态目录 (.gitkeep 占位, *.json 已 gitignore)
│       └── backup/           # jump_points 等编辑前自动备份
├── xscripts/                 # 游戏脚本明文 (112 个 .rb + INDEX.txt), 编辑源
├── export/                   # 游戏数据导出 (只读分析用)
│   ├── *.txt                 # 18 份数据表 (Actors/Items/CommonEvents/MapInfos…)
│   ├── map_events/           # 263 张地图的事件明细
│   └── tileset_maps/         # 263 张地图的渲染截图 (PNG)
├── _analyze/                 # 分析/验证工具集 (80+ 个 Ruby 脚本)
│   ├── oneshot_data.rb       # 数据读取库 (共享)
│   ├── rmxpm.py              # RMXP 数据解析
│   ├── check_*/inspect_*/verify_*/scan_*/fix_*.rb   # 各类探查脚本
│   ├── scripts/              # 公共事件分析 dump
│   └── *.txt                 # 分析输出
├── runtime/                  # Ruby 3.1 运行时 (mod 脚本 require 标准库的依赖)
├── modshot.json              # 引擎配置全注释模板 (mkxp-z 官方配置说明, 备份用)
├── pack_xscripts.rb          # 打包: xscripts\ → OneShot/mods/mod/Data/xScripts.rxdata
├── unpack_xscripts.rb        # 解包: xScripts.rxdata → xscripts\
├── _dump_scripts.rb          # 脚本 dump 工具
├── _inspect_maps.rb          # 地图检查工具
├── _verify_jump.rb           # 跳点验证工具
├── modshot.exe - 快捷方式.lnk
├── OneShot游戏运行逻辑分析报告.html   # 游戏逻辑分析报告 (Trae Work 生成)
├── .gitignore                # 忽略 OneShot/mods/mod/logs/
└── .vs/                      # Visual Studio 缓存 (可删除)
```

## Mod 功能开关

`OneShot/mods/mod/config.json`，可在游戏中按 **Ctrl+D** 打开开发者设置实时切换并写回文件。

| 开关 | 当前值 | 作用 |
|---|---|---|
| `skip_pictures` | true | 跳过图片过场 |
| `quit_all_time` | true | 忽略 `menu_disabled`，任何场景下都能退出/打开菜单 |
| `skip_dialogue` | true | 跳过所有对话（整段 Show Text 101） |
| `skip_choice` | true | 自动选择第一个选项（Show Choices 102） |
| `skip_uneasy` | true | 单独跳过读档时的 "Niko feels uneasy." 提示 |
| `always_travel` | true | 事件/对话运行中仍可按 Ctrl+J 打开跳地图（打开后暂停事件，关闭后继续） |
| `always_settings` | true | 事件/对话运行中仍可按 Ctrl+D 打开开发者设置（打开后暂停事件，关闭后继续） |
| `unshow_title` | true | 不展示标题界面，直接进游戏 |
| `is_developer` | true | 开发者模式：设置页显示"开发者设置"栏 + 快捷键可用 |
| `fly_mode` | false | 飞行模式初始状态：Ctrl+F 切换（无视障碍物 + run 速度×2 + 角色置顶，保留传送事件） |
| `live_update` | true | 实时更新模式：RMXP 保存→同步后游戏内自动热重载当前地图；玩家站上障碍物自动飞行、走出恢复（默认开） |

> 注：`skip_event` 已从开发者设置界面与 config 移除（界面第 12 项原为它，超出 480 视口被裁）。其内部引擎脚本 `skip_event.rb` 仍保留，供 Ctrl+J 跳关后的自由浏览模式使用（config 无该键时默认 `off`）。

## Mod 脚本清单

`OneShot/mods/mod/Scripts/`，由 `mod.rb` 按文件名排序自动加载（新增脚本放入即可，无需改配置）。

| 文件 | 作用 |
|---|---|
| `mod.rb` | preload 入口加载器：挂载 runtime 标准库到 `$LOAD_PATH` + 自动加载同目录全部 .rb |
| `_config.rb` | 统一配置加载器，读 config.json → 全局 `$mod_config` |
| `_patch_helper.rb` | PatchHelper：统一"等待类定义 + `Module#prepend` 打补丁"样板 |
| `_status_log.rb` | StatusLog：统一向 logs/ 写状态文件 |
| `skip_dialogue.rb` | 跳过对话（101 整段）、自动选第一项（102）、跳过 uneasy 提示 |
| `skip_event.rb` | 事件阻止/快进内部引擎：已从开发者设置界面移除（config 无该键时默认 off）；**保留**供 Ctrl+J 跳关后的自由浏览模式使用 |
| `picture_skip.rb` | 跳过图片过场（含 c112 Loop 直接跳过整个循环体） |
| `quit_all_time.rb` | 忽略菜单/退出限制，随时可退出 |
| `shortcut_keys.rb` | 全局快捷键：Ctrl+D 开发者设置、Ctrl+J 跳地图 |
| `dev_settings.rb` | 开发者设置子界面：游戏内实时切换全部开关 + Jump Map 入口；分页显示（每页 8 项，左右键翻页、ACTION 切换开关，页码右下角） |
| `dev_settings_patch.rb` | 给 Window_Settings 追加"开发者设置"栏 |
| `jump_map.rb` | Jump Map 跳地图界面（书页式列表，模仿原版 FastTravel 传送链黑屏转场），落点数据 mods/mod/jump_points.json |
| `debug_map.rb` | Ctrl+G 调试显示：格子可通行性（碰撞）+ 事件位置 |
| `fly_mode.rb` | Ctrl+F 飞行模式：无视障碍物 + run 速度×2 + 角色置顶（FLY 徽标在所有图层之上，保留传送/接触触发事件） |
| `live_update.rb` | 实时更新（事件驱动）：同步脚本写完 `settings\map_update.signal` 信号后，游戏内 ~83ms 内自动热重载对应地图（重建精灵组、抑制 autorun/parallel 重放、保留 erased/地图定制，5s 低频兜底自检）；玩家站上障碍物自动飞行（@through）、走出恢复基准 |
| `title_screen.rb` | 控制标题界面（`save_exists` 挂钩实现 unshow_title） |

## 常用快捷键

| 按键 | 功能 | 前置条件 |
|---|---|---|
| Ctrl+D | 打开开发者设置 | `is_developer: true` |
| Ctrl+J | 打开跳地图 | — |
| Ctrl+G | 碰撞 + 事件位置调试显示 | `is_developer: true` |
| Ctrl+F | 飞行模式开关（无视障碍物 + run 速度） | — |
| F1 / F2 / Alt+Enter | 引擎内置：按键设置 / FPS / 全屏 | 引擎配置开启 |

## 常用工作流

### 修改游戏脚本（xscripts 打包）

游戏逻辑脚本以明文形式保存在 `xscripts/`，修改后打包为 `xScripts.rxdata` 覆盖原版：

```
ruby pack_xscripts.rb      # xscripts\ → OneShot/mods/mod/Data/xScripts.rxdata (zlib+Marshal)
ruby unpack_xscripts.rb    # 反向解包 (默认读 OneShot/Data/xScripts.rxdata, 有 .bak 优先)
```

`xscripts/INDEX.txt` 记录了每个脚本的编号、名称与大小，可用于核对解包完整性。

### 查看游戏数据

`export/` 已导出全部数据表（文本格式，可直接搜索）：地图信息 `MapInfos.txt`、地图树 `map_tree.txt`、公共事件 `CommonEvents.txt`、物品 `Items.txt`、全部文本 `all_text.txt`，以及每张地图的事件明细（`map_events/`）和渲染截图（`tileset_maps/`）。

### 运行分析脚本

`_analyze/` 内含 80+ 个探查脚本（`check_passability.rb`、`scan_doors.rb`、`verify_exit_chain.rb` 等），依赖 `runtime/` 的 Ruby。例如：

```
runtime\bin\ruby.exe _analyze\verify_points.rb
```

## 依赖

- **`runtime/`** — 便携版 Ruby 3.1（含标准库），mod 脚本 `require 'json'` 等依赖它，由 `mod.rb` 在启动时挂载；系统未装 Ruby 也能独立运行工具脚本（`runtime\bin\ruby.exe`）。
- **`build/`** — 引擎自带 Ruby 3.1 运行时（`x64-msvcrt-ruby310.dll`），与 `runtime/` 相互独立。

## 说明

- 除 `xscripts/` → `xScripts.rxdata` 的脚本覆盖外，**mod 的所有功能均通过 preload 注入实现**，不修改原版 `xScripts.rxdata`；还原只需关闭对应开关或删除 `mods/mod`。
- `OneShot/mods/mod/Data/` 为空时表示当前未打包脚本覆盖，mod 仅以 preload 方式生效。
- `xscripts/` 为游戏脚本唯一编辑源（4 位数字前缀 + INDEX.txt）。
- 顶层 `modshot.json` 是 mkxp-z 引擎配置的全注释模板（含 `displayFPS`/`fullscreen`/`patches` 等全部选项说明）；实际生效的是 `build/modshot.json`。
- `.vs/` 为 Visual Studio 缓存目录，`logs/` 为运行时日志，`settings/*.json` 为运行时状态文件，均不入库。
- 隐藏目录：`.git/` 为项目版本库（51 个提交）；`.trae-html-share-packages/` 为分析报告 HTML 的 zip 备份。
