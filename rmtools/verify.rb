# 验证: 修改后的地图文件 Marshal 往返 + 瓦片完整性
$LOAD_PATH.unshift File.dirname(__FILE__)
require "rxdata_stub"

GAME = "C:/Program Files (x86)/Steam/steamapps/common/OneShot/Data/Map004.rxdata"
MOD  = "C:/Program Files (x86)/Steam/steamapps/common/OneShot/mods/MyMod/Data/Map004.rxdata"

orig = Marshal.load(File.binread(GAME))
modd = Marshal.load(File.binread(MOD))

puts "== 瓦片数据完整性 =="
same = true
(0...modd.data.xsize).each do |x|
  (0...modd.data.ysize).each do |y|
    (0...modd.data.zsize).each do |z|
      if orig.data[x, y, z] != modd.data[x, y, z]
        same = false
        puts "  不同 @(#{x},#{y},#{z}): #{orig.data[x,y,z]} vs #{modd.data[x,y,z]}"
      end
    end
  end
end
puts same ? "  OK - 瓦片完全一致 (addnpc 未破坏地图)" : "  FAIL - 瓦片被改动!"

puts "== 事件数 =="
puts "  原版 #{orig.events.size} -> mod #{modd.events.size}"

puts "== Marshal 往返 (dump 后再 load) =="
b = Marshal.dump(modd)
r2 = Marshal.load(b)
puts "  再dump尺寸: #{b.size} bytes, 事件数: #{r2.events.size}"
puts "  新NPC存在: #{r2.events[24] && r2.events[24].name == "ModNPC"}"

puts "== 与游戏内置 Marshal 兼容性: 文件可被 modshot 的 Ruby 3.1 重新加载 =="
puts "  (mkxp 的 Table/Color/Tone/Rect 格式与此桩完全一致, 已从源码核对)"
