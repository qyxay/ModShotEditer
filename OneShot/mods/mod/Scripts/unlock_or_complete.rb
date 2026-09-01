# ============================================================
#  unlock_or_complete.rb — 地图浏览器: Unlock/Complete(可编辑)
#
#  把原三个功能动作(unlock_all_doors / complete_all_dialogues /
#  complete_all_story)合并为统一的 "Unlock/Complete" 子界面, 按地图分页浏览
#  并允许直接修改运行时状态:
#    * 页 0          : Niko Items(全局物品, 勾选拥有/没有)
#    * 页 1..N(地图) : 每页一张地图, 列出并编辑该地图的
#                       - Doors   门/出口(可通行 / 锁定)
#                       - Events  事件(含对话)完成状态(已完成 / 未)
#    * 打开时自动定位到"当前所在地图"那一页(用户要求)
#    * 上下键选择条目, 确认键切换状态, 左右键整页(地图)翻页, 取消关闭
#
#  纯 preload 实现, 不修改游戏原始文件。
#  依赖(运行时已加载):
#    jump_map.rb     —— JUMP_MAP_FILTER / JUMP_MAP_NAME_PATTERN / JUMP_MAP_PARENT_FILTER
#    dev_settings.rb —— Window_DevSettings($dev_settings_instance)
# ============================================================

require 'json'

# 一页显示一张地图(页 0 是物品页)
UNLOCK_COMPLETE_PER_PAGE = 1

# 静态扫描缓存: map_id → { activate:, close_only:, dialogues:, story:, doors:, events: }
UNLOCK_COMPLETE_CACHE = {}

# 一屏最多显示的行数(条目滚动窗口)
UNLOCK_COMPLETE_VISIBLE_ROWS = 15

