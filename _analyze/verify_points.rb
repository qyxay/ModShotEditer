# 验证 jump_points.json 落点可通行性(复用扫描器完整类定义)
require 'json'

class Table
  def initialize(x, y = 1, z = 1)
    @dim = 1 + (y > 1 ? 1 : 0) + (z > 1 ? 1 : 0)
    @x_size, @y_size, @z_size = x, y, z
    @data = Array.new(x * y * z, 0)
  end
  def [](x, y = 0, z = 0); @data[x + y * @x_size + z * @x_size * @y_size]; end
  def xsize; @x_size; end
  def ysize; @y_size; end
  def zsize; @z_size; end
  def self._load(s)
    dim, xsize, ysize, zsize, size = s[0, 20].unpack('LLLLL')
    table = new(xsize, ysize, zsize)
    table.instance_variable_set(:@data, s[20, size * 2].unpack('S*'))
    table
  end
end
module RPG
  class MapInfo; attr_accessor :name, :parent_id, :order; end
  class Map; attr_accessor :width, :height, :data, :events, :tileset_id; end
  class Event; attr_accessor :id, :x, :y, :name, :pages; end
  class Event::Page; attr_accessor :x, :y, :condition, :list, :graphic; end
  class Event::Page::Condition; end
  class Event::Page::Graphic
    attr_accessor :tile_id, :character_name, :character_hue, :direction,
                  :pattern, :opacity, :blend_type
  end
  class EventCommand; end
  class MoveRoute; end
  class MoveCommand; end
  class Tileset
    attr_accessor :id, :name, :tileset_name, :autotile_names, :panorama_name,
                  :panorama_hue, :fog_name, :fog_hue, :fog_opacity, :fog_blend_type,
                  :fog_zoom, :fog_sx, :fog_sy, :battleback_name, :passages,
                  :priorities, :terrain_tags
  end
  class CommonEvent; end
  class Actor; end
  class Skill; end
  class Item; end
  class Weapon; end
  class Armor; end
  class Enemy; end
  class Troop; end
  class Troop::Page; end
  class Troop::Page::Condition; end
  class State; end
  class Animation; end
  class Animation::Frame; end
  class Animation::Timing; end
  class System; end
  class System::Words; end
  class AudioFile; end
  class Switch; end
  class Variable; end
end
def load_data(path)
  File.open(path, 'rb') { |f| Marshal.load(f) }
end

infos = load_data('Data/MapInfos.rxdata')
tilesets = load_data('Data/Tilesets.rxdata')

def event_tile_id(ev)
  pg = ev.pages && ev.pages.last
  pg && pg.graphic ? pg.graphic.tile_id : 0
end
def event_char(ev)
  pg = ev.pages && ev.pages.last
  pg && pg.graphic ? pg.graphic.character_name.to_s : ''
end
def passable?(map, passages, priorities, x, y, d)
  return false if x < 0 || y < 0 || x >= map.width || y >= map.height
  bit = d == 0 ? 0 : (1 << (d / 2 - 1)) & 0x0f
  map.events.each_value do |ev|
    next unless ev
    next unless ev.x == x && ev.y == y
    tile_id = event_tile_id(ev)
    next unless tile_id && tile_id >= 0
    if tile_id == 0 && event_char(ev).empty?
      return false
    elsif passages[tile_id] & bit != 0
      return false
    elsif passages[tile_id] & 0x0f == 0x0f
      return false
    elsif priorities[tile_id] == 0
      return true
    end
  end
  blank = 0
  [2, 1, 0].each do |i|
    tile_id = map.data[x, y, i]
    next if tile_id.nil?
    if tile_id < 48 && i > 0
      blank += 1
      next if blank < 3
    end
    if passages[tile_id] & bit != 0
      return false
    elsif passages[tile_id] & 0x0f == 0x0f
      return false
    elsif priorities[tile_id] == 0
      return true
    end
  end
  true
end

jp = JSON.parse(File.read('mods/mod/jump_points.json'))
bad = []
checked = 0
jp.each do |id, m|
  map = begin
    load_data(sprintf('Data/Map%03d.rxdata', id.to_i))
  rescue StandardError => e
    bad << "map #{id}: #{e.class}: #{e.message}"
    next
  end
  tileset = tilesets[map.tileset_id]
  next unless tileset
  x, y = m['x'].to_i, m['y'].to_i
  if x < 0 || y < 0 || x >= map.width || y >= map.height
    bad << "map #{id} (#{m['name']}): 越界 (#{x},#{y}) 图#{map.width}x#{map.height}"
    next
  end
  checked += 1
  dirs = [2, 4, 6, 8]
  ok = dirs.count { |d| passable?(map, tileset.passages, tileset.priorities, x, y, d) }
  bad << "map #{id} (#{m['name']}): 落点 (#{x},#{y}) 仅 #{ok}/4 方向可通" if ok < 2
end

puts "检查 #{checked} 个落点"
if bad.empty?
  puts "全部验证通过 (>=2 方向可通)"
else
  puts "发现问题 #{bad.size} 个:"
  puts bad
end
