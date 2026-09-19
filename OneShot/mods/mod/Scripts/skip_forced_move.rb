# ============================================================
#  skip_forced_move.rb — 跳过所有强制移动路线
#
#  开发者功能: 开启后, 任何 Game_Event / Game_Player 的强制
#  移动路线 (move_route_forcing) 都会被立即跳过——事件不执行
#  任何移动命令, move_route 直接释放回原始路线。
#
#  用途: 快速测试剧情, 跳过"事件慢慢走到门口"之类的过场动画。
#  注意: 事件位置不变, 如果剧情后续逻辑依赖事件走到某格,
#        可能会出问题 (这是开发者功能, 自行承担)。
#
#  配置: mods/mod/config.json
#    "skip_forced_move": false → 初始关闭
# ============================================================

require 'json'

default_config = { "skip_forced_move" => false }
config = default_config.merge($mod_config || {})
$skip_forced_move = config["skip_forced_move"] ? true : false

SKIP_CONFIG_PATH = File.join(__dir__, '..', 'config.json')

# ============================================================
#  配置读写
# ============================================================
module SkipForcedMove
  def self.save_config
    $mod_config ||= {}
    $mod_config['skip_forced_move'] = $skip_forced_move
    ordered = {}
    %w[skip_pictures quit_all_time skip_dialogue skip_choice skip_uneasy always_travel always_settings unshow_title is_developer fly_mode live_update skip_forced_move].each do |k|
      ordered[k] = $mod_config[k] if $mod_config.key?(k)
    end
    $mod_config.each do |k, v|
      ordered[k] = v unless ordered.key?(k)
    end
    File.write(SKIP_CONFIG_PATH, JSON.pretty_generate(ordered) + "\n")
  rescue StandardError
  end
end

# ============================================================
#  Game_Character 补丁: 跳过强制移动路线
#
#  move_type_custom 在每帧被调用, 处理 move_route 命令列表。
#  当 $skip_forced_move 开启且 @move_route_forcing=true 时,
#  直接把 index 跳到列表末尾, 并释放强制路线——等价于"所有移动
#  命令都已执行完毕", 事件位置不变。
# ============================================================
module SkipForcedMovePatch
  def move_type_custom
    if $skip_forced_move && @move_route_forcing
      # 跳过所有移动命令: index 直接到列表末尾
      @move_route_index = @move_route.list.size
      # 释放强制移动路线 (与原版 code=0 分支相同)
      @move_route_forcing = false
      @move_route = @original_move_route
      @move_route_index = @original_move_route_index
      @original_move_route = nil
      @stop_count = 0
      return
    end
    super
  end
end

# --- 等待类定义完成后 prepend 补丁 ---
PatchHelper.install('Game_Character', methods: [:move_type_custom]) do |k|
  k.prepend(SkipForcedMovePatch)
end

# --- 写状态文件 ---
StatusLog.write('skip_forced_move_status.txt', [
  "skip_forced_move loaded at = #{Time.now}",
  "skip_forced_move_enabled = #{$skip_forced_move} (initial from config)",
  "behavior = when enabled, forced move routes are skipped entirely (event stays in place, route released immediately)",
  "patches = Game_Character#move_type_custom"
])
