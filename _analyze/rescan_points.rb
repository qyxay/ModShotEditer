# 全量重扫 jump_points.json: 用 RMXP 通行判定逻辑为每张地图找安全落点
# 用法: cd OneShot; ruby _analyze/rescan_points.rb
require 'json'

# 顶层 Table (mkxp/RGSS 地图数据)
class Table
  def initialize(x, y = 1, z = 1)
    @dim = 1 + (y > 1 ? 1 : 0) + (z > 1 ? 1 : 0)
    @x_size, @y_size, @z_size = x, y, z
    @data = Array.new(x * y * z, 0)
  end
  def [](x, y = 0, z = 0)
    @data[x + y * @x_size + z * @x_size * @y_size]
  end
  def []=(x, y = 0, z = 0, v)
    @data[x + y * @x_size + z * @x_size * @y_size] = v
  end
  def xsize; @x_size; end
  def ysize; @y_size; end
  def zsize; @z_size; end
  def self._load(s)
    dim, xsize, ysize, zsize, size = s[0, 20].unpack('LLLLL')
    data = s[20, size * 2].unpack('S*')
    table = new(xsize, ysize, zsize)
    table.instance_variable_set(:@data, data)
    table
  end
  def _dump(depth)
    [@dim, @x_size, @y_size, @z_size, @x_size * @y_size * @z_size].pack('LLLLL') +
      @data.pack('S*')
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

# 事件当前页的 tile_id / character_name (取最后一页, 静态近似)
def event_tile_id(ev)
  pg = ev.pages && ev.pages.last
  pg && pg.graphic ? pg.graphic.tile_id : 0
end
def event_char(ev)
  pg = ev.pages && ev.pages.last
  pg && pg.graphic ? pg.graphic.character_name.to_s : ''
end

# 模拟 Game_Map#passable?(x, y, d): 检查 (x,y) 朝 d 方向是否可行
def passable?(map, passages, priorities, x, y, d)
  return false if x < 0 || y < 0 || x >= map.width || y >= map.height
  bit = d == 0 ? 0 : (1 << (d / 2 - 1)) & 0x0f
  # 事件阻挡
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
  # 图层
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

# 某格是否适合做落点: 至少 3 个方向可通行
def good_spot?(map, passages, priorities, x, y)
  dirs = [2, 4, 6, 8]
  ok = dirs.count { |d| passable?(map, passages, priorities, x, y, d) }
  ok >= 3
end

result = {}
infos.each do |id, info|
  next if id == 0 || info.nil?
  map = begin
    load_data(sprintf('Data/Map%03d.rxdata', id))
  rescue StandardError
    next
  end
  tileset = tilesets[map.tileset_id]
  next unless tileset
  passages = tileset.passages
  priorities = tileset.priorities
  w = map.width
  h = map.height
  next if w == 0 || h == 0

  # 搜索顺序: 地图中部环形向外扩展
  spot = nil
  cx = w / 2
  cy = h / 2
  max_r = [w, h].max
  (0..max_r).each do |r|
    found = nil
    # 扫描当前环带 (宽松版: 直接全图扫描更可靠, 但优先中部)
    x0 = [cx - r, 0].max
    x1 = [cx + r, w - 1].min
    y0 = [cy - r, 0].max
    y1 = [cy + r, h - 1].min
    (y0..y1).each do |yy|
      (x0..x1).each do |xx|
        if good_spot?(map, passages, priorities, xx, yy)
          found = [xx, yy]
          break
        end
      end
      break if found
    end
    if found
      spot = found
      break
    end
  end

  # 退路: 只要求单格可站(任一方向)
  if spot.nil?
    (0...h).each do |yy|
      (0...w).each do |xx|
        if passable?(map, passages, priorities, xx, yy, 2) ||
           passable?(map, passages, priorities, xx, yy, 6)
          spot = [xx, yy]
          break
        end
      end
      break if spot
    end
  end

  next unless spot
  result[id.to_s] = { 'name' => info.name.to_s, 'x' => spot[0], 'y' => spot[1], 'dir' => 2 }
end

out = JSON.pretty_generate(result)
File.write('mods/mod/jump_points.json', out)
puts "wrote #{result.size} maps"
# 打印几个关键图
%w[120 225 23 110 64 4].each do |k|
  puts "map #{k}: #{result[k].inspect}" if result[k]
end
