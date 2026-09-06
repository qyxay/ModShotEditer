# ============================================================
#  position_sync.rb — 游戏位置同步 (供外部面板读取/传送)
#
#  - 每秒写入 settings/current_position.json (玩家 + 事件列表)
#  - 每帧检测 settings/goto_request.json (外部面板传送请求)
#  - 拦截 command_209 (设置移动路线): 传送后跳过指定目标的强制移动,
#    避免目标地图 autorun 事件覆盖传送位置 (方案A)
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

  # 设置 command_209 跳过目标 (存在 frames 帧)
  # targets: [:player] 或 [event_id, ...] 或混合
  def self.set_skip_targets(targets, frames = 2)
    $position_sync_skip_targets = targets
    $position_sync_skip_frame = frames
    StatusLog.append("settings.log", "skip_targets set: #{targets.inspect} for #{frames}f")
  end

  # 每帧递减 skip 帧计数, 到期清除
  def self.tick_skip
    return unless $position_sync_skip_frame
    $position_sync_skip_frame -= 1
    if $position_sync_skip_frame <= 0
      $position_sync_skip_targets = nil
      $position_sync_skip_frame = nil
    end
  end

  # 检查 command_209 目标是否应跳过
  # target: -1=玩家, 0=本事件, >0=指定事件ID
  def self.should_skip_move?(target)
    return false unless $position_sync_skip_targets
    $position_sync_skip_targets.any? do |t|
      case t
      when :player then target == -1
      when Integer then target == t
      else false
      end
    end
  end

  # 写入当前位置 (玩家 + 事件列表, 节流: 每秒1次)
  def self.write_current
    return unless $game_map && $game_player
    now = Time.now.to_f
    return if now - @last_write < 1.0
    @last_write = now

    ensure_dir
    dir_name = {2 => "下", 4 => "左", 6 => "右", 8 => "上"}

    events = []
    $game_map.events.each do |id, ev|
      next unless ev
      events << {
        "id" => id,
        "name" => ev.instance_variable_get(:@event) ? ev.instance_variable_get(:@event).name : "EV#{id}",
        "x" => ev.x,
        "y" => ev.y,
        "dir" => ev.direction,
        "dir_name" => dir_name[ev.direction] || ev.direction.to_s
      }
    end

    data = {
      "player" => {
        "map_id" => $game_map.map_id,
        "x" => $game_player.x,
        "y" => $game_player.y,
        "dir" => $game_player.direction,
        "dir_name" => dir_name[$game_player.direction] || $game_player.direction.to_s
      },
      "events" => events,
      "updated_at" => Time.now.to_s
    }
    begin
      File.write(CURRENT_FILE, JSON.pretty_generate(data), encoding: "UTF-8")
    rescue StandardError => e
      StatusLog.append("settings.log", "position write FAIL: #{e.message}")
    end
  end

  # 检测传送请求 (每帧调用)
  # 请求格式:
  #   玩家: {"target":"player", "map_id":2, "x":18, "y":19, "dir":2}
  #   事件: {"target":"event", "event_id":7, "x":20, "y":20, "dir":2}
  def self.check_goto
    return unless File.exist?(GOTO_FILE)
    begin
      raw = File.read(GOTO_FILE, encoding: "UTF-8")
      req = JSON.parse(raw)
      File.delete(GOTO_FILE)  # 立即删除, 避免重复传送

      target = req["target"] || "player"
      dir = req["dir"].to_i
      dir = 2 unless [2, 4, 6, 8].include?(dir)

      if target == "player"
        map_id = req["map_id"].to_i
        x = req["x"].to_i
        y = req["y"].to_i
        if $game_player && map_id > 0
          $game_player.reserve_transfer(map_id, x, y, dir)
          set_skip_targets([:player], 2)  # 跳过传送后 autorun 事件的玩家移动
          StatusLog.append("settings.log", "goto player: map#{map_id} (#{x},#{y}) dir=#{dir}")
        end
      elsif target == "event"
        event_id = req["event_id"].to_i
        x = req["x"].to_i
        y = req["y"].to_i
        ev = $game_map.events[event_id] if $game_map
        if ev
          ev.moveto(x, y)
          ev.direction = dir  # Game_Event 没有 set_direction, 直接赋值
          set_skip_targets([event_id], 2)  # 跳过针对该事件的移动路线
          StatusLog.append("settings.log", "goto event##{event_id}: (#{x},#{y}) dir=#{dir}")
        else
          StatusLog.append("settings.log", "goto FAIL: event##{event_id} not found")
        end
      end
    rescue StandardError => e
      StatusLog.append("settings.log", "goto FAIL: #{e.message}")
      File.delete(GOTO_FILE) rescue nil
    end
  end
end

# --- Patch Scene_Map#update ---
module PositionSyncPatch
  def update
    PositionSync.tick_skip       # 递减 skip 帧计数
    PositionSync.write_current   # 写入位置 (节流)
    PositionSync.check_goto      # 检测传送请求
    super
  end
end

PatchHelper.install("Scene_Map", methods: [:update]) do |k|
  k.prepend(PositionSyncPatch)
end

# --- Patch Game_Interpreter#command_209 (方案A: 拦截设置移动路线) ---
module PositionSyncCommand209Patch
  def command_209
    target = @parameters[0]
    if PositionSync.should_skip_move?(target)
      StatusLog.append("settings.log", "command_209 skipped: target=#{target}")
      @index += 1
      return true
    end
    super
  end
end

PatchHelper.install("Interpreter", methods: [:command_209]) do |k|
  k.prepend(PositionSyncCommand209Patch)
end
