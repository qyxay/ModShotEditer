# ============================================================
#  jump_map.rb — "Jump Map" 跳地图 mod
#
#  在开发者设置(Window_DevSettings)中新增 "Jump Map" 栏:
#  进入后列出可跳地图(过滤内部/debug/测试图), 选中即模仿原版
#  FastTravel 的传送链做黑屏转场跳转。
#
#  纯 preload 实现, 不修改游戏原始文件。
#  落点数据: mods/mod/jump_points.json (预扫描生成, 见附录说明)
#
#  依赖:
#    mods/mod/Scripts/dev_settings.rb 提供 Window_DevSettings
#    config.json: "is_developer": true
# ============================================================

require 'json'

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

# --- 跳转后"自由浏览模式" ---
# 跳到某地图后进入自由浏览模式, 玩家在该模式下完全自由:
#   1) 冻结所有地图的 autorun(trigger 3) 事件 —— 防止剧情 AUTORUN 锁玩家
#   2) 拦截 autorun 公共事件(trigger 1) —— 该路径绕过 Game_Event 冻结
#   3) 拦截玩家触发 here/there/touch —— 防止按确认键/移动触发事件对话
# 自由浏览模式持续到游戏重启; 重启后恢复正常剧情。
JUMP_MAP_FREEZE_AUTORUN = true

# 当前是否处于自由浏览模式 + 被冻结的地图 ID
$jump_map_free_mode = false
$jump_map_frozen_map_id = -1

# --- 冻结补丁: 阻止 autorun 自动触发 ---
# Game_Event#check_event_trigger_auto 在每次 refresh/update 时都会被调用,
# trigger==3(autorun) 会无条件 start, 进入 map_interpreter 运行。
# 自由浏览模式下跳过 start, 让玩家在跳转目标地图上自由活动。
#
# 修复: 不再限定"只冻结目标地图"。跳转后玩家可能通过门/传送走到其他地图
# (如 Livingroom 落点正上方 1 格就是 north door, 触发后传到地图 2),
# 这些地图同样有剧情 AUTORUN (地图 2 的 intro / Map Events 都含对话),
# 会立即锁住玩家并禁用菜单。因此自由浏览模式下冻结所有地图的 AUTORUN。
module JumpMapFreezePatch
  def check_event_trigger_auto
    if $jump_map_free_mode &&
       @trigger == 3
      return  # 不触发 autorun
    end
    super
  end
end

# --- 补丁 2: 自由浏览模式下拦截公共事件 autorun ---
# Interpreter#setup_starting_event 每帧会在 map_interpreter 空闲时
# 启动条件开关为 ON 的 trigger==1(autorun) 公共事件, 该路径完全绕过上面的
# Game_Event 冻结补丁, 同样会锁住玩家。这里在自由浏览模式下临时把 autorun
# 公共事件的 trigger 改为非 1, 让原循环跳过; 保留 common_event_id 明确
# 调用的公共事件(如 quit_all_time 的保存退出), 结束后立即恢复。
#
# 例外(白名单): 公共事件 #9 "Exit Transition" 是 OneShot 地图出口传送的
# 执行者 —— 所有地图的 south/north/east/west exit 平行事件检测到玩家后,
# 设置变量(目标地图/坐标)并置 SW11=true, 再由它执行 201 传送。如果把它也
# 冻结, 自由浏览模式下玩家走到任何出口都无法传送离开(瞭望甲板即如此)。
# 它只在 SW11=true(出口触发)时启动, 平时不占用解释器, 放行是安全的。
JUMP_MAP_KEEP_COMMON_EVENTS = [9]  # 放行: Exit Transition(出口传送)

module JumpMapCommonEventPatch
  def setup_starting_event
    if $jump_map_free_mode
      saved = []
      $data_common_events.each_with_index do |ce, i|
        if ce && ce.trigger == 1 && !JUMP_MAP_KEEP_COMMON_EVENTS.include?(i)
          saved << [i, ce]
          ce.trigger = 0  # 临时改为非 autorun, 原循环即跳过
        end
      end
      begin
        super
      ensure
        saved.each { |_i, ce| ce.trigger = 1 }
      end
    else
      super
    end
  end
end

# --- 补丁 3: 自由浏览模式下拦截玩家触发 (here/there/touch) ---
# 玩家按确认键触发同格"事件开始"(trigger 0) 或移动触发"接触"(trigger 1/2)
# 的地图事件时, 若事件命令含对话会立刻锁住玩家(如 Start 落点同格的床事件
# "Niko just woke up here.")。该路径也绕过 AUTORUN 冻结, 会重新造成
# "跳转后卡住"。自由浏览模式下直接拦截, 玩家在目标地图上完全自由。
#
# 例外: 出口/门类事件(当前激活页含 201 传送 或 check_exit/transfer 脚本)
# 必须放行 —— 它们是玩家离开当前地图的唯一途径(如 start 的 west/south door
# 是 trigger=1 接触事件)。只放行含传送命令的事件, 对话类事件仍被拦截。
module JumpMapPlayerTriggerPatch
  def check_event_trigger_here(triggers)
    if $jump_map_free_mode
      return false unless exit_event_at?($game_player.x, $game_player.y)
    end
    super
  end

  def check_event_trigger_there(triggers)
    if $jump_map_free_mode
      d = $game_player.direction
      x = $game_player.x + (d == 6 ? 1 : (d == 4 ? -1 : 0))
      y = $game_player.y + (d == 2 ? 1 : (d == 8 ? -1 : 0))
      return false unless exit_event_at?(x, y)
    end
    super
  end

  def check_event_trigger_touch(x, y)
    if $jump_map_free_mode
      return false unless exit_event_at?(x, y)
    end
    super
  end

  # 该格是否"出口事件": 当前激活页含 201 传送或 check_exit/transfer 脚本
  def exit_event_at?(x, y)
    return false unless $game_map && $game_map.events
    $game_map.events.each_value do |e|
      next unless e.x == x && e.y == y
      list = e.list
      next unless list
      return true if list.any? { |c| c.code == 201 }
      return true if list.any? do |c|
        [355, 655].include?(c.code) && c.parameters[0].to_s =~ /check_exit|transfer|teleport|unlock_map/i
      end
    end
    false
  end
