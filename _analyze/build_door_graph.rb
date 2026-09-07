# ============================================================
#  build_door_graph.rb — 预扫描全部地图, 生成门连接图数据
#
#  输出: OneShot/mods/mod/settings/graph.json
#    maps  : 全部地图节点 (id + 名字)
#    doors : 门/连接事件 (触发类型/坐标/条件/传送目标列表)
#
#  用法: runtime\bin\ruby.exe _analyze\build_door_graph.rb
# ============================================================

ROOT = File.expand_path('..', __dir__)
DATA_DIR = File.join(ROOT, 'OneShot', 'Data')
OUT_PATH = File.join(ROOT, 'OneShot', 'mods', 'mod', 'settings', 'graph.json')

# --- 引擎内建类空壳 (供 Marshal 反序列化) ---
class Table
  def self._load(s); allocate; end
end
class Color
  def self._load(s); allocate; end
end
class Tone
  def self._load(s); allocate; end
end
module RPG
  class AudioFile; end
  class BGM < AudioFile; end
  class BGS < AudioFile; end
  class ME < AudioFile; end
  class SE < AudioFile; end
  class MoveCommand; end
  class MoveRoute; end
  class Map; end
  class Event; end
  class Event::Page; end
  class Event::Page::Condition; end
  class Event::Page::Graphic; end
  class EventCommand; end
  class MapInfo; end
  class Tileset; end
  class System; end
  class CommonEvent; end
end

def load_rxdata(name)
  Marshal.load(File.binread(File.join(DATA_DIR, name)))
end

def map_id_from_file(name)
  name[/Map(\d+)\.rxdata/, 1].to_i
end

# --- 页条件摘要 ---
def page_conditions(pg)
  cond = pg.instance_variable_get(:@condition)
  out = []
  if cond
    out << { k: 'sw', id: cond.instance_variable_get(:@switch1_id), v: true } if cond.instance_variable_get(:@switch1_valid)
    out << { k: 'sw', id: cond.instance_variable_get(:@switch2_id), v: false } if cond.instance_variable_get(:@switch2_valid)
    if cond.instance_variable_get(:@variable_valid)
      out << { k: 'var', id: cond.instance_variable_get(:@variable_id), v: cond.instance_variable_get(:@variable_value) }
    end
    if cond.instance_variable_get(:@self_switch_valid)
      out << { k: 'self', id: cond.instance_variable_get(:@self_switch_ch), v: true }
    end
  end
  out
end

# --- 命令扫描: 提取 201 传送目标 + 条件上下文 ---
# 返回 { targets: [...], texts: [...] }
def scan_commands(list)
  result = { targets: [], texts: [] }
  # 条件栈: 记录进入各分支时仍生效的条件分支 (111 静态可解析部分)
  cond_stack = []
  i = 0
  while i < list.size
    cmd = list[i]
    if cmd.nil?
      i += 1
      next
    end
    code = cmd.instance_variable_get(:@code)
    p = cmd.instance_variable_get(:@parameters) || []
    case code
    when 111 # 条件分支
      if p[0] == 0
        cond_stack << { k: 'sw', id: p[1], v: (p[2] != 0) }
      elsif p[0] == 1
        cond_stack << { k: 'var', id: p[1], v: p[2] }
      elsif p[0] == 12
        cond_stack << { k: 'self', id: p[1], v: true }
      else
        cond_stack << nil # 无法静态解析的分支类型
      end
    when 412 # 条件分支 Else
      # 弹出当前 if 的条件(若有), 并压入取反(仅开关可稳定取反)
      c = cond_stack.pop
      if c && c[:k] == 'sw'
        cond_stack << { k: 'sw', id: c[:id], v: !c[:v] }
      elsif c
        cond_stack << { k: 'not', inner: c }
      end
    when 413, 411, 404, 408, 4120 # 分支结束符
      # 分支结束: 出栈一次
      cond_stack.pop if cond_stack.any?
    when 201 # 传送玩家
      t = {}
      if p[0] == 0
        t = { map: p[1], x: p[2], y: p[3], d: p[4] }
      else
        t = { dynamic: true, var_ids: [p[1], p[2], p[3]], d: p[4] }
      end
      t[:via] = cond_stack.compact.dup
      result[:targets] << t
    when 101, 401 # 文本
      txt = p[0].to_s
      result[:texts] << txt unless txt.empty?
    end
    i += 1
  end
  result
