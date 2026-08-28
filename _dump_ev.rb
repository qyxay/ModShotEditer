# dump 地图事件的命令结构，验证解析
$LOAD_PATH.unshift 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/rmtools'
require 'rxdata_stub'

path = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data/Map001.rxdata'
m = Marshal.load(File.binread(path))
puts "地图 #{m.width}x#{m.height} 事件数=#{m.events.size}"
m.events.each do |eid, ev|
  puts "== 事件##{eid} '#{ev.name}' @(#{ev.x},#{ev.y}) pages=#{ev.pages.size}"
  ev.pages.each_with_index do |pg, pi|
    next unless pg.respond_to?(:list)
    puts "  -- page#{pi} 命令数=#{pg.list.size}"
    pg.list.first(12).each_with_index do |cmd, ci|
      puts "    [#{ci}] code=#{cmd.code} indent=#{cmd.indent} params=#{cmd.parameters.inspect}"
    end
  end
  break if eid >= 2
end
