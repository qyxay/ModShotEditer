# dump CommonEvent 15 (二周目开场) 和 43/101
$LOAD_PATH.unshift 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/rmtools'
require 'rxdata_stub'
CE = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data/CommonEvents.rxdata'

def cmds(ce)
  v = ce.instance_variable_get(:@list)
  v.is_a?(Array) ? v : []
end

arr = Marshal.load(File.binread(CE))
[15, 43, 101].each do |idx|
  ce = arr[idx]
  next unless ce
  puts "===== CommonEvent##{idx} trigger=#{ce.instance_variable_get(:@trigger)} cmds=#{cmds(ce).size} ====="
  cmds(ce).each_with_index do |cmd, ci|
    c = cmd.code; p = cmd.parameters
    txt = case c
          when 101 then "头像 #{p[0]}"
          when 401 then "文本: #{p[0]}"
          when 111 then "条件: #{p[0] == 12 ? '脚本=' + p[1].to_s : (p[0] == 0 ? "开关#{p[1]} #{p[2] == 0 ? '=0' : '=1'}" : p.inspect)}"
          when 355, 655 then "脚本: #{p.join(' ')}"
          when 121 then "开关#{p[0]}-#{p[1]}=#{p[2]}"
          when 122 then "变量#{p[0]}-#{p[1]}=#{p[2..3].inspect}"
          when 117 then "公共事件 #{p[0]}"
          when 201 then "传送地图#{p[1]} (#{p[2]},#{p[3]})"
          when 0 then "END"
          else "c#{c} #{p.inspect}"
          end
    puts "  [#{ci}] #{txt}"
  end
end
