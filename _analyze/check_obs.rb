# RGSS1 (RMXP) Table 解码 + 分析 observation deck 落点
# 顶层 Table (mkxp/RGSS 使用顶层 Table 存地图数据)
class Table
  def initialize(x, y = 1, z = 1)
    @dim = 1 + (y > 1 ? 1 : 0) + (z > 1 ? 1 : 0)
    @x_size, @y_size, @z_size = x, y, z
    @data = Array.new(x * y * z, 0)
  end
  def [](x, y = 0, z = 0)
    @data[x + y * @x_size + z * @x_size * @y_size]
  end
  def []=(x, y = 0, z = 0, v)
    @data[x + y * @x_size + z * @x_size * @y_size] = v
  end
  def xsize; @x_size; end
  def ysize; @y_size; end
  def zsize; @z_size; end
  def self._load(s)
    dim, xsize, ysize, zsize, size = s[0, 20].unpack('LLLLL')
    data = s[20, size * 2].unpack('S*')
    table = new(xsize, ysize, zsize)
    table.instance_variable_set(:@data, data)
    table
  end
  def _dump(depth)
    [@dim, @x_size, @y_size, @z_size, @x_size * @y_size * @z_size].pack('LLLLL') +
      @data.pack('S*')
  end
end

module RPG
  class MapInfo; attr_accessor :name, :parent_id, :order; end
  class Map; attr_accessor :width, :height, :data, :events; end
  class Event; attr_accessor :id, :name, :pages; end
  class Event::Page; attr_accessor :x, :y, :condition, :list; end
  class Event::Page::Condition; end
  class Event::Page::Graphic; end
  class EventCommand; end
  class MoveRoute; end
  class MoveCommand; end
  class Tileset; end
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

def load_data(path)
  File.open(path, 'rb') { |f| Marshal.load(f) }
end

infos = load_data('Data/MapInfos.rxdata')
puts "MapInfos loaded: #{infos.size} entries"
[120, 225, 23, 110].each do |id|
  info = infos[id]
  puts "#{id}: name=#{info.name.inspect} parent=#{info.parent_id}" if info
end

# 检查 120/225 observation deck
[120, 225].each do |id|
  map = load_data(sprintf('Data/Map%03d.rxdata', id))
  w = map.width; h = map.height
  puts "=== Map #{id} (#{infos[id].name.inspect}) #{w}x#{h} ==="
  # 显示 y=14..20 每行的可通行格(0层数据为 0 表示该格无地图块 = 可通行基础)
  (12..22).each do |yy|
    empty = []
    (0...w).each { |xx| empty << xx if map.data[xx, yy, 0] == 0 }
    next if empty.empty?
    # 压缩显示连续段
    seg = []
    empty.each do |xx|
      if seg.empty? || xx == seg.last[:e] + 1
        seg << { s: xx, e: xx } if seg.empty?
        seg.last[:e] = xx
      else
        seg << { s: xx, e: xx }
      end
    end
    desc = seg.map { |g| "#{g[:s]}-#{g[:e]}" }.join(',')
    puts "y=#{yy} empty_x_segments: #{desc}"
  end
  # 事件列表(可能包含阻塞/栏杆)
  if map.events
    map.events.each do |eid, ev|
      pg = ev.pages.last
      next unless pg
      puts "  event #{eid} @(#{pg.x},#{pg.y}) name=#{ev.name.inspect}"
    end
  end
end
