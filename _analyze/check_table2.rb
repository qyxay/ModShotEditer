ROOT = File.expand_path('..', __dir__)
# ============================================================
#  检查 Table 真实序列化格式 (打印 _load 收到的原始 bytes)
# ============================================================

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
  attr_reader :xsize, :ysize, :zsize, :raw_size, :raw_head
  def self._load(s)
    t = allocate
    t.instance_variable_set(:@raw_size, s.bytesize)
    t.instance_variable_set(:@raw_head, s.bytes.first(64))
    # 尝试标准 RMXP 解析
    dim = s[0, 4].unpack1('l<')  # 带符号
    t.instance_variable_set(:@dim, dim)
    sizes = []
    if dim.between?(1, 3)
      sizes = dim.times.map { |i| s[4 + i * 4, 4].unpack1('l<') }
    end
    t.instance_variable_set(:@sizes, sizes)
    t
  end
  def _dump(*); "\x00" * 4; end
end
class Color; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end
class Tone; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end
class Rect; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end

DATA = "#{ROOT}/OneShot/Data"

[2, 4].each do |mid|
  map = Marshal.load(File.binread(format("#{DATA}/Map%03d.rxdata", mid)))
  data = map.instance_variable_get(:@data)
  puts "地图#{mid}:"
  puts "  dim(带符号)=#{data.instance_variable_get(:@dim)}"
  puts "  sizes=#{data.instance_variable_get(:@sizes).inspect}"
  puts "  raw_size=#{data.raw_size}"
  puts "  raw_head(前48B): #{data.raw_head.first(48).map { |b| format('%02X', b) }.join(' ')}"
  puts ""
end
