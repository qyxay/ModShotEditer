# 绘制 Mod 地图方案（OneShot ModShot-mkxp-z）

> 方案基于对 `OneShot/Data/` 数据结构、`Tilesets.rxdata`、`MapInfos.rxdata`、
> 现有工具链（`_analyze/rmxpm.py`、`dump_map.rb`、`event_editor.rb`、`live_sync.rb`、
> `tools/door_graph*.py/html`、`pack_xscripts.rb`）的代码级核实。
> 标注：【已核实】= 已读源码/数据确认；【推断】= 依据 RGSS 常识推断，需验证。
> 生成日期：2026-09-07

---

## 1. 结论先行

**推荐路径（组合式）**：用 **Ruby/Python 脚本直接构造 `MapXXX.rxdata`**（图层数据 + 事件骨架）
→ 落盘到 `OneShot/mods/mod/Data/`（mod 数据覆盖层）
→ **游戏内 `event_editor.rb`（Ctrl+E）+ 网页 `door_graph.html`** 做事件位置/门连接的可视化微调
→ 用 **`debug_map.rb`（Ctrl+G）与 `jump_map.rb`（Ctrl+J）** 现场验证通行与落点。

不需要 RPG Maker XP 编辑器，不需要改引擎；全部基于本仓库现有工具链 + 标准 RGSS 数据格式。

---

## 2. 地图数据格式（已核实的核心事实）

### 2.1 `Map%03d.rxdata` = `RPG::Map` 的 Marshal 序列化

```ruby
# 实例变量清单（Map004 实测）
@tileset_id    # Integer，1..30，对应 Tilesets.rxdata 数组索引
@width, @height
@data          # Table(w, h, 3) 三层图块 ID
@events        # Hash{ id => RPG::Event }
@encounter_list, @encounter_step
@bgm, @bgs     # RPG::AudioFile
@autoplay_bgm, @autoplay_bgs
```

### 2.2 `Table` 的 Marshal 二进制布局【已核实，关键！】

```
4 bytes : dim   (=3)
4 bytes : xsize
4 bytes : ysize
4 bytes : zsize
4 bytes : size  (= xsize*ysize*zsize)
N bytes : 数据，每格 2 字节小端无符号（'v*'）—— 不是 4 字节！
```
- **必须用 16 位（`'v*'`）读取/写入**。用 32 位会读出 42599049 这类错乱值（本项目 `check_table.rb` 踩过这个坑）。
- 索引：`data[x + xsize*y + xsize*ysize*z]`。

### 2.3 tile ID 规则【已核实】

```
ID 1..383    → 自动图块（autotile）区域，7 个 autotile 各占 48 格（tileset 里 autotile_names[0..6]）
ID 384 起    → Tilesets 图片内的普通图块，偏移 = ID - 384
               图片 256px 宽 → 每行 8 个 32px 图块
               col = (ID-384) % 8, row = (ID-384) / 8
```
实测：Map004（tileset 1 "Start"）z0 层 tile ID 范围 48–586，z1 层 234–650，z2 层 234–552；
`start.png`（256×1200=296 块）与 passages 长度 680 = 384 + 296 完全吻合。

### 2.4 通行/地形/优先级继承自 Tileset【已核实】

- 地图本身**没有**通行数据，全部由 `@tileset_id` 指向的 `Tilesets.rxdata[i]` 决定：
  - `@passages`（Table，长度 = 384 + 图片块数）：`v & 0x0F != 0` 或 `v & 0x80 != 0` → 不可通行
  - `@terrain_tags`：地形标签（1 起），驱动脚步声 `FOOTSTEP_SFX[tileset_id-1][tag-1]`
  - `@priorities`：z 优先级
- **做新地图想改通行 → 只能改 tileset 的 passages 表**，或复用现有 tileset 的图块语义。

### 2.5 `MapInfos.rxdata`【已核实】

`Hash{ id => RPG::MapInfo }`，字段 `@name / @parent_id / @order`（共 263 条，Map001–Map263）。
新地图必须在此登记（含 parent_id 层级与 order），否则地图名/层级显示异常。

### 2.6 覆盖生效机制【已核实】

`modshot.json` 的 `patches: ["mods/mod"]` → 引擎优先加载 `OneShot/mods/mod/Data/*.rxdata`，
同名覆盖原版。**新地图只需放到 `mods/mod/Data/Map264.rxdata`（或任意新编号）+ 覆盖 `MapInfos.rxdata`**。

---

## 3. 工具链选型（三方案对比）

