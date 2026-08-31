# 扫描所有门/锁类事件引用的条件开关号 + 对话事件统计
# 用法: runtime\bin\ruby.exe _analyze\scan_lock_switches.rb
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
  class Event; attr_accessor :id, :name, :pages, :x, :y; end
  class Event::Page; attr_accessor :list, :trigger, :condition; end
  class Event::Page::Condition
    attr_accessor :switch1_valid, :switch2_valid, :variable_valid, :self_switch_valid,
                  :switch1_id, :switch2_id, :variable_id, :variable_value, :self_switch_ch
  end
  class Event::Page::Graphic; end
  class EventCommand; attr_accessor :code, :parameters; end
  class MapInfo; attr_accessor :name, :id; end
  class Tileset; end
  class System; end
  class CommonEvent; end
end

maps_info = Marshal.load(File.binread(File.join(DATA_DIR, 'MapInfos.rxdata')))

def mid_of(f); File.basename(f)[/Map(\d+)\.rxdata/, 1].to_i; end

# 门/锁事件的条件开关号统计
lock_switch_counts = Hash.new(0)
lock_switch_maps = Hash.new { |h, k| h[k] = [] }
# 记录: 事件页触发条件里的开关(页可见性开关) - 这些也是"门开/关"的关键
page_switch_counts = Hash.new(0)

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
    low = ename.downcase
    is_doorish = low =~ /door|lock|gate|seal/i
    (ev.pages || []).each do |pg|
      next unless pg
      # 页触发条件: 开关1/开关2 控制页面显示
      cond = pg.condition
      if cond
        if cond.switch1_valid
          page_switch_counts[cond.switch1_id] += 1
          if is_doorish
            lock_switch_counts[cond.switch1_id] += 1
            lock_switch_maps[cond.switch1_id] << "#{mid}(#{mname})"
          end
        end
        if cond.switch2_valid
          page_switch_counts[cond.switch2_id] += 1
          if is_doorish
            lock_switch_counts[cond.switch2_id] += 1
            lock_switch_maps[cond.switch2_id] << "#{mid}(#{mname})"
          end
        end
      end
      # 事件命令里的条件分支(111)开关判断
      (pg.list || []).each do |cmd|
        next unless cmd
        if cmd.code == 111 && cmd.parameters && cmd.parameters[0] == 0
          sw = cmd.parameters[1]
          if is_doorish
            lock_switch_counts[sw] += 1
            lock_switch_maps[sw] << "#{mid}(#{mname})" unless lock_switch_maps[sw].include?("#{mid}(#{mname})")
          end
        end
      end
    end
  end
end

puts "=== 门/锁事件页可见性开关 & 条件分支开关 (按引用次数排序) ==="
lock_switch_counts.sort_by { |k, v| -v }.first(40).each do |sw, cnt|
  maps = lock_switch_maps[sw].uniq.first(5).join(', ')
  puts "switch #{sw}: #{cnt} refs  [maps: #{maps}]"
end

puts ""
puts "=== 全部页可见性开关 Top30 (可能包含剧情/区域开关) ==="
page_switch_counts.sort_by { |k, v| -v }.first(30).each do |sw, cnt|
  puts "switch #{sw}: #{cnt} pages"
end
