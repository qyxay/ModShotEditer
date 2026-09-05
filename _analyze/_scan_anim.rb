# -*- coding: utf-8 -*-
require File.expand_path('oneshot_data', __dir__)

# 扫描所有地图事件的 207(动画)/221/222/223/224/225/355 命令, 找非 231 的 CG 机制
codes = [207, 221, 222, 223, 224, 225, 355, 117]
hits = {}
(1..400).each do |mid|
  begin
    map = os_load_map(mid)
  rescue StandardError
    next
  end
  evs = map.instance_variable_get(:@events) rescue {}
  evs.each do |id, ev|
    pages = ev.instance_variable_get(:@pages) rescue []
    pages.each_with_index do |pg, pi|
      list = pg.instance_variable_get(:@list) rescue []
      list.each_with_index do |c, i|
        next if c.nil? || c.code == 0
        if codes.include?(c.code)
          key = "c#{c.code}"
          hits[key] ||= []
          pm = c.parameters.inspect rescue ''
          hits[key] << "map#{mid} ev#{id} p#{pi} [#{i}] c#{c.code} #{pm[0, 70]}"
        end
      end
    end
  end
end

hits.each do |code, arr|
  puts "=== #{code} (#{arr.size}) ==="
  arr.first(15).each { |x| puts "  #{x}" }
  puts "  ..." if arr.size > 15
end
