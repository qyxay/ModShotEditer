# ============================================================
#  验证 Window_UnlockComplete(可编辑版 v2)界面逻辑(桩环境):
#  - 打开定位到当前所在地图页(页0=物品页)
#  - 地图页 Doors/Events 分组, 无条件门显示 [–] 不可编辑
#  - toggle_door(east door sw7) / toggle_event(niko hello 自开关) /
#    toggle_item 状态切换生效
# ============================================================
$LOAD_PATH.unshift('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/runtime/lib/ruby/3.1.0')
require_relative 'oneshot_data'
module RPG
  class Map
    attr_accessor :events
  end
  class MapInfo
    attr_accessor :name, :parent_id
  end
  class Item
    attr_accessor :name, :icon_index, :description, :price, :occasion, :scope, :menu_se
  end
end

# 模拟 jump_map.rb 常量
JUMP_POINTS_PATH = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/mods/mod/jump_points.json'
JUMP_MAP_FILTER = /IGNORE|DEBUG|INTERNAL|UNUSED|\bTEST\b|^INIT\b|TELEPORT|DEMO|PROTOWALK|PSHOT|LANGUAGE\s?DEBUG|LANG\s?DEBUG/i
JUMP_MAP_NAME_PATTERN = /^[TCS]\d+$/i
JUMP_MAP_PARENT_FILTER = /IGNORE|DEBUG|UNUSED|INTERNAL|\bTEST\b|^INIT\b|TELEPORT/i

DATA2 = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data'
def load_data(name)
  base = File.basename(name)
  Marshal.load(File.binread(File.join(DATA2, base)))
end

# ---- UI 桩 ----
class Viewport
  attr_accessor :z, :visible
  def initialize(*); @visible = true; end
end
class Font
  attr_accessor :size
  def initialize; @size = 20; end
end
class Bitmap
  attr_accessor :font
  def initialize(*); @font = Font.new; end
  def draw_text(*); end
  def clear; end
  def fill_rect(*); end
  def width; 500; end
  def height; 24; end
  def dispose; end
end
class Sprite
  attr_accessor :bitmap, :x, :y, :opacity, :z, :viewport, :visible
  def initialize(*); @visible = true; @opacity = 255; end
  def dispose; end
end
class Color
  def initialize(*); end
end
module Input
  LEFT = 0; RIGHT = 1; UP = 2; DOWN = 3; ACTION = 4; CANCEL = 5
  @@t = {}
  def self.trigger?(k); @@t[k]; end
  def self.press(k); @@t[k] = true; end
  def self.release_all; @@t = {}; end
end

$game_system = Object.new
def $game_system.se_play(*); end
$data_system = Object.new
def $data_system.decision_se; end
def $data_system.cursor_se; end
def $data_system.cancel_se; end
def tr(s); s; end

# ---- 运行时状态桩 ----
$game_switches = []
$game_variables = []
$game_self_switches = {}
$game_party = Object.new
$ITEMS = {}
def $game_party.item_number(id); $ITEMS[id] || 0; end
def $game_party.gain_item(id, n); $ITEMS[id] = ($ITEMS[id] || 0) + n; end
def $game_party.lose_item(id, n); $ITEMS[id] = [($ITEMS[id] || 0) - n, 0].max; end

# Game_Event 桩: 包装真实 RPG::Event
class GameEventStub
  attr_accessor :id, :x, :y
  def initialize(ev, id)
    @event = ev
    @id = id
  end
  def refresh; end
end

# 当前所在地图 = 4, events 用真实地图4数据包装
$game_map = Object.new
def $game_map.map_id; 4; end
def $game_map.events
  @evs ||= begin
    m = load_data(format('Data/Map%03d.rxdata', 4))
    h = {}
    (m.events || {}).each { |id, ev| h[id] = GameEventStub.new(ev, id) }
    h
  end
end
def $game_map.refresh; end

load 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/mods/mod/Scripts/unlock_or_complete.rb'

failures = []
w = Window_UnlockComplete.new
w.open
pages = w.instance_variable_get(:@pages)
page_map4 = pages.index { |p| p[:type] == :map && p[:id] == 4 }
puts "  页数: #{pages.size} (含物品页0)"
puts "  打开定位: 地图4 → page=#{w.instance_variable_get(:@page)} (期望 #{page_map4})"
failures << '打开应定位地图4页' unless w.instance_variable_get(:@page) == page_map4

# 地图4页: Doors 分组 + Events 分组
rows = w.instance_variable_get(:@rows)
labels = rows.map { |r| r[:label] }
failures << '应有 Doors 分组' unless rows.any? { |r| r[:type] == :head && r[:label] =~ /Doors/ }
failures << '应有 Events 分组' unless rows.any? { |r| r[:type] == :head && r[:label] =~ /Events/ }

