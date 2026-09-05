ROOT = File.expand_path('..', __dir__)
# ============================================================
#  临时分析: 对比三张 Livingroom 地图 (4/64/182)
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

TRIGGER = {0=>'事件开始',1=>'接触主角',2=>'接触事件',3=>'AUTORUN',4=>'PARALLEL'}

MAPS = {
  4   => [21, 10, 'Livingroom(地图4) 落点(21,10)'],
  64  => [0, 0,  'Livingroom(地图64) 落点(0,0)'],
  182 => [16, 13, 'Livingroom(地图182) 落点(16,13)']
}

MAPS.each do |mid, (sx, sy, label)|
  path = format("#{ROOT}/OneShot/Data/Map%03d.rxdata", mid)
  map = Marshal.load(File.binread(path))
  w = map.instance_variable_get(:@width)
  h = map.instance_variable_get(:@height)
  puts "=" * 60
  puts "## #{label}  尺寸 #{w}x#{h}"
  events = map.instance_variable_get(:@events)
  puts "事件总数: #{events.size}"
  events.each do |id, ev|
    name = ev.instance_variable_get(:@name)
    x = ev.instance_variable_get(:@x)
    y = ev.instance_variable_get(:@y)
    pages = ev.instance_variable_get(:@pages)
    triggers = []
    autocond = []
    near = (x-sx).abs <= 2 && (y-sy).abs <= 2
    pages.each do |pg|
      trig = pg.instance_variable_get(:@trigger)
      cond = pg.instance_variable_get(:@condition)
      triggers << TRIGGER[trig] || trig.to_s
      cstr = []
      cstr << "SW1=#{cond.instance_variable_get(:@switch1_id)}" if cond.instance_variable_get(:@switch1_valid)
      cstr << "SW2=#{cond.instance_variable_get(:@switch2_id)}" if cond.instance_variable_get(:@switch2_valid)
      cstr << "SELF=#{cond.instance_variable_get(:@self_switch_ch)}" if cond.instance_variable_get(:@self_switch_valid)
      cstr << "VAR" if cond.instance_variable_get(:@variable_valid)
      autocond << cstr.join(',') unless cstr.empty?
    end
    marker = near ? "  <<< 距落点(#{sx},#{sy})<=2格" : ""
    puts "  #%3d '%s' @(%2d,%2d) 触发=[%s]%s%s" % [id, name, x, y, triggers.uniq.join('/'), autocond.empty? ? '' : " 条件=#{autocond.join(';')}", marker]
  end
  puts ""
end
