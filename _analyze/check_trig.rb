# 查看地图事件的 trigger / 页面属性 (判断转移点类型)
class Table
  def initialize(x, y = 1, z = 1); @x_size, @y_size, @z_size = x, y, z; @data = Array.new(x * y * z, 0); end
  def [](x, y = 0, z = 0); @data[x + y * @x_size + z * @x_size * @y_size]; end
  def self._load(s)
    dim, xsize, ysize, zsize, size = s[0, 20].unpack('LLLLL')
    t = new(xsize, ysize, zsize); t.instance_variable_set(:@data, s[20, size * 2].unpack('S*')); t
  end
end
module RPG
  class MapInfo; attr_accessor :name, :parent_id; end
  class Map; attr_accessor :width, :height, :data, :events, :tileset_id; end
  class Event; attr_accessor :id, :x, :y, :name, :pages; end
  class Event::Page; attr_accessor :x, :y, :condition, :list, :graphic, :trigger, :priority_type, :move_type; end
  class Event::Page::Condition; end
  class Event::Page::Graphic; attr_accessor :tile_id, :character_name; end
  class EventCommand; attr_accessor :code, :parameters, :indent; end
  class MoveRoute; end
  class MoveCommand; end
  class Tileset; attr_accessor :passages, :priorities; end
  class CommonEvent; end
  class Actor; end
  class Skill; end
  class Item; end
  class Weapon; end
  class Armor; end
  class Enemy; end
  class Troop; end
  class Troop::Page; end
  class Troop::Page::Condition; end
  class State; end
  class Animation; end
  class Animation::Frame; end
  class Animation::Timing; end
  class System; end
  class System::Words; end
  class AudioFile; end
  class Switch; end
  class Variable; end
end
def load_data(path); File.open(path, 'rb') { |f| Marshal.load(f) }; end

infos = load_data('Data/MapInfos.rxdata')
[225, 120, 23, 64].each do |id|
  map = load_data(sprintf('Data/Map%03d.rxdata', id))
  puts "=== Map #{id} #{infos[id].name.inspect} ==="
  map.events.each do |eid, ev|
    pg = ev.pages.last
    next unless pg
    trig = pg.respond_to?(:trigger) ? pg.trigger : '?'
    # 检测事件是否含转移指令(108 = 场所移动)
    has_transfer = pg.list.any? { |c| c && [108, 201, 202].include?(c.code) }
    onground = pg.respond_to?(:below) ? pg.below : '?'
    prio = pg.respond_to?(:priority_type) ? pg.priority_type : '?'
    puts "  ev#{eid} #{ev.name.inspect} @(#{ev.x},#{ev.y}) trigger=#{trig} transfer=#{has_transfer} priority=#{prio}"
  end
end
