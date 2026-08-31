# ============================================================
#  验证: 真实 Game_Event 是否有 list 方法 / 101 检测方式
# ============================================================

$LOAD_PATH.unshift('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/runtime/lib/ruby/3.1.0')
require_relative 'oneshot_data'

# --- 桩环境 (Game_Event 需要) ---
$game_switches = {}
$game_variables = {}
$game_self_switches = {}
$game_map = Object.new
def $game_map.map_id; 225; end
def $game_map.width; 140; end
def $game_map.height; 36; end
def $game_map.passable?(*); true; end
def $game_map.valid?(*); true; end
def $game_map.events; {}; end
def $game_map.map_id; 225; end

module Input
  def self.trigger?(*); false; end
  def self.press?(*); false; end
  def self.dir4; 2; end
end
def tr(s); s; end

class Game_Battler; end
class Game_Character
  def initialize; end
end

# 加载真实 Game_Character (3段) + Game_Event
3.times do |i|
  load format('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/_scripts_dump/%03d_Game_Character_%d.rb', 18 + i, i + 1)
end
load 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/_scripts_dump/021_Game_Event.rb'

map = os_load_map(225)
evs = map.instance_variable_get(:@events)
ev001 = evs[1]  # EV001 出口事件

ev = Game_Event.allocate
ev.instance_variable_set(:@event, ev001)
ev.instance_variable_set(:@id, ev001.id)
ev.instance_variable_set(:@map_id, 225)
puts "Game_Event#respond_to?(:list) = #{ev.respond_to?(:list)}"
begin
  p ev.list
rescue => e
  puts "ev.list 抛错: #{e.class}: #{e.message}"
end
puts "ev.instance_variable_get(:@event).pages.size = #{ev.instance_variable_get(:@event).pages.size}"
puts "ev.instance_variable_get(:@event).list 存在? = #{!ev.instance_variable_get(:@event).list.nil?}"

# 101 检测: 遍历 pages 的 list
has_text = ev.instance_variable_get(:@event).pages.any? { |pg| pg.list.any? { |c| c && c.code == 101 } }
puts "EV001 含101? = #{has_text}"

# Map Events 事件 (含对话) 检查
map_events = evs[16]
ev2 = Game_Event.allocate
ev2.instance_variable_set(:@event, map_events)
ev2.instance_variable_set(:@id, map_events.id)
ev2.instance_variable_set(:@map_id, 225)
has_text2 = ev2.instance_variable_get(:@event).pages.any? { |pg| pg.list.any? { |c| c && c.code == 101 } }
puts "'Map Events' 含101? = #{has_text2}"
