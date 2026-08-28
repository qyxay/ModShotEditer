# 全量收集: 游戏给 $game_switches[x] 赋值的所有地方
# 1) 脚本层: *.rb 里所有 $game_switches[...] = ... (含 $game_switches[x] = 值 / set 方法)
# 2) 事件层: Map*.rxdata + CommonEvents 里 code121(开关操作) + code355/655(脚本内赋值)
$LOAD_PATH.unshift 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/rmtools'
require 'rxdata_stub'
DATA = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data'
SCR  = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/xscripts'

puts '############ A. 脚本层直接赋值 (xscripts/*.rb) ############'
Dir.glob("#{SCR}/*.rb").sort.each do |f|
  File.readlines(f).each_with_index do |ln, i|
    # $game_switches[123] = ...
    if ln =~ /^\s*\$game_switches\[(\d+)\]\s*=\s*(.+?)(\s*#.*)?$/
      puts "#{File.basename(f)}:#{i+1}: $game_switches[#{$1}] = #{$2.strip}"
    end
  end
end

puts "\n############ B. Game_Switches 类的赋值入口 ############"
Dir.glob("#{SCR}/*.rb").sort.each do |f|
  File.readlines(f).each_with_index do |ln, i|
    if ln =~ /class Game_Switches|def \[\]|def \[\]=|def set|@data\[|def setup|def load|def save/
      puts "#{File.basename(f)}:#{i+1}: #{ln.strip[0,70]}"
    end
  end
end

def page_cmds(pg)
  l = pg.instance_variable_get(:@list); l.is_a?(Array) ? l : []
end

puts "\n############ C. 事件层 code121 开关操作 (按开关编号汇总) ############"
h = Hash.new { |k, v| k[v] = [] }
Dir.glob("#{DATA}/Map[0-9]*.rxdata").sort.each do |f|
  m = File.basename(f) =~ /Map(\d+)\.rxdata/ ? $1.to_i : 0
  map = Marshal.load(File.binread(f))
  map.events.each do |evid, ev|
    ev.pages.each_with_index do |pg, pgid|
      page_cmds(pg).each_with_index do |cmd, ci|
        p = cmd.parameters
        if cmd.code == 121
          (p[0]..p[1]).each { |sw| h[sw] << "Map#{m} ev#{evid} '#{ev.name}' pg#{pgid}[#{ci}]=#{p[2]}" }
        end
      end
    end
  end
end
cearr = Marshal.load(File.binread("#{DATA}/CommonEvents.rxdata"))
cearr.compact.each_with_index do |ce, idx|
  page_cmds(ce).each_with_index do |cmd, ci|
    p = cmd.parameters
    if cmd.code == 121
      (p[0]..p[1]).each { |sw| h[sw] << "CE#{idx} '#{ce.instance_variable_get(:@name)}'[#{ci}]=#{p[2]}" }
    end
  end
end
h.keys.sort.each do |sw|
  puts "开关#{sw}: #{h[sw].size} 处"
end

puts "\n############ D. 事件层脚本调用中的赋值 (code355/655, 仅非perma段) ############"
Dir.glob("#{DATA}/Map[0-9]*.rxdata").sort.each do |f|
  m = File.basename(f) =~ /Map(\d+)\.rxdata/ ? $1.to_i : 0
  map = Marshal.load(File.binread(f))
  map.events.each do |evid, ev|
    ev.pages.each_with_index do |pg, pgid|
      page_cmds(pg).each_with_index do |cmd, ci|
        p = cmd.parameters
        if [355, 655].include?(cmd.code) && p.join(' ') =~ /\$game_switches\[(\d+)\]\s*=\s*(\w+)/
          puts "Map#{m} ev#{evid} '#{ev.name}' pg#{pgid}[#{ci}]: #{$1}=#{$2}  #{p.join(' ')[0,60]}"
        end
      end
    end
  end
end
