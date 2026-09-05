ROOT = File.expand_path('..', __dir__)
$LOAD_PATH.unshift("#{ROOT}/runtime/lib/ruby/3.1.0")
require 'json'
d = JSON.parse(File.read("#{ROOT}/OneShot/mods/mod/jump_points.json"))
d.select { |k, v| v['name'].to_s =~ /living/i }.each do |k, v|
  puts "map=#{k} x=#{v['x']} y=#{v['y']} dir=#{v['dir']} name=#{v['name']}"
end
puts "--- total #{d.size} maps ---"
