require_relative 'oneshot_data'

[4, 120].each do |mid|
  map = os_load_map(mid)
  evs = map.instance_variable_get(:@events)
  puts "===== 地图#{mid} 含 FAST TRAVEL / unlock_map / enable_travel / 传送相关事件 ====="
  evs.each_value do |ev|
    ev.pages.each_with_index do |pg, pi|
      pg.list.each do |cmd|
        if cmd.code == 355 || cmd.code == 655
          s = cmd.parameters[0].to_s
          if s =~ /unlock_map|enable_travel|disable_travel|check_exit|wrap_map|pan_offset/
            puts "  ##{ev.id} '#{ev.name}' 页#{pi} 触发=#{pg.trigger} @(#{ev.x},#{ev.y}): #{s}"
          end
        end
      end
    end
  end
  puts ""
end
