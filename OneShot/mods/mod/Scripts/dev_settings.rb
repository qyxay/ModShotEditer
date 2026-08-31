# ============================================================
#  dev_settings.rb — 设置页"开发者设置"栏 mod
#
#  在游戏设置窗口(Window_Settings)最下方追加一栏"开发者设置"。
#  进入后列出 config.json 中的所有布尔开关, 可在游戏内实时
#  切换并写回 config.json, 同时同步对应 mod 的全局开关变量
#  (实现不重启即生效)。
#
#  纯 preload 实现, 不修改游戏原始文件。
#  用 TracePoint(:end) 监听 Window_Settings 类定义, 在
#  open/update/dispose 就绪后用 Module#prepend 打补丁。
#
#  配置: mods/mod/config.json
#    "is_developer": true  → 设置页显示"开发者设置"栏
#    "is_developer": false → 隐藏该栏
# ============================================================

require 'json'

# --- 读取配置 (统一由 _config.rb 加载到 $mod_config) ---
default_config = { "is_developer" => false }
config = default_config.merge($mod_config || {})

$dev_settings_enabled = config["is_developer"] ? true : false

# config.json 路径: Scripts/../config.json
CONFIG_PATH = File.join(__dir__, '..', 'config.json')

# config.json 键 → mod 全局开关变量 映射(白名单, 用于实时同步)
# always_travel / always_settings 暂无对应脚本消费, 仅写回文件
GLOBAL_SYNC = {
  'skip_pictures' => '$is_skip_picture',
  'quit_all_time' => '$quit_all_time_enabled',
  'skip_dialogue' => '$skip_dialogue_enabled',
  'skip_choice'   => '$skip_choice_enabled',
  'unshow_title'  => '$unshow_title_enabled',
  'is_developer'  => '$dev_settings_enabled'
}

