# ============================================================
#  临时验证脚本 v2: 验证 dev_settings.rb 的功能开关
#  - unlock_all_doors / complete_all_dialogues / complete_all_story
#  - 只操作"当前地图事件引用到的开关", 不触碰其他地图的全局开关
# ============================================================

$LOAD_PATH.unshift('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/runtime/lib/ruby/3.1.0')
$LOAD_PATH.unshift('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/runtime/lib/ruby/3.1.0/x64-mingw64')

require 'json'

# --- 桩: 语言翻译原样返回 ---
def tr(s); s; end

# --- 桩: 游戏全局 ---
$game_switches = {}
$game_self_switches = {}

# 重置 config.json 三个功能开关为 false, 保证测试序列从 ON 开始(可重复运行)
CONFIG_JSON = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/mods/mod/config.json'
def reset_feature_switches
  cfg = JSON.parse(File.read(CONFIG_JSON))
  %w[unlock_all_doors complete_all_dialogues complete_all_story].each { |k| cfg[k] = false }
  File.write(CONFIG_JSON, JSON.pretty_generate(cfg) + "\n")
  cfg
end
cfg = reset_feature_switches
# 预置 $mod_config(读真实 config.json), 使加载时 is_developer=true
$mod_config = cfg

class FakeSE
  def se_play(*); end
end
$game_system = FakeSE.new
$data_system = Object.new
def $data_system.decision_se; nil; end
def $data_system.cursor_se; nil; end
def $data_system.cancel_se; nil; end

module Input
  def self.trigger?(_k); false; end
  def self.press?(_k); false; end
  UP=0; DOWN=1; ACTION=2; LEFT=3; RIGHT=4; CANCEL=5
end

# --- 桩: RGSS UI 类 ---
class Viewport
  attr_accessor :z, :visible
  def initialize(*); @visible = true; end
end
class Sprite
  attr_accessor :bitmap, :x, :y, :opacity, :visible, :z, :viewport
  def initialize(vp = nil); @viewport = vp; @visible = true; end
  def dispose; end
end
class Bitmap
  attr_accessor :font
  class Font
    attr_accessor :size
  end
  def initialize(w, h); @font = Font.new; @w = w; @h = h; end
  def width; @w; end
  def height; @h; end
  def fill_rect(*); end
  def clear; end
  def draw_text(*); end
  def dispose; end
end
class Color
  def initialize(*); end
end

# --- 桩: RPG 数据结构 (事件页条件 / 事件指令) ---
class FakeCondition
  attr_accessor :switch1_valid, :switch1_id, :switch2_valid, :switch2_id
  def initialize
    @switch1_valid = false; @switch1_id = 0
    @switch2_valid = false; @switch2_id = 0
  end
end

class FakeCommand
  attr_accessor :code, :parameters
  def initialize(code, parameters = [])
    @code = code
    @parameters = parameters
  end
end

class FakePage
  attr_accessor :condition, :list
  def initialize(cond, list)
    @condition = cond
    @list = list
  end
end

class FakeEventObj
  attr_accessor :pages
  def initialize(pages); @pages = pages; end
end

class FakeEvent
  attr_accessor :list
  attr_reader :id
  def initialize(id, event_obj)
    @id = id
    @event = event_obj
    @list = event_obj.pages.first.list   # 当前页取第一页
  end
  def refresh; end
  def instance_variable_get(name)
    name == :@event ? @event : super
  end
end

class FakeMap
  attr_reader :map_id, :events
  def initialize
    @map_id = 42
    # 事件1: 页条件 switch1=8 + 指令条件分支 switch=50 (门锁)
    c1 = FakeCondition.new
    c1.switch1_valid = true; c1.switch1_id = 8
    p1 = FakePage.new(c1, [FakeCommand.new(111, [0, 50, 0])])
    # 事件2: 页条件 switch2=112 + 含对话指令 (门锁 + 对话)
    c2 = FakeCondition.new
    c2.switch2_valid = true; c2.switch2_id = 112
    p2 = FakePage.new(c2, [FakeCommand.new(101, ['hi'])])
    # 事件3: 无开关引用
    c3 = FakeCondition.new
    p3 = FakePage.new(c3, [FakeCommand.new(201, [])])
    @events = {
      1 => FakeEvent.new(1, FakeEventObj.new([p1])),
      2 => FakeEvent.new(2, FakeEventObj.new([p2])),
      3 => FakeEvent.new(3, FakeEventObj.new([p3]))
    }
  end
end
$game_map = FakeMap.new

