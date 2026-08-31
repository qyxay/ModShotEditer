# ============================================================
#  验证 dev_settings.rb 新逻辑 (当前地图开关 激活/关闭 分类)
#  用真实地图225(瞭望甲板) 数据
# ============================================================

$LOAD_PATH.unshift('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/runtime/lib/ruby/3.1.0')
$LOAD_PATH.unshift('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/runtime/lib/ruby/3.1.0/x64-mingw64')

require 'json'

# --- 真实数据所需 RPG 类 + Table (oneshot_data 复用) ---
require_relative 'oneshot_data'

module Input
  def self.trigger?(*); false; end
  def self.press?(*); false; end
  def self.dir4; 2; end
end
def tr(s); s; end

# --- 游戏环境 stub ---
class Viewport
  attr_accessor :z, :visible
  def initialize(*); @visible = true; end
end
class Sprite
  attr_accessor :bitmap, :x, :y, :opacity, :visible, :z, :viewport
  def initialize(*); @visible = true; end
  def dispose; end
end
class Bitmap
  attr_accessor :font
  class Font; attr_accessor :size; end
  def initialize(*); @font = Font.new; end
  def width; 0; end
  def height; 0; end
  def clear; end
  def fill_rect(*); end
  def draw_text(*); end
  def dispose; end
end
class Color; def self._load(s); allocate; end; def _dump(*); "\x00" * 4; end; def initialize(*); end; end
class Tone; def self._load(s); allocate; end; def _dump(*); "\x00" * 4; end; end
class Rect; def self._load(s); allocate; end; def _dump(*); "\x00" * 4; end; end
class Font; end

$game_switches = {}
$game_variables = {}
$game_self_switches = {}
$mod_config = { 'is_developer' => true }

# Window_Settings 桩 (TracePoint 要监听)
class Window_Settings
  MARGIN = 30; TITLE_MARGIN = 100; TITLE_TOP_MARGIN = 32; ITEM_SPACING = 28
  def open; end
  def update; end
  def dispose; end
end

# 加载 dev_settings.rb
load 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/mods/mod/Scripts/dev_settings.rb'

# --- 用真实地图数据构造桩 $game_map ---
map = os_load_map(225)
class FakeMapEvent
  attr_reader :event
  def initialize(ev)
    @event = ev
  end
  def refresh; end
end
fake_events = {}
map.instance_variable_get(:@events).each do |id, evdata|
  fake_events[id] = FakeMapEvent.new(evdata)
end
fake_map = Object.new
def fake_map.events
  @evs ||= {}
end
def fake_map.map_id
  225
end
fake_map.instance_variable_set(:@evs, fake_events)

ds = Window_DevSettings.new
$game_map = fake_map

# --- 验证 current_map_switch_info ---
info = ds.current_map_switch_info
act = info[:activate].sort
close = info[:close_only].sort
puts "== 地图225 开关分类 =="
puts "  激活类: #{act.inspect}"
puts "  关闭类: #{close.inspect}"
puts "  断言: 激活类含296(出口可用) = #{act.include?(296)}"
puts "  断言: 激活类不含301(出口已用) = #{!act.include?(301)}"
puts "  断言: 关闭类含301 = #{close.include?(301)}"
puts "  断言: 关闭类不含296 = #{!close.include?(296)}"

# --- 验证 set_current_switches(:unlock) ---
$game_switches = {}
n = ds.set_current_switches(:unlock)
puts ""
puts "== unlock 后开关状态 =="
puts "  激活类数量: #{n}"
puts "  SW296 = #{$game_switches[296]} (期望 true)"
puts "  SW301 = #{$game_switches[301]} (期望 false/nil)"
puts "  SW297 = #{$game_switches[297].inspect}"

# --- 验证 set_current_switches(:lock) ---
ds.set_current_switches(:lock)
puts ""
puts "== lock 后开关状态 =="
puts "  SW296 = #{$game_switches[296].inspect} (期望 false)"
puts "  SW301 = #{$game_switches[301].inspect} (期望 false)"

# --- 验证 safe_completion_page? ---
puts ""
puts "== safe_completion_page? (地图225) =="
map225_evs = map.instance_variable_get(:@events)
balcony = map225_evs[14]  # balcony 事件
puts "  balcony SSA 页(trigger 3 AUTORUN) 安全? = #{ds.safe_completion_page?(balcony.pages[1])} (期望 false)"
# 找一个触发0空页
ev001 = map225_evs[1]
puts "  EV001 页1(trigger 0 空页) 安全? = #{ds.safe_completion_page?(ev001.pages[1])} (期望 true)"

# --- 完整模拟: complete_all_dialogues ---
puts ""
puts "== complete_all_dialogues (地图225) =="
# 用真实 Game_Event 包装 (find_self_switch_page 需要 @event)
class RealEvWrapper
  attr_reader :event
  def initialize(evd); @event = evd; end
  def id; @event.id; end
  def refresh; end
end
real_events = {}
map225_evs.each { |id, evd| real_events[id] = RealEvWrapper.new(evd) }
fake_map.instance_variable_set(:@evs, real_events)
ds.complete_all_dialogues
puts "  (完成对话, 无崩溃)"

# --- 完整模拟: complete_all_story ---
puts ""
puts "== complete_all_story (地图225) =="
$game_switches = {}
$game_self_switches = {}
ds.complete_all_story
puts "  SW296 = #{$game_switches[296].inspect} (期望 true, 出口可用)"
puts "  SW301 = #{$game_switches[301].inspect} (期望 false, 门不关死)"
puts "  balcony SSA 自开关 = #{$game_self_switches[[225, 14, 'A']].inspect} (期望 nil, 跳过 AUTORUN)"

puts ""
puts "DONE"
