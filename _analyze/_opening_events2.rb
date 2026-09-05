# -*- coding: utf-8 -*-
require File.expand_path('oneshot_data', __dir__)

# 1) map1 init [52] 条件 (调用 CE15 的条件)
map = os_load_map(1)
ev = map.instance_variable_get(:@events)[1]
pg = ev.instance_variable_get(:@pages)[0]
list = pg.instance_variable_get(:@list)
puts "=== map1 ev1 init [49]-[56] ==="
(49..56).each do |i|
  c = list[i]
  next unless c
  puts "  [#{i}] c#{c.code} #{c.parameters.inspect}"
end

# 2) intro 事件完整 (含 241/250/245 声音)
[2, 188].each do |mid|
  map = os_load_map(mid)
  ev = map.instance_variable_get(:@events)[7]
  pg = ev.instance_variable_get(:@pages)[0]
  lst = pg.instance_variable_get(:@list)
  puts "\n=== map#{mid} ev7 intro 声音/移动/结束 (共#{lst.size}条) ==="
  lst.each_with_index do |c, i|
    next unless c
    pm = c.parameters.inspect
    pm = pm[0, 70] + '...' if pm.size > 70
    puts "  [#{i}] c#{c.code} #{pm}" if [241, 245, 250, 208, 209, 213, 203, 413, 412, 111, 121, 201, 106].include?(c.code)
  end
end

# 3) 地图默认 BGM
[1, 2, 188, 258, 63].each do |mid|
  map = os_load_map(mid)
  bgm = map.instance_variable_get(:@bgm)
  puts "map#{mid} @bgm=#{bgm ? bgm.instance_variable_get(:@name) : 'nil'}"
end

# 4) map1 init [67] 241 曲名 + 全部 241
puts "\n=== map1 ev1 init 全部 241 ==="
list.each_with_index do |c, i|
  next unless c
  if c.code == 241
    b = c.parameters[0]
    name = b ? (b.instance_variable_get(:@name) rescue '?') : 'nil'
    puts "  [#{i}] c241 name=#{name}"
  end
end
