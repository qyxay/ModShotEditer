# ============================================================
#  jump_map.rb — "Jump Map" 跳地图 mod + 快捷键
#
#  1) 在开发者设置(Window_DevSettings)中新增 "Jump Map" 栏:
#     进入后列出可跳地图(过滤内部/debug/测试图), 选中即模仿原版
#     FastTravel 的传送链做黑屏转场跳转。
#  2) 全局快捷键(Scene_Map):
#       Ctrl+D → 打开开发者设置(需 config "is_developer": true)
#       Ctrl+J → 打开跳地图
#     基于 mkxp-z 扩展 Input.pressex?/triggerex?(SDL scancode 符号)。
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

# --- 补丁 3: 自由浏览模式下的玩家触发 (here/there/touch) ---
# 玩家按确认键触发同格"事件开始"(trigger 0) 或移动触发"接触"(trigger 1/2)
# 的地图事件(对话/互动)时, 一律放行 —— 这是"跳转后能正常跟 NPC/物品对话互动"
# 的关键。玩家主动触发是安全行为: 事件执行完(对话/开关/变量)后玩家恢复控制,
# 不会锁死; 真正会导致"跳转后卡住"的是剧情 AUTORUN(trigger 3, 由补丁 1
# JumpMapFreezePatch 拦截)与公共事件 AUTORUN(trigger 1, 由补丁 2 拦截),
# 以及早期落点撞事件格的问题(已由落点修正解决)。
#
# 说明: 早期版本曾在此拦截所有非出口事件, 结果 Jump Map 跳转后任何对话/
# 互动都触发不了。经分析 Start/Livingroom 等地图的对话事件(trigger 0/1)
# 多为"对话 + 开关/变量"的普通互动, 放行安全。出口传送事件(trigger 1/2)
# 同样走这里的 super 正常触发, 无需再单独白名单。
module JumpMapPlayerTriggerPatch
  def check_event_trigger_here(triggers)
    super
  end

  def check_event_trigger_there(triggers)
    super
  end

  def check_event_trigger_touch(x, y)
    super
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

# ============================================================
#  快捷键: Ctrl+D 打开开发者设置(需 is_developer), Ctrl+J 打开跳地图
# ------------------------------------------------------------
#  实现要点:
#   * 监听点: Scene_Map#update 开头(prepend)。仅在地图场景、非对话/转场/
#     事件运行中响应, 避免打断剧情。
#   * 按键 API: mkxp-z 扩展 Input.pressex?/Input.triggerex? 接受 SDL scancode
#     符号(:LCTRL/:RCTRL/:D/:J)。若运行时无该扩展则回退 Input.press?(Input::CTRL),
#     Ctrl+D/J 将不可用(见状态文件记录的 API 探测)。
#   * 打开方式: 把 Window_DevSettings 实例挂到 @window_settings 的 dev_settings
#     槽位, 由 WindowSettingsDevPatch#update 统一接管输入并 return; 同时把设置
#     窗口置可见, 复用 Scene_Map 原逻辑(屏蔽菜单打开 + 玩家停止移动)。
#     dev_settings 全屏不透明黑底盖住下层, 视觉上就是直接进入开发者设置。
#   * 关闭: dev_settings 按 CANCEL → on_closed 回调恢复设置窗口(visible=false
#     并清槽位), 玩家回到游戏, 不残留设置界面。
# ============================================================
module ShortcutKeysPatch
  def update
    begin
      shortcut_handle
    rescue StandardError
      # 快捷键异常不影响主流程
    end
    super
  end

  private

  def shortcut_handle
    # 开发者设置已打开(无论谁打开的): 输入由 WindowSettingsDevPatch 接管, 不重复响应
    ds = $dev_settings_instance
    return if ds && ds.visible
    return unless shortcut_available?

    ctrl = ctrl_pressed?
    if ctrl && key_triggered?(:D) && $dev_settings_enabled
      open_dev_settings_shortcut
    elsif ctrl && key_triggered?(:J)
      open_jump_map_shortcut
    end
  end

  # 快捷键可响应条件: 在地图上、非对话/转场/事件运行中
  def shortcut_available?
    return false unless $game_map && $game_player
    return false if $game_temp.message_window_showing
    return false if $game_temp.transition_processing
    return false if $game_temp.player_transferring
    if @message_window && @message_window.visible
      return false
    end
    if @ed_message && @ed_message.visible
      return false
    end
    mi = $game_system ? $game_system.map_interpreter : nil
    return false if mi && mi.running?
    true
  end

  # Ctrl 按住检测: 优先 mkxp-z 扩展, 回退标准 API
  def ctrl_pressed?
    if Input.respond_to?(:pressex?)
      begin
        return true if Input.pressex?(:LCTRL) || Input.pressex?(:RCTRL)
      rescue StandardError
      end
    end
    begin
      Input.press?(Input::CTRL)
    rescue StandardError
      false
    end
  end

  # 字母键按下检测(SDL scancode 符号, 如 :D / :J)
  def key_triggered?(sym)
    return false unless Input.respond_to?(:triggerex?)
    begin
      Input.triggerex?(sym)
    rescue StandardError
      false
    end
  end

  def open_dev_settings_shortcut
    ds = $dev_settings_instance ||= Window_DevSettings.new
    ds.parent_settings = @window_settings
    # 关闭时恢复被借用的设置窗口(visible + 槽位), 避免残留设置界面
    ds.on_closed = proc {
      @window_settings.visible = false
      @window_settings.instance_variable_set(:@dev_settings, nil)
    }
    # 设置窗口未初始化时先 open 一次(初始化 sprite/数据); 已打开则保持原状态
    @window_settings.open unless @window_settings.visible
    # 挂到设置窗口的 dev_settings 槽位: WindowSettingsDevPatch#update 检测到
    # ds.visible 后接管输入并 return, 设置窗口自身不响应输入
    @window_settings.instance_variable_set(:@dev_settings, ds)
    # 设置窗口置可见: 复用 Scene_Map 的"菜单屏蔽 + 玩家停止"逻辑(dev_settings 全屏盖住)
    @window_settings.visible = true
    ds.open
  end

  def open_jump_map_shortcut
    open_dev_settings_shortcut
    $dev_settings_instance.open_jump_map
  end
end

# --- 等待 Scene_Map 类定义完成后 prepend 快捷键补丁 ---
_trace_scene = TracePoint.trace(:end) do |tp|
  begin
    if tp.self.is_a?(Class) && tp.self.name == 'Scene_Map' &&
       tp.self.method_defined?(:update)
      tp.self.prepend(ShortcutKeysPatch)
      _trace_scene.disable
    end
  rescue StandardError
    # 忽略异常, 继续监听
  end
end

# --- 写状态文件 ---
status_path = File.join(__dir__, '..', 'logs', 'jump_map_status.txt')
begin
  _log_dir = File.dirname(status_path)
  Dir.mkdir(_log_dir) unless File.directory?(_log_dir)
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
    f.puts "shortcut_ctrl_d = #{$dev_settings_enabled} (open dev settings)"
    f.puts "shortcut_ctrl_j = true (open jump map)"
    f.puts "input_api = pressex?#{Input.respond_to?(:pressex?)}, triggerex?#{Input.respond_to?(:triggerex?)}"
  end
rescue StandardError
end
