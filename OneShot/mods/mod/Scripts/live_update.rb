# ============================================================
#  live_update.rb — 实时更新模式: 地图热重载 + 障碍物自动飞行
#
#  用途:
#    在 RMXP 工程里改图并保存后(经"一键同步补丁Data.bat"或
#    "启动自动同步.bat"进入补丁 Data), 游戏内轮询当前地图的
#    Data/Map%03d.rxdata(引擎会解析到补丁覆盖文件), 检测到变化
#    即热重载当前地图(不传送玩家), 并自动处理碰撞:
#      * 重载后/任意时刻, 玩家若站在障碍物上(脚下四向全不可通行
#        或超出地图边界) → 进入 fly 模式(@through=true, 穿墙可走)
#      * 走出障碍物(脚下任一方向可通行) → 恢复进入前的基准模式
#        (基准 = config 的 fly_mode: true=常驻飞行, false=正常)
#
#  性能设计 (事件驱动, 双冗余, 不做地图文件轮询):
#    外部同步脚本(一键同步补丁Data.bat / 启动自动同步.bat)在
#    robocopy 同步完成后, 向 settings\map_update.signal 写入
#    信号(时间戳 + 变化的地图 id 列表, 或 ALL)。
#    游戏内每 5 帧(~83ms)查一次信号文件(File.mtime+size, O(1),
#    真实磁盘路径, 不依赖虚拟 FS), 信号变了才 load_data 重载
#    对应地图; 另外每 0.5s 做一次地图文件元数据兜底自检
#    (同样 O(1)), 信号机制失效时仍能秒级响应。
#    重载失败保留旧游标自动重试。
#
#  配置: mods/mod/config.json
#    "live_update": true|false   总开关(实时更新 + 自动飞行一并生效)
#    "fly_mode":    true|false   手动常驻飞行(与自动飞行叠加)
#
#  安全机制:
#    * 事件/对话/菜单/传送进行中不重载(等空闲)
#    * 重载后该地图会话内抑制 autorun(trigger3) 与 parallel(trigger4)
#      自动启动 —— map1 ev1 开场等演出不会被重放; 重载前在跑的
#      parallel 事件在抑制窗口结束后按原事件 id 恢复
#    * 重载后玩家坐标越界自动钳制回地图内, 镜头重新居中
#    * 保留 erased 事件状态与地图定制(bg/particles/ambient/wrap)
#    * 任何异常吞掉, 不影响游戏主流程
#
#  限制: 重载过的地图, 其 autorun/parallel 需离开地图(传送/跳图)
#        或重启游戏后才恢复自动执行。
#
#  纯 preload 实现, 不修改游戏原始文件。
# ============================================================

# --- 读取 config (统一由 _config.rb 加载到 $mod_config) ---
$live_update_enabled = ($mod_config && $mod_config['live_update']) ? true : false
$fly_mode_enabled    = ($mod_config && $mod_config['fly_mode']) ? true : false

