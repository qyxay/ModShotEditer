ROOT = File.expand_path('..', __dir__)
# ============================================================
#  检查: start(15,17) 及床区域的 tile ID + 通行性 bits
# ============================================================

$LOAD_PATH.unshift("#{ROOT}/runtime/lib/ruby/3.1.0")

module RPG
  class Map; end
  class Event; end
  class Tileset; end
  class EventCommand; end
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

DATA = "#{ROOT}/OneShot/Data"
map = Marshal.load(File.binread("#{DATA}/Map002.rxdata"))
tilesets = Marshal.load(File.binread("#{DATA}/Tilesets.rxdata"))
ts = tilesets[map.instance_variable_get(:@tileset_id)]
pass = ts.instance_variable_get(:@passages)
data = map.instance_variable_get(:@data)

puts "地图2 tileset_id=#{map.instance_variable_get(:@tileset_id)}"
puts "床区域 (14,16)-(15,17) 及周围 每格 3 层 tile ID + bits"
puts "(bits: 0x0F=四向堵, 0x00=四向通)"
puts ""
(15..18).each do |y|
  row = []
  (13..16).each do |x|
    t0 = data[x, y, 0]; t1 = data[x, y, 1]; t2 = data[x, y, 2]
    b0 = t0 == 0 ? nil : pass[t0]
    b1 = t1 == 0 ? nil : pass[t1]
    b2 = t2 == 0 ? nil : pass[t2]
    row << "(#{x},#{y})[#{t0}:#{b0 ? format('0x%02X', b0) : '.'},#{t1}:#{b1 ? format('0x%02X', b1) : '.'},#{t2}:#{b2 ? format('0x%02X', b2) : '.'}]"
  end
  puts row.join(' ')
end
