# ============================================================
#  jump_map.rb — "Jump Map" 跳地图界面 (Window_JumpMap)
#
#  在开发者设置(Window_DevSettings)中作为 "Jump Map" 栏进入:
#  列出全部地图(含 debug/内部/测试图), 选中即模仿原版 FastTravel
#  的传送链做黑屏转场跳转。书页式列表, 每页 JUMP_MAP_PER_PAGE 条,
#  左右键翻页, 上下键页内选择。
#
#  纯 preload 实现, 不修改游戏原始文件。
#
#  ★ 数据源 (2026-09 重构: 不再依赖手工维护的 jump_points.json):
#    * 地图列表 : 运行时读取 Data/MapInfos.rxdata (惰性缓存) ——
#                 新增/改名/删除地图自动同步, 无需维护外部 JSON。
#    * 落点     : 跳转确认时解析, 优先级:
#                  1) 可选覆盖层 jump_points.json (有效 x/y, 人工微调)
#                  2) 原游戏入口落点 —— 首次打开跳地图时预构建索引,
#                     收集全部地图事件页 + 公共事件中的 Transfer Player
#                     (201) 指令 (即门事件/切换地图时玩家出现的位置);
#                  3) 地图中心 —— 中心不可通行时 BFS 环形扩张找最近可行格;
#                  4) 全图不可通行/读取失败回退 (0,0),
#                     由 live_update 的障碍物自动飞行脱困。
#    通行判定复刻 Game_Map#passable? 的 tileset 层 (与 debug_map.rb 同源)。
#
#  依赖:
#    dev_settings.rb 提供 Window_DevSettings(EXTRA_ACTIONS 入口 / open_jump_map)
#    skip_event.rb 提供自由浏览模式的事件阻止规则 ($jump_map_free_mode)
#    shortcut_keys.rb 提供 Ctrl+J 快捷键入口
#    config.json: "is_developer": true
# ============================================================

require 'json'

# --- 自由浏览模式开关 ---
# 跳转成功后进入自由浏览模式($jump_map_free_mode = true):
# 该模式下 skip_event.rb 的事件级阻止规则生效(原 jump_map_free.rb
# 的冻结补丁已统一并入 skip_event.rb) —— 演出事件整体不启动,
# 玩家自由行动; 模式持续到游戏重启。
JUMP_MAP_FREEZE_AUTORUN = true

# 可选覆盖层路径(文件不存在则完全动态): Scripts/../jump_points.json
JUMP_POINTS_PATH = File.join(__dir__, '..', 'jump_points.json')

# 一页最多显示条数(书页式)
JUMP_MAP_PER_PAGE = 10