module LiveUpdate
  SUPPRESS_FRAMES = 40        # 重载后抑制自动触发窗口(帧), ~0.67s
  SIGNAL_POLL_FRAMES = 5      # 信号文件检测间隔(帧), ~83ms
  FALLBACK_CHECK_FRAMES = 30  # 兜底地图文件自检间隔(帧), 0.5s
  # 信号文件真实磁盘路径(不依赖虚拟 FS 相对路径解析, 与 fly_mode.rb 写 config 同理)
  SIGNAL_PATH = File.join(File.dirname(__FILE__), '..', 'settings', 'map_update.signal')

  @last_map_id = nil
  @last_map_sig = nil
  @fly = false                # 是否处于自动飞行状态
  @suppress_until = 0         # 短窗口截止帧
  @suppress_map = nil         # 本次热重载的地图 id(该会话内抑制自动事件)
  @resume_parallel = []       # 重载前在跑的 parallel 事件 id
  @use_mtime = nil            # nil=未探测; true=File.mtime 可用(快速模式); false=回退内容对比
  @meta_mtime = nil           # 最近一次成功重载后的文件 mtime
  @meta_size = nil            # 最近一次成功重载后的文件 size
  @last_sig_frame = 0         # 上次信号检测帧
  @last_map_check_frame = 0   # 上次兜底自检帧
  @sig_mode = nil             # nil=未探测; :meta=File.mtime+size; :read=内容对比
  @sig_mtime = nil            # 信号游标(meta 模式)
  @sig_size = nil
  @sig_content = nil          # 信号游标(read 模式)

  def self.enabled?
    $live_update_enabled
  end

  def self.fly?
    @fly
  end

  def self.suppress_map?
    @suppress_map && @suppress_map == ($game_map ? $game_map.map_id : nil)
  end

  # 自动触发抑制判定: 重载过的地图会话内一律抑制; 另加短窗口
  def self.suppress_auto?
    return true if suppress_map?
    fc = begin
      Graphics.frame_count
    rescue StandardError
      0
    end
    fc < @suppress_until
  end

  # --- 每帧钩子 (Scene_Map#update prepend) ---
  def self.tick
    return unless enabled?
    map = $game_map
    player = $game_player
    return unless map && player && map.map_id.to_i > 0

    fc = begin
      Graphics.frame_count
    rescue StandardError
      0
    end

    # 换图(传送/读档/初始): 重置基线, 不重载
    if @last_map_id != map.map_id
      @last_map_id = map.map_id
      @last_map_sig = current_sig(map)
      refresh_meta(map)
      probe_signal_baseline # 启动/换图后首轮: 探测信号并记游标(不重载)
      @suppress_map = nil
      @resume_parallel = []
      if @fly
        @fly = false
        set_player_through(player, $fly_mode_enabled ? true : false)
      end
      return
    end

    # 忙时不重载(事件/对话/菜单/传送/移动中), 下次空闲再检测
    return if busy?(map, player)

    # 主通道: 外部同步信号文件 (bat / watch 同步完成后写入)
    if fc - @last_sig_frame >= SIGNAL_POLL_FRAMES
      @last_sig_frame = fc
      if signal_changed?(map)
        reload_map(map, player)
        consume_signal # 重载成功后更新游标; 失败则保留旧游标自动重试
      end
    end

    # 兜底: 低频自检地图文件 (信号机制失效时仍能工作)
    if fc - @last_map_check_frame >= FALLBACK_CHECK_FRAMES
      @last_map_check_frame = fc
      reload_map(map, player) if map_changed?(map)
    end

    # 恢复重载前在跑的 parallel 事件(抑制窗口结束后)
    resume_parallel_if_due

    # 飞行状态机: 障碍物上飞行, 走出恢复基准
    update_fly_mode(map, player)
  end

  # --- 忙判定: 真时跳过本轮检测 ---
  def self.busy?(map, player)
    return true if $game_temp && $game_temp.player_transferring
    return true if $game_temp && $game_temp.message_window_showing
    return true if $game_temp && $game_temp.menus_visible
    return true if player && player.moving?
    return true if $game_system && $game_system.map_interpreter &&
                   $game_system.map_interpreter.running?
    false
  rescue StandardError
    true # 保守: 异常时视为忙
  end

  # --- 当前内存地图的签名(Marshal 序列化, 与磁盘文件对比用) ---
  def self.current_sig(map)
    m = map.instance_variable_get(:@map)
    m ? Marshal.dump(m) : nil
  end

  # --- 补丁侧地图文件的真实磁盘路径 (用于 File.mtime/size 检测) ---
  # 说明: File 的 mtime/size/read 用真实路径(必然可用); load_data 仍用
  # 虚拟 FS 相对路径(由引擎 patches 解析到补丁覆盖层, 游戏 API 保证)。
  def self.map_file_path(mid)
    File.join(File.dirname(__FILE__), '..', 'Data', format('Map%03d.rxdata', mid))
  end

  # --- 兜底: 当前地图文件是否变化 (每 FALLBACK_CHECK_FRAMES 调用一次) ---
  # 优先 File.mtime + File.size (真实路径, O(1)); 若异常回退 load_data
  # + Marshal.dump 内容对比。记录只在 reload_map 成功后刷新。
  def self.map_changed?(map)
    mid = map.map_id
    real = map_file_path(mid)
    vpath = sprintf('Data/Map%03d.rxdata', mid)
    if @use_mtime.nil?
      begin
        @meta_mtime = File.mtime(real)
        @meta_size = File.size(real)
        @use_mtime = true
        StatusLog.append('live_update_trace.log', 'fallback detector = File.mtime+size (0.5s)')
        # 首轮补一次内容对比, 覆盖"进入检测前文件已被同步"的情况
        new_map = load_data(vpath)
        return true if Marshal.dump(new_map) != @last_map_sig
        return false
      rescue StandardError
        @use_mtime = false
        StatusLog.append('live_update_trace.log', 'fallback detector = load_data+Marshal.dump (0.5s)')
      end
    end
    if @use_mtime
      begin
        mt = File.mtime(real)
        sz = File.size(real)
        return true if mt != @meta_mtime || sz != @meta_size
        return false
      rescue StandardError
        @use_mtime = false # 探测失败, 永久降级为内容对比
      end
    end
    new_map = load_data(vpath)
    Marshal.dump(new_map) != @last_map_sig
  rescue StandardError
    false
  end

  # --- 记录当前地图文件元数据基线 (换图/重载成功后调用; 失败则不动) ---
  def self.refresh_meta(map)
    return unless @use_mtime == true
    begin
      @meta_mtime = File.mtime(map_file_path(map.map_id))
      @meta_size = File.size(map_file_path(map.map_id))
    rescue StandardError
    end
  end

  # --- 启动/换图后首轮: 探测信号检测模式并记游标(不重载) ---
  # 避免"启动时残留信号"被误判为变化而重载(会打断刚进图的开场演出)
  def self.probe_signal_baseline
    return unless @sig_mode.nil?
    begin
      @sig_mtime = File.mtime(SIGNAL_PATH)
      @sig_size = File.size(SIGNAL_PATH)
      @sig_mode = :meta
      StatusLog.append('live_update_trace.log', 'signal detector = File.mtime+size (fast)')
    rescue StandardError
      @sig_mode = :read
      begin
        @sig_content = File.read(SIGNAL_PATH)
        StatusLog.append('live_update_trace.log', 'signal detector = File.read content (fallback)')
      rescue StandardError
        @sig_content = nil # 信号文件暂不存在, 运行中出现时视为变化
      end
    end
  end

  # --- 主通道: 信号文件是否变化且命中当前地图 ---
  # 信号由外部同步脚本在 robocopy 完成后写入 settings\map_update.signal,
  # 内容: 行1=时间戳, 行2=变化的 map id 列表(逗号分隔) 或 ALL。
  # 检测优先 File.mtime+size(O(1)); 不可用则读几字节内容对比(同样 O(1))。
  def self.signal_changed?(map)
    if @sig_mode.nil?
      probe_signal_baseline # 兜底: 理论上 baseline 已探测, 此处防御
    end
    if @sig_mode == :meta
      begin
        mt = File.mtime(SIGNAL_PATH)
        sz = File.size(SIGNAL_PATH)
        return signal_target?(map) if mt != @sig_mtime || sz != @sig_size
        return false
      rescue StandardError
        @sig_mode = :read # 探测失败, 降级为内容对比
      end
    end
    begin
      c = File.read(SIGNAL_PATH)
      if @sig_content.nil?
        @sig_content = c
        return signal_target?(map) # 信号文件首次出现(运行中): 视为变化
      end
      c != @sig_content && signal_target?(map)
    rescue StandardError
      false
    end
  end

  # --- 信号内容是否命中当前地图 (解析失败保守返回 true) ---
  def self.signal_target?(map)
    content = begin
      File.read(SIGNAL_PATH)
    rescue StandardError
      nil
    end
    return true if content.nil? || content.empty?
    lines = content.to_s.split("\n")
    tag = lines.size >= 2 ? lines[1].to_s.strip : ''
    return true if tag.empty? || tag == 'ALL'
    tag.split(',').map { |s| s.to_i }.include?(map.map_id)
  rescue StandardError
    true
  end

  # --- 消费信号: 重载成功后更新游标 (失败则不更新, 自动重试) ---
  def self.consume_signal
    if @sig_mode == :meta
      begin
        @sig_mtime = File.mtime(SIGNAL_PATH)
        @sig_size = File.size(SIGNAL_PATH)
      rescue StandardError
      end
    else
      begin
        @sig_content = File.read(SIGNAL_PATH)
      rescue StandardError
      end
    end
  end

  # --- 热重载当前地图 ---
  def self.reload_map(map, player)
    mid = map.map_id
    px = player.x
    py = player.y

    # 记录重载前状态
    saved_extra = {
      bg: map.bg_name,
      particles: map.particles_type,
      ambient: map.ambient,
      wrap: map.wrapping,
      pan_y: map.pan_offset_y
    }
    erased_ids = []
    map.events.each_value { |ev| erased_ids << ev.instance_variable_get(:@id) if ev.instance_variable_get(:@erased) }
    resume_ids = []
    map.events.each_value do |ev|
      begin
        ip = ev.instance_variable_get(:@interpreter)
        resume_ids << ev.instance_variable_get(:@id) if ev.trigger == 4 && ip && ip.running?
      rescue StandardError
      end
    end

    # 抑制窗口先于 setup: 事件在 setup 内创建并 refresh/自动触发
    @suppress_until = (begin
      Graphics.frame_count
    rescue StandardError
      0
    end) + SUPPRESS_FRAMES
    @suppress_map = mid

    $game_map.setup(mid)

    # 钳制玩家坐标(地图可能缩小)并重新居中
    px = [[px, 0].max, $game_map.width - 1].min
    py = [[py, 0].max, $game_map.height - 1].min
    player.moveto(px, py)

    # 恢复地图定制
    begin
      map.bg_name = saved_extra[:bg]
      map.particles_type = saved_extra[:particles]
      map.ambient = saved_extra[:ambient]
      map.wrapping = saved_extra[:wrap]
      map.pan_offset_y = saved_extra[:pan_y]
    rescue StandardError
    end

    # 恢复 erased 事件
    erased_ids.each do |id|
      ev = $game_map.events[id]
      ev.instance_variable_set(:@erased, true) if ev
    end

    # 重建精灵组(复刻 Scene_Map#transfer_player 模式)
    scene = $scene
    if scene && scene.is_a?(Scene_Map)
      begin
        sp = scene.instance_variable_get(:@spriteset)
        sp.dispose if sp
        scene.instance_variable_set(:@spriteset, Spriteset_Map.new)
        scene.instance_variable_get(:@spriteset).update
      rescue StandardError
      end
    end

    # 刷新事件页状态(parallel 解释器由补丁在抑制窗口内清除)
    begin
      map.refresh if map.respond_to?(:refresh)
    rescue StandardError
    end

    @resume_parallel = resume_ids
    @last_map_sig = current_sig(map)
    # 重载成功后刷新元数据记录(防止下轮再次触发; 失败则保留旧记录自动重试)
    refresh_meta(map)

    StatusLog.append('live_update_trace.log',
                     "RELOAD map=#{mid} pos=#{px},#{py} erased=#{erased_ids.size} resume_parallel=#{resume_ids.inspect}")
  end

  # --- 恢复重载前在跑的 parallel 事件(窗口结束后执行一次) ---
  def self.resume_parallel_if_due
    return if @resume_parallel.empty?
    fc = begin
      Graphics.frame_count
    rescue StandardError
      0
    end
    return if fc < @suppress_until
    done = []
    @resume_parallel.each do |id|
      begin
        ev = $game_map.events[id]
        if ev.nil? || ev.trigger != 4
          done << id
        elsif ev.instance_variable_get(:@interpreter).nil? && ev.list && ev.list.size > 1
          ip = Interpreter.new
          ip.setup(ev.list, ev.instance_variable_get(:@id))
          ev.instance_variable_set(:@interpreter, ip)
          done << id
        end
      rescue StandardError
        done << id
      end
    end
    @resume_parallel -= done
    StatusLog.append('live_update_trace.log', "RESUME parallel restored=#{done.inspect}") if done.any?
  end

  # --- 飞行状态机 ---
  def self.update_fly_mode(map, player)
    if $fly_mode_enabled
      # 手动飞行(Ctrl+F)接管: 复位自动飞行状态, 不做干预
      @fly = false if @fly
      return
    end
    base = false # 手动飞行关闭时的恢复基准
    if @fly
      set_player_through(player, true)
      unless tile_obstructed?(map, player)
        @fly = false
        set_player_through(player, base)
        StatusLog.append('live_update_trace.log', "FLY OFF (restored base=#{base})")
      end
    else
      if tile_obstructed?(map, player)
        @fly = true
        set_player_through(player, true)
        StatusLog.append('live_update_trace.log', 'FLY ON (player on obstacle)')
      elsif player.through != base
        set_player_through(player, base)
      end
    end
  end

  # --- 玩家是否站在障碍物上: 出界 或 四向全不可通行 ---
  def self.tile_obstructed?(map, player)
    x = player.x
    y = player.y
    return true unless map.valid?(x, y)
    [2, 4, 6, 8].all? { |d| !map.passable?(x, y, d, player) }
  end

  # --- 设置玩家 @through (Game_Character 只有 attr_reader, 直接写实例变量) ---
  def self.set_player_through(player, val)
    player.instance_variable_set(:@through, val ? true : false)
  end
