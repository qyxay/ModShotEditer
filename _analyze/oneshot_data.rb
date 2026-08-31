# ============================================================
#  OneShot/mkxp 数据统一解析工具
#  Table 格式: dim(int32) xsize(int32) ysize(int32) zsize(int32)
#              cell_count(int32) data(uint16 * cell_count)
# ============================================================

$LOAD_PATH.unshift('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/runtime/lib/ruby/3.1.0')
require 'json'

module RPG
  class Map; end
  class Event
    attr_accessor :id, :name, :x, :y, :pages, :list
  end
  class EventCommand
    attr_accessor :code, :parameters, :indent
  end
  class Tileset; end
  class AudioFile; end
  class MoveRoute; end
  class MoveCommand; end
  class Event
    class Page
      attr_accessor :condition, :graphic, :list, :trigger, :through
    end
    class Page::Condition
      attr_accessor :switch1_valid, :switch2_valid, :variable_valid, :self_switch_valid,
                    :switch1_id, :switch2_id, :variable_id, :variable_value, :self_switch_ch
    end
    class Page::Graphic
      attr_accessor :character_name
    end
  end
end
class Table
  attr_reader :xsize, :ysize, :zsize, :cell_count
  def self._load(s)
    t = allocate
    t.instance_variable_set(:@xsize, s[4, 4].unpack1('V'))
    t.instance_variable_set(:@ysize, s[8, 4].unpack1('V'))
    t.instance_variable_set(:@zsize, s[12, 4].unpack1('V'))
    t.instance_variable_set(:@cell_count, s[16, 4].unpack1('V'))
    t.instance_variable_set(:@data, s[20..].unpack('v*'))
    t
  end
  def _dump(*); "\x00" * 4; end
  def [](x, y = 0, z = 0)
    @data[x + @xsize * y + @xsize * @ysize * z] || 0
  end
end
class Color; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end
class Tone; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end
class Rect; def self._load(s); allocate; end; def _dump(*); "\x00"*4; end; end

DATA = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data'

def os_load_map(mid)
  Marshal.load(File.binread(format("#{DATA}/Map%03d.rxdata", mid)))
end

def os_load_tilesets
  ts = Marshal.load(File.binread("#{DATA}/Tilesets.rxdata"))
  passages = {}
  ts.each_with_index do |t, i|
    next unless t
    p = t.instance_variable_get(:@passages)
    if p && p.cell_count > 0 && p.xsize > 0
      # uint16 data; 只取前 xsize 个 (1D 通行性表)
      passages[i] = p
    end
  end
  passages
end

# 格 (x,y) 朝 d 方向 tile 是否可通行
def os_dir_passable(map, passages, x, y, d)
  ts = map.instance_variable_get(:@tileset_id)
  pass = passages[ts]
  data = map.instance_variable_get(:@data)
  [0, 1, 2].each do |z|
    tile = data[x, y, z]
    next if tile == 0
    bits = pass ? pass[tile] : nil
    next unless bits
    # 0x0F = 四向全不可通行
    if (bits & 0x0F) == 0x0F
      return false
    end
    # 方向位: 下=1 左=2 右=4 上=8 (RMXP 标准)
    bit = { 2 => 1, 4 => 2, 6 => 4, 8 => 8 }[d]
    return false if bit && (bits & bit) != 0
  end
  true
end

# 格 (x,y) 是否可站立: 四向至少1方向可走
def os_standable?(map, passages, x, y)
  w = map.instance_variable_get(:@width)
  h = map.instance_variable_get(:@height)
  return false if x < 0 || y < 0 || x >= w || y >= h
  [2, 4, 6, 8].any? { |d| os_dir_passable(map, passages, x, y, d) }
end

# 同格阻挡事件? (非 through 且图形非空)
def os_event_blocker?(map, x, y)
  evs = map.instance_variable_get(:@events)
  evs.each_value do |ev|
    next unless ev.instance_variable_get(:@x) == x && ev.instance_variable_get(:@y) == y
    pages = ev.instance_variable_get(:@pages)
    pages.each do |pg|
      c = pg.instance_variable_get(:@condition)
      cond_ok = !c.instance_variable_get(:@switch1_valid) &&
                !c.instance_variable_get(:@switch2_valid) &&
                !c.instance_variable_get(:@variable_valid) &&
                !c.instance_variable_get(:@self_switch_valid)
      next unless cond_ok
      graphic = pg.instance_variable_get(:@graphic)
      cname = graphic ? graphic.instance_variable_get(:@character_name).to_s : ''
      through = pg.instance_variable_get(:@through)
      return true if !through && !cname.empty?
    end
  end
  false
end

# 安全落点: 可站立 + 同格无阻挡事件
def os_safe_landing?(map, passages, x, y)
  return false unless os_standable?(map, passages, x, y)
  return false if os_event_blocker?(map, x, y)
  true
end
