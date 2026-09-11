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
  class MapInfo; end
end
iv = ->(o,n){ o.instance_variable_get(n) }
D = "C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data"
# Map004 结构
m = Marshal.load(File.binread("#{D}/Map004.rxdata"))
puts "== Map004 =="
m.instance_variables.each { |v| val = iv.call(m, v); puts "#{v} => #{val.class} #{val.is_a?(Table) ? "#{val.xsize}x#{val.ysize}x#{val.zsize}" : val.inspect[0,120]}" }
# Tilesets 结构
ts = Marshal.load(File.binread("#{D}/Tilesets.rxdata"))
puts "== Tilesets count=#{ts.size} =="
ts.each_with_index do |t, i|
  next unless t
  ivs = t.instance_variables
  puts "ts#{i}: name=#{iv.call(t,:@name).inspect} ivs=#{ivs.inspect}"
  pas = iv.call(t,:@passages)
  if pas
    puts "  passages: #{pas.class} #{pas.respond_to?(:xsize) ? "#{pas.xsize}x#{pas.ysize}x#{pas.zsize}" : pas.size rescue 'n/a'}"
  end
end
# MapInfos
mi = Marshal.load(File.binread("#{D}/MapInfos.rxdata"))
puts "== MapInfos count=#{mi.size} =="
mi.each do |k, info|
  puts "  #{k}: name=#{iv.call(info,:@name).inspect} parent=#{iv.call(info,:@parent_id)} order=#{iv.call(info,:@order)}" if k <= 5
end
# System
sys = Marshal.load(File.binread("#{D}/System.rxdata"))
puts "== System =="
sys.instance_variables.each { |v| val = iv.call(sys, v); puts "  #{v} => #{val.is_a?(Array) ? "[#{val.size}]" : val.inspect[0,100]}" }
