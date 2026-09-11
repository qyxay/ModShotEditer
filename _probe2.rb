$LOAD_PATH.unshift("C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/runtime/lib/ruby/3.1.0")
class Table
  attr_reader :xsize, :ysize, :zsize
  def self._load(s)
    dim = s[0,4].unpack1('V'); sizes = dim.times.map { |i| s[4+i*4,4].unpack1('V') }
    t = allocate
    t.instance_variable_set(:@xsize, sizes[0]); t.instance_variable_set(:@ysize, sizes[1] || 1); t.instance_variable_set(:@zsize, sizes[2] || 1)
    t.instance_variable_set(:@data, s[4+dim*4..].unpack('l*'))
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
ts = Marshal.load(File.binread("#{D}/Tilesets.rxdata"))
ts.each_with_index do |t, i|
  next unless t && i <= 16
  puts "ts#{i}: tileset_name=#{iv.call(t,:@tileset_name).inspect} autotile_names=#{iv.call(t,:@autotile_names).inspect}"
end
# 地图 4 的 tile id 范围
m = Marshal.load(File.binread("#{D}/Map004.rxdata"))
d = m.instance_variable_get(:@data)
ids = []
(0...d.xsize).each { |x| (0...d.ysize).each { |y| (0...d.zsize).each { |z| v = d[x,y,z]; ids << v if v != 0 } } }
puts "Map004 tileset_id=#{m.instance_variable_get(:@tileset_id)} tile id range: #{ids.min}-#{ids.max}, count=#{ids.size}, sample=#{ids.uniq.sort.first(20).inspect}"
