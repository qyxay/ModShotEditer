# ============================================================
#  临时验证 v3: 修改后的 jump_map.rb (冻结所有地图 + 公共事件拦截)
#  用真实 Game_Character/Game_Event 源码 + 模拟 Interpreter
# ============================================================

ROOT = File.expand_path('..', __dir__)
$LOAD_PATH.unshift(File.join(ROOT, 'runtime', 'lib', 'ruby', '3.1.0'))
$LOAD_PATH.unshift(File.join(ROOT, 'runtime', 'lib', 'ruby', '3.1.0', 'x64-mingw64'))

require 'json'

# --- 数据类桩 ---
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
def $game_map.events; @evs ||= {}; end
def $game_map.need_refresh; false; end
$game_player = Object.new
def $game_player.x; 21; end
def $game_player.y; 10; end
def $game_player.moving?; false; end

# $game_temp 桩
class Game_TempStub
  attr_accessor :common_event_id
  def initialize; @common_event_id = 0; end
end
$game_temp = Game_TempStub.new

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
def $game_system.map_interpreter; @mi ||= Interpreter.new(0, true); end
def $game_system.menu_disabled; false; end

class Viewport; attr_accessor :z, :visible; def initialize(*); @visible=true; end; end
class Sprite; attr_accessor :bitmap,:x,:y,:opacity,:visible,:z,:viewport; def initialize(*); @visible=true; end; def dispose; end; end
class Bitmap; attr_accessor :font; class Font; attr_accessor :size; end; def initialize(*); @font=Font.new; end; def width; 0; end; def height; 0; end; def dispose; end; end

# --- 先 load jump_map.rb ---
load File.join(ROOT, 'OneShot', 'mods', 'mod', 'Scripts', 'jump_map.rb')

# --- load 真实 Game_Character/Game_Event ---
3.times do |i|
  load format(File.join(ROOT, '_scripts_dump', '%03d_Game_Character_%d.rb'), 18 + i, i + 1)
end
load File.join(ROOT, '_scripts_dump', '021_Game_Event.rb')

# --- 模拟 Interpreter (最小, 含 setup/setup_starting_event) ---
class Interpreter
  attr_reader :list
  def initialize(depth = 0, main = false)
    @list = nil
  end
  def clear
    @list = nil
  end
  def setup(list, event_id, common_event_name = nil)
    @list = list
    @event_id = event_id
    @common_event_name = common_event_name
  end
  def running?
    @list != nil
  end
  def setup_starting_event
    # 公共事件保留
    if $game_temp.common_event_id > 0
      ce = $data_common_events[$game_temp.common_event_id]
      setup(ce.list, 0, ce.name)
      $game_temp.common_event_id = 0
      return
    end
    # 地图事件 starting
    for event in $game_map.events.values
      if event.starting
        setup(event.list, event.id)
        return
      end
    end
    # 公共事件 autorun
    for ce in $data_common_events.compact
      if ce.trigger == 1 and $game_switches[ce.switch_id] == true
        setup(ce.list, 0, ce.name)
        return
      end
    end
  end
end

# 公共事件桩
class CommonEventStub
  attr_accessor :trigger, :switch_id, :name, :list
  def initialize(id, trigger, switch_id)
    @trigger = trigger
    @switch_id = switch_id
    @name = "CE#{id}"
    @list = [id]  # 标记
  end
end

# --- 验证 1: 补丁是否 prepend ---
puts "== 验证 1: 补丁 prepend =="
puts "  Game_Event ancestors: #{Game_Event.ancestors.first(3).inspect}"
puts "  FreezePatch on Game_Event: #{Game_Event.ancestors.include?(JumpMapFreezePatch)}"
puts "  CommonPatch on Interpreter: #{Interpreter.ancestors.include?(JumpMapCommonEventPatch)}"
puts "  Interpreter#setup_starting_event owner: #{Interpreter.instance_method(:setup_starting_event).owner}"

# --- 验证 2: Game_Event 冻结所有地图 AUTORUN ---
puts ""
puts "== 验证 2: AUTORUN 冻结(所有地图) =="
$game_map = Object.new
def $game_map.map_id; 2; end   # 非目标地图
def $game_map.events; {}; end
def $game_map.need_refresh; false; end
$jump_map_free_mode = true
$jump_map_frozen_map_id = 4
e = Game_Event.allocate
e.instance_variable_set(:@trigger, 3)
e.instance_variable_set(:@starting, false)
e.check_event_trigger_auto
puts "  AUTORUN on map2 (非目标图) starting=#{e.starting.inspect} (期望 false=被冻结)"
puts(e.starting == false ? "  FREEZE-ALL OK" : "  ** FAILED **")

# --- 验证 3: 公共事件 autorun 被拦截 ---
puts ""
puts "== 验证 3: 公共事件 autorun 拦截 =="
$data_common_events = [nil, CommonEventStub.new(1, 1, 1), CommonEventStub.new(2, 1, 9)]
$game_switches[1] = true   # 公共事件1 条件满足
$game_switches[9] = true
mi = $game_system.map_interpreter
mi.clear
$game_temp.common_event_id = 0
mi.setup_starting_event
puts "  free_mode 下公共事件 autorun 是否 setup: list=#{mi.list.inspect} (期望 nil=被拦截)"
puts(mi.list.nil? ? "  COMMON-EVENT INTERCEPT OK" : "  ** FAILED ** (公共事件#{mi.list}被启动)")

# --- 验证 4: common_event_id 保留的公共事件正常 ---
puts ""
puts "== 验证 4: common_event_id 保留公共事件(退出)正常 =="
$data_common_events[35] = CommonEventStub.new(35, 0, 0)
$game_temp.common_event_id = 35
mi.setup_starting_event
puts "  common_event_id=35 保留: list=#{mi.list.inspect} (期望 [35]=正常启动)"
puts(mi.list == [35] ? "  RESERVED-COMMON OK" : "  ** FAILED **")

# --- 验证 5: 非 free_mode 下公共事件 autorun 正常 ---
puts ""
puts "== 验证 5: 非 free_mode 公共事件正常 =="
$jump_map_free_mode = false
mi.clear
$game_temp.common_event_id = 0
mi.setup_starting_event
puts "  非 free_mode: list=#{mi.list.inspect} (期望 [1]=正常启动第一个 autorun)"
puts(mi.list == [1] ? "  NORMAL-COMMON OK" : "  ** FAILED **")

puts ""
puts "DONE"