# ------------------------------------------------------------
#  地图静态扫描: 分析一张地图(rxdata)涉及的开关/对话/故事/门/事件。
#  不依赖运行时事件实例(运行时 $game_map.events 只是"当前激活页"的快照),
#  直接加载地图数据逐页分析。
# ------------------------------------------------------------
module UnlockCompleteScanner
  module_function

  # 开关分类与 Window_DevSettings#current_map_switch_info 同口径:
  #   激活类(activate)  : 作为"非空页"(有实际命令)的页条件, 或出现在条件分支
  #                       (code 111)判断里 → 置 true 激活功能页(解锁/推进)
  #   关闭类(close_only): 只作为"空页"(命令全空)的页条件 → 置 true 使事件变哑
  # 对话(dialogues): 事件任意页含 Show Text(101)
  # 故事(story)    : 不含对话但含非空命令的事件
  # 门(doors)      : 含 201 传送(或 transfer/check_exit 脚本)的事件
  # 事件(events)   : 其余含非空命令的事件(含对话)
  def scan(map_id)
    return UNLOCK_COMPLETE_CACHE[map_id] if UNLOCK_COMPLETE_CACHE.key?(map_id)
    map = load_data(format('Data/Map%03d.rxdata', map_id))
    events = map.events || {}
    activate = {}
    close_only = {}
    dialogues = []
    story = []
    doors = []
    evlist = []
    events.each_value do |ev|
      pages = ev.pages || []
      pages.each do |page|
        c = page.condition
        list = page.list
        is_empty = list.nil? || list.empty? || list.all? { |cmd| cmd && cmd.code == 0 }
        sws = []
        sws << c.switch1_id if c && c.switch1_valid
        sws << c.switch2_id if c && c.switch2_valid
        sws.each do |sid|
          next unless sid && sid > 0
          if is_empty
            close_only[sid] = true
          else
            activate[sid] = true
          end
        end
      end
      # 条件分支(111, parameters[0]==0)里的开关判断 → 激活类
      pages.each do |page|
        (page.list || []).each do |cmd|
          next unless cmd && cmd.code == 111
          p = cmd.parameters
          activate[p[1]] = true if p && p[0] == 0 && p[1]
        end
      end
      has_dlg = pages.any? { |pg| (pg.list || []).any? { |c| c && c.code == 101 } }
      has_cmd = pages.any? do |pg|
        l = pg.list
        l && l.any? { |c| c && c.code != 0 && c.code != 101 && c.code != 401 }
      end
      has_201 = pages.any? { |pg| (pg.list || []).any? { |c| c && c.code == 201 } }
      has_script = pages.any? do |pg|
        (pg.list || []).any? { |c| c && [355, 655].include?(c.code) && c.parameters[0].to_s =~ /check_exit|transfer|teleport|unlock_map/i }
      end
      dialogues << ev.name if has_dlg
      story << ev.name if !has_dlg && has_cmd
      if has_201 || has_script
        doors << { id: ev.id, name: ev.name }
      elsif has_cmd || has_dlg
        evlist << { id: ev.id, name: ev.name, has_dlg: has_dlg, completable: has_self_switch_page?(ev) }
      end
    end
    UNLOCK_COMPLETE_CACHE[map_id] = {
      activate:   activate.keys.sort,
      close_only: close_only.keys.sort,
      dialogues:  dialogues.compact,
      story:      story.compact,
      doors:      doors.compact,
      events:     evlist.compact
    }
  end

  # 统一取事件页: 兼容 RPG::Event(静态) 与 Game_Event(运行时, pages 在 @event 里)
  def event_pages(ev)
    evt = ev.instance_variable_get(:@event) || ev
    evt.respond_to?(:pages) ? evt.pages : nil
  end

  # 事件是否含"自开关条件页"(可被 complete 跳到完成态)
  def has_self_switch_page?(ev)
    pages = event_pages(ev)
    pages && pages.any? { |pg| c = pg.condition; c && c.self_switch_valid }
  end

  # 事件指定自开关的条件页
  def self_switch_page(ev, ch)
    pages = event_pages(ev)
    return nil unless pages
    pages.find { |pg| c = pg.condition; c && c.self_switch_valid && c.self_switch_ch == ch }
  end

  # 该"自开关条件页"是否安全完成(完成不触发卡住)
  def safe_self_switch_page?(page)
    return false unless page
    return false if page.trigger == 3
    list = page.list
    return false unless list
    return false if list.any? { |cmd| cmd && (cmd.code == 209 || cmd.code == 201) }
    true
  end

  # 门的可通行/锁定条件开关(静态)
  # 返回 [{sw:, ss:}, {sw:, ss:}] = [通行页条件, 锁定页条件]  (sw=开关, ss=自开关)
  def door_switches(ev)
    pass = { sw: {}, ss: {} }
    lock = { sw: {}, ss: {} }
    pages = event_pages(ev)
    return [pass, lock] unless pages
    pages.each do |pg|
      list = pg.list
      has_tr = list && list.any? { |c| c && c.code == 201 }
      target = has_tr ? pass : lock
      c = pg.condition
      next unless c
      target[:sw][c.switch1_id] = true if c.switch1_valid && c.switch1_id && c.switch1_id > 0
      target[:sw][c.switch2_id] = true if c.switch2_valid && c.switch2_id && c.switch2_id > 0
      target[:ss][c.self_switch_ch] = true if c.self_switch_valid
    end
    [pass, lock]
  end
end

