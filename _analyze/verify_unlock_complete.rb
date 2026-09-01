# ============================================================
#  验证 unlock_or_complete.rb 的 UnlockCompleteScanner.scan 逻辑
#  用真实地图数据(Map%03d.rxdata)离线复跑, 确认开关分类/对话/故事清单正确。
# ============================================================
$LOAD_PATH.unshift('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/runtime/lib/ruby/3.1.0')
require_relative 'oneshot_data'
module RPG
  class Map
    attr_accessor :events
  end
end

DATA2 = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data'
# 运行时 load_data 的桩: 读真实地图文件
def load_data(name)
  base = File.basename(name)
  if base =~ /^Map(\d+)\.rxdata$/
    Marshal.load(File.binread(File.join(DATA2, base)))
  else
    Marshal.load(File.binread(File.join(DATA2, base)))
  end
end

# 直接加载真实 mod 脚本(类定义期不需要 Viewport/Sprite 等, 只在 new 时用到)
load 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/mods/mod/Scripts/unlock_or_complete.rb'

def show(mid)
  info = UnlockCompleteScanner.scan(mid)
  puts "===== Map #{mid} ====="
  puts "  activate   : #{info[:activate].inspect}"
  puts "  close_only : #{info[:close_only].inspect}"
  puts "  dialogues  : #{info[:dialogues].inspect}"
  puts "  story      : #{info[:story].inspect}"
  puts "  doors      : #{info[:doors].map { |d| "#{d[:id]}:#{d[:name]}" }.inspect}"
  puts "  events     : #{info[:events].map { |e| "#{e[:id]}:#{e[:name]}#{e[:completable] ? '~' : ''}" }.inspect}"
  info
end

failures = []
m2 = show(2)
m4 = show(4)
m120 = show(120)

# 断言
failures << 'Map2 activate 应非空' if m2[:activate].empty?
failures << 'Map2 对话应含床/电脑类事件' unless m2[:dialogues].any? { |n| n.to_s =~ /bed|pc|remote|window/i }
failures << 'Map2 story 应含书架类互动事件' unless m2[:story].any? { |n| n.to_s =~ /bookshelf|panorama/i }
failures << 'Map4 对话应含 EV010/EV012' unless (m4[:dialogues] & ['EV010', 'EV012']).size == 2
failures << 'Map120 应含出口关闭标记开关(close_only)' if m120[:close_only].empty? && m120[:activate].empty?
# 新: 门/事件清单
failures << 'Map2 门应含 west/south door' unless m2[:doors].any? { |d| d[:name].to_s =~ /west door/ } &&
                                                 m2[:doors].any? { |d| d[:name].to_s =~ /south door/ }
failures << 'Map4 门应含 north/east door' unless m4[:doors].any? { |d| d[:name].to_s =~ /north door/ } &&
                                                 m4[:doors].any? { |d| d[:name].to_s =~ /east door/ }
failures << 'Map4 事件应含 EV010/EV012' unless m4[:events].any? { |e| e[:name] == 'EV010' } &&
                                             m4[:events].any? { |e| e[:name] == 'EV012' }
failures << 'Map2 事件应含 pc/bed' unless m2[:events].any? { |e| e[:name].to_s =~ /pc|bed/i }

puts ""
if failures.empty?
  puts "result = ALL PASS"
else
  puts "FAIL:"
  failures.each { |f| puts "  - #{f}" }
  exit 1
end
