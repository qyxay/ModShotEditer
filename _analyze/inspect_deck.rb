# ============================================================
#  分析地图 120/225 'observation deck' 事件结构
#  重点: 门/传送/出口事件 + 自开关页条件
# ============================================================

require_relative 'oneshot_data'

[120, 225].each do |mid|
  map = os_load_map(mid)
  w = map.instance_variable_get(:@width)
  h = map.instance_variable_get(:@height)
  puts "===== 地图#{mid} (#{w}x#{h}) ====="
  evs = map.instance_variable_get(:@events)
  evs.each do |id, ev|
    name = ev.name
    x = ev.x
    y = ev.y
    pages = ev.pages
    puts "  ##{id} '#{name}' @(#{x},#{y}) 页数=#{pages.size}"
    pages.each_with_index do |pg, pi|
      c = pg.condition
      trig = pg.trigger
      list = pg.list
      conds = []
      conds << "SW#{c.switch1_id}" if c.switch1_valid
      conds << "SW#{c.switch2_id}" if c.switch2_valid
      conds << "VAR#{c.variable_id}>=#{c.variable_value}" if c.variable_valid
      conds << "SS#{c.self_switch_ch}" if c.self_switch_valid
      codes = list.map(&:code)
      teleports = list.select { |cmd| cmd.code == 201 }
      tele_targets = teleports.map do |cmd|
        p = cmd.parameters
        "(map#{p[0]},#{p[1]},#{p[2]})"
      end
      move_routes = list.select { |cmd| cmd.code == 209 || cmd.code == 205 }
      summary = []
      summary << "101对话" if codes.include?(101)
      summary << "传送#{tele_targets.join(',')}" unless tele_targets.empty?
      summary << "移动路线#{move_routes.size}条" unless move_routes.empty?
      is_empty = codes.all? { |cd| cd == 0 || cd == 355 || cd == 412 || cd == 604 || cd == 655 }
      puts "    页#{pi}: 触发=#{trig} 条件=[#{conds.join(',')}] #{summary.join(' ')} #{'[空/仅结束]' if is_empty}"
    end
  end
  puts ""
end
