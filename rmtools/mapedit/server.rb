#!/usr/bin/env ruby
# ============================================================
#  OneShot 可视化地图编辑器 - 本地服务 (ModShot 工作台)
#  启动:  ruby server.rb [端口]   (默认 8737)
#  然后浏览器打开 http://localhost:8737
#
#  功能:
#   - 地图列表 / 加载地图(3层瓦片+事件+bgm) / 保存回 mod 目录
#   - tileset 图块 + autotile 面板数据
#   - 图片代理: tileset PNG / autotile PNG (浏览器直接显示)
#   - 保存到 mods/mod/Data/ (patches 覆盖), 不碰原版
# ============================================================
require 'socket'
require 'json'
require 'cgi'
require 'fileutils'

# ---------- 路径 ----------
ROOT = File.expand_path(File.join(__dir__, '..', '..'))           # ModShot-mkxp-z
GAME_DIR = File.join(ROOT, 'OneShot')                             # 游戏副本
DATA_DIR = File.join(GAME_DIR, 'Data')
MOD_DATA = File.join(GAME_DIR, 'mods', 'mod', 'Data')             # 编辑落点
GRAPHICS = File.join(GAME_DIR, 'Graphics')
PORT = (ARGV[0] || 8737).to_i

FileUtils.mkdir_p(MOD_DATA)

# ---------- rxdata 读写 (复用 rxdata_stub) ----------
$LOAD_PATH.unshift File.expand_path(File.join(__dir__, '..'))
require 'rxdata_stub'

def load_data(path) = Marshal.load(File.binread(path))
def dump_data(obj, path)
  FileUtils.mkdir_p(File.dirname(path))
  File.binwrite(path, Marshal.dump(obj))
end

def map_path(id) = File.join(DATA_DIR, "Map#{id.to_s.rjust(3, '0')}.rxdata")
def mod_map_path(id) = File.join(MOD_DATA, "Map#{id.to_s.rjust(3, '0')}.rxdata")
def map_infos = @map_infos ||= load_data(File.join(DATA_DIR, 'MapInfos.rxdata'))
def tilesets = @tilesets ||= load_data(File.join(DATA_DIR, 'Tilesets.rxdata'))

# ---------- 对象 -> 可 JSON 结构 ----------
def o2j(obj)
  case obj
  when Integer, Float, String, TrueClass, FalseClass, NilClass then obj
  when RPG::AudioFile
    { 'audio' => [obj.instance_variable_get(:@name), obj.instance_variable_get(:@volume), obj.instance_variable_get(:@pitch)] }
  when RPG::Event::Page::Condition
    {
      'sw1' => obj.instance_variable_get(:@switch1_valid) ? obj.instance_variable_get(:@switch1_id) : nil,
      'sw2' => obj.instance_variable_get(:@switch2_valid) ? obj.instance_variable_get(:@switch2_id) : nil,
      'var' => obj.instance_variable_get(:@variable_valid) ? [obj.instance_variable_get(:@variable_id), obj.instance_variable_get(:@variable_value)] : nil,
      'self' => obj.instance_variable_get(:@self_switch_valid) ? obj.instance_variable_get(:@self_switch_ch) : nil
    }
  when RPG::Event::Page::Graphic
    {
      'tile_id' => obj.instance_variable_get(:@tile_id),
      'char' => obj.instance_variable_get(:@character_name),
      'dir' => obj.instance_variable_get(:@direction),
      'pattern' => obj.instance_variable_get(:@pattern),
      'hue' => obj.instance_variable_get(:@character_hue),
      'opacity' => obj.instance_variable_get(:@opacity),
      'blend' => obj.instance_variable_get(:@blend_type)
    }
  when RPG::Event::Page
    cond = obj.instance_variable_get(:@condition)
    gfx = obj.instance_variable_get(:@graphic)
    cmds = obj.instance_variable_get(:@list) || []
    {
      'condition' => o2j(cond),
      'graphic' => o2j(gfx),
      'trigger' => obj.instance_variable_get(:@trigger),
      'move_type' => obj.instance_variable_get(:@move_type),
      'move_speed' => obj.instance_variable_get(:@move_speed),
      'move_frequency' => obj.instance_variable_get(:@move_frequency),
      'commands' => cmds.map { |c| [c.instance_variable_get(:@code), c.instance_variable_get(:@indent), c.instance_variable_get(:@parameters)] }
    }
  when RPG::Event
    { 'id' => obj.instance_variable_get(:@id), 'name' => obj.instance_variable_get(:@name),
      'x' => obj.instance_variable_get(:@x), 'y' => obj.instance_variable_get(:@y),
      'pages' => obj.instance_variable_get(:@pages).map { |p| o2j(p) } }
  when RPG::Map
    data = obj.instance_variable_get(:@data)
    w, h, z = data.xsize, data.ysize, data.zsize
    layers = Array.new(z) { Array.new(h) { Array.new(w, 0) } }
    (0...h).each do |j|
      (0...w).each do |i|
        (0...z).each { |l| layers[l][j][i] = data[i, j, l] }
      end
    end
    {
      'id' => nil, 'width' => w, 'height' => h, 'tileset_id' => obj.instance_variable_get(:@tileset_id),
      'autoplay_bgm' => obj.instance_variable_get(:@autoplay_bgm),
      'bgm' => o2j(obj.instance_variable_get(:@bgm)),
      'autoplay_bgs' => obj.instance_variable_get(:@autoplay_bgs),
      'bgs' => o2j(obj.instance_variable_get(:@bgs)),
      'encounter_list' => obj.instance_variable_get(:@encounter_list) || [],
      'encounter_step' => obj.instance_variable_get(:@encounter_step) || 30,
      'layers' => layers,
      'events' => obj.instance_variable_get(:@events).values.sort_by { |e| e.instance_variable_get(:@id) }.map { |e| o2j(e) }
    }
  else
    # 通用 fallback
    obj.instance_variables.map { |iv| [iv.to_s[1..], obj.instance_variable_get(iv).to_s] }.to_h
  end
