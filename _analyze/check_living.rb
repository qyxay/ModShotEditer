$LOAD_PATH.unshift('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/runtime/lib/ruby/3.1.0')
require 'json'
d = JSON.parse(File.read('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/mods/mod/jump_points.json'))
d.select { |k, v| v['name'].to_s =~ /living/i }.each do |k, v|
  puts "map=#{k} x=#{v['x']} y=#{v['y']} dir=#{v['dir']} name=#{v['name']}"
end
puts "--- total #{d.size} maps ---"
