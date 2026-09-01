# ============================================================
#  unlock_or_complete.rb — 地图浏览器: Unlock/Complete
#
#  把原三个功能动作(unlock_all_doors / complete_all_dialogues /
#  complete_all_story)合并为统一的 "Unlock/Complete" 子界面:
#    * 像 Jump Map 一样分页, 每页一张地图(用户要求"每一页是一个地图")
#    * 每页列出该地图涉及的: 开关(激活类/关闭类)、对话事件、故事事件
#    * 打开时自动定位到"当前所在地图"那一页
#    * 按确认键对当前所在地图一并执行 unlock+complete
#      (unlock_all_doors → complete_all_dialogues → complete_all_story)
#
#  纯 preload 实现, 不修改游戏原始文件。
#  依赖(运行时已加载):
#    jump_map.rb    —— JUMP_MAP_FILTER / JUMP_MAP_NAME_PATTERN / JUMP_MAP_PARENT_FILTER
#    dev_settings.rb—— Window_DevSettings (动作方法 + $dev_settings_instance)
# ============================================================

require 'json'

# 一页显示一张地图
UNLOCK_COMPLETE_PER_PAGE = 1

# 静态扫描缓存: map_id → { activate:, close_only:, dialogues:, story: }
UNLOCK_COMPLETE_CACHE = {}

# ------------------------------------------------------------
#  地图静态扫描: 分析一张地图(rxdata)涉及的开关/对话/故事。
#  不依赖运行时事件实例(运行时 $game_map.events 只是"当前激活页"的快照,
#  未激活事件取不到), 直接加载地图数据逐页分析。
# ------------------------------------------------------------
module UnlockCompleteScanner
  module_function

  # 开关分类与 Window_DevSettings#current_map_switch_info 同口径:
  #   激活类(activate)  : 作为"非空页"(有实际命令)的页条件, 或出现在条件分支
  #                       (code 111)判断里 → 置 true 激活功能页(解锁/推进)
  #   关闭类(close_only): 只作为"空页"(命令全空)的页条件 → 置 true 使事件变哑
  #                       (如出口的"已用过/关闭"标记), 完成/解锁时绝不能置 true
  # 对话(dialogues): 事件任意页含 Show Text(101)
  # 故事(story)    : 不含对话但含非空命令的事件(门/传送/机制/剧情)
  def scan(map_id)
    return UNLOCK_COMPLETE_CACHE[map_id] if UNLOCK_COMPLETE_CACHE.key?(map_id)
    map = load_data(format('Data/Map%03d.rxdata', map_id))
    events = map.events || {}
    activate = {}
    close_only = {}
    dialogues = []
    story = []
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
      dialogues << ev.name if has_dlg
      story << ev.name if !has_dlg && has_cmd
    end
    UNLOCK_COMPLETE_CACHE[map_id] = {
      activate:   activate.keys.sort,
      close_only: close_only.keys.sort,
      dialogues:  dialogues.compact,
      story:      story.compact
    }
  end
end