end

# ---------- JSON -> 对象 ----------
def j2cmd(arr)
  c = RPG::EventCommand.new
  c.instance_variable_set(:@code, arr[0])
  c.instance_variable_set(:@indent, arr[1] || 0)
  c.instance_variable_set(:@parameters, arr[2] || [])
  c
end

def j2page(pj)
  pg = RPG::Event::Page.new
  cond = RPG::Event::Page::Condition.new
  gfx = RPG::Event::Page::Graphic.new
  pg.instance_variable_set(:@condition, cond)
  pg.instance_variable_set(:@graphic, gfx)
  c = pj['condition'] || {}
  cond.instance_variable_set(:@switch1_valid, !!c['sw1'])
  cond.instance_variable_set(:@switch1_id, c['sw1'] || 1)
  cond.instance_variable_set(:@switch2_valid, !!c['sw2'])
  cond.instance_variable_set(:@switch2_id, c['sw2'] || 1)
  cond.instance_variable_set(:@variable_valid, !!(c['var']))
  cond.instance_variable_set(:@variable_id, (c['var'] || [1])[0])
  cond.instance_variable_set(:@variable_value, (c['var'] || [1, 0])[1])
  cond.instance_variable_set(:@self_switch_valid, !!(c['self']))
  cond.instance_variable_set(:@self_switch_ch, c['self'] || 'A')
  g = pj['graphic'] || {}
  gfx.instance_variable_set(:@tile_id, g['tile_id'] || 0)
  gfx.instance_variable_set(:@character_name, g['char'] || '')
  gfx.instance_variable_set(:@direction, g['dir'] || 2)
  gfx.instance_variable_set(:@pattern, g['pattern'] || 0)
  gfx.instance_variable_set(:@character_hue, g['hue'] || 0)
  gfx.instance_variable_set(:@opacity, g['opacity'] || 255)
  gfx.instance_variable_set(:@blend_type, g['blend'] || 0)
  pg.instance_variable_set(:@trigger, pj['trigger'] || 0)
  pg.instance_variable_set(:@move_type, pj['move_type'] || 0)
  pg.instance_variable_set(:@move_speed, pj['move_speed'] || 3)
  pg.instance_variable_set(:@move_frequency, pj['move_frequency'] || 3)
  # 其余标准字段默认值 (避免 nil 写入)
  pg.instance_variable_set(:@walk_anime, true)
  pg.instance_variable_set(:@step_anime, false)
  pg.instance_variable_set(:@direction_fix, false)
  pg.instance_variable_set(:@through, false)
  pg.instance_variable_set(:@always_on_top, false)
  pg.instance_variable_set(:@opacity, 255)
  pg.instance_variable_set(:@blend_type, 0)
  route = RPG::MoveRoute.new
  route.instance_variable_set(:@repeat, true)
  route.instance_variable_set(:@skippable, false)
  route.instance_variable_set(:@list, [])
  pg.instance_variable_set(:@move_route, route)
  cmds = (pj['commands'] || []).map { |a| j2cmd(a) }
  pg.instance_variable_set(:@list, cmds)
  pg
