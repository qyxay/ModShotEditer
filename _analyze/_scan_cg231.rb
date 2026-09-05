# -*- coding: utf-8 -*-
require File.expand_path('oneshot_data', __dir__)

# 1) 所有地图事件中 231 显示 cg_wake* 的命令
puts "=== 231 显示 cg_wake 的事件 ==="
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
        next unless c && c.code == 231
        name = (c.parameters[1].to_s rescue '')
        puts "map#{mid} ev#{id} p#{pi} [#{i}] 231 #{name}" if name =~ /cg_wake|cg_tower|felix|instruction|black|white/i
      end
    end
  end
end

# 2) 所有公共事件中 231 显示 cg_wake*
puts "\n=== 公共事件 231 显示 cg_wake* ==="
module RPG
  class CommonEvent; end
end
ces = Marshal.load(File.binread("#{DATA}/CommonEvents.rxdata"))
ces.each_with_index do |ce, cid|
  next unless ce
  list = ce.instance_variable_get(:@list) rescue []
  list.each_with_index do |c, i|
    next unless c && c.code == 231
    name = (c.parameters[1].to_s rescue '')
    if name =~ /cg_wake|cg_tower|felix|instruction|black|white/i
      puts "CE#{cid} [#{i}] 231 #{name}"
    end
  end
end