# --- 开发者设置子界面 ---
class Window_DevSettings
  MARGIN = 30
  TITLE_TOP_MARGIN = 32
  TITLE_MARGIN = 100
  ITEM_SPACING = 28
  VALUE_MARGIN = 270
  ACTIVE_MARGIN = MARGIN * 2 + 20

  def initialize
    @viewport = Viewport.new(0, 0, 640, 480)
    @bg = Sprite.new(@viewport)
    @bg.bitmap = Bitmap.new(640, 480)
    # 不透明背景, 完全遮住下层设置窗口的文字, 保证可读性
    @bg.bitmap.fill_rect(0, 0, 640, 480, Color.new(0, 0, 0, 255))
    @title = Sprite.new(@viewport)
    @title.bitmap = Bitmap.new(320, TITLE_MARGIN)
    @title.bitmap.font.size = 40
    @title.y = TITLE_TOP_MARGIN
    @title.x = MARGIN
    # 动作执行后的短暂提示
    @flash_sprite = Sprite.new(@viewport)
    @flash_sprite.bitmap = Bitmap.new(400, 24)
    @flash_sprite.y = 452
    @flash_sprite.x = MARGIN
    @flash_sprite.visible = false
    @flash_timer = 0
    @viewport.z = 9999
    @data_sprites = []
    @index = 0
    @visible = false
    @config = {}
    @keys = []
    # 功能动作条目(追加在布尔开关之后), 按确认键执行对应动作
    @extra_items = ['Jump Map', 'Unlock All Doors', 'Complete All Dialogues', 'Complete All Story']
    @jump_map = nil
    # 外层 Window_Settings 引用(由补丁注入), 用于跳转后一并关闭
    @parent_settings = nil
  end

  # 完整显示列表 = 布尔开关 + 固定功能条目
  def display_items
    @keys + @extra_items
  end

  attr_accessor :parent_settings

  def visible
    @visible
  end

  def visible=(val)
    @viewport.visible = val
    @visible = val
  end

  def open
    reload_config
    return if display_items.empty?
    @index = 0
    @flash_timer = 0
    @flash_sprite.visible = false
    # 必须先置可见, 否则 open 内的 redraw 会因 @visible == false 而跳过绘制
    self.visible = true
    # 标题
    @title.bitmap.clear
    @title.bitmap.draw_text(0, 0, @title.bitmap.width, @title.bitmap.height, tr('Developer Settings'))
    # 清掉旧 sprite
    @data_sprites.each { |spr| spr.dispose }
    @data_sprites = []
    display_items.each_with_index do |key, i|
      spr = Sprite.new(@viewport)
      spr.bitmap = Bitmap.new(400, ITEM_SPACING)
      spr.x = MARGIN
      spr.y = TITLE_MARGIN + TITLE_TOP_MARGIN + ITEM_SPACING * i
      spr.opacity = 0
      redraw(spr, i)
      @data_sprites << spr
    end
  end

  def reload_config
    @config = begin
      JSON.parse(File.read(CONFIG_PATH))
    rescue StandardError
      $mod_config || {}
    end
    @keys = @config.keys.select { |k| @config[k] == true || @config[k] == false }
  end

  def redraw(spr, i)
    return if @visible == false
    item = display_items[i]
    spr.bitmap.clear
    spr.bitmap.draw_text(0, 0, spr.bitmap.width, spr.bitmap.height, tr(item))
    if i < @keys.size
      # 布尔开关: 显示 ON/OFF
      val = @config[item]
      spr.bitmap.draw_text(VALUE_MARGIN, 0, spr.bitmap.width, spr.bitmap.height,
                           val ? tr('ON') : tr('OFF'))
    else
      # 功能条目: 显示进入箭头
      spr.bitmap.draw_text(VALUE_MARGIN, 0, spr.bitmap.width, spr.bitmap.height, '>')
    end
  end

  def redraw_all
    @data_sprites.each_with_index { |spr, i| redraw(spr, i) }
  end

  def update
    return if !@visible || display_items.empty?
    # 子界面(跳地图)优先: 完全接管输入, 返回后恢复开发者设置
    if @jump_map && @jump_map.visible
      @jump_map.update
      return
    end
    # 光标动画(与 Window_Settings 视觉一致)
    @data_sprites.each_with_index do |spr, i|
      if i == @index
        if spr.x < ACTIVE_MARGIN
          spr.x += 6
          spr.x = ACTIVE_MARGIN if spr.x > ACTIVE_MARGIN
        end
        spr.opacity += 10 if spr.opacity < 255
      else
        if spr.x > MARGIN * 2
          spr.x -= 6
          spr.x = MARGIN * 2 if spr.x < MARGIN * 2
        end
        spr.opacity -= 10 if spr.opacity > 128
        spr.opacity = 128 if spr.opacity < 128
      end
    end

    if Input.trigger?(Input::UP)
      @index = (@index - 1) % display_items.size
      $game_system.se_play($data_system.cursor_se)
    end
    if Input.trigger?(Input::DOWN)
      @index = (@index + 1) % display_items.size
      $game_system.se_play($data_system.cursor_se)
    end

    # 确认键: 布尔开关直接切换; 功能条目执行对应动作
    if Input.trigger?(Input::ACTION)
      if @index >= @keys.size
        $game_system.se_play($data_system.decision_se)
        run_action(@extra_items[@index - @keys.size])
      else
        toggle(@index)
      end
    end
    # 左右键: 仅对布尔开关生效, 功能条目忽略
    if Input.trigger?(Input::LEFT) || Input.trigger?(Input::RIGHT)
      toggle(@index) if @index < @keys.size
    end

    if Input.trigger?(Input::CANCEL)
      $game_system.se_play($data_system.cancel_se)
      self.visible = false
    end

    # 动作反馈提示的显示计时
    if @flash_timer > 0
      @flash_timer -= 1
      @flash_sprite.visible = true if @flash_timer > 0
      @flash_sprite.visible = false if @flash_timer == 0
    end
  end

  # 执行功能动作
  def run_action(action)
    case action
    when 'Jump Map'
      open_jump_map
    when 'Unlock All Doors'
      unlock_all_doors
    when 'Complete All Dialogues'
      complete_all_dialogues
    when 'Complete All Story'
      complete_all_story
    end
  end

  # 短暂显示动作结果提示
  def flash(msg)
    @flash_sprite.bitmap.clear
    @flash_sprite.bitmap.draw_text(0, 0, @flash_sprite.bitmap.width, @flash_sprite.bitmap.height, tr(msg))
    @flash_sprite.visible = true
    @flash_timer = 120
  end

  # --- 解锁全部的门 ---
  # OneShot 的门锁由事件条件分支的开关控制(扫描确定的高频门锁开关)。
  # 全部设为 true, 并刷新当前地图事件让门页面立即切换。
  DOOR_SWITCHES = [8, 50, 112, 178, 32, 16, 152, 284, 59, 36, 122, 245,
                   66, 28, 71, 290, 187, 35, 34, 208, 216, 83, 42, 31,
                   240, 304, 305, 7, 103]
  def unlock_all_doors
    if !$game_switches
      flash('Not in game')
      return
    end
    count = set_door_switches
    flash("#{count} door switches ON")
  end

  # 设置全部门锁开关(供 unlock_all_doors / complete_all_story 复用)
  def set_door_switches
    count = 0
    DOOR_SWITCHES.each do |s|
      $game_switches[s] = true
      count += 1
    end
    if $game_map && $game_map.events
      $game_map.events.each_value { |e| e.refresh }
    end
    count
  end

  # --- 完成所有对话(当前地图) ---
  # 把当前地图所有含对话(Show Text 101)事件的自开关 A-D 置 true,
  # 使其跳到"已完成"页; 不实际运行事件, 无副作用。配合 Jump Map 逐图使用。
  def complete_all_dialogues
    if !$game_map || !$game_map.events
      flash('Not in game')
      return
    end
    count = 0
    $game_map.events.each_value do |ev|
      next unless ev && ev.list
      has_text = ev.list.any? { |c| c && c.code == 101 }
      next unless has_text
      %w[A B C D].each do |s|
        $game_self_switches[[$game_map.map_id, ev.id, s]] = true
      end
      count += 1
    end
    $game_map.events.each_value { |e| e.refresh }
    flash("#{count} dialogues done (this map)")
  end

  # --- 完成所有剧情(当前地图) ---
  # 把当前地图所有事件(除玩家)的自开关 A-D 置 true, 让全部剧情/事件
  # 跳到"已发生"状态; 同时解锁全部门锁。配合 Jump Map 逐图使用。
  def complete_all_story
    if !$game_map || !$game_map.events
      flash('Not in game')
      return
    end
    count = 0
    $game_map.events.each_value do |ev|
      next unless ev
      %w[A B C D].each do |s|
        $game_self_switches[[$game_map.map_id, ev.id, s]] = true
      end
      count += 1
    end
    $game_map.events.each_value { |e| e.refresh }
    # 一并解锁全部门锁(全局生效)
    set_door_switches if $game_switches
    flash("#{count} events done (this map)")
  end

  # 切换当前布尔开关并写回
  def toggle(i)
    key = @keys[i]
    @config[key] = !@config[key]
    apply_global(key, @config[key])
    $mod_config[key] = @config[key] if $mod_config
    save_config
    $game_system.se_play($data_system.decision_se)
    redraw_all
  end

  # 进入跳地图子界面
  # 注意: 不能隐藏自身(visible=false), 否则 Window_Settings 的补丁
  # 只在 @dev_settings.visible 为 true 时才调用其 update, 界面会冻结。
  # 靠 JumpMap 更高的 viewport z(10000) 盖住本界面, 视觉等效。
  def open_jump_map
    @jump_map ||= Window_JumpMap.new
    @jump_map.on_transfer = proc {
      # 跳转成功: 关闭跳地图、开发者设置、外层设置窗口
      @jump_map.visible = false
      self.visible = false
      @parent_settings.visible = false if @parent_settings
    }
    @jump_map.open
  end

  def dispose
    @jump_map.dispose if @jump_map
    @data_sprites.each { |spr| spr.dispose }
    @flash_sprite.dispose
    @title.dispose
    @bg.dispose
    @viewport.dispose
  end

  private

  # 同步对应 mod 的全局开关变量, 实现不重启即生效(白名单, 无注入风险)
  def apply_global(key, val)
    var = GLOBAL_SYNC[key]
    eval("#{var} = #{val}") if var
  end

  # 写回 config.json, 已知键保持固定顺序, 未知键追加在尾部
  def save_config
    $mod_config ||= @config
    ordered = {}
    %w[skip_pictures quit_all_time skip_dialogue skip_choice always_travel always_settings unshow_title is_developer].each do |k|
      ordered[k] = @config[k] if @config.key?(k)
    end
    @config.each do |k, v|
      ordered[k] = v unless ordered.key?(k)
    end
    File.write(CONFIG_PATH, JSON.pretty_generate(ordered) + "\n")
  end
