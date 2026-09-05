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
#             * 105   按钮输入       → 模拟"已按确认键"(设参数变量非0),
#                                     防依赖按键的 loop 死循环(CG 停留)
#             * 106/230 时间等待     → 直接跳过
#             * 231/232 显示图片/效果 → 直接跳过(CG 过场不显示, 防反复闪现)
#           效果: 走到任何事件(NPC/剧情/出口)都瞬间通过, 自由探索。
#
#    false → 事件正常触发(角色经历对话/剧情) + 防卡 watchdog:
#            * map_interpreter 运行中, 连续 WATCHDOG_FRAMES 帧 @index
#              无推进, 且无对话/选择窗口, 且无任何"合法等待"状态
#              (message/move route/button input/wait_count/子解释器),
#              且当前命令非 move route(212)/wait(230)/animation(231),
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

# --- 诊断 trace (写入 skip_trace.log) ---
def skip_event_trace(msg)
  StatusLog.append('skip_trace.log', msg)
end

# --- 识别"播放开场 CG"的事件 (skip_event=true 时特殊阻止) ---
# 开场流程 = 新游戏/读档后的启动演出, 由这些事件驱动:
#   map1 ev1 (init)      —— 开场主流程(读档/instruction CG/cg_wake CG/开场BGM/传送)
#   map2 ev7, map188 ev7 (intro) —— "niko 在床上醒来"的 intro(床上CG + 推玩家 move route)
#   CE15 (Instructions)  —— 操作说明 CG (由 map1 init c117 调用)
#   CE42 (Load Save)     —— 读档后的苏醒/开场对话 (real_load 设置 common_event_id=42)
# 特殊阻止 = 快进这些事件时, 额外:
#   * 241 播放 BGM   → 拦截 + Audio.bgm_stop(开场音乐不播; 若读档恢复的
#                      开场音乐已在播, 一并停止 —— 空名 241(停止BGM) 则放行执行)
#   * 209 移动路线   → 拦截(intro 的"推玩家" move route 不执行, 避免角色
#                      被推到不可达位置而卡住/抽搐)
# 其余等待类/图片命令沿用已有快进。
def skip_event_opening_event?
  begin
    if @event_id == 0
      # 公共事件(CE15 Instructions / CE42 Load Save): mkxp-z 里 setup 时
      # @event_id=0, 事件名记在 @event_name("/Instructions" 等)。
      @event_name.to_s =~ /Instructions|Load Save/i
    else
      mid = $game_map.map_id.to_i
      (mid == 1 && @event_id == 1) || ([2, 188].include?(mid) && @event_id == 7)
    end
  rescue StandardError
    false
  end
end

