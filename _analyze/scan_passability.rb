ROOT = File.expand_path('..', __dir__)
# ============================================================
#  扫描: 所有可跳地图的落点是否可通行 (mkxp Table 真实解析)
# ============================================================

$LOAD_PATH.unshift("#{ROOT}/runtime/lib/ruby/3.1.0")
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
    # mkxp Table: dim(4B V) + sizes(每维4B V) + data(int32 l*)
    dim = s[0, 4].unpack1('V')
    sizes = dim.times.map { |i| s[4 + i * 4, 4].unpack1('V') }
    t = allocate
    t.instance_variable_set(:@xsize, sizes[0])
    t.instance_variable_set(:@ysize, sizes[1] || 1)
    t.instance_variable_set(:@zsize, sizes[2] || 1)
    data = s[4 + dim * 4..]
    t.instance_variable_set(:@data, data.unpack('l*'))
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

DATA = "#{ROOT}/OneShot/Data"

def load_map(mid)
  Marshal.load(File.binread(format("#{DATA}/Map%03d.rxdata", mid)))
end

# tileset 通行性表
tilesets = Marshal.load(File.binread("#{DATA}/Tilesets.rxdata"))
tileset_passages = {}
tilesets.each_with_index do |t, i|
  next unless t
  pass = t.instance_variable_get(:@passages)
  tileset_passages[i] = pass if pass
end

# 地图一层 tile 的通行性
def terrain_passable(map, tileset_passages, x, y, d)
  ts = map.instance_variable_get(:@tileset_id)
  pass = tileset_passages[ts]
  return true unless pass
  data = map.instance_variable_get(:@data)
  # 3 层
  [0, 1, 2].each do |z|
    tile = data[x, y, z]
    next if tile == 0
    bits = pass[tile]
    return false if bits && (bits & 0x0F) == 0x0F  # 0x0F = 四向全不可通行
    if bits
      # d: 2下 4左 6右 8上 -> bit 位: 下=1, 左=2, 右=4, 上=8
      bit = { 2 => 1, 4 => 2, 6 => 4, 8 => 8 }[d]
      return false if bit && (bits & bit) != 0
    end
  end
  true
end

# 事件是否阻挡
def event_blocker?(ev)
  pages = ev.instance_variable_get(:@pages)
  pages.reverse.each do |pg|
    c = pg.instance_variable_get(:@condition)
    cond_ok = !c.instance_variable_get(:@switch1_valid) &&
              !c.instance_variable_get(:@switch2_valid) &&
              !c.instance_variable_get(:@variable_valid) &&
              !c.instance_variable_get(:@self_switch_valid)
    if cond_ok
      return false  # 无条件页不阻挡 (通过 graphic 判定, 简化为不阻挡)
    end
  end
  false
end

d = JSON.parse(File.read("#{ROOT}/OneShot/mods/mod/jump_points.json"))
FILTER = /IGNORE|DEBUG|INTERNAL|UNUSED|\bTEST\b|^INIT\b|TELEPORT|DEMO|PROTOWALK|PSHOT/i
NAME_PAT = /^[TCS]\d+$/i

bad = []
cands = []
d.each do |id, m|
  next unless m.is_a?(Hash)
  x = m['x'].to_i; y = m['y'].to_i
  next if x < 0 || y < 0
  name = m['name'].to_s
  next if name =~ FILTER
  next if name =~ NAME_PAT
  cands << { id: id.to_i, x: x, y: y, dir: m['dir'].to_i, name: name }
end

cands.each do |c|
  begin
    map = load_map(c[:id])
    # 落点自身可通行? (朝四个方向试探, 检查该格 tile 是否四向全堵)
    self_ok = [2, 4, 6, 8].any? { |dir| terrain_passable(map, tileset_passages, c[:x], c[:y], dir) }
    # 简单判定: 四向全不可通行则视为卡点
    all_blocked = [2, 4, 6, 8].all? { |dir| !terrain_passable(map, tileset_passages, c[:x], c[:y], dir) }
    if all_blocked
      bad << "地图#{c[:id]} '#{c[:name]}' 落点(#{c[:x]},#{c[:y]}) 四向全不可通行(卡点!)"
    end
  rescue => e
    bad << "地图#{c[:id]} '#{c[:name]}' 读取失败: #{e.message}"
  end
end

puts "可跳地图 #{cands.size} 个"
puts ""
puts "== 落点四向全不可通行(跳转即卡) =="
bad.each { |b| puts b }
puts ""
puts "卡点数量: #{bad.size}"
