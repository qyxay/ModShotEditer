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

# --- 命令扫描: 提取 201 传送目标 + 条件上下文 + check_exit 出口 + CE 调用 ---
# 返回 { targets: [...], texts: [...], exit_area, exit_vars, ce_calls }
def scan_commands(list)
  result = { targets: [], texts: [], exit_vars: {}, ce_calls: [] }
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
    when 355, 655 # 脚本
      s = p[0].to_s
      if s =~ /check_exit\s*\(\s*(-?\d+)\s*,\s*(-?\d+)\s*(?:,\s*(x|y)\s*:\s*(-?\d+))?\s*\)|check_exit\s+(-?\d+)\s*,\s*(-?\d+)\s*(?:,\s*(x|y)\s*:\s*(-?\d+))?/
        if $3
          result[:exit_area] = { axis: $3, min: $1.to_i, max: $2.to_i, fixed: $4.to_i }
        elsif $7
          result[:exit_area] = { axis: $7, min: $5.to_i, max: $6.to_i, fixed: $8.to_i }
        else
          result[:exit_area] = { axis: nil, min: ($1 || $5).to_i, max: ($2 || $6).to_i, fixed: nil }
        end
      end
    when 122 # 变量操作 (OneShot exit 系统: var6=目标地图 7=x 8=y 9=d 10=偏移)
      vid = p[0]
      if [6, 7, 8, 9, 10].include?(vid) && p[2] == 0
        result[:exit_vars][vid] = p[4]
      end
    when 117 # 调用公共事件
      result[:ce_calls] << p[0]
    end
    i += 1
  end
  result
end

# --- check_exit 出口方向: CE5北(8) CE6南(2) CE7西(4) CE8东(6) ---
def exit_dir_from_ce(calls)
  { 5 => 8, 6 => 2, 7 => 4, 8 => 6 }.each do |ce_id, dir|
    return dir if calls.include?(ce_id)
  end
  nil
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
ce110_callers = []   # 调用 CE110(SQUARES BE GONE) 的地图事件 -> 剧情传送边
stats = { maps_with_doors: 0, dynamic_targets: 0, exit_events: 0 }

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
    is_exit = false

    pages.each_with_index do |pg, pi|
      next unless pg
      list = pg.instance_variable_get(:@list) || []
      scanned = scan_commands(list)
      # 只关注含传送或门样文本的页
      next if scanned[:targets].empty? && scanned[:texts].none? { |t| t =~ /lock|locked|seal/i } && scanned[:exit_area].nil?

      trig = pg.instance_variable_get(:@trigger)
      conds = page_conditions(pg)

      # check_exit 出口: 目标地图=var6, 坐标=var7/var8, 方向=CE5-8
      if scanned[:exit_area] && scanned[:exit_vars][6]
        v6 = scanned[:exit_vars][6]
        t = {
          map: v6,
          x: scanned[:exit_vars][7],
          y: scanned[:exit_vars][8],
          d: exit_dir_from_ce(scanned[:ce_calls]),
          kind: 'exit',
          area: scanned[:exit_area],
          via: [{ k: 'exit' }]
        }
        ev_targets << t
        is_exit = true
      end

      scanned[:targets].each do |t|
        ev_targets << t
        stats[:dynamic_targets] += 1 if t[:dynamic]
      end
      scanned[:texts].each { |t| ev_texts << t }
      # 记录首个传送页的触发/条件 (若前面页没记过)
      if ev_trigger.nil? && (scanned[:targets].any? || (scanned[:exit_area] && scanned[:exit_vars][6]))
        ev_trigger = trig
        ev_page = pi
        ev_page_conds = conds
      end
      # CE110 (SQUARES BE GONE) 调用者: 剧情传送边
      if scanned[:ce_calls].include?(110)
        ce110_callers << { map: mid, ev: eid, name: ename, x: ex, y: ey }
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
      kind: is_exit ? 'exit' : 'door',
      texts: ev_texts.first(3),
      targets: ev_targets
    }
  end
end

# CE110 剧情传送边: 调用者地图 -> map257(30,20)
ce110_callers.uniq.each do |c|
  doors << {
    map: c[:map],
    ev: c[:ev],
    name: c[:name] + ' [CE110]',
    x: c[:x],
    y: c[:y],
    trigger: nil,
    page: nil,
    page_conds: [],
    kind: 'common',
    texts: ['SQUARES BE GONE → map257'],
    targets: [{ map: 257, x: 30, y: 20, d: 0, kind: 'common', via: [{ k: 'ce', id: 110 }] }]
  }
end

doors.sort_by! { |d| [d[:map], d[:ev]] }
stats[:maps_with_doors] = doors.map { |d| d[:map] }.uniq.size
stats[:exit_events] = doors.count { |d| d[:kind] == 'exit' }

graph = {
  generated_at: Time.now.strftime('%Y-%m-%d %H:%M:%S'),
  maps: maps,
  doors: doors,
  stats: {
    maps: maps.size,
    total_events: total_events,
    door_events: doors.size,
    exit_events: stats[:exit_events],
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
puts "  其中: 普通门 #{doors.count { |d| d[:kind] == 'door' }} / check_exit 出口 #{stats[:exit_events]} / CE110剧情 #{doors.count { |d| d[:kind] == 'common' }}"
puts "动态目标(变量指定): #{stats[:dynamic_targets]}"
puts "输出: #{OUT_PATH}"

# 抽样打印几个典型门
puts "\n=== 抽样 (前 12 个) ==="
doors.first(12).each do |d|
  puts "map#{d[:map]} ev#{d[:ev]} '#{d[:name]}' @(#{d[:x]},#{d[:y]}) trig=#{d[:trigger]} page=#{d[:page]} kind=#{d[:kind]}"
  d[:targets].each do |t|
    if t[:dynamic]
      puts "   → [动态] var_ids=#{t[:var_ids].inspect} dir=#{t[:d]}"
    elsif t[:kind] == 'exit'
      puts "   → [exit] map#{t[:map]} (x=#{t[:x].inspect},y=#{t[:y].inspect}) dir=#{t[:d].inspect} area=#{t[:area].inspect}"
    else
      puts "   → map#{t[:map]} (#{t[:x]},#{t[:y]}) dir=#{t[:d]} via=#{t[:via].inspect}"
    end
  end
  puts "   文本: #{d[:texts].inspect}" unless d[:texts].empty?
end

# 打印 exit 边
exits = doors.select { |d| d[:kind] == 'exit' }
puts "\n=== check_exit 出口 (#{exits.size}) ==="
exits.each do |d|
  t = d[:targets].first
  puts "map#{d[:map]} ev#{d[:ev]} '#{d[:name]}' -> map#{t[:map]} (x=#{t[:x].inspect}, y=#{t[:y].inspect}, d=#{t[:d].inspect}) area=#{t[:area].inspect}"
end