# --- 补丁 1: 事件快进 (skip_event=true) ---
# 在 execute_command 层拦截"等待类"命令并跳过, 事件其余命令照常执行。
# 注意: 101/102 的 @index 处理与 skip_dialogue 相同 —— 101 时把 @index
# 移到最后一个 401(靠 update 统一 +1 越过), 102 只设 @branch[0] 选择索引。
# 105/106/230 直接 return(靠 update 的 +1 进入下一条)。
module SkipEventFastForwardPatch
  def execute_command
    if @index < @list.size && @list[@index]
      code = @list[@index].code
      if $skip_event_enabled
        case code
        when 101, 401
          @index += 1 while @index < @list.size - 1 && @list[@index + 1].code == 401
          skip_event_trace("SE_FAST c#{code} ev=#{@event_id} idx=#{@index}")
          return true
        when 102
          @branch[0] = 0
          skip_event_trace("SE_FAST c102 ev=#{@event_id} idx=#{@index}")
          return true
        when 105
          # 按钮输入(OneShot 定制 command_105): 等待玩家按键并把按键值存入
          # 参数变量。快进时模拟"已按确认键"——把参数变量设为非 0(5)。
          # 若不模拟, 依赖按键的 loop/条件分支(如 #15 Instructions 开场 CG:
          # loop → 105 → 条件分支"变量22≠0"→ break)会因变量恒为 0 而死循环,
          # 导致开场 CG 停留/反复展示。
          var_id = @list[@index].parameters[0].to_i
          $game_variables[var_id] = 5 if var_id > 0 && $game_variables
          @button_input_variable_id = 0 if defined?(@button_input_variable_id)
          skip_event_trace("SE_FAST c105 ev=#{@event_id} idx=#{@index} var=#{var_id}")
          return true
        when 106, 230
          skip_event_trace("SE_FAST c#{code} ev=#{@event_id} idx=#{@index}")
          return true
        when 231, 232
          # 显示图片(231)/画面效果(232) —— CG 过场类(如 #15 Instructions 开场
          # 说明、动画 CG)在快进下也跳过, 避免 SW40 残留导致 CE15 反复启动时
          # CG 图片反复闪现。231 跳过=图片从未显示, 无残留; 235 消除不跳过。
          skip_event_trace("SE_FAST c#{code} ev=#{@event_id} idx=#{@index}")
          return true
        when 241
          # 播放 BGM —— 开场事件里特殊阻止: 有名曲目拦截(不播)并主动停止
          # 已播放的(读档恢复的开场音乐会残留, 必须 Audio.bgm_stop);
          # 空名曲目(241 停止 BGM 的命令)则放行执行, 让 BGM 真正停掉
          # (picture_skip 会把空名 241 也当普通 BGM 拦截, 导致停止不执行)。
          if skip_event_opening_event?
            b = (@list[@index].parameters[0] rescue nil)
            name = (b.instance_variable_get(:@name) rescue '').to_s
            if name.empty?
              skip_event_trace("SE_BGM_STOP_CMD opening ev=#{@event_id} idx=#{@index}")
            else
              skip_event_trace("SE_FAST c241 opening ev=#{@event_id} idx=#{@index} #{name}")
              begin
                Audio.bgm_stop if Audio.respond_to?(:bgm_stop)
              rescue StandardError
              end
              return true
            end
          end
        when 209
          # 强制移动路线 —— 开场事件里拦截(如 intro 的"推玩家" move route:
          # 快进下跳过 106 等待, move route 若推到不可达位置会永久锁玩家)。
          if skip_event_opening_event?
            skip_event_trace("SE_FAST c209 opening ev=#{@event_id} idx=#{@index}")
            return true
          end
        when 207, 221, 222, 223, 224, 225
          # 诊断: 动画/转场/色调/闪屏/震动 —— 暂不拦截, 只记录(确认"CG"是否这些)
          skip_event_trace("SE_VIS c#{code} ev=#{@event_id} idx=#{@index}")
        when 355
          txt = @list[@index].parameters[0].to_s
          if txt =~ /Graphics|picture|Scene|transition|smooth|splash/i
            skip_event_trace("SE_355 ev=#{@event_id} idx=#{@index} #{txt[0, 60]}")
          end
        end
      else
        # 诊断: skip_event 关闭时记录关键命令的到达(确认运行时开关状态)
        if [101, 105, 231].include?(code)
          skip_event_trace("SE_OFF c#{code} ev=#{@event_id} idx=#{@index}")
        end
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
    # 任何"合法等待"状态 → 事件正常进行, 不算卡(否则 106 时间等待 /
    # 105 按键等待 / move route 进行中 / 子解释器运行中会因 @index 暂时
    # 不变而被误判卡死, 清空事件导致"经历不了事件")
    return if mi.instance_variable_get(:@message_waiting)
    return if mi.instance_variable_get(:@move_route_waiting)
    return if mi.instance_variable_get(:@button_input_variable_id).to_i > 0
    return if mi.instance_variable_get(:@wait_count).to_i > 0
    child = mi.instance_variable_get(:@child_interpreter)
    return if child && child.running?
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

# --- 补丁 3: 记录"实际执行"的 231 显示图片命令 (诊断用) ---
# skip_event 拦截 231 时 command_231 不执行、图片不显示; 若用户仍看到 CG,
# 说明有 231 绕过了拦截 —— 这里记录所有真正执行的 231(含图片名), 直接定位。
module SkipEventPictureLogger
  def command_231
    begin
      name = (@list[@index].parameters[1].to_s rescue '')
      skip_event_trace("PIC_ACTUAL c231 ev=#{@event_id} idx=#{@index} #{name}")
    rescue StandardError
    end
    super
  end
end

