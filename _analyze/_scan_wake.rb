# -*- coding: utf-8 -*-
hits = {}
Dir.glob('xscripts/*.rb').each do |f|
  File.readlines(f).each_with_index do |l, i|
    if l =~ /cg_wake|panorama/i
      (hits[f] ||= []) << [i + 1, l.strip]
    end
  end
end
hits.each do |f, arr|
  puts "=== #{File.basename(f)} (#{arr.size}) ==="
  arr.first(12).each { |x| puts "  #{x[0]}: #{x[1]}" }
end

# 地图远景: 扫描所有地图的 panorama_name
puts "\n=== 地图远景 panorama ==="
require File.expand_path('oneshot_data', __dir__)
(1..400).each do |mid|
  begin
    map = os_load_map(mid)
  rescue StandardError
    next
  end
  pano = map.instance_variable_get(:@panorama_name).to_s
  puts "map#{mid}: #{pano}" unless pano.empty?
end
