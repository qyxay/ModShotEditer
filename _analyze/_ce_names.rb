# -*- coding: utf-8 -*-
require File.expand_path('oneshot_data', __dir__)
module RPG
  class CommonEvent; end
end
ces = Marshal.load(File.binread('OneShot/Data/CommonEvents.rxdata'))
[15, 42].each do |id|
  ce = ces[id]
  puts "CE#{id}: name=#{ce.instance_variable_get(:@name)} trigger=#{ce.instance_variable_get(:@trigger)} sw=#{ce.instance_variable_get(:@switch_id)}"
end
