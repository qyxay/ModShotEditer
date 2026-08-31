require_relative 'oneshot_data'

$LOAD_PATH.unshift('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/runtime/lib/ruby/3.1.0')

module Input
  def self.trigger?(*); false; end
  def self.press?(*); false; end
  def self.dir4; 2; end
end
def tr(s); s; end
class Viewport; attr_accessor :z, :visible; def initialize(*); @visible = true; end; end
class Sprite; attr_accessor :bitmap, :x, :y, :opacity, :visible, :z, :viewport; def initialize(*); @visible = true; end; def dispose; end; end
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
$game_switches = {}
$game_variables = {}
$game_self_switches = {}
$mod_config = { 'is_developer' => true }
class Window_Settings
  MARGIN = 30; TITLE_MARGIN = 100; TITLE_TOP_MARGIN = 32; ITEM_SPACING = 28
  def open; end
  def update; end
  def dispose; end
end
load 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/mods/mod/Scripts/dev_settings.rb'

[120, 225].each do |mid|
  map = os_load_map(mid)
  class FakeMapEvent
    attr_reader :event
    def initialize(ev); @event = ev; end
    def refresh; end
    def id; @event.id; end
  end
  fake_events = {}
  map.instance_variable_get(:@events).each { |id, evd| fake_events[id] = FakeMapEvent.new(evd) }
  fake_map = Object.new
  def fake_map.events; @evs ||= {}; end
  def fake_map.map_id; @mid; end
  fake_map.instance_variable_set(:@evs, fake_events)
  fake_map.instance_variable_set(:@mid, mid)

  $game_map = fake_map
  ds = Window_DevSettings.new
  info = ds.current_map_switch_info
  puts "地图#{mid} 激活类: #{info[:activate].sort.inspect}"
  puts "地图#{mid} 关闭类: #{info[:close_only].sort.inspect}"
  puts "  SW22(south exit 传送条件) 在激活类? = #{info[:activate].include?(22)}"
  puts ""
end
