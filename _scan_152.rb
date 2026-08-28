# 扫描所有地图+公共事件：找开关 152/160 的设置(code121) 和 152/160 条件(code111, [0,id,val,0,0])
$LOAD_PATH.unshift 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/rmtools'
require 'rxdata_stub'

DATA_DIR = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data'

def cmds(pg)
  v = pg.instance_variable_get(:@list)
  v.is_a?(Array) ? v : []
end

def scan(file, label)
  m = Marshal.load(File.binread(file))
  return unless m.respond_to?(:events)
  m.events.each do |eid, ev|
    next unless ev.respond_to?(:pages)
    ev.pages.each_with_index do |pg, pi|
      cmds(pg).each_with_index do |cmd, ci|
        next unless cmd.respond_to?(:code)
        c = cmd.code; p = cmd.parameters.nil? ? [] : cmd.parameters
        if c == 121  # 开关操作
          a, b, v = p[0], p[1], p[2]
          if (a..b).to_a.any? { |i| [152, 160, 154].include?(i) }
            puts "#{label} [#{ci}] code121 开关#{a}-#{b} = #{v}"
          end
        elsif c == 111 && p[0] == 0  # 开关条件
          sw = p[1]; val = p[2]
          if [152, 160, 154].include?(sw)
            puts "#{label} [#{ci}] code111 条件 开关#{sw} #{val==0 ? '== 0' : '== 1'}"
          end
        end
      end
    end
  end
end

Dir.glob("#{DATA_DIR}/Map*.rxdata").sort.each do |f|
  next if File.basename(f) =~ /MapInfos/
  begin
    scan(f, File.basename(f))
  rescue Exception => e
    puts "FAIL #{File.basename(f)}: #{e.message}"
  end
end

if File.exist?("#{DATA_DIR}/CommonEvents.rxdata")
  arr = Marshal.load(File.binread("#{DATA_DIR}/CommonEvents.rxdata"))
  arr.each_with_index do |ce, i|
    begin
      cmds(ce).each_with_index do |cmd, ci|
        next unless cmd.respond_to?(:code)
        c = cmd.code; p = cmd.parameters.nil? ? [] : cmd.parameters
        if c == 121
          a, b, v = p[0], p[1], p[2]
          if (a..b).to_a.any? { |x| [152, 160, 154].include?(x) }
            puts "CE##{i} [#{ci}] code121 开关#{a}-#{b} = #{v}"
          end
        elsif c == 111 && p[0] == 0
          sw = p[1]; val = p[2]
          if [152, 160, 154].include?(sw)
            puts "CE##{i} [#{ci}] code111 条件 开关#{sw} #{val==0 ? '== 0' : '== 1'}"
          end
        end
      end
    rescue Exception
    end
  end
end
puts '==完成=='
