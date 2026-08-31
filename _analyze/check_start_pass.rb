# ============================================================
#  用正确解析: start(15,17) 四向通行性 + tile 386 bits
# ============================================================

require_relative 'oneshot_data'

passages = os_load_tilesets
map = os_load_map(2)
data = map.instance_variable_get(:@data)
pass = passages[map.instance_variable_get(:@tileset_id)]

# tile 386 及相关 tile 的 bits
[386, 385, 394, 82, 409, 144].each do |tile|
  bits = pass ? pass[tile] : nil
  puts "tile #{tile}: bits=#{bits ? format('0x%02X', bits) : 'nil'}"
end

puts ""
puts "== start 落点 (15,17) 及周围 四向通行性(正确解析) =="
(16..18).each do |y|
  (14..16).each do |x|
    d_ok = {}
    [2, 4, 6, 8].each { |dd| d_ok[dd] = os_dir_passable(map, passages, x, y, dd) }
    stand = os_standable?(map, passages, x, y)
    puts "(#{x},#{y}) 下=#{d_ok[2] ? 'Y' : 'N'} 左=#{d_ok[4] ? 'Y' : 'N'} 右=#{d_ok[6] ? 'Y' : 'N'} 上=#{d_ok[8] ? 'Y' : 'N'} 可站=#{stand ? 'Y' : 'N'} tiles=[#{data[x,y,0]},#{data[x,y,1]},#{data[x,y,2]}]"
  end
end