# ------------------------------------------------------------
#  地图浏览器子界面(可编辑): 页 0 物品, 页 1..N 地图。
#  上下键选择, 确认键切换状态, 左右键翻页, 取消关闭。
# ------------------------------------------------------------
class Window_UnlockComplete
  MARGIN = 30
  TITLE_TOP_MARGIN = 24
  TITLE_MARGIN = 56
  ITEM_SPACING = 24
  ACTIVE_MARGIN = MARGIN * 2 + 20

  # 关闭回调(由外层设置, 用于恢复开发者设置)
  attr_accessor :on_close

  def initialize
    @viewport = Viewport.new(0, 0, 640, 480)
    @bg = Sprite.new(@viewport)
    @bg.bitmap = Bitmap.new(640, 480)
    # 不透明黑底, 完全遮住下层(开发者设置)的文字
    @bg.bitmap.fill_rect(0, 0, 640, 480, Color.new(0, 0, 0, 255))
    # 页标题(地图名 / Niko Items), 与内容区分离, 不重叠
    @title = Sprite.new(@viewport)
    @title.bitmap = Bitmap.new(500, 40)
    @title.bitmap.font.size = 28
    @title.y = TITLE_TOP_MARGIN
    @title.x = MARGIN
    # 底部提示(操作说明)
    @hint_sprite = Sprite.new(@viewport)
    @hint_sprite.bitmap = Bitmap.new(420, 24)
    @hint_sprite.x = MARGIN
    @hint_sprite.y = 452
    # 底部页码
    @page_sprite = Sprite.new(@viewport)
    @page_sprite.bitmap = Bitmap.new(120, 24)
    @page_sprite.x = 640 - 120 - 24
    @page_sprite.y = 452
    # 高于 Window_DevSettings 的 viewport z(9999), 保证盖住下层
    @viewport.z = 10000
    @data_sprites = []
    @pages = []
    @page = 0      # 当前页索引(@pages)
    @top = 0       # 当前页内滚动窗口顶部行索引
    @sel = 0       # 当前页内选中行索引(仅指向可编辑行)
    @rows = []     # 当前页行: {type:, label:, state:, act:, id:}
    @visible = false
    @maps = []
    @items = []
    @mapinfos = nil
    @on_close = nil
  end

  def visible
    @visible
  end

  def visible=(val)
    @viewport.visible = val
    @visible = val
  end

  def opacity=(val)
    @title.opacity = val
  end

  # 打开: 构建页列表, 定位到当前所在地图页
  def open
    load_maps
    load_items
    build_pages
    return if @pages.empty?
    cur = ($game_map && $game_map.map_id) || -1
    idx = @pages.index { |p| p[:type] == :map && p[:id] == cur }
    idx = 0 unless idx
    @page = idx
    @bg.opacity = 255
    @title.opacity = 255
    @page_sprite.opacity = 255
    @hint_sprite.bitmap.clear
    @hint_sprite.bitmap.draw_text(0, 0, @hint_sprite.bitmap.width, @hint_sprite.bitmap.height,
                                  tr('ACTION: toggle    < >: map/items    CANCEL: back'))
    self.visible = true
    refresh_page
  end

  # 帧更新
  def update
    return if !@visible || @pages.empty?

    # 光标动画(视觉与 Window_Settings 一致)
    @data_sprites.each_with_index do |spr, i|
      active = (i + @top) == @sel
      if active
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

    # 上下键: 页内选择(仅可编辑行), 到达边缘滚动
    if Input.trigger?(Input::UP)
      prev = @sel
      loop do
        @sel -= 1
        break if @sel < 0 || @sel >= @rows.size || editable?(@rows[@sel])
      end
      if @sel < 0 || @sel >= @rows.size
        @sel = prev
      elsif @sel < @top
        @top = @sel
      end
      $game_system.se_play($data_system.cursor_se)
    end
    if Input.trigger?(Input::DOWN)
      prev = @sel
      loop do
        @sel += 1
        break if @sel >= @rows.size || editable?(@rows[@sel])
      end
      if @sel >= @rows.size
        @sel = prev
      elsif @sel >= @top + UNLOCK_COMPLETE_VISIBLE_ROWS
        @top = @sel - UNLOCK_COMPLETE_VISIBLE_ROWS + 1
      end
      $game_system.se_play($data_system.cursor_se)
    end

    # 确认键: 切换选中条目状态
    if Input.trigger?(Input::ACTION)
      row = @rows[@sel]
      if row && row[:act]
        $game_system.se_play($data_system.decision_se)
        send(row[:act], row[:id])
        refresh_page
      end
      return
    end

    # 左右键: 整页翻页(物品页 / 地图页)
    if Input.trigger?(Input::LEFT)
      if @page > 0
        @page -= 1
        $game_system.se_play($data_system.cursor_se)
        refresh_page
      end
    end
    if Input.trigger?(Input::RIGHT)
      if @page < @pages.size - 1
        @page += 1
        $game_system.se_play($data_system.cursor_se)
        refresh_page
      end
    end

    # 取消: 关闭, 返回开发者设置
    if Input.trigger?(Input::CANCEL)
      $game_system.se_play($data_system.cancel_se)
      self.visible = false
      @on_close.call if @on_close
    end
  end

  def dispose
    @data_sprites.each { |spr| spr.dispose }
    @page_sprite.dispose
    @hint_sprite.dispose
    @title.dispose
    @bg.dispose
    @viewport.dispose
  end

  # ---- 条目切换动作 ----

  # 切换门的可通行/锁定
  def toggle_door(ev_id)
    ev = find_event(ev_id)
    return unless ev
    pass, lock = UnlockCompleteScanner.door_switches(ev)
    if door_passable?(ev, pass)
      # 锁定: 通行条件全 false, 锁定条件全 true
      apply_door_switches(pass, false, ev_id)
      apply_door_switches(lock, true, ev_id)
    else
      # 解锁: 通行条件全 true, 锁定条件全 false
      apply_door_switches(pass, true, ev_id)
      apply_door_switches(lock, false, ev_id)
    end
    refresh_map_events
  end

  # 切换事件(含对话)完成状态
  def toggle_event(ev_id)
    ev = find_event(ev_id)
    return unless ev
    if event_done?(ev_id)
      %w[A B C D].each { |ch| $game_self_switches[[$game_map.map_id, ev_id, ch]] = false }
    else
      %w[A B C D].each do |ch|
        page = UnlockCompleteScanner.self_switch_page(ev, ch)
        next unless UnlockCompleteScanner.safe_self_switch_page?(page)
        $game_self_switches[[$game_map.map_id, ev_id, ch]] = true
      end
    end
    refresh_map_events
  end

  # 切换物品拥有状态
  def toggle_item(item_id)
    if $game_party.item_number(item_id) > 0
      $game_party.lose_item(item_id, 1)
    else
      $game_party.gain_item(item_id, 1)
    end
  end

  private

  def editable?(row)
    row && row[:act] && row[:id] != nil
  end

  def find_event(ev_id)
    return nil unless $game_map && $game_map.events
    $game_map.events[ev_id]
  end

  def apply_door_switches(spec, val, ev_id)
    spec[:sw].each_key { |sid| $game_switches[sid] = val }
    spec[:ss].each_key { |ch| $game_self_switches[[$game_map.map_id, ev_id, ch]] = val }
  end

  def door_passable?(ev, pass)
    return true if pass[:sw].empty? && pass[:ss].empty?
    pass[:sw].each_key { |sid| return false unless $game_switches[sid] }
    pass[:ss].each_key { |ch| return false unless $game_self_switches[[$game_map.map_id, ev.id, ch]] }
    true
  end

  def event_done?(ev_id)
    %w[A B C D].any? { |ch| $game_self_switches[[$game_map.map_id, ev_id, ch]] }
  end

  def refresh_map_events
    if $game_map && $game_map.events
      $game_map.events.each_value { |e| e.refresh }
    end
  end

  def cur_map_id
    p = @pages[@page]
    p && p[:type] == :map ? p[:id] : nil
  end

  def build_pages
    @pages = []
    @pages << { type: :items }
    @maps.each { |m| @pages << { type: :map, id: m[:id] } }
  end

  # 重建当前页行列表并渲染(翻页/打开/切换后调用)
  def refresh_page
    p = @pages[@page]
    @rows = []
    if p[:type] == :items
      build_item_rows
      @title.bitmap.clear
      @title.bitmap.draw_text(0, 0, @title.bitmap.width, @title.bitmap.height, tr('Niko Items'))
    else
      build_map_rows(p[:id])
      @title.bitmap.clear
      @title.bitmap.draw_text(0, 0, @title.bitmap.width, @title.bitmap.height,
                             tr(map_name(p[:id])) + "  [Map #{p[:id]}#{cur? ? ' · current' : ''}]")
    end
    # 选中默认第一条可编辑行; 滚动窗口从页顶开始(选中行超一屏时才下移)
    @sel = @rows.index { |r| editable?(r) } || 0
    @top = @sel >= UNLOCK_COMPLETE_VISIBLE_ROWS ? @sel - UNLOCK_COMPLETE_VISIBLE_ROWS + 1 : 0
    render_rows
    # 页码
    @page_sprite.bitmap.clear
    @page_sprite.bitmap.draw_text(0, 0, @page_sprite.bitmap.width, @page_sprite.bitmap.height,
                                  "#{@page + 1} / #{@pages.size}")
  end

  def cur?
    p = @pages[@page]
    p && p[:type] == :map && p[:id] == ($game_map && $game_map.map_id)
  end

  def map_name(id)
    info = mapinfos[id]
    (info && info.name) ? info.name.to_s : id.to_s
  end

  def build_item_rows
    @rows << { type: :head, label: tr('— Items —') }
    @items.each do |it|
      have = $game_party.item_number(it[:id]) > 0
      @rows << { type: :item, label: it[:name], state: have ? tr('[have]') : tr('[none]'),
                 act: :toggle_item, id: it[:id] }
    end
  end

  def build_map_rows(map_id)
    info = UnlockCompleteScanner.scan(map_id)
    doors = info[:doors]
    evs = info[:events]
    unless doors.empty?
      @rows << { type: :head, label: tr('— Doors —') }
      doors.each do |d|
        @rows << { type: :item, label: d[:name].to_s.empty? ? "ev#{d[:id]}" : d[:name],
                   state: door_row_state(map_id, d[:id]), act: :toggle_door, id: d[:id] }
      end
    end
    unless evs.empty?
      @rows << { type: :head, label: tr('— Events —') }
      evs.each do |e|
        label = e[:name].to_s.empty? ? "ev#{e[:id]}" : e[:name]
        state = if e[:completable]
                  event_done?(e[:id]) ? tr('[done]') : tr('[undone]')
                else
                  tr('[–]')
                end
        @rows << { type: :item, label: label, state: state,
                   act: (e[:completable] ? :toggle_event : nil), id: e[:id] }
      end
    end
  end

  # 门的当前状态(静态开关推断): 通行页条件当前满足 → 可通行
  def door_row_state(map_id, ev_id)
    ev = event_static(map_id, ev_id)
    return tr('[?]') unless ev
    pass, = UnlockCompleteScanner.door_switches(ev)
    ok = pass[:sw].empty? && pass[:ss].empty?
    pass[:sw].each_key { |sid| ok &&= !!$game_switches[sid] }
    pass[:ss].each_key { |ch| ok &&= !!$game_self_switches[[map_id, ev_id, ch]] }
    ok ? tr('[unlocked]') : tr('[locked]')
  end

  # 从静态数据取事件(供状态推断, 不依赖运行时激活)
  def event_static(map_id, ev_id)
    map = load_data(format('Data/Map%03d.rxdata', map_id))
    evs = map.events || {}
    evs[ev_id]
  rescue StandardError
    nil
  end

  # 渲染当前页可见行
  def render_rows
    @data_sprites.each { |spr| spr.dispose }
    @data_sprites = []
    y = TITLE_MARGIN
    vis = @rows[@top, UNLOCK_COMPLETE_VISIBLE_ROWS] || []
    vis.each do |row|
      spr = Sprite.new(@viewport)
      spr.bitmap = Bitmap.new(500, ITEM_SPACING)
      spr.bitmap.font.size = 16 if row[:type] == :head
      spr.x = MARGIN
      spr.y = y
      spr.opacity = row[:type] == :head ? 160 : 128
      text = row[:type] == :head ? row[:label] : "#{row[:label]}"
      spr.bitmap.draw_text(0, 0, spr.bitmap.width, spr.bitmap.height, tr(text))
      if row[:type] == :item
        # 状态列靠右
        spr.bitmap.draw_text(360, 0, spr.bitmap.width, spr.bitmap.height, tr(row[:state].to_s))
      end
      @data_sprites << spr
      y += ITEM_SPACING
    end
  end

  def page_count
    return 1 if @pages.empty?
    @pages.size
  end

  # 运行时惰性加载 MapInfos
  def mapinfos
    @mapinfos ||= begin
      load_data('Data/MapInfos.rxdata')
    rescue StandardError
      {}
    end
  end

  # 祖先链是否含内部图标记(与 jump_map.rb 同口径)
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

  # 从 jump_points.json 加载可浏览地图(与 Jump Map 同一份列表)
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
      next if x < 0 || y < 0
      name = m['name'].to_s
      next if name =~ JUMP_MAP_FILTER
      next if name =~ JUMP_MAP_NAME_PATTERN
      next if ancestor_blacklisted?(id.to_i)
      @maps << { id: id.to_i, x: x, y: y, dir: m['dir'].to_i, name: name }
    end
    @maps.sort_by! { |mm| mm[:id] }
  end

  # 物品清单(Items.rxdata 有名字的物品)
  def load_items
    @items = []
    items = begin
      load_data('Data/Items.rxdata')
    rescue StandardError
      []
    end
    items.each_with_index do |it, i|
      next unless it && it.name.to_s != ''
      @items << { id: i, name: it.name }
    end
  end
end
