# 结构对比: Project1 vs OneShot 的 Map002/System/Tilesets/MapInfos
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
class Color; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end
class Tone; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end
class Rect; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end
module RPG
  class Map; end; class Event; end; class EventCommand; end; class AudioFile; end
  class MoveRoute; end; class MoveCommand; end; class Tileset; end; class MapInfo; end
  class System; end
  class Event::Page; end; class Event::Page::Condition; end; class Event::Page::Graphic; end
end
iv = ->(o,n){ o.instance_variable_get(n) }
P = "C:/Users/Qyxay/Documents/RPGXP/Project1/Data"
O = "C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data"

def cmp_cmdlist(l1, l2)
  return "命令条数不同: #{l1.size} vs #{l2.size}" unless l1.size == l2.size
  diffs = []
  l1.each_with_index do |c, i|
    c2 = l2[i]
    unless c.instance_variable_get(:@code) == c2.instance_variable_get(:@code) &&
           c.instance_variable_get(:@parameters) == c2.instance_variable_get(:@parameters)
      diffs << "  命令#{i}: P=#{c.instance_variable_get(:@code)}#{c.instance_variable_get(:@parameters).inspect[0,60]} vs O=#{c2.instance_variable_get(:@code)}#{c2.instance_variable_get(:@parameters).inspect[0,60]}"
    end
  end
  diffs.empty? ? nil : diffs.first(8)
end

def cmp_map(p, o, name)
  m1 = Marshal.load(File.binread(p)); m2 = Marshal.load(File.binread(o))
  iv = ->(o,n){ o.instance_variable_get(n) }
  puts "== #{name} =="
  puts "tileset_id: P=#{iv.call(m1,:@tileset_id)} O=#{iv.call(m2,:@tileset_id)}"
  puts "size: P=#{iv.call(m1,:@width)}x#{iv.call(m1,:@height)} O=#{iv.call(m2,:@width)}x#{iv.call(m2,:@height)}"
  d1 = iv.call(m1,:@data); d2 = iv.call(m2,:@data)
  tile_diff = 0; firsts = []
  (0...d1.xsize).each { |x| (0...d1.ysize).each { |y| (0...d1.zsize).each { |z|
    a = d1[x,y,z]; b = d2[x,y,z]
    if a != b
      tile_diff += 1
      firsts << "  (#{x},#{y},z#{z}): P=#{a} O=#{b}" if firsts.size < 6
    end
  } } }
  puts "tile 差异数: #{tile_diff}"
  firsts.each { |f| puts f }
  e1 = iv.call(m1,:@events); e2 = iv.call(m2,:@events)
  puts "事件数: P=#{e1.size} O=#{e2.size}"
  (e1.keys | e2.keys).sort.each do |k|
    a = e1[k]; b = e2[k]
    if a.nil? || b.nil?
      puts "  事件#{k}: 仅一侧存在"; next
    end
    diffs = []
    diffs << "名字 #{iv.call(a,:@name).inspect} vs #{iv.call(b,:@name).inspect}" if iv.call(a,:@name) != iv.call(b,:@name)
    diffs << "坐标 #{iv.call(a,:@x)},#{iv.call(a,:@y)} vs #{iv.call(b,:@x)},#{iv.call(b,:@y)}" if iv.call(a,:@x) != iv.call(b,:@x) || iv.call(a,:@y) != iv.call(b,:@y)
    pa = iv.call(a,:@pages); pb = iv.call(b,:@pages)
    diffs << "页数 #{pa.size} vs #{pb.size}" if pa.size != pb.size
    if pa.size == pb.size
      pa.each_with_index do |pg, i|
        pg2 = pb[i]
        tr = iv.call(pg,:@trigger); tr2 = iv.call(pg2,:@trigger)
        diffs << "  页#{i} trigger #{tr} vs #{tr2}" if tr != tr2
        r = cmp_cmdlist(iv.call(pg,:@list)||[], iv.call(pg2,:@list)||[])
        diffs << "  页#{i} 命令: #{r}" if r
      end
    end
    puts "  事件#{k}: #{diffs.join('; ')}" unless diffs.empty?
  end
end

cmp_map("#{P}/Map002.rxdata", "#{O}/Map002.rxdata", "Map002 (Start)")
