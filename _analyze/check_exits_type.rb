ROOT = File.expand_path('..', __dir__)
require_relative 'oneshot_data'
DATA2 = "#{ROOT}/OneShot/Data"

targets = [2, 3, 5, 119, 120, 225]
targets.each do |mid|
  m = os_load_map(mid)
  evs = m.instance_variable_get(:@events)
  puts "===== 地图#{mid} ====="
  found = false
  evs.each do |id, ev|
    next unless ev
    name = ev.name.to_s
    next unless name =~ /exit|door|transfer/i
    found = true
    info = []
    ev.pages.each_with_index do |pg, pi|
      codes = pg.list.map(&:code).uniq
      has201 = pg.list.any? { |c| c.code == 201 }
      has_check_exit = pg.list.any? { |c| [355, 655].include?(c.code) && c.parameters[0].to_s =~ /check_exit/i }
      has122_6 = pg.list.any? { |c| c.code == 122 && c.parameters[0] == 6 }
      has117 = pg.list.any? { |c| c.code == 117 }
      info << "页#{pi}触发=#{pg.trigger} [201=#{has201} check_exit=#{has_check_exit} VAR6=#{has122_6} 117=#{has117} codes=#{codes.inspect}]"
    end
    puts "  ##{id} '#{name}' @(#{ev.x},#{ev.y}) #{info.join('  ')}"
  end
  puts "  (无 exit/door 事件)" unless found
end
