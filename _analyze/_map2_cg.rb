# -*- coding: utf-8 -*-
require File.expand_path('oneshot_data', __dir__)

[2, 188].each do |mid|
  map = os_load_map(mid)
  evs = map.instance_variable_get(:@events) rescue {}
  evs.each do |id, ev|
    pages = ev.instance_variable_get(:@pages) rescue []
    pages.each_with_index do |pg, pi|
      list = pg.instance_variable_get(:@list) rescue []
      has_cg = list.any? { |c| c && c.code == 231 && (c.parameters[1].to_s rescue '') =~ /cg_wake/ }
      next unless has_cg
      puts "=== map#{mid} ev#{id} p#{pi} name=#{ev.instance_variable_get(:@name)} trigger=#{pg.instance_variable_get(:@trigger)} ==="
      list.each_with_index do |c, i|
        next unless c
        pm = c.parameters.inspect
        pm = pm[0, 70] + '...' if pm.size > 70
        puts "  [#{i}] c#{c.code} #{pm}" if [231, 235, 106, 105, 101, 112, 413].include?(c.code)
      end
      puts
    end
  end
end
