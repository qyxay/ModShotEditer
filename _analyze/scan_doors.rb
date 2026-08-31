# 扫描 OneShot 地图事件, 分析门/锁/对话/剧情机制
# 用法: runtime\bin\ruby.exe _analyze\scan_doors.rb
DATA_DIR = File.join(__dir__, '..', 'OneShot', 'Data')

# 引擎内建类(mkxp C++ 扩展, 独立运行时缺失, 提供空壳供 Marshal 反序列化)
class Table
  def initialize(*args); end
  def [](*args); 0; end
  def []=(*args); 0; end
  def resize(*args); end
  def xsize; 0; end
  def ysize; 0; end
  def zsize; 0; end
  def self._load(s); new; end  # mkxp 二进制序列化, 数据不重要, 丢弃
end

class Color
  attr_accessor :red, :green, :blue, :alpha
  def initialize(*args); @red = @green = @blue = @alpha = 0; end
  def self._load(s); new; end
end

class Tone
  attr_accessor :red, :green, :blue, :gray
  def initialize(*args); @red = @green = @blue = @gray = 0; end
  def self._load(s); new; end
end

# RPG 空壳类(仅用于 Marshal 反序列化; 实例变量自动恢复, attr_accessor 提供读方法)
module RPG
  class AudioFile
    attr_accessor :name, :volume, :pitch
  end
  class BGM < AudioFile; end
  class BGS < AudioFile; end
  class ME < AudioFile; end
  class SE < AudioFile; end
  class MoveCommand
    attr_accessor :code, :parameters
  end
  class MoveRoute
    attr_accessor :repeat, :skippable, :list
  end
  class Map
    attr_accessor :events, :width, :height, :autoplay_bgm, :autoplay_bgs, :bgm, :bgs, :encounter_list, :encounter_step, :data, :tileset_id
  end
  class Event
    attr_accessor :id, :name, :pages, :x, :y
  end
  class Event::Page
    attr_accessor :list, :trigger, :condition, :graphic, :move_route, :move_frequency, :move_speed, :move_type, :priority_type, :walk_anime, :step_anime, :direction_fix, :through
  end
  class Event::Page::Condition
    attr_accessor :switch1_valid, :switch2_valid, :variable_valid, :self_switch_valid, :switch1_id, :switch2_id, :variable_id, :variable_value, :self_switch_ch
  end
  class Event::Page::Graphic
    attr_accessor :tile_id, :character_name, :character_hue, :direction, :pattern, :opacity, :blend_type
  end
  class EventCommand
    attr_accessor :code, :parameters, :indent
  end
  class MapInfo
    attr_accessor :name, :id, :parent_id, :order, :expanded, :scroll_x, :scroll_y
  end
  class Tileset
    attr_accessor :id, :name, :tileset_name, :autotile_names, :panorama_name, :panorama_hue, :fog_name, :fog_hue, :fog_opacity, :fog_blend_type, :fog_zoom, :fog_sx, :fog_sy, :battleback_name, :passages, :priorities, :terrain_tags
  end
  class System
    attr_accessor :magic_number, :party_members, :elements, :switches, :variables, :windowskin_name, :title_name, :gameover_name, :battle_transition, :title_bgm, :battle_bgm, :battle_end_me, :gameover_me, :cursor_se, :decision_se, :cancel_se, :buzzer_se, :equip_se, :shop_se, :save_se, :load_se, :battle_start_se, :escape_se, :actor_collapse_se, :enemy_collapse_se, :words, :test_battlers, :test_troop_id, :start_map_id, :start_x, :start_y, :battleback_name
  end
  class System::TestBattler
    attr_accessor :actor_id, :level, :weapon_id, :armor1_id, :armor2_id, :armor3_id, :armor4_id
  end
  class System::Words
    attr_accessor :gold, :hp, :sp, :str, :dex, :agi, :int, :atk, :pdef, :mdef, :weapon, :armor1, :armor2, :armor3, :armor4, :attack, :skill, :guard, :item, :equip
  end
  class CommonEvent
    attr_accessor :id, :name, :trigger, :switch_id, :list
  end
end

def load_rxdata(name)
  Marshal.load(File.binread(File.join(DATA_DIR, name)))
end

maps_info = load_rxdata('MapInfos.rxdata')
puts "=== MapInfos count: #{maps_info.size} ==="

# 收集地图文件名 → ID 映射 (Map001.rxdata → 1)
def map_id_from_file(name)
  name[/Map(\d+)\.rxdata/, 1].to_i
end

# 统计门/锁事件
door_events = []
dialog_events = 0
switch_refs = Hash.new(0)
variable_refs = Hash.new(0)

Dir.glob(File.join(DATA_DIR, 'Map*.rxdata')).each do |f|
  mid = map_id_from_file(File.basename(f))
  begin
    map = Marshal.load(File.binread(f))
  rescue StandardError => e
    puts "ERR #{f}: #{e}"
    next
  end
  info = maps_info[mid]
  mname = info ? info.name.to_s : '?'
  if !map.is_a?(RPG::Map)
    puts "MAP#{mid} NOT Map: #{map.class}"
    next
  end
  (map.events || {}).each do |eid, ev|
    next unless ev
    ename = ev.name.to_s
    low = ename.downcase
    # 事件命令扫描
    commands = []
    if ev.pages
      ev.pages.each do |pg|
        next unless pg && pg.list
        pg.list.each do |cmd|
          next unless cmd
          code = cmd.code
          params = cmd.parameters || []
          if code == 101
            dialog_events += 1
            commands << [:text, params[0].to_s]
          elsif code == 111 && params[0] == 0
            # 条件分支: 开关判断
            switch_refs[params[1]] += 1
            commands << [:switch_cond, params[1]]
          elsif code == 111 && params[0] == 1
            variable_refs[params[1]] += 1
            commands << [:var_cond, params[1]]
          elsif code == 122
            variable_refs[params[0]] += 1
            commands << [:var_set, params[0]]
          elsif code == 121
            switch_refs[params[0]] += 1
            commands << [:switch_set, params[0]]
          end
        end
      end
    end
    is_doorish = low =~ /door|lock|gate|seal/i
    has_locked_text = commands.any? { |c| c[0] == :text && c[1] =~ /lock|locked|seal/i }
    if is_doorish || has_locked_text
      door_events << { map: mid, mapname: mname, ev: eid, name: ename, cmds: commands }
    end
  end
end

puts "=== total dialog events: #{dialog_events} ==="
puts "=== door/lock-like events: #{door_events.size} ==="
door_events.first(60).each do |d|
  puts "--- map #{d[:map]} (#{d[:mapname]}) ev #{d[:ev]} '#{d[:name]}'"
  d[:cmds].each { |c| puts "    #{c[0]}: #{c[1]}" }
end
