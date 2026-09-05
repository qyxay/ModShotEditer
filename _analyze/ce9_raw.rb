ROOT = File.expand_path('..', __dir__)
class Tone
  def self._load(s); allocate; end
end
class Color
  def self._load(s); allocate; end
end
# raw 鍙嶅簭鍒楀寲鍏叡浜嬩欢, 绮剧‘鐪?#9 鐨?condition 缁撴瀯
class Tone
  def self._load(s); allocate; end
end
module RPG
  class AudioFile; end
  class MoveRoute; end
  class MoveCommand; end
  class EventCommand
    attr_accessor :code, :indent, :parameters
  end
  class CommonEvent
    class Condition
      attr_accessor :switch1_valid, :switch2_valid, :variable_valid, :self_switch_valid,
                    :switch1_id, :switch2_id, :variable_id, :variable_value, :self_switch_ch
      def initialize(*); end
    end
    attr_accessor :trigger, :condition, :name, :list
    def switch_id
      @condition ? @condition.switch1_id : nil
    end
  end
end

DATA2 = "#{ROOT}/OneShot/Data"
raw = File.binread("#{DATA2}/CommonEvents.rxdata")

# Marshal 鏃舵墦鍗版瘡涓璞＄殑绫诲悕 (trace)
classes = {}
loader = Proc.new do |obj|
  classes[obj.class.name] ||= 0
  classes[obj.class.name] += 1
  obj
end
$marshal_visitor = loader

# 鐢ㄦ爣鍑?Marshal.load
ces = Marshal.load(raw)

puts "===== 鍏叡浜嬩欢 #9 condition ====="
ce9 = ces[9]
c = ce9.condition
puts "condition class: #{c ? c.class.name : 'nil'}"
if c
  puts "switch1_valid=#{c.switch1_valid} switch1_id=#{c.switch1_id}"
  puts "switch2_valid=#{c.switch2_valid} switch2_id=#{c.switch2_id}"
  puts "variable_valid=#{c.variable_valid} variable_id=#{c.variable_id} value=#{c.variable_value}"
  puts "self_switch_valid=#{c.self_switch_valid} ch=#{c.self_switch_ch}"
end
puts "CommonEvent#switch_id => #{ce9.switch_id.inspect}"
puts "trigger=#{ce9.trigger} name=#{ce9.name.inspect}"

puts ""
puts "===== 鍏ㄩ儴 trigger=1 鍏叡浜嬩欢鐨?condition ====="
ces.each_with_index do |ce, i|
  next unless ce && ce.trigger == 1
  cc = ce.condition
  desc = cc ? "valid=#{cc.switch1_valid} id=#{cc.switch1_id}" : "nil"
  puts "  ##{i} '#{ce.name}' switch_id=#{ce.switch_id.inspect} condition=#{desc}"
end


