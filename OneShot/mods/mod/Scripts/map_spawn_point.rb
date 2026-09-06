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
  @last_reload = 0.0

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

  # 热重载: 每 1 秒重新读取配置文件, 面板修改后立即生效
  def self.reload_if_needed
    now = Time.now.to_f
    if now - @last_reload > 1.0
      load
      @last_reload = now
    end
  end

  def self.get(map_id)
    reload_if_needed
    @config[map_id.to_s]
  end

  def self.all
    reload_if_needed
    @config
  end
end

MapSpawnPoint.ensure_dir
MapSpawnPoint.load
StatusLog.append("settings.log", "map_spawn_point loaded: #{MapSpawnPoint.all.size} maps configured (goto-only mode)")
