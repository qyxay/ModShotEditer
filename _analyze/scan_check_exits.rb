# -*- coding: utf-8 -*-
# 扫描所有地图的 check_exit 出口事件, 解析 var6-10 传送目标
# OneShot 第二套传送: 并行exit事件调 check_exit -> 设 var6(目标地图)/var7(x)/var8(y)/var9(d)/var10(off)
# -> 调 CE5-8(方向走出屏幕) -> 开关11 ON -> CE9 'Exit Transition' 变量传送 [1,6,7,8,0,0]
require_relative 'oneshot_data'
module RPG
  class MapInfo
    attr_accessor :name, :parent_id, :order, :expanded, :scroll_x, :scroll_y
  end
end

MAP_INFOS_RAW = Marshal.load(File.binread(File.join(DATA, 'MapInfos.rxdata')))
MAP_INFOS = {}
MAP_INFOS_RAW.each { |k, v| MAP_INFOS[k] = v }

def map_name(id)
  i = MAP_INFOS[id]
  i ? i.name.to_s : "Map#{id}"
end

results = []
total_check_exit_events = 0

Dir.glob(File.join(DATA, 'Map*.rxdata')).sort.each do |f|
  mid = f[/Map(\d+)\.rxdata/, 1].to_i
  m = Marshal.load(File.binread(f))
  evs = m.instance_variable_get(:@events)
  next unless evs
  evs.each do |evid, ev|
    next unless ev
    (ev.pages || []).each_with_index do |pg, pi|
      next unless pg && pg.list
      ce_script = nil
      area = nil
      vars = {}   # var_id -> 直接赋值 (取最后)
      calls_ce = []
      has_201 = false
      pg.list.each do |cmd|
        c = cmd.code
        p = cmd.parameters
        if c == 355 || c == 655
          s = p[0].to_s
          if s =~ /check_exit\s*\(\s*(-?\d+)\s*,\s*(-?\d+)\s*(?:,\s*(x|y)\s*:\s*(-?\d+))?\s*\)|check_exit\s+(-?\d+)\s*,\s*(-?\d+)\s*(?:,\s*(x|y)\s*:\s*(-?\d+))?/
            ce_script = s
            if $3
              area = { axis: $3, min: $1.to_i, max: $2.to_i, fixed: $4.to_i }
            elsif $7
              area = { axis: $7, min: $5.to_i, max: $6.to_i, fixed: $8.to_i }
            else
              area = { axis: nil, min: ($1 || $5).to_i, max: ($2 || $6).to_i, fixed: nil }
            end
          end
        elsif c == 122
          # [var_id, var_id, type, flag, ...]
          vid = p[0]
          if [6, 7, 8, 9, 10].include?(vid) && p[2] == 0
            vars[vid] = p[4]
          elsif [6, 7, 8, 9, 10].include?(vid)
            vars[vid] = :dynamic
          end
        elsif c == 117
          calls_ce << p[0]
        elsif c == 201
          has_201 = true
        end
      end
      next unless ce_script
      total_check_exit_events += 1
      results << {
        map: mid, map_name: map_name(mid), ev: evid, ev_name: ev.name.to_s,
        page: pi, trigger: pg.trigger,
        area: area, script: ce_script.strip,
        vars: vars, calls_ce: calls_ce.uniq, has_201: has_201
      }
    end
  end
end

puts "含 check_exit 的事件数: #{total_check_exit_events}"
puts "=" * 60

# 按地图分组输出, 只有 var6(目标地图) 明确才算有效出口
valid = results.select { |r| r[:vars][6] && r[:vars][6] != :dynamic }
puts "有效出口(var6=静态目标地图): #{valid.size} / 全部 #{results.size}"
puts "=" * 60
seen = {}
valid.sort_by { |r| [r[:map], r[:ev]] }.each do |r|
  v6 = r[:vars][6]
  v7 = r[:vars][7] || '-'
  v8 = r[:vars][8] || '-'
  v9 = r[:vars][9] || '-'
  v10 = r[:vars][10] || '-'
  ax = r[:area]
  area_s = ax ? "#{ax[:axis]}#{ax[:fixed]}? y/x[#{ax[:min]}..#{ax[:max]}]" : '?'
  puts "map#{r[:map].to_s.rjust(3)} ev#{r[:ev].to_s.rjust(3)} '#{r[:ev_name]}' trig=#{r[:trigger]} p#{r[:page]} " \
       "-> map#{v6}(x=#{v7},y=#{v8},d=#{v9},off=#{v10}) area=#{area_s} ce=#{r[:calls_ce].inspect}"
end

puts "=" * 60
dyn = results.select { |r| r[:vars][6] == :dynamic }
puts "动态目标(var6由变量/计算指定): #{dyn.size}"
dyn.each do |r|
  puts "map#{r[:map]} ev#{r[:ev]} '#{r[:ev_name]}' vars=#{r[:vars].inspect} ce=#{r[:calls_ce].inspect}"
end

# 汇总: 有效出口的目标地图分布
puts "=" * 60
dist = Hash.new(0)
valid.each { |r| dist[r[:vars][6]] += 1 }
dist.sort.each { |k, v| puts "  -> map#{k} (#{map_name(k)}): #{v} 个出口" }
