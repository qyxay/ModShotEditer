# OneShot ModShot 源码全解析・Mod 制作知识库

> 基于对 
>
> `xscripts/`
>
> （111 个 RGSS 游戏脚本）、
>
> `OneShot/mods/mod/Scripts/`
>
> （15 个 mod 脚本）、
> `OneShot/Data/`
>
> （游戏数据）、
>
> `runtime/`
>
> （引擎运行库）、
>
> `modshot.json`
>
> （引擎配置）的逐文件代码级核实。
> 标注约定：【已核实】= 直接读源码确认；【推断】= 依据 RGSS 常识或调用关系推断，需进一步验证。
> 生成日期：2026-09-07



***

## 目录



1. [项目架构总览](#1-项目架构总览)

2. [引擎层调用知识（mkxp-z C++ 扩展）](#2-引擎层调用知识mkxp-z-c-扩展)

3. [游戏脚本层：111 个脚本功能清单](#3-游戏脚本层111-个脚本功能清单)

4. [全局对象与状态调用知识](#4-全局对象与状态调用知识)

5. [事件命令码完整参考（101–355）](#5-事件命令码完整参考101355)

6. [Script 工具库 API（事件脚本常用函数）](#6-script-工具库-api事件脚本常用函数)

7. [OneShot 特有系统详解](#7-oneshot-特有系统详解)

8. [地图与事件数据结构](#8-地图与事件数据结构)

9. [Mod 注入机制](#9-mod-注入机制)

10. [15 个 mod 脚本详解（补丁地图）](#10-15-个-mod-脚本详解补丁地图)

11. [config.json 配置键全表](#11-configjson-配置键全表)

12. [常用开关 / 变量语义表](#12-常用开关变量语义表)

13. [做 mod 的陷阱与最佳实践](#13-做-mod-的陷阱与最佳实践)

14. [验证与调试工具链](#14-验证与调试工具链)



***

## 1. 项目架构总览



```
┌────────────────────────────────────────────────────────────┐

│ 第4层  mod 层 (本项目的核心工作区)                            │

│   OneShot/mods/mod/  Scripts/\*.rb + config.json + Data/覆盖  │

│   注入方式: modshot.json → preloadScript → mod.rb             │

├────────────────────────────────────────────────────────────┤

│ 第3层  游戏数据层                                             │

│   OneShot/Data/\*.rxdata (Map/System/CommonEvents/Items…)     │

│   Graphics/ Audio/ Fonts/ Languages/ Wallpaper/              │

├────────────────────────────────────────────────────────────┤

│ 第2层  游戏脚本层 (RGSS)                                      │

│   xscripts/ 111 个 .rb → 打包为 mods/mod/Data/xScripts.rxdata │

│   类: Interpreter/Game\_\*/Scene\_\*/Window\_\*/Sprite\_\*           │

├────────────────────────────────────────────────────────────┤

│ 第1层  引擎层 (mkxp-z, C++)                                   │

│   runtime/ 解释 RGSS API: Graphics/Input/Audio/RPG::Cache     │

│   Oneshot 模块扩展 + Input.pressex?/triggerex? 扩展           │

└────────────────────────────────────────────────────────────┘
```

【已核实】关键目录职责：



| 目录 / 文件              | 职责                                                                                                                                |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `xscripts/`          | 全部游戏脚本的明文 Ruby 源（打包为 `OneShot/Data/xScripts.rxdata` 供引擎加载）。本项目对其中个别脚本做了改造（如 `0070_Interpreter_1.rb` 新增 `@pic_skip_mode`），需重新打包才生效 |
| `OneShot/Data/`      | 游戏数据：`xScripts.rxdata`、`Map*.rxdata`（263 张图）、`MapInfos.rxdata`、`System.rxdata`、`CommonEvents.rxdata` 等                            |
| `OneShot/mods/mod/`  | mod 本体：`Scripts/`（15 个 rb）、`config.json`、`Data/`（覆盖原版数据的可选目录，当前为空）、`logs/`（状态文件）、`settings/`、`backup/`                            |
| `build/modshot.json` | 引擎实际生效配置                                                                                                                          |
| `modshot.json`       | 配置模板（与 build 中一致）                                                                                                                 |
| `runtime/`           | mkxp-z 运行库 + Ruby 3.1.5 标准库（`runtime/lib/ruby/3.1.0`）                                                                             |
| `export/`            | 数据导出产物（表格等）                                                                                                                       |
| `_analyze/`          | 分析脚本（地图 / 门 / 事件扫描等）                                                                                                              |

【已核实】`build/modshot.json` 内容：



```
{

&#x20; "gameFolder": "../OneShot",

&#x20; "dataPathOrg": "OneShotMods",

&#x20; "dataPathApp": "OneShotMod",

&#x20; "patches": \[ "mods/mod" ],

&#x20; "preloadScript": \[ "mods/mod/Scripts/mod.rb" ]

}
```



* `patches`：mod 数据补丁目录（数据覆盖优先级：`mods/mod/Data/` > 原版 `Data/`）。

* `preloadScript`：引擎启动时、游戏脚本加载**之前**执行的 Ruby 文件（唯一注入入口是 `mod.rb`）。



***

## 2. 引擎层调用知识（mkxp-z C++ 扩展）

### 2.1 Oneshot 模块【已核实】



| 调用                                          | 用途                                                           |
| ------------------------------------------- | ------------------------------------------------------------ |
| `Oneshot::USER_NAME`                        | 系统用户名（用于主角名，`Game_Oneshot.get_user_name` 取首词，`the/a` 开头则取全名） |
| `Oneshot::SAVE_PATH`                        | 存档目录（`save.dat`/`persistent.dat`/`p-settings.dat` 所在）        |
| `Oneshot::GAME_PATH` / `Oneshot::DOCS_PATH` | 游戏目录 / 文档目录（谜题向游戏外写文件的路径）                                    |
| `Oneshot::JOURNAL`                          | 游戏外 "日记" 文件名（clover 可执行 / 快捷方式，跨窗口系统）                        |
| `Oneshot::OS` / `Oneshot::DE`               | 操作系统 / Linux 桌面环境标识                                          |
| `Oneshot::LANG`                             | 系统语言（构造 `LanguageCode`）                                      |
| `Oneshot.allow_exit(bool)`                  | 控制窗口右上角 X 是否能关闭游戏（过场中调用 `false`）【mod 的 `quit_all_time` 覆盖它】  |
| `Oneshot.exiting(bool)`                     | 退出状态                                                         |
| `Oneshot.set_yes_no(y, n)`                  | 设置引擎对话框 "是 / 否" 文本（i18n 调用）                                  |
| `Oneshot.crc32(str)`                        | 字符串 CRC32（i18n 词条查找键）                                        |
| `Oneshot.textinput(...)`                    | 文本输入（Main.rb 中被注释）                                           |

### 2.2 Steam 模块【已核实】

`Steam.enabled?`、`Steam::USER_NAME`、`Steam::LANG`。持久化语言选择：`Steam::LANG || Oneshot::LANG`；非 Steam 运行时强制 `en`；存在 `zh_CN.ver` 文件时强制 `zh_CN`。

### 2.3 Input 扩展【已核实】

标准 API：`Input.press?` / `trigger?` / `repeat?` / `dir4` / `dir8`（推断）。

常量：`Input::UP/DOWN/LEFT/RIGHT`（方向）、`Input::ACTION`（确认）、`Input::CANCEL`（取消）、`Input::MENU`、`Input::ITEMS`、`Input::RUN`、`Input::CTRL`、`Input::R` 等。

**mkxp-z 扩展（mod 依赖）**：



* `Input.pressex?(:LCTRL)` / `Input.pressex?(:RCTRL)` —— 按住检测，参数为 SDL scancode 符号。

* `Input.triggerex?(:D)` / `(:J)` / `(:G)` —— 按下瞬间检测，参数为 SDL scancode 符号。

* 兼容回退：`Input.respond_to?(:pressex?)` 为 false 时回退 `Input.press?(Input::CTRL)`，此时 Ctrl+D/J 不可用。

### 2.4 Graphics / Audio / Font【已核实】



* `Graphics.frame_rate = 60`（Main 设置）、`frame_count`（帧计数，用于计时）、`fullscreen`（读写）、`freeze` / `transition(帧数)` / `transition_name`、`frame_reset`、`update`。

* `Audio.bgm_play/bgm_stop/bgm_fade`、`bgs_play/bgs_fade`、`me_play`、`se_play/se_stop`；`Game_Player` 直接以 `Audio.se_play("Audio/SE/#{name}.wav", vol, pitch)` 播脚印声。

* `Font.default_name` / `default_size`（Main 设 20）。字体随语言切换：西文 `'Terminus (TTF)'`，日文 `'HigashiOme Gothic regular'`（`Language::FONT_WESTERN/FONT_J`）。

### 2.5 RPG::Cache 扩展【已核实】

`RPG::Cache.character/face/menu/lightmap/light/misc`：



* 文件名强制小写。

* 开关 160 开启时，`niko*` 角色 / 头像文件名中的 `niko` 全部替换为 `en`（换皮）。

* 每年 4 月 1 日（愚人节）`niko*` 头像替换为 `af`。

### 2.6 Wallpaper 模块（引擎 C 方法 + Ruby 包装）【已核实】

`Wallpaper.set(name, color)` / `Wallpaper.reset`（C 层）；`Game_Oneshot.rb` 中的 `Wallpaper.set_persistent/reset_persistent` 先退出全屏，再按语言路径 `Wallpaper/<langcode>/<name>.png(bmp)` 查找本地化壁纸。壁纸名与颜色存于 `$game_oneshot.wallpaper/wallpaper_color`，读档时恢复。



***

## 3. 游戏脚本层：111 个脚本功能清单

脚本按编号分 10 组（编号即加载顺序，`Main.rb` 最后执行）：

### 3.1 全局状态（0000–0006）



| 脚本                          | 功能【已核实】                                                                                                               |
| --------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| 0000\_RPG.rb                | RGSS 扩展：RPG::Cache 重载（小写 / 开关 160 / 愚人节）、Tone `+ * blank?` 运算                                                         |
| 0001\_Game\_Temp.rb         | 临时状态：消息文本 / 头像 / 回调、选择项、公共事件 id、传送 flags、转场 flags、菜单调用 flags、`footstep_sfx`（当前地图脚步声数组）、`filmsprite`、`menus_visible` 等 |
| 0002\_Game\_System.rb       | 系统级状态：BGM/BGS/ME/SE、存档计数、`menu_disabled/save_disabled/encounter_disabled`、`map_interpreter`、计时器、魔法数                   |
| 0003\_Game\_Switches.rb     | 开关数组（按 id 读写，超界自动扩展）                                                                                                  |
| 0004\_Game\_Variables.rb    | 变量数组                                                                                                                  |
| 0005\_Game\_SelfSwitches.rb | 自开关（key = \[map\_id, event\_id, key]）                                                                                 |
| 0006\_Game\_Screen.rb       | 屏幕效果：色调 / 闪光 / 震动 / 天气 / 图片（1-50 号，战斗中 +50）                                                                           |

### 3.2 战斗系统（0008–0015）

Game\_Battler\_1/2/3、Game\_BattleAction、Game\_Actor、Game\_Enemy、Game\_Actors、Game\_Party。

> 注：OneShot 实际无战斗（Battler 保留但主流程不触发），保留为标准 RGSS 实现【推断，未在游戏流程中见到战斗】。

### 3.3 地图 / 角色（0016–0026）



| 脚本                                    | 功能【已核实】                                                                                                                       |
| ------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| 0016\_Game\_Map.rb                    | 地图核心：tileset 表、全景图钳制 / 动画列表（见 §8）、footstep\_sfx 按 tileset\_id 设置、通行判定、地形标签、滚动、雾效、`bg_name/particles_type/ambient/wrapping` 定制 |
| 0017\_Game\_CommonEvent.rb            | 公共事件（并行 trigger=1 轮询开关）                                                                                                       |
| 0018/19/20\_Game\_Character\_1/2/3.rb | 角色基类：坐标 / 移动 / 动画帧 / 移动路线 / 通行                                                                                                |
| 0021\_Game\_Event.rb                  | 地图事件：事件名解析 `:flag` 与 `!special`（见 §8）、页条件判定、触发类型、锁 / 擦除                                                                       |
| 0022\_Game\_Player.rb                 | 玩家：移速（开关 251 反转）、方向键移动（开关 112 轮椅模式）、镜头居中（开关 98 钳制 / 100 关闭）、脚步声 / 轮子声发射                                                       |
| 0023\_Game\_Oneshot.rb                | 主角名（`get_user_name`）、壁纸模块、`bruteforce_start/plight_timer`                                                                     |
| 0024\_Game\_Light.rb                  | 灯光数据（光源位置 / 强度）                                                                                                               |
| 0025\_Game\_Follower.rb               | 跟随者（`$game_followers`，读档时重设 leader）                                                                                           |
| 0026\_Game\_FastTravel.rb             | 快速旅行数据：按 zone 分组的已解锁地图表 `unlock(map, id, x, y, dir)`                                                                          |

### 3.4 精灵（0027–0036）

Sprite\_Character（角色）、Sprite\_Battler、Sprite\_Picture、Sprite\_Timer、Sprite\_Light（光图）、Sprite\_Footprint/Sprite\_Footsplash（脚印）、Sprite\_MapText（地图文字）、Spriteset\_Map（地图总装：角色 / 雾 / 全景 / 灯光 z 分层）、FastTravel（快速旅行界面，见 §7）。

### 3.5 窗口（0037–0069）

Window\_Base（文本色 / 图标绘制）、Window\_Selectable（光标 / 滚动）、Window\_Command、Window\_Help、Window\_Gold、Window\_PlayTime、Window\_Steps、Window\_MenuStatus、Window\_Item、Window\_Skill、Window\_SkillStatus、Window\_Target、Window\_EquipLeft/Right/Item、Window\_Status、Window\_SaveFile、**Window\_Settings**（设置界面，mod 挂 "开发者设置" 栏）、Window\_Shop\*（商店五件套）、Window\_NameEdit/NameInput、Window\_InputNumber、**Window\_Message**（对话窗口，转义序列见 §7）、Window\_PartyCommand、Window\_BattleStatus/Result、Window\_DebugLeft/Right、Window\_MainMenu（主菜单）。

### 3.6 事件解释器（0070–0076）★ 做 mod 的核心

Interpreter\_1（执行循环 /clear/setup/start/ 子解释器）、Interpreter\_2（命令分发表 101–355）、Interpreter\_3（101–119：文本 / 分支 / 循环 / 标签）、Interpreter\_4（121–136：开关 / 变量 / 物品 / 系统访问）、Interpreter\_5（201–251：传送 / 移动路线 / 转场 / 图片 / 音频）、Interpreter\_6（301–339：战斗 / 商店 / 改名 / 数值）、Interpreter\_7（331–355：战斗指令 + 355 Script）。

完整命令码表见 §5。

### 3.7 场景（0077–0089）

Scene\_Title（标题）、**Scene\_Map**（地图主循环，定制方法见 §7）、Scene\_Menu/Item/Skill/Equip/Status/File/Save/Load/End/Name/Debug。

### 3.8 持久化与 i18n（0090–0092）

0090\_Persistent（`$persistent`：语言 + 存档独立持久化）、0091\_i18n\_Language（.po 解析 + `tr()` + 字体映射）、0092\_i18n\_English（英文默认词条）。详见 §7。

### 3.9 数据定义（0093–0096）

0093\_Data\_Item（物品合成表）、0094\_Data\_Footsteps（按 tileset 的脚步声数组）、0095\_Data\_SpecialEventData（特殊事件多格碰撞）、0096\_Data\_FastTravel（快速旅行 ZONES 定义）。详见 §7/§8。

### 3.10 谜题 / 工具 / 收尾（0097–0110）

0097\_Script.rb（**全局函数工具库**，§6）、0098\_Puzzle\_Sokoban（推箱子）、0099\_Puzzle\_Pixel（像素谜题）、0100\_Puzzle\_Film（胶片谜题）、0101\_Puzzle\_Safe（保险柜）、0102\_SaveLoad（存档系统，§7）、0103\_Ed\_Message（ED 对话框）、0104\_Doc\_Message（文档框）、0105\_Desktop\_Message（桌面消息框）、0106\_Credits\_Message（Credits 框）、0107\_Particles（粒子）、0108\_Demo（演示模式）、0109\_EdText（ED 文本 / 报错）、0110\_Main（入口）。



***

## 4. 全局对象与状态调用知识

### 4.1 全局对象【已核实】



| 对象                                                                      | 含义                                                                                                           |
| ----------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `$scene`                                                                | 当前场景实例（`while $scene != nil; $scene.main` 主循环）                                                               |
| `$game_temp`                                                            | 临时状态（不存档）                                                                                                    |
| `$game_system`                                                          | 系统状态（存档）                                                                                                     |
| `$game_switches` / `$game_variables`                                    | 开关 / 变量数组（存档）                                                                                                |
| `$game_self_switches`                                                   | 自开关（key=\[map,event,key]，存档）                                                                                 |
| `$game_screen`                                                          | 屏幕效果 + 图片（存档）                                                                                                |
| `$game_actors` / `$game_party` / `$game_followers`                      | 角色 / 队伍 / 跟随者（存档）                                                                                            |
| `$game_map` / `$game_player`                                            | 地图 / 玩家（存档）                                                                                                  |
| `$game_oneshot`                                                         | OneShot 特有状态：player\_name/wallpaper/bruteforce\_start/plight\_timer（存档）                                      |
| `$game_fasttravel`                                                      | 快速旅行解锁表（存档）                                                                                                  |
| `$persistent`                                                           | 跨存档持久化（`persistent.dat`，**不随存档**）                                                                            |
| `$data_*`                                                               | 数据库：`$data_system/$data_actors/$data_items/$data_common_events/$data_troops/$data_tilesets/$data_states`（只读） |
| `$debug` / `$console` / `$demo` / `$GDC`                                | 调试 / 控制台 / 演示 / GDC 模式标记                                                                                     |
| `$mod_config`                                                           | 【mod】config.json 解析结果                                                                                        |
| `$dev_settings_instance` / `$jump_map_free_mode` / `$skip_event_mode` 等 | 【mod】全局开关变量（见 §10）                                                                                           |

### 4.2 高频调用模式【已核实】



```
\# 传送玩家（事件 201 等价物，FastTravel/jump\_map 复用此链）

\$game\_temp.player\_transferring = true

\$game\_temp.player\_new\_map\_id = map\_id

\$game\_temp.player\_new\_x = x

\$game\_temp.player\_new\_y = y

\$game\_temp.player\_new\_direction = dir   # 2/4/6/8

Graphics.freeze

\$game\_temp.transition\_processing = true

\$game\_temp.transition\_name = "black"

\# 调用公共事件（如 CE35 保存退出、CE42 读档苏醒）

\$game\_temp.common\_event\_id = 35

\# 触发场景切换（Scene\_Map#update 每帧检测这些 flags）

\$game\_temp.menu\_calling = true     # 菜单

\$game\_temp.item\_menu\_calling = true

\$game\_temp.save\_calling = true     # 存档

\$game\_temp.shop\_calling = true     # 商店

\$game\_temp.battle\_calling = true   # 战斗

\$game\_temp.name\_calling = true     # 改名

\$game\_temp.travel\_menu\_calling = true   # 快速旅行（OneShot 定制）

\$game\_temp.window\_settings\_calling = true  # 设置（OneShot 定制）

\# 地图定制（OneShot 扩展）

\$game\_map.bg\_name = name

\$game\_map.particles\_type = type

\$game\_map.ambient.set(r, g, b, gray)

\$game\_map.wrapping = true

\$game\_map.pan\_offset\_y = val
```



***

## 5. 事件命令码完整参考（101–355）

【已核实】以下参数结构直接来自 `Interpreter_2..7` 源码。**通用规则**：



* `@index` 由 `Interpreter#update` 在 `execute_command` 返回 `true` 后统一 `+= 1`。

* 返回 `false` 的命令**自己推进了 @index**（或需要跨帧暂停），更新循环会暂停直到条件满足。

* 分支类命令（402/403/411/413/601/602/603）依赖 `@branch[indent]` 与 `command_skip`（跳到同缩进下一条）。

### 5.1 文本与分支（101–119）



| 码       | 命令      | 参数                            | 说明【已核实】                                                                                                                 |
| ------- | ------- | ----------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| 101     | 显示文章    | `[text]`                      | **OneShot 定制**：`$` 开头→文档框；`@credits`→credits 框；`@ed ` / `@desktop ` / `@credits ` / `@头像名 ` 前缀解析。随后 401 行续接，102/103 可挂接 |
| 102     | 显示选项    | `[[opt1,opt2…], cancel_type]` | `cancel_type`: 0 = 禁止取消 / 1 = 分支 2/2 = 分支 3…；结果写 `@branch[indent]`                                                      |
| 402     | 选项分支    | `[index]`                     | `@branch[indent] == index` 才执行，否则 skip                                                                                  |
| 403     | 取消分支    | —                             | `@branch[indent] == 4`                                                                                                  |
| 103     | 输入数字    | `[var_id, digits]`            | 结果写 `$game_variables[var_id]`                                                                                           |
| 104     | 更改文字选项  | `[position, frame]`           | 窗口位置 / 边框                                                                                                               |
| 105     | 按键输入处理  | `[var_id]`                    | **自推进 index 并返回 false**；结果 = 按键编号 1–18                                                                                  |
| 106     | 等待      | `[frames/2]`                  | 实际等待 `参数×2` 帧                                                                                                           |
| 111     | 条件分支    | 见下                            | 结果写 `@branch[indent]`，false 时 skip                                                                                      |
| 411     | Else    | —                             | `@branch[indent] == false` 才执行                                                                                          |
| 112     | 循环开始    | —                             | 无操作                                                                                                                     |
| 413     | 重复上方    | —                             | 回退到同缩进                                                                                                                  |
| 113     | 中断循环    | —                             | 跳到循环外                                                                                                                   |
| 115     | 终止事件处理  | —                             | `command_end`                                                                                                           |
| 116     | 暂时消除事件  | —                             | 自推进 index 并返回 false                                                                                                     |
| 117     | 公共事件    | `[ce_id]`                     | 建子解释器（深度上限 100）                                                                                                         |
| 118/119 | 标签 / 跳转 | `[label]`                     | 线性扫描                                                                                                                    |

**111 条件分支参数结构**（`@parameters[0]` 类型）：



* `0` 开关：`[0, switch_id, 0=ON/1=OFF]`

* `1` 变量：`[1, var_id, 0=常数/1=变量, 操作数, 比较(0=等/1=≥/2=≤/3=>/4=</5=≠)]`

* `2` 自开关：`[2, key, 0=ON/1=OFF]`

* `3` 计时器：`[3, 秒数, 0=≥/1=≤]`

* `4` 角色：`[4, actor_id, 0=在队/1=名字/2=技能/3=武器/4=防具/5=状态, 参数]`

* `5` 敌人：`[5, idx, 0=存在/1=状态, 参数]`

* `6` 角色方向：`[6, char(-1玩家/0本事件/事件id), 方向]`

* `7` 金钱：`[7, 数额, 0=≥/1=≤]`

* `8/9/10` 持有物品 / 武器 / 防具：`[id]`

* `11` 按键：`[11, button_id]` → `Input.press?`

* `12` 脚本：`[12, "ruby code"]` → `eval`**&#x20;求值，返回真值即成立**

### 5.2 状态与物品（121–136）



| 码               | 命令                  | 参数                                                                                  | 说明【已核实】             |
| --------------- | ------------------- | ----------------------------------------------------------------------------------- | ------------------- |
| 121             | 变量操作                | `[start, end, 0=ON/1=OFF]`                                                          | 批量写开关               |
| 122             | 变量操作                | `[start, end, 操作(0代入/1加/2减/3乘/4除/5余), 操作数类型(0常数/1变量/2随机/3物品/4角色/5敌人/6角色坐标/7其他), …]` | 见源码 §Interpreter\_4 |
| 123             | 自开关操作               | `[key, 0=ON/1=OFF]`                                                                 | key='A'..           |
| 124             | 计时器操作               | `[0=开始/1=停止, 秒数]`                                                                   |                     |
| 125/126/127/128 | 金钱 / 物品 / 武器 / 防具增减 | `[id, 操作, 操作数类型, 操作数]`                                                              | `operate_value`     |
| 129             | 队员增删                | `[actor_id, 0=加入/1=离开, 初始化]`                                                        |                     |
| 131             | 更改窗口外观              | `[windowskin]`                                                                      | **不是窗口透明度**（命名易混淆）  |
| 132/133         | 战斗 BGM / 战斗结束 ME    | `[RPG::AudioFile]`                                                                  |                     |
| 134             | 更改存档许可              | `[0=禁止/1=允许]` → `save_disabled`                                                     |                     |
| 135             | 更改菜单许可              | `[0=禁止/1=允许]` → `menu_disabled`                                                     |                     |
| 136             | 更改遇敌                | `[0=禁止/1=允许]` → `encounter_disabled`                                                |                     |

### 5.3 地图与画面（201–251）



| 码           | 命令                       | 参数                                                   | 说明【已核实】                                             |
| ----------- | ------------------------ | ---------------------------------------------------- | --------------------------------------------------- |
| 201         | 场所移动                     | `[0直接/1变量, map, x, y, dir, 0=淡出/1=无]`                | **自推进 index + 返回 false**；直接写 `player_*` flags       |
| 202         | 事件位置设置                   | `[char, 0直接/1变量/2交换, x, y, 方向]`                      | 方向 2/4/6/8                                          |
| 203         | 卷动地图                     | `[方向, 距离, 速度]`                                       |                                                     |
| 204         | 更改地图设置                   | `[0全景/1雾/2战斗背景, …]`                                  |                                                     |
| 205/206     | 雾色调 / 浓度                 | `[tone, 帧数]` / `[opacity, 帧数]`                       | 帧数 ×2                                               |
| 207         | 显示动画                     | `[char, anim_id]`                                    | `character.animation_id = id`                       |
| 208         | 更改透明状态                   | `[0=透明/1=不透明]`                                       |                                                     |
| 209         | 设置移动路线                   | `[char, RPG::MoveRoute]`                             | **char=-1 表示玩家**（mod 大量依赖）                          |
| 210         | 等待移动结束                   | —                                                    | `@move_route_waiting = true`                        |
| 221         | 准备过渡                     | —                                                    | `Graphics.freeze`（消息显示中返回 false）                    |
| 222         | 执行过渡                     | `[transition_name]`                                  | 自推进 + 返回 false                                      |
| 223/224/225 | 画面色调 / 闪光 / 震动           | `[tone/color, 帧数]` 等                                 |                                                     |
| 231         | 显示图片                     | `[编号, 文件名, 原点, 0直接/1变量, x, y, 缩放x, 缩放y, 不透明度, 合成方式]` | **图片过场跳过 mod 的进入点**                                 |
| 232         | 移动图片                     | `[编号, 帧数, 文件名, …]`                                   |                                                     |
| 233/234/235 | 旋转 / 色调 / 消除图片           | `[编号, …]`                                            |                                                     |
| 236         | 设置天气效果                   | `[类型, 强度, 帧数]`                                       | 0 = 无 / 1 = 雨 / 2 = 暴风雨 / 3 = 雪                     |
| 241         | 播放 BGM                   | `[RPG::AudioFile]`                                   | 同时重置 `target_bgm_vol_level=-1, bgm_fadein_speed=99` |
| 242/245/246 | BGM 淡出 / BGS 播放 / BGS 淡出 |                                                      |                                                     |
| 247/248     | 记忆 / 还原 BGM・BGS          |                                                      |                                                     |
| 249/250/251 | 播放 ME/SE/ 停止 SE          |                                                      |                                                     |

### 5.4 战斗与其他（301–355）



| 码           | 命令                                                          | 说明【已核实】                                                       |
| ----------- | ----------------------------------------------------------- | ------------------------------------------------------------- |
| 301         | 战斗处理                                                        | `[troop_id, 可逃跑, 可失败]`；结果写 `@branch[indent]`（0 胜 / 1 逃 / 2 败） |
| 601/602/603 | 胜利 / 逃跑 / 失败分支                                              |                                                               |
| 302         | 商店处理                                                        | 后续 605 行续接商品                                                  |
| 303         | 输入名字                                                        | `[actor_id]`，自推进 + false                                      |
| 311–322     | 角色 HP/SP/ 状态 / 全恢复 / EXP / 等级 / 能力 / 技能 / 装备 / 名字 / 职业 / 图像 | 标准 RGSS                                                       |
| 331–340     | 敌人 HP/SP/ 状态 / 全恢复 / 出现 / 变身 / 动画 / 伤害 / 强制行动 / 中止战斗        |                                                               |
| 351/352     | 调用菜单 / 存档画面                                                 | 自推进 + false                                                   |
| 353/354     | 游戏结束 / 返回标题                                                 | 自推进 + false                                                   |
| 355         | 脚本                                                          | `[code]`；后续 655 行续接；`eval(script)`**&#x20;求值，恒返回 true**       |



***

## 6. Script 工具库 API（事件脚本常用函数）

【已核实】`0097_Script.rb` 定义了模块方法 `Script.*` 与顶层全局函数，是事件 "脚本" 命令（355）最常用的调用库。

### 6.1 Script 模块方法



| 方法                                                                                               | 功能                                                                                         |
| ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------ |
| `Script.px / Script.py`                                                                          | 玩家逻辑坐标（含半格校正 `logpos`）                                                                     |
| `Script.is_name_swear / is_name_niko / is_name_like_niko / is_name_like_mom_dad / is_name_gross` | 主角名匹配 i18n 词表（po 键 `NAME_SWEARS/NAME_NIKOS/NAMES_LIKE_NIKO/NAMES_LIKE_MOMDAD/NAMES_GROSS`） |
| `Script.start_bruteforce / check_bruteforce / skip_bruteforce / bruteforce_vars`                 | 保险柜暴力破解计时；`bruteforce_vars` 把尝试次数拆成变量 26–30                                                |
| `Script.lose_all_items`                                                                          | 丢弃 1–99 号物品（跳过 54/81/82 调试物品）                                                              |
| `Script.fix_footsplashes(x, y)` / `move_player_relative(x, y)` / `move_player(x, y)`             | 脚印修正 / 玩家相对 / 绝对移动（改坐标 + 显示偏移）                                                             |
| `Script.eve_x(name) / eve_y(name)`                                                               | 按**事件名**查事件坐标                                                                              |
| `Script.countdown_*`（4 个）                                                                        | 倒计时数字拆位写入变量 101–110                                                                        |
| `Script.niko_reflection_update / _enc_update / _peng_update`                                     | "niko reflection" 事件镜像同步                                                                   |
| `Script.tmp_s1..3 / tmp_v1..3`                                                                   | 临时开关 / 变量（索引 22/23/24，即 `TMP_INDEX=22`）                                                    |
| `Script.set_cam(x, y)` / `fadein_bgm(target, speed)`                                             | 相机 / BGM 渐入                                                                                |
| `Script.copy_journal`                                                                            | 向游戏外复制日记（含 Linux .desktop 处理）                                                              |
| `Script.create_boxes / clear_boxes / put_key_in_box / is_key_in_box / is_key_in_bigbox`          | 元游戏谜题：向游戏目录 Portal1-3/BigPortal 写钥匙文件                                                      |
| `Script.password1 / password2`                                                                   | 向 DOCS\_PATH 复制本地化密码图                                                                      |
| `Script.is_key_in_box(numb)`                                                                     | 检查钥匙文件是否存在（跨存档持久，依赖 `Oneshot::GAME_PATH`）                                                  |

### 6.2 顶层全局函数



| 函数                                                                 | 功能                                          |
| ------------------------------------------------------------------ | ------------------------------------------- |
| `has_lightbulb?`                                                   | 物品 1（灯泡）数量 > 0                              |
| `button_pressed?`                                                  | 1–18 任一按键触发                                 |
| `enter_name`                                                       | 触发改名场景（`name_calling = true`）               |
| `check_exit(min, max, x: -1, y: -1)`                               | 玩家在指定矩形区域 → `Script.tmp_s1`（受开关 11 影响）      |
| `loadQASave(fname)`                                                | 加载 `testing_saves/` 测试存档                    |
| `kill_perma_flags`                                                 | 清开关 151–175 + 变量 76–100                     |
| `bg(name)` / `particles(type)`                                     | 地图背景 / 粒子类型                                 |
| `ambient(r,g,b,gray=0)` / `clear_ambient`                          | 环境光（Tone）                                   |
| `add_light / del_light / clear_lights`                             | **已注释禁用**（灯光改为开关 200 后按地图内置）                |
| `wrap_map` / `pan_offset_y(val)`                                   | 环绕地图 / 全景 Y 偏移                              |
| `green_ambient / blue_ambient / house_ambient`                     | 预设环境光                                       |
| `enable_travel / disable_travel / unlock_map(zone, map, dir)`      | 快速旅行：`unlock_map` 查找名为 `FAST TRAVEL` 的事件取落点 |
| `watcher_tell_time` / `plight_start_timer` / `plight_update_timer` | 时钟 / 苦难以分钟写 `tmp_v1`                        |
| `activate_balcony?(ypos)`                                          | 阳台互动判定（菜单未开 + 面向 + 按 ACTION + 无事件运行）        |



***

## 7. OneShot 特有系统详解

### 7.1 i18n 翻译系统【已核实】



* `Language.set(lc)`：按 `Languages/<full>.po` → `<lang>.po` 加载词条；`language_fonts.ini` 提供 `语言=字体` 映射并填充 `Language::LANGUAGES`。

* 词条存储：`@data[Oneshot::crc32(msgid)] = msgstr`，`Language.tr(str)` 查表，未命中返回原文。

* `tr(text)` 顶层函数返回 `TrString`（`to_s` 时翻译）。**在 UI 代码中写&#x20;**`tr('Hello')`**&#x20;即接入翻译**。

* `Language.register_text_sprite(key, spr)`：注册文字精灵，语言切换时 `reset_fonts` 自动更新字体。

* `TrString` 用于数据库对象名（`initialize_database` 包装 item/actor 名字）。

### 7.2 持久化（Persistent）【已核实】



* `$persistent` 存语言，文件 `SAVE_PATH/persistent.dat`（Marshal）。

* `$persistent.langcode` → 语言代码字符串（如 `zh_CN`、`en`），全游戏用于资源本地化路径。

### 7.3 存档系统【已核实】

文件：



* `SAVE_PATH/save.dat`：主存档。Marshal 序列：`frame_count → system → switches → variables → self_switches → screen → actors → party → map → player → followers → oneshot → fasttravel → footstep_sfx`。

* `SAVE_PATH/p-settings.dat`：永久标记 = 开关 151–175 + 变量 76–100 + 玩家名。

* `SAVE_PATH/save_backups/save1-5.bk`：滚动轮换备份（最多 5 份，损坏时自动回退）。

* `save_progress.oneshot`：假存档（Steam 兼容 / 时长统计）。

关键规则：



* 存档守卫：`$game_variables[3] == 0` 时不写（开场未完成）。

* `real_load`（读档）：恢复 BGM（开关 181/183/186/188/190 梦场景除外）→ `$game_map.update` → `$scene = Scene_Map.new` → 非检查点（开关 198）时 `common_event_id = 42`。

* `save_exists` = `FileTest.exist?(SAVE_FILE_NAME)`。

* `quit_game_bed`：保存并退出（用解释器 index ±1 技巧绕过守卫）。

* **mod 铁律**：`real_load` 完成后立即清空主解释器（防 map1 ev1 开场流程覆盖读档位置）。

### 7.4 对话窗口转义序列【已核实】（Window\_Message）



| 序列      | 效果                                                                  |
| ------- | ------------------------------------------------------------------- |
| `\v[n]` | 插入变量 n 的值                                                           |
| `\p`    | 插入玩家名（东亚字体前加空格）                                                     |
| `\n`    | 换行                                                                  |
| `\c[n]` | 颜色 n（0–7）                                                           |
| `\.`    | 短停顿（10 帧）                                                           |
| `\|`    | 长停顿（40 帧）                                                           |
| `\@`    | 换头像（后跟头像文件名）                                                        |
| `\>`    | 立即显示剩余文字                                                            |
| `\\`    | 字面反斜杠                                                               |
| `[开头`   | 机器人音效 `text_robot`（否则 `text`）                                       |
| 按钮      | `Input::R` + 开关 253 = 快进（跳过停顿）                                      |
| 防毒面具    | 玩家角色名含 `gasmask` 时，`niko*`/`en*` 头像强制换为 `niko_gasmask`/`en_gasmask` |

### 7.5 消息框四兄弟【已核实】

`$game_temp.message_ed_text / message_doc_text / message_desktop_text / message_credits_text`，分别由 `Ed_Message / Doc_Message / Desktop_Message / Credits_Message` 渲染，事件 101 用 `@ed `、`$`、`@desktop`、`@credits` 前缀触发。

### 7.6 快速旅行【已核实】



* 数据：`Game_FastTravel`（`unlocked` 按 zone 分组，`unlock(map_key, map_id, x, y, dir)`）+ `FastTravel::ZONES`（4 大区 30 个落点定义，全部经 `tr()` 本地化）。

* 界面：`FastTravel` 窗口（z=9998），确认后走标准传送链（`player_transferring` + `Graphics.freeze` + transition `"black"`）。

* **mod 的&#x20;**`jump_map`**&#x20;完全复刻此传送链**。

### 7.7 脚步声系统【已核实】



* `Data_Footsteps.rb`：`FOOTSTEP_SFX[tileset_id-1]` 定义每类地形的地面音效数组（可含 `['step_metal', 0.5]` 音量系数）。

* `Game_Map#setup` 按 tileset 填充 `$game_temp.footstep_sfx`。

* `Game_Player#emit_footstep`：取 `terrain_tag-1` 索引音效；`FOOTSTEP_AMT` 表做多帧随机（`step_wood01/02…`）；音量 70–90、音高 85–115 随机；开关 112（轮椅）改播 `wheel_squeak1` 交替音高；移动后发 `emit_footsplash`（水面溅射）。

### 7.8 灯光系统【已核实】



* `Scene_Map` 提供 `add_light(id, filename, intensity, x, y) / del_light(id) / clear_lights`（z 分层：光照层 z=200）。

* 事件侧 `Script.add_light` 等已被注释禁用 —— 灯光现由地图内置（开关 200 后启用）。

### 7.9 物品合成【已核实】（`Item::COMBINATIONS`）

48 条组合规则，`Item.combine(a, b)` 按键值排序后查表，返回合成结果物品 id 或失败提示 id（100–104）。代表：`[3,4]→5`（酒精 + 干枝→湿枝）、`[8,9]→10`（相机 + 螺丝刀→镜头）、`[27,56]→57`（试管水 + 药丸→奇迹水）、照片系列 61–70 → 粘性照片等。

### 7.10 谜题【已核实】



* 推箱子（Puzzle\_Sokoban）、像素谜题（Puzzle\_Pixel）、胶片谜题（Puzzle\_Film，用 `$game_temp.filmsprite`）、保险柜（Puzzle\_Safe，依赖 `Script.bruteforce_*`）。

### 7.11 Scene\_Map 定制方法【已核实】

`call_travel_menu / call_window_settings`（快速旅行 / 设置菜单入口，对应 `$game_temp.travel_menu_calling / window_settings_calling`）、`call_save / call_debug`、`transfer_player`（读 `player_*` flags 执行传送）、`add_light / del_light / clear_lights`、`particles=`、`add_follower / remove_follower`、`bg=`、`new_footprint / new_footsplash / new_maptext`、`fix_footsplashes`、`menu_open?`。



***

## 8. 地图与事件数据结构

### 8.1 事件名语法【已核实】（Game\_Event#initialize）



```
event.name.scan(/:(\[a-z]+)/)   # 冒号+小写 → 自定义 flags

/!(\[a-z]+)/.match(event.name)  # 感叹号+小写 → SpecialEventData
```



* 例：`!bigpool` → 继承 `:bottom` flag + 24 格碰撞数组（多格碰撞事件）。

* `SpecialEventData::SPECIAL_EVENTS`：`bigpool/smallpool/specialpool/generator/machine/glitch/bed/vendor/lens`。

* 事件页条件：`page.condition.switch1_valid/switch2_valid/variable_valid/self_switch_valid`（mod 的 skip\_event 用 "第一页无条件" 判断演出事件）。

* 触发类型：0 = 按键 / 1 = 接触 / 2 = 接触 (角色下方)/3 = 自动执行 / 4 = 并行处理。

* 事件是否 "同格触发" 由 `over_trigger?` 判定（有图 + 不可通行→面触发；无图或可通行→同格触发）。

* `intersects?(x, y)` 用碰撞数组判定 "踩到事件范围"。

### 8.2 Game\_Map 定制字段与全景图表【已核实】



| 列表                        | 内容                                      |
| ------------------------- | --------------------------------------- |
| `CLAMPED`（双轴钳制）           | `red`、`red_distort`、`codebg`            |
| `CLAMPED_Y`（仅 Y）          | `red_obsdesk`                           |
| `ANIMATED`                | `blue_water`                            |
| `FADE_ANIMATION_PANORAMA` | `dark_water`、`green_water`              |
| `ONETOONE`（1:1 跟随）        | `blue_water`、`green_water`、`dark_water` |
| `NOZOOM`（缩放 = 1）          | `dark_water`                            |
| `ALWAYS_MOVING`           | `codebg`                                |

字段：`bg_name`、`particles_type`、`clamped_x/y`、`always_moving`、`pan_move_offset`、`pan_onetoone`、`pan_animate`、`pan_fade_animate`、`pan_zoom`、`wrapping`（环绕地图，`valid?` 恒真）、`pan_offset_y`、`ambient`（Tone）。

### 8.3 地图数据

`Data/Map%03d.rxdata`（`load_data` 加载）；`MapInfos.rxdata` 通过 `parent_id` 链构建 `map_name`（`大区/子图` 路径）。地图 263 张（Map001–Map263）。



***

## 9. Mod 注入机制

### 9.1 注入链路【已核实】



```
引擎启动

&#x20; → 读 build/modshot.json

&#x20; → 执行 preloadScript = mods/mod/Scripts/mod.rb

&#x20;     ├─ 1. \$LOAD\_PATH 追加 runtime 标准库 (runtime/lib/ruby/3.1.0 + x64-mingw64)

&#x20;     │    → 使 require 'json' 等可用 (引擎默认只挂 gameFolder)

&#x20;     ├─ 2. Dir.glob(Scripts/\*.rb).sort 逐个 load (排除自身)

&#x20;     │    → 文件名排序决定加载顺序: \_config.rb → \_patch\_helper.rb → \_status\_log.rb

&#x20;     │      → debug\_map.rb → dev\_settings.rb → dev\_settings\_patch.rb → event\_twitch.rb

&#x20;     │      → jump\_map.rb → picture\_skip.rb → quit\_all\_time.rb → shortcut\_keys.rb

&#x20;     │      → skip\_dialogue.rb → skip\_event.rb → title\_screen.rb

&#x20;     └─ 3. 写 logs/preload\_loaded.txt (加载清单 + 错误)

&#x20; → 引擎加载游戏脚本 (xScripts.rxdata, 111 个类定义)

&#x20; → 各 mod 脚本用 TracePoint(:end) 监听类定义完成 → Module#prepend 打补丁

&#x20; → Main.rb 开始主循环
```

### 9.2 补丁模式（核心调用知识）【已核实】



```
\# \_patch\_helper.rb —— 统一封装

PatchHelper.install('Scene\_Map', methods: \[:update]) do |k|

&#x20; k.prepend(SomePatchModule)

end

\# 语义: TracePoint(:end) 异步监听; 类名匹配 && 指定方法全部就绪 → 执行 block(prepend) → disable
```



* **为什么需要 TracePoint**：preload 在游戏类定义之前执行，不能直接 `class Scene_Map; prepend`。

* **prepend 语义**：补丁模块中的同名方法先于原方法执行，`super` 调用原实现；未定义的方法透传。

* **类级 / 单例级覆盖**（非 prepend）：`Object.prepend(...)`（全局方法如 `save_exists`、`real_load`）、`Oneshot.singleton_class.alias_method` + `define_singleton_method`（C 方法覆盖，如 `allow_exit`）、`Input.singleton_class`（`quit?` 临时覆盖）。

* **数据覆盖**：`patches: ["mods/mod"]` → `mods/mod/Data/*.rxdata` 优先于原版。

* **脚本覆盖**：游戏脚本本体（xscripts → xScripts.rxdata）重新打包后，加载顺序与内容随打包结果生效（本项目在 `0070_Interpreter_1.rb` 注入了 `@pic_skip_mode` 字段）。

### 9.3 配置加载【已核实】

`_config.rb`（`_` 开头 ASCII 最小，最先加载）读 `mods/mod/config.json` → `$mod_config`（容错 UTF-8 BOM）。所有 mod 脚本 `default_config.merge($mod_config)` 取开关，写 `logs/config_loaded.txt`。

### 9.4 状态 / 日志【已核实】

`StatusLog.write(name, lines)` / `StatusLog.append(name, msg)`（带时间戳追加）→ `mods/mod/logs/`。游戏内改动配置 → `dev_settings.rb#save_config` 写回 config.json（固定键顺序）。



***

## 10. 15 个 mod 脚本详解（补丁地图）

> 补丁目标 = 被 prepend / 覆盖的类与方法。所有脚本均为
>
> **纯 preload，不修改游戏原始文件**
>
> （除 xscripts 重打包）。

### 10.1 基础设施（3 个）



| 脚本                 | 作用【已核实】                                      |
| ------------------ | -------------------------------------------- |
| `_config.rb`       | 统一加载 config.json → `$mod_config`             |
| `_patch_helper.rb` | `PatchHelper.install`（TracePoint+prepend 封装） |
| `_status_log.rb`   | `StatusLog.write/append` 日志工具                |

### 10.2 功能 mod（10 个）



| 脚本                      | 配置键                                             | 补丁目标                                                                                                                                              | 调用知识要点【已核实】                                                                                                                                                                      |
| ----------------------- | ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `skip_pictures.rb`      | `skip_pictures`                                 | `Interpreter#execute_command`                                                                                                                     | 命令 231 进入 `@pic_skip_mode`；跳过集 `[106,207,208,210-215,221-225,232-236,241]`；**101 退出跳过**、**112 循环整体跳到首个 413**、**209 不跳**（删图必须执行）；不手动 `@index += 1`                                |
| `skip_dialogue.rb`      | `skip_dialogue` / `skip_choice` / `skip_uneasy` | `Interpreter#execute_command`                                                                                                                     | 101/401 整段跳过（index 移到最后一个 401）；102 自动选第一项（`@branch[0]=0`）；"Niko feels uneasy." 单独开关                                                                                              |
| `skip_event.rb`         | `skip_event`（off/block/fast）                    | `Game_Event#check_event_trigger_auto`、`Game_Event#update`、`Interpreter#setup`、`Interpreter#execute_command`、`Scene_Map#update`、`Object#real_load` | 三态模式 + `$jump_map_free_mode` 自由浏览；block = 事件级阻止（autorun/parallel 锁玩家演出 + CE15/CE42）；fast = 命令级跳过 `[101,401,102,105,106,230,231,232,209(-1)]` + 每帧限步 60；**铁律：real\_load 后清空主解释器** |
| `quit_all_time.rb`      | `quit_all_time`                                 | `Oneshot.allow_exit`、`Scene_Map#update`、`Input.quit?`（临时）                                                                                         | 忽略 `menu_disabled`/`map_interpreter.running?`；退出键 → `common_event_id=35` + `Input.quit?` 临时返回 false 走 super                                                                      |
| `shortcut_keys.rb`      | `always_settings` / `always_travel`             | `Scene_Map#update`                                                                                                                                | Ctrl+D 开发者设置 / Ctrl+J 跳地图；界面打开时拦截 super（事件 / 玩家 / 地图全暂停）；`Input.pressex?/triggerex?`（SDL scancode 符号）                                                                            |
| `jump_map.rb`           | `is_developer`（依赖）                              | `Window_JumpMap`（新类）+ dev\_settings 联动                                                                                                            | 读 `jump_points.json`（263 图预扫描落点）；名字黑名单 / 祖先链过滤；书页式（每页 10 条）；复刻 FastTravel 传送链；跳转后 `$jump_map_free_mode=true` + 清解释器                                                              |
| `dev_settings.rb`       | `is_developer`                                  | `Window_DevSettings`（新类）                                                                                                                          | 运行时开关列表；布尔取反 / `skip_event` 三态循环；`apply_global` 白名单同步 10 个全局变量；写回 config.json                                                                                                    |
| `dev_settings_patch.rb` | `is_developer`（依赖）                              | `Window_Settings#open/update/dispose`                                                                                                             | 设置页追加 "开发者设置" 栏；修原版 sprite 残留堆积                                                                                                                                                  |
| `event_twitch.rb`       | 无（常开）                                           | `Game_Event#start/update`                                                                                                                         | 含 209/212 目标 =-1（推玩家）的事件做触发抑制：玩家位置未变则抑制，移动后解除（修跳关后抽搐）                                                                                                                            |
| `title_screen.rb`       | `unshow_title`                                  | `Scene_Title#main`、`Object#save_exists`                                                                                                           | 上下文敏感：标题画面内 `save_exists` 返回 true（跳过标题），其余场合原版检查（修无存档卡死）                                                                                                                         |
| `debug_map.rb`          | `is_developer`（依赖）                              | `Scene_Map#update`                                                                                                                                | Ctrl+G 调试图层（z=250）：红色 = 四向不可通行、橙色 = 部分、蓝色块 + 事件 ID                                                                                                                               |

### 10.3 全局开关变量一览【已核实】

`$mod_config`、`$is_skip_picture`、`$skip_dialogue_enabled`、`$skip_choice_enabled`、`$skip_uneasy_enabled`、`$skip_event_mode`（off/block/fast）、`$jump_map_free_mode`、`$quit_all_time_enabled`、`$unshow_title_enabled`、`$dev_settings_enabled`、`$always_settings_enabled`、`$always_travel_enabled`、`$dev_settings_instance`、`$debug_map_overlay`、`$title_screen_context`。



***

## 11. config.json 配置键全表

【已核实】当前 `OneShot/mods/mod/config.json` 实际值 + 默认值：



| 键                 | 类型   | 默认    | 当前    | 作用                                        |
| ----------------- | ---- | ----- | ----- | ----------------------------------------- |
| `skip_pictures`   | bool | true  | true  | 图片过场跳过（231 进入跳过模式）                        |
| `quit_all_time`   | bool | true  | true  | 随时退出 / 打开菜单                               |
| `skip_dialogue`   | bool | false | true  | 跳过对话文字（101/401）                           |
| `skip_choice`     | bool | false | true  | 自动选第一个选项（102）                             |
| `skip_uneasy`     | bool | false | true  | 跳过 "Niko feels uneasy." 读档提示              |
| `skip_event`      | str  | off   | block | `off` 正常 / `block` 整体阻止演出 / `fast` 跳演出保功能 |
| `always_travel`   | bool | false | true  | 事件 / 对话中也可 Ctrl+J                         |
| `always_settings` | bool | false | true  | 事件 / 对话中也可 Ctrl+D                         |
| `unshow_title`    | bool | false | true  | 跳过标题画面直接进游戏                               |
| `is_developer`    | bool | false | true  | 开发者设置入口（设置栏 + Ctrl+D + Ctrl+G）            |

另：`mods/mod/jump_points.json`（263 图跳转落点，由 `_analyze` 预扫描生成，可编辑）。



***

## 12. 常用开关 / 变量语义表

【已核实】从源码调用点提取（`$game_switches[n]` / `$game_variables[n]`）：



| 编号                  | 类型      | 语义                                     |
| ------------------- | ------- | -------------------------------------- |
| 3                   | 变量      | 开场完成标记（=0 时不存档）                        |
| 11                  | 开关      | 影响 `check_exit` 结果（取反）                 |
| 22–24               | 开关 / 变量 | `Script.tmp_s1..3 / tmp_v1..3`（临时槽）    |
| 26–30               | 变量      | 保险柜暴力破解尝试次数的五位数                        |
| 76–100              | 变量      | 永久变量（随 `p-settings.dat` 跨存档）           |
| 98                  | 开关      | 镜头钳制在地图边界内（Player#center / Map scroll） |
| 99                  | 开关      | 退出时不自动存档（Main at\_exit）                |
| 100                 | 开关      | 禁用镜头居中与滚动（自由镜头 / 特殊地图）                 |
| 101–110             | 变量      | 倒计时数字位（秒个位→天千位）                        |
| 112                 | 开关      | 轮椅模式：上下键只转身 + 轮子声                      |
| 151–175             | 开关      | 永久开关（随 `p-settings.dat` 跨存档）           |
| 160                 | 开关      | niko→en 角色 / 头像替换                      |
| 181/183/186/188/190 | 开关      | 梦境场景（读档不恢复 BGM）                        |
| 198                 | 开关      | 检查点存档（读档跳过 CE42 苏醒演出）                  |
| 200                 | 开关      | 启用灯光系统（推断，基于 `Game_Light` 使用）          |
| 251                 | 开关      | 反转奔跑 / 步行速度映射                          |
| 253                 | 开关      | 对话快进（按住 `Input::R`）                    |

> 注意：
>
> `p-settings.dat`
>
>  的永久开关 151–175 / 永久变量 76–100 是 OneShot 剧情跨存档系统（新游戏 +）的核心，mod 改动这些槽位会直接影响多周目继承。



***

## 13. 做 mod 的陷阱与最佳实践

### 13.1 解释器 index 陷阱【已核实】



* `Interpreter#update` 在 `execute_command` 返回 `true` 后**统一&#x20;**`@index += 1`。

* 因此补丁里**绝不手动&#x20;**`@index += 1`（会叠加多跳）；要跳过一段命令就把 `@index` 停在最后一条被跳命令上。

* 105（按键输入）/116（擦除）/201（传送）/222（转场）/301/303/339/340/351/352/353/354 会**自己推进 index 并返回 false**—— 补丁要小心这些命令的返回语义。

### 13.2 命令跳过黑名单【已核实】（skip\_dialogue /skip\_pictures 的经验）



* **105 不能跳**：教学事件的 c112 Loop + c105 + c111 循环依赖按键写入变量，跳过会死循环黑屏。

* **209 不能跳**：删除图片命令，跳过会残留图片盖屏。

* 106 等待可跳但影响时序；241 BGM 只在开场总控（map1 ev1）拦截。

* 图片跳过模式的退出信号：101（对话）与 112（循环整体跳过）。

### 13.3 事件冻结的正确姿势【已核实】（shortcut\_keys 的经验）



* 打开全屏界面后，在 `Scene_Map#update` 的 prepend 里**直接 return（不调 super）**，事件解释器 / 玩家 / 地图 / 消息窗口全部暂停；关闭后恢复 super 继续。

* 转场 / 传送中（`transition_processing` / `player_transferring`）禁用快捷键，避免干扰 `Graphics.freeze/transition`。

### 13.4 上下文敏感补丁【已核实】（title\_screen 方案 B）



* 全局劫持（`Object.prepend` 改返回值）会误伤所有调用点；改用**上下文标记**（在 `Scene_Title#main` 入口置 `$title_screen_context`，出口 ensure 复位）区分调用场景。

### 13.5 读档铁律【已核实】（skip\_event）



* 存档快照若带着运行中的解释器状态，读档后事件流会继续跑到 "新游戏" 分支覆盖读档位置。`real_load` 完成后必须**清空主解释器**（`map_interpreter.clear` + `@list=nil`）。

### 13.6 多补丁叠加顺序【已核实】



* 同方法多补丁（execute\_command：skip\_event → skip\_dialogue → picture\_skip）按 load 顺序 prepend，**后加载的在外层**。skip\_dialogue 吞掉 101 后必须代清 `@pic_skip_mode`，否则 picture\_skip 见不到 101 会提前 `command_end` 截断事件。

### 13.7 通用最佳实践



* 新开关键 → `dev_settings.rb` 的 `apply_global` case 补一个分支（白名单），并考虑 `ENUM_KEYS` 三态化。

* 新 mod 脚本放入 `Scripts/` 即可自动加载，无需改 modshot.json（注意 `_` 前缀控制加载顺序）。

* 与引擎 C 方法交互用 `respond_to?` 探测 + 回退（`pressex?` 不存在时用 `Input::CTRL`）。

* 写日志用 `StatusLog`，排查加载问题看 `logs/preload_loaded.txt`。



***

## 14. 验证与调试工具链



| 工具 / 方法                            | 用途                                                              |
| ---------------------------------- | --------------------------------------------------------------- |
| `mods/mod/logs/preload_loaded.txt` | 启动加载清单与错误                                                       |
| `mods/mod/logs/*_status.txt`（17 个） | 各 mod 开关状态 / 配置快照                                               |
| `mods/mod/logs/skip_trace.log`     | 事件跳过 / 阻止的逐条 trace（1.3MB 级别，可 grep）                             |
| `mods/mod/logs/settings.log`       | 设置变更记录                                                          |
| Ctrl+G 调试图层（debug\_map.rb）         | 碰撞热区 + 事件 ID 可视化（z=250）                                         |
| Ctrl+D 开发者设置（dev\_settings.rb）     | 运行时切换全部开关并写回 config.json                                        |
| Ctrl+J 跳地图（jump\_map.rb）           | 快速跳转 263 图（`jump_points.json` 落点）                               |
| `_analyze/` 脚本                     | 地图 / 门 / 事件预扫描（`build_door_graph` 产出 `graph.json`：1199 个门事件连接图） |
| `export/` 表格                       | 数据导出供审查                                                         |



***

*本文档基于源码逐文件核实生成；标注【推断】的条目在使用前建议二次验证。*