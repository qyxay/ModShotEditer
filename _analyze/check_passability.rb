# ============================================================
#  临时分析: 检查三张 Livingroom 地图落点四周的可通行性
# ============================================================

$LOAD_PATH.unshift('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/runtime/lib/ruby/3.1.0')
$LOAD_PATH.unshift('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/runtime/lib/ruby/3.1.0/x64-mingw64')

# --- 真正的 Table 解析 (mkxp 格式: dim=4字节, sizes=4字节, 数据=int32) ---
class Table
  def self._load(str)
    s = str.dup.force_encoding('BINARY')
    dim = s[0, 4].unpack1('V')
    sizes = []
    off = 4
    dim.times { sizes << s[off, 4].unpack1('V'); off += 4 }
    elems = sizes.reduce(1) { |a, b| a * b }
    data = s[off, elems * 4].unpack('l*')
    t = allocate
    t.instance_variable_set(:@dim, dim)
    t.instance_variable_set(:@sizes, sizes)
    t.instance_variable_set(:@data, data)
    t
  end
  def _dump(*); "\x00"; end
  def xsize; @sizes[0] || 1; end
  def ysize; @sizes[1] || 1; end
  def zsize; @sizes[2] || 1; end
  def [](x, y = nil, z = nil)
    if z
      @data[x + y * xsize + z * xsize * ysize] || 0
    elsif y
      @data[x + y * xsize] || 0
    else
      @data[x] || 0
    end
  end
end

class Color; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end
class Tone; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end
class Rect; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end

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

tilesets = Marshal.load(File.binread('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data/Tilesets.rxdata'))
passages_by_ts = {}
priorities_by_ts = {}
tilesets.compact.each do |ts|
  id = ts.instance_variable_get(:@id)
  passages_by_ts[id] = ts.instance_variable_get(:@passages)
  priorities_by_ts[id] = ts.instance_variable_get(:@priorities)
end

MAPS = { 4 => [21, 10], 64 => [0, 0], 182 => [16, 13] }

def passable?(data, passages, priorities, x, y, d, w, h)
  # valid?
  return false if x < 0 || y < 0 || x >= w || y >= h
  bit = (1 << (d / 2 - 1)) & 0x0f
  [2, 1, 0].each do |i|
    tile_id = data[x, y, i]
    next if tile_id == 0
    if (passages[tile_id] & bit) != 0
      return false
    elsif (passages[tile_id] & 0x0f) == 0x0f
      return false
    elsif (priorities[tile_id] & 0x0f) == 0
      return true
    end
  end
  true
end

MAPS.each do |mid, (sx, sy)|
  path = format('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data/Map%03d.rxdata', mid)
  map = Marshal.load(File.binread(path))
  tsid = map.instance_variable_get(:@tileset_id)
  data = map.instance_variable_get(:@data)
  w = map.instance_variable_get(:@width)
  h = map.instance_variable_get(:@height)
  passages = passages_by_ts[tsid]
  priorities = priorities_by_ts[tsid]
  puts "== 地图 #{mid} (tileset #{tsid}) 落点 (#{sx},#{sy}) =="
  puts "  tile: (0,0,0)=#{data[sx,sy,0]} (1,0,0)=#{data[sx,sy,1]} (2,0,0)=#{data[sx,sy,2]}"
  # 落点自身能否站立 + 四个方向
  { '落点' => [sx, sy, 0], '上' => [sx, sy - 1, 8], '下' => [sx, sy + 1, 2], '左' => [sx - 1, sy, 4], '右' => [sx + 1, sy, 6] }.each do |name, (tx, ty, d)|
    ok = passable?(data, passages, priorities, tx, ty, d, w, h)
    puts "  #{name}(#{tx},#{ty}) dir#{d}: #{ok ? '可通行' : '**不可通行**'}"
  end
  puts ""
end
