$LOAD_PATH.unshift 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/rmtools'
require 'rxdata_stub'
D = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data'
def cond_str(pg)
  c = pg.instance_variable_get(:@condition)
  s = ''
  s += " sw1=#{c.instance_variable_get(:@switch1_id)}#{c.instance_variable_get(:@switch1_valid) ? '(v)' : ''}"
  s += " sw2=#{c.instance_variable_get(:@switch2_id)}#{c.instance_variable_get(:@switch2_valid) ? '(v)' : ''}"
  s += " var=#{c.instance_variable_get(:@variable_id)}#{c.instance_variable_get(:@variable_valid) ? '(v)' : ''}=#{c.instance_variable_get(:@variable_value)}"
  s += " self=#{c.instance_variable_get(:@self_switch_valid) ? c.instance_variable_get(:@self_switch_ch) : '-'}"
  s
end
[242, 255].each do |mid|
  m = Marshal.load(File.binread(format("#{D}/Map%03d.rxdata", mid)))
  puts "=== Map#{mid} ==="
  m.events.each do |eid, ev|
    ev.pages.each_with_index do |pg, i|
      list = pg.instance_variable_get(:@list)
      next if list.size <= 1
      puts "  ev#{eid} '#{ev.name}' pg#{i}#{cond_str(pg)} cmds=#{list.size}"
    end
  end
end
