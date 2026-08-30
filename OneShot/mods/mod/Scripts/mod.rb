# ============================================================
#  mod.rb — preload 入口加载器
#
#  modshot 的 preloadScript 不支持通配符, 只能指定具体文件。
#  本文件作为入口, 自动加载同目录下所有 .rb 文件(排除自身),
#  按文件名排序。新增脚本只需放入此目录, 无需修改 modshot.json。
# ============================================================

script_dir = __dir__
loaded = []

Dir.glob(File.join(script_dir, '*.rb')).sort.each do |path|
  # 排除自身
  next if File.absolute_path(path) == File.absolute_path(__FILE__)
  load path
  loaded << File.basename(path)
end

# 写一个加载日志方便验证
log_path = File.join(script_dir, '..', 'preload_loaded.txt')
File.open(log_path, 'w') do |f|
  f.puts "preload loaded at #{Time.now}"
  f.puts "script_dir: #{script_dir}"
  f.puts "loaded scripts (#{loaded.size}):"
  loaded.each { |name| f.puts "  - #{name}" }
end
