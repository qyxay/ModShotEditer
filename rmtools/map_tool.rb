#!/usr/bin/env ruby
# ============================================================
#  map_tool.rb — 非 RMXP 的 OneShot 地图/NPC 编辑工具 (ModShot)
#  用法:
#    ruby map_tool.rb list
#    ruby map_tool.rb dump <mapid>
#    ruby map_tool.rb pull <mapid>            # 从游戏复制地图到 mod 目录
#    ruby map_tool.rb addnpc <mapid> <x> <y> <名字> [charset] ["对话文本"]
#    ruby map_tool.rb addmap <名字> <宽> <高> [tileset_id]
#    ruby map_tool.rb export <mapid> <out.json>
#    ruby map_tool.rb import <mapid> <in.json>
#    ruby map_tool.rb backup <mapid>
#  默认写入 mod 目录 (mods/MyMod/Data), 加 --game 才写真实游戏目录(自动备份)
# ============================================================
$LOAD_PATH.unshift File.dirname(__FILE__)
require "rxdata_stub"
require "json"
require "fileutils"

GAME_DIR = "C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot"
# 注意: mod 目录必须在游戏目录内 (modshot.json 的 patches 相对 gameFolder 解析)
MOD_DIR  = GAME_DIR + "/mods/mod/Data"

WRITE_GAME = ARGV.delete("--game")
DATA_DIR = WRITE_GAME ? "#{GAME_DIR}/Data" : MOD_DIR
BACKUP    = File.expand_path("backup", __dir__)

# ---------- 基础读写 ----------
def load_data(path) = Marshal.load(File.binread(path))
def save_data(obj, path)
  FileUtils.mkdir_p(File.dirname(path))
  File.binwrite(path, Marshal.dump(obj))
end
def map_path(dir, id) = "#{dir}/Map#{id.to_s.rjust(3, "0")}.rxdata"
def map_infos_path(dir) = "#{dir}/MapInfos.rxdata"
def map_infos(dir) = load_data(map_infos_path(dir))
def info_of(dir, id) = map_infos(dir)[id.to_i]

# ---------- 事件命令构造 ----------
def cmd(code, indent, params)
  c = RPG::EventCommand.new
  c.instance_variable_set(:@code, code)
  c.instance_variable_set(:@indent, indent)
  c.instance_variable_set(:@parameters, params)
  c
end

def make_move_cmd(code, params = [])
  c = RPG::MoveCommand.new
  c.instance_variable_set(:@code, code)
  c.instance_variable_set(:@parameters, params)
  c
end

# ---------- 新建事件页(带 RMXP 标准默认值) ----------
def new_page(charset = "", x = 0, y = 0, text = nil, trigger = 0)
  cond = RPG::Event::Page::Condition.new
  { :@switch1_id => 1, :@switch2_id => 1, :@variable_id => 1, :@variable_value => 0,
    :@switch1_valid => false, :@switch2_valid => false, :@variable_valid => false,
    :@self_switch_valid => false, :@self_switch_ch => "A" }.each { |k, v| cond.instance_variable_set(k, v) }

  gfx = RPG::Event::Page::Graphic.new
  { :@tile_id => 0, :@character_name => charset, :@direction => 2, :@pattern => 0,
    :@character_hue => 0, :@opacity => 255, :@blend_type => 0 }.each { |k, v| gfx.instance_variable_set(k, v) }

  route = RPG::MoveRoute.new
  route.instance_variable_set(:@repeat, true)
  route.instance_variable_set(:@skippable, false)
  route.instance_variable_set(:@list, [make_move_cmd(0)])

  cmds = []
  if text
    cmds << cmd(101, 0, ["", 0, 2])
    text.to_s.each_line.map(&:chomp).each { |ln| cmds << cmd(401, 0, [ln]) }
    cmds << cmd(0, 0, [])
  end

  pg = RPG::Event::Page.new
  { :@condition => cond, :@graphic => gfx, :@event_commands => cmds, :@list => cmds,
    :@trigger => trigger, :@move_route => route, :@move_type => 0,
    :@move_speed => 3, :@move_frequency => 3, :@walk_anime => true,
    :@step_anime => false, :@direction_fix => false, :@through => false,
    :@always_on_top => false, :@opacity => 255, :@blend_type => 0 }.each { |k, v| pg.instance_variable_set(k, v) }
  pg
