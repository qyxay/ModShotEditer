# ============================================================
#  shortcut_keys.rb — 全局快捷键 (Ctrl+D / Ctrl+J)
#
#  Scene_Map 中的快捷键:
#    Ctrl+D → 打开开发者设置(需 config "is_developer": true)
#    Ctrl+J → 打开跳地图
#  基于 mkxp-z 扩展 Input.pressex?/triggerex?(SDL scancode 符号)。
#
#  纯 preload 实现, 不修改游戏原始文件。
#  用 TracePoint(:end) 监听 Scene_Map 类定义, 在 update 就绪后
#  用 Module#prepend 打补丁。
#
#  依赖:
#    dev_settings.rb 提供 Window_DevSettings / $dev_settings_enabled / $dev_settings_instance
#    jump_map.rb 提供 Window_JumpMap (open_jump_map)
# ============================================================

# ============================================================
#  实现要点:
#   * 监听点: Scene_Map#update 开头(prepend)。仅在地图场景、非对话/转场/
#     事件运行中响应, 避免打断剧情。
#   * 按键 API: mkxp-z 扩展 Input.pressex?/Input.triggerex? 接受 SDL scancode
#     符号(:LCTRL/:RCTRL/:D/:J)。若运行时无该扩展则回退 Input.press?(Input::CTRL),
#     Ctrl+D/J 将不可用(见状态文件记录的 API 探测)。
#   * 打开方式: 把 Window_DevSettings 实例挂到 @window_settings 的 dev_settings
#     槽位, 由 WindowSettingsDevPatch#update 统一接管输入并 return; 同时把设置
#     窗口置可见, 复用 Scene_Map 原逻辑(屏蔽菜单打开 + 玩家停止移动)。
#     dev_settings 全屏不透明黑底盖住下层, 视觉上就是直接进入开发者设置。
#   * 关闭: dev_settings 按 CANCEL → on_closed 回调恢复设置窗口(visible=false
#     并清槽位), 玩家回到游戏, 不残留设置界面。
# ============================================================
module ShortcutKeysPatch
  def update
    begin
      shortcut_handle
    rescue StandardError
      # 快捷键异常不影响主流程
    end
    super
  end

  private

  def shortcut_handle
    # 开发者设置已打开(无论谁打开的): 输入由 WindowSettingsDevPatch 接管, 不重复响应
    ds = $dev_settings_instance
    return if ds && ds.visible
    return unless shortcut_available?

    ctrl = ctrl_pressed?
    if ctrl && key_triggered?(:D) && $dev_settings_enabled
      open_dev_settings_shortcut
    elsif ctrl && key_triggered?(:J)
      open_jump_map_shortcut
    end
  end

  # 快捷键可响应条件: 在地图上、非对话/转场/事件运行中
  def shortcut_available?
    return false unless $game_map && $game_player
    return false if $game_temp.message_window_showing
    return false if $game_temp.transition_processing
    return false if $game_temp.player_transferring
    if @message_window && @message_window.visible
      return false
    end
    if @ed_message && @ed_message.visible
      return false
    end
    mi = $game_system ? $game_system.map_interpreter : nil
    return false if mi && mi.running?
    true
  end

  # Ctrl 按住检测: 优先 mkxp-z 扩展, 回退标准 API
  def ctrl_pressed?
    if Input.respond_to?(:pressex?)
      begin
        return true if Input.pressex?(:LCTRL) || Input.pressex?(:RCTRL)
      rescue StandardError
      end
    end
    begin
      Input.press?(Input::CTRL)
    rescue StandardError
      false
    end
  end

  # 字母键按下检测(SDL scancode 符号, 如 :D / :J)
  def key_triggered?(sym)
    return false unless Input.respond_to?(:triggerex?)
    begin
      Input.triggerex?(sym)
    rescue StandardError
      false
    end
  end

  def open_dev_settings_shortcut
    ds = $dev_settings_instance ||= Window_DevSettings.new
    ds.parent_settings = @window_settings
    # 关闭时恢复被借用的设置窗口(visible + 槽位), 避免残留设置界面
    ds.on_closed = proc {
      @window_settings.visible = false
      @window_settings.instance_variable_set(:@dev_settings, nil)
    }
    # 设置窗口未初始化时先 open 一次(初始化 sprite/数据); 已打开则保持原状态
    @window_settings.open unless @window_settings.visible
    # 挂到设置窗口的 dev_settings 槽位: WindowSettingsDevPatch#update 检测到
    # ds.visible 后接管输入并 return, 设置窗口自身不响应输入
    @window_settings.instance_variable_set(:@dev_settings, ds)
    # 设置窗口置可见: 复用 Scene_Map 的"菜单屏蔽 + 玩家停止"逻辑(dev_settings 全屏盖住)
    @window_settings.visible = true
    ds.open
  end

  def open_jump_map_shortcut
    open_dev_settings_shortcut
    $dev_settings_instance.open_jump_map
  end
end

# --- 等待 Scene_Map 类定义完成后 prepend 快捷键补丁 ---
_trace_scene = TracePoint.trace(:end) do |tp|
  begin
    if tp.self.is_a?(Class) && tp.self.name == 'Scene_Map' &&
       tp.self.method_defined?(:update)
      tp.self.prepend(ShortcutKeysPatch)
      _trace_scene.disable
    end
  rescue StandardError
    # 忽略异常, 继续监听
  end
end

# --- 写状态文件 ---
status_path = File.join(__dir__, '..', 'logs', 'shortcut_keys_status.txt')
begin
  _log_dir = File.dirname(status_path)
  Dir.mkdir(_log_dir) unless File.directory?(_log_dir)
  File.open(status_path, 'w') do |f|
    f.puts "shortcut_keys loaded at = #{Time.now}"
    f.puts "shortcut_ctrl_d = #{$dev_settings_enabled} (open dev settings)"
    f.puts "shortcut_ctrl_j = true (open jump map)"
    f.puts "input_api = pressex?#{Input.respond_to?(:pressex?)}, triggerex?#{Input.respond_to?(:triggerex?)}"
  end
rescue StandardError
end
