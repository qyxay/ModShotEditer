ROOT = File.expand_path('..', __dir__)
# ============================================================
#  检查 Table 解析是否正确 (地图2 vs 地图4)
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

[2, 4].each do |mid|
  map = Marshal.load(File.binread(format("#{DATA}/Map%03d.rxdata", mid)))
  data = map.instance_variable_get(:@data)
  puts "地图#{mid}: w=#{map.instance_variable_get(:@width)} h=#{map.instance_variable_get(:@height)}"
  puts "  Table dump size=#{data._dump.bytesize} x=#{data.xsize} y=#{data.ysize} z=#{data.zsize}"
  # 统计非0 tile
  cnt = 0
  total = 0
  (0...data.zsize).each do |z|
    (0...data.ysize).each do |y|
      (0...data.xsize).each do |x|
        total += 1
        cnt += 1 if data[x, y, z] != 0
      end
    end
  end
  puts "  非0 tile: #{cnt}/#{total}"
  # 打印几个已知位置
  [['落点', 21, 10], ['附近', 20, 10], ['(0,0)', 0, 0]].each do |lbl, x, y|
    puts "  #{lbl}(#{x},#{y}) z0=#{data[x, y, 0]} z1=#{data[x, y, 1]} z2=#{data[x, y, 2]}"
  end if mid == 4
  [['落点', 15, 17], ['(0,0)', 0, 0]].each do |lbl, x, y|
    puts "  #{lbl}(#{x},#{y}) z0=#{data[x, y, 0]} z1=#{data[x, y, 1]} z2=#{data[x, y, 2]}"
  end if mid == 2
end

# 原始 dump 头部对比
raw2 = File.binread("#{DATA}/Map002.rxdata")
# 找 Table 的位置: Map 对象序列化里 @data 是 Table
# 直接解析: 用 Marshal 后转储 Table
t2 = Marshal.load(File.binread("#{DATA}/Map002.rxdata")).instance_variable_get(:@data)
d = t2._dump
puts ""
puts "地图2 @data dump 前 32 bytes: #{d.bytes.first(32).map { |b| format('%02X', b) }.join(' ')}"
