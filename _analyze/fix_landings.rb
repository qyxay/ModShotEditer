# ============================================================
#  修正 jump_points.json 落点: BFS 移到安全位置
#  安全格: 同格无事件 + tile 至少1方向可通行 + 有效地图内
# ============================================================

ROOT = File.expand_path('..', __dir__)
$LOAD_PATH.unshift(File.join(ROOT, 'runtime', 'lib', 'ruby', '3.1.0'))
require 'json'

module RPG
  class Map; end
  class Event; end
  class EventCommand; end
  class Tileset; end
  class AudioFile; end
  class MoveRoute; end
  class MoveCommand; end
  class Event
    class Page; end
    class Page::Condition; end
    class Page::Graphic; end
  end
end
class Table
  attr_reader :xsize, :ysize, :zsize
  def self._load(s)
    dim = s[0, 4].unpack1('V')
    sizes = dim.times.map { |i| s[4 + i * 4, 4].unpack1('V') }
    t = allocate
    t.instance_variable_set(:@xsize, sizes[0])
    t.instance_variable_set(:@ysize, sizes[1] || 1)
    t.instance_variable_set(:@zsize, sizes[2] || 1)
    # RMXP Table 头 = 5 个 uint32 (dim, 各维 size, cell_count), 之后才是数据。
    # 数据为 uint16 数组。
    # 原实现偏移用 4+dim*4(把 cell_count 当成数据)且按 l*(int32) 解析,
    # 导致 tile 值全部错位、数量减半 —— 通行性判定全部失真。
    t.instance_variable_set(:@data, s[8 + dim * 4..].unpack('v*'))
    t
  end
  def _dump(*); "\x00" * 4; end
  def [](x, y = 0, z = 0)
    @data[x + @xsize * y + @xsize * @ysize * z] || 0
  end
end
class Color; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end
class Tone; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end
class Rect; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end

DATA = File.join(ROOT, 'OneShot', 'Data')
JP = File.join(ROOT, 'OneShot', 'mods', 'mod', 'jump_points.json')

def load_map(mid)
  Marshal.load(File.binread(format("#{DATA}/Map%03d.rxdata", mid)))
end

tilesets = Marshal.load(File.binread("#{DATA}/Tilesets.rxdata"))
tileset_passages = {}
tilesets.each_with_index do |t, i|
  next unless t
  tileset_passages[i] = t.instance_variable_get(:@passages)
end

# 格 (x,y) 朝 d 方向是否可通行 (tile 层)
def dir_passable(map, tileset_passages, x, y, d)
  ts = map.instance_variable_get(:@tileset_id)
  pass = tileset_passages[ts]
  return true unless pass
  data = map.instance_variable_get(:@data)
  [0, 1, 2].each do |z|
    tile = data[x, y, z]
    next if tile == 0
    bits = pass[tile]
    next unless bits
    return false if (bits & 0x0F) == 0x0F
    bit = { 2 => 1, 4 => 2, 6 => 4, 8 => 8 }[d]
    return false if bit && (bits & bit) != 0
  end
  true
end

# 格安全性: 同格无阻挡事件 + 至少1方向可走 + 地图内
def safe_landing?(map, tileset_passages, events, x, y)
  w = map.instance_variable_get(:@width)
  h = map.instance_variable_get(:@height)
  return false if x < 0 || y < 0 || x >= w || y >= h
  # 同格事件: 非 through 且图形非空 视为阻挡(视觉/功能)
  events.each_value do |ev|
    next unless ev.instance_variable_get(:@x) == x && ev.instance_variable_get(:@y) == y
    pages = ev.instance_variable_get(:@pages)
    pages.each do |pg|
      c = pg.instance_variable_get(:@condition)
      cond_ok = !c.instance_variable_get(:@switch1_valid) &&
                !c.instance_variable_get(:@switch2_valid) &&
                !c.instance_variable_get(:@variable_valid) &&
                !c.instance_variable_get(:@self_switch_valid)
      next unless cond_ok
      graphic = pg.instance_variable_get(:@graphic)
      cname = graphic ? graphic.instance_variable_get(:@character_name).to_s : ''
      through = pg.instance_variable_get(:@through)
      if !through && !cname.empty?
        return false  # 有阻挡事件
      end
    end
  end
  # 至少1方向可走
  [2, 4, 6, 8].any? { |d| dir_passable(map, tileset_passages, x, y, d) }
end

d = JSON.parse(File.read(JP))
# 备份
File.write(JP.sub('.json', '.backup.json'), JSON.pretty_generate(d))

FILTER = /IGNORE|DEBUG|INTERNAL|UNUSED|\bTEST\b|^INIT\b|TELEPORT|DEMO|PROTOWALK|PSHOT/i
NAME_PAT = /^[TCS]\d+$/i

changes = []
total = 0
d.each do |id, m|
  next unless m.is_a?(Hash)
  x = m['x'].to_i; y = m['y'].to_i
  name = m['name'].to_s
  next if name =~ FILTER || name =~ NAME_PAT
  next if x < 0 || y < 0
  begin
    map = load_map(id.to_i)
    events = map.instance_variable_get(:@events)
    if safe_landing?(map, tileset_passages, events, x, y)
      total += 1
      next
    end
    # BFS 找最近安全格
    w = map.instance_variable_get(:@width)
    h = map.instance_variable_get(:@height)
    q = [[x, y]]
    visited = { [x, y] => true }
    found = nil
    until q.empty? || found
      cx, cy = q.shift
      if safe_landing?(map, tileset_passages, events, cx, cy)
        found = [cx, cy]
        break
      end
      [[2, 0, 1], [4, -1, 0], [6, 1, 0], [8, 0, -1]].each do |_d, dx, dy|
        nx = cx + dx; ny = cy + dy
        next if nx < 0 || ny < 0 || nx >= w || ny >= h
        next if visited[[nx, ny]]
        visited[[nx, ny]] = true
        q << [nx, ny]
      end
    end
    if found
      m['x'] = found[0]
      m['y'] = found[1]
      changes << "地图#{id} '#{name}' 落点 (#{x},#{y}) -> (#{found[0]},#{found[1]})"
      total += 1
    else
      puts "地图#{id} '#{name}': 未找到安全格(跳过)"
    end
  rescue => e
    puts "地图#{id} '#{name}': 读取失败 #{e.message}"
  end
end

puts "安全落点总数: #{total}/202"
puts ""
puts "== 修正的落点 (#{changes.size}) =="
changes.each { |c| puts c }

File.write(JP, JSON.pretty_generate(d))
puts ""
puts "已写回 jump_points.json (#{d.size} 个地图)"
