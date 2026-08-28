# 验证新 mod.rb 核心逻辑: 152/154/160 置位 + 读回
save_path = '_vdir'
Dir.mkdir(save_path) unless Dir.exist?(save_path)
pset = File.join(save_path, 'p-settings.dat')

# 模拟 mod.rb 读取+置位+写回
perma_flags = Array.new(25, false)
perma_vars  = Array.new(25, 0)
player_name = 'Niko'
if File.exist?(pset)
  File.open(pset, 'rb') do |f|
    perma_flags = Marshal.load(f)
    perma_vars  = Marshal.load(f)
    player_name = Marshal.load(f)
  end
end
perma_flags[152 - 151] = true
perma_flags[154 - 151] = true
perma_flags[160 - 151] = true
File.open(pset, 'wb') do |f|
  Marshal.dump(perma_flags, f)
  Marshal.dump(perma_vars, f)
  Marshal.dump(player_name, f)
end

# 读回
File.open(pset, 'rb') do |f|
  a = Marshal.load(f)
  Marshal.load(f)
  Marshal.load(f)
  puts "读回: sw152=#{a[1]}  sw154=#{a[3]}  sw160=#{a[9]}"
  puts '完整格式OK (152/154/160 全部 true)' if a[1] && a[3] && a[9]
end

require 'fileutils'
FileUtils.rm_rf(save_path)
