# ============================================================
#  fly_mode.rb — Niko 飞行行走模式 (Fly)
#
#  按 Ctrl+F 进入/退出飞行模式 (需 config "is_developer": true):
#    * 无视障碍物: 地图内任意方向可通行 (不越过地图边界)
#    * 速度: run 模式速度的 2 倍 (run=4→5, 32px/帧; 开关 251 反转时 run=3→4)
#    * 角色置顶: 飞行中 Niko 显示在所有图层之上 (always_on_top)
#    * 保留传送事件: 目标格存在可触发的接触事件(trigger 1/2,
#      非 over_trigger?)时视为不可通行, 走原版 else 分支触发
#      check_event_trigger_touch; 区域触发(over_trigger?)事件
#      仍按停止时触发。飞行不会导致传送/门失效。
#
#  飞行只作用于玩家自由行走时; 事件/强制移动路线/对话/菜单进行中
#  不生效 (与 Game_Player#update 的移动闸门一致, 不干扰演出脚本)。
#
#  实现 (纯 preload, 不修改游戏原始文件):
#    * Scene_Map#update      prepend → Ctrl+F 切换 + 屏显指示同步
#    * Game_Player#passable? prepend → 飞行时绕过碰撞判定 (地图边界仍生效;
#      接触触发事件格保留阻挡以触发传送)
#    * Game_Player#update_move prepend → 飞行时移动速度 = run 速度
#
#  配置: mods/mod/config.json
#    "fly_mode": false → 初始关闭 (游戏内 Ctrl+F 切换并写回,
#      也可在开发者设置菜单中切换, 即时生效)
# ============================================================

require 'json'

# --- 读取配置 (统一由 _config.rb 加载到 $mod_config) ---
default_config = { "fly_mode" => false }
config = default_config.merge($mod_config || {})

$fly_mode_enabled = config["fly_mode"] ? true : false

# config.json 路径 (与 dev_settings.rb 相同)
FLY_CONFIG_PATH = File.join(__dir__, '..', 'config.json')

# ============================================================
#  飞行生效条件: 仅玩家自由行走时
# ============================================================
module FlyMode
  def self.active?
    return false unless $fly_mode_enabled
    return false unless $game_map && $game_player && $game_system && $game_temp
    return false if $game_temp.transition_processing
    return false if $game_temp.player_transferring
    return false if $game_system.map_interpreter.running?
    return false if $game_temp.message_window_showing
    return false if $game_temp.menus_visible
    return false if $game_player.instance_variable_get(:@move_route_forcing)
    true
  end

  # 写回 config.json (保留原键顺序, 与 dev_settings.rb 的固定顺序一致)
  def self.save_config
    $mod_config ||= {}
    $mod_config['fly_mode'] = $fly_mode_enabled
    ordered = {}
    %w[skip_pictures quit_all_time skip_dialogue skip_choice skip_uneasy always_travel always_settings unshow_title is_developer fly_mode live_update].each do |k|
      ordered[k] = $mod_config[k] if $mod_config.key?(k)
    end
    $mod_config.each do |k, v|
      ordered[k] = v unless ordered.key?(k)
    end
    File.write(FLY_CONFIG_PATH, JSON.pretty_generate(ordered) + "\n")
  rescue StandardError
  end
end

# ============================================================
#  屏显指示: 左上角 FLY 徽标 (飞行开启时显示)
#  z=20000: 位于所有图层/窗口之上 (含 dev_settings 9999 / jump_map 10000)
# ============================================================
class FlyModeIndicator
  def initialize
    @viewport = Viewport.new(0, 0, 640, 480)
    @viewport.z = 20000
    @sprite = Sprite.new(@viewport)
    @sprite.bitmap = Bitmap.new(96, 24)
    @sprite.bitmap.font.size = 16
    @sprite.bitmap.font.bold = true
    @sprite.bitmap.draw_text(0, 0, 96, 24, 'FLY', 1)
    @sprite.x = 6
    @sprite.y = 6
    @sprite.visible = false
  end

  def visible=(v)
    @sprite.visible = v
  end

  def dispose
    @sprite.dispose
    @viewport.dispose
  end
end

$fly_mode_indicator = nil  # 惰性创建 (Scene_Map 首次 update 时实例化)

# ============================================================
#  Scene_Map 补丁: Ctrl+F 切换飞行 + 指示同步
# ============================================================
module FlyModeScenePatch
  def update
    begin
      fly_sync_indicator
      fly_toggle_handle
    rescue StandardError
      # 快捷键异常不影响主流程
    end
    super
  end

  private

  # 每帧同步指示 (dev_settings 菜单切换 fly_mode 时也能即时反映)
  def fly_sync_indicator
    $fly_mode_indicator ||= FlyModeIndicator.new
    $fly_mode_indicator.visible = $fly_mode_enabled
  end

  def fly_toggle_handle
    return unless $dev_settings_enabled
    return unless fly_toggle_triggered?
    return unless $game_map && $game_player
    # 转场/传送中禁用, 避免干扰 Graphics.freeze/transition
    return if $game_temp.transition_processing
    return if $game_temp.player_transferring

    $fly_mode_enabled = !$fly_mode_enabled
    # 飞行中角色置顶显示 (所有图层之上), 退出时恢复原状态
    if $fly_mode_enabled
      $fly_old_always_on_top = $game_player.instance_variable_get(:@always_on_top)
      $game_player.instance_variable_set(:@always_on_top, true)
    else
      $game_player.instance_variable_set(:@always_on_top, $fly_old_always_on_top ? true : false)
      $fly_old_always_on_top = nil
    end
    FlyMode.save_config
    $fly_mode_indicator.visible = $fly_mode_enabled if $fly_mode_indicator
    if $game_system && $data_system
      $game_system.se_play($fly_mode_enabled ? $data_system.decision_se : $data_system.cancel_se)
    end
    StatusLog.append('fly_mode_status.txt', "toggle=#{$fly_mode_enabled ? 'ON' : 'OFF'}")
  end

  # Ctrl+F 触发检测: 优先 mkxp-z 扩展 (pressex?/triggerex?), 回退标准 API
  def fly_toggle_triggered?
    return false unless Input.respond_to?(:triggerex?)
    ctrl = if Input.respond_to?(:pressex?)
             begin
               Input.pressex?(:LCTRL) || Input.pressex?(:RCTRL)
             rescue StandardError
               false
             end
           else
             begin
               Input.press?(Input::CTRL)
             rescue StandardError
               false
             end
           end
    ctrl && (Input.triggerex?(:F) rescue false)
  end
