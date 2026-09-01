# ============================================================
#  验证 UnlockCompleteScanner#event_control 的控制状态识别(离线静态):
#  直接暴露底层开关/变量/自开关(不做语义转化)。
# ============================================================
$LOAD_PATH.unshift('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/runtime/lib/ruby/3.1.0')
require_relative 'oneshot_data'
module RPG
  class Map
    attr_accessor :events
  end
end
JUMP_POINTS_PATH = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/mods/mod/jump_points.json'
JUMP_MAP_FILTER = /IGNORE|DEBUG|INTERNAL|UNUSED|\bTEST\b|^INIT\b|TELEPORT|DEMO|PROTOWALK|PSHOT|LANGUAGE\s?DEBUG|LANG\s?DEBUG/i
JUMP_MAP_NAME_PATTERN = /^[TCS]\d+$/i
JUMP_MAP_PARENT_FILTER = /IGNORE|DEBUG|UNUSED|INTERNAL|\bTEST\b|^INIT\b|TELEPORT/i
DATA2 = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data'
def load_data(name)
  base = File.basename(name)
  Marshal.load(File.binread(File.join(DATA2, base)))
end
def tr(s); s; end

load 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/mods/mod/Scripts/unlock_or_complete.rb'

def static_ev(mid, eid)
  m = load_data(format('Data/Map%03d.rxdata', mid))
  (m.events || {})[eid]
end

failures = []
cases = {
  [2, 9, 'Map2 west door(命令内111 sw178)'] => { kind: :switch, sids: [178], vars: [], ch: nil },
  [2, 10, 'Map2 south door'] => { kind: :switch, sids: [178], vars: [], ch: nil },
  [2, 8, 'Map2 pc(命令内111 sw178, 直接暴露不改方向)'] => { kind: :switch, sids: [178], vars: [], ch: nil },
  [3, 1, 'Map3 east door(无条件传送)'] => { kind: :none, sids: [], vars: [], ch: nil },
  [4, 1, 'Map4 north door(无条件传送)'] => { kind: :none, sids: [], vars: [], ch: nil },
  [4, 2, 'Map4 east door(命令内111 sw7, 优先开关跳过var1)'] => { kind: :switch, sids: [7], vars: [], ch: nil },
  [4, 17, 'Map4 niko hello(自开关 ssA)'] => { kind: :self_switch, sids: [], vars: [], ch: 'A' },
  [4, 11, 'Map4 fire action(页条件 sw5)'] => { kind: :switch, sids: [5], vars: [], ch: nil },
  [120, 2, 'Map120 south exit(命令内111 sw22)'] => { kind: :switch, sids: [22], vars: [], ch: nil }
}

cases.each do |(mid, eid, name), exp|
  ev = static_ev(mid, eid)
  if ev.nil?
    puts "  [SKIP] #{name}: 事件不存在"
    next
  end
  ctl = UnlockCompleteScanner.event_control(ev)
  ok = ctl[:kind] == exp[:kind] && ctl[:sids] == exp[:sids] && ctl[:vars] == exp[:vars] && ctl[:ch] == exp[:ch]
  puts "  #{ok ? 'OK ' : 'FAIL'} #{name}"
  puts "        got=#{ctl.inspect} exp=#{exp.inspect}" unless ok
  failures << "#{name}: got #{ctl.inspect} exp #{exp.inspect}" unless ok
end

puts ""
if failures.empty?
  puts "result = ALL PASS"
else
  puts "FAIL:"
  failures.each { |f| puts "  - #{f}" }
  exit 1
end
