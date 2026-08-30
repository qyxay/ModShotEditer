# ============================================================
#  skip_dialogue.rb — 跳过所有对话 mod
#
#  允许玩家直接跳过所有对话文字, 没有过程。
#  遇到 Show Text(101) 时跳过整段文字(含后续 401 行),
#  遇到 Show Choices(102) 时自动选择第一个选项。
#
#  纯 preload 实现, 不修改游戏原始文件。
#  用 TracePoint(:end) 监听 Interpreter 类定义, 在
#  execute_command 方法就绪后用 Module#prepend 打补丁。
#
#  配置: mods/mod/config.json
#    "skip_all_dialogue": true   → 开启跳过所有对话
#    "skip_all_dialogue": false  → 关闭(恢复原始对话)
# ============================================================

require 'json'

# --- 读取配置 (统一由 _config.rb 加载到 $mod_config) ---
default_config = { "skip_all_dialogue" => false }
config = default_config.merge($mod_config || {})

$skip_all_dialogue_enabled = config["skip_all_dialogue"] ? true : false

# --- 补丁模块 ---
module SkipAllDialoguePatch
  # 只跳过纯文字显示, 不跳过等待/按键/设置命令
  # (跳过 105/106 会导致事件时序混乱、音效反复触发甚至死循环)

  def execute_command
    if $skip_all_dialogue_enabled && @index < @list.size && @list[@index]
      code = @list[@index].code

      case code
      when 101
        # Show Text: 跳过当前命令和后续所有 401(文字数据行)
        @index += 1
        while @index < @list.size && @list[@index].code == 401
          @index += 1
        end
        return true

      when 401
        # 文字数据行(理论上 101 已批量跳过, 这里兜底)
        @index += 1
        return true

      when 102
        # Show Choices: 自动选择第一个选项
        # @branch[0] 存储选择索引, 后续 402(When [**])会据此判断分支
        @branch[0] = 0
        @index += 1
        return true
      end
    end

    super  # 调用原始 execute_command
  end
end

# --- 等待 Interpreter 类定义完成后 prepend 补丁 ---
trace = TracePoint.trace(:end) do |tp|
  begin
    if tp.self.is_a?(Class) && tp.self.name == 'Interpreter' &&
       tp.self.method_defined?(:execute_command)
      tp.self.prepend(SkipAllDialoguePatch)
      trace.disable
    end
  rescue
    # 忽略异常, 继续监听
  end
end

# --- 写状态文件 ---
status_path = File.join(__dir__, '..', 'skip_dialogue_status.txt')
File.open(status_path, 'w') do |f|
  f.puts "skip_all_dialogue_enabled = #{$skip_all_dialogue_enabled}"
  f.puts "config_source = \$mod_config (unified loader _config.rb)"
  f.puts "config = #{JSON.pretty_generate(config)}"
  f.puts "patch_method = TracePoint(:end) + Module#prepend (Interpreter#execute_command)"
  f.puts "skipped_commands = 101(ShowText)+401(text lines), 102(ShowChoices auto-select first)"
  f.puts "not_skipped = 103/104/105/106 (preserve event timing, avoid audio glitches and deadlocks)"
  f.puts "loaded_at = #{Time.now}"
end
