require_relative 'oneshot_data'

module RPG
  class CommonEvent
    attr_accessor :trigger, :condition, :list, :name
  end
  class CommonEvent::Condition
    attr_accessor :switch1_valid, :switch1_id, :switch2_valid, :switch2_id,
                  :variable_valid, :variable_id, :variable_value,
                  :self_switch_valid, :self_switch_ch
  end
end

DATA2 = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data'
ces = Marshal.load(File.binread("#{DATA2}/CommonEvents.rxdata"))

puts "===== 公共事件 #9 condition 原始对象 ====="
ce = ces[9]
c = ce.condition
puts "  trigger=#{ce.trigger} name=#{ce.name.inspect}"
p c
puts "  switch1_valid=#{c.switch1_valid} switch1_id=#{c.switch1_id}"
puts "  switch2_valid=#{c.switch2_valid} switch2_id=#{c.switch2_id}"
puts "  variable_valid=#{c.variable_valid} variable_id=#{c.variable_id} value=#{c.variable_value}"
puts "  self_switch_valid=#{c.self_switch_valid} ch=#{c.self_switch_ch}"

puts ""
puts "===== 所有公共事件 #9 的条件 (trigger=1 的5个) ====="
[1,2,9,15,40].each do |i|
  cc = ces[i].condition
  puts "  ##{i}: valid=#{cc.switch1_valid} id=#{cc.switch1_id}"
end

puts ""
puts "===== 谁调用公共事件 #9 (code 117, parameters[0]==9) ====="
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
        if cmd.code == 117 && cmd.parameters[0] == 9
          puts "  地图#{mid} ##{ev.id} '#{ev.name}' 页#{pi} 触发=#{pg.trigger}: 调用公共事件9"
        end
      end
    end
  end
end
# 公共事件之间调用
ces.each_with_index do |cce, i|
  next unless cce
  cce.list.each do |cmd|
    if cmd.code == 117 && cmd.parameters[0] == 9
      puts "  公共事件##{i}: 调用公共事件9"
    end
  end
end
