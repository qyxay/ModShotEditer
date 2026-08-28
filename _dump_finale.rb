# dump Map242, Map259, Map255 ev3 完整 关键命令
$LOAD_PATH.unshift 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/rmtools'
require 'rxdata_stub'
DATA = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data'

def show(mapid, filter_ev = nil)
  map = Marshal.load(File.binread("#{DATA}/Map%03d.rxdata" % mapid))
  puts "===== Map#{mapid} '#{map.inspect[0,20]}' events=#{map.events.size} ====="
  map.events.each do |evid, ev|
    next if filter_ev && evid != filter_ev
    ev.pages.each_with_index do |pg, pgid|
      list = pg.instance_variable_get(:@list)
      puts "--- ev#{evid} '#{ev.name}' pg#{pgid} cmds=#{list.size} ---"
      list.each_with_index do |cmd, ci|
        p = cmd.parameters
        case cmd.code
        when 101 then puts "  [#{ci}] 头像 #{p[0]}"
        when 401 then puts "  [#{ci}]   文: #{p[0]}"
        when 111 then puts "  [#{ci}] if #{p[0]==12 ? '脚本:'+p[1].to_s : (p[0]==0 ? "开关#{p[1]}#{p[2]==0 ? '=0' : '=1'}" : p.inspect)}"
        when 411 then puts "  [#{ci}] else"
        when 412 then puts "  [#{ci}] end"
        when 355, 655 then puts "  [#{ci}] 脚本: #{p.join(' ')}"
        when 121 then puts "  [#{ci}] 开关#{p[0]}-#{p[1]}=#{p[2]}"
        when 117 then puts "  [#{ci}] 公共事件#{p[0]}"
        when 201 then puts "  [#{ci}] 传送地图#{p[1]} (#{p[2]},#{p[3]})"
        when 102 then puts "  [#{ci}] 选项: #{p[0].inspect}"
        when 104 then puts "  [#{ci}] 选项分支: #{p.inspect}"
        when 403 then puts "  [#{ci}] 选项else"
        when 106 then puts "  [#{ci}] 等待#{p[0]}"
        when 0, 115 then puts "  [#{ci}] END"
        end
      end
    end
  end
end

show(242)
show(259)
