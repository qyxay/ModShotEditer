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
class Color
  attr_accessor :red, :green, :blue, :alpha
  def initialize(r=0,g=0,b=0,a=255); @red=r;@green=g;@blue=b;@alpha=a; end
  def self._load(s); r,g,b,a = s.unpack('d4'); new(r,g,b,a); end
  def _dump(*); [@red,@green,@blue,@alpha].pack('d4'); end
  def ==(o); o.class == Color && [red,green,blue,alpha] == [o.red,o.green,o.blue,o.alpha]; end
end
class Tone
  attr_accessor :red, :green, :blue, :gray
  def initialize(r=0,g=0,b=0,gr=0); @red=r;@green=g;@blue=b;@gray=gr; end
  def self._load(s); r,g,b,gr = s.unpack('d4'); new(r,g,b,gr); end
  def _dump(*); [@red,@green,@blue,@gray].pack('d4'); end
  def ==(o); o.class == Tone && [red,green,blue,gray] == [o.red,o.green,o.blue,o.gray]; end
end
class Rect; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end
module RPG
  class Map; end; class Event; end; class EventCommand; end; class AudioFile
    attr_accessor :name, :volume, :pitch
    def self._load(s); Marshal.load(s); end
    def ==(o); o.class == AudioFile && name == o.name && volume == o.volume && pitch == o.pitch; end
  end
  class MoveRoute; end; class MoveCommand; end; class Tileset; end; class MapInfo; end
  class System; end
  class Event::Page; end; class Event::Page::Condition; end; class Event::Page::Graphic; end
end
def iv(o, n); o.instance_variable_get(n); end
P = "C:/Users/Qyxay/Documents/RPGXP/Project1/Data"
O = "C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data"

def norm(obj)
  case obj
  when Array then obj.map { |x| norm(x) }
  when Hash then obj.transform_values { |x| norm(x) }
  when RPG::AudioFile then ["AF", obj.name, obj.volume, obj.pitch]
  when Color, Tone then obj
  else obj
  end
end

def deep_cmp(l1, l2)
  return "条数不同 #{l1.size} vs #{l2.size}" unless l1.size == l2.size
  diffs = []
  l1.each_with_index do |c, i|
    c2 = l2[i]
    unless c.instance_variable_get(:@code) == c2.instance_variable_get(:@code) &&
           norm(c.instance_variable_get(:@parameters)) == norm(c2.instance_variable_get(:@parameters))
      diffs << "  cmd#{i}: P=#{c.instance_variable_get(:@code)}#{norm(c.instance_variable_get(:@parameters)).inspect[0,70]} O=#{c2.instance_variable_get(:@code)}#{norm(c2.instance_variable_get(:@parameters)).inspect[0,70]}"
    end
  end
  diffs.empty? ? nil : diffs
end

def cmp_map(p, o, name)
  m1 = Marshal.load(File.binread(p)); m2 = Marshal.load(File.binread(o))
  puts "== #{name} =="
  puts "tileset/size: P=#{iv(m1,:@tileset_id)} #{iv(m1,:@width)}x#{iv(m1,:@height)} O=#{iv(m2,:@tileset_id)} #{iv(m2,:@width)}x#{iv(m2,:@height)}"
  d1 = iv(m1,:@data); d2 = iv(m2,:@data)
  td = 0; firsts = []
  (0...d1.xsize).each { |x| (0...d1.ysize).each { |y| (0...d1.zsize).each { |z|
    a = d1[x,y,z]; b = d2[x,y,z]
    if a != b then td += 1; firsts << "  (#{x},#{y},z#{z}): P=#{a} O=#{b}" if firsts.size < 8 end
  } } }
  puts "tile 差异: #{td}"
  firsts.each { |f| puts f }
  e1 = iv(m1,:@events); e2 = iv(m2,:@events)
  puts "事件数: P=#{e1.size} O=#{e2.size}"
  (e1.keys | e2.keys).sort.each do |k|
    a = e1[k]; b = e2[k]
    if a.nil? || b.nil? then puts "  事件#{k}: 仅一侧"; next end
    ds = []
    ds << "名字 #{iv(a,:@name).inspect} vs #{iv(b,:@name).inspect}" if iv(a,:@name) != iv(b,:@name)
    ds << "坐标 #{iv(a,:@x)},#{iv(a,:@y)} vs #{iv(b,:@x)},#{iv(b,:@y)}" if iv(a,:@x) != iv(b,:@x) || iv(a,:@y) != iv(b,:@y)
    pa = iv(a,:@pages); pb = iv(b,:@pages)
    if pa.size != pb.size then ds << "页数 #{pa.size} vs #{pb.size}"
    else
      pa.each_with_index do |pg, i|
        pg2 = pb[i]
        ds << "页#{i} trigger #{iv(pg,:@trigger)} vs #{iv(pg2,:@trigger)}" if iv(pg,:@trigger) != iv(pg2,:@trigger)
        r = deep_cmp(iv(pg,:@list)||[], iv(pg2,:@list)||[])
        ds << "页#{i} 命令: #{r.join(' | ')}" if r
      end
    end
    puts "  事件#{k}: #{ds.join('; ')}" unless ds.empty?
  end
end

%w[Map011 Map015 Map048].each { |m| cmp_map("#{P}/#{m}.rxdata", "#{O}/#{m}.rxdata", m) }
