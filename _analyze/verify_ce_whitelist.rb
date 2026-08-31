# 简化验证: 模拟 JumpMapCommonEventPatch 的核心逻辑
JUMP_MAP_KEEP_COMMON_EVENTS = [9]

# 模拟 $data_common_events: 索引 1,2,9,15,40 是 trigger=1
$data_common_events = (0..40).map do |i|
  obj = Struct.new(:trigger, :name).new(0, "ce#{i}")
  obj.trigger = 1 if [1, 2, 9, 15, 40].include?(i)
  obj.name = "Exit Transition" if i == 9
  obj
end

# --- 复制 patch 的拦截逻辑 ---
def simulate_patch(free_mode)
  saved = []
  if free_mode
    $data_common_events.each_with_index do |ce, i|
      if ce && ce.trigger == 1 && !JUMP_MAP_KEEP_COMMON_EVENTS.include?(i)
        saved << [i, ce]
        ce.trigger = 0
      end
    end
  end
  # 拦截后: 哪些还保持 trigger=1 (即放行的)
  kept = (0..40).select { |i| $data_common_events[i].trigger == 1 }
  # 恢复
  saved.each { |_i, ce| ce.trigger = 1 }
  kept
end

puts "=== 自由浏览模式: 拦截后仍 trigger=1 的公共事件 ==="
kept = simulate_patch(true)
puts "  放行的: #{kept.inspect}"
puts "  期望:   [9] (仅 Exit Transition)"

puts ""
puts "=== 非自由浏览模式: 不拦截 ==="
kept2 = simulate_patch(false)
puts "  所有 trigger=1 保持: #{kept2.inspect}"
puts "  期望: [1, 2, 9, 15, 40]"

# 校验
pass = (kept == [9]) && (kept2 == [1, 2, 9, 15, 40])
puts ""
puts pass ? "PASS: 白名单逻辑正确" : "FAIL: 逻辑错误"
