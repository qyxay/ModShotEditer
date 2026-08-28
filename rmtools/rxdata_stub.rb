# RXData 工具用 RPG 类桩定义 + RMXP Table 自定义 Marshal 格式
# 仅供 Marshal.load/dump .rxdata 使用

# ============ RMXP Table (顶层类, 自定义 _dump/_load) ============
# 格式: 5xint32le(dim,xsize,ysize,zsize,size) + size x int16le
class Table
  attr_accessor :xsize, :ysize, :zsize, :data
  def initialize(x, y = 1, z = 1)
    @xsize = x; @ysize = y; @zsize = z
    @data = Array.new(x * y * z, 0)
  end
  def [](x, y = 0, z = 0)
    @data[x + y * @xsize + z * @xsize * @ysize]
  end
  def []=(x, y = 0, z = 0, v)
    @data[x + y * @xsize + z * @xsize * @ysize] = v
  end
  def _dump(limit)
    dim = @zsize > 1 ? 3 : (@ysize > 1 ? 2 : 1)
    size = @xsize * @ysize * @zsize
    [dim, @xsize, @ysize, @zsize, size].pack("V5") + @data.pack("s<*")
  end
  def self._load(str)
    _dim, x, y, z, size = str.unpack("V5")
    t = new(x, y, z)
    t.instance_variable_set(:@data, str.byteslice(20, size * 2).unpack("s<*"))
    t
  end
  def to_s
    "Table(#{@xsize}x#{@ysize}x#{@zsize})"
  end
end

# ============ RMXP 内置 RGSS 类 (Color/Tone/Rect, 自定义 _dump/_load) ============
# Color/Tone: 4 x float64le | Rect: 4 x int32le
class Color
  attr_accessor :red, :green, :blue, :alpha
  def initialize(r = 0, g = 0, b = 0, a = 255)
    @red = r; @green = g; @blue = b; @alpha = a
  end
  def _dump(limit)
    [@red, @green, @blue, @alpha].pack("E4")
  end
  def self._load(str)
    r, g, b, a = str.unpack("E4")
    new(r, g, b, a)
  end
end
class Tone
  attr_accessor :red, :green, :blue, :gray
  def initialize(r = 0, g = 0, b = 0, gr = 0)
    @red = r; @green = g; @blue = b; @gray = gr
  end
  def _dump(limit)
    [@red, @green, @blue, @gray].pack("E4")
  end
  def self._load(str)
    r, g, b, gr = str.unpack("E4")
    new(r, g, b, gr)
  end
end
class Rect
  attr_accessor :x, :y, :width, :height
  def initialize(x = 0, y = 0, w = 0, h = 0)
    @x = x; @y = y; @width = w; @height = h
  end
  def _dump(limit)
    [@x, @y, @width, @height].pack("l<4")
  end
  def self._load(str)
    x, y, w, h = str.unpack("l<4")
    new(x, y, w, h)
  end
end

module RPG
  Table = ::Table

  class Map
    attr_accessor :tileset_id, :width, :height, :autotile_names, :events, :data,
                  :encounter_list, :encounter_step, :parallax_name, :parallax_loop_x,
                  :parallax_loop_y, :parallax_sx, :parallax_sy, :parallax_show, :battleback_name
  end
  class MapInfo
    attr_accessor :name, :parent_id, :order, :expanded, :scroll_x, :scroll_y
  end
  class Event
    attr_accessor :id, :name, :x, :y, :pages, :command
  end
  class Event::Page
    attr_accessor :condition, :graphic, :event_commands, :trigger, :move_route,
                  :move_type, :move_speed, :move_frequency, :walk_anime, :step_anime,
                  :direction_fix, :through, :always_on_top, :opacity, :blend_type
  end
  class Event::Page::Condition
    attr_accessor :switch1_id, :switch2_id, :variable_id, :variable_value, :self_switch_ch
  end
  class Event::Page::Graphic
    attr_accessor :tile_id, :character_name, :direction, :pattern, :character_hue
  end
  class EventCommand
    attr_accessor :code, :indent, :parameters
  end
  class MoveRoute
    attr_accessor :repeat, :skippable, :list
  end
  class MoveCommand
    attr_accessor :code, :parameters
  end
  class AudioFile
    attr_accessor :name, :volume, :pitch
  end
  class BGM < AudioFile; end
  class BGS < AudioFile; end
  class ME < AudioFile; end
  class SE < AudioFile; end
  # 其余可能出现的类: 空壳
  class Actor; end
  class Skill; end
  class Item; end
  class Weapon; end
  class Armor; end
  class Enemy; end
  class Troop; end
  class State; end
  class Animation; end
  class CommonEvent; end
  class System; end
  class Tileset; end
  class Class; end
end