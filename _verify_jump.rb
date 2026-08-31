# 验证 jump_map.rb 的 load_maps 过滤逻辑
require 'json'
data = JSON.parse(File.read('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/mods/mod/jump_points.json'))
FILTER = /IGNORE|DEBUG|INTERNAL|UNUSED|\bTEST\b|^INIT$/i
maps = []
filtered = []
data.each do |id, m|
  x = m['x'].to_i; y = m['y'].to_i
  if x < 0 || y < 0
    filtered << [id, m['name'], 'no-spot']; next
  end
  name = m['name'].to_s
  if name =~ FILTER
    filtered << [id, name, 'filtered']; next
  end
  maps << { id: id.to_i, name: name, x: x, y: y }
end
maps.sort_by! { |m| m[:id] }
puts "total in json=#{data.size}, jumpable=#{maps.size}, excluded=#{filtered.size}"
puts '--- excluded ---'
filtered.each { |f| puts format('  %-4s %-24s %s', f[0], f[1], f[2]) }
puts '--- first 20 jumpable ---'
maps.first(20).each { |m| puts format('  %3d %-24s (%d,%d)', m[:id], m[:name], m[:x], m[:y]) }
puts '--- last 5 jumpable ---'
maps.last(5).each { |m| puts format('  %3d %-24s (%d,%d)', m[:id], m[:name], m[:x], m[:y]) }
