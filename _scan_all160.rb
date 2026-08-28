# 全量宽松搜索: 所有地图/公共事件所有命令参数中含 160 的 + 所有脚本含 160 的行
$LOAD_PATH.unshift 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/rmtools'
require 'rxdata_stub'
DATA = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data'
SCR  = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/xscripts'

def page_cmds(pg)
  l = pg.instance_variable_get(:@list); l.is_a?(Array) ? l : []
end

puts '===== 事件/公共事件命令中所有含 160 的 (参数含160) ====='
Dir.glob("#{DATA}/Map[0-9]*.rxdata").sort.each do |f|
  m = File.basename(f) =~ /Map(\d+)\.rxdata/ ? $1.to_i : 0
  map = Marshal.load(File.binread(f))
  map.events.each do |evid, ev|
    ev.pages.each_with_index do |pg, pgid|
      page_cmds(pg).each_with_index do |cmd, ci|
        p = cmd.parameters
        s = p.inspect
        if s =~ /160/
          puts "Map#{m} ev#{evid} '#{ev.name}' pg#{pgid} [#{ci}] c#{cmd.code} #{s[0,90]}"
        end
      end
    end
  end
end
cearr = Marshal.load(File.binread("#{DATA}/CommonEvents.rxdata"))
cearr.compact.each_with_index do |ce, idx|
  page_cmds(ce).each_with_index do |cmd, ci|
    s = cmd.parameters.inspect
    if s =~ /160/
      puts "CE#{idx} '#{ce.instance_variable_get(:@name)}' [#{ci}] c#{cmd.code} #{s[0,90]}"
    end
  end
end

puts "\n===== 脚本中所有含 160 的行 =====\n"
Dir.glob("#{SCR}/*.rb").sort.each do |f|
  File.readlines(f).each_with_index do |ln, i|
    if ln =~ /160/
      puts "#{File.basename(f)}:#{i+1}: #{ln.strip[0,100]}"
    end
  end
end
