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
    @viewport.z = 9999
    @data_sprites = []
    @index = 0
    @visible = false
    @config = {}
    @keys = []
  end

  def visible
    @visible
  end

  def visible=(val)
    @viewport.visible = val
    @visible = val
  end

  def open
    reload_config
    return if @keys.empty?
    @index = 0
    # 必须先置可见, 否则 open 内的 redraw 会因 @visible == false 而跳过绘制
    self.visible = true
    # 标题
    @title.bitmap.clear
    @title.bitmap.draw_text(0, 0, @title.bitmap.width, @title.bitmap.height, tr('Developer Settings'))
    # 清掉旧 sprite
    @data_sprites.each { |spr| spr.dispose }
    @data_sprites = []
    @keys.each_with_index do |key, i|
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
    key = @keys[i]
    spr.bitmap.clear
    spr.bitmap.draw_text(0, 0, spr.bitmap.width, spr.bitmap.height, key)
    val = @config[key]
    spr.bitmap.draw_text(VALUE_MARGIN, 0, spr.bitmap.width, spr.bitmap.height,
                         val ? tr('ON') : tr('OFF'))
  end

  def redraw_all
    @data_sprites.each_with_index { |spr, i| redraw(spr, i) }
  end

  def update
    return if !@visible || @keys.empty?
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
      @index = (@index - 1) % @keys.size
      $game_system.se_play($data_system.cursor_se)
    end
    if Input.trigger?(Input::DOWN)
      @index = (@index + 1) % @keys.size
      $game_system.se_play($data_system.cursor_se)
    end

    # 切换当前开关: 确认键 / 左右键
    if Input.trigger?(Input::ACTION) || Input.trigger?(Input::LEFT) || Input.trigger?(Input::RIGHT)
      key = @keys[@index]
      @config[key] = !@config[key]
      apply_global(key, @config[key])
      $mod_config[key] = @config[key] if $mod_config
      save_config
      $game_system.se_play($data_system.decision_se)
      redraw_all
    end

    if Input.trigger?(Input::CANCEL)
      $game_system.se_play($data_system.cancel_se)
      self.visible = false
    end
  end

  def dispose
    @data_sprites.each { |spr| spr.dispose }
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
    super
    if $dev_settings_enabled
      # 最下方追加"开发者设置"栏
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
      @dev_settings.open
    end
  end

  def dispose
    @dev_settings.dispose if @dev_settings
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