end

# ============================================================
#  Game_Player 补丁: 飞行时无视障碍物 (但保留传送/接触触发事件)
# ============================================================
module FlyModePlayerPassPatch
  def passable?(x, y, d)
    new_x = x + (d == 6 ? 1 : d == 4 ? -1 : 0)
    new_y = y + (d == 2 ? 1 : d == 8 ? -1 : 0)
    # 地图边界仍生效 (不飞出地图)
    return false unless $game_map.valid?(new_x, new_y)
    if FlyMode.active?
      # 保留传送/接触事件: 目标格存在可触发的接触事件时视为不可通行,
      # 使 move_* 走原版 else 分支调用 check_event_trigger_touch 触发事件
      # (与正常行走时"撞上门/接触事件"的体验一致, 飞行不会让传送失效)
      return false if fly_touch_event_at?(new_x, new_y)
      return true
    end
    super
  end

  private

  # 与 Game_Player#check_event_trigger_touch 相同的事件匹配条件
  # (trigger 1/2 + 非 over_trigger? 的面触发事件)
  def fly_touch_event_at?(x, y)
    $game_map.events.each_value do |ev|
      next if ev.jumping?
      next if ev.over_trigger?
      next unless [1, 2].include?(ev.trigger)
      return true if ev.x == x && ev.y == y
    end
    false
  end
end

# ============================================================
#  Game_Player 补丁: 飞行时速度 = run 模式
#  (update_move 在移动执行前被调用, 此时改 @move_speed 即可
#   覆盖原版 update 的速度行, 保证整段移动恒为 run 速度)
# ============================================================
module FlyModeMoveSpeedPatch
  def update_move
    if FlyMode.active?
      # 飞行速度 = run 速度的 2 倍 (move_speed+1 ⇒ 像素/帧翻倍):
      #   251 关闭时 run=4 → 5 (16→32px/帧)
      #   251 反转时 run=3 → 4 (8→16px/帧)
      @move_speed = $game_switches[251] ? 4 : 5
    end
    super
  end
end

# --- 等待类定义完成后 prepend 补丁 ---
PatchHelper.install('Scene_Map', methods: [:update]) do |k|
  k.prepend(FlyModeScenePatch)
end

PatchHelper.install('Game_Player', methods: [:passable?]) do |k|
  k.prepend(FlyModePlayerPassPatch)
end

PatchHelper.install('Game_Player', methods: [:update_move]) do |k|
  k.prepend(FlyModeMoveSpeedPatch)
end

# ============================================================
#  Game_Character 补丁: fly 模式开启时, Game_Event 无视地形碰撞
#  (地图边界仍生效, 防止事件飞出地图)
#
#  原版 Game_Event 没有自己的 passable?, 继承 Game_Character。
#  这里 prepend 到 Game_Character: $fly_mode_enabled 且 self 是
#  Game_Event 时直接返回 true (保留地图边界), 否则走原版逻辑。
#  影响范围: 所有 Game_Event 实例 (强制移动路线 / 随机移动),
#  不影响 Game_Player (已重写 passable?) / Game_Follower (已重写)。
# ============================================================
module FlyModeEventPassPatch
  def passable?(x, y, d)
    new_x = x + (d == 6 ? 1 : d == 4 ? -1 : 0)
    new_y = y + (d == 2 ? 1 : d == 8 ? -1 : 0)
    # 地图边界仍生效
    return false unless $game_map.valid?(new_x, new_y)
    if $fly_mode_enabled && self.is_a?(Game_Event)
      return true
    end
    super
  end
end

# --- 等待类定义完成后 prepend 补丁 ---
PatchHelper.install('Game_Character', methods: [:passable?]) do |k|
  k.prepend(FlyModeEventPassPatch)
end

# --- 写状态文件 ---
StatusLog.write('fly_mode_status.txt', [
  "fly_mode loaded at = #{Time.now}",
  "fly_mode_enabled = #{$fly_mode_enabled} (initial from config)",
  "toggle = Ctrl+F (Scene_Map, requires is_developer, except transition/transfer)",
  "obstacles = ignored while flying (map bounds still enforced)",
  "touch_events = PRESERVED: contact-trigger events (trigger 1/2, non-over_trigger) still block+fire, region triggers (over_trigger) fire on stop",
  "on_top = player always_on_top while flying (restored on exit), FLY badge z=20000 above all layers/windows",
  "speed = 2x run-mode speed (run=4→5=32px/frame; switch 251 inverted run=3→4), enforced at update_move",
  "scope = free movement only (events / forced move routes / dialogue / menu unaffected)",
  "event_wallhack = Game_Event#passable? returns true while fly_mode_enabled (map bounds kept), affects forced move routes & random movement, not followers",
  "config_writeback = fly_mode key synced to config.json on toggle",
  "patches = Scene_Map#update, Game_Player#passable?, Game_Player#update_move, Game_Event#passable?"
])
