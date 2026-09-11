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
  class MoveRoute; attr_accessor :repeat, :skippable, :wait, :list; def self._load(s); Marshal.load(s); end; end
  class MoveCommand; attr_accessor :code, :parameters; def self._load(s); Marshal.load(s); end; end
  class Tileset; end; class MapInfo; end; class System
    class Words; def self._load(s); Marshal.load(s); end; end
  end
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

def map_real_diff(p, o)
  m1 = Marshal.load(File.binread(p)); m2 = Marshal.load(File.binread(o))
  d1 = iv(m1,:@data); d2 = iv(m2,:@data)
  td = 0
  (0...d1.xsize).each { |x| (0...d1.ysize).each { |y| (0...d1.zsize).each { |z| td += 1 if d1[x,y,z] != d2[x,y,z] } } }
  e1 = iv(m1,:@events); e2 = iv(m2,:@events)
  ev_diff = 0
  (e1.keys | e2.keys).sort.each do |k|
    a = e1[k]; b = e2[k]
    if a.nil? || b.nil? then ev_diff += 1; next end
    if iv(a,:@name) != iv(b,:@name) || iv(a,:@x) != iv(b,:@x) || iv(a,:@y) != iv(b,:@y) then ev_diff += 1; next end
    pa = iv(a,:@pages); pb = iv(b,:@pages)
    if pa.size != pb.size then ev_diff += 1; next end
    pa.each_with_index do |pg, i|
      pg2 = pb[i]
      if iv(pg,:@trigger) != iv(pg2,:@trigger) then ev_diff += 1; next end
      l1 = iv(pg,:@list)||[]; l2 = iv(pg2,:@list)||[]
      if l1.size != l2.size then ev_diff += 1; next end
      l1.each_with_index do |c, j|
        c2 = l2[j]
        a2 = [c.instance_variable_get(:@code), norm(c.instance_variable_get(:@parameters))]
        b2 = [c2.instance_variable_get(:@code), norm(c2.instance_variable_get(:@parameters))]
        if a2 != b2 then ev_diff += 1; break end
      end
    end
  end
  [td, ev_diff]
end

puts "== 全量地图扫描 =="
real_maps = []
(1..263).each do |n|
  f = "Map%03d.rxdata" % n
  pa = "#{P}/#{f}"; oa = "#{O}/#{f}"
  next unless File.exist?(oa)
  td, ev = map_real_diff(pa, oa)
  if td > 0 || ev > 0
    real_maps << [f, td, ev]
  end
end
if real_maps.empty?
  puts "没有任何地图有真实差异"
else
  real_maps.each { |f, td, ev| puts "#{f}: tile差异=#{td} 事件差异=#{ev}" }
end

puts "== 关键数据库对比 =="
%w[System.rxdata CommonEvents.rxdata Tilesets.rxdata Actors.rxdata Items.rxdata Animations.rxdata Classes.rxdata Skills.rxdata States.rxdata Weapons.rxdata Armors.rxdata Enemies.rxdata].each do |f|
  begin
    a = Marshal.load(File.binread("#{P}/#{f}")); b = Marshal.load(File.binread("#{O}/#{f}"))
    puts "#{f}: #{norm(a) == norm(b) ? "真实差异=0 (重写噪音)" : "有真实差异"}"
  rescue => e
    puts "#{f}: 加载失败 #{e.message}"
  end
end
