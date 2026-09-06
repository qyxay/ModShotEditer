# ============================================================
#  _settings_core.rb — 运行时设置系统核心框架
#
#  架构:
#    SettingDef      — 设置项定义 (key/label/type/default/...)
#    SettingRegistry — 全局注册表 (register/get/all/by_category)
#    SettingStore    — JSON 存储 + 热重载 (load/save/get/set/check_reload)
#
#  可扩展性: 新增设置只需 SettingRegistry.register(...)，
#  GUI 和存储自动适配，无需改核心代码。
#
#  存储文件: mods/mod/settings/runtime.json
#  热重载:   每帧检测文件 mtime，变化自动 reload + apply
# ============================================================

require 'json'
require 'fileutils'

# --- 设置项定义 ---
class SettingDef
  attr_accessor :key, :label, :type, :default, :min, :max,
                :options, :category, :order, :apply_proc, :help

  # @param key       [String] 唯一标识 (如 "spawn.x")
  # @param label     [String] 显示名
  # @param type      [Symbol] :bool / :int / :float / :string / :enum
  # @param default   [Object] 默认值
  # @param min/max   [Numeric] 数值范围 (int/float)
  # @param options   [Array]  enum 选项 [[value, label], ...]
  # @param category  [String] 分类 (如 "spawn", "skip", "debug")
  # @param order     [Integer] 排序权重 (小的在前)
  # @param apply_proc [Proc]  设置变更时回调 (val)
  # @param help      [String] 帮助文本
  def initialize(key:, label:, type:, default:, min: nil, max: nil,
                 options: nil, category: "general", order: 100,
                 apply_proc: nil, help: "")
    @key = key
    @label = label
    @type = type
    @default = default
    @min = min
    @max = max
    @options = options
    @category = category
    @order = order
    @apply_proc = apply_proc
    @help = help
  end

  # 校验值是否合法
  def valid?(val)
    case @type
    when :bool
      val == true || val == false
    when :int
      val.is_a?(Integer) && (@min.nil? || val >= @min) && (@max.nil? || val <= @max)
    when :float
      val.is_a?(Numeric) && (@min.nil? || val >= @min) && (@max.nil? || val <= @max)
    when :string
      val.is_a?(String)
    when :enum
      @options && @options.any? { |v, _| v == val }
    else
      false
    end
  end

  # 格式化值为显示文本
  def format(val)
    case @type
    when :bool
      val ? "ON" : "OFF"
    when :enum
      opt = @options&.find { |v, _| v == val }
      opt ? opt[1] : val.to_s
    else
      val.to_s
    end
  end
end

# --- 全局注册表 ---
module SettingRegistry
  @defs = {}

  def self.register(def_obj)
    @defs[def_obj.key] = def_obj
  end

  def self.get(key)
    @defs[key]
  end

  def self.all
    @defs.values.sort_by { |d| [d.category, d.order, d.key] }
  end

  def self.by_category(cat)
    @defs.values.select { |d| d.category == cat }
                 .sort_by { |d| [d.order, d.key] }
  end

  def self.categories
    @defs.values.map(&:category).uniq.sort
  end

  def self.size
    @defs.size
  end

  # 导出 schema 为 hash (供外部 GUI 自动发现所有设置)
  def self.export_schema
    {
      "version" => 1,
      "exported_at" => Time.now.to_s,
      "categories" => categories,
      "settings" => all.map do |d|
        h = {
          "key" => d.key,
          "label" => d.label,
          "type" => d.type.to_s,
          "default" => d.default,
          "category" => d.category,
          "order" => d.order,
          "help" => d.help
        }
        h["min"] = d.min unless d.min.nil?
        h["max"] = d.max unless d.max.nil?
        h["options"] = d.options unless d.options.nil?
        h
      end
    }
  end
end

