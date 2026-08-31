# 打印真实地图的 layer 0 tile -> passages 值分布, 确定通行判定
class Table
  def initialize(x, y = 0, z = 0)
    @x = x; @y = y; @z = z
    @data = Array.new(x * y * z, 0)
    @dim = 1 + (y > 0 ? 1 : 0) + (z > 0 ? 1 : 0)
  end
  attr_accessor :data, :x, :y, :z, :dim
  def [](x, y = 0, z = 0); @data[x + y * @x + z * @x * @y]; end
  def []=(*args)
    x = args[0]; y = args.size > 2 ? args[1] : 0; z = args.size > 3 ? args[2] : 0; v = args.pop
    @data[x + y * @x + z * @x * @y] = v
  end
  def _dump(limit)
    [@dim, @x, @y, @z, @x * @y * @z].pack('L5') + @data.pack('v*')
  end
  def self._load(s)
    dim, x, y, z, size = s.unpack('L5')
    data = s.byteslice(20, size * 2).unpack('v*')
    t = Table.new(x, y, z)
    t.instance_variable_set(:@dim, dim)
    t.instance_variable_set(:@data, data)
    t
  end
end

class Color
  def initialize(r = 0, g = 0, b = 0, a = 255)
    @red = r; @green = g; @blue = b; @alpha = a
  end
  attr_accessor :red, :green, :blue, :alpha
  def _dump(limit); [@red, @green, @blue, @alpha].pack('e4'); end
  def self._load(s); r, g, b, a = s.unpack('e4'); Color.new(r, g, b, a); end
end
class Tone
  def initialize(r = 0, g = 0, b = 0, gray = 0)
    @red = r; @green = g; @blue = b; @gray = gray
  end
  attr_accessor :red, :green, :blue, :gray
  def _dump(limit); [@red, @green, @blue, @gray].pack('e4'); end
  def self._load(s); r, g, b, a = s.unpack('e4'); Tone.new(r, g, b, a); end
end

module RPG
  Table = ::Table unless const_defined?(:Table)
  class AudioFile
    def initialize(name = '', volume = 100, pitch = 100)
      @name = name; @volume = volume; @pitch = pitch
    end
    attr_accessor :name, :volume, :pitch
  end
  class MoveCommand
    def initialize(code = 0, parameters = [])
      @code = code; @parameters = parameters
    end
    attr_accessor :code, :parameters
  end
  class MoveRoute
    def initialize
      @repeat = true; @skippable = false; @wait = false; @list = [RPG::MoveCommand.new]
    end
    attr_accessor :repeat, :skippable, :wait, :list
  end
  class EventCommand
    def initialize(code = 0, indent = 0, parameters = [])
      @code = code; @indent = indent; @parameters = parameters
    end
    attr_accessor :code, :indent, :parameters
  end
  class Event
    def initialize(x, y)
      @id = 0; @name = ''; @x = x; @y = y
      @pages = [RPG::Event::Page.new]
    end
    class Page
      def initialize
        @condition = RPG::Event::Page::Condition.new
        @graphic = RPG::Event::Page::Graphic.new
        @event_commands = []
      end
      class Condition
        def initialize
          @switch1_valid = false; @switch2_valid = false
          @variable_valid = false; @self_switch_valid = false
          @switch1_id = 1; @switch2_id = 1; @variable_id = 1; @variable_value = 0
          @self_switch_ch = 'A'
        end
        attr_accessor :switch1_valid, :switch2_valid, :variable_valid, :self_switch_valid,
                      :switch1_id, :switch2_id, :variable_id, :variable_value, :self_switch_ch
      end
      class Graphic
        def initialize
          @tile_id = 0; @character_name = ''; @character_index = 0; @direction = 2; @pattern = 0
        end
        attr_accessor :tile_id, :character_name, :character_index, :direction, :pattern
      end
      attr_accessor :condition, :graphic, :list, :event_commands
    end
    attr_accessor :id, :name, :x, :y, :pages
  end
  class Map
    def initialize(width, height)
      @display_name = ''; @tileset_id = 1; @width = width; @height = height
      @autoplay_bgm = false; @bgm = RPG::AudioFile.new
      @autoplay_bgs = false; @bgs = RPG::AudioFile.new
      @encounter_list = []; @encounter_step = 30
      @parallax_name = ''; @parallax_loop_x = false; @parallax_loop_y = false
      @parallax_sx = 0; @parallax_sy = 0; @parallax_show = false; @note = ''
      @data = RPG::Table.new(width, height); @events = {}
    end
    attr_accessor :display_name, :tileset_id, :width, :height, :autoplay_bgm, :bgm,
                  :autoplay_bgs, :bgs, :encounter_list, :encounter_step,
                  :parallax_name, :parallax_loop_x, :parallax_loop_y,
                  :parallax_sx, :parallax_sy, :parallax_show, :note, :data, :events
  end
  class MapInfo
    def initialize
      @name = ''; @parent_id = 0; @order = 0; @expanded = false; @scroll_x = 0; @scroll_y = 0
    end
    attr_accessor :name, :parent_id, :order, :expanded, :scroll_x, :scroll_y
  end
  class Tileset
    attr_accessor :id, :name, :passages, :priorities, :terrain_tags
  end
