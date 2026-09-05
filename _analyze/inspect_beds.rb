ROOT = File.expand_path('..', __dir__)
# ============================================================
#  分析: 地图2 落点同格事件 bed bottom right (#4) 命令
# ============================================================

$LOAD_PATH.unshift("#{ROOT}/runtime/lib/ruby/3.1.0")
$LOAD_PATH.unshift("#{ROOT}/runtime/lib/ruby/3.1.0/x64-mingw64")

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

path = "#{ROOT}/OneShot/Data/Map002.rxdata"
map = Marshal.load(File.binread(path))
evs = map.instance_variable_get(:@events)

[4, 3, 2, 1].each do |id|
  ev = evs[id]
  next unless ev
  name = ev.instance_variable_get(:@name)
  x = ev.instance_variable_get(:@x); y = ev.instance_variable_get(:@y)
  puts "==== 地图2 ##{id} '#{name}' @(#{x},#{y}) ===="
  ev.instance_variable_get(:@pages).each_with_index do |pg, pi|
    trig = pg.instance_variable_get(:@trigger)
    c = pg.instance_variable_get(:@condition)
    cond = []
    cond << "SW1=#{c.instance_variable_get(:@switch1_id)}" if c.instance_variable_get(:@switch1_valid)
    cond << "SW2=#{c.instance_variable_get(:@switch2_id)}" if c.instance_variable_get(:@switch2_valid)
    cond << "VAR#{c.instance_variable_get(:@variable_id)}>=#{c.instance_variable_get(:@variable_value)}" if c.instance_variable_get(:@variable_valid)
    cond << "SELF=#{c.instance_variable_get(:@self_switch_ch)}" if c.instance_variable_get(:@self_switch_valid)
    puts "--- 页#{pi} 触发#{trig} 条件[#{cond.join(',')}] ---"
    (pg.instance_variable_get(:@list) || []).each_with_index do |cmd, idx|
      code = cmd.instance_variable_get(:@code)
      p = cmd.instance_variable_get(:@parameters)
      case code
      when 101, 401 then puts "  #{idx} [#{code}] #{p[0].to_s[0,50]}"
      when 111 then puts "  #{idx} [111] 分支 op=#{p[0]} #{p[1..].inspect}"
      when 411, 412 then puts "  #{idx} [#{code}]"
      when 106 then puts "  #{idx} [106] wait#{p[0]}"
      when 122 then puts "  #{idx} [122] var #{p[0].inspect}"
      when 0 then puts "  #{idx} [0] end"
      else puts "  #{idx} [#{code}]"
      end
    end
  end
end