| 方案 | 工具 | 优点 | 缺点 | 适用 |
|---|---|---|---|---|
| **A. 脚本生成**（推荐） | Ruby + 本仓库 runtime / Python + `rmxpm.py` | 精确可控、可复用、支持程序化铺砖；本仓库已具备全部解码能力 | 无 WYSIWYG 预览 | 新地图从零画/批量生成/复制改造 |
| B. 游戏内可视化编辑 | `event_editor.rb`（Ctrl+E） | 真实运行环境、所见即所得、持久化到 `event_edits.json` | 只编辑**事件位置/方向**，不编辑图块层 | 事件摆放微调 |
| C. 网页联动编辑 | `door_graph_server.py` + `door_graph.html` + `live_sync.rb` | 门连接可视化、拖拽修改事件并实时写回（`event_modify.json`） | 需起本地服务器；同样不编辑图块层 | 门/传送落点联调 |

**图块层的可视化绘制**：方案 A 之外，可选用 **Tiled 编辑器 + 自写 tmx→rxdata 转换脚本**
（图块层仍是 Tiled 最顺手的工具；转换器把 `tmx` 的 csv 层数据映射为 `Table` 16 位布局并生成事件）。
这是当前仓库缺失的一环，可作为下一步工具开发项【推断：tmx 格式为公开标准，OneShot 图块可直接导入】。

---

## 4. 推荐执行流程（7 步）

```
① 选型定图    选择 tileset（31 个现成图块集：Start/Blue/Green/Red/Study/…）+ 地图尺寸
② 铺图块层    用脚本/Tiled 填 Table(w,h,3)：z0 地面、z1 墙体家具、z2 屋顶覆盖
③ 生成地图    Marshal 写出 MapXXX.rxdata（16 位 Table + 空 events）
④ 登记注册    更新 MapInfos.rxdata（name/parent/order）+ 放入 mods/mod/Data/
⑤ 事件摆放    游戏内 Ctrl+E 放置/拖拽事件 + 写对话/传送命令
⑥ 门连接联调  door_graph.html 连接传送门 ↔ jump_points.json 落点
⑦ 验证验收    Ctrl+G 看通行热区、Ctrl+J 跳图、脚本校验 passages
```

---

## 5. 最小可用脚本（方案 A 核心，可直接运行）

用本仓库 runtime Ruby（`runtime/lib/ruby/3.1.0`）执行。完整 RGSS 类骨架见
`_analyze/dump_map.rb`（Tone/Color/Table 的 `_dump`/`_load` 已写好），下方脚本在其基础上
**生成**一张空地图：

```ruby
# make_map.rb —— 生成一张空白 mod 地图
# 用法: ruby make_map.rb 264 40 30 1
require 'zlib'

# ---- RGSS 序列化骨架（复制自 _analyze/dump_map.rb）----
class Tone
  attr_accessor :red, :green, :blue, :gray
  def initialize(r = 0, g = 0, b = 0, gray = 0); @red = r; @green = g; @blue = b; @gray = gray; end
  def _dump(depth); [@red, @green, @blue, @gray].pack('d4'); end
  def self._load(s); r, g, b, gr = s.unpack('d4'); new(r, g, b, gr); end
end
class Color
  attr_accessor :red, :green, :blue, :alpha
  def initialize(r = 0, g = 0, b = 0, a = 255); @red = r; @green = g; @blue = b; @alpha = a; end
  def _dump(depth); [@red, @green, @blue, @alpha].pack('d4'); end
  def self._load(s); r, g, b, a = s.unpack('d4'); new(r, g, b, a); end
end
class Table
  attr_accessor :dim, :xsize, :ysize, :zsize, :data
  def initialize(x, y, z)
    @dim = z > 0 ? 3 : (y > 0 ? 2 : 1)
    @xsize = x; @ysize = y; @zsize = z
    @data = Array.new(x * y * z, 0)
  end
  def [](x, y = 0, z = 0); @data[x + @xsize * y + @xsize * @ysize * z]; end
  def []=(x, y, z, v); @data[x + @xsize * y + @xsize * @ysize * z] = v; end
  def _dump(depth)
    size = @xsize * @ysize * @zsize
    [@dim, @xsize, @ysize, @zsize, size].pack('L5') + @data.pack('v*')  # ← 16 位！
  end
  def self._load(s)
    dim, xs, ys, zs, size = s.unpack('L5')
    t = allocate; t.dim = dim; t.xsize = xs; t.ysize = ys; t.zsize = zs
    t.data = s.byteslice(20, size * 2).unpack('v*')  # ← 16 位！
    t
  end
end
module RPG
  class Map; end; class Event; end; class EventCommand; end
  class AudioFile; end; class MoveRoute; end; class MoveCommand; end
end
class RPG::Event::Page; end
class RPG::Event::Page::Condition; end
class RPG::Event::Page::Graphic; end

# ---- 主流程 ----
id    = (ARGV[0] || 264).to_i
w     = (ARGV[1] || 40).to_i
h     = (ARGV[2] || 30).to_i
tileset_id = (ARGV[3] || 1).to_i

map = RPG::Map.new
map.instance_variable_set(:@tileset_id, tileset_id)
map.instance_variable_set(:@width, w)
map.instance_variable_set(:@height, h)
map.instance_variable_set(:@data, Table.new(w, h, 3))
map.instance_variable_set(:@events, {})
map.instance_variable_set(:@encounter_list, [])
map.instance_variable_set(:@encounter_step, 30)
map.instance_variable_set(:@bgm, RPG::AudioFile.new('', 100, 100))
map.instance_variable_set(:@bgs, RPG::AudioFile.new('', 80, 100))
map.instance_variable_set(:@autoplay_bgm, false)
map.instance_variable_set(:@autoplay_bgs, false)

# 铺一块地面示例：tile 485（start.png 第 101 块，col5 row12）
data = map.instance_variable_get(:@data)
(0...w).each { |x| (0...h).each { |y| data[x, y, 0] = 485 if y < 10 } }

out = "OneShot/mods/mod/Data/Map%03d.rxdata" % id
File.binwrite(out, Marshal.dump(map))
puts "wrote #{out} (#{w}x#{h}, tileset #{tileset_id})"
```

