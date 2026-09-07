# ============================================================
#  event_editor.rb — 游戏内可视化事件编辑器
#
#  Ctrl+E 在游戏窗口内直接编辑当前地图的事件位置/方向:
#    * 事件标记层: 每事件画色块+ID(门/出口=蓝, 玩家接触=橙, 其他=灰),
#      跟随镜头滚动(复用 debug_map 的镜头换算, 格子级对齐)
#    * 鼠标选中: 左键点击选事件, 按住拖拽实时移动(逐格, 节流写入)
#    * 滚轮:     修改选中事件方向(2下/4左/6右/8上 循环)
#    * 右键:     取消选中;  Ctrl+E 退出编辑模式
#    * 键盘降级: 无 Mouse 模块时用方向键移动光标/事件, Enter 选中落定,
#      [ / ] 转方向
#    * 持久化: 改动写入 settings/event_edits.json(按 map+ev 覆盖),
#      每次进入地图时自动应用 —— 换图/读档/重启游戏后仍生效
#    * 与网页联动: live_state.json 每 0.5s 自动把新位置同步给
#      门连接编辑器(doors_graph.html), 无需额外操作
#
#  编辑模式拦截 Scene_Map#update 的 super: 暂停玩家/事件/镜头,
#  避免编辑时游戏在后台推进; 退出后恢复。
#
#  纯 preload 实现, 不修改游戏原始文件。
# ============================================================

require 'json'

