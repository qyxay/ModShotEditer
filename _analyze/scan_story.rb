# 扫描 postgame/结局/关键剧情 相关开关与地图
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
  class Event::Page::Condition
    attr_accessor :switch1_valid, :switch2_valid, :switch1_id, :switch2_id
  end
  class EventCommand; attr_accessor :code, :parameters; end
  class MapInfo; attr_accessor :name, :id; end
  class CommonEvent; end
end

maps_info = Marshal.load(File.binread(File.join(DATA_DIR, 'MapInfos.rxdata')))
def mid_of(f); File.basename(f)[/Map(\d+)\.rxdata/, 1].to_i; end

switches_by_name = Hash.new { |h, k| h[k] = [] }
# 收集所有事件命令里 121(开关设置) 且参数是 "ON" 的开关, 以及文本含 postgame/the end/credits 的事件上下文
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
    ename = ev.name.to_s
    (ev.pages || []).each do |pg|
      (pg.list || []).each do |cmd|
        next unless cmd
        p = cmd.parameters || []
        if cmd.code == 101 && p[0].to_s =~ /postgame|the end|ending|credits|final|finished|complete/i
          switches_by_name["TEXT:#{p[0].to_s[0, 40]}"] << "#{mid}(#{mname}) ev#{eid} '#{ename}'"
        elsif cmd.code == 121 && p[2] == 0 # 开关 ON
          switches_by_name["switch#{p[0]}"] << "ON #{mid}(#{mname}) ev#{eid} '#{ename}'"
        end
      end
    end
  end
end

# 找 postgame 相关地图
puts "=== 含 postgame/ending/credits 文本的事件 ==="
switches_by_name.select { |k, _| k.start_with?('TEXT') }.each do |k, v|
  puts "#{k}: #{v.uniq.first(4).join(' | ')}"
end
puts ""
puts "=== 含 final/finished/complete 文本的事件 ==="
switches_by_name.select { |k, _| k =~ /final|finished|complete/i }.each do |k, v|
  puts "#{k}: #{v.uniq.first(4).join(' | ')}"
end
