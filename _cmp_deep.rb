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
end
class Tone
  attr_accessor :red, :green, :blue, :gray
  def initialize(r=0,g=0,b=0,gr=0); @red=r;@green=g;@blue=b;@gray=gr; end
  def self._load(s); r,g,b,gr = s.unpack('d4'); new(r,g,b,gr); end
  def _dump(*); [@red,@green,@blue,@gray].pack('d4'); end
end
class Rect; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end
module RPG
  class Map; end; class Event; end; class EventCommand; end; class AudioFile
    attr_accessor :name, :volume, :pitch
    def self._load(s); Marshal.load(s); end
  end
  class MoveRoute
    attr_accessor :repeat, :skippable, :wait, :list
    def self._load(s); Marshal.load(s); end
  end
  class MoveCommand
    attr_accessor :code, :parameters
    def self._load(s); Marshal.load(s); end
  end
  class Tileset; end; class MapInfo; end; class System; end
  class Event::Page; end; class Event::Page::Condition; end; class Event::Page::Graphic; end
end
def iv(o, n); o.instance_variable_get(n); end
P = "C:/Users/Qyxay/Documents/RPGXP/Project1/Data"
O = "C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data"

def norm(obj)
  case obj
  when Array then obj.map { |x| norm(x) }
  when Hash then obj.keys.sort.map { |k| [k, norm(obj[k])] }
  when RPG::AudioFile then ["AF", obj.name, obj.volume, obj.pitch]
  when RPG::MoveRoute then ["MR", obj.repeat, obj.skippable, obj.wait, norm(obj.list)]
  when RPG::MoveCommand then ["MC", obj.code, norm(obj.parameters)]
  when Color then ["C", obj.red, obj.green, obj.blue, obj.alpha]
  when Tone then ["T", obj.red, obj.green, obj.blue, obj.gray]
  when Float then obj.round(6)
  else obj
  end
end

def deep_cmp(l1, l2)
  return "条数不同 #{l1.size} vs #{l2.size}" unless l1.size == l2.size
  diffs = []
  l1.each_with_index do |c, i|
    c2 = l2[i]
    a = [c.instance_variable_get(:@code), norm(c.instance_variable_get(:@parameters))]
    b = [c2.instance_variable_get(:@code), norm(c2.instance_variable_get(:@parameters))]
    unless a == b
      diffs << "  cmd#{i}: P=#{a.inspect[0,80]} O=#{b.inspect[0,80]}"
    end
  end
  diffs.empty? ? nil : diffs
end

# 深度对比三张地图
%w[Map011 Map015 Map048].each do |m|
  m1 = Marshal.load(File.binread("#{P}/#{m}.rxdata")); m2 = Marshal.load(File.binread("#{O}/#{m}.rxdata"))
  real = []
  d1 = iv(m1,:@data); d2 = iv(m2,:@data)
  td = 0
  (0...d1.xsize).each { |x| (0...d1.ysize).each { |y| (0...d1.zsize).each { |z| td += 1 if d1[x,y,z] != d2[x,y,z] } } }
  e1 = iv(m1,:@events); e2 = iv(m2,:@events)
  (e1.keys | e2.keys).sort.each do |k|
    a = e1[k]; b = e2[k]
    next if a.nil? || b.nil?
    pa = iv(a,:@pages); pb = iv(b,:@pages)
    if pa.size == pb.size
      pa.each_with_index do |pg, i|
        r = deep_cmp(iv(pg,:@list)||[], iv(pb[i],:@list)||[])
        real << "事件#{k}页#{i}: #{r.join(' | ')}" if r
      end
    end
  end
  if td == 0 && real.empty?
    puts "#{m}: 真实差异 = 0 (MD5 不同纯属 RMXP 重写格式噪音)"
  else
    puts "#{m}: tile差异=#{td}, 事件差异=#{real.size}"
    real.first(3).each { |r| puts "  #{r}" }
  end
end

# MapInfos 对比
puts "== MapInfos =="
i1 = Marshal.load(File.binread("#{P}/MapInfos.rxdata")); i2 = Marshal.load(File.binread("#{O}/MapInfos.rxdata"))
puts "条目数: P=#{i1.size} O=#{i2.size}"
(i1.keys | i2.keys).sort.each do |k|
  a = i1[k]; b = i2[k]
  if a.nil? || b.nil? then puts "  仅一侧: #{k}"; next end
  fa = [iv(a,:@name), iv(a,:@parent_id), iv(a,:@order)]; fb = [iv(b,:@name), iv(b,:@parent_id), iv(b,:@order)]
  puts "  #{k}: #{fa.inspect} vs #{fb.inspect}" unless fa == fb
end

# System 对比
puts "== System =="
s1 = Marshal.load(File.binread("#{P}/System.rxdata")); s2 = Marshal.load(File.binread("#{O}/System.rxdata"))
(iv(s1,:@start_map_id) == iv(s2,:@start_map_id) ? (puts "start_map_id 相同=#{iv(s1,:@start_map_id)}") : (puts "start_map_id 不同: P=#{iv(s1,:@start_map_id)} O=#{iv(s2,:@start_map_id)}"))
(iv(s1,:@start_x) == iv(s2,:@start_x) ? nil : puts("start_x 不同: P=#{iv(s1,:@start_x)} O=#{iv(s2,:@start_x)}"))
(iv(s1,:@start_y) == iv(s2,:@start_y) ? nil : puts("start_y 不同: P=#{iv(s1,:@start_y)} O=#{iv(s2,:@start_y)}"))
(iv(s1,:@switches) == iv(s2,:@switches) ? nil : puts("switches 不同"))
(iv(s1,:@variables) == iv(s2,:@variables) ? nil : puts("variables 不同"))
(iv(s1,:@elements) == iv(s2,:@elements) ? nil : puts("elements 不同"))
