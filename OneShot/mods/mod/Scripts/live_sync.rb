# ============================================================
#  live_sync.rb — 门连接可视化编辑器: 游戏端实时状态同步
#
#  配合 tools/door_graph_server.py + tools/door_graph.html 使用:
#    * 每帧 hook Scene_Map#update, 节流 30 帧(~0.5s)写 live_state.json:
#        当前地图 id/名称、玩家坐标方向、地图全部事件(id/name/x/y/dir)
#    * 输出动态传送引用变量的当前值(vars): 前端把"动态目标"解析为实际地图
#
#  (事件位置修改功能已移除: 游戏内 event_editor.rb 与网页 /move 均已取消)
#
#  纯 preload 实现, 不修改游戏原始文件。
#  外部服务器按文件 mtime 轮询, 变化时经 WebSocket 推送给网页。
# ============================================================

require 'json'

module DoorGraphSync
  # 路径: Scripts/../settings (与 mod.rb 相同的 absolute_path 模式, CWD=项目根)
  SETTINGS_DIR = File.absolute_path(File.join(__dir__, '..', 'settings'))
  LIVE_PATH = File.join(SETTINGS_DIR, 'live_state.json')
  GRAPH_PATH = File.join(SETTINGS_DIR, 'graph.json')

  # 写文件节流帧数 (60fps 下 30 帧 = 0.5s)
  THROTTLE_FRAMES = 30

  @last_write_frame = 0
  @mapinfos = nil
  @dyn_vars = nil   # 动态传送引用的变量 id 数组

  # Scene_Map#update 每帧调用
  def self.tick
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

  # --- 动态传送引用的变量 (从 graph.json 提取, 惰性) ---
  def self.dyn_vars
    @dyn_vars ||= begin
      ids = []
      if File.exist?(GRAPH_PATH)
        g = JSON.parse(File.read(GRAPH_PATH))
        (g['doors'] || []).each do |d|
          (d['targets'] || []).each do |t|
            ids.concat(t['var_ids']) if t['dynamic'] && t['var_ids']
          end
        end
      end
      ids.uniq.sort
    rescue StandardError
      [6, 7, 8]
    end
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

    vars = {}
    dyn_vars.each do |vid|
      vars[vid.to_s] = $game_variables[vid]
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
      'vars' => vars,
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
  "throttle = #{THROTTLE_FRAMES} frames (~0.5s @60fps)",
  "hook = Scene_Map#update prepend (PatchHelper.install)",
  "dyn_vars = #{dyn_vars.inspect} (dynamic transfer vars synced to live_state)",
  "event_edit = REMOVED (event_editor.rb + /move 已取消)"
])