end

# --- 等待 Game_Event / Interpreter / Game_Player 类定义完成后 prepend ---
_trace = TracePoint.trace(:end) do |tp|
  begin
    if tp.self.is_a?(Class) && tp.self.name == 'Game_Event' &&
       tp.self.method_defined?(:check_event_trigger_auto)
      tp.self.prepend(JumpMapFreezePatch)
      _trace.disable
    end
  rescue
    # 忽略异常, 继续监听
  end
end

_trace_ce = TracePoint.trace(:end) do |tp|
  begin
    if tp.self.is_a?(Class) && tp.self.name == 'Interpreter' &&
       tp.self.method_defined?(:setup_starting_event)
      tp.self.prepend(JumpMapCommonEventPatch)
      _trace_ce.disable
    end
  rescue
    # 忽略异常, 继续监听
  end
end

_trace_pl = TracePoint.trace(:end) do |tp|
  begin
    if tp.self.is_a?(Class) && tp.self.name == 'Game_Player' &&
       tp.self.method_defined?(:check_event_trigger_here)
      tp.self.prepend(JumpMapPlayerTriggerPatch)
      _trace_pl.disable
    end
  rescue
    # 忽略异常, 继续监听
  end
end

# --- 补丁 4: 自由浏览模式下进入地图后按 config 自动应用功能开关 ---
# 跳转(传送)是异步的: transfer 标志先设, 地图在下一帧才 Game_Map#setup。
# 所以在 setup 完成后, 若处于自由浏览模式, 自动调用 dev_settings 的
# auto_apply_current_map —— config 里 unlock_all_doors / complete_all_dialogues /
# complete_all_story 为 true 时对当前地图生效。这样跳转瞭望甲板等地图后,
# SW22 等传送条件开关自动为 true, 出口传送立即可用, 无需再手动切一次。
module JumpMapAutoApplyPatch
  def setup(map_id)
    super
    if $jump_map_free_mode && defined?(Window_DevSettings) &&
       Window_DevSettings.respond_to?(:auto_apply_current_map)
      Window_DevSettings.auto_apply_current_map
    end
  rescue StandardError
    # 静默: 自动应用失败不影响地图加载
  end
end

_trace_apply = TracePoint.trace(:end) do |tp|
  begin
    if tp.self.is_a?(Class) && tp.self.name == 'Game_Map' &&
       tp.self.method_defined?(:setup)
      tp.self.prepend(JumpMapAutoApplyPatch)
      _trace_apply.disable
    end
  rescue
    # 忽略异常, 继续监听
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
    @index = 0
    @page = 0
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
      # 背景保持全黑, 只淡出文字, 保证 Graphics.freeze 冻结的是纯黑画面
      @title.opacity -= 20
      @data_sprites.each { |spr| spr.opacity -= 10 }
      @page_sprite.opacity -= 10
      if @title.opacity <= 0
        @fade_out = false
        self.visible = false
        @data_sprites.each { |spr| spr.dispose }
        @data_sprites = []
        if @transfer_player
          # 开启自由浏览模式: 冻结目标地图的 autorun, 避免剧情事件锁住玩家
          if JUMP_MAP_FREEZE_AUTORUN
            $jump_map_free_mode = true
            $jump_map_frozen_map_id = @transfer_player[:id]
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

  # 从 jump_points.json 加载可跳地图(过滤内部图与无落点项)
  def load_maps
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
status_path = File.join(__dir__, '..', 'jump_map_status.txt')
begin
  File.open(status_path, 'w') do |f|
    f.puts "jump_map loaded at = #{Time.now}"
    f.puts "jump_points_path = #{JUMP_POINTS_PATH}"
    f.puts "filter = #{JUMP_MAP_FILTER.inspect}"
    f.puts "name_pattern = #{JUMP_MAP_NAME_PATTERN.inspect}"
    f.puts "parent_filter = #{JUMP_MAP_PARENT_FILTER.inspect}"
    f.puts "per_page = #{JUMP_MAP_PER_PAGE}"
    f.puts "paging = book-style, LEFT/RIGHT flip page, UP/DOWN move cursor"
    f.puts "fade = background stays black (no lower menu flash)"
    f.puts "method = FastTravel transfer chain (player_transferring + Graphics.freeze + transition_processing 'black')"
  end
rescue StandardError
end
