# 找进入后记/结局地图(198/207/227/243)的传送事件及其前置开关
DATA_DIR = File.join(__dir__, '..', 'OneShot', 'Data')

class Table; def initialize(*); end; def self._load(s); new; end; end
class Color; def initialize(*); end; def self._load(s); new; end; end
class Tone; def initialize(*); end; def self._load(s); new; end; end

module RPG
  class AudioFile; end
  class BGM < AudioFile; end
  class BGS < AudioFile; end
  class ME < AudioFile; end
  class SE < AudioFile; end
  class MoveCommand; end
  class MoveRoute; end
  class Map; attr_accessor :events; end
  class Event; attr_accessor :id, :name, :pages; end
  class Event::Page; attr_accessor :list, :trigger, :condition; end
  class Event::Page::Condition; end
  class EventCommand; attr_accessor :code, :parameters; end
  class MapInfo; attr_accessor :name, :id; end
  class CommonEvent; end
end

maps_info = Marshal.load(File.binread(File.join(DATA_DIR, 'MapInfos.rxdata')))
def mid_of(f); File.basename(f)[/Map(\d+)\.rxdata/, 1].to_i; end

TARGETS = [198, 207, 227, 243]
found = []
Dir.glob(File.join(DATA_DIR, 'Map*.rxdata')).each do |f|
  mid = mid_of(f)
  begin
    map = Marshal.load(File.binread(f))
  rescue StandardError
    next
  end
  next unless map.is_a?(RPG::Map)
  info = maps_info[mid]
  mname = info ? info.name.to_s : '?'
  (map.events || {}).each do |eid, ev|
    next unless ev
    (ev.pages || []).each do |pg|
      list = pg.list || []
      list.each_with_index do |cmd, i|
        next unless cmd
        p = cmd.parameters || []
        if cmd.code == 201 && TARGETS.include?(p[1])
          # 收集该事件页内引用的所有开关(条件/设置)
          sw_refs = []
          list.each do |c2|
            next unless c2
            pp = c2.parameters || []
            sw_refs << pp[1] if c2.code == 111 && pp[0] == 0
            sw_refs << pp[0] if c2.code == 121
          end
          found << { from: mid, mname: mname, ev: eid, ename: ev.name.to_s, to: p[1], sw: sw_refs.uniq }
        end
      end
    end
  end
end

puts "=== 传送到 198/207/227/243 的事件 ==="
found.each do |f2|
  puts "from #{f2[:from]}(#{f2[:mname]}) ev#{f2[:ev]} '#{f2[:ename]}' -> map #{f2[:to]}  sw_refs=#{f2[:sw].inspect}"
end
