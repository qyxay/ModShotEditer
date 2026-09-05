# -*- coding: utf-8 -*-
require File.expand_path('oneshot_data', __dir__)

module RPG
  class CommonEvent; end
end
ces = Marshal.load(File.binread("#{DATA}/CommonEvents.rxdata"))
ce = ces[42]
list = ce.instance_variable_get(:@list)
puts "CE42 list size = #{list.size}"
puts "=== CE42 [700]-[735] ==="
(700..735).each do |i|
  c = list[i]
  next unless c
  pm = c.parameters.inspect
  pm = pm[0, 80] + '...' if pm.size > 80
  puts "  [#{i}] c#{c.code} #{pm}"
end
