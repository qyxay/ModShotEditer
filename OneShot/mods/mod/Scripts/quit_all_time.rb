# ============================================================
#  quit_all_time.rb — 随时退出 mod
#
#  取消 OneShot 中"部分情况下无法退出/打开菜单"的限制。
#  原始游戏在图片过场等场景中会设置 menu_disabled=true 或
#  事件运行中禁止打开菜单。本 mod 忽略这两个限制, 让玩家
#  随时按菜单键打开菜单退出。
#
#  纯 preload 实现, 不修改游戏原始文件。
#  用 TracePoint(:end) 监听 Scene_Map 类定义, 在 update
#  方法就绪后用 Module#prepend 打补丁。
#
#  配置: mods/mod/config.json
#    "quit_all_time": true   → 开启随时退出
#    "quit_all_time": false  → 关闭(恢复原始限制)
# ============================================================

require 'json'

# --- 读取配置 (统一由 _config.rb 加载到 $mod_config) ---
default_config = { "quit_all_time" => true }
config = default_config.merge($mod_config || {})

$quit_all_time_enabled = config["quit_all_time"] ? true : false

# --- 覆盖 Oneshot.allow_exit ---
# Oneshot.allow_exit(true/false) 是引擎提供的 C 方法, 控制窗口右上角 X
# 按钮是否能关闭游戏。过场中游戏会调用 allow_exit(false) 禁止关闭。
# 这里覆盖该方法, 当 quit_all_time 开启时始终传入 true, 允许随时关闭。
if defined?(Oneshot) && Oneshot.respond_to?(:allow_exit)
  Oneshot.singleton_class.alias_method(:qat_orig_allow_exit, :allow_exit)
  Oneshot.define_singleton_method(:allow_exit) do |arg|
    if $quit_all_time_enabled
      Oneshot.qat_orig_allow_exit(true)
    else
      Oneshot.qat_orig_allow_exit(arg)
    end
  end
end

# --- 补丁模块 ---
module QuitAllTimePatch
  def update
    if $quit_all_time_enabled
      # 处理退出键: 忽略 map_interpreter.running? 限制
      # 原始代码在过场中按退出键会弹出 "You cannot perform this action during cutscenes."
      # 这里设置公共事件 35 (保存并退出), 然后临时让 Input.quit? 返回 false,
      # 调用 super 处理公共事件, 同时避免 super 中的限制提示。
      if Input.quit?
        $game_temp.common_event_id = 35
        begin
          # 临时覆盖 Input.quit? 返回 false, 阻止 super 中的限制检查
          Input.singleton_class.alias_method(:qat_orig_quit?, :quit?)
          Input.define_singleton_method(:quit?) { false }
          return super
        ensure
          # 恢复原始方法 (即使 super 抛异常也会执行)
          Input.singleton_class.alias_method(:quit?, :qat_orig_quit?)
        end
      end

      # 检查消息窗口是否显示 (对话中不拦截菜单键, ESC 用于推进对话)
      message_showing = $game_temp.message_window_showing ||
                        @ed_message.visible || @doc_message.visible ||
                        @desktop_message.visible || @credits_message.visible

      # 忽略 $game_system.menu_disabled 和 map_interpreter.running?
      # 保留其他限制: 消息窗口、快速旅行、设置窗口、菜单调用中
      unless message_showing ||
             @fast_travel.visible || @window_settings.visible ||
             $game_temp.menu_calling == true ||
             $game_temp.item_menu_calling == true
        if !@menu.visible && Input.trigger?(Input::MENU)
          $game_temp.menu_calling = true
          $game_temp.menu_beep = true
        end
      end
    end

    super  # 调用原始 update
  end
end

# --- 等待 Scene_Map 类定义完成后 prepend 补丁 ---
trace = TracePoint.trace(:end) do |tp|
  begin
    if tp.self.is_a?(Class) && tp.self.name == 'Scene_Map' &&
       tp.self.method_defined?(:update)
      tp.self.prepend(QuitAllTimePatch)
      trace.disable
    end
  rescue
    # 忽略异常, 继续监听
  end
end

# --- 写状态文件 ---
status_path = File.join(__dir__, '..', 'logs', 'quit_all_time_status.txt')
File.open(status_path, 'w') do |f|
  f.puts "quit_all_time_enabled = #{$quit_all_time_enabled}"
  f.puts "config_source = \$mod_config (unified loader _config.rb)"
  f.puts "config = #{JSON.pretty_generate(config)}"
  f.puts "patch_method = TracePoint(:end) + Module#prepend (Scene_Map#update)"
  f.puts "bypassed_restrictions = menu_disabled, map_interpreter.running? (menu key + quit key), Oneshot.allow_exit (window X button)"
  f.puts "removed_message = You cannot perform this action during cutscenes."
  f.puts "overridden_methods = Oneshot.allow_exit (always true when enabled)"
  f.puts "preserved_restrictions = message_window, fast_travel, settings, menu_calling"
  f.puts "loaded_at = #{Time.now}"
end
