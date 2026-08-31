# ============================================================
#  zz_diagnose.rb — 临时诊断脚本(用完即删)
#  目标: 定位 "Jump Map 跳到 livingroom 后角色动不了 + 无法进设置"
#  记录: 1) 冻结补丁是否生效  2) 跳转后 300 帧内的关键状态
#  输出: mods/mod/jump_diag.log
# ============================================================

DIAG_PATH = File.join(__dir__, '..', 'jump_diag.log')

def diag(*args)
  line = "[#{Time.now.strftime('%H:%M:%S.%L')}] #{args.join(' ')}"
  File.open(DIAG_PATH, 'a') { |f| f.puts(line) }
rescue StandardError
end

# 清空旧日志
begin
  File.delete(DIAG_PATH)
rescue StandardError
end
diag('=== zz_diagnose loaded ===')

# --- 1. 冻结补丁生效自检 ---
diag("Game_Event defined?: #{defined?(Game_Event).inspect}")
if defined?(Game_Event)
  diag("Game_Event ancestors: #{Game_Event.ancestors.inspect}")
  diag("JumpMapFreezePatch applied: #{Game_Event.ancestors.include?(JumpMapFreezePatch)}")
end
diag("Window_Settings defined?: #{defined?(Window_Settings).inspect}")
diag("Window_DevSettings defined?: #{defined?(Window_DevSettings).inspect}")

# --- 2. Scene_Map#update 补丁: 跳转后记录状态 ---
# 帧计数器用全局 $diag_f, 每张地图跳转后由 Game_Map#setup 重置,
# 保证每张地图都能记录前 300 帧状态(不再因上一张地图耗尽上限而漏记)。
module ZzDiagScenePatch
  def update
    begin
      if $jump_map_free_mode && $game_map && $game_map.map_id == $jump_map_frozen_map_id
        $diag_f ||= 0
        $diag_f += 1
        if $diag_f <= 300
          mi = $game_system.map_interpreter
          starting_ids = ($game_map.events ? $game_map.events.values.select { |e| e.starting }.map(&:id).inspect : 'n/a')
          dev = @window_settings.instance_variable_get(:@dev_settings)
          sw = [1, 9, 11, 15, 40].map { |i| "#{i}:#{$game_switches[i]}" }.join(',')
          diag(
            "f=#{$diag_f}",
            "map=#{$game_map.map_id}(frozen)",
            "interp_running=#{mi.running?}",
            "list=#{mi.instance_variable_get(:@list).inspect}",
            "menus_visible=#{$game_temp.menus_visible}",
            "msg_showing=#{$game_temp.message_window_showing}",
            "winset_vis=#{@window_settings.visible}",
            "menu_vis=#{@menu.visible}",
            "item_vis=#{@item_menu.visible}",
            "ft_vis=#{@fast_travel.visible}",
            "dev_vis=#{dev ? dev.visible : 'n/a'}",
            "player=#{$game_player.x},#{$game_player.y}",
            "moving=#{$game_player.moving?}",
            "move_route_forcing=#{$game_player.instance_variable_get(:@move_route_forcing)}",
            "starting=#{starting_ids}",
            "common_event=#{$game_temp.common_event_id}",
            "transf=#{$game_temp.player_transferring}",
            "transproc=#{$game_temp.transition_processing}",
            "menu_disabled=#{$game_system.menu_disabled}",
            "sw[1,9,11,15,40]=#{sw}"
          )
        end
      end
    rescue StandardError => e
      diag("diag_scene ERROR: #{e.class}: #{e.message}")
    end
    super
  end
end

_trace = TracePoint.trace(:end) do |tp|
  begin
    if tp.self.is_a?(Class) && tp.self.name == 'Scene_Map' && tp.self.method_defined?(:update)
      tp.self.prepend(ZzDiagScenePatch)
      diag('Scene_Map#update patched')
      _trace.disable
    end
  rescue StandardError
  end
end

# --- 3. Game_Map#setup 钩子: 记录地图切换 ---
module ZzDiagMapPatch
  def setup(map_id)
    diag("MAP_SETUP -> #{map_id}  (jump_free=#{$jump_map_free_mode} frozen=#{$jump_map_frozen_map_id})")
    # 每张地图跳转后重置帧计数器, 保证新地图的前 300 帧都被记录
    $diag_f = 0
    super
    if $jump_map_free_mode && map_id == $jump_map_frozen_map_id
      evs = @events.values
      starting = evs.select(&:starting).map(&:id)
      autoruns = evs.select { |e| e.trigger == 3 }.map(&:id)
      diag("MAP_SETUP_DONE map=#{map_id} events=#{evs.size} starting=#{starting.inspect} autorun_events=#{autoruns.inspect}")
    end
  rescue StandardError => e
    diag("MAP_SETUP ERROR #{map_id}: #{e.class}: #{e.message}")
    diag(e.backtrace.first(8).join(' | '))
    raise
  end
end

_trace2 = TracePoint.trace(:end) do |tp|
  begin
    if tp.self.is_a?(Class) && tp.self.name == 'Game_Map' && tp.self.method_defined?(:setup)
      tp.self.prepend(ZzDiagMapPatch)
      diag('Game_Map#setup patched')
      _trace2.disable
    end
  rescue StandardError
  end
end

# --- 4. Interpreter#setup 钩子: 记录谁在跳转后被 setup(定位卡死源) ---
module ZzDiagInterpPatch
  def setup(list, event_id, common_event_name = nil)
    if $jump_map_free_mode && $game_map && $game_map.map_id == $jump_map_frozen_map_id && ($diag_f || 0) <= 300
      diag("INTERP_SETUP event_id=#{event_id} name=#{common_event_name.inspect} list_size=#{list ? list.size : 'nil'}")
    end
    super
  end
end

_trace3 = TracePoint.trace(:end) do |tp|
  begin
    if tp.self.is_a?(Class) && tp.self.name == 'Interpreter' && tp.self.method_defined?(:setup)
      tp.self.prepend(ZzDiagInterpPatch)
      diag('Interpreter#setup patched')
      _trace3.disable
    end
  rescue StandardError
  end
end
