# ============================================================
#  验证 Window_UnlockComplete 界面逻辑(桩环境):
#  - 实例化/打开不崩, 打开时定位到当前所在地图页
#  - refresh_list 渲染不崩, 页码正确
#  - 模拟确认键 → 对当前地图执行 unlock+complete(记录调用)
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
end

# 模拟 jump_map.rb 已加载(定义其常量, 真实游戏由加载顺序保证)
JUMP_POINTS_PATH = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/mods/mod/jump_points.json'
JUMP_MAP_FILTER = /IGNORE|DEBUG|INTERNAL|UNUSED|\bTEST\b|^INIT\b|TELEPORT|DEMO|PROTOWALK|PSHOT|LANGUAGE\s?DEBUG|LANG\s?DEBUG/i
JUMP_MAP_NAME_PATTERN = /^[TCS]\d+$/i
JUMP_MAP_PARENT_FILTER = /IGNORE|DEBUG|UNUSED|INTERNAL|\bTEST\b|^INIT\b|TELEPORT/i

DATA2 = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data'
def load_data(name)
  base = File.basename(name)
  Marshal.load(File.binread(File.join(DATA2, base)))
end

# ---- 最小 UI 桩 ----
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
  @@trig = {}
  def self.trigger?(*); @@trig[:now]; end
  def self.set(k, v); @@trig[:now] = v; end
end
module Kernel2; end

$game_system = Object.new
def $game_system.se_play(*); end
$data_system = Object.new
def $data_system.decision_se; end
def $data_system.cursor_se; end
def $data_system.cancel_se; end

def tr(s); s; end

# dev_settings 桩: 记录 unlock/complete 调用
$dev_settings_instance = Object.new
$CALLS = []
def $dev_settings_instance.unlock_all_doors; $CALLS << :unlock; 5; end
def $dev_settings_instance.complete_all_dialogues; $CALLS << :dialogue; 3; end
def $dev_settings_instance.complete_all_story; $CALLS << :story; 2; end
def $dev_settings_instance.flash(*); end

# 当前所在地图 = 4 (Livingroom)
$game_map = Object.new
def $game_map.map_id; 4; end

# 加载真实脚本
load 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/mods/mod/Scripts/unlock_or_complete.rb'

failures = []
w = Window_UnlockComplete.new
w.open
maps = w.instance_variable_get(:@maps)
puts "  地图列表: #{maps.size} 张"
failures << '地图列表应为空(应有可浏览地图)' if maps.empty?
failures << '地图4应在地图列表中' if maps.none? { |m| m[:id] == 4 }
exp_page = maps.index { |m| m[:id] == 4 } || 0
page0 = w.instance_variable_get(:@page)
puts "  打开定位: 地图4 → page=#{page0} (期望 #{exp_page})"
failures << '打开后应定位到地图4页' unless page0 == exp_page

# 渲染不崩
w.send(:refresh_list)
puts "  当前页 sprite 数: #{w.instance_variable_get(:@data_sprites).size}"
failures << '渲染应生成内容行' if w.instance_variable_get(:@data_sprites).empty?

# 模拟确认键 → 应执行 unlock+complete
Input.set(:now, true)
w.update
puts "  确认键调用: #{$CALLS.inspect}"
failures << '确认应调用 unlock' unless $CALLS.include?(:unlock)
failures << '确认应调用 dialogue' unless $CALLS.include?(:dialogue)
failures << '确认应调用 story' unless $CALLS.include?(:story)
Input.set(:now, false)

puts ""
if failures.empty?
  puts "result = ALL PASS"
else
  puts "FAIL:"
  failures.each { |f| puts "  - #{f}" }
  exit 1
end
