# ============================================================
#  settings_register.rb — 注册现有设置到运行时设置系统
#
#  新增设置只需在此文件 register 一行，GUI 和存储自动适配。
#  示例: 注册 spawn_override (自设出生位置) 的 5 个设置项。
# ============================================================

# --- spawn_override 注册 ---
SettingRegistry.register(SettingDef.new(
  key: "spawn.enabled",
  label: "启用自设出生点",
  type: :bool,
  default: false,
  category: "spawn",
  order: 10,
  help: "开启后覆盖新游戏开场传送位置",
  apply_proc: ->(val) { $spawn_override_enabled = val }
))

SettingRegistry.register(SettingDef.new(
  key: "spawn.map_id",
  label: "目标地图 ID",
  type: :int,
  default: 258,
  min: 1,
  max: 300,
  category: "spawn",
  order: 20,
  help: "传送目标地图 (1-300)",
  apply_proc: ->(val) { $spawn_override_map_id = val }
))

SettingRegistry.register(SettingDef.new(
  key: "spawn.x",
  label: "X 坐标",
  type: :int,
  default: 10,
  min: 0,
  max: 60,
  category: "spawn",
  order: 30,
  apply_proc: ->(val) { $spawn_override_x = val }
))

SettingRegistry.register(SettingDef.new(
  key: "spawn.y",
  label: "Y 坐标",
  type: :int,
  default: 19,
  min: 0,
  max: 80,
  category: "spawn",
  order: 40,
  apply_proc: ->(val) { $spawn_override_y = val }
))

SettingRegistry.register(SettingDef.new(
  key: "spawn.dir",
  label: "朝向",
  type: :enum,
  default: 2,
  options: [[2, "下"], [4, "左"], [6, "右"], [8, "上"]],
  category: "spawn",
  order: 50,
  apply_proc: ->(val) { $spawn_override_dir = val }
))

StatusLog.append("settings.log",
  "register OK: #{SettingRegistry.size} settings, categories=#{SettingRegistry.categories.join(',')}")