# --- 动态跳转数据源 ---
# 地图列表 = Data/MapInfos.rxdata(唯一真源); 落点 = 运行时计算(覆盖层优先)。
module JumpPoints
  module_function

  # 运行时惰性加载 MapInfos(游戏初始化后 load_data 可用); 失败回退空表
  def mapinfos
    @mapinfos ||= begin
      load_data('Data/MapInfos.rxdata')
    rescue StandardError
      {}
    end
  end

  # 全部地图列表: 按 MapInfos 的 parent_id 做深度优先(DFS)树形遍历,
  # 与 RPG Maker XP 编辑器左侧地图树一致; 每项带 depth 字段用于缩进显示。
  def all_maps
    infos = mapinfos
    # 按 parent_id 分组
    children = Hash.new { |h, k| h[k] = [] }
    infos.each do |id, info|
      next unless info
      children[info.parent_id] << [id.to_i, info]
    end
    # 每组按 order 排序 (RPG Maker XP 树中同级地图的顺序)
    children.each { |_k, v| v.sort_by! { |_id, info| info.order } }

    result = []
    # DFS: 从 parent_id=0 的根节点开始, 递归遍历子节点
    dfs = lambda do |parent_id, depth|
      children[parent_id].each do |id, info|
        name = !info.name.to_s.empty? ? info.name.to_s : "Map#{id}"
        result << { id: id, name: name, depth: depth, x: nil, y: nil, dir: 2 }
        dfs.call(id, depth + 1)
      end
    end
    dfs.call(0, 0)
    result
  end

  # 落点解析优先级: 可选覆盖层(有效 x/y) -> 原游戏入口落点(跨地图传送201指令)
  # -> 地图中心(不可通行时环形扩张) -> 回退 (0,0) (live_update 自动飞行兜底)
  def landing(map_id)
    ov = overlay[map_id.to_s]
    if ov.is_a?(Hash) && ov['x'].to_i >= 0 && ov['y'].to_i >= 0
      return { x: ov['x'].to_i, y: ov['y'].to_i, dir: ov['dir'].to_i }
    end
    map = (load_data(sprintf('Data/Map%03d.rxdata', map_id)) rescue nil)
    return { x: 0, y: 0, dir: 2 } unless map
    ts = tileset(map.tileset_id)
    return { x: 0, y: 0, dir: 2 } unless ts
    w = map.width
    h = map.height
    data = map.data
    passages = ts.passages
    priorities = ts.priorities
    # 1) 原游戏入口落点: 所有指向本图的 Transfer Player(201) 指令的落点
    (entrances[map_id] || []).uniq.each do |ex, ey, edir|
      next unless landable?(data, passages, priorities, ex, ey, w, h)
      return { x: ex, y: ey, dir: edir.to_i }
    end
    # 2) 地图中心(从中心环形扩张找最近可行格)
    cx, cy = center_landing(data, passages, priorities, w, h)
    { x: cx, y: cy, dir: 2 }
  end

  # 可选覆盖层: jump_points.json 存在则读取(向后兼容旧数据/人工微调)
  def overlay
    @overlay ||= begin
      if File.exist?(JUMP_POINTS_PATH)
        JSON.parse(File.read(JUMP_POINTS_PATH))
      else
        {}
      end
    rescue StandardError
      {}
    end
  end

  # 原游戏入口落点索引: map_id -> [[x, y, dir], ...]
  # 来源: 全部地图事件页 + 公共事件中的 Transfer Player(201) 指令
  # (即"切换地图/门事件"时玩家实际出现的位置)。一次性构建并缓存;
  # 构建耗时写入 jump_map_runtime.txt。构建失败降级为空索引(全部回退中心)。
  def entrances
    return @entrances if @entrances
    begin
      t0 = Time.now
      idx = {}
      # 公共事件中的传送(如公共门/传送脚本)
      ces = (load_data('Data/CommonEvents.rxdata') rescue nil)
      ces.each { |ce| scan_command_list(idx, ce.list) if ce } if ces
      # 所有地图事件页
      mapinfos.keys.each do |mid|
        map = (load_data(sprintf('Data/Map%03d.rxdata', mid)) rescue nil)
        next unless map
        map.events.each_value do |ev|
          ev.pages.each { |pg| scan_command_list(idx, pg.list) }
        end
      end
      @entrances = idx
      total = idx.values.sum(&:size)
      jlog_sync("entrance index built: #{mapinfos.size} maps, #{total} transfers (#{((Time.now - t0) * 1000).to_i}ms)")
    rescue StandardError => e
      @entrances = {}
      jlog_sync("entrance index build FAILED, fallback to map-center: #{e.class}: #{e.message}")
    end
    @entrances
  end

  # 从事件命令列表提取 Transfer Player(201): parameters = [map_id, x, y, dir, ...]
  def scan_command_list(idx, list)
    return unless list
    list.each do |cmd|
      next unless cmd.code == 201
      p = cmd.parameters
      next unless p && p.size >= 3
      mid = p[0]
      next unless mid.is_a?(Integer) && mid > 0
      (idx[mid] ||= []) << [p[1].to_i, p[2].to_i, p[3].to_i]
    end
  end

  # 地图中心落点: 中心格可行则用之, 否则 BFS 环形扩张找最近可行格;
  # 全图不可通行回退 (0,0) (live_update 自动飞行兜底)
  def center_landing(data, passages, priorities, w, h)
    cx = w / 2
    cy = h / 2
    return [cx, cy] if landable?(data, passages, priorities, cx, cy, w, h)
    seen = { [cx, cy] => true }
    q = [[cx, cy]]
    head = 0
    while head < q.size
      x, y = q[head]
      head += 1
      [2, 4, 6, 8].each do |d|
        nx = x + (d == 6 ? 1 : d == 4 ? -1 : 0)
        ny = y + (d == 2 ? 1 : d == 8 ? -1 : 0)
        next if nx < 0 || ny < 0 || nx >= w || ny >= h
        k = [nx, ny]
        next if seen[k]
        seen[k] = true
        return [nx, ny] if landable?(data, passages, priorities, nx, ny, w, h)
        q << [nx, ny]
      end
    end
    [0, 0]
  end

  # Tilesets 数据库(按 tileset_id 索引, 惰性加载并缓存)
  def tileset(tileset_id)
    @tilesets ||= (load_data('Data/Tilesets.rxdata') rescue nil)
    @tilesets && @tilesets[tileset_id]
  end

  # 该格是否"存在至少一个可通行相邻格"(站上去能走出去)
  def landable?(data, passages, priorities, x, y, w, h)
    [2, 4, 6, 8].any? do |d|
      nx = x + (d == 6 ? 1 : d == 4 ? -1 : 0)
      ny = y + (d == 2 ? 1 : d == 8 ? -1 : 0)
      next false if nx < 0 || ny < 0 || nx >= w || ny >= h
      static_passable?(data, passages, priorities, nx, ny, 1 << (d / 2 - 1))
    end
  end

  # tileset 静态层判定: 复刻 Game_Map#passable?(xscripts/0016:359-388),
  # 与 debug_map.rb 的 static_passable? 同源(含 blank 三空层逻辑)。
  # 注意: 判定对象是"目标格"(从当前格向 d 走要检查的格), 与 passable? 一致。
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

  # 同步日志(入口索引构建耗时等): 复用 jump_map_runtime.txt
  def jlog_sync(msg)
    begin
      dir = File.join(__dir__, '..', 'logs')
      Dir.mkdir(dir) unless File.directory?(dir)
      File.open(File.join(dir, 'jump_map_runtime.txt'), 'a') do |f|
        f.puts("[#{Time.now.strftime('%H:%M:%S')}] #{msg}")
      end
    rescue StandardError
    end
  end
