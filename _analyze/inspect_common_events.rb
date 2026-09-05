ROOT = File.expand_path('..', __dir__)
# ============================================================
#  临时分析: 找出所有 trigger==1 (autorun) 的公共事件
# ============================================================

$LOAD_PATH.unshift("#{ROOT}/runtime/lib/ruby/3.1.0")
$LOAD_PATH.unshift("#{ROOT}/runtime/lib/ruby/3.1.0/x64-mingw64")

module RPG
  class Map; end
  class Event; end
  class EventCommand; end
  class Tileset; end
  class AudioFile; end
  class MoveRoute; end
  class MoveCommand; end
  class CommonEvent; end
  class Event
    class Page; end
    class Page::Condition; end
    class Page::Graphic; end
  end
end
class Table; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end
class Color; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end
class Tone; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end
class Rect; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end

ce = Marshal.load(File.binread("#{ROOT}/OneShot/Data/CommonEvents.rxdata"))
puts "公共事件总数: #{ce.compact.size}"
puts ""
ce.compact.each do |ev|
  id = ev.instance_variable_get(:@id)
  name = ev.instance_variable_get(:@name)
  trig = ev.instance_variable_get(:@trigger)
  sw = ev.instance_variable_get(:@switch_id)
  list = ev.instance_variable_get(:@list)
  codes = list.map { |c| c.instance_variable_get(:@code) }
  puts "##{id} '%s' trigger=%d switch=%d 命令=%s" % [name, trig, sw, codes.inspect]
end
