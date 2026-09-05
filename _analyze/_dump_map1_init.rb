# -*- coding: utf-8 -*-
# 重新 dump map1 init 事件完整命令, 检查非 231 的 CG 路径 (355 等)
require File.expand_path('oneshot_data', __dir__)

map = os_load_map(1)
puts "=== map1 事件总数: #{map.instance_variable_get(:@events).size} ==="
map.instance_variable_get(:@events).each do |id, ev|
  name = ev.instance_variable_get(:@name)
  puts "--- map1 event ##{id} name=#{name} ---"
  pages = ev.instance_variable_get(:@pages)
  pages.each_with_index do |pg, pi|
    trg = pg.instance_variable_get(:@trigger)
    puts "  page #{pi}: trigger=#{trg}"
    next unless trg == 3
    list = pg.instance_variable_get(:@list)
    puts "  --- autorun 命令 (#{list.size}) ---"
    list.each_with_index do |c, i|
      next if c.code == 0
      puts "  [#{i}] c#{c.code} #{c.parameters.inspect}"
    end
  end
end
