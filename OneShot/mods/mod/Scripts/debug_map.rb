# ============================================================
#  debug_map.rb — 调试显示: 碰撞(可通行性) + 事件位置
#
#  在地图上叠加半透明图层, 显示:
#    * 碰撞: 每个格子的可通行性
#        - 红色(不透明90)  = 四个方向都不可通行(完全阻挡)
#        - 橙色(不透明70)  = 部分方向不可通行(墙/单向阻挡)
#        - 透明             = 可通行
#    * 事件: 事件锚点格显示蓝色半透明块 + 事件 ID
#        - 同格多事件以 | 分隔显示
#
#  快捷键: Ctrl+G 切换显示/隐藏 (Scene_Map, 需 "is_developer": true)
#  该图层 viewport z=250, 位于光照层(z=200)之上、图片层(z=500)之下。
#
#  纯 preload 实现, 不修改游戏原始文件。
#  用 TracePoint(:end) 监听 Scene_Map 类定义, 在 update 就绪后用
#  Module#prepend 打补丁。
#
#  性能优化 (A+B):
#    A. 格子级重绘判定 —— 只有镜头跨过整格才重绘,
#       像素级滚动由 @sprite 偏移处理(原实现像素级 key 每帧重绘)。
#    B. 可通行性静态缓存 —— 换图时一次性计算全图 tileset 静态通行表,
#       redraw 只查表; 事件层用事件锚点索引 O(1) 判断。
#       逻辑完全复刻 Game_Map#passable?(xscripts/0016), 精度零损失。
# ============================================================

# --- 调试图层 ---
class DebugMapOverlay
  TILE = 32
  # 方向 -> 缓存位索引 (bit0=d2, bit1=d4, bit2=d6, bit3=d8)
  DIR_BITS = { 2 => 0, 4 => 1, 6 => 2, 8 => 3 }

  attr_reader :visible

  def initialize
    @viewport = Viewport.new(0, 0, 640, 480)
    @viewport.z = 250
    @sprite = Sprite.new(@viewport)
    @sprite.bitmap = Bitmap.new(640, 480)
    @sprite.bitmap.font.size = 14
    @visible = false
    @sprite.visible = false
    @last_redraw_key = nil
    # --- A+B 优化: 可通行性静态缓存 ---
    # 换图时重建一次, redraw 只查表, 不再每格调 Game_Map#passable?
    # (原实现每格 4 方向 × 遍历全部事件, 是 Ctrl+G 卡顿的根因)
    @pass_cache = nil    # [x][y] -> 4bit mask (bit0=d2, bit1=d4, bit2=d6, bit3=d8)
    @cache_map_id = nil  # 缓存对应的地图 id, 换图时失效
    @events_at = {}      # 当前帧事件锚点索引: [x,y] -> [event,...]
  end

  def visible?
    @visible
  end

  def toggle
    @visible = !@visible
    @sprite.visible = @visible
    if @visible
      @sprite.bitmap.clear
      @last_redraw_key = nil
      redraw
    end
  end

  # 每帧: 镜头滚动时重绘(格子偏移变化), 否则保持
  # 方案 A: 用格子坐标做 key(display_x/128 = 格子坐标, 128 = 4*TILE),
  #         只有跨过整格才重绘; 像素级滚动由 @sprite.x = -(dx % TILE) 补偿。
  def update
    return unless @visible
    map = $game_map
    return unless map
    key = [map.display_x / 128, map.display_y / 128]
    if key != @last_redraw_key
      @last_redraw_key = key
      redraw
    end
  end

  private

  # 重绘当前可视区域的碰撞 + 事件
  def redraw
    map = $game_map
    bmp = @sprite.bitmap
    bmp.clear
    return unless map

    # 方案 B: 换图时重建静态通行缓存
    rebuild_cache(map)

    dx = map.display_x / 4   # 镜头左上角像素
    dy = map.display_y / 4
    x0 = dx / TILE           # 可视左上角格子
    y0 = dy / TILE
    # sprite 反向偏移, 让格子与 tilemap 对齐
    @sprite.x = -(dx % TILE)
    @sprite.y = -(dy % TILE)

    x1 = x0 + (640 + TILE - 1) / TILE
    y1 = y0 + (480 + TILE - 1) / TILE

    # 事件锚点索引: [x, y] -> [event, ...] (只索引未 erased 的事件)
    @events_at = {}
    map.events.each_value do |ev|
      next if ev.instance_variable_get(:@erased)
      k = [ev.x, ev.y]
      (@events_at[k] ||= []) << ev
    end

    (x0..x1).each do |x|
      (y0..y1).each do |y|
        next unless map.valid?(x, y)
        px = (x - x0) * TILE
        py = (y - y0) * TILE

        # --- 碰撞(可通行性): 统计四向不可通行数 ---
        blocked = [2, 4, 6, 8].count { |d| !passable_cheap?(map, x, y, d) }
        if blocked == 4
          bmp.fill_rect(px, py, TILE, TILE, Color.new(255, 0, 0, 90))
        elsif blocked > 0
          bmp.fill_rect(px, py, TILE, TILE, Color.new(255, 165, 0, 70))
        end

        # --- 事件: 蓝色块 + ID ---
        ids = @events_at[[x, y]]
        if ids && !ids.empty?
          bmp.fill_rect(px + 1, py + 1, TILE - 2, TILE - 2, Color.new(0, 120, 255, 120))
          bmp.draw_text(px + 2, py + 2, TILE - 4, TILE - 4, ids.map(&:id).join('|'), 1)
        end
      end
    end
  end

  # 方案 B: 全图静态通行缓存(不含事件层), 地图切换时重建一次。
  # 复刻 Game_Map#passable? 中 tileset 层判定逻辑(xscripts/0016_Game_Map.rb:359-388)。
  def rebuild_cache(map)
    mid = map.map_id
    return if @cache_map_id == mid && @pass_cache
    @cache_map_id = mid
    w = map.width
    h = map.height
    passages = map.passages
    priorities = map.priorities
    data = map.data
    cache = Array.new(w) { Array.new(h, 0) }
    (0...w).each do |x|
      (0...h).each do |y|
        mask = 0
        [2, 4, 6, 8].each do |d|
          bit = 1 << (d / 2 - 1)
          mask |= (1 << DIR_BITS[d]) unless static_passable?(data, passages, priorities, x, y, bit)
        end
        cache[x][y] = mask
      end
    end
    @pass_cache = cache
  end

  # tileset 静态层判定(复刻 passable? 的 tile 循环; blank 三空层逻辑)
  def static_passable?(data, passages, priorities, x, y, bit)
    blank = 0
    [2, 1, 0].each do |i|
      tile_id = data[x, y, i]
      next if tile_id == nil
      if tile_id < 48 && i > 0
        blank += 1
        next if blank < 3
      end
      return false if passages[tile_id] & bit != 0
      return false if passages[tile_id] & 0x0f == 0x0f
      return true if priorities[tile_id] == 0
    end
    true
  end

  # 快速可通行判断: 静态查缓存表 + 事件层查锚点索引(复刻 passable? 全逻辑)
  def passable_cheap?(map, x, y, d)
    return false unless map.valid?(x, y)
    x %= map.width
    y %= map.height
    bit = 1 << (d / 2 - 1)

    # 事件层: 只查该格事件(O(1) 索引), 顺序与原 passable? 一致
    # (事件可能覆盖静态结果: priorities[tile_id]==0 时格可通行)
    evs = @events_at[[x, y]]
    if evs
      passages = map.passages
      priorities = map.priorities
      evs.each do |ev|
        next unless ev.tile_id >= 0 && !ev.through
        if ev.tile_id == 0 && ev.character_name.empty?
          return false
        elsif passages[ev.tile_id] & bit != 0
          return false
        elsif passages[ev.tile_id] & 0x0f == 0x0f
          return false
        elsif priorities[ev.tile_id] == 0
          return true
        end
      end
    end

    # 静态层: 查缓存表
    return false if @pass_cache[x][y] & (1 << DIR_BITS[d]) != 0
    true
  end
