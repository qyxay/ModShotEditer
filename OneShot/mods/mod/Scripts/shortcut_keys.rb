# ============================================================
#  shortcut_keys.rb — 全局快捷键 (Ctrl+D / Ctrl+J)
#
#  Scene_Map 中的快捷键:
#    Ctrl+D → 打开开发者设置(需 config "is_developer": true)
#    Ctrl+J → 打开跳地图(需 config "is_developer": true)
#  基于 mkxp-z 扩展 Input.pressex?/triggerex?(SDL scancode 符号)。
#
#  事件/对话运行中可用性 (由 config 开关控制):
#    "always_settings": true → 任何事件/对话进行中都可 Ctrl+D
#    "always_travel":   true → 任何事件/对话进行中都可 Ctrl+J
#  界面打开后拦截 Scene_Map#update 的 super, 暂停游戏(事件/玩家/地图/
#  消息窗口), 只更新 dev_settings/jump_map 界面; 关闭后事件从暂停处继续。
#  转场/传送中(transition_processing / player_transferring)仍禁用, 避免
#  干扰 Graphics.freeze/transition 流程。
#
#  纯 preload 实现, 不修改游戏原始文件。
#  用 TracePoint(:end) 监听 Scene_Map 类定义, 在 update 就绪后
#  用 Module#prepend 打补丁。
#
#  依赖:
#    dev_settings.rb 提供 Window_DevSettings / $dev_settings_enabled / $dev_settings_instance
#    jump_map.rb 提供 Window_JumpMap (open_jump_map)
# ============================================================

# --- 读取 always_* 开关 (事件运行中是否放行对应快捷键) ---
$always_settings_enabled = ($mod_config && $mod_config["always_settings"]) ? true : false
$always_travel_enabled   = ($mod_config && $mod_config["always_travel"])   ? true : false

# ============================================================
#  实现要点:
#   * 监听点: Scene_Map#update 开头(prepend)。
#   * 界面打开时拦截: 若 dev_settings 可见(含 jump_map 子界面), 直接
#     ds.update + return, 不调用 super —— 事件解释器/玩家/地图/消息窗口
#     全部暂停, 避免事件在后台继续推进。关闭后 super 恢复执行, 事件续跑。
#   * 按键 API: mkxp-z 扩展 Input.pressex?/Input.triggerex? 接受 SDL scancode
#     符号(:LCTRL/:RCTRL/:D/:J)。若运行时无该扩展则回退 Input.press?(Input::CTRL),
#     Ctrl+D/J 将不可用(见状态文件记录的 API 探测)。
#   * 打开方式: 把 Window_DevSettings 实例挂到 @window_settings 的 dev_settings
#     槽位, 同时把设置窗口置可见; dev_settings 全屏不透明黑底盖住下层。
#   * 关闭: dev_settings 按 CANCEL → on_closed 回调恢复设置窗口(visible=false
#     并清槽位), 玩家回到游戏, 不残留设置界面。
#   * 兜底驱动: jump_map 界面可见但 dev_settings 不可见(异常残留状态)时,
#     直接驱动 jump_map, 避免界面冻结无响应(按 ESC/确认都无效)。
# ============================================================
module ShortcutKeysPatch
  def update
    begin
      ds = $dev_settings_instance
      if ds && ds.visible
        ds.update
        return
      end
      # 兜底: jump_map 可见但 dev_settings 不可见(异常残留状态)时直接驱动,
      # 保证界面始终响应输入(ESC/确认都能收回)
      if ds
        jm = ds.instance_variable_get(:@jump_map)
        if jm && jm.visible
          jm.update
          return
        end
      end
      shortcut_handle
    rescue StandardError
      # 快捷键异常不影响主流程
    end
    super
  end

  private

  def shortcut_handle
    # 开发者设置已打开(无论谁打开的): 输入由本 update 拦截接管, 不重复响应
    ds = $dev_settings_instance
    return if ds && ds.visible
    return unless shortcut_available?

    ctrl = ctrl_pressed?
    in_event = event_running?
    if ctrl && key_triggered?(:D) && $dev_settings_enabled
      # 事件/对话运行中需 always_settings 放行
      return if in_event && !$always_settings_enabled
      open_dev_settings_shortcut
    elsif ctrl && key_triggered?(:J) && $dev_settings_enabled
      # 事件/对话运行中需 always_travel 放行
      return if in_event && !$always_travel_enabled
      open_jump_map_shortcut
    end
  end

  # 基础可响应条件: 在地图上、非转场/传送中
  # (事件/对话运行中的放行由 always_settings/always_travel 在 shortcut_handle 中控制)
  def shortcut_available?
    return false unless $game_map && $game_player
    return false if $game_temp.transition_processing
    return false if $game_temp.player_transferring
    true
  end

  # 是否处于事件/对话运行中 (mi.running? 或任意消息窗口可见)
  def event_running?
    return true if $game_temp.message_window_showing
    return true if @message_window && @message_window.visible
    return true if @ed_message && @ed_message.visible
    mi = $game_system ? $game_system.map_interpreter : nil
    return true if mi && mi.running?
    false
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
    # 旧实例可能已被 on_transfer 销毁(jump map 跳转后), 检查 disposed? 后新建
    ds = $dev_settings_instance
    ds = nil if ds && ds.disposed?
    ds = $dev_settings_instance = Window_DevSettings.new unless ds
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
    # Ctrl+J 直接打开: 取消键一次全关回游戏(不先回 dev_settings 菜单)
    jm = $dev_settings_instance.instance_variable_get(:@jump_map)
    jm.close_all_on_cancel = true if jm
  end
end

# --- 等待 Scene_Map 类定义完成后 prepend 补丁 ---
PatchHelper.install('Scene_Map', methods: [:update]) do |k|
  k.prepend(ShortcutKeysPatch)
end

# --- 写状态文件 ---
StatusLog.write('shortcut_keys_status.txt', [
  "shortcut_keys loaded at = #{Time.now}",
  "shortcut_ctrl_d = #{$dev_settings_enabled} (open dev settings)",
  "shortcut_ctrl_j = #{$dev_settings_enabled} (open jump map, requires is_developer)",
  "always_settings = #{$always_settings_enabled} (allow Ctrl+D during events/dialogue)",
  "always_travel = #{$always_travel_enabled} (allow Ctrl+J during events/dialogue)",
  "event_pause = intercept super while dev_settings visible (pause interpreter/player/map)",
  "fallback_drive = jump_map visible but dev_settings hidden -> still driven (no frozen UI)",
  "input_api = pressex?#{Input.respond_to?(:pressex?)}, triggerex?#{Input.respond_to?(:triggerex?)}"
])
