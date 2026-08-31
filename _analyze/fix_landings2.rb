# ============================================================
#  用正确通行性扫描+修正 jump_points.json 落点
#  安全格: 可站立 + 同格无阻挡事件; 不安全 -> BFS 最近安全格
# ============================================================

require_relative 'oneshot_data'

JP = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/mods/mod/jump_points.json'

passages = os_load_tilesets
d = JSON.parse(File.read(JP))
File.write(JP.sub('.json', '.backup2.json'), JSON.pretty_generate(d))

FILTER = /IGNORE|DEBUG|INTERNAL|UNUSED|\bTEST\b|^INIT\b|TELEPORT|DEMO|PROTOWALK|PSHOT/i
NAME_PAT = /^[TCS]\d+$/i

unsafe = []
changes = []
total = 0
d.each do |id, m|
  next unless m.is_a?(Hash)
  x = m['x'].to_i; y = m['y'].to_i
  name = m['name'].to_s
  next if name =~ FILTER || name =~ NAME_PAT
  next if x < 0 || y < 0
  begin
    map = os_load_map(id.to_i)
    if os_safe_landing?(map, passages, x, y)
      total += 1
      next
    end
    unsafe << "地图#{id} '#{name}' 落点(#{x},#{y}) 不安全(原)"
    # BFS 找最近安全格
    w = map.instance_variable_get(:@width)
    h = map.instance_variable_get(:@height)
    q = [[x, y]]
    visited = { [x, y] => true }
    found = nil
    until q.empty? || found
      cx, cy = q.shift
      if os_safe_landing?(map, passages, cx, cy)
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
      changes << "地图#{id} '#{name}' 落点 (#{x},#{y}) -> (#{found[0]},#{found[1]})"
      total += 1
    elsif found
      total += 1
    else
      puts "地图#{id} '#{name}': 未找到安全格(跳过)"
    end
  rescue => e
    puts "地图#{id} '#{name}': 读取失败 #{e.message}"
  end
end

puts "安全落点(含修正后): #{total}"
puts "原始不安全落点: #{unsafe.size}"
puts ""
puts "== 修正的落点 (#{changes.size}) =="
changes.each { |c| puts c }

File.write(JP, JSON.pretty_generate(d))
puts ""
puts "已写回 jump_points.json"
