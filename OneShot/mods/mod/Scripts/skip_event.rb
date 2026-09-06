# ============================================================
#  skip_event.rb — 事件跳过 (skip_event) 三态模式
#
#  config "skip_event": "off" | "block" | "fast"
#    off   → 正常游玩: 所有事件照常触发执行, 无任何跳过。
#    block → A模式"整体阻止"(自由探索): 识别"限制角色行动的演出事件"
#            (进图自动触发 + 第一页无条件 + 含对话/按键/玩家移动路线/
#            长等待), 整个事件不启动; 玩家主动触发(对话/互动)与 CE9
#            出口传送放行。剧情不推进, 玩家自由行动。
#    fast  → B模式"跳过演出保功能": 事件照常触发, 但跳过演出命令
#            (对话/选项/按键/等待/图片/玩家移动路线), 保留功能命令
#            (传送/开关/变量/调CE/脚本)。每帧限步, 事件跨帧完成,
#            避免一帧跑完导致 real_load 的场景切换被后续命令覆盖。
#
#  自由浏览模式($jump_map_free_mode, Ctrl+J 跳关后进入)与 block 共用
#  同一套"事件级阻止"规则 —— 统一实现。
#
#  公共事件处理(全部经 Interpreter#setup 的 common_event_name 拦截,
#  覆盖 自动 trigger1 / common_event_id 42 / 手动 117 三条路径):
#    CE15 "Instructions" → 阻止(操作教学演出, 锁玩家)
#    CE42 "Load Save"    → 阻止(读档苏醒演出: 推玩家 + CG + 传送)
#    其余(CE1 Use Item / CE2 Text / CE9 Exit Transition 等) → 放行
#
#  铁律(block/fast 共有): 读档(real_load)完成后立即清空主事件解释器
#  —— 事件流终止, 读档恢复的地图/位置不被 map1 ev1 开场流程
#  (felix/cg_wake CG + 传送 map2 等)覆盖。这是修复"重启后进度丢失"
#  的核心: 存档快照若带着运行中的 map1 ev1 解释器状态, 读档后事件流
#  会从该状态继续, 一路跑到"新游戏"分支的传送 map2。
#
#  纯 preload 实现, 不修改游戏原始文件。
# ============================================================

# --- 读取 config 中的 skip_event (三态字符串) ---
$skip_event_mode = ($mod_config && $mod_config['skip_event']).to_s
$skip_event_mode = 'off' unless %w[off block fast].include?($skip_event_mode)

# 自由浏览模式标记 (jump_map.rb 跳关成功后置 true; 与 block 共用规则)
$jump_map_free_mode = false if $jump_map_free_mode.nil?

# fast 模式每帧最多跳过的演出命令数 (限步: 事件跨帧完成, 给 real_load
# 的场景切换留帧间隙, 防一帧跑完事件覆盖读档状态)
FAST_MAX_STEPS_PER_FRAME = 60

# 开场残留 CG 图片名 (兜底清除用)
CG_PICTURE_RE = %r{cg_wake|cg_tower|instruction|felix|cg_niko_in_bed|^black$|^white$}i

# --- 诊断 trace (写入 skip_trace.log) ---
def skip_event_trace(msg)
  StatusLog.append('skip_trace.log', msg)
end

# --- 模式判断 ---
def skip_event_active?
  $skip_event_mode != 'off' || $jump_map_free_mode
end

def skip_event_block_mode?
  $skip_event_mode == 'block' || $jump_map_free_mode
end

# --- 事件分类 (缓存) ---
# 返回 :block(整体阻止) / :partial(部分执行, 仅 map1 ev1) / :allow(放行)
$skip_event_class_cache = {}

def skip_event_classify(map_id, event_id)
  # map1 ev1 "init": 开场总控 —— 必须执行到 real_load(读档)后终止,
  # 不能整体阻止(否则无法读档/开新档); 其演出命令由 execute_command
  # 补丁在 block/fast 模式下跳过
  return :partial if map_id == 1 && event_id == 1

  key = [map_id, event_id]
  return $skip_event_class_cache[key] if $skip_event_class_cache.key?(key)

  result = :allow
  begin
    ev = $game_map && $game_map.events && $game_map.events[event_id]
    if ev
      page = ev.event.pages[0]
      if page && (page.trigger == 3 || page.trigger == 4)  # autorun / parallel
        cond = page.condition
        if cond && !cond.switch1_valid && !cond.switch2_valid &&
           !cond.variable_valid && !cond.self_switch_valid        # 第一页无条件
          result = :block if skip_event_lock_player?(page.list)
        end
      end
    end
  rescue StandardError
    result = :allow
  end
  $skip_event_class_cache[key] = result
end