end

# --- Scene_Map 每帧钩子 ---
module LiveUpdateScenePatch
  def update
    begin
      LiveUpdate.tick
    rescue StandardError
      # 实时更新异常不影响主流程
    end
    super
    # 同步飞行徽标: 手动飞行或自动飞行(站上障碍物)时都显示
    begin
      $fly_mode_indicator.visible = $fly_mode_enabled || LiveUpdate.fly? if $fly_mode_indicator
    rescue StandardError
    end
  end
end

# --- 事件补丁: 热重载地图会话内抑制自动启动 ---
module LiveUpdateEventAutoPatch
  def check_event_trigger_auto
    return if LiveUpdate.suppress_auto?
    super
  end
end

# --- 事件补丁: 清除 setup 期间创建的 parallel 解释器(会话内抑制) ---
module LiveUpdateEventRefreshPatch
  def refresh
    super
    if LiveUpdate.suppress_map? && @trigger == 4 && @interpreter
      begin
        @interpreter.clear if @interpreter.respond_to?(:clear)
        @interpreter = nil
      rescue StandardError
      end
    end
  end
end

PatchHelper.install('Scene_Map', methods: [:update]) do |k|
  k.prepend(LiveUpdateScenePatch)
end

PatchHelper.install('Game_Event', methods: [:check_event_trigger_auto]) do |k|
  k.prepend(LiveUpdateEventAutoPatch)
end

PatchHelper.install('Game_Event', methods: [:refresh]) do |k|
  k.prepend(LiveUpdateEventRefreshPatch)
end

# --- 写状态文件 ---
StatusLog.write('live_update_status.txt', [
  "live_update loaded at = #{Time.now}",
  "live_update_enabled = #{$live_update_enabled} (config live_update)",
  "fly_mode_enabled = #{$fly_mode_enabled} (config fly_mode, manual always-fly base)",
  "signal = mods/mod/settings/map_update.signal (real path), written by sync scripts after robocopy; polled every 5 frames O(1)",
  "detector = File.mtime+size on real paths (no VFS dependence); 0.5s map self-check as safety net; load_data fallback retained",
  "reload = load_data current map, hot setup + spriteset rebuild (transfer_player pattern), only on signal hit or fallback change",
  "fly = player on obstacle (4-dir blocked / out of bounds) -> @through=true; exit -> restore base",
  "suppress = autorun(3)/parallel(4) auto-start off for the reloaded map session; pre-reload parallel resumed by id after window",
  "busy_guard = event/message/menu/transfer/moving -> skip this poll",
  "hook = Scene_Map#update, Game_Event#check_event_trigger_auto, Game_Event#refresh (PatchHelper.install)"
])
