# ============================================================
#  扫描: 所有可跳地图的落点, 检查同格/相邻是否有会触发的故事件
# ============================================================

$LOAD_PATH.unshift('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/runtime/lib/ruby/3.1.0')
require 'json'

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

TRIG = {0=>'here',1=>'touch',2=>'touch2',3=>'autorun',4=>'parallel'}

def load_map_events(mid)
  path = format('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data/Map%03d.rxdata', mid)
  map = Marshal.load(File.binread(path))
  map.instance_variable_get(:@events)
end

# 事件当前有效页 trigger (全 false/0 默认状态下, 只取无条件页)
def effective_trigger(ev)
  pages = ev.instance_variable_get(:@pages)
  pages.reverse.each do |pg|
    c = pg.instance_variable_get(:@condition)
    cond_ok = !c.instance_variable_get(:@switch1_valid) &&
              !c.instance_variable_get(:@switch2_valid) &&
              !c.instance_variable_get(:@variable_valid) &&
              !c.instance_variable_get(:@self_switch_valid)
    if cond_ok
      return pg.instance_variable_get(:@trigger)
    end
  end
  nil  # 所有页都有条件, 默认状态下无有效页
end

d = JSON.parse(File.read('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/mods/mod/jump_points.json'))
FILTER = /IGNORE|DEBUG|INTERNAL|UNUSED|\bTEST\b|^INIT\b|TELEPORT|DEMO|PROTOWALK|PSHOT/i
NAME_PAT = /^[TCS]\d+$/i

cands = []
d.each do |id, m|
  next unless m.is_a?(Hash)
  x = m['x'].to_i; y = m['y'].to_i
  next if x < 0 || y < 0
  name = m['name'].to_s
  next if name =~ FILTER
  next if name =~ NAME_PAT
  cands << { id: id.to_i, x: x, y: y, dir: m['dir'].to_i, name: name }
end
cands.sort_by! { |c| c[:id] }

puts "可跳地图 #{cands.size} 个"
puts ""
bad = 0
cands.each do |c|
  evs = load_map_events(c[:id])
  hits = []
  evs.each do |eid, ev|
    ex = ev.instance_variable_get(:@x)
    ey = ev.instance_variable_get(:@y)
    name = ev.instance_variable_get(:@name)
    t = effective_trigger(ev)
    next if t.nil?
    # 落点同格
    if ex == c[:x] && ey == c[:y]
      hits << "同格:#{name}(##{eid},#{TRIG[t]})"
    end
  end
  if hits.any?
    bad += 1
    puts "地图#{c[:id]} '#{c[:name]}' 落点(#{c[:x]},#{c[:y]}) ← #{hits.join(' ')}"
  end
end
puts ""
puts "落点同格有触发事件的地图数: #{bad}"
