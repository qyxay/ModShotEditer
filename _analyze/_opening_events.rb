# -*- coding: utf-8 -*-
require File.expand_path('oneshot_data', __dir__)
module RPG
  class CommonEvent; end
end

# 1) CE42 完整(重点: 结尾设置)
ces = Marshal.load(File.binread("#{DATA}/CommonEvents.rxdata"))
ce = ces[42]
puts "=== CE42 Load Save (#{ce.instance_variable_get(:@list).size} cmds) ==="
list = ce.instance_variable_get(:@list)
list.each_with_index do |c, i|
  next unless c
  pm = c.parameters.inspect
  pm = pm[0, 60] + '...' if pm.size > 60
  tag = ''
  tag = ' <== SW198/190/306/121' if [111, 121, 122, 412].include?(c.code)
  puts "  [#{i}] c#{c.code} #{pm}#{tag}" if [111, 121, 122, 201, 117, 101, 412, 113, 413].include?(c.code)
end

# 1b) CE42 结尾 (700-835)
puts "=== CE42 结尾 (700-834) ==="
(700..834).each do |i|
  c = list[i]
  next unless c
  pm = c.parameters.inspect
  pm = pm[0, 60] + '...' if pm.size > 60
  puts "  [#{i}] c#{c.code} #{pm}" if [111, 121, 122, 201, 117, 101, 250, 241, 412, 413].include?(c.code)
end
[2, 188].each do |mid|
  map = os_load_map(mid)
  ev = map.instance_variable_get(:@events)[7]
  pg = ev.instance_variable_get(:@pages)[0]
  list = pg.instance_variable_get(:@list)
  puts "\n=== map#{mid} ev7 intro (#{list.size} cmds) ==="
  list.each_with_index do |c, i|
    next unless c
    pm = c.parameters.inspect
    pm = pm[0, 60] + '...' if pm.size > 60
    puts "  [#{i}] c#{c.code} #{pm}" if [101, 102, 105, 106, 111, 121, 201, 202, 203, 205, 208, 209, 213, 231, 232, 235, 241, 245, 250, 301, 355, 412, 413].include?(c.code)
  end
end

# 3) map1 init [52] 条件 + [54] 调用
map = os_load_map(1)
ev = map.instance_variable_get(:@events)[1]
pg = ev.instance_variable_get(:@pages)[0]
list = pg.instance_variable_get(:@list)
puts "\n=== map1 ev1 init [49]-[56] ==="
(49..56).each do |i|
  c = list[i]
  next unless c
  puts "  [#{i}] c#{c.code} #{c.parameters.inspect}"
end
