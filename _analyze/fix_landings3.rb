ROOT = File.expand_path('..', __dir__)
# ============================================================
#  严格修正 jump_points.json 落点 (v3)
#  安全格: 可站立 + 同格无任何事件 (避免站床/家具/NPC 上)
# ============================================================

require_relative 'oneshot_data'

JP = "#{ROOT}/OneShot/mods/mod/jump_points.json"

passages = os_load_tilesets
d = JSON.parse(File.read(JP))
File.write(JP.sub('.json', '.backup3.json'), JSON.pretty_generate(d))

# 同格是否有任何事件
def any_event?(map, x, y)
  evs = map.instance_variable_get(:@events)
  evs.each_value.any? { |ev| ev.instance_variable_get(:@x) == x && ev.instance_variable_get(:@y) == y }
end

def safe?(map, passages, x, y)
  return false unless os_standable?(map, passages, x, y)
  return false if any_event?(map, x, y)
  true
end

FILTER = /IGNORE|DEBUG|INTERNAL|UNUSED|\bTEST\b|^INIT\b|TELEPORT|DEMO|PROTOWALK|PSHOT/i
NAME_PAT = /^[TCS]\d+$/i

changes = []
checked = 0
d.each do |id, m|
  next unless m.is_a?(Hash)
  x = m['x'].to_i; y = m['y'].to_i
  name = m['name'].to_s
  next if name =~ FILTER || name =~ NAME_PAT
  next if x < 0 || y < 0
  begin
    map = os_load_map(id.to_i)
    checked += 1
    next if safe?(map, passages, x, y)
    # BFS
    w = map.instance_variable_get(:@width)
    h = map.instance_variable_get(:@height)
    q = [[x, y]]
    visited = { [x, y] => true }
    found = nil
    until q.empty? || found
      cx, cy = q.shift
      if safe?(map, passages, cx, cy)
        found = [cx, cy]
        break
      end
      [[2, 0, 1], [4, -1, 0], [6, 1, 0], [8, 0, -1]].each do |_dd, dx, dy|
        nx = cx + dx; ny = cy + dy
        next if nx < 0 || ny < 0 || nx >= w || ny >= h
        next if visited[[nx, ny]]
        visited[[nx, ny]] = true
        q << [nx, ny]
      end
    end
    if found && (found[0] != x || found[1] != y)
      m['x'] = found[0]
      m['y'] = found[1]
      changes << "地图#{id} '#{name}' (#{x},#{y}) -> (#{found[0]},#{found[1]})"
    elsif !found
      puts "地图#{id} '#{name}': 未找到安全格(跳过)"
    end
  rescue => e
    puts "地图#{id} '#{name}': 读取失败 #{e.message}"
  end
end

puts "检查 #{checked} 个落点"
puts "== 修正 (#{changes.size}) =="
changes.each { |c| puts c }

File.write(JP, JSON.pretty_generate(d))
puts "已写回 jump_points.json"
