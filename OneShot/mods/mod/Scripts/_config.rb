# ============================================================
#  _config.rb — 统一配置加载器
#
#  所有 mod 脚本共享同一个 config.json。
#  本文件按文件名排序最先加载(_ 开头 ASCII 码最小),
#  读取配置后存入全局变量 $mod_config。
#  其他脚本直接使用 $mod_config["key"], 不再各自读取文件。
# ============================================================

require 'json'

config_path = File.join(__dir__, '..', 'config.json')

$mod_config = if File.exist?(config_path)
  begin
    parsed = JSON.parse(File.read(config_path))
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end
else
  {}
end

# --- 写状态文件 ---
status_path = File.join(__dir__, '..', 'config_loaded.txt')
File.open(status_path, 'w') do |f|
  f.puts "config_path = #{config_path}"
  f.puts "config = #{JSON.pretty_generate($mod_config)}"
  f.puts "loaded_at = #{Time.now}"
end
