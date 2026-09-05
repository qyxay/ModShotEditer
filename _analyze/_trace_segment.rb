# -*- coding: utf-8 -*-
ls = File.readlines('OneShot/mods/mod/logs/skip_trace.log')
ls.each_with_index do |l, i|
  puts "#{i + 1}: #{l}" if l =~ /20:1[7-9]:/
end
