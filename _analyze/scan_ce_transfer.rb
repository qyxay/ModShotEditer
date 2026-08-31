# ============================================================
#  扫所有公共事件: 201 传送 / 变量6/9/8 判断 / 含 117 链
# ============================================================

require_relative 'oneshot_data'

module RPG
  class CommonEvent
    attr_accessor :trigger, :condition, :list
  end
  class CommonEvent::Condition
    attr_accessor :switch1_valid, :switch1_id, :variable_valid, :variable_id, :variable_value
  end
end

DATA2 = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data'
ces = Marshal.load(File.binread("#{DATA2}/CommonEvents.rxdata"))

ces.each_with_index do |ce, i|
  next unless ce
  interesting = []
  ce.list.each do |cmd|
    c = cmd.code
    p = cmd.parameters
    if c == 201
      interesting << "201传送 map=#{p[0]} #{p[1]},#{p[2]}"
    elsif c == 111 && p[0] == 1 && [6,7,8,9].include?(p[1])
      interesting << "条件分支变量#{p[1]}=#{p.inspect}"
    elsif c == 117
      interesting << "调公共事件#{p[0]}"
    elsif c == 122 && p[0] && p[1] && [6,7,8,9].include?(p[0])
      interesting << "设变量#{p[0]}=#{p[4,8].inspect}"
    elsif c == 355 || c == 655
      interesting << "脚本:#{p[0]}"
    end
  end
  if interesting.any?
    cond = ce.condition
    conds = []
    conds << "SW#{cond.switch1_id}" if cond && cond.switch1_valid
    conds << "VAR#{cond.variable_id}>=#{cond.variable_value}" if cond && cond.variable_valid
    puts "公共事件##{i} trigger=#{ce.trigger} 条件=[#{conds.join(',')}]"
    interesting.each { |x| puts "    #{x}" }
    puts ""
  end
end