module EventEditor
  TILE = 32
  SETTINGS_DIR = File.absolute_path(File.join(__dir__, '..', 'settings'))
  EDITS_PATH = File.join(SETTINGS_DIR, 'event_edits.json')
  DIRS = [2, 4, 6, 8]   # 下 左 右 上

  @active = false
  @overlay = nil
  @selected = nil       # 当前选中事件 (Game_Event)
  @dragging = false
  @hover_tile = nil     # 鼠标所在格子 [x, y]
  @cursor_tile = nil    # 键盘降级用光标格
  @same_tile_click = 0
  @modify_ts = 0.0      # 拖拽写入节流时间戳
  @edits = nil          # 持久编辑记录缓存
  @applied_for = nil    # 已应用编辑的 $game_map.object_id
  @mouse_ok = nil

  class << self
    def active?; @active; end
    def selected; @selected; end

    def overlay
      @overlay ||= Overlay.new
    end

    # Ctrl+E 切换编辑模式
    def toggle
      @active = !@active
      overlay.set_visible(@active)
      @selected = nil
      @dragging = false
      @hover_tile = nil
      overlay.redraw if @active
      @active
    end

    # --- 每帧调用(编辑模式激活时由 Patch 调用) ---
    def frame
      apply_for_current_map
      # 编辑模式拦截了 super, live_sync 的 tick 不会跑; 手动同步一次,
      # 保证网页端(门连接编辑器)仍能实时看到事件新位置 / 接收网页修改
      begin
        DoorGraphSync.tick
      rescue StandardError
      end
      overlay.update_frame
    end

    # --- 非编辑模式时也每帧调用: 进图应用持久编辑 ---
    def idle
      apply_for_current_map
    rescue StandardError
    end

    # 选中事件
    def select(ev)
      @selected = ev
      overlay.redraw
    end

    def clear_selected
      @selected = nil
      @dragging = false
      overlay.redraw
    end

    # 移动选中事件(节流): throttle=true 用于拖拽
    def move_selected(x, y, throttle = false)
      ev = @selected
      return unless ev
      return if ev.x == x && ev.y == y
      now = Time.now.to_f
      if !throttle || (now - @modify_ts) >= 0.08
        @modify_ts = now
        ev.moveto(x, y)
        save_edit
        overlay.redraw
      end
    end

    # 提交(松手/落定时强制写一次)
    def commit_selected
      ev = @selected
      return unless ev
      @modify_ts = 0.0
      save_edit
    end

    # 旋转选中事件方向: delta=±1
    def rotate_selected(delta)
      ev = @selected
      return unless ev
      dir = (ev.direction rescue 2)
      idx = DIRS.index(dir) || 0
      ev.direction = DIRS[(idx + delta) % DIRS.size]
      save_edit
      overlay.redraw
    end

    # --- 持久化 ---
    def edits
      @edits ||= begin
        arr = File.exist?(EDITS_PATH) ? (JSON.parse(File.read(EDITS_PATH)) rescue nil) : nil
        arr.is_a?(Array) ? arr : []
      end
    end

    def save_edit
      ev = @selected
      return unless ev && $game_map
      edits
      mid = $game_map.map_id
      @edits.reject! { |r| r['map'].to_i == mid && r['ev'].to_i == ev.id }
      @edits << { 'map' => mid, 'ev' => ev.id, 'x' => ev.x, 'y' => ev.y,
                  'dir' => (ev.direction rescue 2) }
      Dir.mkdir(SETTINGS_DIR) unless File.directory?(SETTINGS_DIR)
      File.write(EDITS_PATH, JSON.generate(@edits))
    end

    # 进入地图时应用该图的持久编辑(以 $game_map.object_id 判重, 换图自动重应用)
    def apply_for_current_map
      map = $game_map
      return unless map
      return if @applied_for == map.object_id
      @applied_for = map.object_id
      edits
      @edits.each do |r|
        next unless r['map'].to_i == map.map_id
        ev = map.events[r['ev'].to_i]
        next unless ev
        begin
          ev.moveto(r['x'].to_i, r['y'].to_i) if r['x']
          ev.direction = r['dir'].to_i if r['dir'].to_i.between?(2, 8)
        rescue StandardError
        end
      end
    end

    # --- 鼠标探测 (mkxp Mouse 扩展) ---
    def mouse_ok?
      @mouse_ok = defined?(Mouse) && Mouse.respond_to?(:x) && Mouse.respond_to?(:y) &&
                  Mouse.respond_to?(:press?) && Mouse.respond_to?(:trigger?) &&
                  Mouse.respond_to?(:released?) unless @mouse_ok == false
      !!@mouse_ok
    end

    def mouse_xy
      return [nil, nil] unless mouse_ok?
      [Mouse.x, Mouse.y]
    rescue StandardError
      [nil, nil]
    end

    def mouse_press?(k); mouse_ok? ? (Mouse.press?(mouse_key(k)) rescue false) : false; end
    def mouse_trigger?(k); mouse_ok? ? (Mouse.trigger?(mouse_key(k)) rescue false) : false; end
    def mouse_released?(k); mouse_ok? ? (Mouse.released?(mouse_key(k)) rescue false) : false; end

    def mouse_key(k)
      @mouse_keys ||= begin
        { left: Mouse::LEFT, right: Mouse::RIGHT,
          wheel_up: Mouse::WHEELUP, wheel_down: Mouse::WHEELDOWN }
      rescue StandardError
        {}
      end
      @mouse_keys[k]
    end

    def erased?(ev)
      !!ev.instance_variable_get(:@erased)
    rescue StandardError
      false
    end
  end

  # ============================================================
  #  覆盖层: 事件标记 + 交互
  # ============================================================
  class Overlay
    def initialize
      @viewport = Viewport.new(0, 0, 640, 480)
      @viewport.z = 260
      @sprite = Sprite.new(@viewport)
      @sprite.bitmap = Bitmap.new(640, 480)
      @sprite.bitmap.font.size = 13
      @sprite.visible = false
    end

    def set_visible(v)
      @sprite.visible = v
    end

    def update_frame
      map = $game_map
      return unless map
      # 镜头像素偏移(格子级对齐)
      dx = map.display_x / 4
      dy = map.display_y / 4
      @sprite.x = -(dx % TILE)
      @sprite.y = -(dy % TILE)

      if EventEditor.mouse_ok?
        handle_mouse(map, dx, dy)
      else
        handle_keyboard(map)
      end
      redraw(map, dx, dy)
    end

    # ---------- 鼠标交互 ----------
    def handle_mouse(map, dx, dy)
      mx, my = EventEditor.mouse_xy
      if mx && my
        tx = (mx + dx) / TILE
        ty = (my + dy) / TILE
        EventEditor.instance_variable_set(:@hover_tile, map.valid?(tx, ty) ? [tx, ty] : nil)
        if @last_hover != [tx, ty]
          @last_hover = [tx, ty]
          EventEditor.instance_variable_set(:@same_tile_click, 0)
        end
      else
        EventEditor.instance_variable_set(:@hover_tile, nil)
      end

      if EventEditor.mouse_trigger?(:left)
        ev = pick_event(map, EventEditor.instance_variable_get(:@hover_tile))
        if ev
          EventEditor.select(ev)
          EventEditor.instance_variable_set(:@dragging, true)
        end
      elsif EventEditor.instance_variable_get(:@dragging) &&
            EventEditor.mouse_press?(:left) && EventEditor.selected
        ht = EventEditor.instance_variable_get(:@hover_tile)
        EventEditor.move_selected(ht[0], ht[1], true) if ht
      elsif EventEditor.instance_variable_get(:@dragging) &&
            EventEditor.mouse_released?(:left)
        EventEditor.instance_variable_set(:@dragging, false)
        EventEditor.commit_selected
      end

      if EventEditor.selected
        if EventEditor.mouse_trigger?(:wheel_up)
          EventEditor.rotate_selected(-1)
        elsif EventEditor.mouse_trigger?(:wheel_down)
          EventEditor.rotate_selected(1)
        end
      end

      if EventEditor.mouse_trigger?(:right)
        EventEditor.clear_selected
      end
    end

    # 拾取鼠标格上的事件(同格多点循环选择, 按 id 排序)
    def pick_event(map, tile)
      return nil unless tile
      list = map.events.values.select do |ev|
        !EventEditor.erased?(ev) && ev.x == tile[0] && ev.y == tile[1]
      end
      return nil if list.empty?
      list = list.sort_by(&:id)
      c = EventEditor.instance_variable_get(:@same_tile_click)
      EventEditor.instance_variable_set(:@same_tile_click, c + 1)
      list[c % list.size]
    end

    # ---------- 键盘降级交互(无 Mouse 时) ----------
    def handle_keyboard(map)
      cur = EventEditor.instance_variable_get(:@cursor_tile)
      unless cur
        cur = [$game_player.x, $game_player.y]
        EventEditor.instance_variable_set(:@cursor_tile, cur)
      end
      step = Input.trigger?(Input::LEFT) ? [-1, 0] : nil
      step = [1, 0] if Input.trigger?(Input::RIGHT)
      step = [0, -1] if Input.trigger?(Input::UP)
      step = [0, 1] if Input.trigger?(Input::DOWN)
      if step
        nx = cur[0] + step[0]
        ny = cur[1] + step[1]
        if map.valid?(nx, ny)
          EventEditor.instance_variable_set(:@cursor_tile, [nx, ny])
          if EventEditor.selected
            EventEditor.move_selected(nx, ny, false)
          end
        end
      end
      if Input.trigger?(Input::C)   # Enter/Space(=C)
        ev = pick_event(map, cur)
        ev ? EventEditor.select(ev) : EventEditor.clear_selected
      end
      if Input.trigger?(Input::B)   # Esc(=B): 取消选中
        EventEditor.clear_selected
      end
      if Input.trigger?(Input::L)
        EventEditor.rotate_selected(-1)
      elsif Input.trigger?(Input::R)
        EventEditor.rotate_selected(1)
      end
    end

    # ---------- 绘制 ----------
    def redraw(map = $game_map, dx = nil, dy = nil)
      bmp = @sprite.bitmap
      bmp.clear
      return unless map
      dx ||= map.display_x / 4
      dy ||= map.display_y / 4
      x0 = dx / TILE
      y0 = dy / TILE
      sel = EventEditor.selected

      # 事件标记
      map.events.each_value do |ev|
        next if EventEditor.erased?(ev)
        px = (ev.x - x0) * TILE + TILE / 2
        py = (ev.y - y0) * TILE + TILE / 2
        next if px < -50 || px > 690 || py < -50 || py > 530
        is_sel = (ev == sel)
        col = ev_color(ev, is_sel)
        bmp.fill_rect(px - 5, py - 5, 10, 10, col)
        bmp.draw_text(px + 8, py - 9, 64, 16, ev.id.to_s, 0)
        if is_sel
          bmp.draw_text(px - 40, py + 6, 200, 16,
                        "(#{ev.x},#{ev.y}) d#{(ev.direction rescue 2)}", 0)
        end
      end

      # 悬停格高亮(未选中时)
      ht = EventEditor.instance_variable_get(:@hover_tile)
      if ht && !sel
        bmp.fill_rect((ht[0] - x0) * TILE, (ht[1] - y0) * TILE, TILE, TILE,
                      Color.new(255, 255, 0, 60))
      end
      # 键盘光标格
      ct = EventEditor.instance_variable_get(:@cursor_tile)
      if ct && !EventEditor.mouse_ok? && !sel
        bmp.fill_rect((ct[0] - x0) * TILE, (ct[1] - y0) * TILE, TILE, TILE,
                      Color.new(0, 255, 255, 70))
      end

      # 顶栏 HUD
      bmp.fill_rect(0, 0, 640, 20, Color.new(0, 0, 0, 150))
      if sel
        info = "事件 ##{sel.id} #{sel.name} (#{sel.x},#{sel.y}) d#{(sel.direction rescue 2)}"
      else
        info = "未选中"
      end
      bmp.draw_text(4, 2, 460, 16, "事件编辑 Ctrl+E退出 | #{info}", 0)
      bmp.draw_text(464, 2, 172, 16, "左键拖移 滚轮方向 右键取消", 0)
    end

    def ev_color(ev, is_sel)
      return Color.new(255, 40, 40, 230) if is_sel
      name = ev.name.to_s.downcase
      if name.include?('door') || name.include?('exit') || name.include?('entrance')
        Color.new(0, 120, 255, 220)
      elsif (ev.trigger rescue 0) == 1
        Color.new(255, 165, 0, 220)
      else
        Color.new(150, 150, 150, 200)
      end
    end
  end