# --- 无条件门(north door ev1): 应显示 [–] 且不可编辑 ---
nd = rows.find { |r| r[:type] == :item && r[:label] =~ /north door/ }
failures << '应含 north door' unless nd
if nd
  puts "  north door(无条件): state=#{nd[:state]} act=#{nd[:act].inspect}"
  failures << '无条件门应显示 [–]' unless nd[:state].to_s =~ /–|‑|-/
  failures << '无条件门不可编辑(act=nil)' unless nd[:act].nil?
end

# --- toggle_door: east door(ev2, 命令内 111 sw7, 直接翻转) ---
ed = rows.find { |r| r[:type] == :item && r[:label] =~ /east door/ }
failures << '应含 east door' unless ed
if ed
  puts "  east door 初始: state=#{ed[:state]} (sw7=#{$game_switches[7].inspect}, 期望 sw7 = OFF)"
  failures << 'east door 初始应显示 sw7 = OFF' unless ed[:state].to_s =~ /sw7 = OFF/
  w.send(:toggle_door, 2)
  w.send(:refresh_page)
  rows2 = w.instance_variable_get(:@rows)
  ed2 = rows2.find { |r| r[:type] == :item && r[:label] =~ /east door/ }
  puts "  toggle_door east door → sw7=#{$game_switches[7].inspect} state=#{ed2 && ed2[:state]}"
  failures << 'east door 切换应置 sw7=true' unless $game_switches[7] == true
  failures << 'east door 切换后应显示 sw7 = ON' unless ed2 && ed2[:state].to_s =~ /sw7 = ON/
  w.send(:toggle_door, 2)
  w.send(:refresh_page)
  puts "  toggle_door east door 再切 → sw7=#{$game_switches[7].inspect}"
  failures << 'east door 再切应恢复 sw7=false' unless $game_switches[7] == false
end

# --- toggle_event: niko hello(ev17, 自开关 ssA 直接翻转) ---
rows = w.instance_variable_get(:@rows)
nik = rows.find { |r| r[:type] == :item && r[:label] == 'niko hello' }
failures << '应含 niko hello' unless nik
if nik
  puts "  niko hello 初始: state=#{nik[:state]}"
  w.send(:toggle_event, 17)
  w.send(:refresh_page)
  ss = $game_self_switches[[4, 17, 'A']]
  rows2 = w.instance_variable_get(:@rows)
  nik2 = rows2.find { |r| r[:type] == :item && r[:label] == 'niko hello' }
  puts "  toggle_event niko hello → ssA=#{ss.inspect} state=#{nik2 && nik2[:state]}"
  failures << 'toggle_event 应置 ssA=true' unless ss == true
  failures << 'niko hello 应显示 ssA = on' unless nik2 && nik2[:state].to_s =~ /ssA = on/
  w.send(:toggle_event, 17)
  w.send(:refresh_page)
  puts "  toggle_event niko hello 再切 → ssA=#{$game_self_switches[[4, 17, 'A']].inspect}"
  failures << 'toggle_event 再切应恢复 ssA=false' unless $game_self_switches[[4, 17, 'A']] == false
end

# --- 事件状态: 无条件对话事件显示 [–] ---
rows = w.instance_variable_get(:@rows)
plain = rows.find { |r| r[:type] == :item && r[:label] =~ /window light/ }
if plain
  puts "  window light(无条件): state=#{plain[:state]} act=#{plain[:act].inspect}"
  failures << '无条件事件应 [–] 不可编辑' unless plain[:act].nil?
end

# --- 物品页: 连续 LEFT 翻到页0 ---
w.send(:refresh_page)
3.times do
  Input.press(Input::LEFT)
  w.update
  Input.release_all
end
puts "  LEFT×3 翻页 → page=#{w.instance_variable_get(:@page)}"
failures << 'LEFT 应到物品页' unless w.instance_variable_get(:@page) == 0
rows = w.instance_variable_get(:@rows)
failures << '物品页应有物品条目' unless rows.any? { |r| r[:type] == :item }
light = rows.index { |r| r[:type] == :item && r[:label] == 'lightbulb' }
failures << '物品页应含 lightbulb' unless light
if light
  w.send(:toggle_item, 1)
  puts "  toggle_item lightbulb → 拥有数: #{$game_party.item_number(1)}"
  failures << 'toggle_item 应获得物品' unless $game_party.item_number(1) > 0
end

puts ""
if failures.empty?
  puts "result = ALL PASS"
else
  puts "FAIL:"
  failures.each { |f| puts "  - #{f}" }
  exit 1
end
