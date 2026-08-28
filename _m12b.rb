$LOAD_PATH.unshift 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/rmtools'
require 'rxdata_stub'
D = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data'
mi = Marshal.load(File.binread(D + '/MapInfos.rxdata'))
puts "=== parent=7 家族 (Map12 的兄弟/祖先) ==="
mi.each do |id, info|
  next unless info
  n = info.instance_variable_get(:@name)
  p = info.instance_variable_get(:@parent_id)
  if [7, 12, 13, 14, 8, 9, 10, 11].include?(id) || p == 7 || p == 12
    puts "Map#{id}: '#{n}' parent=#{p}"
  end
end
# 打印 7 是什么
puts "\n=== Map7 ==="
puts mi[7].instance_variable_get(:@name) if mi[7]
