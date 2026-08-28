# 验证 p-settings.dat Marshal 格式 (模拟 mod.rb 写入 + read_perma_flags 读取)
perma = Array.new(25, false)
perma[1] = true  # 152
perma[3] = true  # 154
vars = Array.new(25, 0)
nm = 'Niko'

# 写入
File.open('_test_pset.dat', 'wb') do |f|
  Marshal.dump(perma, f)
  Marshal.dump(vars, f)
  Marshal.dump(nm, f)
end

# 读取 (严格按 read_perma_flags 逻辑)
perma_flags = perma_vars = p_name = nil
File.open('_test_pset.dat', 'rb') do |f|
  perma_flags = Marshal.load(f)
  perma_vars  = Marshal.load(f)
  p_name      = Marshal.load(f)
end
puts "flags.size=#{perma_flags.size} vars.size=#{perma_vars.size} name=#{p_name.inspect}"
(151..175).each { |i| puts "  sw#{i}=#{perma_flags[i-151]}" if perma_flags[i-151] }
puts '格式OK' if perma_flags[1] == true && perma_flags[3] == true && p_name == 'Niko'
File.delete('_test_pset.dat')
