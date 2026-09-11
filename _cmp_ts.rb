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
  class Tileset
    attr_accessor :id, :name, :tileset_name, :autotile_names, :panorama_name, :panorama_hue,
                  :fog_name, :fog_hue, :fog_opacity, :fog_blend_type, :fog_zoom, :fog_sx, :fog_sy,
                  :battleback_name, :passages, :priorities, :terrain_tags
    def self._load(s); Marshal.load(s); end
  end
  class MapInfo; end
  class System
    class Words; def self._load(s); Marshal.load(s); end; end
    class TestBattler; def self._load(s); Marshal.load(s); end; end
  end
  class Event::Page; end; class Event::Page::Condition; end; class Event::Page::Graphic; end
end
def iv(o, n); o.instance_variable_get(n); end
P = "C:/Users/Qyxay/Documents/RPGXP/Project1/Data"
O = "C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data"

# Tilesets 深度对比
t1 = Marshal.load(File.binread("#{P}/Tilesets.rxdata")); t2 = Marshal.load(File.binread("#{O}/Tilesets.rxdata"))
puts "Tilesets 数量: P=#{t1.size} O=#{t2.size}"
diff_ts = []
(1..[t1.size, t2.size].max).each do |i|
  a = t1[i]; b = t2[i]
  next if a.nil? && b.nil?
  if a.nil? || b.nil? then diff_ts << "ts#{i} 仅一侧"; next end
  fields = %i[name tileset_name panorama_name fog_name battleback_name]
  fields.each do |fd|
    diff_ts << "ts#{i}.#{fd}: P=#{a.send(fd).inspect} O=#{b.send(fd).inspect}" unless a.send(fd) == b.send(fd)
  end
  unless a.autotile_names == b.autotile_names
    diff_ts << "ts#{i}.autotile_names: P=#{a.autotile_names.inspect} O=#{b.autotile_names.inspect}"
  end
  %i[panorama_hue fog_hue fog_opacity fog_blend_type fog_zoom fog_sx fog_sy].each do |fd|
    diff_ts << "ts#{i}.#{fd}: P=#{a.send(fd)} O=#{b.send(fd)}" unless a.send(fd) == b.send(fd)
  end
  pa = a.passages; pb = b.passages
  if pa.xsize == pb.xsize
    pd = []
    (0...pa.xsize).each { |x| pd << "#{x}:P=#{pa[x]}O=#{pb[x]}" if pa[x] != pb[x] }
    diff_ts << "ts#{i}.passages 差异#{pd.size}个: #{pd.first(5).join(' ')}" unless pd.empty?
  else
    diff_ts << "ts#{i}.passages 长度: P=#{pa.xsize} O=#{pb.xsize}"
  end
  pr1 = a.priorities; pr2 = b.priorities
  if pr1.xsize == pr2.xsize
    pd = []
    (0...pr1.xsize).each { |x| pd << "#{x}:P=#{pr1[x]}O=#{pr2[x]}" if pr1[x] != pr2[x] }
    diff_ts << "ts#{i}.priorities 差异#{pd.size}个" unless pd.empty?
  end
  tr1 = a.terrain_tags; tr2 = b.terrain_tags
  if tr1.xsize == tr2.xsize
    pd = []
    (0...tr1.xsize).each { |x| pd << "#{x}:P=#{tr1[x]}O=#{tr2[x]}" if tr1[x] != tr2[x] }
    diff_ts << "ts#{i}.terrain_tags 差异#{pd.size}个" unless pd.empty?
  end
end
if diff_ts.empty?
  puts "Tilesets: 真实差异=0 (重写噪音)"
else
  diff_ts.first(20).each { |d| puts d }
end

# System 对比
s1 = Marshal.load(File.binread("#{P}/System.rxdata")); s2 = Marshal.load(File.binread("#{O}/System.rxdata"))
%i[start_map_id start_x start_y].each do |fd|
  v1 = s1.send(fd); v2 = s2.send(fd)
  puts "System.#{fd}: #{v1 == v2 ? "相同=#{v1}" : "不同 P=#{v1} O=#{v2}"}"
end
puts "System.switches 相同: #{s1.switches == s2.switches}"
puts "System.variables 相同: #{s1.variables == s2.variables}"
puts "System.elements 相同: #{s1.elements == s2.elements}"
puts "System.words 相同: #{s1.words == s2.words}"
puts "System 其余字段数量: #{s1.instance_variables.size} vs #{s2.instance_variables.size}"
(s1.instance_variables | s2.instance_variables).each do |ivn|
  v1 = s1.instance_variable_get(ivn); v2 = s2.instance_variable_get(ivn)
  unless v1 == v2
    puts "  System#{ivn}: 不同 (P=#{v1.class} O=#{v2.class})"
  end
end
