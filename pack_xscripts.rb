# ============================================================
#  pack_xscripts.rb — 把 xscripts\ 明文 .rb 打包成 xScripts.rxdata
#
#  用法: ruby pack_xscripts.rb [输出路径]
#  默认输出: OneShot/mods/mod/Data/xScripts.rxdata
#
#  工作流:
#    1. 编辑 xscripts\ 目录下的 .rb 文件
#    2. 运行 ruby pack_xscripts.rb
#    3. 生成的 xScripts.rxdata 通过 modshot patches 覆盖
# ============================================================

require 'zlib'
require 'fileutils'

XSCRIPTS_DIR = File.join(__dir__, 'xscripts')
DEFAULT_OUTPUT = File.join(__dir__, 'OneShot', 'mods', 'mod', 'Data', 'xScripts.rxdata')

output = ARGV[0] || DEFAULT_OUTPUT

unless Dir.exist?(XSCRIPTS_DIR)
  abort "错误: 找不到目录 #{XSCRIPTS_DIR}"
end

# 读取所有 .rb 文件, 按文件名开头的编号排序
files = Dir.glob(File.join(XSCRIPTS_DIR, '*.rb')).sort_by do |path|
  name = File.basename(path)
  if name =~ /\A(\d+)_/
    $1.to_i
  else
    99999
  end
end

puts "找到 #{files.size} 个脚本文件"

scripts = []
files.each_with_index do |path, idx|
  name = File.basename(path, '.rb')
  # 提取脚本名 (去掉开头的编号和下划线)
  script_name = name.sub(/\A\d+_/, '')
  # 读取原始字节 (不做编码转换)
  content = File.binread(path)
  # zlib 压缩
  compressed = Zlib::Deflate.deflate(content)
  # 构造条目: [magic=0, 脚本名, 压缩内容]
  scripts << [0, script_name, compressed]
  if idx < 3 || idx >= files.size - 2
    puts "  [#{idx.to_s.rjust(4)}] #{script_name} (#{content.bytesize} -> #{compressed.bytesize} bytes)"
  elsif idx == 3
    puts "  ..."
  end
end

# 写入输出文件
FileUtils.mkdir_p(File.dirname(output))
File.open(output, 'wb') { |f| Marshal.dump(scripts, f) }

puts "\n打包完成: #{output} (#{File.size(output)} bytes)"
puts "包含 #{scripts.size} 个脚本"
