# dump Map060 ev#12 和 Map061 ev#3 完整命令
$LOAD_PATH.unshift 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/rmtools'
require 'rxdata_stub'

DATA_DIR = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data'

def dump_event(file, eid, label)
  m = Marshal.load(File.binread("#{DATA_DIR}/#{file}"))
  ev = m.events[eid]
  puts "===== #{label} (#{file} ev##{eid} '#{ev.name}') ====="
  ev.pages.each_with_index do |pg, pi|
    list = pg.instance_variable_get(:@list)
    cond = pg.instance_variable_get(:@condition)
    puts "--- page#{pi} cond=#{cond.inspect} cmds=#{list.size}"
    list.each_with_index do |cmd, ci|
      c = cmd.code; p = cmd.parameters
      txt = case c
            when 101 then "显示头像: #{p[0]}"
            when 401 then "文本: #{p[0]}"
            when 111 then "条件: #{p[0] == 12 ? '脚本=' + p[1].to_s : p.inspect}"
            when 355, 655 then "脚本: #{p.join(' ')}"
            when 121 then "开关#{p[0]}-#{p[1]} = #{p[2]}"
            when 122 then "变量#{p[0]}-#{p[1]} 操作"
            when 117 then "调用公共事件 #{p[0]}"
            when 0 then "结束"
            else "code=#{c} #{p.inspect}"
            end
      puts "  [#{ci}] #{txt}"
    end
  end
end

dump_event('Map060.rxdata', 12, 'Summit')
