# -*- coding: utf-8 -*-
s = File.read('OneShot/mods/mod/logs/skip_trace.log')
puts "size=#{s.bytesize}"
puts "--- instruction/cg/felix 相关 ---"
s.lines.each_with_index do |l, i|
  puts "#{i + 1}: #{l}" if l =~ /instruction|cg_wake|felix|black|white/i
end
puts "--- 尾部 20 行 ---"
puts s.lines.last(20).join
