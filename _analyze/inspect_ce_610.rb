# ============================================================
#  公共事件 6/10 (south exit 传送链) + 其他传送相关公共事件
# ============================================================

require_relative 'oneshot_data'

module RPG
  class CommonEvent
    attr_accessor :trigger, :condition, :list
  end
  class CommonEvent::Condition
    attr_accessor :switch1_valid, :switch1_id
  end
end
DATA2 = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data'
ces = Marshal.load(File.binread("#{DATA2}/CommonEvents.rxdata"))

[6, 10].each do |id|
  ce = ces[id]
  next unless ce
  cond = ce.condition
  cond_sw = (cond && cond.switch1_valid) ? cond.switch1_id : nil
  puts "===== 公共事件 ##{id} trigger=#{ce.trigger} 条件SW=#{cond_sw} ====="
  ce.list.each_with_index do |cmd, ci|
    code = cmd.code
    p = cmd.parameters
    case code
    when 122 then puts "  [#{ci}] 设置变量 #{p.inspect}"
    when 121 then puts "  [#{ci}] 控制开关 #{p.inspect}"
    when 111 then puts "  [#{ci}] 条件分支 #{p.inspect}"
    when 117 then puts "  [#{ci}] 调用公共事件 #{p.inspect}"
    when 201 then puts "  [#{ci}] 传送 #{p.inspect}"
    when 101 then puts "  [#{ci}] 对话 #{p.inspect}"
    when 355, 655 then puts "  [#{ci}] 脚本: #{p.inspect}"
    when 230, 250, 231, 232 then puts "  [#{ci}] code=#{code} #{p.inspect}"
    else
      puts "  [#{ci}] code=#{code} #{p.inspect}" if code != 0
    end
  end
end