> 事件骨架：在 `@events` 里加 `RPG::Event`（`@id/@name/@x/@y/@pages`），
> 页内 `@list` 是 `RPG::EventCommand`（`@code/@indent/@parameters`）数组，
> 命令码 101–355 见 `MOD_KNOWLEDGE.md` 第 5 章。最简单做法：**复制现有地图的事件做模板改坐标**。

---

## 6. 图块 ID 速查（31 个 tileset 的起始偏移）

| tileset_id | 名称 | 图片 | 图块数 | 可用 ID 范围（384 起） |
|---|---|---|---|---|
| 1 | Start | start.png | 296 | 384–679 |
| 2 | Blue | blue.png | 1248 | 384–1631 |
| 3 | Blue Interior | blue_in.png | 896 | 384–1279 |
| 4 | Green | green.png | 1248 | 384–1631 |
| 5 | Green Interior | green_in.png | 480 | 384–863 |
| 6 | Red | red.png | 800 | 384–1183 |
| 7 | Red Interior | red_in.png | 896 | 384–1279 |
| 8 | Tower-old | tower.png | 600 | 384–983 |
| 9 | debug | red_start.png | 128 | 384–511 |
| 10 | Blank | blank.png | 16 | 384–399 |
| 11 | Blue Factory Interior | factory in.png | 464 | 384–847 |
| 12 | Red Ground | red_ground.png | 696 | 384–1079 |
| 13 | Red Factory | red_factory.png | 896 | 384–1279 |
| 14 | Red Factory Interior | red_factory_in.png | 496 | 384–879 |
| 15 | Red Obsdeck | red_obsdeck.png | 648 | 384–1031 |
| 16 | Red alley | red_alley.png | 1200 | 384–1583 |
| 17 | Blue outpost | blue_outposts.png | 896 | 384–1279 |
| 18 | Blue mineshaft | blue_mineshaft.png | 896 | 384–1279 |
| 19 | Tower | tower.png | 600 | 384–983 |
| 20 | Start Tower | start_tower.png | 296 | 384–679 |
| 21 | start line | start_line.png | 296 | 384–679 |
| 22 | Green mineshaft | green_mineshaft.png | 896 | 384–1279 |
| 23 | Green Interior_boat | green_in copy.png | 480 | 384–863 |
| 25 | Finale | finale.png | 800 | 384–1183 |
| 26 | Study | study.png | 848 | 384–1231 |
| 27 | unreality | unreality.png | 528 | 384–911 |
| 28 | unreality2 | unreality2.png | 528 | 384–911 |

> 注：`RULER.png`（32×1024=32 块）、`pshot.png`（504）、`tower_negativespace.png`（464）、
> `green_mineshaft` 对应 ts22，ts24/29/30 名为空（占位，图片为空或未用）。
> 查任意 tile 的通行：`Tilesets.rxdata[i].passages[id] & 0x0F`。

