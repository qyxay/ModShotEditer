# ============================================================
#  mod.rb — preload 入口加载器
#
#  modshot 的 preloadScript 不支持通配符, 只能指定具体文件。
#  本文件作为入口:
#    1. 添加 runtime 标准库路径 (使 require 'json' 等可用)
#    2. 自动加载同目录下所有 .rb 文件(排除自身), 按文件名排序
#
#  新增脚本只需放入此目录, 无需修改 modshot.json。
# ============================================================

script_dir = __dir__

# --- 1. 添加 runtime 标准库路径 ---
# modshot 的 Ruby 环境 $LOAD_PATH 只有 gameFolder, 没有标准库。
# runtime/ 目录下有完整的 Ruby 3.1.5 标准库, 添加进来即可使用。
runtime_lib = File.absolute_path(File.join(script_dir, '..', '..', '..', '..', 'runtime', 'lib', 'ruby', '3.1.0'))
runtime_arch = File.join(runtime_lib, 'x64-mingw64')

if File.exist?(runtime_lib)
  $LOAD_PATH.unshift(runtime_lib)
  $LOAD_PATH.unshift(runtime_arch) if File.exist?(runtime_arch)
end

# --- 2. 自动加载同目录下所有 .rb 文件 ---
loaded = []
errors = []

Dir.glob(File.join(script_dir, '*.rb')).sort.each do |path|
  # 排除自身
  next if File.absolute_path(path) == File.absolute_path(__FILE__)
  begin
    load path
    loaded << File.basename(path)
  rescue => e
    errors << "#{File.basename(path)}: #{e.class}: #{e.message}"
  end
end

# --- 3. 写加载日志 ---
log_path = File.join(script_dir, '..', 'logs', 'preload_loaded.txt')
File.open(log_path, 'w') do |f|
  f.puts "preload loaded at #{Time.now}"
  f.puts "script_dir: #{script_dir}"
  f.puts "runtime_lib: #{runtime_lib} (exists=#{File.exist?(runtime_lib)})"
  f.puts "runtime_arch: #{runtime_arch} (exists=#{File.exist?(runtime_arch)})"
  f.puts ""
  f.puts "=== \$LOAD_PATH ==="
  $LOAD_PATH.each { |p| f.puts "  #{p}" }
  f.puts ""
  f.puts "loaded scripts (#{loaded.size}):"
  loaded.each { |name| f.puts "  - #{name}" }
  if errors.any?
    f.puts ""
    f.puts "errors (#{errors.size}):"
    errors.each { |e| f.puts "  - #{e}" }
  end
end
