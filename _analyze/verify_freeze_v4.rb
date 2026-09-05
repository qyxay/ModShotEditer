ROOT = File.expand_path('..', __dir__)
# ============================================================
#  临时验证 v4: Game_Player 触发拦截补丁
#  用真实 Game_Character/Game_Event/Game_Player 源码
# ============================================================

$LOAD_PATH.unshift("#{ROOT}/runtime/lib/ruby/3.1.0")
$LOAD_PATH.unshift("#{ROOT}/runtime/lib/ruby/3.1.0/x64-mingw64")

require 'json'

module RPG
  class EventCommand; end
  class MoveRoute; end
  class MoveCommand; end
  class Event
    class Page; end
    class Page::Condition; end
    class Page::Graphic; end
  end
  class AudioFile; end
end
class Table; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end
class Color; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end
class Tone; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end
class Rect; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end

$game_switches = []
$game_variables = []
$game_self_switches = {}
$game_map = Object.new
def $game_map.map_id; 2; end
def $game_map.passable?(x, y, d, self_event = nil); true; end
def $game_map.events; @evs ||= {}; end
def $game_map.need_refresh; false; end
$game_temp = Object.new
def $game_temp.common_event_id; 0; end
def $game_temp.message_window_showing; false; end
def $game_temp.menus_visible; false; end

module Input
  def self.trigger?(*); false; end
  def self.press?(*); false; end
  def self.dir4; 2; end
end

def tr(s); s; end
$data_system = Object.new
def $data_system.se_play(*); end
def $data_system.decision_se; nil; end
def $data_system.cursor_se; nil; end
def $data_system.cancel_se; nil; end

$game_system = Object.new
def $game_system.se_play(*); end
def $game_system.map_interpreter; @mi ||= Object.new; end
def $game_system.menu_disabled; false; end

class Viewport; attr_accessor :z, :visible; def initialize(*); @visible=true; end; end
class Sprite; attr_accessor :bitmap,:x,:y,:opacity,:visible,:z,:viewport; def initialize(*); @visible=true; end; def dispose; end; end
class Bitmap; attr_accessor :font; class Font; attr_accessor :size; end; def initialize(*); @font=Font.new; end; def width; 0; end; def height; 0; end; def dispose; end; end

# --- load jump_map.rb (含新补丁) ---
load "#{ROOT}/OneShot/mods/mod/Scripts/jump_map.rb"

# --- load 真实 Game_Character / Game_Event / Game_Player ---
3.times do |i|
  load format("#{ROOT}/_scripts_dump/%03d_Game_Character_%d.rb", 18 + i, i + 1)
end
load "#{ROOT}/_scripts_dump/021_Game_Event.rb"

# Game_Player 需要 Game_Follower 依赖吗? 试加载
begin
  load "#{ROOT}/_scripts_dump/022_Game_Player.rb"
  puts "loaded 022_Game_Player"
rescue => e
  puts "022 FAILED: #{e.class}: #{e.message}"
  puts e.backtrace.first(3)
end

puts ""
puts "== 补丁验证 =="
puts "  Game_Event FreezePatch: #{defined?(Game_Event) && Game_Event.ancestors.include?(JumpMapFreezePatch)}"
puts "  Interpreter CommonPatch: #{defined?(Interpreter) && Interpreter.ancestors.include?(JumpMapCommonEventPatch)}"
if defined?(Game_Player)
  puts "  Game_Player PlayerTriggerPatch: #{Game_Player.ancestors.include?(JumpMapPlayerTriggerPatch)}"
  puts "  check_event_trigger_here owner: #{Game_Player.instance_method(:check_event_trigger_here).owner}"
  puts "  check_event_trigger_touch owner: #{Game_Player.instance_method(:check_event_trigger_touch).owner}"
  puts "  check_event_trigger_there owner: #{Game_Player.instance_method(:check_event_trigger_there).owner}"
end
puts ""
puts "DONE"
