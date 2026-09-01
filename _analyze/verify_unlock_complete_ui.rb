# ============================================================
#  验证 Window_UnlockComplete(可编辑版)界面逻辑(桩环境):
#  - 打开定位到当前所在地图页(页0=物品页)
#  - 地图页渲染 Doors/Events 分组
#  - toggle_door / toggle_event / toggle_item 状态切换生效
#  - 物品页渲染与切换
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
_map4 = load_data(format('Data/Map%03d.rxdata', 4))
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

# 地图4页: 应有 Doors 分组 + Events 分组
rows = w.instance_variable_get(:@rows)
labels = rows.map { |r| r[:label] }
puts "  地图4行: #{rows.size} (Doors=#{rows.count { |r| r[:type] == :head && r[:label] =~ /Doors/ }}, Events=#{rows.count { |r| r[:type] == :head && r[:label] =~ /Events/ }})"
failures << '应有 Doors 分组' unless rows.any? { |r| r[:type] == :head && r[:label] =~ /Doors/ }
failures << '应有 Events 分组' unless rows.any? { |r| r[:type] == :head && r[:label] =~ /Events/ }
failures << '应含 north door 门' unless rows.any? { |r| r[:type] == :item && r[:label] =~ /north door/ }

# toggle_event: 选可完成事件 niko hello(ev17, 有自开关页) → 确认 → 自开关置 true
nik = rows.index { |r| r[:type] == :item && r[:label] == 'niko hello' }
failures << '应含 niko hello 事件' unless nik
if nik
  w.send(:toggle_event, 17)
  done = %w[A B C D].any? { |ch| $game_self_switches[[4, 17, ch]] }
  puts "  toggle_event niko hello → 自开关: #{$game_self_switches.inspect} done=#{done}"
  failures << 'toggle_event 应完成事件' unless done
  # 再切回未完成
  w.send(:toggle_event, 17)
  done2 = %w[A B C D].any? { |ch| $game_self_switches[[4, 17, ch]] }
  failures << 'toggle_event 应可切回未完成' if done2
end

# toggle_door: north door(ev1) 初始(通行条件开关未置) → 切换后通行
w.send(:toggle_door, 1)
pass_state = w.send(:door_row_state, 4, 1)
puts "  toggle_door north door → 状态: #{pass_state}"
# 反转再切回
w.send(:toggle_door, 1)

# 物品页: 连续 LEFT 翻到页0
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