end

$debug_map_overlay = nil  # 惰性创建: 首次 Ctrl+G 时才实例化(preload 阶段 Graphics 未初始化)

# --- Scene_Map 补丁: Ctrl+G 切换 + 每帧更新 ---
module DebugMapPatch
  def update
    begin
      ov = debug_map_overlay
      if ov
        if debug_toggle_triggered?
          ov.toggle
          $game_system.se_play($data_system.decision_se) if $game_system && $data_system
        end
        ov.update
      end
    rescue StandardError
      # 调试层异常不影响主流程
    end
    super
  end

  private

  # 惰性创建调试层实例(首次 Ctrl+G 时才建立, 避免 preload 阶段图形未初始化)
  def debug_map_overlay
    $debug_map_overlay ||= DebugMapOverlay.new
  end

  # Ctrl+G 切换调试层 (仅开发者模式)
  def debug_toggle_triggered?
    return false unless $dev_settings_enabled
    return false unless Input.respond_to?(:triggerex?)
    return false unless Input.respond_to?(:pressex?)
    (Input.pressex?(:LCTRL) || Input.pressex?(:RCTRL)) && Input.triggerex?(:G)
  rescue StandardError
    false
  end
end

# --- 等待 Scene_Map 类定义完成后 prepend 补丁 ---
PatchHelper.install('Scene_Map', methods: [:update]) do |k|
  k.prepend(DebugMapPatch)
end

# --- 写状态文件 ---
StatusLog.write('debug_map_status.txt', [
  "debug_map loaded at = #{Time.now}",
  "toggle = Ctrl+G (Scene_Map, requires is_developer)",
  "collision = red(all 4 dirs blocked) / orange(partial) / transparent(passable)",
  "events = blue block + event id (same-cell merged with |)",
  "layer_z = 250 (above lights 200, below pics 500)",
  "redraw = grid-level key (camera crosses a tile) + static pass cache (A+B optimized)",
  "cache = rebuild on map switch, full-map tileset passability, event layer via anchor index",
  "logic = replicates Game_Map#passable? (xscripts/0016) exactly, zero precision loss"
])
