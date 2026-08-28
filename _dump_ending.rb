# dump Map60 ev12 pg2 完整结局流程 + 全脚本 160 引用
$LOAD_PATH.unshift 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/rmtools'
require 'rxdata_stub'
DATA = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data'
SCR  = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/xscripts'

# --- Map60 ev12 pg2 ---
map = Marshal.load(File.binread("#{DATA}/Map060.rxdata"))
ev = map.events[12]
pg = ev.pages[2]
list = pg.instance_variable_get(:@list)
puts "===== Map060 ev#12 pg2 cmds=#{list.size} ====="
list.each_with_index do |cmd, ci|
  p = cmd.parameters
  txt = case cmd.code
        when 101 then "头像#{p[0]}"
        when 401 then "文: #{p[0]}"
        when 111 then p[0] == 12 ? "if脚本: #{p[1]}" : (p[0] == 0 ? "if开关#{p[1]}#{p[2]==0 ? '=0' : '=1'}" : "if#{p.inspect}")
        when 411 then 'else'
        when 412 then 'endif'
        when 355, 655 then "脚本: #{p.join(' ')}"
        when 121 then "开关#{p[0]}-#{p[1]}=#{p[2]}"
        when 122 then "变量#{p[0]}-#{p[1]}=#{p[2..3].inspect}"
        when 117 then "公共事件#{p[0]}"
        when 108, 408 then ";#{p[0]}"
        when 0 then 'END'
        else "c#{cmd.code} #{p.inspect}"
        end
  puts "[#{ci}] #{txt}"
end

# --- 全脚本 grep 160/Beat Solstice ---
puts "\n===== 脚本中 160 引用 ====="
Dir.glob("#{SCR}/*.rb").sort.each do |f|
  File.readlines(f).each_with_index do |ln, i|
    if ln =~ /160/ && ln =~ /\$game_switches|switches\[|Beat|perma|fake/
      puts "#{File.basename(f)}:#{i+1}: #{ln.strip[0,90]}"
    end
  end
end

puts "\n===== 脚本中 perma_flags / Beat ====="
Dir.glob("#{SCR}/*.rb").sort.each do |f|
  File.readlines(f).each_with_index do |ln, i|
    if ln =~ /Beat|perma_flags|perma_vars|BEGAN|END PERMA/
      puts "#{File.basename(f)}:#{i+1}: #{ln.strip[0,90]}"
    end
  end
end
