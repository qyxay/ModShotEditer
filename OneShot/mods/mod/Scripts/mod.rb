# ============================================================
#  mod.rb — 图片过场跳过 mod 的配置加载器
#
#  读取 mods/mod/skip_pictures.txt 决定是否跳过图片过场:
#    内容为 1 / true / yes / on  → 开启跳过
#    内容为 0 / false / no / off → 关闭跳过(恢复原始游戏)
#    文件不存在                    → 默认开启
#
#  实际跳过逻辑注入在 Data/xScripts.rxdata 的 Interpreter#execute_command
#  中, 通过全局变量 $pic_skip_enabled 控制是否生效。
# ============================================================

config_path = File.join(__dir__, '..', 'skip_pictures.txt')

$pic_skip_enabled = if File.exist?(config_path)
  content = File.read(config_path).strip.downcase
  if ['1', 'true', 'yes', 'on'].include?(content)
    true
  elsif ['0', 'false', 'no', 'off'].include?(content)
    false
  else
    true  # 无法识别的内容, 默认开启
  end
else
  true  # 文件不存在, 默认开启
end

# 写一个状态文件方便验证
status_path = File.join(__dir__, '..', 'skip_pictures_status.txt')
File.open(status_path, 'w') do |f|
  f.puts "pic_skip_enabled = #{$pic_skip_enabled}"
  f.puts "config_path = #{config_path}"
  f.puts "config_exists = #{File.exist?(config_path)}"
  f.puts "loaded_at = #{Time.now}"
end
