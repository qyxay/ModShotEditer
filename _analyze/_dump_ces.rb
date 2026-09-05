# -*- coding: utf-8 -*-
require File.expand_path('oneshot_data', __dir__)

# CommonEvents.rxdata 需要 RPG::CommonEvent 定义
module RPG
  class CommonEvent; end
end

ces = Marshal.load(File.binread("#{DATA}/CommonEvents.rxdata"))
[15, 42, 9, 2, 40, 1].each do |id|
  ce = ces[id]
  next unless ce
  name = ce.instance_variable_get(:@name)
  sw = ce.instance_variable_get(:@switch_id)
  list = ce.instance_variable_get(:@list)
  puts "=== CE##{id} name=#{name} switch=#{sw} list_size=#{list.size} ==="
  list.each_with_index do |c, i|
    next if c.code == 0
    pms = c.parameters.inspect
    pms = pms[0, 90] + '...' if pms.size > 90
    puts "  [#{i}] c#{c.code} #{pms}"
  end
  puts
end
