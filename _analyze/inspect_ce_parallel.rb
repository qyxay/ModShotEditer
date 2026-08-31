# ============================================================
#  分析: 公共事件 trigger==2 (PARALLEL) 及命令
# ============================================================

$LOAD_PATH.unshift('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/runtime/lib/ruby/3.1.0')
$LOAD_PATH.unshift('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/runtime/lib/ruby/3.1.0/x64-mingw64')

module RPG
  class EventCommand; end
  class MoveRoute; end
  class MoveCommand; end
  class AudioFile; end
  class CommonEvent; end
end
class Table; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end
class Color; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end
class Tone; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end
class Rect; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end

$data_common_events = Marshal.load(File.binread('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data/CommonEvents.rxdata'))

$data_common_events.each_with_index do |ce, i|
  next unless ce
  trig = ce.instance_variable_get(:@trigger)
  swid = ce.instance_variable_get(:@switch_id)
  name = ce.instance_variable_get(:@name)
  next unless trig == 2  # PARALLEL
  list = ce.instance_variable_get(:@list) || []
  # 摘要命令
  cmds = []
  list.each do |c|
    code = c.instance_variable_get(:@code)
    p = c.instance_variable_get(:@parameters)
    case code
    when 101, 401 then cmds << "#{code}[#{p[0].to_s[0,28]}]"
    when 106 then cmds << "106(wait#{p[0]})"
    when 111 then cmds << "111(分支#{p[0]})"
    when 121 then cmds << "121(sw#{p[0]}=#{p[1]})"
    when 117 then cmds << "117(CE#{p[0]})"
    when 355, 655 then cmds << "#{code}[#{p[0].to_s[0,28]}]"
    when 0 then cmds << "0(end)"
    end
  end
  puts "CE##{i} '#{name}' 条件开关=#{swid} 命令数=#{list.size}: #{cmds.first(10).join(' | ')}"
end
