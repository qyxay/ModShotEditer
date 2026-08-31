# ============================================================
# verify_extra_actions.rb — 离线验证"三开关回归为动作条目"
#
# 用最小桩环境加载 dev_settings.rb, 验证:
#   1) EXTRA_ACTIONS / ACTION_KEYS 定义正确
#   2) reload_config 后 @keys 不含三个功能键(仅普通布尔)
#   3) display_items = 普通布尔 + 4 个动作条目
#   4) run_action 三个动作名分别分发到对应方法(用 stub 方法确认)
#   5) 三动作条目点击不会写回 config(不经 toggle / 不经 save_config)
#
# 用法: runtime\bin\ruby.exe _analyze\verify_extra_actions.rb
# ============================================================

require 'json'
require 'fileutils'

DEV_SETTINGS = File.expand_path('../OneShot/mods/mod/Scripts/dev_settings.rb', __dir__)

# ---------- 最小桩 ----------
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
class Font
  attr_accessor :size
end
class Color
  def initialize(*); end
end
module Input
  def self.trigger?(_k); false; end
end
def tr(s); s; end
$data_system = Struct.new(:cursor_se, :decision_se, :cancel_se).new(nil, nil, nil)
$game_system = Struct.new(:se_play).new(proc { |_x| })
$game_switches = nil   # 触发 unlock_all_doors 的 'Not in game' 分支
$game_map = nil

# config 快照(读真实 config, 不写)
$mod_config = begin
  JSON.parse(File.read(File.expand_path('../OneShot/mods/mod/config.json', __dir__)))
rescue StandardError
  {}
end

# ---------- 加载被测脚本 ----------
load DEV_SETTINGS

results = []
def check(results, name, cond, detail = '')
  results << [name, cond, detail]
end

# --- 1) 常量定义 ---
check(results, 'EXTRA_ACTIONS 有 4 个动作', EXTRA_ACTIONS.size == 4,
      EXTRA_ACTIONS.map { |id, n| "#{id}->#{n}" }.join(' | '))
check(results, 'ACTION_KEYS 有 3 个功能键', ACTION_KEYS == %w[unlock_all_doors complete_all_dialogues complete_all_story],
      ACTION_KEYS.inspect)

# --- 2) 实例化并 reload_config ---
ds = Window_DevSettings.new
ds.send(:reload_config)
bool_keys = @config_keys_before = ds.instance_variable_get(:@keys)
check(results, '@keys 不含三个功能键', (bool_keys & ACTION_KEYS).empty?,
      "keys=#{bool_keys.inspect}")
check(results, '@keys 含普通布尔(skip_pictures 等)', bool_keys.include?('skip_pictures'),
      "keys=#{bool_keys.inspect}")

# --- 3) display_items ---
items = ds.display_items
check(results, 'display_items = 布尔 + 4 动作', items.size == bool_keys.size + 4,
      "total=#{items.size} bool=#{bool_keys.size}")
check(results, '动作条目顺序正确', items[-4, 4] == EXTRA_ACTIONS.map(&:last),
      items[-4, 4].inspect)

# --- 4) run_action 分发 ---
calls = []
%i[unlock_all_doors complete_all_dialogues complete_all_story].each do |m|
  ds.define_singleton_method(m) { |*| calls << m }
end
ds.define_singleton_method(:open_jump_map) { calls << :jump_map }
EXTRA_ACTIONS.each do |id, name|
  ds.send(:run_action, name)
end
check(results, 'run_action 分发到 4 个方法', calls == %i[unlock_all_doors complete_all_dialogues complete_all_story jump_map],
      calls.inspect)
check(results, 'run_action 未知名静默', (ds.send(:run_action, 'Bogus') || true) == true, '')

# --- 5) 动作不写回 config(未触发 save_config/toggle) ---
# run_action 未调用 toggle → config 文件未被写。用 save_config 被调计数间接确认:
# 只要不调用 toggle/save_config, 文件 mtime 不变。
mtime_before = File.mtime(File.expand_path('../OneShot/mods/mod/config.json', __dir__))
sleep 0.05
# 触发 run_action(再次), 若逻辑误写回会 touch 文件
EXTRA_ACTIONS.each { |_id, name| ds.send(:run_action, name) }
mtime_after = File.mtime(File.expand_path('../OneShot/mods/mod/config.json', __dir__))
check(results, '点击动作未写回 config.json', mtime_before == mtime_after,
      "mtime unchanged=#{mtime_before == mtime_after}")

# ---------- 输出 ----------
puts "=== verify_extra_actions ==="
fails = 0
results.each do |name, cond, detail|
  mark = cond ? 'PASS' : 'FAIL'
  fails += 1 unless cond
  puts "  [#{mark}] #{name}" + (detail && detail != '' ? "  (#{detail})" : '')
end
puts "result = #{fails.zero? ? 'ALL PASS' : "#{fails} FAIL"}"
exit(fails.zero? ? 0 : 1)