end

# ============================================================
#  Scene_Map 补丁: Ctrl+E 切换 + 编辑模式拦截 super
# ============================================================
module EventEditorPatch
  def update
    begin
      if editor_toggle_triggered?
        EventEditor.toggle
        $game_system.se_play($data_system.decision_se) if $game_system && $data_system
      end
      if EventEditor.active?
        EventEditor.frame
        return   # 编辑模式: 暂停玩家/事件/镜头, 只更新编辑器
      end
      EventEditor.idle
    rescue StandardError
      # 编辑器异常不影响主流程
    end
    super
  end

  private

  # Ctrl+E 切换编辑模式 (仅开发者模式)
  def editor_toggle_triggered?
    return false unless $dev_settings_enabled
    return false unless Input.respond_to?(:triggerex?)
    return false unless Input.respond_to?(:pressex?)
    (Input.pressex?(:LCTRL) || Input.pressex?(:RCTRL)) && Input.triggerex?(:E)
  rescue StandardError
    false
  end
end

# --- 等待 Scene_Map 类定义完成后 prepend 补丁 ---
PatchHelper.install('Scene_Map', methods: [:update]) do |k|
  k.prepend(EventEditorPatch)
end

# --- 写状态文件 ---
StatusLog.write('event_editor_status.txt', [
  "event_editor loaded at = #{Time.now}",
  "toggle = Ctrl+E (Scene_Map, requires is_developer)",
  "mouse = #{EventEditor.mouse_ok?} (mkxp Mouse extension; keyboard fallback if unavailable)",
  "mouse_keys = #{EventEditor.mouse_key(:left).inspect}",
  "drag = left hold moves event (throttled 0.08s), wheel rotates dir, right cancels",
  "persist = settings/event_edits.json (per map+ev overwrite), applied on map enter (object_id key)",
  "web = live_state.json syncs new positions to door_graph.html every ~0.5s",
  "pause = editor mode intercepts Scene_Map#update super (player/events/camera frozen)"
])