end

base = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data/'
ts_all = Marshal.load(File.binread(base + 'Tilesets.rxdata'))
mi = Marshal.load(File.binread(base + 'MapInfos.rxdata'))

# 扫描全部地图的 Transfer Player(201) 事件命令, 收集目标坐标 (map_id, x, y)
# map_id=0 表示相对传送(当前地图), 归属到源地图
targets = Hash.new { |h, k| h[k] = [] }
Dir[base + 'Map*.rxdata'].each do |path|
  next unless path =~ /Map(\d+)\.rxdata$/
  mid = Regexp.last_match(1).to_i
  m = Marshal.load(File.binread(path))
  m.events.values.each do |ev|
    ev.pages.each do |pg|
      pg.list.each do |cmd|
        if cmd.code == 201
          p = cmd.parameters
          # VX 201: [map_id, x, y, direction, fade]
          dst = p[0] == 0 ? mid : p[0]
          targets[dst] << [p[1], p[2]]
        end
      end
    end
  end
end

# ===== 最终预扫描: 为每张地图生成安全落点 =====
# 策略: 1) 转移目标点(游戏作者钦定可走) 2) 无则扫描 passages & 0x0F/0x80 地面 3) 全无则标记
require 'json'

transfer_pts = Hash.new { |h, k| h[k] = [] }
Dir[base + 'Map*.rxdata'].each do |path|
  next unless path =~ /Map(\d+)\.rxdata$/
  mid = Regexp.last_match(1).to_i
  m = Marshal.load(File.binread(path))
  m.events.values.each do |ev|
    ev.pages.each do |pg|
      pg.list.each do |cmd|
        if cmd.code == 201
          p = cmd.parameters
          # OneShot 201: [method, map_id, x, y, dir, fade]
          # method==0 直接指定; 否则 map_id/x/y 是变量 id, 离线无法解析
          if p[0] == 0
            transfer_pts[p[1]] << { x: p[2], y: p[3], dir: p[4].to_i }
          else
            # 变量模式: 记录到源地图的变量引用, 落点未知, 跳过
            transfer_pts[mid] << nil # 标记该地图有变量式传送, 仍需地面扫描
          end
        end
      end
    end
  end
end

result = {}
inter = 0
no_spot = []
Dir[base + 'Map*.rxdata'].each do |path|
  next unless path =~ /Map(\d+)\.rxdata$/
  mid = Regexp.last_match(1).to_i
  name = mi[mid] ? mi[mid].name : '?'
  m = Marshal.load(File.binread(path))
  ts = ts_all[m.tileset_id]

  spot = nil
  # 1) 转移点(仅 direct 模式)
  direct_pts = transfer_pts[mid].reject { |e| e.nil? }
  if direct_pts.size > 0
    p0 = direct_pts.first
    spot = { x: p0[:x], y: p0[:y], dir: p0[:dir] }
  end
  # 2) 无转移点则扫地面
  unless spot
    (0...m.height).each do |y|
      (0...m.width).each do |x|
        t = nil
        [0, 1, 2].each do |i|
          v = m.data[x, y, i]
          if v && v != 0
            t = v; break
          end
        end
        next if t.nil?
        f = ts.passages[t] || 0
        if f & 0x0F != 0 || f & 0x80 != 0
          spot = { x: x, y: y, dir: 2 }
          break
        end
      end
      break if spot
    end
  end
  # 3) 全无
  if spot
    result[mid] = { 'name' => name, 'x' => spot[:x], 'y' => spot[:y], 'dir' => spot[:dir] }
  else
    no_spot << mid
    result[mid] = { 'name' => name, 'x' => -1, 'y' => -1, 'dir' => 2 }
    inter += 1
  end
end

puts "maps with spot = #{result.size - no_spot.size}, no spot = #{no_spot.size}"
puts "no-spot maps: #{no_spot.inspect}"
out = File.join('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/mods/mod', 'jump_points.json')
File.open(out, 'w') { |f| f.puts JSON.pretty_generate(result) }
puts "saved -> #{out}"
# 打印前 40 个有落点的地图
n = 0
result.sort.each do |mid, r|
  next if r['x'] < 0
  puts format('%3d %-22s -> (%d, %d) dir=%d', mid, r['name'], r['x'], r['y'], r['dir'])
  n += 1
  break if n >= 40
end
