# -*- coding: utf-8 -*-
# 1) 所有 Scene 类
puts "=== Scene 类 ==="
Dir.glob('xscripts/*.rb').each do |f|
  File.readlines(f).each do |l|
    if l =~ /^class (Scene_\w+)/
      puts "#{File.basename(f)}: #{Regexp.last_match(1)}"
    end
  end
end

# 2) 直接操作 $game_screen.pictures / pictures[ 的脚本
puts "\n=== pictures 直接操作 ==="
Dir.glob('xscripts/*.rb').each do |f|
  File.readlines(f).each_with_index do |l, i|
    if l =~ /pictures\[|\.pictures|game_screen\.pictures|Graphics\.snapshot|\.show\(.*cg/i
      puts "#{File.basename(f)}:#{i + 1}: #{l.strip[0, 90]}"
    end
  end
end
