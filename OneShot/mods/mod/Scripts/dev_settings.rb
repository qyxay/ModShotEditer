# ============================================================
#  dev_settings.rb — 开发者设置子界面 (Window_DevSettings)
#
#  开发者设置子界面: 进入后列出 config.json 中的所有布尔开关,
#  可在游戏内实时切换并写回 config.json, 同时同步对应 mod 的
#  全局开关变量(实现不重启即生效)。
#
#  纯 preload 实现, 不修改游戏原始文件。
#
#  入口来源:
#    1) dev_settings_patch.rb: Window_Settings 最下方追加"开发者设置"栏
#    2) shortcut_keys.rb: Ctrl+D 快捷键直接打开
#  功能条目(EXTRA_ACTIONS): 非布尔开关的可执行动作, 如 Jump Map
#
#  翻页: 项数超过 PAGE_SIZE 时自动分页, 上下键跨页, 页码在右下角。
#
#  配置: mods/mod/config.json
#    "is_developer": true  → 设置页显示"开发者设置"栏
#    "is_developer": false → 隐藏该栏
#
# ============================================================

require 'json'

# --- 读取配置 (统一由 _config.rb 加载到 $mod_config) ---
default_config = { "is_developer" => false }
config = default_config.merge($mod_config || {})

$dev_settings_enabled = config["is_developer"] ? true : false

# config.json 路径: Scripts/../config.json
CONFIG_PATH = File.join(__dir__, '..', 'config.json')

# config.json 键 → mod 全局开关变量: 同步逻辑见 apply_global 的 case 分支
# (白名单, 无注入风险; 新增开关时在 case 中补一个分支)

# --- 功能动作条目(非布尔开关): 标识 → 界面显示名, 顺序即菜单顺序 ---
EXTRA_ACTIONS = [
  [:jump_map, 'Jump Map']
]

# --- 三态枚举键(非布尔): 键 → 可选值列表, 确认/左右键循环切换 ---
# (skip_event 已从界面移除; 枚举机制保留备用)
ENUM_KEYS = {}

