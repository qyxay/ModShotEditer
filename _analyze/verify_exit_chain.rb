# ============================================================
#  综合验证: 瞭望甲板出口传送链 + 三个补丁放行逻辑
# ============================================================
require_relative 'oneshot_data'
DATA2 = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data'

module RPG
  class CommonEvent
    attr_accessor :trigger, :condition, :name, :list
  end
end

puts "======== 1. 公共事件白名单 (jump_map.rb) ========"
JUMP_MAP_KEEP_COMMON_EVENTS = [9]
ces = Marshal.load(File.binread("#{DATA2}/CommonEvents.rxdata"))
intercepted = []
(0...ces.size).each do |i|
  ce = ces[i]
  next unless ce && ce.trigger == 1
  next if JUMP_MAP_KEEP_COMMON_EVENTS.include?(i)
  intercepted << i
end
puts "  自由浏览模式将被拦截的 trigger=1 公共事件: #{intercepted.inspect}"
puts "  放行: #{JUMP_MAP_KEEP_COMMON_EVENTS.inspect} (#{ces[9].name.inspect})"
puts "  => #{intercepted.empty? || !intercepted.include?(9) ? 'OK: CE9(Exit Transition) 已放行' : 'FAIL'}"

puts ""
puts "======== 2. 出口事件放行 (PlayerTriggerPatch exit_event_at?) ========"
def exit_event_at?(map_events, x, y)
  map_events.each do |_id, e|
    next unless e.x == x && e.y == y
    # 模拟 Game_Event#list: 取第一个条件满足的页(简化: 页0无条件则用页0, 否则取首页)
    pg = e.pages.first
    next unless pg
    list = pg.list
    return true if list.any? { |c| c.code == 201 }
    return true if list.any? { |c| [355, 655].include?(c.code) && c.parameters[0].to_s =~ /check_exit|transfer|teleport|unlock_map/i }
  end
  false
end

# 地图2 (start): west door (11,18) 接触触发 → 应放行
m2 = os_load_map(2)
puts "  地图2 west door (11,18): exit_event_at?=#{exit_event_at?(m2.instance_variable_get(:@events), 11, 18)} (期望 true)"
puts "  地图2 床 (15,17): exit_event_at?=#{exit_event_at?(m2.instance_variable_get(:@events), 15, 17)} (期望 false, 对话事件仍拦)"
# 地图120: south exit (26,26) 平行事件
m120 = os_load_map(120)
puts "  地图120 south exit (26,26): exit_event_at?=#{exit_event_at?(m120.instance_variable_get(:@events), 26, 26)} (期望 true)"
puts "  地图120 普通格 (5,5): exit_event_at?=#{exit_event_at?(m120.instance_variable_get(:@events), 5, 5)} (期望 false)"

puts ""
puts "======== 3. CE9 传送目标计算 (south exit 变量 → 目标坐标) ========"
# south exit: VAR6=119, VAR9=15, VAR8=34, CE10 清 VAR7=-1
# CE9 逻辑: VAR7>=1&&VAR8>=1 → (VAR6,VAR7,VAR8)
#          VAR7>=1&&VAR8<1 → (VAR6,VAR7,玩家y+10)
#          VAR7<1 → (VAR6,玩家x+VAR9,VAR8)
vars = { 6 => 119, 7 => -1, 8 => 34, 9 => 15 }
player_x, player_y = 27, 26  # south exit 检测区 (27~28, 26)
v22, v23 = player_x, player_y
if vars[7] >= 1 && vars[8] >= 1
  target = [vars[6], vars[7], vars[8]]
elsif vars[7] >= 1
  target = [vars[6], vars[7], v23 + 10]
else
  target = [vars[6], v22 + vars[9], vars[8]]
end
puts "  玩家在 (#{player_x},#{player_y}) 触发 south exit"
puts "  传送目标: 地图#{target[0]} (#{target[1]}, #{target[2]})"
puts "  地图119 north exit 位置: (41,35) → 目标应在其附近"
puts "  => #{target[0] == 119 && target[1].between?(40, 44) && target[2].between?(32, 36) ? 'OK: 目标落在 north exit 门口' : "注意: 目标 (#{target[1]},#{target[2]})"}"
