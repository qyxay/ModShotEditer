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
  "skip_choice"   => false,
  "skip_uneasy"   => false
}
config = default_config.merge($mod_config || {})

$skip_dialogue_enabled = config["skip_dialogue"] ? true : false
$skip_choice_enabled   = config["skip_choice"]   ? true : false
$skip_uneasy_enabled   = config["skip_uneasy"]   ? true : false

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

  # "Niko feels uneasy." 消息检测: 当前 101 后续的 401 文本命中即视为该句
  def uneasy_line?(list, idx)
    i = idx + 1
    while i < list.size && list[i].code == 401
      return true if list[i].parameters[0].to_s =~ /Niko feels uneasy/i
      i += 1
    end
    false
  end

  def execute_command
    if @index < @list.size && @list[@index]
      code = @list[@index].code

      case code
      when 101, 401
        # "Niko feels uneasy." 特别跳过(独立开关 skip_uneasy, 仅 ED 读档提示这一句):
        # 命中则只跳过这一句消息, 不影响其他对话
        if code == 101 && $skip_uneasy_enabled && uneasy_line?(@list, @index)
          if defined?(@pic_skip_mode) && @pic_skip_mode
            @pic_skip_mode = false
            _trace_log("SKIP_UNEASY clear_pic ev=#{@event_id} idx=#{@index}")
          end
          _trace_log("SKIP_UNEASY c101 ev=#{@event_id} idx=#{@index}")
          @index += 1 while @index < @list.size - 1 && @list[@index + 1].code == 401
          return true
        end
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
PatchHelper.install('Interpreter', methods: [:execute_command]) do |k|
  k.prepend(SkipAllDialoguePatch)
end

# --- 写状态文件 ---
StatusLog.write('skip_dialogue_status.txt', [
  "skip_dialogue_enabled = #{$skip_dialogue_enabled} (101/401 text lines)",
  "skip_choice_enabled   = #{$skip_choice_enabled}   (102 auto-select first option)",
  "config_source = \$mod_config (unified loader _config.rb)",
  "config = #{JSON.pretty_generate(config)}",
  "patch_method = PatchHelper.install (Interpreter#execute_command)",
  "skipped_commands = [skip_dialogue] 101(ShowText)+401(text lines), [skip_choice] 102(ShowChoices auto-select first)",
  "not_skipped = 103/104/105/106 (preserve event timing, avoid audio glitches and deadlocks)",
  "skip_uneasy_enabled = #{$skip_uneasy_enabled} (only skips the \"Niko feels uneasy.\" load-screen line)",
  "loaded_at = #{Time.now}"
])