end

# --- 地图跳转子界面 ---
# 书页式: 每页 JUMP_MAP_PER_PAGE 条, 底部显示页码, 左右键翻页, 上下键页内选择。
# 背景全程不透明黑色(淡入淡出只作用于文字), 避免跳转时露出下层设置菜单。
class Window_JumpMap
  MARGIN = 30
  TITLE_TOP_MARGIN = 32
  TITLE_MARGIN = 100
  ITEM_SPACING = 28
  ACTIVE_MARGIN = MARGIN * 2 + 20

  # 跳转成功后的回调(由外层设置, 用于关闭设置窗口)
  attr_accessor :on_transfer
  # 直接打开(Ctrl+J 入口)时: 取消键一次全关回游戏, 不再回 dev_settings 菜单
  attr_accessor :close_all_on_cancel

  def initialize
    @viewport = Viewport.new(0, 0, 640, 480)
    @bg = Sprite.new(@viewport)
    @bg.bitmap = Bitmap.new(640, 480)
    # 不透明黑底, 完全遮住下层(开发者设置/设置页)的文字; 淡入淡出期间保持全黑
    @bg.bitmap.fill_rect(0, 0, 640, 480, Color.new(0, 0, 0, 255))
    @bg.opacity = 255
    @title = Sprite.new(@viewport)
    @title.bitmap = Bitmap.new(420, TITLE_MARGIN)
    @title.bitmap.font.size = 40
    @title.y = TITLE_TOP_MARGIN
    @title.x = MARGIN
    @title.opacity = 0
    # 底部页码
    @page_sprite = Sprite.new(@viewport)
    @page_sprite.bitmap = Bitmap.new(120, 24)
    @page_sprite.x = 640 - 120 - 24
    @page_sprite.y = 452
    @page_sprite.opacity = 255
    # 高于 Window_DevSettings 的 viewport z(9999), 保证盖住下层
    @viewport.z = 10000
    @data_sprites = []
    @index = 0     # 全局选中索引(在整个 @maps 中的位置)
    @page = 0      # 当前页码(0-based)
    @visible = false
    @fade_in = false
    @fade_out_ticks = 0
    @fade_out = false
    @transfer_player = nil
    @maps = []
    @mapinfos = nil
    @on_transfer = nil
  end

  def visible
    @visible
  end

  def visible=(val)
    @viewport.visible = val
    @visible = val
  end

  # 背景始终全黑, 淡入淡出只作用于文字层
  def opacity=(val)
    @title.opacity = val
  end

  # 打开跳地图列表
  def open
    load_maps
    return if @maps.empty?
    JumpPoints.entrances   # 预热入口落点索引(首次构建约 1-3s, 此后缓存复用, 卡顿只发生在第一次打开)
    # 定位当前所在地图: 若在可跳列表中则跳到对应页并选中, 否则回退到第 0 页首项
    cur = locate_current_map
    if cur
      @index = cur
      @page = cur / JUMP_MAP_PER_PAGE
    else
      @index = 0
      @page = 0
    end
    @bg.opacity = 255
    @title.opacity = 0
    @page_sprite.opacity = 255
    self.visible = true
    @fade_in = true
    @title.bitmap.clear
    @title.bitmap.draw_text(0, 0, @title.bitmap.width, @title.bitmap.height, tr('Jump Map'))
    jlog("open maps=#{@maps.size} page=#{@page + 1}/#{page_count}")
    refresh_list
  end

  # 帧更新: 淡入 -> 选择 -> 淡出 -> 设置传送 flags
  # 运行时日志(仅记录关键事件, 定位"传送后不收回"类问题)
  def jlog(msg)
    begin
      dir = File.join(__dir__, '..', 'logs')
      Dir.mkdir(dir) unless File.directory?(dir)
      File.open(File.join(dir, 'jump_map_runtime.txt'), 'a') { |f| f.puts("[#{Time.now.strftime('%H:%M:%S')}] #{msg}") }
    rescue StandardError
    end
  end

  def update
    begin
      update_inner
    rescue StandardError => e
      # 关键: 捕获异常并记录, 绝不让界面因异常而冻结(shortcut_keys 的 rescue 会吞掉并落 super)
      jlog("update error: #{e.class}: #{e.message}")
      jlog(e.backtrace.first(6).join(" | ")) if e.backtrace
    end
  end

  def update_inner
    if @fade_in
      @title.opacity += 20
      @title.opacity = 255 if @title.opacity > 255
      @data_sprites.each do |spr|
        spr.opacity += 10
        spr.opacity = 128 if spr.opacity > 128
      end
      # 首项滑入(活动光标)
      if @data_sprites[0] && @data_sprites[0].x < MARGIN * 2
        @data_sprites[0].x += 6
        @data_sprites[0].x = MARGIN * 2 if @data_sprites[0].x > MARGIN * 2
      end
      if @title.opacity >= 255
        @fade_in = false
      end
      return
    end

    if @fade_out
      @fade_out_ticks = (@fade_out_ticks || 0) + 1   # 兜底: 帧计数强制完成, 防 update 驱动异常导致淡出卡死
      # 背景保持全黑, 只淡出文字, 保证 Graphics.freeze 冻结的是纯黑画面
      @title.opacity -= 20
      @data_sprites.each { |spr| spr.opacity -= 10 }
      @page_sprite.opacity -= 10
      if @title.opacity <= 0 || @fade_out_ticks >= 120
        @fade_out_ticks = 0
        @fade_out = false
        self.visible = false
        @data_sprites.each { |spr| spr.dispose }
        @data_sprites = []
        if @transfer_player
          # 开启自由浏览模式: 冻结目标地图的 autorun, 避免剧情事件锁住玩家
          if JUMP_MAP_FREEZE_AUTORUN
            $jump_map_free_mode = true
            # 清掉 transfer 过程中可能残留运行的地图事件解释器
            if $game_system && $game_system.map_interpreter
              $game_system.map_interpreter.clear
              $game_system.map_interpreter.instance_variable_set(:@list, nil)
            end
          end
          # 模仿原版 FastTravel 的传送链:
          # Scene_Map#update 检测到 player_transferring 后执行 transfer_player
          $game_temp.player_transferring = true
          $game_temp.player_new_map_id = @transfer_player[:id]
          $game_temp.player_new_x = @transfer_player[:x]
          $game_temp.player_new_y = @transfer_player[:y]
          $game_temp.player_new_direction = @transfer_player[:dir]
          Graphics.freeze
          $game_temp.transition_processing = true
          $game_temp.transition_name = "black"
          jlog("fade_out done, transfer=#{!!@transfer_player}, on_transfer=#{!@on_transfer.nil?}")
          @on_transfer.call if @on_transfer
          @transfer_player = nil
        end
      end
      return
    end

    return if !@visible

    # 光标动画(与 Window_Settings/FastTravel 视觉一致)
    @data_sprites.each_with_index do |spr, i|
      if i == @index - @page * JUMP_MAP_PER_PAGE
        if spr.x < ACTIVE_MARGIN
          spr.x += 6
          spr.x = ACTIVE_MARGIN if spr.x > ACTIVE_MARGIN
        end
        spr.opacity += 10 if spr.opacity < 255
      else
        if spr.x > MARGIN * 2
          spr.x -= 6
          spr.x = MARGIN * 2 if spr.x < MARGIN * 2
        end
        spr.opacity -= 10 if spr.opacity > 128
        spr.opacity = 128 if spr.opacity < 128
      end
    end

    page_start = @page * JUMP_MAP_PER_PAGE
    page_last = [page_start + JUMP_MAP_PER_PAGE, @maps.size].min - 1

    # 上下键: 仅在本页内移动光标
    if Input.trigger?(Input::UP)
      @index = (@index > page_start) ? @index - 1 : page_last   # 页内循环: 页顶继续向上回页底
      $game_system.se_play($data_system.cursor_se)
    end
    if Input.trigger?(Input::DOWN)
      @index = (@index < page_last) ? @index + 1 : page_start   # 页内循环: 页底继续向下回页顶
      $game_system.se_play($data_system.cursor_se)
    end

    # 左右键: 整页翻页
    if Input.trigger?(Input::LEFT)
      if @page > 0
        @page -= 1
        @index = @page * JUMP_MAP_PER_PAGE
        refresh_list
        $game_system.se_play($data_system.cursor_se)
      end
    end
    if Input.trigger?(Input::RIGHT)
      if @page < page_count - 1
        @page += 1
        @index = @page * JUMP_MAP_PER_PAGE
        refresh_list
        $game_system.se_play($data_system.cursor_se)
      end
    end

    # 确认: 此时解析落点(覆盖层优先, 否则动态计算), 保存目标并淡出;
    # 淡出结束后设置传送 flags
    if Input.trigger?(Input::ACTION)
      $game_system.se_play($data_system.decision_se)
      jlog("ACTION index=#{@index} map=#{@maps[@index][:name]}(#{@maps[@index][:id]}) -> fade_out")
      @transfer_player = @maps[@index].merge(JumpPoints.landing(@maps[@index][:id]))
      @fade_out = true
      return
    end

    # 取消: 返回开发者设置(开发者设置一直保持可见, 只是被本界面盖住)
    if Input.trigger?(Input::CANCEL)
        jlog("CANCEL close_all=#{@close_all_on_cancel}")
      if @close_all_on_cancel
        # Ctrl+J 直接打开: 取消一次全关(跳地图 + 开发者设置 + 外层设置窗口), 直接回游戏
        @on_transfer.call if @on_transfer
      end
      $game_system.se_play($data_system.cancel_se)
      self.visible = false
    end
  end

  def dispose
    @data_sprites.each { |spr| spr.dispose }
    @page_sprite.dispose
    @title.dispose
    @bg.dispose
    @viewport.dispose
  end

  private

  def page_count
    return 1 if @maps.empty?
    (@maps.size.to_f / JUMP_MAP_PER_PAGE).ceil
  end

  # 当前所在地图在可跳列表中的索引(不在列表中返回 nil)
  def locate_current_map
    return nil unless $game_map
    id = $game_map.map_id
    @maps.index { |mm| mm[:id] == id }
  end

  # 地图列表来自 JumpPoints(MapInfos 动态生成, 缓存复用;
  # 与历史行为一致: 过滤放开, 全量列出)
  def load_maps
    @maps = @maps_cache
    return if @maps
    @maps = JumpPoints.all_maps
    @maps_cache = @maps
  end

  # 重建当前页列表 sprite(翻页时调用) + 更新页码
  def refresh_list
    @data_sprites.each { |spr| spr.dispose }
    @data_sprites = []
    start = @page * JUMP_MAP_PER_PAGE
    visible_items = @maps[start, JUMP_MAP_PER_PAGE] || []
    visible_items.each_with_index do |mm, i|
      spr = Sprite.new(@viewport)
      spr.bitmap = Bitmap.new(420, ITEM_SPACING)
      spr.x = MARGIN * 2   # 原位统一为 MARGIN*2(60): 取消选中后滑回的目标即其他项的静止位, 避免停在半途不对齐
      spr.y = TITLE_MARGIN + TITLE_TOP_MARGIN + ITEM_SPACING * i
      spr.opacity = 0
      # 树形缩进: 每层 depth 用 2 个空格前缀 (与 RPG Maker XP 地图树视觉一致)
      prefix = '  ' * (mm[:depth] || 0)
      spr.bitmap.draw_text(0, 0, spr.bitmap.width, spr.bitmap.height, tr(prefix + mm[:name].to_s))
      @data_sprites << spr
    end
    # 页码: "当前页 / 总页数"
    @page_sprite.bitmap.clear
    @page_sprite.bitmap.draw_text(0, 0, @page_sprite.bitmap.width, @page_sprite.bitmap.height,
                                  "#{@page + 1} / #{page_count}")
  end
end

# --- 写状态文件 ---
StatusLog.write('jump_map_status.txt', [
  "jump_map loaded at = #{Time.now}",
  "data = dynamic: map list from Data/MapInfos.rxdata (cached, no external JSON required)",
  "landing = overlay(x/y>=0) -> original-game entrance (Transfer 201 targets) -> map center (BFS) -> (0,0)",
  "entrances = prebuilt once at first open: all map event pages + CommonEvents, Transfer Player(201) params",
  "overlay = #{JUMP_POINTS_PATH} optional (kept for manual fine-tuning; absent -> fully dynamic)",
  "fallback = (0,0) on read failure / fully-blocked map (live_update auto-fly rescues)",
  "per_page = #{JUMP_MAP_PER_PAGE}",
  "paging = book-style, LEFT/RIGHT flip page, UP/DOWN move cursor",
  "fade = background stays black (no lower menu flash)",
  "method = FastTravel transfer chain (player_transferring + Graphics.freeze + transition_processing 'black')",
  "free_mode = jump_map_free.rb (JUMP_MAP_FREEZE_AUTORUN)"
])
