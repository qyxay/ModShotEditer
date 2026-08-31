# ============================================================
#  临时验证: jump_map.rb 的冻结补丁(TracePoint prepend)是否生效
#  场景: load jump_map.rb 时 Game_Event 尚未定义(与真实加载顺序一致)
# ============================================================

$LOAD_PATH.unshift('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/runtime/lib/ruby/3.1.0')
$LOAD_PATH.unshift('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/runtime/lib/ruby/3.1.0/x64-mingw64')

require 'json'
def tr(s); s; end

# --- RGSS 桩 ---
class Viewport
  attr_accessor :z, :visible
  def initialize(*); @visible = true; end
end
class Sprite
  attr_accessor :bitmap, :x, :y, :opacity, :visible, :z, :viewport
  def initialize(vp=nil); @viewport=vp; @visible=true; end
  def dispose; end
end
class Bitmap
  attr_accessor :font
  class Font; attr_accessor :size; end
  def initialize(w,h); @font=Font.new; @w=w; @h=h; end
  def width; @w; end
  def height; @h; end
  def fill_rect(*); end
  def clear; end
  def draw_text(*); end
  def dispose; end
end
class Color; def initialize(*); end; end
class Tone; def initialize(*); end; end

$game_system = Object.new
def $game_system.se_play(*); end
def $game_system.map_interpreter; @mi ||= Object.new; end
$data_system = Object.new
def $data_system.decision_se; nil; end
def $data_system.cursor_se; nil; end
def $data_system.cancel_se; nil; end

module Input
  def self.trigger?(*); false; end
  def self.press?(*); false; end
  UP=0;DOWN=1;ACTION=2;LEFT=3;RIGHT=4;CANCEL=5
end

# --- 先 load jump_map.rb (此时 Game_Event 尚未定义, TracePoint 建立监听) ---
load 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/mods/mod/Scripts/jump_map.rb'

# --- 之后再定义 Game_Event (模拟 Data/Scripts.rxdata 定义时) ---
class Game_Event
  attr_accessor :trigger, :starting
  def initialize
    @starting = false
    @trigger = 3   # AUTORUN
  end
  def check_event_trigger_auto
    @starting = true   # 原版行为: autorun 会 start
  end
end

# --- 验证 1: 补丁是否 prepend 成功 ---
puts "== 验证 1: TracePoint prepend =="
puts "  ancestors = #{Game_Event.ancestors.inspect}"
if Game_Event.ancestors.include?(JumpMapFreezePatch)
  puts "  PATCH APPLIED OK"
else
  puts "  ** PATCH NOT APPLIED **"
end

# --- 验证 2: 冻结行为 ---
puts ""
puts "== 验证 2: 冻结行为 =="
$jump_map_free_mode = true
$jump_map_frozen_map_id = 4
$game_map = Object.new
def $game_map.map_id; 4; end

e = Game_Event.new
e.trigger = 3
e.check_event_trigger_auto
puts "  AUTORUN in frozen map: starting=#{e.starting.inspect} (期望 false=被冻结)"
puts ($jump_map_free_mode && e.starting == false ? "  FREEZE OK" : "  ** FREEZE FAILED **")

# --- 验证 3: 非冻结地图行为 ---
$jump_map_frozen_map_id = 999
e2 = Game_Event.new
e2.trigger = 3
e2.check_event_trigger_auto
puts "  AUTORUN in other map: starting=#{e2.starting.inspect} (期望 true=正常触发)"
puts (e2.starting == true ? "  NORMAL OK" : "  ** NORMAL FAILED **")

# --- 验证 4: 非 autorun(trigger==4 parallel)不受冻结 ---
$jump_map_frozen_map_id = 4
e3 = Game_Event.new
e3.trigger = 4
e3.check_event_trigger_auto
puts "  PARALLEL in frozen map: starting=#{e3.starting.inspect} (期望 true=并行不受冻结)"
puts (e3.starting == true ? "  PARALLEL OK" : "  ** PARALLEL FAILED **")

puts ""
puts "DONE"