end

def j2event(ej)
  ev = RPG::Event.new
  ev.instance_variable_set(:@id, ej['id'])
  ev.instance_variable_set(:@name, ej['name'] || 'EV')
  ev.instance_variable_set(:@x, ej['x'] || 0)
  ev.instance_variable_set(:@y, ej['y'] || 0)
  ev.instance_variable_set(:@pages, (ej['pages'] || []).map { |p| j2page(p) })
  ev
end

# ---------- 路由 ----------
def send_resp(sock, code, body, ctype = 'text/html')
  header = "HTTP/1.1 #{code} #{code == 200 ? 'OK' : 'Not Found'}\r\n" \
           "Content-Type: #{ctype}\r\n" \
           "Content-Length: #{body.bytesize}\r\n" \
           "Cache-Control: no-store\r\n" \
           "Access-Control-Allow-Origin: *\r\n" \
           "Connection: close\r\n\r\n"
  sock.write(header)
  sock.write(body)
rescue Errno::EPIPE, IOError
end

def serve_file(sock, path, ctype)
  if File.exist?(path)
    send_resp(sock, 200, File.binread(path), ctype)
  else
    send_resp(sock, 404, 'not found', 'text/plain')
  end
end

def ctype_for(path)
  case File.extname(path).downcase
  when '.png' then 'image/png'
  when '.jpg', '.jpeg' then 'image/jpeg'
  when '.js' then 'application/javascript'
  when '.css' then 'text/css'
  when '.html' then 'text/html'
  else 'application/octet-stream'
  end
end

