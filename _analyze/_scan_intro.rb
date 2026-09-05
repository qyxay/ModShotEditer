# -*- coding: utf-8 -*-
hits = {}
Dir.glob('xscripts/*.rb').each do |f|
  File.readlines(f).each_with_index do |l, i|
    if l =~ /intro|Intro/i
      (hits[f] ||= []) << [i + 1, l.strip]
    end
  end
end
hits.each do |f, arr|
  puts "=== #{File.basename(f)} (#{arr.size}) ==="
  arr.first(10).each { |x| puts "  #{x[0]}: #{x[1]}" }
end
