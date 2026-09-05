ROOT = File.expand_path('..', __dir__)
require_relative 'oneshot_data'
JP = "#{ROOT}/OneShot/mods/mod/jump_points.json"
passages = os_load_tilesets
d = JSON.parse(File.read(JP))
def any_event?(map, x, y)
  map.instance_variable_get(:@events).each_value.any? { |ev| ev.instance_variable_get(:@x) == x && ev.instance_variable_get(:@y) == y }
end
def safe?(map, passages, x, y)
  return false unless os_standable?(map, passages, x, y)
  return false if any_event?(map, x, y)
  true
end
FILTER = /IGNORE|DEBUG|INTERNAL|UNUSED|\bTEST\b|^INIT\b|TELEPORT|DEMO|PROTOWALK|PSHOT/i
NAME_PAT = /^[TCS]\d+$/i
bad = []; ok = 0; skip = 0
d.each do |id, m|
  next unless m.is_a?(Hash)
  x = m['x'].to_i; y = m['y'].to_i; name = m['name'].to_s
  if name =~ FILTER || name =~ NAME_PAT || x < 0 || y < 0
    skip += 1; next
  end
  begin
    map = os_load_map(id.to_i)
    if safe?(map, passages, x, y)
      ok += 1
    else
      bad << "地图#{id} '#{name}' (#{x},#{y})"
    end
  rescue => e
    bad << "地图#{id} '#{name}' 读取失败"
  end
end
puts "安全: #{ok}  跳过: #{skip}  不安全: #{bad.size}"
bad.each { |b| puts "  #{b}" }
