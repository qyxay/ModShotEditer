$LOAD_PATH.unshift 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/rmtools'
require 'rxdata_stub'
D = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data'
mi = Marshal.load(File.binread(D + '/MapInfos.rxdata'))
[2, 12, 13, 14, 11, 258, 262, 255].each do |id|
  info = mi[id]
  puts "Map#{id}: name='#{info.instance_variable_get(:@name)}' parent=#{info.instance_variable_get(:@parent_id)}" if info
end
m = Marshal.load(File.binread(D + '/Map012.rxdata'))
puts "\nMap12 tileset=#{m.tileset_id} events=#{m.events.size} width=#{m.width} height=#{m.height}"
