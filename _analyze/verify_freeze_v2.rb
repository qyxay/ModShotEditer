ROOT = File.expand_path('..', __dir__)
# ============================================================
#  临时验证 v2: 用真实 xscripts 源码验证冻结补丁
#  加载顺序与真实一致: 先 load jump_map.rb (TracePoint),
#  再 load 真实的 Game_Character/Game_Event 源码。
# ============================================================

$LOAD_PATH.unshift("#{ROOT}/runtime/lib/ruby/3.1.0")
$LOAD_PATH.unshift("#{ROOT}/runtime/lib/ruby/3.1.0/x64-mingw64")

require 'json'

# --- 数据类桩 (RPG 类) ---
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

# --- 全局桩 ---
$game_switches = []
$game_variables = []
$game_self_switches = {}
$game_map = Object.new
def $game_map.map_id; 4; end
def $game_map.passable?(x, y, d, self_event = nil); true; end
$game_player = Object.new
def $game_player.x; 21; end
def $game_player.y; 10; end
def $game_player.moving?; false; end

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

# Sprite/Bitmap/Viewport 桩 (Game_Event 不直接用到, 但保险)
class Viewport; attr_accessor :z, :visible; def initialize(*); @visible=true; end; end
class Sprite; attr_accessor :bitmap,:x,:y,:opacity,:visible,:z,:viewport; def initialize(*); @visible=true; end; def dispose; end; end
class Bitmap; attr_accessor :font; class Font; attr_accessor :size; end; def initialize(*); @font=Font.new; end; def width; 0; end; def height; 0; end; def dispose; end; end
class Color; def initialize(*); end; end
class Tone; def initialize(*); end; end

SCRIPT = "#{ROOT}/_scripts_dump"

# --- 先 load jump_map.rb (与真实 preload 顺序一致) ---
load "#{ROOT}/OneShot/mods/mod/Scripts/jump_map.rb"

# --- 再 load 真实 Game_Character 和 Game_Event 源码 ---
# (Game_Character 拆成 3 段: 018/019/020)
[:game_char_1, :game_char_2, :game_char_3].each_with_index do |sym, i|
  begin
    load format("#{SCRIPT}/%03d_Game_Character_%d.rb", 18 + i, i + 1)
    puts "loaded Game_Character_#{i+1}"
  rescue => e
    puts "Game_Character_#{i+1} FAILED: #{e.class}: #{e.message}"
    puts e.backtrace.first(3)
  end
end

begin
  load "#{SCRIPT}/021_Game_Event.rb"
  puts "loaded 021_Game_Event"
rescue => e
  puts "021 FAILED: #{e.class}: #{e.message}"
  puts e.backtrace.first(3)
end

# --- 验证 ---
puts ""
puts "== ancestors =="
if defined?(Game_Event)
  puts Game_Event.ancestors.inspect
  puts "JUMPPATCH APPLIED: #{Game_Event.ancestors.include?(JumpMapFreezePatch)}"
  puts "check_event_trigger_auto owner: #{Game_Event.instance_method(:check_event_trigger_auto).owner.inspect}"
else
  puts "Game_Event not defined"
end