# --- 加载被测脚本 ---
load 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/mods/mod/Scripts/dev_settings.rb'

ds = Window_DevSettings.new
ds.open

# 预期当前地图引用到的开关: 8(页条件), 50(指令111), 112(页条件)
expected = [8, 50, 112]
actual = ds.current_map_switches.sort
puts "== current_map_switches =="
puts "  actual=#{actual.inspect}  expected=#{expected.inspect}"
raise "FAIL: 开关收集不匹配" unless actual == expected

# 其他地图的开关(模拟已开启的全局开关), 必须保持不被改动
$game_switches[178] = true
$game_switches[999] = true

keys = ds.instance_variable_get(:@keys)
i_u = keys.index('unlock_all_doors')
i_d = keys.index('complete_all_dialogues')
i_s = keys.index('complete_all_story')

puts ""
puts "== 1. unlock_all_doors -> ON =="
puts "  [debug] keys=#{keys.inspect}"
puts "  [debug] i_u=#{i_u.inspect}  STATE_ACTIONS=#{Object::STATE_ACTIONS.keys.inspect}"
puts "  [debug] unlock_all_doors enabled? #{ds.instance_variable_get(:@config)['unlock_all_doors'].inspect}"
before = $game_switches.dup
ds.toggle(i_u)
puts "  [debug] before=#{before.inspect}"
puts "  [debug] after=#{$game_switches.inspect}"
puts "  [debug] config unlock_all_doors=#{ds.instance_variable_get(:@config)['unlock_all_doors'].inspect}"
[8,50,112].each { |s| raise "FAIL: 本图开关#{s}未置true" unless $game_switches[s] == true }
raise "FAIL: 他图开关178被误改" unless $game_switches[178] == true
raise "FAIL: 他图开关999被误改" unless $game_switches[999] == true
puts "  本图[8,50,112]=#{[8,50,112].map{|s|$game_switches[s]}.inspect}  他图[178,999]=#{$game_switches[178].inspect},#{$game_switches[999].inspect}  OK"

puts "== 2. unlock_all_doors -> OFF =="
ds.toggle(i_u)
[8,50,112].each { |s| raise "FAIL: 本图开关#{s}未置false" unless $game_switches[s] == false }
raise "FAIL: 他图开关178被误改" unless $game_switches[178] == true
raise "FAIL: 他图开关999被误改" unless $game_switches[999] == true
puts "  本图[8,50,112]=#{[8,50,112].map{|s|$game_switches[s]}.inspect}  他图[178,999]=#{$game_switches[178].inspect},#{$game_switches[999].inspect}  OK"

puts ""
puts "== 3. complete_all_story -> ON (应一并置当前地图开关ON) =="
ds.toggle(i_s)
raise "FAIL: 事件1自开关未完成" unless $game_self_switches[[42,1,'A']] == true
raise "FAIL: 本图开关8未随剧情置true" unless $game_switches[8] == true
raise "FAIL: 他图开关178被误改" unless $game_switches[178] == true
puts "  自开关[42,1,A]=#{$game_self_switches[[42,1,'A']].inspect} 本图开关8=#{$game_switches[8].inspect} 他图178=#{$game_switches[178].inspect}  OK"

puts "== 4. complete_all_story -> OFF (应一并置当前地图开关OFF) =="
ds.toggle(i_s)
raise "FAIL: 事件1自开关未置回" unless $game_self_switches[[42,1,'A']] == false
raise "FAIL: 本图开关8未置false" unless $game_switches[8] == false
raise "FAIL: 他图开关178被误改" unless $game_switches[178] == true
puts "  自开关[42,1,A]=#{$game_self_switches[[42,1,'A']].inspect} 本图开关8=#{$game_switches[8].inspect} 他图178=#{$game_switches[178].inspect}  OK"

puts ""
puts "== 5. complete_all_dialogues 仅处理含对话事件 =="
# 重置事件3 自开关为干净状态(模拟未操作过), 再测 complete_all_dialogues
$game_self_switches.delete([42,3,'A'])
ds.toggle(i_d)
raise "FAIL: 事件2(含对话)未完成" unless $game_self_switches[[42,2,'A']] == true
raise "FAIL: 事件3(无对话)被误改" unless $game_self_switches[[42,3,'A']].nil?
puts "  事件2(含对话)自开关=#{$game_self_switches[[42,2,'A']].inspect}  事件3(无对话)=#{$game_self_switches[[42,3,'A']].inspect}  OK"

puts ""
puts "ALL CHECKS PASSED"
# 恢复 config.json 为初始状态(三键 false), 不污染用户配置
reset_feature_switches