end

def new_event(id, x, y, name, charset = "", text = nil)
  ev = RPG::Event.new
  { :@id => id, :@name => name, :@x => x, :@y => y, :@pages => [new_page(charset, x, y, text)] }.each { |k, v| ev.instance_variable_set(k, v) }
  ev
end

def new_map(w, h, tileset_id = 8)
  tpl = load_data(map_path(GAME_DIR + "/Data", 1))
  m = RPG::Map.new
  tpl.instance_variables.each { |iv| m.instance_variable_set(iv, tpl.instance_variable_get(iv)) }
  m.instance_variable_set(:@width, w)
  m.instance_variable_set(:@height, h)
  m.instance_variable_set(:@tileset_id, tileset_id)
  m.instance_variable_set(:@events, {})
  m.instance_variable_set(:@data, Table.new(w, h, 3))
  m.instance_variable_set(:@encounter_list, [])
  m
end

# ============ 命令实现 ============
def cmd_list
  mi = map_infos(GAME_DIR + "/Data")
  puts "%-6s %-8s %-28s %s" % ["ID", "Parent", "名称", "在mod目录?"]
  mi.keys.sort_by { |k| k.to_i }.each do |k|
    info = mi[k]
    inmod = File.exist?(map_path(MOD_DIR, k)) ? "yes" : "-"
    puts "%-6s %-8s %-28s %s" % [k, info.parent_id, info.name, inmod]
  end
end

def cmd_dump(id)
  dir = WRITE_GAME ? GAME_DIR + "/Data" : (File.exist?(map_path(MOD_DIR, id)) ? MOD_DIR : GAME_DIR + "/Data")
  pth = map_path(dir, id)
  unless File.exist?(pth)
    puts "地图 #{id} 不存在于 #{dir} (先用 pull 复制到 mod 目录?)"; return
  end
  m = load_data(pth)
  mi = info_of(dir, id)
  puts "地图 #{id}: #{mi ? mi.name : "(未登记)"}  #{m.width}x#{m.height}  tileset=#{m.tileset_id}"
  puts "图层: #{m.data.zsize}  autotiles: #{m.autotile_names.inspect}"
  puts "事件/NPC 数: #{m.events.size}"
  m.events.each do |eid, ev|
    gfx = ev.pages[0] ? ev.pages[0].graphic.character_name.inspect : "?"
    puts "  ##{eid} #{ev.name.inspect} @(#{ev.x},#{ev.y}) pages=#{ev.pages.size} gfx=#{gfx}"
  end
end

def cmd_pull(id)
  src = map_path(GAME_DIR + "/Data", id)
  abort "游戏里没有地图 #{id}" unless File.exist?(src)
  FileUtils.mkdir_p(MOD_DIR)
  FileUtils.cp(src, map_path(MOD_DIR, id))
  dst_inf = map_infos_path(MOD_DIR)
  FileUtils.cp(map_infos_path(GAME_DIR + "/Data"), dst_inf) unless File.exist?(dst_inf)
  puts "已复制 Map#{id.to_s.rjust(3,'0')}.rxdata 到 mod 目录: #{MOD_DIR}"
end

def cmd_addnpc(id, x, y, name, charset = "", text = nil)
  dir = File.exist?(map_path(MOD_DIR, id)) ? MOD_DIR : GAME_DIR + "/Data"
  pth = map_path(dir, id)
  abort "地图 #{id} 不存在 (先用 pull 复制)" unless File.exist?(pth)
  backup(pth)
  m = load_data(pth)
  nid = m.events.keys.max.to_i + 1
  m.events[nid] = new_event(nid, x.to_i, y.to_i, name, charset, text)
  save_data(m, pth)
  puts "已添加 NPC ##{nid} '#{name}' @(#{x},#{y}) 到 #{dir}"
  puts "  提示: charset 填 Graphics/Characters 下的文件名(不带扩展名)"
end