---

## 7. 事件层：用现有 mod 工具做可视化编辑

### 7.1 游戏内事件编辑器（已存在，`event_editor.rb`）【已核实】
- **Ctrl+E** 进入编辑模式：事件按类型着色（门/出口=蓝、玩家接触=橙、其他=灰），跟随镜头滚动。
- **鼠标**：左键选中、拖拽逐格移动（节流 0.08s 写入）；**滚轮**循环方向（下/左/右/上）。
- **键盘降级**：方向键移动光标，Enter 落定，`[` `]` 转方向。
- 改动持久化到 `settings/event_edits.json`，进图自动应用；换图/读档/重启仍生效。
- 编辑时拦截 `Scene_Map#update` 的 super → 玩家/事件/镜头全暂停。

### 7.2 网页门连接编辑器（已存在）【已核实】
- `tools/start_door_graph.bat` → `door_graph_server.py`（轮询文件 mtime，WebSocket 推送）。
- `live_sync.rb` 每 0.5s 写 `settings/live_state.json`（地图 id/名称、玩家坐标方向、全部事件 id/name/x/y/dir + 动态传送变量值）。
- 网页修改写入 `settings/event_modify.json`，游戏端每帧读取应用后删除；并同步写 `$data_maps`（重载仍生效）。
- 门连接结构在 `settings/graph.json`（由 `_analyze/build_door_graph.rb` 预扫描 1199 个门事件生成）。

### 7.3 新地图加入门连接/快速旅行
- 落点：新地图的传送事件被 `_analyze/rescan_points.rb` 扫描后可进 `jump_points.json`（Ctrl+J 直达）。
- 快速旅行：往 `xscripts/0096_Data_FastTravel.rb` 的 `FastTravel::ZONES` 对应 zone 加一个条目
  （`unlock_map` 通过查找名为 `FAST TRAVEL` 的事件取落点），需重打包 `xScripts.rxdata`（`pack_xscripts.rb`）。

---

## 8. 验证清单

| 检查项 | 方法 |
|---|---|
| 地图可加载、尺寸正确 | 启动游戏 → Ctrl+J 跳入新地图（需先登记 jump_points 或事件传送） |
| 通行正确（无穿墙/无卡死） | Ctrl+G 调试图层：红色=四向不可通行、橙色=部分可通行 |
| 落点安全（不落在墙里） | `_analyze/check_passability.rb` / `verify_points.rb` |
| 图块 ID 合法 | 脚本校验：所有 ID ∈ (0) ∪ [384, 384+图块数)；autotile 区域仅 1–383 |
| 事件不重叠/触发正常 | 游戏内 Ctrl+E 目视 + `_analyze/check_ev_list.rb` |
| MapInfos 层级正确 | 地图名显示（含父级路径） |
| 存档/读档正常 | 新图保存 → 退出 → 读档（注意 `skip_event` 的 real_load 铁律） |

---

## 9. 常见坑（已核实/高置信）

1. **Table 必须 16 位存取**——用 `'l*'` 会得到天文数字 tile id（本项目实测踩坑）。
2. **地图没有自己的通行表**——想改通行必须改 tileset 的 `passages`，或调整图块选用。
3. **tile ID 偏移 384**——把图片第 1 块误当 ID 1，会画成 autotile 区（ID 1–383），显示完全错乱。
4. **新地图编号避免冲突**——当前 263 张已占用，新图从 264 起；覆盖 MapInfos 时必须保留原 263 条 + 新增。
5. **z2 层不要乱用**——只有 3 个 ID 的地图也要注意 z2 是屋顶/覆盖层，画太多会挡角色。
6. **events Hash 的 key 必须与事件 @id 一致**，且从 1 起连续（引擎按 id 遍历）。
7. **jump_points.json 由脚本生成**——手工编辑后如被 `rescan_points.rb` 重跑会覆盖，需维护脚本白名单。

---

## 10. 待办（建议的下一步工具开发）

1. **tmx→rxdata 转换器**（Tiled 可视化画图块层 → 本仓库格式）【当前缺失，收益最大】
2. **tileset 图块浏览器/ID 拾取器**（从 PNG 点选图块得到 ID 与通行值）
3. **地图渲染预览脚本**（把 Table 三层 + tileset PNG 合成一张 PNG 预览，替代进游戏验证）

---

*本方案全部数据格式结论均来自对本仓库数据的直接解析验证；工具链清单来自对现有脚本的源码阅读。*
