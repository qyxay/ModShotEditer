$LOAD_PATH.unshift("C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/runtime/lib/ruby/3.1.0")
class Table
  attr_reader :xsize, :ysize, :zsize
  def self._load(s)
    dim = s[0,4].unpack1('V'); sizes = dim.times.map { |i| s[4+i*4,4].unpack1('V') }
    t = allocate
    t.instance_variable_set(:@xsize, sizes[0]); t.instance_variable_set(:@ysize, sizes[1] || 1); t.instance_variable_set(:@zsize, sizes[2] || 1)
    t.instance_variable_set(:@data, s.byteslice(20, (sizes[0]*(sizes[1]||1)*(sizes[2]||1))*2).unpack('v*'))
    t
  end
  def [](x, y = 0, z = 0); @data[x + @xsize*y + @xsize*@ysize*z] || 0; end
end
class Color; def self._load(s); allocate; end; end
class Tone; def self._load(s); allocate; end; end
class Rect; def self._load(s); allocate; end; end
module RPG
  class Map; end; class Event; end; class EventCommand; end; class AudioFile; end
  class MoveRoute; end; class MoveCommand; end; class Tileset; end
  class Event::Page; end; class Event::Page::Condition; end; class Event::Page::Graphic; end
end
iv = ->(o,n){ o.instance_variable_get(n) }
D = "C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data"
m = Marshal.load(File.binread("#{D}/Map004.rxdata"))
d = m.instance_variable_get(:@data)
puts "Map004 tileset_id=#{m.instance_variable_get(:@tileset_id)} #{d.xsize}x#{d.ysize}x#{d.zsize}"
[0,1,2].each do |z|
  zids = []
  (0...d.xsize).each { |x| (0...d.ysize).each { |y| v = d[x,y,z]; zids << v if v != 0 } }
  puts "z#{z}: #{zids.min}-#{zids.max} uniq=#{zids.uniq.size} sample=#{zids.uniq.sort.first(10).inspect}"
end
# 通行表前几项（tileset 1 = start, 384 偏移? RMXP: autotile 384 占位）
ts = Marshal.load(File.binread("#{D}/Tilesets.rxdata"))
t1 = ts[1]
pas = t1.instance_variable_get(:@passages)
puts "ts1 passages len=#{pas.xsize} terrain len=#{t1.instance_variable_get(:@terrain_tags).xsize} priorities len=#{t1.instance_variable_get(:@priorities).xsize}"
# 打印几个 tile 的 passages 值（tile 485 = 485-384=101 号图块）
[485, 487, 493, 552].each do |tid|
  puts "tile #{tid}: passage=#{pas[tid]}"
end
# tile 485 在 start.png 的位置: (485-384)=101 -> col=101%8=5, row=101/8=12 (32px)
(485-384).tap { |i| puts "tile485 -> png index #{i}: col=#{i%8} row=#{i/8}" }
