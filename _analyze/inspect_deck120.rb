# ============================================================
#  地图120 传送机制分析: mark/Map Events/south exit/FAST TRAVEL
# ============================================================

require_relative 'oneshot_data'

map = os_load_map(120)
evs = map.instance_variable_get(:@events)

[16, 2, 13, 14, 5, 4, 6, 1, 7, 8, 9, 10, 11, 3, 12].each do |id|
  ev = evs[id]
  next unless ev
  puts "===== 地图120 ##{id} '#{ev.name}' @(#{ev.x},#{ev.y}) ====="
  ev.pages.each_with_index do |pg, pi|
    c = pg.condition
    conds = []
    conds << "SW#{c.switch1_id}" if c.switch1_valid
    conds << "SW#{c.switch2_id}" if c.switch2_valid
    conds << "VAR#{c.variable_id}>=#{c.variable_value}" if c.variable_valid
    conds << "SS#{c.self_switch_ch}" if c.self_switch_valid
    puts "--- 页#{pi} 触发=#{pg.trigger} 条件=[#{conds.join(',')}]"
    pg.list.each_with_index do |cmd, ci|
      code = cmd.code
      p = cmd.parameters
      case code
      when 122 then puts "  [#{ci}] 设置变量 params=#{p.inspect}"
      when 111 then puts "  [#{ci}] 条件分支 params=#{p.inspect}"
      when 121 then puts "  [#{ci}] 控制开关 params=#{p.inspect}"
      when 201 then puts "  [#{ci}] 传送 params=#{p.inspect}"
      when 101 then puts "  [#{ci}] 对话 params=#{p.inspect}"
      when 209, 205 then puts "  [#{ci}] 移动路线 params=#{p.inspect}"
      when 108, 408 then puts "  [#{ci}] 注释: #{p.inspect}"
      when 355, 655 then puts "  [#{ci}] 脚本: #{p.inspect}"
      else
        puts "  [#{ci}] code=#{code} params=#{p.inspect}" if code != 0
      end
    end
  end
end
