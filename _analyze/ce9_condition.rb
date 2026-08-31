require_relative 'oneshot_data'

module RPG
  class CommonEvent
    attr_accessor :trigger, :condition, :list
  end
  class CommonEvent::Condition
    attr_accessor :switch1_valid, :switch1_id, :switch2_valid, :switch2_id,
                  :variable_valid, :variable_id, :variable_value,
                  :self_switch_valid, :self_switch_ch
  end
end

DATA2 = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data'
ces = Marshal.load(File.binread("#{DATA2}/CommonEvents.rxdata"))

# 所有 trigger==1 的公共事件 + 条件
puts "===== 所有 trigger=1 公共事件 + 条件 ====="
ces.each_with_index do |ce, i|
  next unless ce && ce.trigger == 1
  c = ce.condition
  conds = []
  conds << "SW#{c.switch1_id}" if c && c.switch1_valid
  conds << "SW#{c.switch2_id}" if c && c.switch2_valid
  conds << "VAR#{c.variable_id}>=#{c.variable_value}" if c && c.variable_valid
  conds << "SS#{c.self_switch_ch}" if c && c.self_switch_valid
  puts "  公共事件##{i} 条件=[#{conds.join(',')}]"
end

# 地图119 north exit 完整命令
puts ""
puts "===== 地图119 north exit(#3) + south exit(#?) 完整 ====="
m119 = os_load_map(119)
m119.instance_variable_get(:@events).each do |id, ev|
  next unless ev.name =~ /exit/i
  puts "  ##{id} '#{ev.name}' @(#{ev.x},#{ev.y}) 触发=#{ev.pages[0].trigger}"
  ev.pages[0].list.each do |cmd|
    c = cmd.code
    p = cmd.parameters
    next if c == 0
    case c
    when 355, 655 then puts "    脚本: #{p.inspect}"
    when 122 then puts "    设变量 #{p.inspect}"
    when 111 then puts "    条件分支 #{p.inspect}"
    when 117 then puts "    调公共事件 #{p.inspect}"
    when 201 then puts "    传送 #{p.inspect}"
    when 121 then puts "    控制开关 #{p.inspect}"
    when 123 then puts "    自开关 #{p.inspect}"
    else puts "    code=#{c} #{p.inspect}"
    end
  end
end
