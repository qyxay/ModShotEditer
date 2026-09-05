ROOT = File.expand_path('..', __dir__)
# ============================================================
#  临时分析: 地图2 intro / Map Events 完整命令
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

def load_map(mid)
  path = format("#{ROOT}/OneShot/Data/Map%03d.rxdata", mid)
  Marshal.load(File.binread(path)).instance_variable_get(:@events)
end

def dump_event(ev, label)
  pages = ev.instance_variable_get(:@pages)
  puts "==== #{label} ===="
  pages.each_with_index do |pg, pi|
    trig = pg.instance_variable_get(:@trigger)
    puts "--- 页#{pi} 触发#{trig} ---"
    list = pg.instance_variable_get(:@list) || []
    list.each_with_index do |c, idx|
      code = c.instance_variable_get(:@code)
      p = c.instance_variable_get(:@parameters)
      case code
      when 101, 401
        puts "  #{idx} [#{code}] #{p[0].to_s[0,60]}"
      when 355, 655
        puts "  #{idx} [#{code}] #{p[0].to_s[0,60]}"
      when 111
        puts "  #{idx} [111] 分支 op=#{p[0]} p=#{p[1..].inspect}"
      when 411, 412
        puts "  #{idx} [#{code}]"
      when 117
        puts "  #{idx} [117] 公共事件 #{p[0]}"
      when 121
        puts "  #{idx} [121] 开关 #{p[0]}=#{p[1]}"
      when 123
        puts "  #{idx} [123] 自开关 #{p[0]}"
      when 122
        puts "  #{idx} [122] 变量 #{p[0].inspect}"
      when 106
        puts "  #{idx} [106] 等待 #{p[0]}"
      when 250
        puts "  #{idx} [250] SE #{p[0].name rescue p[0]}"
      when 0
        puts "  #{idx} [0] 结束"
      else
        puts "  #{idx} [#{code}]"
      end
    end
  end
end

evs2 = load_map(2)
dump_event(evs2[7], '地图2 #7 intro')
puts ""
dump_event(evs2[13], '地图2 #13 Map Events')
