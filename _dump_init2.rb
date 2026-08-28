# 完整 dump Map001 INIT ev1 pg0 (带缩进结构) + Map255 全部事件
$LOAD_PATH.unshift 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/rmtools'
require 'rxdata_stub'
DATA = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data'

def decode(cmd)
  p = cmd.parameters
  case cmd.code
  when 101 then "头像 #{p[0]}"
  when 401 then "  文本: #{p[0]}"
  when 111 then
    if p[0] == 12 then "if 脚本: #{p[1]}"
    elsif p[0] == 0 then "if 开关#{p[1]} #{p[2]==0 ? '=0' : '=1'}"
    else "if #{p.inspect}"
    end
  when 411 then 'else'
  when 412 then 'end'
  when 355, 655 then "脚本: #{p.join(' ')}"
  when 121 then "开关#{p[0]}-#{p[1]}=#{p[2]}"
  when 122 then "变量#{p[0]}-#{p[1]}=#{p[2..3].inspect}"
  when 117 then "公共事件#{p[0]}"
  when 201 then "传送地图#{p[1]} (#{p[2]},#{p[3]})"
  when 106 then "等待#{p[0]}"
  when 231 then "画面#{p[0]} #{p[1]}"
  when 232 then "淡入#{p[0]} #{p[1]}"
  when 235 then "消除#{p[0]}"
  when 209 then "移动#{p[0]}"
  when 509 then "移动命令 #{p[0].inspect}"
  when 241 then "BGM #{p[0].respond_to?(:name) ? p[0].name : p[0]}"
  when 115 then 'END'
  when 0 then 'END'
  else "c#{cmd.code} #{p.inspect}"
  end
end

map = Marshal.load(File.binread("#{DATA}/Map001.rxdata"))
ev = map.events[1]
puts "===== Map001 INIT ev1 pages=#{ev.pages.size} ====="
ev.pages.each_with_index do |pg, pgid|
  list = pg.instance_variable_get(:@list)
  puts "--- pg#{pgid} cmds=#{list.size} ---"
  list.each_with_index do |cmd, ci|
    puts "  [#{ci}] #{'  '*cmd.indent}#{decode(cmd)}"
  end
end

# Map255 Last room
puts "\n===== Map255 Last room ====="
map2 = Marshal.load(File.binread("#{DATA}/Map255.rxdata"))
map2.events.each do |evid, ev2|
  ev2.pages.each_with_index do |pg, pgid|
    list = pg.instance_variable_get(:@list)
    cond = pg.instance_variable_get(:@condition)
    sw = "sw1=#{cond.instance_variable_get(:@switch1_id)}#{cond.instance_variable_get(:@switch1_valid) ? '(v)' : ''}"
    puts "--- ev#{evid} '#{ev2.name}' pg#{pgid} #{sw} cmds=#{list.size} ---"
    list.each_with_index do |cmd, ci|
      txt = decode(cmd)
      puts "  [#{ci}] #{'  '*cmd.indent}#{txt}" if [101,401,111,355,655,121,122,117,201,115,0,411,412].include?(cmd.code)
    end
  end
end
