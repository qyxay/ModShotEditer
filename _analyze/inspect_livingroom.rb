ROOT = File.expand_path('..', __dir__)
# ============================================================
#  临时分析脚本: 解析 Map004.rxdata (Livingroom)
#  重点: 事件触发器(autorun/parallel/player touch)、落点附近事件
# ============================================================

$LOAD_PATH.unshift("#{ROOT}/runtime/lib/ruby/3.1.0")
$LOAD_PATH.unshift("#{ROOT}/runtime/lib/ruby/3.1.0/x64-mingw64")

# --- 定义 mkxp/RGSS 数据类型空类, 使 Marshal.load 能反序列化 ---
module RPG
  class Map; end
  class MapInfo; end
  class Event; end
  class EventCommand; end
  class Tileset; end
  class System; end
  class AudioFile; end
  class MoveRoute; end
  class MoveCommand; end
  class CommonEvent; end
  class Troop; end
  class Troop::Page; end
  class Troop::Page::Condition; end
  class Troop::Page::Graphic; end
  class BattleEventPage; end
  class Skill; end
  class Item; end
  class Weapon; end
  class Armor; end
  class Enemy; end
  class Actor; end
  class Class; end
  class State; end
  class Animation; end
  class Animation::Timing; end
  class Animation::Frame; end
  class Enemy::Action; end
  class Enemy::DropItem; end
  class Enemy::Action; end
  class Actor; end
  class Class::Learning; end
  class Event
    class Page; end
    class Page::Condition; end
    class Page::Graphic; end
  end
end
class Table
  def self._load(str)
    t = allocate
    t.instance_variable_set(:@dummy, str)
    t
  end
  def _dump(*); @dummy || "\x00"*4; end
end

class Color
  def self._load(str); allocate; end
  def _dump(*); "\x00"*4; end
end

class Tone
  def self._load(str); allocate; end
  def _dump(*); "\x00"*4; end
end

class Rect
  def self._load(str); allocate; end
  def _dump(*); "\x00"*4; end
end

# 触发类型名称
TRIGGER = { 0=>'事件开始', 1=>'与主角接触', 2=>'与事件接触', 3=>'AUTORUN', 4=>'PARALLEL' }

map = Marshal.load(File.binread("#{ROOT}/OneShot/Data/Map004.rxdata"))

puts "== 地图信息 =="
puts "  map_id=4  width=#{map.instance_variable_get(:@width)}  height=#{map.instance_variable_get(:@height)}"
puts "  autoplay_bgm=#{map.instance_variable_get(:@autoplay_bgm).inspect}"
puts ""

events = map.instance_variable_get(:@events)
puts "== 事件总数: #{events.size} =="
puts ""

# 落点
spawn = [21, 10]

events.each do |id, ev|
  name = ev.instance_variable_get(:@name)
  x = ev.instance_variable_get(:@x)
  y = ev.instance_variable_get(:@y)
  pages = ev.instance_variable_get(:@pages)
  puts "--- 事件##{id}: '#{name}' @(#{x},#{y})  页数=#{pages ? pages.size : 0}"
  pages.each_with_index do |pg, pi|
    cond = pg.instance_variable_get(:@condition)
    trig = pg.instance_variable_get(:@trigger)
    list = pg.instance_variable_get(:@list)
    s1 = cond ? [cond.instance_variable_get(:@switch1_valid), cond.instance_variable_get(:@switch1_id)] : nil
    s2 = cond ? [cond.instance_variable_get(:@switch2_valid), cond.instance_variable_get(:@switch2_id)] : nil
    ss = cond ? [cond.instance_variable_get(:@self_switch_valid), cond.instance_variable_get(:@self_switch_ch)] : nil
    cond_str = []
    cond_str << "SW1=#{s1[1]}" if s1 && s1[0]
    cond_str << "SW2=#{s2[1]}" if s2 && s2[0]
    cond_str << "SELF=#{ss[1]}" if ss && ss[0]
    cond_str << "VAR" if cond && cond.instance_variable_get(:@variable_valid)
    cond_str = cond_str.empty? ? "无条件" : cond_str.join(",")
    # 命令摘要
    cmds = []
    if list
      list.each do |cmd|
        next unless cmd
        code = cmd.instance_variable_get(:@code)
        params = cmd.instance_variable_get(:@parameters)
        case code
        when 101 then cmds << "对话[#{params[0]}]"
        when 108, 408 then cmds << "注释[#{params[0]}]"
        when 111 then cmds << "条件分支(t#{params[0]},p#{params[1]})"
        when 355, 655 then cmds << "脚本[#{params[0]}]"
        when 122 then cmds << "变量操作"
        when 121 then cmds << "开关操作#{params[0]}-#{params[1]}=#{params[2]}"
        when 117 then cmds << "公共事件##{params[0]}"
        when 201 then cmds << "场所移动(地图#{params[1]},#{params[2]},#{params[3]})"
        end
      end
    end
    trig_name = TRIGGER[trig] || trig.inspect
    puts "    [页#{pi}] 触发器=#{trig_name}  条件: #{cond_str}"
    puts "        命令: #{cmds[0, 12].join(' | ')}#{cmds.size > 12 ? " ...(+#{cmds.size-12})" : ''}" unless cmds.empty?
  end
  # 落点/近旁标记
  dx = (x - spawn[0]).abs
  dy = (y - spawn[1]).abs
  if dx <= 2 && dy <= 2
    puts "    *** 距落点(21,10)较近 (dx=#{dx},dy=#{dy})"
  end
  puts ""
end
