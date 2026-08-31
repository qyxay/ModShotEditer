# ============================================================
# verify_shortcut_keys.rb — 离线验证快捷键补丁(Ctrl+D / Ctrl+J)
#
# 加载 dev_settings.rb + jump_map.rb(含 ShortcutKeysPatch),
# 用桩 Scene_Map / Input 验证:
#   1) ShortcutKeysPatch 已 prepend 到 Scene_Map
#   2) Ctrl+D (is_developer) → 打开开发者设置, 借用设置窗口槽位
#   3) 快捷键打开的 dev_settings 关闭(CANCEL) → on_closed 恢复设置窗口
#   4) Ctrl+J → 打开 jump_map 子界面
#   5) 对话/事件运行中不响应快捷键
#   6) Input 无扩展 API 时回退(不崩)
#
# 注意: Scene_Map 桩必须在 load 两个脚本之后定义, 才能被
# jump_map.rb 的 TracePoint(:end) 捕获并 prepend 补丁。
#
# 用法: runtime\bin\ruby.exe _analyze\verify_shortcut_keys.rb
# ============================================================

require 'json'

ROOT = File.expand_path('..', __dir__)
DEV_SETTINGS = File.join(ROOT, 'OneShot/mods/mod/Scripts/dev_settings.rb')
JUMP_MAP     = File.join(ROOT, 'OneShot/mods/mod/Scripts/jump_map.rb')

# ---------- 基础桩(在 load 前即可; Scene_Map 桩在 load 后) ----------
class Viewport
  def initialize(*); @visible = true; end
  attr_accessor :z, :visible
end
class Sprite
  def initialize(vp = nil); @bitmap = nil; @visible = true; @opacity = 255; @x = 0; @y = 0; end
  attr_accessor :bitmap, :x, :y, :opacity, :visible, :z
  def dispose; end
end
class Bitmap
  def initialize(*); @font = Font.new; end
  attr_reader :font, :width, :height
  def clear; end
  def draw_text(*); end
  def fill_rect(*); end
  def dispose; end
end
class Font; attr_accessor :size; end
class Color; def initialize(*); end; end

module Input
  CTRL = 1
  CANCEL = 5
  ACTION = 6
  UP = 7
  DOWN = 8
  LEFT = 9
  RIGHT = 10

  @held = {}
  @trig = {}
  class << self
    attr_accessor :held, :trig
  end

  def self.press?(k); @held[k]; end
  def self.trigger?(k); @trig[k]; end
  # mkxp-z 扩展
  def self.pressex?(sym); !!@held[sym]; end
  def self.triggerex?(sym); !!@trig[sym]; end
end

def tr(s); s; end
$data_system = Struct.new(:cursor_se, :decision_se, :cancel_se).new(nil, nil, nil)
class FakeGameSystem
  attr_accessor :map_interpreter
  def se_play(_se); end
end
$game_system = FakeGameSystem.new
$game_temp = Struct.new(:message_window_showing, :transition_processing, :player_transferring, :menus_visible).new(false, false, false, false)
$game_switches = nil
$game_map = Object.new
$game_player = Object.new
class FakeInterp
  def running?; false; end
end
class FakeInterpRunning
  def running?; true; end
end
$game_system.map_interpreter = FakeInterp.new
$mod_config = { 'is_developer' => true }

# ---------- 加载被测脚本 ----------
load DEV_SETTINGS
load JUMP_MAP

# ---------- Scene_Map 桩(必须在 load 之后, 使 TracePoint 捕获并 prepend) ----------
class FakeSettings
  attr_accessor :visible
  def initialize; @visible = false; @data_sprites = []; @data = []; @dev_settings = nil; @index = 0; end
  def open; @visible = true; @data_sprites = []; end
  # 模拟 WindowSettingsDevPatch#update: dev_settings 打开时接管输入并 return
  def update
    if @dev_settings && @dev_settings.visible
      @dev_settings.update
      return
    end
  end
end
class FakeMsg
  attr_accessor :visible
  def initialize; @visible = false; end
end

