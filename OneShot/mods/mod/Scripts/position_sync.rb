# ============================================================
#  position_sync.rb — 游戏位置同步 (供外部面板读取/传送)
#
#  - 每秒写入 settings/current_position.json (玩家当前位置)
#  - 每帧检测 settings/goto_request.json (外部面板传送请求)
#  - 检测到传送请求后执行 reserve_transfer, 并删除请求文件
# ============================================================

require 'json'
require 'fileutils'

module PositionSync
  SETTINGS_DIR = File.join(__dir__, '..', 'settings')
  CURRENT_FILE = File.join(SETTINGS_DIR, 'current_position.json')
  GOTO_FILE = File.join(SETTINGS_DIR, 'goto_request.json')

  @last_write = 0.0

  def self.ensure_dir
    FileUtils.mkdir_p(SETTINGS_DIR) unless Dir.exist?(SETTINGS_DIR)
  end

  # 写入当前位置 (节流: 每秒1次, 避免频繁IO)
  def self.write_current
    return unless $game_map && $game_player
    now = Time.now.to_f
    return if now - @last_write < 1.0
    @last_write = now

    ensure_dir
    data = {
      "map_id" => $game_map.map_id,
      "x" => $game_player.x,
      "y" => $game_player.y,
      "dir" => $game_player.direction,
      "updated_at" => Time.now.to_s
    }
    begin
      File.write(CURRENT_FILE, JSON.pretty_generate(data), encoding: "UTF-8")
    rescue StandardError => e
      StatusLog.append("settings.log", "position write FAIL: #{e.message}")
    end
  end

  # 检测传送请求 (每帧调用)
  def self.check_goto
    return unless File.exist?(GOTO_FILE)
    begin
      raw = File.read(GOTO_FILE, encoding: "UTF-8")
      req = JSON.parse(raw)
      File.delete(GOTO_FILE)  # 立即删除, 避免重复传送

      map_id = req["map_id"].to_i
      x = req["x"].to_i
      y = req["y"].to_i
      dir = req["dir"].to_i
      dir = 2 unless [2, 4, 6, 8].include?(dir)

      if $game_player && map_id > 0
        $game_player.reserve_transfer(map_id, x, y, dir)
        StatusLog.append("settings.log", "goto: map#{map_id} (#{x},#{y}) dir=#{dir}")
      end
    rescue StandardError => e
      StatusLog.append("settings.log", "goto FAIL: #{e.message}")
      File.delete(GOTO_FILE) rescue nil
    end
  end
end

# --- Patch Scene_Map#update (与 _settings_core.rb 的热重载patch共存) ---
module PositionSyncPatch
  def update
    PositionSync.write_current
    PositionSync.check_goto
    super
  end
end

PatchHelper.install("Scene_Map", methods: [:update]) do |k|
  k.prepend(PositionSyncPatch)
end
