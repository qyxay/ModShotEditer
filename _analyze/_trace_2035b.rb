# -*- coding: utf-8 -*-
ls = File.readlines('OneShot/mods/mod/logs/skip_trace.log')
(10675..ls.size).each do |i|
  l = ls[i - 1]
  break unless l
  puts "#{i}: #{l}" if l =~ /20:35:/
end
