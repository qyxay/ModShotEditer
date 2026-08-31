# ============================================================
#  临时分析: 门事件传送目标 + 目标地图 AUTORUN 的变量条件
# ============================================================

$LOAD_PATH.unshift('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/runtime/lib/ruby/3.1.0')
$LOAD_PATH.unshift('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/runtime/lib/ruby/3.1.0/x64-mingw64')

module RPG
  class Map; end
  class Event; end
  class EventCommand; end
  class Tileset; end
  class AudioFile; end
  class MoveRoute; end
  class MoveCommand; end
  class Event
    class Page; end
    class Page::Condition; end
    class Page::Graphic; end
  end
end
class Table; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end
class Color; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end
class Tone; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end
class Rect; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end

def dump_map(mid)
  path = format('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data/Map%03d.rxdata', mid)
  map = Marshal.load(File.binread(path))
  map.instance_variable_get(:@events)
end

# 打印事件命令概要 (101文本/201传送/355脚本/117公共事件/121开关/123自开关/122变量)
def summarize_commands(ev, mid, max=12)
  pages = ev.instance_variable_get(:@pages)
  out = []
  pages.each_with_index do |pg, pi|
    trig = pg.instance_variable_get(:@trigger)
    cond = pg.instance_variable_get(:@condition)
    cond_s = []
    cond_s << "SW1=#{cond.instance_variable_get(:@switch1_id)}" if cond.instance_variable_get(:@switch1_valid)
    cond_s << "SW2=#{cond.instance_variable_get(:@switch2_id)}" if cond.instance_variable_get(:@switch2_valid)
    cond_s << "VAR" if cond.instance_variable_get(:@variable_valid)
    cond_s << "SELF=#{cond.instance_variable_get(:@self_switch_ch)}" if cond.instance_variable_get(:@self_switch_valid)
    cmds = []
    list = pg.instance_variable_get(:@list) || []
    list.each do |c|
      code = c.instance_variable_get(:@code)
      p = c.instance_variable_get(:@parameters)
      case code
      when 101 then cmds << "101[#{p[0].to_s[0,30]}]"
      when 401 then cmds << "401[#{p[0].to_s[0,20]}]"
      when 201 then cmds << "201(传送→地图#{p[0]},#{p[1]},#{p[2]})"
      when 355, 655 then cmds << "#{code}[#{p[0].to_s[0,50]}]"
      when 117 then cmds << "117(公共事件#{p[0]})"
      when 121 then cmds << "121(开关#{p[0]}=#{p[1]})"
      when 123 then cmds << "123(自开关#{p[0]})"
      when 122 then cmds << "122(变量)"
      when 111 then cmds << "111(分支#{p[0]})"
      end
    end
    out << "  [页#{pi} 触发#{trig} 条件#{cond_s.join(',')}] #{cmds.first(max).join(' ')}"
  end
  out
end

# 地图4 的门事件
puts "### 地图4 门/关键事件命令 ###"
evs4 = dump_map(4)
[1, 2, 3, 15, 8].each do |id|
  ev = evs4[id]
  next unless ev
  puts "事件##{id} '#{ev.instance_variable_get(:@name)}' @(#{ev.instance_variable_get(:@x)},#{ev.instance_variable_get(:@y)})"
  summarize_commands(ev, 4).each { |l| puts l }
end
puts ""

# 地图4 niko hello
puts "### 地图4 niko hello ###"
niko = evs4[17]
puts summarize_commands(niko, 4) if niko
puts ""

# 地图2 intro / Map Events 的 VAR 条件详情
puts "### 地图2 intro / Map Events VAR 条件 ###"
evs2 = dump_map(2)
[7, 13].each do |id|
  ev = evs2[id]
  next unless ev
  pages = ev.instance_variable_get(:@pages)
  puts "事件##{id} '#{ev.instance_variable_get(:@name)}'"
  pages.each_with_index do |pg, pi|
    trig = pg.instance_variable_get(:@trigger)
    cond = pg.instance_variable_get(:@condition)
    puts "  页#{pi} 触发#{trig} var_valid=#{cond.instance_variable_get(:@variable_valid)} var_id=#{cond.instance_variable_get(:@variable_id)} var_val=#{cond.instance_variable_get(:@variable_value)} sw1=#{cond.instance_variable_get(:@switch1_id)}/#{cond.instance_variable_get(:@switch1_valid)} sw2=#{cond.instance_variable_get(:@switch2_id)}/#{cond.instance_variable_get(:@switch2_valid)} self=#{cond.instance_variable_get(:@self_switch_ch)}/#{cond.instance_variable_get(:@self_switch_valid)}"
  end
end
puts ""

# 地图182 west door 传送目标
puts "### 地图182 west door ###"
evs182 = dump_map(182)
[3, 9].each do |id|
  ev = evs182[id]
  next unless ev
  puts "事件##{id} '#{ev.instance_variable_get(:@name)}' @(#{ev.instance_variable_get(:@x)},#{ev.instance_variable_get(:@y)})"
  summarize_commands(ev, 182).each { |l| puts l }
end
puts ""

# 地图64 无事件 (空图)
puts "### 地图64 ###"
evs64 = dump_map(64)
puts "事件数: #{evs64.size}"
