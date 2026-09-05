ROOT = File.expand_path('..', __dir__)
# ============================================================
#  OneShot/mkxp Table 正确解析 (uint16 data)
#  头: dim(int32) + sizes(dim*int32) + cell_count(int32) + data(uint16[])
# ============================================================

$LOAD_PATH.unshift("#{ROOT}/runtime/lib/ruby/3.1.0")

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
    # cell_count at offset 4+dim*4
    cell_count = s[4 + dim * 4, 4].unpack1('V')
    t.instance_variable_set(:@cell_count, cell_count)
    data = s[4 + dim * 4 + 4..].unpack('v*')  # uint16
    t.instance_variable_set(:@data, data)
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

# tileset passages: 也检查是否 uint16 (Tilesets.rxdata 里的 Table)
ts_data = Marshal.load(File.binread("#{DATA}/Tilesets.rxdata"))
t = ts_data[1].instance_variable_get(:@passages)
puts "Tilesets[1].passages: x=#{t.xsize} y=#{t.ysize} z=#{t.zsize} cell=#{t.instance_variable_get(:@cell_count)}"

[2, 4].each do |mid|
  map = Marshal.load(File.binread(format("#{DATA}/Map%03d.rxdata", mid)))
  data = map.instance_variable_get(:@data)
  cnt = 0
  (0...data.zsize).each do |z|
    (0...data.ysize).each do |y|
      (0...data.xsize).each do |x|
        cnt += 1 if data[x, y, z] != 0
      end
    end
  end
  puts "地图#{mid}: w=#{map.instance_variable_get(:@width)} h=#{map.instance_variable_get(:@height)} 非0tile=#{cnt}"
  [2, 4].each do |m2|
    next unless mid == m2
    [['落点', 15, 17], ['上方', 15, 16], ['左方', 14, 17], ['下方', 15, 18], ['右方', 16, 17]].each do |lbl, x, y|
      puts "  #{lbl}(#{x},#{y}) z0=#{data[x, y, 0]} z1=#{data[x, y, 1]} z2=#{data[x, y, 2]}"
    end
  end
  [4].each do |m2|
    next unless mid == m2
    [['落点', 21, 10], ['(0,0)', 0, 0]].each do |lbl, x, y|
      puts "  #{lbl}(#{x},#{y}) z0=#{data[x, y, 0]} z1=#{data[x, y, 1]} z2=#{data[x, y, 2]}"
    end
  end
end
