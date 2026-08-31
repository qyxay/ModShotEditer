# ============================================================
#  精确检查: 地图2 (15,17) 及周围通行性 (含事件图形)
# ============================================================

$LOAD_PATH.unshift('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/runtime/lib/ruby/3.1.0')

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
class Table
  attr_reader :xsize, :ysize, :zsize
  def self._load(s)
    dim = s[0, 4].unpack1('V')
    sizes = dim.times.map { |i| s[4 + i * 4, 4].unpack1('V') }
    t = allocate
    t.instance_variable_set(:@xsize, sizes[0])
    t.instance_variable_set(:@ysize, sizes[1] || 1)
    t.instance_variable_set(:@zsize, sizes[2] || 1)
    t.instance_variable_set(:@data, s[4 + dim * 4..].unpack('l*'))
    t
  end
  def _dump(*); "\x00" * 4; end
  def [](x, y = 0, z = 0)
    @data[x + @xsize * y + @xsize * @ysize * z] || 0
  end
end
class Color; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end
class Tone; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end
class Rect; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end

DATA = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data'

def load_map(mid)
  Marshal.load(File.binread(format("#{DATA}/Map%03d.rxdata", mid)))
end

tilesets = Marshal.load(File.binread("#{DATA}/Tilesets.rxdata"))
tileset_passages = {}
tilesets.each_with_index do |t, i|
  next unless t
  tileset_passages[i] = t.instance_variable_get(:@passages)
end

def tile_info(map, tileset_passages, x, y)
  ts = map.instance_variable_get(:@tileset_id)
  pass = tileset_passages[ts]
  data = map.instance_variable_get(:@data)
  tiles = [data[x, y, 0], data[x, y, 1], data[x, y, 2]]
  info = tiles.map { |t| t == 0 ? '.' : "t#{t}" }
  # 每方向通行
  dir_ok = {}
  [2, 4, 6, 8].each do |d|
    ok = true
    tiles.each do |tile|
      next if tile == 0
      bits = pass ? pass[tile] : nil
      if bits
        if (bits & 0x0F) == 0x0F
          ok = false
          break
        end
        bit = { 2 => 1, 4 => 2, 6 => 4, 8 => 8 }[d]
        if bit && (bits & bit) != 0
          ok = false
          break
        end
      end
    end
    dir_ok[d] = ok
  end
  [info, dir_ok]
end

map = load_map(2)
evs = map.instance_variable_get(:@events)

puts "地图2 落点(15,17) 及周围 3x3 通行性"
puts "方向: 下/左/右/上 (true=可通行)"
puts ""
(-1..1).each do |dy|
  row = []
  (-1..1).each do |dx|
    x = 15 + dx
    y = 17 + dy
    _info, dir_ok = tile_info(map, tileset_passages, x, y)
    row << "(#{x},#{y}) 下=#{dir_ok[2] ? 'Y' : 'N'} 左=#{dir_ok[4] ? 'Y' : 'N'} 右=#{dir_ok[6] ? 'Y' : 'N'} 上=#{dir_ok[8] ? 'Y' : 'N'}"
  end
  puts row.join('  ')
end

puts ""
puts "== 该区域事件 =="
evs.each do |id, ev|
  ex = ev.instance_variable_get(:@x)
  ey = ev.instance_variable_get(:@y)
  next unless ex.between?(14, 16) && ey.between?(16, 18)
  name = ev.instance_variable_get(:@name)
  pages = ev.instance_variable_get(:@pages)
  trigs = pages.map { |p| p.instance_variable_get(:@trigger) }
  chars = pages.map { |p| p.instance_variable_get(:@graphic).instance_variable_get(:@character_name) }
  puts "  ##{id} '#{name}' @(#{ex},#{ey}) triggers=#{trigs.uniq.inspect} chars=#{chars.uniq.inspect}"
end
