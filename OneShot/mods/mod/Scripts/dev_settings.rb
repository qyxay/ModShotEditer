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
#
#  三个"功能动作"(非布尔开关, 点击一次即对"当前地图"执行解锁/完成):
#    只作用于"当前地图事件实际引用到的开关"(事件页条件 + 条件分支指令),
#    不触碰其他地图的全局开关。
#    开关分两类: "激活类"(非空页/条件分支用, true=解锁推进) 与
#    "关闭类"(仅空页条件用, true=事件变哑, 如"出口已用过"标记)。
#    Unlock All Doors (this map)        → 当前地图激活类开关全 ON, 关闭类置 OFF(门保持可用)
#    Complete All Dialogues (this map)  → 完成当前地图对话(只完成自开关页安全的)
#    Complete All Story (this map)      → 完成当前地图剧情(自开关+激活类开关, 不关死门)
#    反向动作(lock / incomplete)已不再被界面触发, 仅保留方法体供排查/复用。
#    这三个键仍保留在 config.json(值为 true/false), 供 Jump Map 跳转后的
#    auto_apply_current_map 读取: true = 跳进地图时自动执行对应动作。
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

# --- 功能动作条目(非布尔开关): 标识 → 界面显示名, 顺序即菜单顺序 ---
# 点击一次即执行对应动作(解锁/完成当前地图), 不切换/不写回开关值。
# 反向动作(lock/incomplete)不再由界面触发。
EXTRA_ACTIONS = [
  [:unlock_all_doors,       'Unlock All Doors (this map)'],
  [:complete_all_dialogues, 'Complete All Dialogues (this map)'],
  [:complete_all_story,     'Complete All Story (this map)'],
  [:jump_map,               'Jump Map']
]

