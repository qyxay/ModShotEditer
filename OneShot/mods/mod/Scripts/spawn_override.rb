# ============================================================
#  spawn_override.rb — 自设 niko 出生位置和方向
#
#  新游戏流程: map1 ev1(idx22) 201 传送 → map258 (10,20) dir=2
#  本脚本拦截该传送, 若 config 配置了 spawn_override.enabled,
#  覆盖传送目标的 map_id/x/y/dir。
#
#  配置 (mods/mod/config.json):
#    "spawn_override": {
#      "enabled": false,
#      "map_id": 258,
#      "x": 10,
#      "y": 19,
#      "dir": 2
#    }
#
#  dir: 2=下, 4=左, 6=右, 8=上
# ============================================================

# --- 读取配置 ---
default_spawn = {
  "enabled" => false,
  "map_id" => 258,
  "x" => 10,
  "y" => 19,
  "dir" => 2
}
spawn_cfg = default_spawn.merge(($mod_config || {})["spawn_override"] || {})

$spawn_override_enabled = spawn_cfg["enabled"] ? true : false
$spawn_override_map_id  = spawn_cfg["map_id"].to_i
$spawn_override_x       = spawn_cfg["x"].to_i
$spawn_override_y       = spawn_cfg["y"].to_i
$spawn_override_dir     = spawn_cfg["dir"].to_i

# --- 拦截 Interpreter#command_201 (传送玩家) ---
module SpawnOverridePatch
  def command_201
    # 仅拦截: map1 ev1 (init 事件) + 传送目标为 map258 (新游戏开场)
    if $spawn_override_enabled &&
       $game_map && $game_map.map_id == 1 &&
       @event_id == 1 &&
       @parameters[0] == 0 &&  # 直接指定
       @parameters[1] == 258   # 原目标 map258
      # 覆盖传送目标
      @parameters[1] = $spawn_override_map_id
      @parameters[2] = $spawn_override_x
      @parameters[3] = $spawn_override_y
      @parameters[4] = $spawn_override_dir  # 方向
      StatusLog.append('spawn_override.log',
        "override map1 ev1 201: map258(10,20) → map#{$spawn_override_map_id}(#{$spawn_override_x},#{$spawn_override_y}) dir=#{$spawn_override_dir}")
      super
      # 方案A: 传送后跳过 autorun 事件的玩家移动路线, 避免覆盖出生位置
      PositionSync.set_skip_targets([:player], 2) if defined?(PositionSync)
      return
    end
    super
  end
end

PatchHelper.install('Interpreter', methods: [:command_201]) do |k|
  k.prepend(SpawnOverridePatch)
end

# --- 写状态文件 ---
StatusLog.write('spawn_override_status.txt', [
  "enabled = #{$spawn_override_enabled}",
  "target = map#{$spawn_override_map_id} (#{$spawn_override_x}, #{$spawn_override_y}) dir=#{$spawn_override_dir}",
  "trigger = map1 ev1 command_201 (原目标 map258)",
  "config_source = $mod_config.spawn_override",
  "loaded_at = #{Time.now}"
])