class Scene_Map
  def initialize
    @window_settings = FakeSettings.new
    @message_window = FakeMsg.new
    @ed_message = FakeMsg.new
    @item_menu = FakeMsg.new
    @fast_travel = FakeMsg.new
  end
  def update
    # super 为空的替代: 真实 Scene_Map#update 在内部调用 @window_settings.update
    @window_settings.update
  end
end

results = []
def check(results, name, cond, detail = '')
  results << [name, cond, detail]
end

# --- 1) 补丁已应用 ---
check(results, 'ShortcutKeysPatch prepend 到 Scene_Map',
      Scene_Map.ancestors.include?(ShortcutKeysPatch), Scene_Map.ancestors.first(3).inspect)

sm = Scene_Map.new

# --- 2) Ctrl+D 打开开发者设置 ---
Input.held = { LCTRL: true, RCTRL: false }
Input.trig = { D: true, J: false }
sm.update
ds = $dev_settings_instance
check(results, 'Ctrl+D 创建并打开 dev_settings', ds && ds.visible, "ds.visible=#{ds && ds.visible}")
check(results, '设置窗口槽位被挂载', sm.instance_variable_get(:@window_settings).instance_variable_get(:@dev_settings) == ds, '')
check(results, '设置窗口被置可见(屏蔽菜单)', sm.instance_variable_get(:@window_settings).visible == true, '')

# --- 3) CANCEL 关闭 → on_closed 恢复 ---
# ds.update 用 Input.trigger?(Input::CANCEL) (数值键), 桩必须用 Input::CANCEL 作键
Input.held = { LCTRL: false }
Input.trig = { D: false, J: false, Input::CANCEL => true }
sm.update
check(results, 'CANCEL 关闭 dev_settings', ds.visible == false, "ds.visible=#{ds.visible}")
ws = sm.instance_variable_get(:@window_settings)
check(results, 'on_closed 恢复设置窗口 visible=false', ws.visible == false, "ws.visible=#{ws.visible}")
check(results, 'on_closed 清空 dev_settings 槽位', ws.instance_variable_get(:@dev_settings).nil?, '')

# --- 4) Ctrl+J 打开 jump_map ---
Input.held = { LCTRL: true }
Input.trig = { D: false, J: true }
sm.update
ds2 = $dev_settings_instance
check(results, 'Ctrl+J 打开 dev_settings 载体', ds2 && ds2.visible, "ds2.visible=#{ds2 && ds2.visible}")
jm = ds2 ? ds2.instance_variable_get(:@jump_map) : nil
check(results, 'Ctrl+J 打开 jump_map 子界面', jm && jm.visible, "jm.visible=#{jm && jm.visible}")

# --- 5) 事件运行中不响应 ---
# 重置(关闭上一界面的 jump_map/dev_settings)
jm.visible = false if jm
ds2.visible = false
$game_system.map_interpreter = FakeInterpRunning.new
Input.held = { LCTRL: true }
Input.trig = { D: true, J: false }
prev = ds2.visible
sm.update
check(results, '事件运行中 Ctrl+D 不打开', ds2.visible == false, "ds2.visible=#{ds2.visible}")

# --- 6) Input 无扩展 API 时不崩 ---
$game_system.map_interpreter = FakeInterp.new
class << Input
  undef_method :pressex? rescue nil
  undef_method :triggerex? rescue nil
end
begin
  sm.update
  check(results, 'Input 无扩展 API 时静默降级', true, '')
rescue StandardError => e
  check(results, 'Input 无扩展 API 时静默降级', false, "raise #{e.class}: #{e.message}")
end

# ---------- 输出 ----------
puts '=== verify_shortcut_keys ==='
fails = 0
results.each do |name, cond, detail|
  mark = cond ? 'PASS' : 'FAIL'
  fails += 1 unless cond
  puts "  [#{mark}] #{name}" + (detail && detail != '' ? "  (#{detail})" : '')
end
puts "result = #{fails.zero? ? 'ALL PASS' : "#{fails} FAIL"}"
exit(fails.zero? ? 0 : 1)
