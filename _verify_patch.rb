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
module RPG; class Map; end; class Event; end; class EventCommand; end; class AudioFile; def self._load(s); Marshal.load(s); end; end; class MoveRoute; def self._load(s); Marshal.load(s); end; end; class MoveCommand; def self._load(s); Marshal.load(s); end; end; class Event::Page; end; class Event::Page::Condition; end; class Event::Page::Graphic; end; end
P = "C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/mods/mod/Data/Map002.rxdata"
O = "C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data/Map002.rxdata"
m = Marshal.load(File.binread(P)); o = Marshal.load(File.binread(O))
iv = ->(o,n){ o.instance_variable_get(n) }
puts "补丁层 Map002 解析 OK"
puts "tileset_id=#{iv.call(m,:@tileset_id)} size=#{iv.call(m,:@width)}x#{iv.call(m,:@height)}"
d1 = iv.call(m,:@data); d2 = iv.call(o,:@data)
puts "== 修改的 tile（z1 层）=="
(0...d1.xsize).each { |x| (0...d1.ysize).each { |y| (0...d1.zsize).each { |z|
  if d1[x,y,z] != d2[x,y,z]
    puts "  (#{x},#{y}) z#{z}: 原版=#{d2[x,y,z]} → 新版=#{d1[x,y,z]}  (图片块偏移#{439-384}, 行#{((439-384)/8).to_i} 列#{((439-384)%8).to_i})"
  end
} } }
puts "事件数: #{iv.call(m,:@events).size} (与原版一致=#{iv.call(m,:@events).size == iv.call(o,:@events).size})"
