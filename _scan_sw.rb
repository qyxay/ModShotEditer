# 扫描事件命令（修复版）：抓脚本条件/脚本调用/开关操作中的 Solstice 相关逻辑
$LOAD_PATH.unshift 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/rmtools'
require 'rxdata_stub'

DATA_DIR = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data'
CE_PATH  = "#{DATA_DIR}/CommonEvents.rxdata"

def page_cmds(pg)
  return nil unless pg.respond_to?(:instance_variable_get)
  ivs = pg.instance_variables
  if ivs.include?(:@list)
    v = pg.instance_variable_get(:@list)
    return v if v.is_a?(Array)
  end
  nil
end

def scan_list(list, label, sw_tally)
  return unless list
  list.each do |cmd|
    next unless cmd.respond_to?(:code)
    begin
      c = cmd.code
      p = cmd.parameters.nil? ? [] : cmd.parameters
      case c
      when 111
        if p[0] == 12
          txt = p[1].to_s
          if txt =~ /\$game_switches|switches\[|$game_variables|variables\[|progress|oneshot|ending|clover/i
            puts "#{label} 脚本条件: #{txt[0,100]}"
          end
        elsif p[0] == 0 && p[1].to_i.between?(151, 200)
          sw_tally[p[1].to_i][:cond] += 1
          puts "#{label} 开关条件: 开关#{p[1]} = #{p[2]}"
        end
      when 121
        (p[0].to_i..p[1].to_i).each do |sw|
          next unless sw.between?(151, 200)
          sw_tally[sw][:set] += 1
          puts "#{label} 设置开关: #{sw} = #{p[2]}"
        end
      when 355, 655
        txt = p.join(' ')
        if txt =~ /progress|oneshot|clover|switches|variables|ending|ruin/i
          puts "#{label} 脚本: #{txt[0,100]}"
        end
      end
    rescue Exception
    end
  end
end

sw_tally = Hash.new { |h, k| h[k] = { cond: 0, set: 0 } }
total_cond = 0

Dir.glob("#{DATA_DIR}/Map*.rxdata").sort.each do |f|
  begin
    m = Marshal.load(File.binread(f))
    next unless m.respond_to?(:events)
    m.events.each do |eid, ev|
      next unless ev.respond_to?(:pages)
      ev.pages.each_with_index do |pg, pi|
        scan_list(page_cmds(pg), "#{File.basename(f)} ev##{eid} pg#{pi}", sw_tally)
      end
    end
  rescue Exception => e
    puts "#{f} 读取失败: #{e.message}"
  end
end

if File.exist?(CE_PATH)
  begin
    arr = Marshal.load(File.binread(CE_PATH))
    arr.each_with_index do |ce, i|
      scan_list(page_cmds(ce), "CommonEvent##{i}", sw_tally)
    end
  rescue Exception => e
    puts "CommonEvents 读取失败: #{e.message}"
  end
end

puts "===== 开关151-200 汇总 ====="
sw_tally.keys.sort.each { |sw| puts "开关#{sw}: 检查x#{sw_tally[sw][:cond]} 设置x#{sw_tally[sw][:set]}" }
puts "==完成=="
