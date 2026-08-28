# 读 System.rxdata 的 start_map_id + dump Map001/Map002 INIT 事件
$LOAD_PATH.unshift 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/rmtools'
require 'rxdata_stub'
DATA_DIR = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data'

sys = Marshal.load(File.binread("#{DATA_DIR}/System.rxdata"))
puts "start_map_id=#{sys.start_map_id} start_x=#{sys.start_x} start_y=#{sys.start_y}"
puts "title_name=#{sys.title_name}"

def dump_all_events(file, label)
  m = Marshal.load(File.binread("#{DATA_DIR}/#{file}"))
  puts "===== #{label} (#{file}) events=#{m.events.size} ====="
  m.events.each do |eid, ev|
    next if ev.pages.empty?
    puts "--- ev##{eid} '#{ev.name}' name='#{ev.name}' pages=#{ev.pages.size}"
    ev.pages.each_with_index do |pg, pi|
      list = pg.instance_variable_get(:@list)
      cond = pg.instance_variable_get(:@condition)
      sw = cond.respond_to?(:switch1_id) ? "sw1=#{cond.switch1_id}#{cond.switch1_valid ? '(valid)' : ''} sw2=#{cond.switch2_id}#{cond.switch2_valid ? '(valid)' : ''} var=#{cond.variable_id}#{cond.variable_valid ? '(valid)' : ''}=#{cond.variable_value} selfsw=#{cond.self_switch_valid ? cond.self_switch_ch : '-'}" : '?'
      puts "  page#{pi} cond[#{sw}] cmds=#{list.size}"
      list.each_with_index do |cmd, ci|
        c = cmd.code; p = cmd.parameters
        txt = case c
              when 101 then "头像 #{p[0]}"
              when 401 then "文本: #{p[0]}"
              when 111 then "条件: #{p[0] == 12 ? '脚本=' + p[1].to_s : (p[0]==0 ? "开关#{p[1]} #{p[2]==0 ? '=0' : '=1'}" : p.inspect)}"
              when 355, 655 then "脚本: #{p.join(' ')}"
              when 121 then "开关#{p[0]}-#{p[1]}=#{p[2]}"
              when 122 then "变量#{p[0]}-#{p[1]}=#{p[2..3].inspect}"
              when 117 then "公共事件 #{p[0]}"
              when 201 then "传送地图#{p[1]} (#{p[2]},#{p[3]})"
              when 0 then "END"
              else "c#{c} #{p.inspect}"
              end
        puts "    [#{ci}] #{txt}"
      end
    end
  end
end

dump_all_events('Map001.rxdata', 'INIT Map001')