# 上述三个功能动作在 config.json 中的键名(不显示为布尔开关, 值仅供 auto_apply 读取)
ACTION_KEYS = %w[unlock_all_doors complete_all_dialogues complete_all_story]

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
    # 功能动作条目(非布尔开关, 点击即执行), 追加在布尔开关之后
    @extra_items = EXTRA_ACTIONS.map { |_, name| name }
    @jump_map = nil
    # 外层 Window_Settings 引用(由补丁注入), 用于跳转后一并关闭
    @parent_settings = nil
    # 关闭回调(由快捷键打开时注入, 用于恢复被借用的设置窗口状态)
    @on_closed = nil
    # 全局实例引用: 供 Jump Map 跳转后"按 config 自动应用开关"用(免 ObjectSpace 扫描)
    $dev_settings_instance = self
  end

  # --- 类方法: 跳转进入地图后, 按 config.json 的三个功能开关自动应用 ---
  # Jump Map 跳转(自由浏览模式)每次 Game_Map#setup 后调用:
  # config 中 unlock_all_doors / complete_all_dialogues / complete_all_story
  # 为 true 时, 对"当前地图"执行对应动作 —— 这样跳转瞭望甲板等地图后,
  # SW22 等传送条件开关自动为 true, 出口传送立即可用, 无需再手动切一次。
  def self.auto_apply_current_map
    ds = $dev_settings_instance
    return unless ds && $game_map && $game_map.events
    cfg = begin
      ds.reload_config
    rescue StandardError
      $mod_config || {}
    end
    return unless cfg.is_a?(Hash)
    ds.unlock_all_doors if cfg['unlock_all_doors'] == true
    ds.complete_all_dialogues if cfg['complete_all_dialogues'] == true
    ds.complete_all_story if cfg['complete_all_story'] == true
  rescue StandardError
    # 静默: 自动应用失败不影响地图加载
  end

  # 完整显示列表 = 布尔开关 + 固定功能条目
  def display_items
    @keys + @extra_items
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
    # 布尔开关 = 所有 bool 键, 但排除三个功能动作键(它们不作为开关显示,
    # 值仅供 Jump Map 跳转后 auto_apply_current_map 读取)
    @keys = @config.keys.select do |k|
      (@config[k] == true || @config[k] == false) && !ACTION_KEYS.include?(k)
    end
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
      # 快捷键打开时注入的关闭回调(恢复被借用的设置窗口状态)
      @on_closed.call if @on_closed
    end

    # 动作反馈提示的显示计时
    if @flash_timer > 0
      @flash_timer -= 1
      @flash_sprite.visible = true if @flash_timer > 0
      @flash_sprite.visible = false if @flash_timer == 0
    end
  end

  # 执行功能动作(非布尔开关的固定条目, 点击一次即执行)
  def run_action(display_name)
    pair = EXTRA_ACTIONS.find { |_, name| name == display_name }
    return unless pair
    case pair[0]
    when :jump_map
      open_jump_map
    else
      send(pair[0])
    end
  end

  # 短暂显示动作结果提示
  def flash(msg)
    @flash_sprite.bitmap.clear
    @flash_sprite.bitmap.draw_text(0, 0, @flash_sprite.bitmap.width, @flash_sprite.bitmap.height, tr(msg))
    @flash_sprite.visible = true
    @flash_timer = 120
  end

  # --- 当前地图使用的全局开关: 区分"激活类"与"关闭类" ---
  # 激活类(activate): 至少一次作为"非空页"的页条件, 或出现在条件分支(111)判断里。
  #   置 true = 激活有实际功能的页 / 走 ON 分支 (解锁、推进剧情)。
  # 关闭类(close_only): 只作为"空页"(命令全空)的页条件。置 true = 激活空页,
  #   使该事件变哑 —— 如瞭望甲板出口 EV001/EV004 的 SW301(true = 出口已用过/关闭)。
  #   解锁/完成时绝不能置 true, 否则门/传送等互动会被"完成"掉。
  # 来源: ① 事件页条件(switch1/switch2) ② 事件指令"条件分支"(code 111)中的开关判断
  def current_map_switch_info
    return { activate: [], close_only: [] } unless $game_map && $game_map.events
    activate = {}
    close_only = {}
    $game_map.events.each_value do |ev|
      evt = ev.instance_variable_get(:@event)
      pages = evt ? evt.pages : nil
      # ① 事件页条件里的开关
      if pages
        pages.each do |page|
          c = page.condition
          next unless c
          list = page.list
          is_empty = list.nil? || list.empty? || list.all? { |cmd| cmd && cmd.code == 0 }
          sws = []
          sws << c.switch1_id if c.switch1_valid
          sws << c.switch2_id if c.switch2_valid
          sws.each do |sid|
            next unless sid && sid > 0
            if is_empty
              close_only[sid] = true
            else
              activate[sid] = true
            end
          end
        end
      end
      # ② 事件指令"条件分支"(111, parameters[0]==0)里的开关判断 → 激活类
      lists = pages ? pages.map { |pg| pg.list } : (ev.list ? [ev.list] : [])
      lists.each do |list|
        next unless list
        list.each do |cmd|
          next unless cmd && cmd.code == 111
          p = cmd.parameters
          activate[p[1]] = true if p && p[0] == 0 && p[1]
        end
      end
    end
    { activate: activate.keys, close_only: close_only.keys }
  end

  # --- 统一设置当前地图开关并刷新事件 ---
  # mode = :unlock(ON) → 激活类置 true, 关闭类置 false(清除"已关闭"标记, 门保持可用)
  # mode = :lock(OFF)  → 激活类+关闭类全置 false(恢复初始未解锁/未完成)
  def set_current_switches(mode = :unlock)
    info = current_map_switch_info
    if mode == :lock
      ids = (info[:activate] + info[:close_only]).uniq
      ids.each { |s| $game_switches[s] = false }
    else
      info[:activate].each { |s| $game_switches[s] = true }
      info[:close_only].each { |s| $game_switches[s] = false }
    end
    if $game_map && $game_map.events
      $game_map.events.each_value { |e| e.refresh }
    end
    info[:activate].size
  end

  # --- 解锁当前地图的门锁(ON) ---
  # 只置"激活类"开关(页0/非空页的页条件开关), 并把"关闭类"(已用完标记)置 false,
  # 保证门/传送保持可用, 不会被"完成"掉。
  def unlock_all_doors
    if !$game_switches
      flash('Not in game')
      return
    end
    count = set_current_switches(:unlock)
    flash("#{count} switches ON (this map)")
  end

  # --- 完成所有对话(当前地图, 只完成"能安全完成"的) ---
  # 把当前地图含对话(Show Text 101)事件的自开关 A-D 置 true, 使其跳到"已完成"页;
  # 但跳过"自开关条件页是 AUTORUN / 含强制移动/传送"的事件(完成会触发卡住),
  # 也跳过没有自开关条件页的事件。不实际运行事件, 无副作用。
  def complete_all_dialogues
    if !$game_map || !$game_map.events
      flash('Not in game')
      return
    end
    count = 0
    $game_map.events.each_value do |ev|
      next unless event_has_dialogue?(ev)
      done = false
      %w[A B C D].each do |s|
        page = find_self_switch_page(ev, s)
        next unless safe_completion_page?(page)
        $game_self_switches[[$game_map.map_id, ev.id, s]] = true
        done = true
      end
      count += 1 if done
    end
    $game_map.events.each_value { |e| e.refresh }
    flash("#{count} dialogues done (this map)")
  end

  # --- 完成所有剧情(当前地图, 但不把门关死) ---
  # 把当前地图所有事件的自开关 A-D 置 true(同样只完成"安全可完成"的), 让剧情
  # 跳到"已发生"状态; 开关部分只置"激活类", 关闭类(已用完标记)置 false —— 完成
  # 剧情的同时保留门/传送可用。
  def complete_all_story
    if !$game_map || !$game_map.events
      flash('Not in game')
      return
    end
    count = 0
    $game_map.events.each_value do |ev|
      next unless ev
      done = false
      %w[A B C D].each do |s|
        page = find_self_switch_page(ev, s)
        next unless safe_completion_page?(page)
        $game_self_switches[[$game_map.map_id, ev.id, s]] = true
        done = true
      end
      count += 1 if done
    end
    $game_map.events.each_value { |e| e.refresh }
    # 一并解锁当前地图使用的"激活类"开关(含门锁), 关闭类(已用完)保持 false
    set_current_switches(:unlock) if $game_switches
    flash("#{count} events done (this map)")
  end

  # --- 锁定当前地图的门锁(OFF) ---
  # 激活类+关闭类全置 false, 恢复未解锁初始状态。
  def lock_all_doors
    if !$game_switches
      flash('Not in game')
      return
    end
    count = set_current_switches(:lock)
    flash("#{count} switches OFF (this map)")
  end

  # --- 未完成所有对话(当前地图, OFF) ---
  # 把含对话事件的安全自开关 A-D 置 false, 使其跳回"未完成"页。
  def incomplete_all_dialogues
    if !$game_map || !$game_map.events
      flash('Not in game')
      return
    end
    count = 0
    $game_map.events.each_value do |ev|
      next unless event_has_dialogue?(ev)
      done = false
      %w[A B C D].each do |s|
        page = find_self_switch_page(ev, s)
        next unless safe_completion_page?(page)
        $game_self_switches[[$game_map.map_id, ev.id, s]] = false
        done = true
      end
      count += 1 if done
    end
    $game_map.events.each_value { |e| e.refresh }
    flash("#{count} dialogues undone (this map)")
  end

  # --- 未完成所有剧情(当前地图, OFF) ---
  # 安全自开关 A-D 置 false + 开关全置 false, 恢复"未发生"状态。
  def incomplete_all_story
    if !$game_map || !$game_map.events
      flash('Not in game')
      return
    end
    count = 0
    $game_map.events.each_value do |ev|
      next unless ev
      done = false
      %w[A B C D].each do |s|
        page = find_self_switch_page(ev, s)
        next unless safe_completion_page?(page)
        $game_self_switches[[$game_map.map_id, ev.id, s]] = false
        done = true
      end
      count += 1 if done
    end
    $game_map.events.each_value { |e| e.refresh }
    set_current_switches(:lock) if $game_switches
    flash("#{count} events undone (this map)")
  end

  # --- 事件"自开关 S 条件页"(条件里 self_switch_ch == s 且 self_switch_valid) ---
  def find_self_switch_page(ev, s)
    evt = ev.instance_variable_get(:@event)
    pages = evt ? evt.pages : (ev.respond_to?(:pages) ? ev.pages : nil)
    return nil unless pages
    pages.find { |pg| c = pg.condition; c && c.self_switch_valid && c.self_switch_ch == s }
  end

  # --- 事件是否含对话(Show Text 101) ---
  # 注意: Game_Event#list 只是"当前激活页"的命令(未激活时为 nil), 不能用来判断
  # 事件是否含对话。必须遍历事件的原始页 @event.pages 检查。
  def event_has_dialogue?(ev)
    evt = ev.instance_variable_get(:@event)
    pages = evt ? evt.pages : (ev.respond_to?(:pages) ? ev.pages : nil)
    return false unless pages
    pages.any? { |pg| list = pg.list; list && list.any? { |c| c && c.code == 101 } }
  end

  # --- 该"自开关条件页"是否安全完成 ---
  # 置自开关 true 后如果会触发 AUTORUN / 强制移动 / 传送(抢占玩家), 视为不安全,
  # 跳过不完成 —— 满足"只完成当前地图能完成的对话和剧情"。
  def safe_completion_page?(page)
    return false unless page
    return false if page.trigger == 3  # AUTORUN
    list = page.list
    return false unless list
    # 强制移动(209 移动路线) / 传送(201) 会强占玩家控制 → 跳过
    return false if list.any? { |cmd| cmd && (cmd.code == 209 || cmd.code == 201) }
    true
  end

  # 切换当前布尔开关并写回 (仅普通布尔开关; 功能动作条目走 run_action)
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
    %w[skip_pictures quit_all_time skip_dialogue skip_choice always_travel always_settings unshow_title is_developer unlock_all_doors complete_all_dialogues complete_all_story].each do |k|
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
      # 经设置菜单打开: 清掉快捷键注入的关闭回调, 按 CANCEL 只关开发者设置
      # 回到设置窗口, 不误关设置窗口本身
      @dev_settings.on_closed = nil
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
status_path = File.join(__dir__, '..', 'logs', 'dev_settings_status.txt')
File.open(status_path, 'w') do |f|
  f.puts "dev_settings_enabled = #{$dev_settings_enabled}"
  f.puts "config_source = \$mod_config (unified loader _config.rb)"
  f.puts "config = #{JSON.pretty_generate(config)}"
  f.puts "patch_method = TracePoint(:end) + Module#prepend (Window_Settings#open/update/dispose)"
  f.puts "config_path = #{CONFIG_PATH}"
  f.puts "sync_globals = #{GLOBAL_SYNC.inspect}"
  f.puts "loaded_at = #{Time.now}"
end
