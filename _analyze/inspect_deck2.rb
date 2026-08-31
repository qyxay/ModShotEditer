# ============================================================
#  地图225 EV001/EV004 完整命令 + 相关开关语义
# ============================================================

require_relative 'oneshot_data'

map = os_load_map(225)
evs = map.instance_variable_get(:@events)

[1, 4].each do |id|
  ev = evs[id]
  puts "===== 地图225 ##{id} '#{ev.name}' @(#{ev.x},#{ev.y}) ====="
  ev.pages.each_with_index do |pg, pi|
    c = pg.condition
    puts "--- 页#{pi} 触发=#{pg.trigger} 条件=[SW#{c.switch1_id if c.switch1_valid}, SW#{c.switch2_id if c.switch2_valid}, VAR#{c.variable_id}>=#{c.variable_value} if #{c.variable_valid}, SS#{c.self_switch_ch} if #{c.self_switch_valid}]"
    pg.list.each_with_index do |cmd, ci|
      code = cmd.code
      p = cmd.parameters
      puts "  [#{ci}] code=#{code} params=#{p.inspect}"
    end
  end
end

# 全地图引用的开关
puts ""
puts "===== 地图225 全部引用的开关 ====="
sws = {}
evs.each_value do |ev|
  ev.pages.each do |pg|
    c = pg.condition
    sws[c.switch1_id] = true if c.switch1_valid
    sws[c.switch2_id] = true if c.switch2_valid
    pg.list.each do |cmd|
      if cmd.code == 111 && cmd.parameters[0] == 0
        sws[cmd.parameters[1]] = true
      end
    end
  end
end
puts sws.keys.sort.inspect
