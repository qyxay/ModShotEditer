ROOT = File.expand_path('..', __dir__)
require_relative 'oneshot_data'

module RPG
  class CommonEvent
    attr_accessor :trigger, :condition, :list
  end
  class CommonEvent::Condition
    attr_accessor :switch1_valid, :switch1_id, :variable_valid, :variable_id, :variable_value, :self_switch_valid, :self_switch_ch
  end
end

DATA2 = "#{ROOT}/OneShot/Data"
ces = Marshal.load(File.binread("#{DATA2}/CommonEvents.rxdata"))
ce = ces[9]
puts "===== 公共事件#9 完整命令 trigger=#{ce.trigger} ====="
ce.list.each_with_index do |cmd, ci|
  c = cmd.code
  p = cmd.parameters
  case c
  when 111 then puts "  [#{ci}] 条件分支 #{p.inspect}"
  when 411 then puts "  [#{ci}] else"
  when 412 then puts "  [#{ci}] endif"
  when 122 then puts "  [#{ci}] 设变量 #{p.inspect}"
  when 201 then puts "  [#{ci}] 传送 #{p.inspect}"
  when 117 then puts "  [#{ci}] 调公共事件 #{p.inspect}"
  when 121 then puts "  [#{ci}] 控制开关 #{p.inspect}"
  when 355, 655 then puts "  [#{ci}] 脚本: #{p.inspect}"
  when 0 then nil
  else puts "  [#{ci}] code=#{c} #{p.inspect}"
  end
end

puts ""
puts "===== 所有地图: 设置变量6/7/9 的事件 ====="
Dir.glob("#{DATA2}/Map*.rxdata").each do |f|
  mid = f[/Map(\d+)\.rxdata/, 1].to_i
  begin
    m = Marshal.load(File.binread(f))
  rescue
    next
  end
  evs = m.instance_variable_get(:@events)
  next unless evs
  evs.each_value do |ev|
    ev.pages.each_with_index do |pg, pi|
      pg.list.each do |cmd|
        if cmd.code == 122 && cmd.parameters[0] && [6,7,9].include?(cmd.parameters[0])
          target = cmd.parameters[1]
          puts "  地图#{mid} ##{ev.id} '#{ev.name}' 页#{pi} 触发=#{pg.trigger} @(#{ev.x},#{ev.y}): 设变量#{cmd.parameters[0]} = #{cmd.parameters[4,8].inspect}"
        end
      end
    end
  end
end
