# ============================================================
#  live_sync.rb — 门连接可视化编辑器: 游戏端实时状态同步
#
#  配合 tools/door_graph_server.py + tools/door_graph.html 使用:
#    * 每帧 hook Scene_Map#update, 节流 30 帧(~0.5s)写 live_state.json:
#        当前地图 id/名称、玩家坐标方向、地图全部事件(id/name/x/y/dir)
#    * 每帧检测 event_modify.json(外部网页的修改请求), 应用后删除:
#        移动事件位置/方向到指定坐标, 并同步写 $data_maps(重载仍生效)
#
#  纯 preload 实现, 不修改游戏原始文件。
#  外部服务器按文件 mtime 轮询, 变化时经 WebSocket 推送给网页。
# ============================================================

require 'json'

module DoorGraphSync
  # 路径: Scripts/../settings (与 mod.rb 相同的 absolute_path 模式, CWD=项目根)
  SETTINGS_DIR = File.absolute_path(File.join(__dir__, '..', 'settings'))
  LIVE_PATH = File.join(SETTINGS_DIR, 'live_state.json')
  MODIFY_PATH = File.join(SETTINGS_DIR, 'event_modify.json')

  # 写文件节流帧数 (60fps 下 30 帧 = 0.5s)
  THROTTLE_FRAMES = 30

  @last_write_frame = 0
  @mapinfos = nil

  # Scene_Map#update 每帧调用
  def self.tick
    handle_modify
    fc = begin
      Graphics.frame_count
    rescue StandardError
      0
    end
    return if fc - @last_write_frame < THROTTLE_FRAMES
    @last_write_frame = fc
    write_state
  rescue StandardError
    # 同步异常不影响游戏主流程
  end

  # --- 写实时状态 ---
  def self.write_state
    map = $game_map
    return unless map && $game_player
    Dir.mkdir(SETTINGS_DIR) unless File.directory?(SETTINGS_DIR)

    evs = []
    map.events.each_value do |ev|
      next if ev.instance_variable_get(:@erased)
      evs << {
        'id' => ev.id,
        'name' => ev.name.to_s,
        'x' => ev.x,
        'y' => ev.y,
        'dir' => (ev.direction rescue 0)
      }
    end

    state = {
      'ts' => Time.now.to_f,
      'map_id' => map.map_id,
      'map_name' => map_name(map.map_id),
      'player' => {
        'x' => $game_player.x,
        'y' => $game_player.y,
        'dir' => ($game_player.direction rescue 0)
      },
      'events' => evs
    }
    File.write(LIVE_PATH, JSON.generate(state))
  end

  # 地图名(惰性加载 MapInfos)
  def self.map_name(mid)
    @mapinfos ||= begin
      load_data('Data/MapInfos.rxdata')
    rescue StandardError
      {}
    end
    info = @mapinfos[mid]
    info ? info.name.to_s : "Map#{mid}"
  end

  # --- 处理外部修改请求 ---
  def self.handle_modify
    return unless File.exist?(MODIFY_PATH)
    req = begin
      JSON.parse(File.read(MODIFY_PATH))
    rescue StandardError
      nil
    end
    File.delete(MODIFY_PATH) rescue nil
    return unless req.is_a?(Hash)
    apply_modify(req)
  end

  def self.apply_modify(req)
    map = $game_map
    return unless map
    ev = map.events[req['ev'].to_i]
    return unless ev

    if req['x'] && req['y']
      ev.moveto(req['x'].to_i, req['y'].to_i)
    end
    if req['dir'] && req['dir'].to_i.between?(2, 8)
      ev.direction = req['dir'].to_i
    end

    # 同步内存数据地图(重新加载地图/存档读取前仍生效)
    mid = (req['map'] ? req['map'].to_i : map.map_id)
    begin
      if defined?($data_maps) && $data_maps && $data_maps[mid]
        dev = $data_maps[mid].events[req['ev'].to_i]
        if dev
          dev.x = req['x'].to_i if req['x']
          dev.y = req['y'].to_i if req['y']
        end
      end
    rescue StandardError
    end
  end
end

# --- Scene_Map 每帧钩子 ---
module DoorGraphSyncPatch
  def update
    DoorGraphSync.tick
    super
  end
end

PatchHelper.install('Scene_Map', methods: [:update]) do |k|
  k.prepend(DoorGraphSyncPatch)
end

# --- 写状态文件 ---
StatusLog.write('door_graph_sync_status.txt', [
  "door_graph_sync loaded at = #{Time.now}",
  "live_state_path = #{LIVE_PATH}",
  "event_modify_path = #{MODIFY_PATH}",
  "throttle = #{THROTTLE_FRAMES} frames (~0.5s @60fps)",
  "hook = Scene_Map#update prepend (PatchHelper.install)",
  "modify = external JSON request, applied once then file deleted",
  "persist = also writes $data_maps (survives map reload)"
])
