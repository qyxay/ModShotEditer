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
#  配置: mods/mod/config.json (两个独立开关)
#    "skip_dialogue": true  → 开启跳过对话文字 (101 + 401)
#    "skip_dialogue": false → 关闭(恢复原始对话)
#    "skip_choice": true    → 开启自动选择第一个选项 (102)
#    "skip_choice": false   → 关闭(恢复原始选项)
# ============================================================

require 'json'

# --- 读取配置 (统一由 _config.rb 加载到 $mod_config) ---
# 两个独立开关:
#   skip_dialogue → 跳过对话文字 (命令 101/401)
#   skip_choice   → 跳过选项, 自动选第一个 (命令 102)
default_config = {
  "skip_dialogue" => false,
  "skip_choice"   => false
}
config = default_config.merge($mod_config || {})

$skip_dialogue_enabled = config["skip_dialogue"] ? true : false
$skip_choice_enabled   = config["skip_choice"]   ? true : false

# --- 补丁模块 ---
module SkipAllDialoguePatch
  # 只跳过纯文字显示, 不跳过等待/按键/设置命令
  # (跳过 105/106 会导致事件时序混乱、音效反复触发甚至死循环)

  def _trace_log(msg)
    begin
      File.open(File.join(__dir__, '..', 'logs', 'skip_trace.log'), 'a') do |f|
        f.puts "[#{Time.now.strftime('%H:%M:%S.%L')}] #{msg}"
      end
    rescue
    end
  end

  def execute_command
    if @index < @list.size && @list[@index]
      code = @list[@index].code

      case code
      when 101, 401
        # Show Text(101) + 文字数据行(401):
        # 仅当 skip_dialogue 开启时跳过整段文字
        if $skip_dialogue_enabled
          # 注意: Interpreter#update 在 execute_command 返回后统一 @index += 1
          # (mkxp-z 070_Interpreter_1.rb), 所以这里不能手动 @index += 1,
          # 否则会与 update 的 +1 叠加, 跳过对话后的下一条命令
          # (如关自开关 123 / 给物品 126 等), 破坏事件状态。
          # 这里只把 @index 移到"最后一个 401"(保持在该 401 上), 靠 update 的 +1
          # 自然越过整段文字。注意不能跳到"第一个非 401"—— 那样 update 的 +1
          # 会再越过一条。多行对话(101+401+401)必须走这条才能不丢后续命令。
          #
          # 另外: 101 被这里吞掉后, PictureSkipPatch 将看不到它来退出"跳过图片"
          # 模式, 会一路 command_end 提前截断含演出的事件 —— 这里代为清除。
          if defined?(@pic_skip_mode) && @pic_skip_mode
            @pic_skip_mode = false
            _trace_log("SKIP_DLG clear_pic ev=#{@event_id} idx=#{@index}")
          end
          text = (@list[@index].parameters[0].to_s rescue '').gsub("\n", ' ')
          _trace_log("SKIP_DLG c#{code} ev=#{@event_id} idx=#{@index} \"#{text[0, 18]}\"")
          @index += 1 while @index < @list.size - 1 && @list[@index + 1].code == 401
          return true
        end

      when 102
        # Show Choices: 仅当 skip_choice 开启时自动选择第一个选项
        if $skip_choice_enabled
          # @branch[0] 存储选择索引, 后续 402(When [**])会据此判断分支。
          # 同样不能手动 @index += 1(会与 update 的 +1 叠加多跳),
          # 只设置选择索引, 靠 update 的 +1 进入第一个 402。
          _trace_log("SKIP_CHOICE c102 ev=#{@event_id} idx=#{@index}")
          @branch[0] = 0
          return true
        end
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
status_path = File.join(__dir__, '..', 'logs', 'skip_dialogue_status.txt')
_log_dir = File.dirname(status_path)
Dir.mkdir(_log_dir) unless File.directory?(_log_dir)
File.open(status_path, 'w') do |f|
  f.puts "skip_dialogue_enabled = #{$skip_dialogue_enabled} (101/401 text lines)"
  f.puts "skip_choice_enabled   = #{$skip_choice_enabled}   (102 auto-select first option)"
  f.puts "config_source = \$mod_config (unified loader _config.rb)"
  f.puts "config = #{JSON.pretty_generate(config)}"
  f.puts "patch_method = TracePoint(:end) + Module#prepend (Interpreter#execute_command)"
  f.puts "skipped_commands = [skip_dialogue] 101(ShowText)+401(text lines), [skip_choice] 102(ShowChoices auto-select first)"
  f.puts "not_skipped = 103/104/105/106 (preserve event timing, avoid audio glitches and deadlocks)"
  f.puts "loaded_at = #{Time.now}"
end
