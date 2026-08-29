# ============================================================
#  unpack_xscripts.rb — 把 xScripts.rxdata 解包成 xscripts\ 明文 .rb
#
#  用法: ruby unpack_xscripts.rb [输入路径] [输出目录]
#  默认输入: OneShot/Data/xScripts.rxdata (或 .bak)
#  默认输出: xscripts\
# ============================================================

require 'zlib'
require 'fileutils'

DEFAULT_INPUT = File.join(__dir__, 'OneShot', 'Data', 'xScripts.rxdata')
BAK_INPUT = File.join(__dir__, 'OneShot', 'Data', 'xScripts.rxdata.bak')
DEFAULT_OUTPUT = File.join(__dir__, 'xscripts')

input = ARGV[0] || (File.exist?(BAK_INPUT) ? BAK_INPUT : DEFAULT_INPUT)
output_dir = ARGV[1] || DEFAULT_OUTPUT

unless File.exist?(input)
  abort "错误: 找不到文件 #{input}"
end

data = File.open(input, 'rb') { |f| Marshal.load(f) }
puts "读取 #{data.size} 个脚本 from #{input}"

FileUtils.mkdir_p(output_dir)

data.each_with_index do |entry, idx|
  magic, script_name, compressed = entry
  # zlib 解压
  content = Zlib::Inflate.inflate(compressed)
  # 文件名: 4位编号_脚本名.rb
  filename = "%04d_%s.rb" % [idx, script_name]
  filepath = File.join(output_dir, filename)
  # 写入原始字节
  File.binwrite(filepath, content)
  if idx < 3 || idx >= data.size - 2
    puts "  [#{idx.to_s.rjust(4)}] #{script_name} (#{content.bytesize} bytes)"
  elsif idx == 3
    puts "  ..."
  end
end

puts "\n解包完成: #{output_dir} (#{data.size} 个文件)"