end

# --- 给 Window_Settings 打补丁 ---
module WindowSettingsDevPatch
  def open
    # 关键修复: 原版 open 每次新建 sprite 到 @data_sprites 且不清旧,
    # 反复进出设置页会残留堆积。这里在调用原版前先 dispose 清空,
    # 保证每次 open 都是干净的一层。
    if @data_sprites
      @data_sprites.each { |spr| spr.dispose if spr }
      @data_sprites = []
    end
    super
    if $dev_settings_enabled
      # 最下方追加"开发者设置"栏 (原版 @data 每次重建, 这里只追加一个)
      @data << tr('Developer Settings')
      i = @data.size - 1
      spr = Sprite.new(@viewport)
      spr.bitmap = Bitmap.new(400, self.class::ITEM_SPACING)
      spr.x = self.class::MARGIN
      spr.y = self.class::TITLE_MARGIN + self.class::TITLE_TOP_MARGIN + self.class::ITEM_SPACING * i
      spr.opacity = 0
      Language.register_text_sprite(self.class.name + "_option_#{i}", spr)
      redraw_setting(spr, i)
      @data_sprites << spr
    end
  end

  def update
    if @dev_settings && @dev_settings.visible
      @dev_settings.update
      return
    end
    super
    # 在"开发者设置"栏上按确认键 → 打开开发者设置子界面
    if $dev_settings_enabled && @visible && !@fade_in && !@fade_out &&
       @data && @index == @data.size - 1 && Input.trigger?(Input::ACTION)
      @dev_settings ||= Window_DevSettings.new
      # 注入外层引用: 跳地图成功后需要一并关闭设置窗口
      @dev_settings.parent_settings = self
      @dev_settings.open
    end
  end

  def dispose
    @dev_settings.dispose if @dev_settings
    @dev_settings = nil  # 防止复用已 dispose 的实例
    super
  end
end

# --- 等待 Window_Settings 类定义完成后 prepend 补丁 ---
trace = TracePoint.trace(:end) do |tp|
  begin
    if tp.self.is_a?(Class) && tp.self.name == 'Window_Settings' &&
       tp.self.method_defined?(:open) && tp.self.method_defined?(:update)
      tp.self.prepend(WindowSettingsDevPatch)
      trace.disable
    end
  rescue StandardError
    # 忽略异常, 继续监听
  end
end

# --- 写状态文件 ---
status_path = File.join(__dir__, '..', 'dev_settings_status.txt')
File.open(status_path, 'w') do |f|
  f.puts "dev_settings_enabled = #{$dev_settings_enabled}"
  f.puts "config_source = \$mod_config (unified loader _config.rb)"
  f.puts "config = #{JSON.pretty_generate(config)}"
  f.puts "patch_method = TracePoint(:end) + Module#prepend (Window_Settings#open/update/dispose)"
  f.puts "config_path = #{CONFIG_PATH}"
  f.puts "sync_globals = #{GLOBAL_SYNC.inspect}"
  f.puts "loaded_at = #{Time.now}"
end
