# 探测 OneShot 地图数据结构
$LOAD_PATH.unshift File.expand_path(File.dirname(__FILE__))
require "rxdata_stub"

d = "C:/Program Files (x86)/Steam/steamapps/common/OneShot/Data"

mi = Marshal.load(File.binread("#{d}/MapInfos.rxdata"))
puts "=== MapInfos ==="
puts "类型: #{mi.class}"
puts "键数: #{mi.size}"
mi.keys.sort_by { |k| k.to_i }.first(8).each do |k|
  info = mi[k]
  puts "  Map#{k}: name=#{info.name.inspect} parent=#{info.parent_id}"
end

m = Marshal.load(File.binread("#{d}/Map001.rxdata"))
puts "\n=== Map001 ==="
puts "类型: #{m.class}"
m.instance_variables.each do |iv|
  v = m.instance_variable_get(iv)
  disp = v.class.to_s
  disp = "Table(#{v.xsize}x#{v.ysize}x#{v.zsize})" if v.is_a?(RPG::Table)
  disp = "Array[#{v.size}]" if v.is_a?(Array)
  puts "  #{iv} = #{disp}"
end
puts "宽x高: #{m.width}x#{m.height}  tileset_id: #{m.tileset_id}"
puts "事件数: #{m.events.size}"
ev = m.events.first
if ev
  puts "\n=== 第一个事件 (NPC 示例) ==="
  ev.instance_variables.each do |iv|
    v = ev.instance_variable_get(iv)
    disp = v.class.to_s
    disp = "Array[#{v.size}]" if v.is_a?(Array)
    puts "  #{iv} = #{disp}"
  end
  pg = ev.pages.first
  if pg
    puts "  pages[0] ivars:"
    pg.instance_variables.each do |iv|
      v = pg.instance_variable_get(iv)
      disp = v.class.to_s
      disp = "Array[#{v.size}]" if v.is_a?(Array)
      disp = "Graphic(x=#{v.x},y=#{v.y})" if v.is_a?(RPG::Event::Page::Graphic)
      puts "    #{iv} = #{disp}"
    end
  end
end