end

# --- 主流程 ---
maps_info = load_rxdata('MapInfos.rxdata')
puts "MapInfos count: #{maps_info.size}"

maps = []
maps_info.each do |id, info|
  next unless info
  maps << { id: id, name: info.instance_variable_get(:@name).to_s }
end
maps.sort_by! { |m| m[:id] }

doors = []
total_events = 0
stats = { maps_with_doors: 0, dynamic_targets: 0 }

Dir.glob(File.join(DATA_DIR, 'Map*.rxdata')).sort.each do |f|
  mid = map_id_from_file(File.basename(f))
  begin
    map = Marshal.load(File.binread(f))
  rescue StandardError => e
    puts "ERR #{f}: #{e}"
    next
  end
  next unless map.is_a?(RPG::Map)

  evs = map.instance_variable_get(:@events) || {}
  evs.each do |eid, ev|
    next unless ev
    total_events += 1
    ename = ev.instance_variable_get(:@name).to_s
    ex = ev.instance_variable_get(:@x).to_i
    ey = ev.instance_variable_get(:@y).to_i
    pages = ev.instance_variable_get(:@pages) || []

    is_doorish = ename.downcase =~ /door|lock|gate|seal|exit|enter/i
    ev_targets = []
    ev_texts = []
    ev_trigger = nil
    ev_page = nil
    ev_page_conds = []

    pages.each_with_index do |pg, pi|
      next unless pg
      list = pg.instance_variable_get(:@list) || []
      scanned = scan_commands(list)
      # 只关注含传送或门样文本的页
      next if scanned[:targets].empty? && scanned[:texts].none? { |t| t =~ /lock|locked|seal/i }

      trig = pg.instance_variable_get(:@trigger)
      conds = page_conditions(pg)

      scanned[:targets].each do |t|
        ev_targets << t
        stats[:dynamic_targets] += 1 if t[:dynamic]
      end
      scanned[:texts].each { |t| ev_texts << t }
      # 记录首个传送页的触发/条件 (若前面页没记过)
      if ev_trigger.nil? && scanned[:targets].any?
        ev_trigger = trig
        ev_page = pi
        ev_page_conds = conds
      end
    end

    next if ev_targets.empty? && !is_doorish && ev_texts.none? { |t| t =~ /lock|locked|seal/i }

    doors << {
      map: mid,
      ev: eid,
      name: ename,
      x: ex,
      y: ey,
      trigger: ev_trigger,
      page: ev_page,
      page_conds: ev_page_conds || [],
      texts: ev_texts.first(3),
      targets: ev_targets
    }
  end
end

doors.sort_by! { |d| [d[:map], d[:ev]] }
stats[:maps_with_doors] = doors.map { |d| d[:map] }.uniq.size

graph = {
  generated_at: Time.now.strftime('%Y-%m-%d %H:%M:%S'),
  maps: maps,
  doors: doors,
  stats: {
    maps: maps.size,
    total_events: total_events,
    door_events: doors.size,
    maps_with_doors: stats[:maps_with_doors],
    dynamic_targets: stats[:dynamic_targets]
  }
}

require 'json'
require 'fileutils'
FileUtils.mkdir_p(File.dirname(OUT_PATH))
File.open(OUT_PATH, 'w') do |f|
  f.write(JSON.pretty_generate(graph))
end

puts "=== 结果 ==="
puts "地图: #{maps.size}, 事件总数: #{total_events}"
puts "门/连接事件: #{doors.size} (覆盖地图 #{stats[:maps_with_doors]} 张)"
puts "动态目标(变量指定): #{stats[:dynamic_targets]}"
puts "输出: #{OUT_PATH}"

# 抽样打印几个典型门
puts "\n=== 抽样 (前 12 个) ==="
doors.first(12).each do |d|
  puts "map#{d[:map]} ev#{d[:ev]} '#{d[:name]}' @(#{d[:x]},#{d[:y]}) trig=#{d[:trigger]} page=#{d[:page]}"
  d[:targets].each do |t|
    if t[:dynamic]
      puts "   → [动态] var_ids=#{t[:var_ids].inspect} dir=#{t[:d]}"
    else
      puts "   → map#{t[:map]} (#{t[:x]},#{t[:y]}) dir=#{t[:d]} via=#{t[:via].inspect}"
    end
  end
  puts "   文本: #{d[:texts].inspect}" unless d[:texts].empty?
end
