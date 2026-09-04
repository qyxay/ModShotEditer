# ============================================================
#  jump_map_free.rb — Jump Map "自由浏览模式" 冻结补丁
#
#  跳到某地图后进入自由浏览模式, 玩家在该模式下完全自由:
#    1) 冻结所有地图的 autorun(trigger 3) 事件 —— 防止剧情 AUTORUN 锁玩家
#    2) 拦截 autorun 公共事件(trigger 1) —— 该路径绕过 Game_Event 冻结
#    3) 玩家触发 here/there/touch 一律放行 —— 跳转后能正常对话/互动
#  自由浏览模式持续到游戏重启; 重启后恢复正常剧情。
#
#  纯 preload 实现, 不修改游戏原始文件。
#  用 TracePoint(:end) 监听 Game_Event / Interpreter / Game_Player
#  类定义, 就绪后用 Module#prepend 打补丁。
#
#  依赖:
#    jump_map.rb 提供 Window_JumpMap(传送成功时置 $jump_map_free_mode = true)
# ============================================================

# --- 跳转后"自由浏览模式" ---
# 是否开启自由浏览模式冻结
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

# --- 等待 Game_Event 类定义完成后 prepend 补丁 ---
PatchHelper.install('Game_Event', methods: [:check_event_trigger_auto]) do |k|
  k.prepend(JumpMapFreezePatch)
end

# --- 等待 Interpreter 类定义完成后 prepend 补丁 ---
PatchHelper.install('Interpreter', methods: [:setup_starting_event]) do |k|
  k.prepend(JumpMapCommonEventPatch)
end

# --- 等待 Game_Player 类定义完成后 prepend 补丁 ---
PatchHelper.install('Game_Player', methods: [:check_event_trigger_here]) do |k|
  k.prepend(JumpMapPlayerTriggerPatch)
end

# --- 写状态文件 ---
StatusLog.write('jump_map_free_status.txt', [
  "jump_map_free loaded at = #{Time.now}",
  "freeze_autorun = #{JUMP_MAP_FREEZE_AUTORUN}",
  "keep_common_events = #{JUMP_MAP_KEEP_COMMON_EVENTS.inspect} (Exit Transition 出口传送)",
  "patches = Game_Event#check_event_trigger_auto / Interpreter#setup_starting_event / Game_Player#check_event_trigger_*",
  "mode = $jump_map_free_mode persists until game restart"
])