def cmd_addmap(name, w, h, tileset_id = 8)
  FileUtils.mkdir_p(MOD_DIR)
  mi = map_infos(MOD_DIR)
  nid = mi.keys.max.to_i + 1
  m = new_map(w.to_i, h.to_i, tileset_id.to_i)
  save_data(m, map_path(MOD_DIR, nid))
  info = RPG::MapInfo.new
  info.instance_variable_set(:@name, name)
  info.instance_variable_set(:@parent_id, 0)
  info.instance_variable_set(:@order, nid)
  info.instance_variable_set(:@expanded, true)
  info.instance_variable_set(:@scroll_x, 0)
  info.instance_variable_set(:@scroll_y, 0)
  mi[nid] = info
  save_data(mi, map_infos_path(MOD_DIR))
  puts "已创建新地图 #{nid} '#{name}' #{w}x#{h}  ->  #{MOD_DIR}"
  puts "  提示: 空地图 tileset=#{tileset_id}, 需复制 System.rxdata/Tilesets 到 mod 目录才能选对图块"
end

# ---------- 通用序列化 (导出/导入 JSON) ----------
def to_h(obj)
  case obj
  when Integer, Float, String, TrueClass, FalseClass, NilClass then obj
  when Symbol then obj.to_s
  when Array then obj.map { |o| to_h(o) }
  when Hash then obj.map { |k, v| [k.to_s, to_h(v)] }.to_h
  when Table then { "_t" => "Table", "x" => obj.xsize, "y" => obj.ysize, "z" => obj.zsize, "data" => obj.data }
  else
    h = { "_c" => obj.class.name.sub("RPG::", "") }
    obj.instance_variables.each { |iv| h[iv.to_s[1..]] = to_h(obj.instance_variable_get(iv)) }
    h
  end
end

def from_h(h)
  case h
  when Integer, Float, String, TrueClass, FalseClass, NilClass then h
  when Array then h.map { |o| from_h(o) }
  when Hash
    if h["_t"] == "Table"
      t = Table.new(h["x"], h["y"], h["z"])
      t.instance_variable_set(:@data, h["data"])
      t
    elsif (c = h["_c"])
      klass = Object.const_get("RPG::" + c)
      obj = klass.new
      h.each { |k, v| obj.instance_variable_set(("@" + k).to_sym, from_h(v)) unless k == "_c" }
      obj
    else
      h.map { |k, v| [k, from_h(v)] }.to_h
    end
  end
end

def cmd_export(id, out)
  dir = File.exist?(map_path(MOD_DIR, id)) ? MOD_DIR : GAME_DIR + "/Data"
  m = load_data(map_path(dir, id))
  File.write(out, JSON.pretty_generate(to_h(m)))
  puts "已导出 #{id} -> #{out} (#{File.size(out)} bytes)"
end

def cmd_import(id, inp)
  dir = File.exist?(map_path(MOD_DIR, id)) ? MOD_DIR : GAME_DIR + "/Data"
  pth = map_path(dir, id)
  backup(pth)
  m = from_h(JSON.parse(File.read(inp)))
  save_data(m, pth)
  puts "已从 #{inp} 导入到地图 #{id} (#{dir})"
end

def backup(pth)
  FileUtils.mkdir_p(BACKUP)
  b = File.join(BACKUP, File.basename(pth) + ".bak")
  FileUtils.cp(pth, b)
  puts "  备份: #{b}"
end

def cmd_backup(id)
  dir = File.exist?(map_path(MOD_DIR, id)) ? MOD_DIR : GAME_DIR + "/Data"
  pth = map_path(dir, id)
  abort "地图 #{id} 不存在" unless File.exist?(pth)
  backup(pth)
end

# ============ 主入口 ============
arg = ARGV.dup
cmd = arg.shift
begin
  case cmd
  when "list"    then cmd_list
  when "dump"    then cmd_dump(arg[0])
  when "pull"    then cmd_pull(arg[0])
  when "addnpc"  then cmd_addnpc(arg[0], arg[1], arg[2], arg[3], arg[4] || "", arg[5])
  when "addmap"  then cmd_addmap(arg[0], arg[1], arg[2], arg[3] || 8)
  when "export"  then cmd_export(arg[0], arg[1])
  when "import"  then cmd_import(arg[0], arg[1])
  when "backup"  then cmd_backup(arg[0])
  else
    puts File.read(__FILE__)[/^# =+.*?(?=^# ==)/m]
  end
rescue SystemExit
  raise
rescue StandardError => e
  puts "错误: #{e.message}"
  puts e.backtrace.first(5)
end
