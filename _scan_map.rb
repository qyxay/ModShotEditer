# 修复版：扫描地图事件，搜索 fake_save/save_progress/oneshot（排除 MapInfos）
$LOAD_PATH.unshift 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/rmtools'
require 'rxdata_stub'

DATA_DIR = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data'
CE_PATH  = "#{DATA_DIR}/CommonEvents.rxdata"

def page_cmds(pg)
  return nil unless pg.respond_to?(:instance_variable_get)
  ivs = pg.instance_variables
  v = pg.instance_variable_get(:@list) if ivs.include?(:@list)
  v.is_a?(Array) ? v : nil
end

def scan_list(list, label)
  return unless list
  list.each do |cmd|
    next unless cmd.respond_to?(:code)
    begin
      c = cmd.code
      p = cmd.parameters.nil? ? [] : cmd.parameters
      next unless [111, 355, 655, 108, 408, 401, 101].include?(c)
      txt = (c == 111 && p[0] == 12) ? p[1].to_s : p.join(' ')
      next unless txt =~ /fake_save|save_progress|oneshot|clover|progress|end_game|ending|completed|new_game|continue/i
      puts "#{label} code=#{c}: #{txt[0,110]}"
    rescue Exception
    end
  end
end

Dir.glob("#{DATA_DIR}/Map*.rxdata").sort.each do |f|
  next if File.basename(f) =~ /MapInfos/
  begin
    m = Marshal.load(File.binread(f))
    next unless m.respond_to?(:events)
    m.events.each do |eid, ev|
      begin
        next unless ev.respond_to?(:pages)
        ev.pages.each_with_index do |pg, pi|
          scan_list(page_cmds(pg), "#{File.basename(f)} ev##{eid} pg#{pi}")
        end
      rescue Exception => e
        puts "EV FAIL #{File.basename(f)} ev##{eid}: #{e.class} #{e.message}"
      end
    end
  rescue Exception => e
    puts "READ FAIL #{File.basename(f)}: #{e.message}"
  end
end

if File.exist?(CE_PATH)
  begin
    arr = Marshal.load(File.binread(CE_PATH))
    arr.each_with_index do |ce, i|
      scan_list(page_cmds(ce), "CommonEvent##{i}")
    end
  rescue Exception => e
    puts "CE FAIL: #{e.message}"
  end
end
puts '==完成=='