# --- 开发者设置子界面 ---
class Window_DevSettings
  MARGIN = 30
  TITLE_TOP_MARGIN = 32
  TITLE_MARGIN = 100
  ITEM_SPACING = 28
  VALUE_MARGIN = 270
  ACTIVE_MARGIN = MARGIN * 2 + 20
  PAGE_SIZE = 8               # 每页最多显示项数, 超出自动翻页(页码在右下角)

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
    # 页码指示 (右下角, 多页时显示)
    @page_indicator = Sprite.new(@viewport)
    @page_indicator.bitmap = Bitmap.new(120, 20)
    @page_indicator.x = 640 - 120 - MARGIN
    @page_indicator.y = 480 - 24 - 8
    @page_indicator.visible = false
    @viewport.z = 9999
    @data_sprites = []
    @index = 0
    @visible = false
    @config = {}
    @keys = []
    @enum_keys = []
    # 功能动作条目(非布尔开关, 点击即执行), 追加在布尔开关之后
    @extra_items = EXTRA_ACTIONS.map { |_, name| name }
    @jump_map = nil
    # 外层 Window_Settings 引用(由补丁注入), 用于跳转后一并关闭
    @parent_settings = nil
    # 关闭回调(由快捷键打开时注入, 用于恢复被借用的设置窗口状态)
    @on_closed = nil
    # 全局实例引用: 供 Jump Map 跳转后"按 config 自动应用开关"用(免 ObjectSpace 扫描)
    $dev_settings_instance = self
    @disposed = false
  end

  # 是否已 dispose (纯 Ruby 类无内置 disposed? 方法, 自行标记)
  def disposed?
    @disposed
  end

  # 完整显示列表 = 布尔开关 + 三态枚举键 + 固定功能条目
  def display_items
    @keys + @enum_keys + @extra_items
  end

  attr_accessor :parent_settings
  attr_accessor :on_closed

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
    @flash_sprite.visible = false unless @flash_sprite.disposed?
    # 必须先置可见, 否则 open 内的 redraw 会因 @visible == false 而跳过绘制
    self.visible = true
    # 标题
    @title.bitmap.clear
    @title.bitmap.draw_text(0, 0, @title.bitmap.width, @title.bitmap.height, tr('Developer Settings'))
    # 按当前页重建项 sprite (翻页时同样调用)
    rebuild_page
  end

  # --- 翻页: 页码/页内容/重建 ---
  def page_count
    (display_items.size + PAGE_SIZE - 1) / PAGE_SIZE
  end

  def page
    @index / PAGE_SIZE
  end

  def page_items
    start = page * PAGE_SIZE
    display_items[start, PAGE_SIZE] || []
  end

  # 按当前页重建项 sprite 并刷新页码指示
  def rebuild_page
    @data_sprites.each { |spr| spr.dispose }
    @data_sprites = []
    page_items.each_with_index do |key, j|
      gi = page * PAGE_SIZE + j
      spr = Sprite.new(@viewport)
      spr.bitmap = Bitmap.new(400, ITEM_SPACING)
      spr.x = MARGIN * 2   # 原位统一为 MARGIN*2(60), 与 jump_map 一致: 取消选中后滑回目标=其他项静止位
      spr.y = TITLE_MARGIN + TITLE_TOP_MARGIN + ITEM_SPACING * j
      spr.opacity = 0
      redraw(spr, gi)
      @data_sprites << spr
    end
    if page_count > 1
      @page_indicator.bitmap.clear
      @page_indicator.bitmap.font.size = 14
      @page_indicator.bitmap.draw_text(0, 0, @page_indicator.bitmap.width, @page_indicator.bitmap.height,
                                       format('%d/%d', page + 1, page_count), 2)
      @page_indicator.visible = true
    else
      @page_indicator.visible = false
    end
  end

  def reload_config
    @config = begin
      JSON.parse(File.read(CONFIG_PATH))
    rescue StandardError
      $mod_config || {}
    end
    # 布尔开关 = 所有 bool 键
    @keys = @config.keys.select do |k|
      @config[k] == true || @config[k] == false
    end
    # 三态枚举键 = ENUM_KEYS 中存在于 config 的键
    @enum_keys = ENUM_KEYS.keys.select { |k| @config.key?(k) }
  end

  def redraw(spr, gi)
    return if @visible == false
    item = display_items[gi]
    spr.bitmap.clear
    spr.bitmap.draw_text(0, 0, spr.bitmap.width, spr.bitmap.height, tr(item))
    if gi < @keys.size
      # 布尔开关: 显示 ON/OFF
      val = @config[item]
      spr.bitmap.draw_text(VALUE_MARGIN, 0, spr.bitmap.width, spr.bitmap.height,
                           val ? tr('ON') : tr('OFF'))
    elsif gi < @keys.size + @enum_keys.size
      # 三态枚举键: 显示当前值
      val = @config[item].to_s
      spr.bitmap.draw_text(VALUE_MARGIN, 0, spr.bitmap.width, spr.bitmap.height, tr(val))
    else
      # 功能条目: 显示进入箭头
      spr.bitmap.draw_text(VALUE_MARGIN, 0, spr.bitmap.width, spr.bitmap.height, '>')
    end
  end

  def redraw_all
    @data_sprites.each_with_index { |spr, j| redraw(spr, page * PAGE_SIZE + j) }
  end

  def update
    return if !@visible || display_items.empty?
    if @jump_map && @jump_map.visible
      @jump_map.update
      return
    end
    # 光标动画(与 Window_Settings 视觉一致; j 为页内索引, gi 为全局索引)
    @data_sprites.each_with_index do |spr, j|
      gi = page * PAGE_SIZE + j
      if gi == @index
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

    old_page = page
    if Input.trigger?(Input::UP)
      @index = (@index - 1) % display_items.size
      $game_system.se_play($data_system.cursor_se)
    end
    if Input.trigger?(Input::DOWN)
      @index = (@index + 1) % display_items.size
      $game_system.se_play($data_system.cursor_se)
    end
    # 跨页: 重建当前页的项
    rebuild_page if page != old_page

    # ACTION: 切换当前开关 (布尔取反/枚举循环); 功能条目执行对应动作
    if Input.trigger?(Input::ACTION)
      if @index >= @keys.size + @enum_keys.size
        $game_system.se_play($data_system.decision_se)
        run_action(@extra_items[@index - @keys.size - @enum_keys.size])
      else
        toggle(@index)
      end
    end
    # 左右键: 翻页 (页数 >1 时生效), 保持页内相对位置
    if Input.trigger?(Input::LEFT) || Input.trigger?(Input::RIGHT)
      if page_count > 1
        $game_system.se_play($data_system.cursor_se)
        rel = @index - page * PAGE_SIZE
        new_page = (page + (Input.trigger?(Input::LEFT) ? -1 : 1)) % page_count
        items = display_items[new_page * PAGE_SIZE, PAGE_SIZE]
        @index = new_page * PAGE_SIZE + [rel, items.size - 1].min
        rebuild_page
      end
    end

    if Input.trigger?(Input::CANCEL)
      $game_system.se_play($data_system.cancel_se)
      self.visible = false
      # 快捷键打开时注入的关闭回调(恢复被借用的设置窗口状态)
      @on_closed.call if @on_closed
    end

    # 动作反馈提示的显示计时
    if @flash_timer > 0
      @flash_timer -= 1
      unless @flash_sprite.disposed?
        @flash_sprite.visible = true if @flash_timer > 0
        @flash_sprite.visible = false if @flash_timer == 0
      end
    end
  end

  # 执行功能动作(非布尔开关的固定条目, 点击一次即进入子界面)
  def run_action(display_name)
    pair = EXTRA_ACTIONS.find { |_, name| name == display_name }
    return unless pair
    case pair[0]
    when :jump_map
      open_jump_map
    end
  end

  # 短暂显示动作结果提示
  def flash(msg)
    @flash_sprite.bitmap.clear
    @flash_sprite.bitmap.draw_text(0, 0, @flash_sprite.bitmap.width, @flash_sprite.bitmap.height, tr(msg))
    @flash_sprite.visible = true
    @flash_timer = 120
  end

  # 切换当前开关并写回 (布尔开关取反; 三态枚举循环切换; 功能条目走 run_action)
  def toggle(i)
    if i < @keys.size
      key = @keys[i]
      @config[key] = !@config[key]
    else
      key = @enum_keys[i - @keys.size]
      vals = ENUM_KEYS[key]
      cur = @config[key].to_s
      idx = vals.index(cur)
      @config[key] = vals[(idx || -1) + 1] || vals[0]
    end
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
      @jump_map = nil   # 彻底重置, 防止复用残留状态(旧 sprites/旧回调)
      self.visible = false
      @parent_settings.visible = false if @parent_settings
      # 彻底销毁并清引用: 跳转后若目标地图触发 real_load(读档), $scene 会
      # 切换为新 Scene_Map, 旧窗口随之 dispose; 这里先销毁自身并把外层
      # Window_Settings 的 @dev_settings 引用置 nil, 防止新场景帧循环
      # 访问已销毁的 sprite (disposed sprite 崩溃)
      begin
        self.dispose
        @parent_settings.instance_variable_set(:@dev_settings, nil) if @parent_settings
      rescue StandardError
      end
    }
    @jump_map.open
  end

  def dispose
    @disposed = true
    @jump_map.dispose if @jump_map
    @data_sprites.each { |spr| spr.dispose }
    @flash_sprite.dispose
    @page_indicator.dispose
    @title.dispose
    @bg.dispose
    @viewport.dispose
  end

  private

  # 同步对应 mod 的全局开关变量, 实现不重启即生效(白名单, 显式赋值)
  def apply_global(key, val)
    case key