def handle(sock, req_line, headers, body)
  method, path, _ = req_line.split(' ', 3)
  path = path.split('?')[0]
  path = '/' if path.empty?

  if path == '/' || path == '/index.html'
    serve_file(sock, File.join(__dir__, 'editor.html'), 'text/html; charset=utf-8')
  elsif path == '/editor.js'
    serve_file(sock, File.join(__dir__, 'editor.js'), 'application/javascript; charset=utf-8')
  elsif path == '/editor.css'
    serve_file(sock, File.join(__dir__, 'editor.css'), 'text/css; charset=utf-8')

  elsif path == '/api/maps'
    infos = map_infos
    list = infos.keys.sort_by(&:to_i).map do |k|
      info = infos[k]
      { 'id' => k.to_i, 'name' => info.instance_variable_get(:@name),
        'parent' => info.instance_variable_get(:@parent_id),
        'in_mod' => File.exist?(mod_map_path(k)) }
    end
    send_resp(sock, 200, JSON.generate(list), 'application/json')

  elsif path =~ %r{^/api/map/(\d+)$}
    id = $1.to_i
    src = File.exist?(mod_map_path(id)) ? mod_map_path(id) : map_path(id)
    if File.exist?(src)
      m = load_data(src)
      m.instance_variable_set(:@id, id)
      info = map_infos[id]
      name = info ? info.instance_variable_get(:@name) : ''
      j = o2j(m)
      j['id'] = id
      j['name'] = name
      j['in_mod'] = File.exist?(mod_map_path(id))
      send_resp(sock, 200, JSON.generate(j), 'application/json')
    else
      send_resp(sock, 404, 'map not found', 'text/plain')
    end

  elsif path == '/api/save' && method == 'POST'
    begin
      j = JSON.parse(body)
      id = j['id'].to_i
      base_path = File.exist?(mod_map_path(id)) ? mod_map_path(id) : map_path(id)
      base = load_data(base_path)
      base.instance_variable_set(:@data, Table.new(j['width'], j['height'], j['layers'].size))
      data = base.instance_variable_get(:@data)
      j['layers'].each_with_index do |layer, l|
        layer.each_with_index do |row, yy|
          row.each_with_index { |v, xx| data[xx, yy, l] = v }
        end
      end
      evs = {}
      (j['events'] || []).each { |ej| evs[ej['id']] = j2event(ej) }
      base.instance_variable_set(:@events, evs)
      dump_data(base, mod_map_path(id))
      send_resp(sock, 200, JSON.generate({ 'ok' => true, 'saved' => mod_map_path(id) }), 'application/json')
    rescue => e
      send_resp(sock, 500, JSON.generate({ 'ok' => false, 'error' => "#{e.class}: #{e.message}" }), 'application/json')
    end

  elsif path == '/api/restore' && method == 'POST'
    j = JSON.parse(body)
    id = j['id'].to_i
    File.delete(mod_map_path(id)) if File.exist?(mod_map_path(id))
    send_resp(sock, 200, JSON.generate({ 'ok' => true }), 'application/json')

  elsif path =~ %r{^/api/tileset/(\d+)$}
    id = $1.to_i
    t = tilesets[id]
    if t
      flags = t.instance_variable_get(:@flags)
      passages = t.instance_variable_get(:@passages)
      flags_a = nil
      flags_a = flags.data[0, flags.data.size] if flags && flags.respond_to?(:data)
      send_resp(sock, 200, JSON.generate({
        'id' => id,
        'tileset_name' => t.instance_variable_get(:@tileset_name) || '',
        'autotile_names' => t.instance_variable_get(:@autotile_names) || [],
        'flags' => flags_a,
        'passages' => (passages && passages.respond_to?(:data)) ? passages.data[0, passages.data.size] : nil
      }), 'application/json')
    else
      send_resp(sock, 404, 'tileset not found', 'text/plain')
    end

  elsif path == '/api/chars'
    list = Dir.glob(File.join(GRAPHICS, 'Characters', '*.png')).map { |f| File.basename(f, '.png') }.sort
    send_resp(sock, 200, JSON.generate(list), 'application/json')

  elsif path =~ %r{^/img/tileset/(.+)$}
    name = CGI.unescape($1)
    name += '.png' unless name.downcase.end_with?('.png')
    serve_file(sock, File.join(GRAPHICS, 'Tilesets', name), 'image/png')
  elsif path =~ %r{^/img/autotile/(.+)$}
    name = CGI.unescape($1)
    name += '.png' unless name.downcase.end_with?('.png')
    serve_file(sock, File.join(GRAPHICS, 'Autotiles', name), 'image/png')
  elsif path =~ %r{^/img/char/(.+)$}
    name = CGI.unescape($1)
    name += '.png' unless name.downcase.end_with?('.png')
    serve_file(sock, File.join(GRAPHICS, 'Characters', name), 'image/png')

  else
    send_resp(sock, 404, 'not found', 'text/plain')
  end
end

puts "OneShot 地图编辑器服务  http://localhost:#{PORT}"
puts "数据目录: #{GAME_DIR}"
puts "保存到:   #{MOD_DATA}"
puts "按 Ctrl+C 停止"

server = TCPServer.new('127.0.0.1', PORT)
loop do
  sock = server.accept
  Thread.new(sock) do |s|
    begin
      begin
        s.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, [5, 0].pack('l_2'))
      rescue; end
      req_line = s.gets
      next unless req_line
      headers = {}
      while (line = s.gets)
        line = line.chomp
        break if line.empty?
        k, v = line.split(':', 2)
        headers[k.strip.downcase] = v.strip if v
      end
      method = req_line.split(' ', 2)[0]
      body = ''
      if method == 'POST' && headers['content-length']
        body = s.read(headers['content-length'].to_i) rescue ''
      end
      handle(s, req_line, headers, body)
    rescue => e
      begin
        send_resp(s, 500, "server error: #{e.message}\n#{e.backtrace.first(5).join("\n")}", 'text/plain')
      rescue; end
    ensure
      s.close rescue nil
    end
  end
end
