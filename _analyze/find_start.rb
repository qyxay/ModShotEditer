ROOT = File.expand_path('..', __dir__)
$LOAD_PATH.unshift("#{ROOT}/runtime/lib/ruby/3.1.0")
require 'json'
d = JSON.parse(File.read("#{ROOT}/OneShot/mods/mod/jump_points.json"))
# 找 start 相关
d.select { |k, v| v['name'].to_s =~ /^start$/i }.each do |k, v|
  puts "map=#{k} x=#{v['x']} y=#{v['y']} dir=#{v['dir']} name=#{v['name']}"
end
puts '--- 名字含 start 的 ---'
d.select { |k, v| v['name'].to_s =~ /start/i }.each do |k, v|
  puts "map=#{k} x=#{v['x']} y=#{v['y']} dir=#{v['dir']} name=#{v['name']}"
end
puts '--- 前 15 个可跳地图(按ID) ---'
d.sort_by { |k, _| k.to_i }.first(15).each do |k, v|
  puts "map=#{k} x=#{v['x']} y=#{v['y']} dir=#{v['dir']} name=#{v['name']}"
end
