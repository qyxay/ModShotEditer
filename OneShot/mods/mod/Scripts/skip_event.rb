# ============================================================
#  skip_event.rb — "skip_event" 设置: 跳过事件 / 正常经历但防卡
#
#  config "skip_event" (可在开发者设置 Ctrl+D 中实时切换):
#    true  → 跳过事件触发:
#            * 地图 autorun 事件 (trigger 3)        — 不触发
#            * 玩家触发事件 (here/there/touch)      — 不触发
#            * 公共事件 autorun (trigger 1)         — 不触发
#            * 并行事件 (trigger 4) 保留 — OneShot 地图出口传送依赖
#              并行的 exit 检测(设 SW11 → 公共事件 #9 执行 201 传送),
#              跳掉并行会导致无法换图。
#            → 效果: 地图无剧情/对话/互动, 自由探索, 仅靠出口传送换图。
#
#    false → 事件正常触发(角色经历对话/剧情) + 防卡 watchdog:
#            * map_interpreter 运行中, 连续 WATCHDOG_FRAMES 帧 @index
#              无推进, 且无对话/选择窗口, 且当前命令非 move route(212)/
#              wait(230)/animation(231)(这些命令会合法地停在原地),
#              判定为"卡死"(如 SW11 残留反复触发出口传送、跳关后错位
#              状态的剧情事件) → 清空解释器, 恢复玩家控制。
#
#  纯 preload 实现, 不修改游戏原始文件。用 TracePoint(:end) 监听
#  Game_Event / Game_Character / Interpreter / Scene_Map 类定义, 就绪后
#  用 Module#prepend 打补丁。
#
#  依赖:
#    dev_settings.rb 的 GLOBAL_SYNC 提供 '$skip_event_enabled' 实时同步
#    jump_map_free.rb 的自由浏览模式($jump_map_free_mode)与本设置相互独立
# ============================================================

require 'json'

SKIP_EVENT_CONFIG_PATH = File.join(__dir__, '..', 'config.json')

# 防卡 watchdog 阈值: 180 帧 ≈ 3 秒 (60fps)
WATCHDOG_FRAMES = 180

# 公共事件白名单(即使 skip_event=true 也放行): #9 "Exit Transition" 出口传送
SKIP_EVENT_KEEP_COMMON = [9]

# --- 读取 config 中的 skip_event ---
def skip_event_load_config
  cfg = begin
    JSON.parse(File.read(SKIP_EVENT_CONFIG_PATH))
  rescue StandardError
    $mod_config || {}
  end
  $skip_event_enabled = cfg['skip_event'] ? true : false
end

skip_event_load_config

# --- 补丁 1: 跳过地图事件触发 (skip_event=true) ---
# autorun(trigger 3) / 玩家触发(here/there/touch) 一律不触发;
# 并行事件(trigger 4)不在此列(由 Game_Event#update 直接 start, 保留出口)。
module SkipEventFreezePatch
  def check_event_trigger_auto
    return if $skip_event_enabled && @trigger == 3
    super
  end

  def check_event_trigger_here(triggers)
    return if $skip_event_enabled
    super
  end

  def check_event_trigger_there(triggers)
    return if $skip_event_enabled
    super
  end

  def check_event_trigger_touch(x, y)
    return if $skip_event_enabled
    super
  end
end

# --- 补丁 2: 跳过公共事件 autorun (skip_event=true) ---
# 临时把 trigger==1 的公共事件改为非 autorun, 原循环即跳过; 保留
# SKIP_EVENT_KEEP_COMMON 白名单(出口传送 #9), 结束后立即恢复。
module SkipEventCommonPatch
  def setup_starting_event
    if $skip_event_enabled
      saved = []
      $data_common_events.each_with_index do |ce, i|
        if ce && ce.trigger == 1 && !SKIP_EVENT_KEEP_COMMON.include?(i)
          saved << [i, ce]
          ce.trigger = 0
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

# --- 补丁 3: 防卡 watchdog (skip_event=false) ---
# 只监控主解释器($game_system.map_interpreter, autorun/玩家触发用),
# 并行解释器不在此列, 不受影响。
module SkipEventWatchdogPatch
  def update
    begin
      skip_event_watchdog
    rescue StandardError
      # watchdog 异常不影响主流程
    end
    super
  end

  private

  def skip_event_watchdog
    return if $skip_event_enabled   # 跳过模式无需防卡
    mi = $game_system && $game_system.map_interpreter
    return unless mi && mi.running?
    # 对话/选择窗口显示中 = 正常等待玩家, 不算卡
    return if $game_temp.message_window_showing
    list = mi.instance_variable_get(:@list)
    idx = mi.instance_variable_get(:@index)
    return unless list && idx && idx < list.size
    code = list[idx].respond_to?(:code) ? list[idx].code : 0
    # move route / wait / animation 会合法地停在原地, 不算卡
    return if [212, 230, 231].include?(code)
    key = [list.object_id, idx]
    if key == @skip_event_watch_key
      @skip_event_watch_count += 1
      if @skip_event_watch_count >= WATCHDOG_FRAMES
        # 判定卡死: 清空解释器, 恢复玩家控制
        mi.clear
        @skip_event_watch_count = 0
      end
    else
      @skip_event_watch_key = key
      @skip_event_watch_count = 0
    end
  end
end

# --- 等待类定义完成后 prepend 补丁 ---
PatchHelper.install('Game_Event', methods: [:check_event_trigger_auto]) do |k|
  k.prepend(SkipEventFreezePatch)
end

PatchHelper.install('Game_Character', methods: [:check_event_trigger_here,
                                              :check_event_trigger_there,
                                              :check_event_trigger_touch]) do |k|
  k.prepend(SkipEventFreezePatch)
end

PatchHelper.install('Interpreter', methods: [:setup_starting_event]) do |k|
  k.prepend(SkipEventCommonPatch)
end

PatchHelper.install('Scene_Map', methods: [:update]) do |k|
  k.prepend(SkipEventWatchdogPatch)
end

# --- 写状态文件 ---
StatusLog.write('skip_event_status.txt', [
  "skip_event loaded at = #{Time.now}",
  "skip_event_enabled = #{$skip_event_enabled}",
  "skip_mode = autorun/here/there/touch/common-autorun skipped, parallel kept (exit relies on it)",
  "normal_mode = events run normally + watchdog",
  "watchdog_frames = #{WATCHDOG_FRAMES} (no message window, not 212/230/231, @index stuck)",
  "keep_common_events = #{SKIP_EVENT_KEEP_COMMON.inspect} (Exit Transition 出口传送)"
])