# 锁玩家特征: 对话 / 按键输入 / 作用于玩家的移动路线 / 长等待(>5帧)
def skip_event_lock_player?(list)
  wait = 0
  (list || []).each do |c|
    next unless c
    case c.code
    when 101 then return true   # 对话(锁玩家)
    when 105 then return true   # 按键输入(等待玩家)
    when 106 then wait += 1     # 等待(演出节奏)
    when 209, 212
      p = c.parameters
      return true if p.is_a?(Array) && p[0].to_i == -1  # 玩家移动路线
    end
  end
  wait > 5
end

# 当前解释器是否在跑 map1 ev1 (开场总控部分执行判断)
def skip_event_is_map1_ev1?
  $game_map && $game_map.map_id.to_i == 1 && @event_id.to_i == 1
end

# --- 补丁 1: 阻止 autorun 演出事件 (block 模式) ---
# trigger==3(autorun) 的锁玩家演出事件不 start, 玩家在图上自由行动。
# 玩家触发(trigger 0/1/2 的 here/there/touch)不走本方法, 天然放行。
module SkipEventAutoRunPatch
  def check_event_trigger_auto
    if skip_event_block_mode? && @trigger == 3
      mid = $game_map ? $game_map.map_id : 0
      if skip_event_classify(mid, self.id) == :block
        skip_event_trace("SE_BLOCK autorun map=#{mid} ev=#{self.id}")
        return
      end
    end
    super
  end
end

# --- 补丁 2: 阻止并行演出事件 (block 模式) ---
# 并行(trigger==4)事件在 refresh 时创建独立子解释器, 不走
# check_event_trigger_auto —— 在 update 层整体静止该事件。
module SkipEventParallelPatch
  def update
    if skip_event_block_mode? && @trigger == 4
      mid = $game_map ? $game_map.map_id : 0
      if skip_event_classify(mid, self.id) == :block
        skip_event_trace("SE_BLOCK parallel map=#{mid} ev=#{self.id}")
        return
      end
    end
    super
  end
end

# --- 补丁 3: 阻止演出类公共事件 (CE15 Instructions / CE42 Load Save) ---
# 所有公共事件路径都经 Interpreter#setup 的 common_event_name:
#   自动 trigger1(CE15) / common_event_id(CE42, real_load 设置) /
#   手动 117 调用(map1 ev1 调 CE15) —— 统一在此拦截, list 置 nil 不执行。
module SkipEventCommonEventPatch
  def setup(list, event_id, common_event_name = nil)
    if skip_event_active? && common_event_name
      name = common_event_name.to_s
      if name =~ /Instructions|Load Save/i
        skip_event_trace("SE_BLOCK_CE name=#{name} ev=#{event_id}")
        list = nil
        common_event_name = nil
      end
    end
    super(list, event_id, common_event_name)
  end
end

# --- 补丁 4: 跳过演出命令 (fast 模式全部事件; block 模式仅 map1 ev1) ---
# 跳过: 对话/选项/按键/等待/图片效果/玩家移动路线。
# 保留: 传送/开关/变量/调CE/脚本 等功能命令。
# 每帧限步 FAST_MAX_STEPS_PER_FRAME: 本帧跳满即返回 false 暂停,
# 下一帧 update 继续 —— 事件跨帧完成, real_load 的场景切换有帧间隙。
module SkipEventFastForwardPatch
  def execute_command
    if skip_event_active? && @index < @list.size && @list[@index]
      code = @list[@index].code
      if skip_event_fast_this_event?
        if skip_event_skip_code?(code)
          frame = Graphics.frame_count
          if @skip_fast_frame != frame
            @skip_fast_frame = frame
            @skip_fast_steps = 0
          end
          @skip_fast_steps += 1
          if @skip_fast_steps > FAST_MAX_STEPS_PER_FRAME
            return false  # 本帧限步: 暂停, 下帧重试同一条
          end
          # 105 按键输入: 模拟"已按确认键"(设参数变量非0), 防依赖按键的
          # loop 死循环(CE15 Instructions 的开场 loop 依赖变量)
          if code == 105
            var_id = @list[@index].parameters[0].to_i
            $game_variables[var_id] = 5 if var_id > 0 && $game_variables
            @button_input_variable_id = 0 if defined?(@button_input_variable_id)
          end
          if code == 241 && skip_event_is_map1_ev1?
            # map1 ev1 的开场 BGM: 有名曲目拦截 + 停止(开场音乐不播)
            b = (@list[@index].parameters[0] rescue nil)
            bname = (b.instance_variable_get(:@name) rescue '').to_s
            if bname.empty?
              skip_event_trace("SE_BGM_STOP_CMD opening idx=#{@index}")
            else
              skip_event_trace("SE_FAST c241 opening idx=#{@index} #{bname}")
              begin
                Audio.bgm_stop if Audio.respond_to?(:bgm_stop)
              rescue StandardError
              end
              return true
            end
          end
          skip_event_trace("SE_FAST c#{code} ev=#{@event_id} idx=#{@index}")
          return true
        end
      end
    end
    super
  end

  private

  # fast 模式: 所有事件跳过演出; block 模式: 仅 map1 ev1 部分执行
  # (block 模式其余演出事件已被补丁1/2阻止, 不会进入解释器)
  def skip_event_fast_this_event?
    return true if $skip_event_mode == 'fast'
    skip_event_is_map1_ev1?
  end

  # 演出命令判定
  def skip_event_skip_code?(code)
    case code
    when 101, 401, 102, 105, 106, 230, 231, 232 then true
    when 209, 212
      p = @list[@index].parameters
      p.is_a?(Array) && p[0].to_i == -1  # 仅作用于玩家的移动路线
    when 241
      skip_event_is_map1_ev1?  # BGM 仅在开场总控内拦截
    else
      false
    end
  end
