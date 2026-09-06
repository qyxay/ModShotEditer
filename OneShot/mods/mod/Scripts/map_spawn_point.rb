# ============================================================
#  map_spawn_point.rb — 地图落点配置
#
#  每个地图可独立配置传送到达后的落点位置。
#  与 spawn_override (新游戏出生点) 不同:
#    - spawn_override: 仅新游戏开场 (map1 ev1 -> map258) 生效, 全局一个
#    - map_spawn_point: 任何传送到达配置了落点的地图时生效, 按地图分别配置
#
#  存储: settings/map_spawn_points.json
#    {
#      "2":   {"enabled": true, "x": 18, "y": 19, "dir": 2},
#      "258": {"enabled": true, "x": 10, "y": 19, "dir": 2}
#    }
# ============================================================

require 'json'
require 'fileutils'

module MapSpawnPoint
  SETTINGS_DIR = File.join(__dir__, '..', 'settings')
  CONFIG_FILE = File.join(SETTINGS_DIR, 'map_spawn_points.json')

  @config = {}
  @last_map_id = nil

  def self.ensure_dir
    FileUtils.mkdir_p(SETTINGS_DIR) unless Dir.exist?(SETTINGS_DIR)
  end

  def self.load
    @config = {}
    if File.exist?(CONFIG_FILE)
      begin
        @config = JSON.parse(File.read(CONFIG_FILE, encoding: 'UTF-8'))
      rescue StandardError => e
        StatusLog.append("settings.log", "map_spawn load FAIL: #{e.message}")
      end
    end
  end

  def self.get(map_id)
    @config[map_id.to_s]
  end

  def self.all
    @config
  end

  # 检测传送到达新地图, 应用落点配置
  def self.check_and_apply
    return unless $game_map && $game_player
    current_map = $game_map.map_id
    if @last_map_id != current_map
      spawn = get(current_map)
      if spawn && spawn["enabled"]
        x = spawn["x"].to_i
        y = spawn["y"].to_i
        dir = spawn["dir"].to_i
        dir = 2 unless [2, 4, 6, 8].include?(dir)
        $game_player.moveto(x, y)
        $game_player.direction = dir
        # 方案A: 阻止目标地图 autorun 事件的强制移动
        PositionSync.set_skip_targets([:player], 2) if defined?(PositionSync)
        StatusLog.append("settings.log", "map_spawn apply: map#{current_map} (#{x},#{y}) dir=#{dir}")
      end
      @last_map_id = current_map
    end
  end
end

# --- Patch Scene_Map#update ---
module MapSpawnPointPatch
  def update
    MapSpawnPoint.check_and_apply
    super
  end
end

PatchHelper.install("Scene_Map", methods: [:update]) do |k|
  k.prepend(MapSpawnPointPatch)
end

MapSpawnPoint.ensure_dir
MapSpawnPoint.load
StatusLog.append("settings.log", "map_spawn_point loaded: #{MapSpawnPoint.all.size} maps configured")
