# -*- coding: utf-8 -*-
require File.expand_path('oneshot_data', __dir__)

module RPG
  class CommonEvent; end
end
ces = Marshal.load(File.binread("#{DATA}/CommonEvents.rxdata"))
ce = ces[42]
list = ce.instance_variable_get(:@list)
(0..92).each do |i|
  c = list[i]
  next unless c
  pm = c.parameters.inspect
  pm = pm[0, 90] + '...' if pm.size > 90
  puts "  [#{i}] #{'  ' * (c.indent || 0)}c#{c.code} #{pm}"
end
