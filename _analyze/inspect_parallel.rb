# ============================================================
#  分析: 地图 2 / 120 的 PARALLEL 事件命令 (是否含 101 对话锁玩家)
# ============================================================

$LOAD_PATH.unshift('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/runtime/lib/ruby/3.1.0')
$LOAD_PATH.unshift('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/runtime/lib/ruby/3.1.0/x64-mingw64')

module RPG
  class Map; end
  class Event; end
  class EventCommand; end
  class Tileset; end
  class AudioFile; end
  class MoveRoute; end
  class MoveCommand; end
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

def load_evs(mid)
  path = format('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data/Map%03d.rxdata', mid)
  Marshal.load(File.binread(path)).instance_variable_get(:@events)
end

[2, 120].each do |mid|
  puts "=" * 60
  puts "### 地图 #{mid} PARALLEL 事件 ###"
  load_evs(mid).each do |id, ev|
    name = ev.instance_variable_get(:@name)
    pages = ev.instance_variable_get(:@pages)
    pages.each_with_index do |pg, pi|
      trig = pg.instance_variable_get(:@trigger)
      next unless trig == 4  # PARALLEL
      list = pg.instance_variable_get(:@list) || []
      cmds = []
      list.each do |c|
        code = c.instance_variable_get(:@code)
        p = c.instance_variable_get(:@parameters)
        case code
        when 101 then cmds << "101[#{p[0].to_s[0,30]}]"
        when 401 then cmds << "401[#{p[0].to_s[0,25]}]"
        when 106 then cmds << "106(w#{p[0]})"
        when 111 then cmds << "111(分支#{p[0]})"
        when 121 then cmds << "121(sw#{p[0]}=#{p[1]})"
        when 122 then cmds << "122(var)"
        when 117 then cmds << "117(CE#{p[0]})"
        when 355, 655 then cmds << "#{code}[#{p[0].to_s[0,30]}]"
        when 0 then cmds << "0(end)"
        end
      end
      puts "  ##{id} '#{name}' 页#{pi}: #{cmds.first(14).join(' | ')}"
    end
  end
end
