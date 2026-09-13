# ============================================================
#  i18n_mod.rb — mod 界面文本中文化 (语言补丁)
#
#  把 mod 新增界面文本(开发者设置/跳地图/开关名)翻译成中文。
#  不改原版 Languages/*.po —— 纯 preload 注入, 语言切到中文时
#  (zh_CN / zh_CHT / zh) 把翻译塞进 Language 的 @data 表。
#
#  原理:
#    OneShot 的 Language.set 加载 Languages/<lang>.po 并重建
#    @data(crc32(msgid) → msgstr) 哈希; tr() 按 crc32 查表。
#    本脚本在 Language 单例类定义完成后 prepend set,
#    在 super(原版加载 .po)之后把 MOD_TRANSLATIONS 注入 @data。
#    原版已翻译的键(ON/OFF/Yes/No/Settings 等)不重复注入。
#
#  注意: Language.set 是类方法(class << self), PatchHelper 的
#  method_defined? 只查实例方法, 故此处用独立 TracePoint 挂单例类。
#
#  依赖: 运行时 tr() 由游戏脚本 0091_i18n_Language.rb 提供
# ============================================================

# --- mod 界面文本中英对照 ---
MOD_TRANSLATIONS = {
  'Developer Settings' => '开发者设置',
  'Jump Map'           => '跳地图',
  # 开发者设置开关名 (config 键名 → 中文显示; 键本身不变)
  'skip_pictures'   => '跳过过场图片',
  'quit_all_time'   => '随时可退出/打开菜单',
  'skip_dialogue'   => '跳过对话',
  'skip_choice'     => '自动选第一个选项',
  'skip_uneasy'     => '跳过读档不安提示',
  'always_travel'   => '事件中可跳地图',
  'always_settings' => '事件中可开设置',
  'unshow_title'    => '跳过标题界面',
  'is_developer'    => '开发者模式',
  'fly_mode'        => '飞行模式',
  'live_update'     => '实时更新'
}.freeze

# --- 语言切换后注入 mod 翻译 (仅中文语言生效) ---
module ModI18nPatch
  def set(lc)
    super
    full = (lc.full.to_s rescue '')
    lang = (lc.lang.to_s rescue '')
    if full =~ /^zh/i || lang =~ /^zh/i
      MOD_TRANSLATIONS.each { |k, v| @data[Oneshot::crc32(k)] = v }
    end
  end
end

# --- 等待 Language 类定义完成后 prepend 到单例类 ---
# (Language.set 为类方法, 需挂 singleton_class)
trace = TracePoint.trace(:end) do |tp|
  begin
    if tp.self.is_a?(Class) && tp.self.name == 'Language' &&
       tp.self.singleton_class.method_defined?(:set)
      tp.self.singleton_class.prepend(ModI18nPatch)
      trace.disable
    end
  rescue StandardError
  end
end

# --- 写状态文件 ---
StatusLog.write('i18n_mod_status.txt', [
  "i18n_mod loaded at = #{Time.now}",
  "method = prepend Language singleton set, inject MOD_TRANSLATIONS after super (zh_CN/zh_CHT/zh only)",
  "keys = #{MOD_TRANSLATIONS.size}",
  "note = ON/OFF/Yes/No/Settings already in zh_CN.po, not re-injected",
  "font = zh_CN uses WenQuanYi Micro Hei (language_fonts.ini)"
])
