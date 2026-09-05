ROOT = File.expand_path('..', __dir__)
require_relative 'oneshot_data'

module RPG
  class CommonEvent
    attr_accessor :trigger, :condition, :list
  end
  class CommonEvent::Condition
    attr_accessor :switch1_valid, :switch1_id
  end
end

map = os_load_map(120)
evs = map.instance_variable_get(:@events)
se = evs[2]  # south exit
puts "===== south exit 完整命令 ====="
se.pages[0].list.each_with_index do |cmd, ci|
  puts "  [#{ci}] code=#{cmd.code} #{cmd.parameters.inspect}"
end

# 找使用变量6/8/9 的脚本/事件 (传送读取)
puts ""
puts "===== 找读取变量 6/8/9 的传送逻辑 ====="
DATA2 = "#{ROOT}/OneShot/Data"
# 全地图扫 201 传送 + 变量使用
total_201 = 0
Dir.glob("#{DATA2}/Map*.rxdata").each do |f|
  begin
    m = Marshal.load(File.binread(f))
    m.instance_variable_get(:@events).each_value do |ev|
      ev.pages.each do |pg|
        pg.list.each do |cmd|
          if cmd.code == 201
            total_201 += 1
          end
        end
      end
    end
  rescue
  end
end
puts "全地图 201 传送指令总数: #{total_201}"
