ROOT = File.expand_path('..', __dir__)
require 'json'
d = JSON.parse(File.read("#{ROOT}/OneShot/mods/mod/jump_points.json"))
['2', '4', '64', '120', '182', '22', '113'].each do |k|
  puts "地图#{k}: #{d[k].inspect}"
end
