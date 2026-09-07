# ============================================================
#  jump_map.rb — "Jump Map" 跳地图界面 (Window_JumpMap)
#
#  在开发者设置(Window_DevSettings)中作为 "Jump Map" 栏进入:
#  列出可跳地图(过滤内部/debug/测试图), 选中即模仿原版 FastTravel
#  的传送链做黑屏转场跳转。书页式列表, 每页 JUMP_MAP_PER_PAGE 条,
#  左右键翻页, 上下键页内选择。
#
#  纯 preload 实现, 不修改游戏原始文件。
#  落点数据: mods/mod/jump_points.json (预扫描生成, 见附录说明)
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

# jump_points.json 路径: Scripts/../jump_points.json
JUMP_POINTS_PATH = File.join(__dir__, '..', 'jump_points.json')

# --- 地图过滤 ---
# 1) 名字黑名单: 命中即不显示
JUMP_MAP_FILTER = /IGNORE|DEBUG|INTERNAL|UNUSED|\bTEST\b|^INIT\b|TELEPORT|DEMO|PROTOWALK|PSHOT|LANGUAGE\s?DEBUG|LANG\s?DEBUG/i
# 2) 纯代号测试图 (Tower 下的 Teleport/Crossroads/Step 测试分支: T1..T16, C1..C7, S1..S4)
JUMP_MAP_NAME_PATTERN = /^[TCS]\d+$/i
# 3) 祖先链黑名单: 若某地图的父级链上存在这些名字, 也视为内部图
JUMP_MAP_PARENT_FILTER = /IGNORE|DEBUG|UNUSED|INTERNAL|\bTEST\b|^INIT\b|TELEPORT/i

# 一页最多显示条数(书页式)
JUMP_MAP_PER_PAGE = 10

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
    refresh_list
  end

  # 帧更新: 淡入 -> 选择 -> 淡出 -> 设置传送 flags
  def update
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
      if @index > page_start
        @index -= 1
        $game_system.se_play($data_system.cursor_se)
      end
    end
    if Input.trigger?(Input::DOWN)
      if @index < page_last
        @index += 1
        $game_system.se_play($data_system.cursor_se)
      end
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

    # 确认: 保存目标并淡出, 淡出结束后设置传送 flags
    if Input.trigger?(Input::ACTION)
      $game_system.se_play($data_system.decision_se)
      @transfer_player = @maps[@index]
      @fade_out = true
      return
    end

    # 取消: 返回开发者设置(开发者设置一直保持可见, 只是被本界面盖住)
    if Input.trigger?(Input::CANCEL)
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

  # 运行时惰性加载 MapInfos(游戏初始化后 load_data 可用)
  def mapinfos
    @mapinfos ||= begin
      load_data('Data/MapInfos.rxdata')
    rescue StandardError
      {}
    end
  end

  # 祖先链是否含内部图标记
  def ancestor_blacklisted?(id)
    seen = {}
    cur = id
    while cur && cur > 0 && !seen[cur]
      seen[cur] = true
      info = mapinfos[cur]
      break unless info
      return true if info.name.to_s =~ JUMP_MAP_PARENT_FILTER
      cur = info.parent_id.to_i
    end
    false
  end

  # 当前所在地图在可跳列表中的索引(不在列表中返回 nil)
  def locate_current_map
    return nil unless $game_map
    id = $game_map.map_id
    @maps.index { |mm| mm[:id] == id }
  end

  # 从 jump_points.json 加载可跳地图(过滤内部图与无落点项)
  def load_maps
    # 缓存: jump_points.json 运行期间不变, 首次加载后复用,
    # 避免每次 Ctrl+J 都重复读文件 + 过滤 + 排序
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
      next if x < 0 || y < 0            # 无落点(空/内部图)
      name = m['name'].to_s
      next if name =~ JUMP_MAP_FILTER               # 名字黑名单
      next if name =~ JUMP_MAP_NAME_PATTERN         # 纯代号测试图 (T1/C1/S1...)
      next if ancestor_blacklisted?(id.to_i)        # 祖先链内部图
      @maps << { id: id.to_i, x: x, y: y, dir: m['dir'].to_i, name: name }
    end
    @maps.sort_by! { |mm| mm[:id] }
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
      spr.x = MARGIN
      spr.y = TITLE_MARGIN + TITLE_TOP_MARGIN + ITEM_SPACING * i
      spr.opacity = 0
      spr.bitmap.draw_text(0, 0, spr.bitmap.width, spr.bitmap.height, tr(mm[:name]))
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
  "jump_points_path = #{JUMP_POINTS_PATH}",
  "filter = #{JUMP_MAP_FILTER.inspect}",
  "name_pattern = #{JUMP_MAP_NAME_PATTERN.inspect}",
  "parent_filter = #{JUMP_MAP_PARENT_FILTER.inspect}",
  "per_page = #{JUMP_MAP_PER_PAGE}",
  "paging = book-style, LEFT/RIGHT flip page, UP/DOWN move cursor",
  "fade = background stays black (no lower menu flash)",
  "method = FastTravel transfer chain (player_transferring + Graphics.freeze + transition_processing 'black')",
  "free_mode = jump_map_free.rb (JUMP_MAP_FREEZE_AUTORUN)"
])
