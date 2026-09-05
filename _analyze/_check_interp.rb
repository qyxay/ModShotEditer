# -*- coding: utf-8 -*-
puts '=== setup_common_event / @event_id / common_event_id ==='
Dir.glob('xscripts/*.rb').each do |f|
  File.readlines(f).each_with_index do |l, i|
    if l =~ /setup_common_event|@event_id\s*=|common_event_id/
      puts "#{File.basename(f)}:#{i + 1}: #{l.strip[0, 100]}"
    end
  end
end
