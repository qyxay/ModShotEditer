# debug: 检查地图事件 page 结构
$LOAD_PATH.unshift 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/rmtools'
require 'rxdata_stub'

DATA_DIR = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data'
begin
  m = Marshal.load(File.binread("#{DATA_DIR}/Map001.rxdata"))
  puts "Map001 events=#{m.events.size}"
  m.events.each do |eid, ev|
    puts "  ev##{eid} name=#{ev.name} pages=#{ev.pages.size}"
    ev.pages.each_with_index do |pg, pi|
      ivs = pg.instance_variables
      puts "    page#{pi} ivars=#{ivs.inspect}"
      list = ivs.include?(:@list) ? pg.instance_variable_get(:@list) : nil
      ec   = ivs.include?(:@event_commands) ? pg.instance_variable_get(:@event_commands) : nil
      puts "      @list=#{list ? list.class.to_s + ' x' + list.size.to_s : 'nil'}"
      puts "      @event_commands=#{ec ? ec.class.to_s + ' x' + ec.size.to_s : 'nil'}"
      if list && list.size > 0
        list.first(5).each_with_index do |cmd, i|
          puts "      [#{i}] code=#{cmd.code} p=#{cmd.parameters.inspect}"
        end
      end
    end
  end
rescue Exception => e
  puts "错误: #{e.class}: #{e.message}"
  puts e.backtrace.first(5)
end