when 'skip_pictures'   then $is_skip_picture = val
when 'quit_all_time'   then $quit_all_time_enabled = val
when 'skip_dialogue'   then $skip_dialogue_enabled = val
when 'skip_choice'     then $skip_choice_enabled = val
when 'skip_uneasy'     then $skip_uneasy_enabled = val
when 'always_settings' then $always_settings_enabled = val
when 'always_travel'   then $always_travel_enabled = val
when 'unshow_title'    then $unshow_title_enabled = val
when 'is_developer'    then $dev_settings_enabled = val
when 'fly_mode'        then $fly_mode_enabled = val
when 'live_update'     then $live_update_enabled = val
    end
  end

  # 写回 config.json, 已知键保持固定顺序, 未知键追加在尾部
  def save_config
    $mod_config ||= @config
    ordered = {}
    %w[skip_pictures quit_all_time skip_dialogue skip_choice skip_uneasy always_travel always_settings unshow_title is_developer fly_mode live_update].each do |k|
      ordered[k] = @config[k] if @config.key?(k)
    end
    @config.each do |k, v|
      ordered[k] = v unless ordered.key?(k)
    end
    File.write(CONFIG_PATH, JSON.pretty_generate(ordered) + "\n")
  end
end

# --- 写状态文件 ---
StatusLog.write('dev_settings_status.txt', [
  "dev_settings_enabled = #{$dev_settings_enabled}",
  "config_source = \$mod_config (unified loader _config.rb)",
  "config = #{JSON.pretty_generate(config)}",
  "entry = dev_settings_patch.rb (Window_Settings row) / shortcut_keys.rb (Ctrl+D)",
  "config_path = #{CONFIG_PATH}",
  "sync_globals = apply_global case (11 keys, skip_event removed)",
  "paging = PAGE_SIZE 8, page indicator bottom-right, UP/DOWN crosses pages",
  "loaded_at = #{Time.now}"
])
