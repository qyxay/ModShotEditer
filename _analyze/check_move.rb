# ============================================================
#  模拟: 玩家在 start(地图2) 落点 (15,17) 的四个方向移动可行性
#  用真实 Game_Character / Game_Event 通行性逻辑
# ============================================================

$LOAD_PATH.unshift('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/runtime/lib/ruby/3.1.0')
$LOAD_PATH.unshift('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/runtime/lib/ruby/3.1.0/x64-mingw64')

require 'json'

module RPG
  class Map; end
  class Event; end
  class EventCommand; end
  class MoveRoute; end
  class MoveCommand; end
  class Event
    class Page; end
    class Page::Condition; end
    class Page::Graphic; end
  end
  class AudioFile; end
  class Tileset; end
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
    t.instance_variable_set(:@data, s[4 + dim * 4..].unpack('l*'))
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

module Input
  def self.trigger?(*); false; end
  def self.press?(*); false; end
  def self.dir4; 2; end
end
def tr(s); s; end

$game_switches = []
$game_variables = []
$game_self_switches = {}

# 地图数据
DATA = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data'
def load_map(mid)
  Marshal.load(File.binread(format("#{DATA}/Map%03d.rxdata", mid)))
end
$map = load_map(2)
tilesets = Marshal.load(File.binread("#{DATA}/Tilesets.rxdata"))
$ts = tilesets[$map.instance_variable_get(:@tileset_id)]
$tileset_passages = $ts.instance_variable_get(:@passages)
$map_data = $map.instance_variable_get(:@data)
$map_w = $map.instance_variable_get(:@width)
$map_h = $map.instance_variable_get(:@height)

# --- 桩 Game_Map (真实通行性逻辑) ---
$game_map = Object.new
def $game_map.map_id; 2; end
def $game_map.events
  $game_map_events
end
def $game_map.valid?(x, y)
  x >= 0 && x < $map_w && y >= 0 && y < $map_h
end
def $game_map.passable?(x, y, d, self_event = nil)
  # 目标格
  nx = x + (d == 6 ? 1 : d == 4 ? -1 : 0)
  ny = y + (d == 2 ? 1 : d == 8 ? -1 : 0)
  return false unless valid?(nx, ny)
  # 目标格事件阻挡 (非 through 事件)
  $game_map_events.each_value do |ev|
    if ev.x == nx && ev.y == ny && !ev.through
      return false if self_event != ev
    end
  end
  # tile 通行性
  return false unless terrain_ok(nx, ny)
  true
end
def terrain_ok(x, y)
  [0, 1, 2].each do |z|
    tile = $map_data[x, y, z]
    next if tile == 0
    bits = $tileset_passages[tile]
    return false if bits && (bits & 0x0F) == 0x0F
  end
  true
end
$game_map_events = {}

# --- 真实 Game_Character (前3段) + Game_Event ---
3.times do |i|
  load format('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/_scripts_dump/%03d_Game_Character_%d.rb', 18 + i, i + 1)
end
load 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/_scripts_dump/021_Game_Event.rb'

# --- 创建事件实例 (模拟 Game_Map#setup) ---
$map.instance_variable_get(:@events).each do |id, evdata|
  ev = Game_Event.allocate
  ev.instance_variable_set(:@event, evdata)
  ev.instance_variable_set(:@id, id)
  ev.instance_variable_set(:@erased, false)
  ev.instance_variable_set(:@starting, false)
  ev.instance_variable_set(:@through, true)  # 初始
  ev.instance_variable_set(:@x, evdata.instance_variable_get(:@x))
  ev.instance_variable_set(:@y, evdata.instance_variable_get(:@y))
  # 简化: 用无条件页决定 through
  pages = evdata.instance_variable_get(:@pages)
  page = pages.reverse.find do |pg|
    c = pg.instance_variable_get(:@condition)
    !c.instance_variable_get(:@switch1_valid) &&
    !c.instance_variable_get(:@switch2_valid) &&
    !c.instance_variable_get(:@variable_valid) &&
    !c.instance_variable_get(:@self_switch_valid)
  end
  ev.instance_variable_set(:@through, page ? page.instance_variable_get(:@through) : true)
  ev.instance_variable_set(:@trigger, page ? page.instance_variable_get(:@trigger) : nil)
  $game_map_events[id] = ev
end

# 打印事件位置 + through
puts "== 地图2 事件 (x,y,through) =="
$game_map_events.each do |id, ev|
  puts "  ##{id} @(#{ev.x},#{ev.y}) through=#{ev.through} trigger=#{ev.trigger}"
end

# --- 模拟玩家在 (15,17) 四向移动 ---
$game_player = Object.new
def $game_player.x; 15; end
def $game_player.y; 17; end

puts ""
puts "== 玩家在 (15,17) 的四向通行 =="
DIR = { 2 => '下', 4 => '左', 6 => '右', 8 => '上' }
DIR.each do |d, label|
  # 用真实 Game_Character 的 passable? (创建一个临时 char, through=false)
  c = Game_Character.allocate
  c.instance_variable_set(:@through, false)
  c.instance_variable_set(:@x, 15)
  c.instance_variable_set(:@y, 17)
  ok = c.passable?(15, 17, d)
  nx = 15 + (d == 6 ? 1 : d == 4 ? -1 : 0)
  ny = 17 + (d == 2 ? 1 : d == 8 ? -1 : 0)
  blocker = nil
  $game_map_events.each_value do |ev|
    blocker = ev if ev.x == nx && ev.y == ny && !ev.through
  end
  puts "  #{label}(#{d}) -> (#{nx},#{ny}): #{ok ? '可通行' : '不可通行'}#{blocker ? " (被事件#{blocker.instance_variable_get(:@id)}阻挡)" : ''}"
end
