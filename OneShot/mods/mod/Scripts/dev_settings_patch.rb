# ============================================================
#  dev_settings_patch.rb — 设置页"开发者设置"栏补丁
#
#  给 Window_Settings 打补丁:
#    1. open 时在设置列表最下方追加"开发者设置"栏
#    2. update 时检测到在该栏上按确认键 → 打开 Window_DevSettings 子界面
#    3. dispose 时清理子界面实例, 防止复用已 dispose 的对象
#
#  纯 preload 实现, 不修改游戏原始文件。
#  用 TracePoint(:end) 监听 Window_Settings 类定义, 在
#  open/update/dispose 就绪后用 Module#prepend 打补丁。
#
#  依赖:
#    dev_settings.rb 提供 Window_DevSettings 与 $dev_settings_enabled
#    config.json: "is_developer": true  → 设置页显示"开发者设置"栏
# ============================================================

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
PatchHelper.install('Window_Settings', methods: [:open, :update]) do |k|
  k.prepend(WindowSettingsDevPatch)
end

# --- 写状态文件 ---
StatusLog.write('dev_settings_patch_status.txt', [
  "dev_settings_patch loaded at = #{Time.now}",
  "patch_method = PatchHelper.install (Window_Settings#open/update/dispose)",
  "dependency = dev_settings.rb (Window_DevSettings, $dev_settings_enabled)",
  "behavior = append 'Developer Settings' row, open sub-window on ACTION"
])
