# 全量扫描: 谁把开关160(Beat Solstice)设为true + Solstice通关相关开关
# 覆盖: 所有地图 + 公共事件 (code121开关操作, code111/355/655脚本中的 $game_switches[X]= 赋值)
$LOAD_PATH.unshift 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/rmtools'
require 'rxdata_stub'

DATA = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data'
SCR  = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/xscripts'

def page_cmds(pg)
  l = pg.instance_variable_get(:@list)
  l.is_a?(Array) ? l : []
end

def cmds(arr, n)
  c = arr[n]; c ? arr[n] : []
end

def dump_sw_set(mapid, name, evname, evid, pgid, list)
  list.each_with_index do |cmd, ci|
    p = cmd.parameters
    case cmd.code
    when 121 # 开关操作
      s, e, v = p[0], p[1], p[2]
      (s..e).each do |sw|
        if (151..175).include?(sw)
          puts "SW #{sw}=#{v}  #{name} ev##{evid} '#{evname}' pg#{pgid} [#{ci}]"
        end
      end
    when 111, 355, 655 # 脚本
      code = cmd.code == 111 ? p[1].to_s : p.join(' ')
      if code =~ /\$game_switches\[(\d+)\]\s*=\s*(true|false|1|0)/
        sw = $1.to_i; v = $2
        if (151..175).include?(sw)
          puts "SW #{sw}=#{v}(script)  #{name} ev##{evid} '#{evname}' pg#{pgid} [#{ci}] #{code[0,60]}"
        end
      end
    end
  end
end

# 地图
Dir.glob("#{DATA}/Map[0-9]*.rxdata").sort.each do |f|
  m = File.basename(f) =~ /Map(\d+)\.rxdata/ ? $1.to_i : 0
  map = Marshal.load(File.binread(f))
  map.events.each do |evid, ev|
    ev.pages.each_with_index do |pg, pgid|
      dump_sw_set(m, "Map#{m}", ev.name, evid, pgid, page_cmds(pg))
    end
  end
end

# 公共事件
cearr = Marshal.load(File.binread("#{DATA}/CommonEvents.rxdata"))
cearr.compact.each_with_index do |ce, idx|
  next unless ce
  dump_sw_set(0, "CE#{idx}", ce.instance_variable_get(:@name) || 'ce', idx, 0, page_cmds(ce))
end

# 脚本里的 $game_switches[160]= 赋值(排除事件内已扫的)
puts '--- 脚本层 160/152 相关赋值 ---'
Dir.glob("#{SCR}/*.rb").sort.each do |f|
  File.readlines(f).each_with_index do |ln, i|
    if ln =~ /\$game_switches\[(160|152|154|153|155|156|157)\]\s*=\s*(\w+)/
      puts "#{File.basename(f)}:#{i+1}: #{$1}=#{$2}  #{ln.strip[0,70]}"
    end
  end
end
puts '--- 脚本层含 "Solstice"/"solstice" ---'
Dir.glob("#{SCR}/*.rb").sort.each do |f|
  File.readlines(f).each_with_index do |ln, i|
    if ln =~ /[Ss]olstice/
      puts "#{File.basename(f)}:#{i+1}: #{ln.strip[0,90]}"
    end
  end
end