# ------------------------------------------------------------
#  地图浏览器子界面: 每页一张地图, 列出开关/对话/故事。
#  打开定位当前所在地图页; 确认 = 对当前所在地图执行 unlock+complete。
# ------------------------------------------------------------
class Window_UnlockComplete
  MARGIN = 30
  TITLE_TOP_MARGIN = 32
  TITLE_MARGIN = 100
  ACTIVE_MARGIN = MARGIN * 2 + 20

  # 关闭回调(由外层设置, 用于恢复开发者设置)
  attr_accessor :on_close

  def initialize
    @viewport = Viewport.new(0, 0, 640, 480)
    @bg = Sprite.new(@viewport)
    @bg.bitmap = Bitmap.new(640, 480)
    # 不透明黑底, 完全遮住下层(开发者设置)的文字
    @bg.bitmap.fill_rect(0, 0, 640, 480, Color.new(0, 0, 0, 255))
    @title = Sprite.new(@viewport)
    @title.bitmap = Bitmap.new(420, TITLE_MARGIN)
    @title.bitmap.font.size = 40
    @title.y = TITLE_TOP_MARGIN
    @title.x = MARGIN
    # 底部提示(操作说明/执行结果)
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
    @index = 0     # 全局选中索引(在 @maps 中的位置)
    @page = 0      # 当前页码(0-based)
    @visible = false
    @maps = []
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

  # 背景始终全黑, 淡入淡出只作用于文字层(本界面无需淡出, 保持简单)
  def opacity=(val)
    @title.opacity = val
  end

  # 打开地图浏览器: 定位到当前所在地图那一页
  def open
    load_maps
    return if @maps.empty?
    cur = ($game_map && $game_map.map_id) || -1
    idx = @maps.index { |m| m[:id] == cur }
    idx = 0 unless idx
    @index = idx
    @page = idx / UNLOCK_COMPLETE_PER_PAGE
    @bg.opacity = 255
    @title.opacity = 255
    @page_sprite.opacity = 255
    @title.bitmap.clear
    @title.bitmap.draw_text(0, 0, @title.bitmap.width, @title.bitmap.height, tr('Unlock / Complete'))
    @hint_sprite.bitmap.clear
    @hint_sprite.bitmap.draw_text(0, 0, @hint_sprite.bitmap.width, @hint_sprite.bitmap.height,
                                  tr('ACTION: unlock/complete current map    CANCEL: back'))
    self.visible = true
    refresh_list
  end

  # 帧更新: 上下键本页内选择(一页一图则无效) / 左右键翻页 / 确认执行 / 取消关闭
  def update
    return if !@visible || @maps.empty?

    # 光标动画(视觉与 Window_Settings 一致)
    @data_sprites.each_with_index do |spr, i|
      if i == @index - @page * UNLOCK_COMPLETE_PER_PAGE
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

    # 左右键: 整页(一张地图)翻页
    if Input.trigger?(Input::LEFT)
      if @page > 0
        @page -= 1
        @index = @page * UNLOCK_COMPLETE_PER_PAGE
        refresh_list
        $game_system.se_play($data_system.cursor_se)
      end
    end
    if Input.trigger?(Input::RIGHT)
      if @page < page_count - 1
        @page += 1
        @index = @page * UNLOCK_COMPLETE_PER_PAGE
        refresh_list
        $game_system.se_play($data_system.cursor_se)
      end
    end

    # 确认: 对"当前所在地图"执行 unlock+complete 合并动作
    if Input.trigger?(Input::ACTION)
      $game_system.se_play($data_system.decision_se)
      ds = $dev_settings_instance
      if ds && $game_map && ds.respond_to?(:unlock_all_doors)
        n1 = ds.unlock_all_doors
        n2 = ds.complete_all_dialogues
        n3 = ds.complete_all_story
        @hint_sprite.bitmap.clear
        @hint_sprite.bitmap.draw_text(0, 0, @hint_sprite.bitmap.width, @hint_sprite.bitmap.height,
                                      "Done: #{n1} sw, #{n2} dlg, #{n3} story (map #{cur_map_name})")
      end
      return
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

  private

  def cur_map_name
    id = $game_map && $game_map.map_id
    info = mapinfos[id]
    (info && info.name) ? info.name.to_s : (id || '?')
  end

  def page_count
    return 1 if @maps.empty?
    (@maps.size.to_f / UNLOCK_COMPLETE_PER_PAGE).ceil
  end

  # 运行时惰性加载 MapInfos(游戏初始化后 load_data 可用)
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

  # 从 jump_points.json 加载可浏览地图(过滤内部图, 与 Jump Map 同一份列表)
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
      next if name =~ JUMP_MAP_FILTER
      next if name =~ JUMP_MAP_NAME_PATTERN
      next if ancestor_blacklisted?(id.to_i)
      @maps << { id: id.to_i, x: x, y: y, dir: m['dir'].to_i, name: name }
    end
    @maps.sort_by! { |mm| mm[:id] }
  end

  # 重建当前页内容(翻页/打开时调用): 渲染地图名 + 开关/对话/故事清单
  def refresh_list
    @data_sprites.each { |spr| spr.dispose }
    @data_sprites = []
    return if @maps.empty?
    mm = @maps[@page]
    info = UnlockCompleteScanner.scan(mm[:id])
    cur = $game_map && $game_map.map_id == mm[:id]
    a = info[:activate]
    c = info[:close_only]

    rows = []
    rows << [:title, mm[:name]]
    rows << [:sub, "Map #{mm[:id]}#{cur ? '  [current]' : ''}"]
    rows << [:line, "Switches activate: #{a.empty? ? 'none' : a.join(',')}"]
    rows << [:line, "Switches close:   #{c.empty? ? 'none' : c.join(',')}"]
    rows << [:head, 'Dialogues:']
    dl = info[:dialogues]
    if dl.empty?
      rows << [:line, '  (none)']
    else
      dl.first(5).each { |n| rows << [:line, "  - #{n}"] }
      rows << [:line, "  ...+#{dl.size - 5} more"] if dl.size > 5
    end
    rows << [:head, 'Story:']
    st = info[:story]
    if st.empty?
      rows << [:line, '  (none)']
    else
      st.first(3).each { |n| rows << [:line, "  - #{n}"] }
      rows << [:line, "  ...+#{st.size - 3} more"] if st.size > 3
    end

    y = 96
    rows.each do |kind, text|
      spr = Sprite.new(@viewport)
      case kind
      when :title
        spr.bitmap = Bitmap.new(500, 40)
        spr.bitmap.font.size = 28
        spr.y = y - 28
        y += 44
      when :head
        spr.bitmap = Bitmap.new(500, 22)
        spr.bitmap.font.size = 16
        spr.y = y
        y += 26
      else
        spr.bitmap = Bitmap.new(500, 22)
        spr.y = y
        y += 22
      end
      spr.x = MARGIN
      spr.bitmap.draw_text(0, 0, spr.bitmap.width, spr.bitmap.height, tr(text))
      spr.opacity = 255
      @data_sprites << spr
    end

    # 页码
    @page_sprite.bitmap.clear
    @page_sprite.bitmap.draw_text(0, 0, @page_sprite.bitmap.width, @page_sprite.bitmap.height,
                                  "#{@page + 1} / #{page_count}")
  end
end
