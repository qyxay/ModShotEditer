# ============================================================
#  picture_skip.rb — 图片过场跳过 mod
#
#  纯 preload 实现, 不修改游戏原始 xScripts.rxdata。
#  用 TracePoint(:end) 监听 Interpreter 类定义, 在
#  execute_command 方法就绪后用 Module#prepend 打补丁。
#
#  配置: mods/mod/config.json
#    "skip_pictures": true   → 开启跳过
#    "skip_pictures": false  → 关闭(恢复原始游戏)
# ============================================================

# 注意: mkxp-z 运行时没有 json 库, 用正则手动解析简单 JSON

# --- 读取配置 ---
config_path = File.join(__dir__, '..', 'config.json')
config = { "skip_pictures" => true }  # 默认值

if File.exist?(config_path)
  begin
    content = File.read(config_path)
    # 解析 "skip_pictures": true / false
    if content =~ /"skip_pictures"\s*:\s*(true|false)/
      config["skip_pictures"] = ($1 == "true")
    end
  rescue
    # 读取失败时保持默认值
  end
end

$pic_skip_enabled = config["skip_pictures"] ? true : false

# --- 补丁模块 ---
module PictureSkipPatch
  # 需要跳过的命令码:
  #   105 等待, 106 按键输入
  #   207-215 图片显示/移动/变色/透明/删除
  #   221-225 背景设置/过渡
  #   232-236 图片操作(色调/旋转/缩放等)
  #   241 播放 BGM
  SKIP_CODES = [105, 106,
                207, 208, 209, 210, 211, 212, 213, 214, 215,
                221, 222, 223, 224, 225,
                232, 233, 234, 235, 236,
                241].freeze

  def clear
    super
    @pic_skip_mode = false
  end

  def execute_command
    if $pic_skip_enabled
      # 遇到 ShowPicture(231) 进入跳过模式
      if @index < @list.size && @list[@index] && @list[@index].code == 231
        @pic_skip_mode = true
        @index += 1
        return true
      end

      # 跳过模式中
      if @pic_skip_mode
        # 列表末尾: 结束事件
        if @index >= @list.size - 1
          @pic_skip_mode = false
          command_end
          return true
        end

        code = @list[@index].code

        if code == 101
          # 遇到对话(ShowText): 退出跳过模式, 正常执行
          @pic_skip_mode = false
        elsif SKIP_CODES.include?(code)
          # 跳过等待/按键/图片操作/BGM/转场
          @index += 1
          return true
        end
        # 其他命令(条件分支/开关/传送/脚本等)正常执行, 不清除跳过模式
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
      tp.self.prepend(PictureSkipPatch)
      trace.disable
    end
  rescue
    # 忽略异常, 继续监听
  end
end

# --- 写状态文件 ---
status_path = File.join(__dir__, '..', 'skip_pictures_status.txt')
File.open(status_path, 'w') do |f|
  f.puts "pic_skip_enabled = #{$pic_skip_enabled}"
  f.puts "config_path = #{config_path}"
  f.puts 'config = {"skip_pictures": '"#{config["skip_pictures"]}"'}'
  f.puts "patch_method = TracePoint(:end) + Module#prepend (no xScripts.rxdata modification)"
  f.puts "loaded_at = #{Time.now}"
end
