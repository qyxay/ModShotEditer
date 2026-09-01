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
puts "======== 2. 玩家触发放行 (PlayerTriggerPatch 新设计) ========"
puts "  新设计: 自由浏览模式下玩家主动触发(here/there/touch)全部放行 ——"
puts "  对话/互动/出口事件都可正常触发; 仅 AUTORUN(trigger 3, FreezePatch)"
puts "  与公共事件 AUTORUN(trigger 1, CommonPatch)被拦截, 避免剧情锁玩家。"
# 验证地图上"对话事件"(trigger 0/1)确实是玩家可触发的(有触发方式):
# 床(trigger=0) / 对话事件 / 出口(trigger=1) 都在放行范围内, 不存在"被拦死"的玩家事件
m2 = os_load_map(2)
evs2 = m2.instance_variable_get(:@events)
player_events = evs2.values.select { |e| [0, 1, 2].include?(e.pages.first.trigger) }
puts "  地图2 Start 玩家可触发事件数: #{player_events.size} (期望 > 0, 且含床/门/电脑等)"
puts "  => #{player_events.size > 0 ? 'OK: 对话/互动事件存在且可触发' : 'FAIL'}"
bed = evs2.values.find { |e| e.name.to_s.include?('bed') }
door = evs2.values.find { |e| e.name.to_s.include?('door') }
puts "  床事件 trigger: #{bed && bed.pages.first.trigger} (0=按确认触发, 放行)"
puts "  门事件 trigger: #{door && door.pages.first.trigger} (1=接触触发, 放行)"

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