# --- 补丁 4: 残留 CG 图片兜底清除 (skip_event=true) ---
# 读档(real_load)会恢复 $game_screen 图片状态: 若存档时开场 CG 图片
# (如 cg_wake4=图片号2) 正在显示, 读档后它会残留覆盖屏幕, 且快进跳过
# 了后续流程、可能没有 235 消除它 → "图片盖在屏幕上, 去不掉"。
# 这里每帧检查: skip_event=true 时, 任何名字含 cg_wake/cg_tower/
# instruction/felix 的显示中图片直接 erase(清空 name 即不绘制)。
# --- 共享: 清除残留 CG 图片 (补丁4 每帧兜底 / 补丁5 读档后, 共用同一正则) ---
CG_PICTURE_RE = %r{cg_wake|cg_tower|instruction|felix|cg_niko_in_bed|^black$|^white$}i
def skip_event_clear_cg_pictures(tag)
  pics = $game_screen.pictures
  return unless pics
  pics.each_with_index do |pic, i|
    next unless pic
    name = (pic.name.to_s rescue '')
    next if name.empty?
    if name =~ CG_PICTURE_RE
      skip_event_trace("#{tag} num=#{i} name=#{name}")
      pic.erase
    end
  end
end

module SkipEventCgCleanerPatch
  def update
    begin
      skip_event_clear_cg_pictures('SE_CLEAR_PIC') if $skip_event_enabled && $game_screen
      # 每帧 BGM 兜底: 开场曲(SomeplaceIKnow)在 skip_event 快进下不该出现。
      # real_load :242 会 bgm_play(playing_bgm) 恢复存档时的开场音乐, 且
      # Game_Temp#bgm_fadein 可能随后把它重播回来 —— 每帧检查并停止,
      # 保证开场音乐绝不残留(正常游玩不播这首, 不影响其他 BGM)。
      if $skip_event_enabled && $game_system && Audio.respond_to?(:bgm_stop)
        pbgm = ($game_system.playing_bgm rescue nil)
        if pbgm
          bname = (pbgm.name.to_s rescue '')
          if !bname.empty? && bname =~ /SomeplaceIKnow/i
            skip_event_trace("SE_STOP_BGM_FRAME name=#{bname}")
            Audio.bgm_stop
          end
        end
      end
    rescue StandardError
      # 兜底清除异常不影响主流程
    end
    super
  end
end

# --- 补丁 5: 读档后立即清除残留 CG 图片 (skip_event=true) ---
# 每帧兜底清除有一帧延迟(读档恢复图片 → 下一帧才清 → 用户看到"一瞬间")。
# 这里 prepend 全局方法 real_load: 读档(load)完成、画面恢复前立即清除,
# 使 CG 图片连一帧都不显示。
module SkipEventRealLoadPatch
  def real_load
    result = super
    begin
      skip_event_clear_cg_pictures('SE_CLEAR_AFTER_LOAD') if $skip_event_enabled && $game_screen
      # 读档会恢复存档时的 BGM 状态: 若存档时开场音乐(SomeplaceIKnow 等)
      # 正在播, 读档后它继续响, 且快进拦截了后续 241(包括空名"停止 BGM")
      # 导致停不下来。这里读档后直接停止 BGM, 开场静音; 后续正常事件
      # 的 241(非开场事件)仍可正常播放音乐。
      if $skip_event_enabled && Audio.respond_to?(:bgm_stop)
        Audio.bgm_stop
        skip_event_trace("SE_STOP_BGM_AFTER_LOAD")
      end
    rescue StandardError
    end
    result
  end
end

Object.prepend(SkipEventRealLoadPatch)

# --- 等待类定义完成后 prepend 补丁 ---
PatchHelper.install('Interpreter', methods: [:execute_command]) do |k|
  k.prepend(SkipEventFastForwardPatch)
  skip_event_trace("SE_MOUNTED Interpreter#execute_command (skip_event_enabled=#{$skip_event_enabled})")
end

PatchHelper.install('Interpreter', methods: [:command_231]) do |k|
  k.prepend(SkipEventPictureLogger)
  skip_event_trace("SE_MOUNTED_PICLOG Interpreter#command_231")
end

PatchHelper.install('Scene_Map', methods: [:update]) do |k|
  k.prepend(SkipEventWatchdogPatch)
end

PatchHelper.install('Scene_Map', methods: [:update]) do |k|
  k.prepend(SkipEventCgCleanerPatch)
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