# --- JSON 存储 + 热重载 ---
module SettingStore
  # 基于脚本所在目录的绝对路径 (Scripts/../settings/)
  # 不依赖游戏工作目录, 避免相对路径导致 Dir.mkdir 崩溃
  SETTINGS_DIR = File.join(__dir__, '..', 'settings')
  RUNTIME_FILE = File.join(SETTINGS_DIR, 'runtime.json')

  @values = {}
  @last_mtime = nil
  @loaded = false

  def self.ensure_dir
    FileUtils.mkdir_p(SETTINGS_DIR) unless Dir.exist?(SETTINGS_DIR)
  end

  # 从文件加载 (不触发 apply)
  def self.load
    ensure_dir
    if File.exist?(RUNTIME_FILE)
      begin
        raw = File.read(RUNTIME_FILE, encoding: "UTF-8")
        @values = JSON.parse(raw)
        @last_mtime = File.mtime(RUNTIME_FILE)
        @loaded = true
        StatusLog.append("settings.log", "load OK: #{@values.size} keys")
      rescue StandardError => e
        StatusLog.append("settings.log", "load FAIL: #{e.message}")
        @values = {}
      end
    else
      @values = {}
      @loaded = true
      save
    end
  end

  # 保存到文件
  def self.save
    ensure_dir
    begin
      File.write(RUNTIME_FILE, JSON.pretty_generate(@values), encoding: "UTF-8")
      @last_mtime = File.mtime(RUNTIME_FILE)
      true
    rescue StandardError => e
      StatusLog.append("settings.log", "save FAIL: #{e.message}")
      false
    end
  end

  # 读取值 (无则返回 default)
  def self.get(key)
    load unless @loaded
    if @values.key?(key)
      @values[key]
    else
      def_obj = SettingRegistry.get(key)
      def_obj ? def_obj.default : nil
    end
  end

  # 设置值 + 触发 apply + 自动保存
  def self.set(key, val, persist: true)
    def_obj = SettingRegistry.get(key)
    return false unless def_obj
    return false unless def_obj.valid?(val)

    @values[key] = val
    apply(key)
    save if persist
    true
  end

  # 应用单个设置 (调用 apply_proc)
  def self.apply(key)
    def_obj = SettingRegistry.get(key)
    return unless def_obj && def_obj.apply_proc
    begin
      def_obj.apply_proc.call(get(key))
    rescue StandardError => e
      StatusLog.append("settings.log", "apply FAIL #{key}: #{e.message}")
    end
  end

  # 应用所有设置
  def self.apply_all
    SettingRegistry.all.each { |d| apply(d.key) }
  end

  # 热重载: 检测文件 mtime 变化，自动 reload + apply_all
  def self.check_reload
    return unless @loaded
    return unless File.exist?(RUNTIME_FILE)
    current_mtime = File.mtime(RUNTIME_FILE)
    return if current_mtime == @last_mtime

    StatusLog.append("settings.log", "hot-reload detected")
    old_values = @values.dup
    load
    # 只 apply 变化了的设置
    SettingRegistry.all.each do |d|
      if old_values[d.key] != @values[d.key]
        apply(d.key)
      end
    end
  end

  # 重置为默认值
  def self.reset(key)
    def_obj = SettingRegistry.get(key)
    return false unless def_obj
    set(key, def_obj.default)
  end

  def self.reset_all
    SettingRegistry.all.each { |d| reset(d.key) }
  end

  def self.values
    @values.dup
  end

  # 延迟导出 schema (第一帧调用, 此时所有设置已注册)
  @schema_exported = false
  def self.export_schema_once
    return if @schema_exported
    @schema_exported = true
    ensure_dir
    schema_path = File.join(SETTINGS_DIR, 'schema.json')
    begin
      File.write(schema_path, JSON.pretty_generate(SettingRegistry.export_schema), encoding: "UTF-8")
      StatusLog.append("settings.log", "schema exported: #{SettingRegistry.size} settings")
    rescue StandardError => e
      StatusLog.append("settings.log", "schema export FAIL: #{e.message}")
    end
  end
end

# --- 热重载补丁: Scene_Map#update 每帧检测 ---
module SettingHotReloadPatch
  def update
    SettingStore.export_schema_once
    SettingStore.check_reload
    super
  end
end

PatchHelper.install("Scene_Map", methods: [:update]) do |k|
  k.prepend(SettingHotReloadPatch)
end

# --- 初始化: 启动时加载 + apply_all ---
begin
  SettingStore.load
  SettingStore.apply_all
  StatusLog.write("settings_status.txt", [
    "registry = #{SettingRegistry.size} settings",
    "categories = #{SettingRegistry.categories.join(', ')}",
    "runtime_file = #{SettingStore::RUNTIME_FILE}",
    "loaded = #{File.exist?(SettingStore::RUNTIME_FILE)}",
    "hot_reload = Scene_Map#update patched",
    "loaded_at = #{Time.now}"
  ])
rescue StandardError => e
  StatusLog.append("settings.log", "init FAIL: #{e.message}")
end
