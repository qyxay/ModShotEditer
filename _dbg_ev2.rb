# 定位崩溃文件
$LOAD_PATH.unshift 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/rmtools'
require 'rxdata_stub'
DATA_DIR = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data'

Dir.glob("#{DATA_DIR}/Map*.rxdata").sort.each do |f|
  begin
    m = Marshal.load(File.binread(f))
  rescue Exception => e
    puts "LOAD FAIL #{File.basename(f)}: #{e.message}"
    next
  end
  begin
    m.events.each do |eid, ev|
      ev.pages.each do |pg|
        ivs = pg.instance_variables
        if ivs.include?(:@list)
          l = pg.instance_variable_get(:@list)
          raise "list not array: #{l.class}" unless l.is_a?(Array)
        end
      end
    end
  rescue Exception => e
    puts "STRUCT FAIL #{File.basename(f)}: #{e.class} #{e.message}"
  end
end
puts '==done=='
