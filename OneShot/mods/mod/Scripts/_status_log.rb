# ============================================================
#  _status_log.rb — 统一状态文件写入工具 (StatusLog)
#
#  各 mod 脚本启动时都会往 mods/mod/logs/ 写一份状态文件, 记录
#  开关值/配置/补丁方式/加载时间, 方便排查。原实现每个文件重复
#  一份 Dir.mkdir + File.open 样板, 本文件统一封装。
#
#  用法:
#    StatusLog.write('skip_dialogue_status.txt', [
#      "skip_dialogue_enabled = #{$skip_dialogue_enabled}",
#      "loaded_at = #{Time.now}"
#    ])
#
#  _ 开头保证按文件名排序最先加载(在 dev_settings 等使用方之前)
# ============================================================

module StatusLog
  # 写 mods/mod/logs/<name>, 内容为 lines 逐行
  def self.write(name, lines)
    path = File.join(__dir__, '..', 'logs', name)
    begin
      dir = File.dirname(path)
      Dir.mkdir(dir) unless File.directory?(dir)
      File.open(path, 'w') do |f|
        lines.each { |l| f.puts(l) }
      end
    rescue StandardError
    end
  end
  # 追加一行到 mods/mod/logs/<name> (带时间戳), 供诊断 trace 使用
  def self.append(name, msg)
    path = File.join(__dir__, '..', 'logs', name)
    begin
      dir = File.dirname(path)
      Dir.mkdir(dir) unless File.directory?(dir)
      File.open(path, 'a') do |f|
        f.puts("[#{Time.now.strftime('%H:%M:%S.%L')}] #{msg}")
      end
    rescue StandardError
    end
  end
end