end

# --- 补丁 5: 读档后终止事件流 (铁律) ---
# real_load 完成(读档恢复状态 + $scene = Scene_Map.new)后立即清空主
# 事件解释器: 若存档快照带着运行中的 map1 ev1 解释器状态, 事件流会
# 从该状态继续跑到"新游戏"分支(传送 map2)覆盖读档位置 —— 清空后
# 事件流终止, 玩家停留在读档恢复的位置。同时清残留开场 CG / 停止
# 开场 BGM(读档恢复的演出不残留)。
module SkipEventRealLoadPatch
  def real_load
    result = super
    begin
      # 铁律(无条件): 读档后立即清空主解释器, 终止 map1 ev1 开场流程
      # (idx75 传送 map2)覆盖读档位置 —— 修复重启后进度丢失。
      # 此铁律不依赖 skip_event 模式, off 模式下也必须生效。
      if $game_system && $game_system.map_interpreter
        $game_system.map_interpreter.clear
        $game_system.map_interpreter.instance_variable_set(:@list, nil)
        skip_event_trace('SE_CLEAR_AFTER_REAL_LOAD')
      end
      skip_event_clear_cg_pictures('SE_CLEAR_AFTER_LOAD') if $game_screen
      if skip_event_active? && Audio.respond_to?(:bgm_stop)
        Audio.bgm_stop
        skip_event_trace('SE_STOP_BGM_AFTER_LOAD')
      end
    rescue StandardError
    end
    result
  end
end

# --- 残留 CG 图片清除 (共享) ---
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

# --- 补丁 6: 每帧兜底 (开场 CG 残留清除 + 开场 BGM 停止) ---
module SkipEventCgCleanerPatch
  def update
    begin
      if skip_event_active?
        skip_event_clear_cg_pictures('SE_CLEAR_PIC') if $game_screen
        if $game_system && Audio.respond_to?(:bgm_stop)
          pbgm = ($game_system.playing_bgm rescue nil)
          if pbgm
            bname = (pbgm.name.to_s rescue '')
            if !bname.empty? && bname =~ /SomeplaceIKnow/i
              skip_event_trace("SE_STOP_BGM_FRAME name=#{bname}")
              Audio.bgm_stop
            end
          end
        end
      end
    rescue StandardError
    end
    super
  end
end

# --- 挂载补丁 ---
PatchHelper.install('Game_Event', methods: [:check_event_trigger_auto]) do |k|
  k.prepend(SkipEventAutoRunPatch)
end

PatchHelper.install('Game_Event', methods: [:update]) do |k|
  k.prepend(SkipEventParallelPatch)
end

PatchHelper.install('Interpreter', methods: [:setup]) do |k|
  k.prepend(SkipEventCommonEventPatch)
end

PatchHelper.install('Interpreter', methods: [:execute_command]) do |k|
  k.prepend(SkipEventFastForwardPatch)
  skip_event_trace("SE_MOUNTED Interpreter#execute_command (skip_event_mode=#{$skip_event_mode})")
end

PatchHelper.install('Scene_Map', methods: [:update]) do |k|
  k.prepend(SkipEventCgCleanerPatch)
end

Object.prepend(SkipEventRealLoadPatch)

# --- 写状态文件 ---
StatusLog.write('skip_event_status.txt', [
  "skip_event loaded at = #{Time.now}",
  "skip_event_mode = #{$skip_event_mode} (off|block|fast)",
  "jump_map_free_mode = #{$jump_map_free_mode} (unified with block)",
  "block = event-level: autorun/parallel lock-player events not started; CE15/CE42 blocked; CE9 and player triggers pass",
  "fast  = command-level: skip 101/401/102/105/106/230/231/232/209(-1), keep transfer/switches/vars/CE/scripts",
  "fast_max_steps_per_frame = #{FAST_MAX_STEPS_PER_FRAME} (events finish across frames, real_load scene switch gets a frame gap)",
  "iron_rule = real_load clears map_interpreter (fixes save-load progress loss)",
  "watchdog = removed (user: unrelated to collision-stuck)"
])
