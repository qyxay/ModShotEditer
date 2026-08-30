# ============================================================
#  always_access.rb — 无论何时都可以传送/调设置
#
#  添加独立快捷键, 绕过菜单禁用、事件运行、玩家移动等限制:
#    F5 → 打开快速旅行 (Fast Travel)
#    F6 → 打开设置 (Settings)
#
#  纯 preload 实现, 不修改游戏原始文件。
#  用 TracePoint(:end) 监听 Scene_Map 类定义, 在
#  update 方法就绪后用 Module#prepend 打补丁。
#
#  配置: mods/mod/config.json
#    "always_travel": true   → F5 随时打开快速旅行
#    "always_settings": true → F6 随时打开设置
# ============================================================

require 'json'

# --- 读取配置 ---
config_path = File.join(__dir__, '..', 'config.json')
default_config = { "always_travel" => true, "always_settings" => true }

config = if File.exist?(config_path)
  begin
    parsed = JSON.parse(File.read(config_path))
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end
else
  {}
end
config = default_config.merge(config)

$always_travel_enabled = config["always_travel"] ? true : false
$always_settings_enabled = config["always_settings"] ? true : false

# --- 补丁模块 ---
module AlwaysAccessPatch
  def update
    if $always_travel_enabled || $always_settings_enabled
      # F5 → 快速旅行 (绕过 $game_player.moving? 和菜单限制)
      if $always_travel_enabled && Input.trigger?(Input::F5)
        if @fast_travel.visible
          # 已打开则关闭
          @fast_travel.close
        else
          # 关闭其他菜单窗口, 避免重叠
          @menu.close if @menu.visible
          @item_menu.close if @item_menu.visible
          @window_settings.close if @window_settings.visible
          $game_temp.menu_calling = false
          $game_temp.item_menu_calling = false
          $game_temp.window_settings_calling = false
          # 直接调用, 绕过 unless $game_player.moving? 限制
          call_travel_menu
        end
      end

      # F6 → 设置 (绕过所有限制)
      if $always_settings_enabled && Input.trigger?(Input::F6)
        if @window_settings.visible
          # 已打开则关闭
          @window_settings.close
        else
          # 关闭其他菜单窗口, 避免重叠
          @menu.close if @menu.visible
          @item_menu.close if @item_menu.visible
          @fast_travel.close if @fast_travel.visible
          $game_temp.menu_calling = false
          $game_temp.item_menu_calling = false
          $game_temp.travel_menu_calling = false
          # 直接调用, 绕过 unless $game_player.moving? 限制
          call_window_settings
        end
      end
    end

    super  # 调用原始 update
  end
end

# --- 补丁: Game_FastTravel#enabled? 始终返回 true ---
# 主菜单选择快速旅行时检查 $game_fasttravel.enabled?,
# 剧情中会被设为 false 导致显示 "You cannot fast travel right now."
module AlwaysAccessFastTravelPatch
  def enabled?
    if $always_travel_enabled
      true
    else
      super
    end
  end
end

# --- 补丁: Game_FastTravel#unlocked_maps 返回 nil 时兜底为空 hash ---
# FastTravel.open 第43行调用 unlocked_maps.keys.sort,
# 当 zone 未设置或无解锁地图时返回 nil, 导致 NoMethodError 崩溃
module AlwaysAccessFastTravelNilPatch
  def unlocked_maps
    result = super
    result || {}
  end
end

# --- 补丁: Window_MainMenu#update 过场中也能选择 ---
# 原始代码: if !self.active || $game_system.map_interpreter.running? then return
# 过场中菜单打开了但无法选择, 这里临时让 running? 返回 false
module AlwaysAccessMainMenuPatch
  def update
    if ($always_travel_enabled || $always_settings_enabled) && self.active
      mi = $game_system.map_interpreter
      if mi && mi.running?
        begin
          mi.singleton_class.alias_method(:aa_orig_running?, :running?)
          mi.define_singleton_method(:running?) { false }
          return super
        ensure
          mi.singleton_class.alias_method(:running?, :aa_orig_running?)
        end
      end
    end
    super
  end
end

# --- 补丁: FastTravel#open 无可用 zone 时显示提示而非崩溃 ---
# FastTravel.open 第52行 zone = ZONES[$game_fasttravel.zone],
# 当 zone 为 nil 时第56行 zone.name 崩溃, 第65行 zone.maps[item] 也崩溃
module AlwaysAccessFastTravelOpenPatch
  def open
    zone_key = $game_fasttravel.zone
    if zone_key.nil? || !defined?(ZONES) || ZONES[zone_key].nil?
      # 没有可用的区域, 显示提示而非崩溃
      if defined?($game_temp) && $game_temp
        $game_temp.message_ed_text = "No fast travel points available yet."
      end
      return
    end
    super
  end
end

# --- 等待各类定义完成后 prepend 补丁 ---
trace = TracePoint.trace(:end) do |tp|
  begin
    if tp.self.is_a?(Class)
      case tp.self.name
      when 'Scene_Map'
        if tp.self.method_defined?(:update)
          tp.self.prepend(AlwaysAccessPatch)
        end
      when 'Game_FastTravel'
        if tp.self.method_defined?(:enabled?)
          tp.self.prepend(AlwaysAccessFastTravelPatch)
        end
        if tp.self.method_defined?(:unlocked_maps)
          tp.self.prepend(AlwaysAccessFastTravelNilPatch)
        end
      when 'Window_MainMenu'
        if tp.self.method_defined?(:update)
          tp.self.prepend(AlwaysAccessMainMenuPatch)
        end
      when 'FastTravel'
        if tp.self.method_defined?(:open)
          tp.self.prepend(AlwaysAccessFastTravelOpenPatch)
        end
      end
      # 五个补丁都加载后停止监听
      if Scene_Map.ancestors.include?(AlwaysAccessPatch) &&
         Game_FastTravel.ancestors.include?(AlwaysAccessFastTravelPatch) &&
         Game_FastTravel.ancestors.include?(AlwaysAccessFastTravelNilPatch) &&
         Window_MainMenu.ancestors.include?(AlwaysAccessMainMenuPatch) &&
         FastTravel.ancestors.include?(AlwaysAccessFastTravelOpenPatch)
        trace.disable
      end
    end
  rescue
    # 忽略异常, 继续监听
  end
end

# --- 写状态文件 ---
status_path = File.join(__dir__, '..', 'always_access_status.txt')
File.open(status_path, 'w') do |f|
  f.puts "always_travel_enabled = #{$always_travel_enabled}"
  f.puts "always_settings_enabled = #{$always_settings_enabled}"
  f.puts "config_path = #{config_path}"
  f.puts "config = #{JSON.pretty_generate(config)}"
  f.puts "patch_method = TracePoint(:end) + Module#prepend (Scene_Map#update, Game_FastTravel#enabled?/#unlocked_maps, Window_MainMenu#update, FastTravel#open)"
  f.puts "hotkeys = F5 (Fast Travel), F6 (Settings)"
  f.puts "bypassed = menu_disabled, map_interpreter.running? (menu input + F-keys), $game_player.moving?, $game_fasttravel.enabled?"
  f.puts "nil_safety = Game_FastTravel#unlocked_maps returns {} instead of nil (prevents FastTravel.rb:43 crash)"
  f.puts "zone_safety = FastTravel#open shows message instead of crashing when zone is nil (prevents FastTravel.rb:56/65 crash)"
  f.puts "main_menu_fixes = fast travel always selectable, menu items selectable during cutscenes"
  f.puts "loaded_at = #{Time.now}"
end
