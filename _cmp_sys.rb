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
  class AudioFile; def self._load(s); Marshal.load(s); end; end
  class System
    class Words; def self._load(s); Marshal.load(s); end; end
    class TestBattler; def self._load(s); Marshal.load(s); end; end
  end
end
P = "C:/Users/Qyxay/Documents/RPGXP/Project1/Data"
O = "C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data"
s1 = Marshal.load(File.binread("#{P}/System.rxdata"))
s2 = Marshal.load(File.binread("#{O}/System.rxdata"))
puts "=== System 实例变量差异 ==="
(s1.instance_variables | s2.instance_variables).sort.each do |n|
  v1 = s1.instance_variable_get(n); v2 = s2.instance_variable_get(n)
  next if v1 == v2
  if v1.is_a?(Array) && v2.is_a?(Array) && v1.size == v2.size && (1..[v1.size,v2.size].min).none? { |i| v1[i] != v2[i] }
    puts "#{n}: 仅首元素(nil)位置差异 Array大小#{v1.size}"
  else
    puts "#{n}: P=#{v1.inspect[0,50]} O=#{v2.inspect[0,50]}"
  end
end
puts "=== 差异字段数: #{(s1.instance_variables | s2.instance_variables).count { |n| s1.instance_variable_get(n) != s2.instance_variable_get(n) }} ==="
puts "P 特有: #{(s1.instance_variables - s2.instance_variables).inspect}"
puts "O 特有: #{(s2.instance_variables - s1.instance_variables).inspect}"
