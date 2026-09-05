# ============================================================
#  skip_event.rb — "skip_event" 设置: 事件快进 / 正常经历但防卡
#
#  config "skip_event" (可在开发者设置 Ctrl+D 中实时切换):
#    true  → 事件"快进": 事件照常触发执行(保留必要流程 —— 出口传送、
#           物品使用、开关/变量设置、剧情逻辑都会正常跑),
#           但跳过所有"等待玩家 / 等待时间"的命令, 事件瞬间完成,
#           不锁玩家、不黑屏:
#             * 101/401 Show Text    → 跳过对话文本
#             * 102   Show Choices   → 自动选第一个选项
#             * 105   按键等待       → 直接跳过
#             * 106/230 时间等待     → 直接跳过
#           效果: 走到任何事件(NPC/剧情/出口)都瞬间通过, 自由探索。
#
#    false → 事件正常触发(角色经历对话/剧情) + 防卡 watchdog:
#            * map_interpreter 运行中, 连续 WATCHDOG_FRAMES 帧 @index
#              无推进, 且无对话/选择窗口, 且当前命令非 move route(212)/
#              wait(230)/animation(231)(这些命令会合法地停在原地),
#              判定为"卡死"(如 SW11 残留反复触发出口传送、跳关后错位
#              状态的剧情事件) → 清空解释器, 恢复玩家控制。
#
#  纯 preload 实现, 不修改游戏原始文件。用 TracePoint(:end) 监听
#  Interpreter / Scene_Map 类定义, 就绪后用 Module#prepend 打补丁。
#
#  依赖:
#    dev_settings.rb 的 GLOBAL_SYNC 提供 '$skip_event_enabled' 实时同步
#    skip_dialogue.rb 的 SkipAllDialoguePatch(同一 execute_command 链, 本补丁在外层)
# ============================================================

require 'json'

SKIP_EVENT_CONFIG_PATH = File.join(__dir__, '..', 'config.json')

# 防卡 watchdog 阈值: 180 帧 ≈ 3 秒 (60fps)
WATCHDOG_FRAMES = 180

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

# --- 补丁 1: 事件快进 (skip_event=true) ---
# 在 execute_command 层拦截"等待类"命令并跳过, 事件其余命令照常执行。
# 注意: 101/102 的 @index 处理与 skip_dialogue 相同 —— 101 时把 @index
# 移到最后一个 401(靠 update 统一 +1 越过), 102 只设 @branch[0] 选择索引。
# 105/106/230 直接 return(靠 update 的 +1 进入下一条)。
module SkipEventFastForwardPatch
  def execute_command
    if $skip_event_enabled && @index < @list.size && @list[@index]
      case @list[@index].code
      when 101, 401
        @index += 1 while @index < @list.size - 1 && @list[@index + 1].code == 401
        return true
      when 102
        @branch[0] = 0
        return true
      when 105, 106, 230
        return true
      end
    end
    super
  end
end

# --- 补丁 2: 防卡 watchdog (skip_event=false) ---
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
    return if $skip_event_enabled   # 快进模式无需防卡
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
PatchHelper.install('Interpreter', methods: [:execute_command]) do |k|
  k.prepend(SkipEventFastForwardPatch)
end

PatchHelper.install('Scene_Map', methods: [:update]) do |k|
  k.prepend(SkipEventWatchdogPatch)
end

# --- 写状态文件 ---
StatusLog.write('skip_event_status.txt', [
  "skip_event loaded at = #{Time.now}",
  "skip_event_enabled = #{$skip_event_enabled}",
  "fast_forward_mode = events run but skip 101/401(text), 102(choice auto-first), 105(key wait), 106/230(time wait)",
  "  → events complete instantly, no lock, no black screen; exits/items/switches still run",
  "normal_mode = events run normally + watchdog",
  "watchdog_frames = #{WATCHDOG_FRAMES} (no message window, not 212/230/231, @index stuck)",
  "patch_method = PatchHelper.install (Interpreter#execute_command + Scene_Map#update)"
])
