# ============================================================
#  检查 Tilesets passages 真实格式
# ============================================================

module RPG
  class Tileset; end
end
class Table
  attr_reader :xsize, :ysize, :zsize, :dim, :sizes, :cell_count, :raw_head, :data16
  def self._load(s)
    t = allocate
    t.instance_variable_set(:@raw_head, s.bytes.first(32))
    t.instance_variable_set(:@raw_size, s.bytesize)
    dim = s[0, 4].unpack1('V')
    t.instance_variable_set(:@dim, dim)
    sizes = dim.times.map { |i| s[4 + i * 4, 4].unpack1('V') }
    t.instance_variable_set(:@sizes, sizes)
    cc = s[4 + dim * 4, 4].unpack1('V')
    t.instance_variable_set(:@cell_count, cc)
    # uint16
    d16 = s[4 + dim * 4 + 4..].unpack('v*')
    t.instance_variable_set(:@data16, d16)
    # uint32
    d32 = s[4 + dim * 4 + 4..].unpack('V*')
    t.instance_variable_set(:@data32, d32)
    t
  end
  def _dump(*); "\x00" * 4; end
end
class Color; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end
class Tone; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end
class Rect; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end

DATA = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data'
ts_data = Marshal.load(File.binread("#{DATA}/Tilesets.rxdata"))
[1].each do |i|
  t = ts_data[i]
  pass = t.instance_variable_get(:@passages)
  puts "Tilesets[#{i}].passages:"
  puts "  dim=#{pass.dim} sizes=#{pass.sizes.inspect} cell_count=#{pass.cell_count} raw_size=#{pass.raw_size}"
  puts "  head: #{pass.raw_head.first(32).map { |b| format('%02X', b) }.join(' ')}"
  puts "  data16 前10: #{pass.data16.first(10).inspect}"
  puts "  data32 前10: #{pass.data32.first(10).inspect}"
  puts "  cell_count 用16位空间: #{pass.raw_size} = #{pass.sizes[0] * (pass.sizes[1] || 1) * (pass.sizes[2] || 1)} cells"
end
