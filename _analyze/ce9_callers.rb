ROOT = File.expand_path('..', __dir__)
require_relative 'oneshot_data'

module RPG
  class CommonEvent
    attr_accessor :trigger, :condition, :list, :name
  end
end

DATA2 = "#{ROOT}/OneShot/Data"
ces = Marshal.load(File.binread("#{DATA2}/CommonEvents.rxdata"))

puts "===== trigger=1 公共事件的名字 ====="
[1,2,9,15,40].each { |i| puts "  ##{i}: #{ces[i].name.inspect}" }

puts ""
puts "===== 谁调用公共事件 #9 (117:9) ====="
found = false
Dir.glob("#{DATA2}/Map*.rxdata").each do |f|
  mid = f[/Map(\d+)\.rxdata/, 1].to_i
  begin
    m = Marshal.load(File.binread(f))
  rescue
    next
  end
  evs = m.instance_variable_get(:@events)
  next unless evs
  evs.each_value do |ev|
    ev.pages.each_with_index do |pg, pi|
      pg.list.each do |cmd|
        if cmd.code == 117 && cmd.parameters[0] == 9
          puts "  地图#{mid} ##{ev.id} '#{ev.name}' 页#{pi} 触发=#{pg.trigger}"
          found = true
        end
      end
    end
  end
end
ces.each_with_index do |cce, i|
  next unless cce
  cce.list.each do |cmd|
    if cmd.code == 117 && cmd.parameters[0] == 9
      puts "  公共事件##{i} '#{cce.name}': 调用公共事件9"
      found = true
    end
  end
end
puts "  (无调用者)" unless found

puts ""
puts "===== 公共事件 #1/#2/#15/#40 的 list 摘要 ====="
[1,2,15,40].each do |i|
  ce = ces[i]
  codes = ce.list.select { |c| c.code != 0 && c.code != 509 }.map(&:code).uniq
  puts "  ##{i} '#{ce.name}': 命令codes=#{codes.inspect}"
end
