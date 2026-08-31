# ============================================================
#  鎵剧敤鍙橀噺鍋氫紶閫佺洰鏍囩殑 201 浜嬩欢 + 鍒ゆ柇鍙橀噺6鐨勫钩琛屼簨浠?
#  RMXP: 201 浼犻€?parameters=[map_id, x, y, dir, fade]
#  map_id >= 10000 鏃惰〃绀哄彉閲?(map_id-10000)
# ============================================================

require_relative 'oneshot_data'

module RPG
  class MapInfo
    attr_accessor :name, :parent_id
  end
end

DATA2 = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data'
# 杞藉叆 MapInfos 鐢ㄤ簬鍚嶅瓧
mapi = Marshal.load(File.binread("#{DATA2}/MapInfos.rxdata"))

puts "===== A) 201 浼犻€?涓?map_id 鏄彉閲?(>=10000) 鐨勪簨浠?====="
Dir.glob("#{DATA2}/Map*.rxdata").each do |f|
  mid = f[/Map(\d+)\.rxdata/, 1].to_i
  begin
    m = Marshal.load(File.binread(f))
  rescue
    next
  end
  evs_h = m.instance_variable_get(:@events); next unless evs_h; evs_h.each_value do |ev|
    ev.pages.each_with_index do |pg, pi|
      pg.list.each do |cmd|
        if cmd.code == 201
          mid_par = cmd.parameters[0]
          if mid_par && mid_par >= 10000
            v = mid_par - 10000
            name = (mapi[ev.id] rescue nil) ? ev.name : ev.name
            puts "  鍦板浘#{mid} ##{ev.id} '#{ev.name}' 椤?{pi} 瑙﹀彂=#{pg.trigger}: 浼犻€?map_id=鍙橀噺#{v} 鍧愭爣=#{cmd.parameters[1]},#{cmd.parameters[2]}"
          end
        end
      end
    end
  end
end

puts ""
puts "===== B) 鏉′欢鍒嗘敮鍒ゆ柇鍙橀噺6/8/9 鐨勪簨浠?====="
Dir.glob("#{DATA2}/Map*.rxdata").each do |f|
  mid = f[/Map(\d+)\.rxdata/, 1].to_i
  begin
    m = Marshal.load(File.binread(f))
  rescue
    next
  end
  evs_h = m.instance_variable_get(:@events); next unless evs_h; evs_h.each_value do |ev|
    ev.pages.each_with_index do |pg, pi|
      pg.list.each do |cmd|
        if cmd.code == 111 && cmd.parameters[0] == 1 && [6,7,8,9].include?(cmd.parameters[1])
          puts "  鍦板浘#{mid} ##{ev.id} '#{ev.name}' 椤?{pi} 瑙﹀彂=#{pg.trigger}: 鏉′欢鍒嗘敮 鍙橀噺#{cmd.parameters[1]} #{cmd.parameters.inspect}"
        end
      end
    end
  end
end

