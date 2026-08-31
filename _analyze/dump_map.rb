# -*- coding: utf-8 -*-
# 用 modshot runtime ruby 解析 OneShot 地图事件
# 用法: ruby dump_map.rb Map004 [maxpages]

# --- RGSS 扩展类 (供 Marshal.load 还原) ---
class Tone
  attr_accessor :red, :green, :blue, :gray
  def initialize(r = 0, g = 0, b = 0, gray = 0)
    @red = r; @green = g; @blue = b; @gray = gray
  end
  def _dump(depth)
    [@red, @green, @blue, @gray].pack('d4')
  end
  def self._load(s)
    r, g, b, gr = s.unpack('d4')
    new(r, g, b, gr)
  end
end

class Color
  attr_accessor :red, :green, :blue, :alpha
  def initialize(r = 0, g = 0, b = 0, a = 255)
    @red = r; @green = g; @blue = b; @alpha = a
  end
  def _dump(depth)
    [@red, @green, @blue, @alpha].pack('d4')
  end
  def self._load(s)
    r, g, b, a = s.unpack('d4')
    new(r, g, b, a)
  end
end

class Table
  attr_accessor :dim, :xsize, :ysize, :zsize, :data
  def _dump(depth)
    size = @xsize * @ysize * @zsize
    [@dim, @xsize, @ysize, @zsize, size].pack('L5') + @data.pack('l*')
  end
  def self._load(s)
    dim, xs, ys, zs, size = s.unpack('L5')
    t = allocate
    t.dim = dim; t.xsize = xs; t.ysize = ys; t.zsize = zs
    t.data = s.byteslice(20, size * 4).unpack('l*')
    t
  end
end

module RPG
  class Map; end
  class Event; end
  class EventCommand; end
  class AudioFile; end
  class MoveRoute; end
  class MoveCommand; end
  class Troop; end
  class CommonEvent; end
  class System; end
end
class RPG::Event::Page; end
class RPG::Event::Page::Condition; end
class RPG::Event::Page::Graphic; end

def iv(obj, name)
  obj.instance_variable_get(name)
end

path = ARGV[0]
data = Marshal.load(File.binread(path))
maps = data.is_a?(Hash) ? data : { 1 => data }
if data.is_a?(RPG::Map)
  maps = { 1 => data }
end

maps.each do |id, map|
  puts "MAP id=#{id} size=#{iv(map,:@width)}x#{iv(map,:@height)}"
  events = iv(map, :@events)
  next unless events
  events.each do |eid, ev|
    name = iv(ev, :@name)
    x = iv(ev, :@x); y = iv(ev, :@y)
    pages = iv(ev, :@pages) || []
    puts "  EV #{eid} name=#{name.inspect} xy=#{x},#{y} pages=#{pages.size}"
    pages.each_with_index do |pg, pi|
      trig = iv(pg, :@trigger)
      lst = iv(pg, :@list) || []
      codes = lst[0, 8].map { |c| [iv(c, :@code), iv(c, :@parameters)] }
      cond = iv(pg, :@condition)
      puts "    pg#{pi} trigger=#{trig} codes=#{codes.inspect}"
    end
  end
end
