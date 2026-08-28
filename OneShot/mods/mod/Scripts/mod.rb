# ============================================================
#  mod.rb — ModShot preload 脚本 (在游戏主脚本之前执行)
#  位置: OneShot/mods/mod/Scripts/mod.rb  (由 modshot.json 的 preloadScript 指定)
#
#  【方案C】Solstice(至日线)解锁:
#    原理(逆向自解包脚本 + System.rxdata 开关名称表):
#      - p-settings.dat 存放 perma_flags(开关151~175)/perma_vars(变量76~100)/player_name
#      - 开关152 = "Beat the game once"(通关过一次) → Map001 INIT 判定
#        152=false → 新游戏从 Map258(Memory) 一周目开场
#        152=true  → 新游戏直接"床醒来"进 Map2(Start) = 二周目/Solstice 线
#      - 开关154 = "Saved world once"(放太阳结局)  开关160 = "Beat Solstice"(通至日)
#      - save_progress.oneshot(假存档) 存在与否影响结局后的冻结/继续逻辑
#    本脚本启动时把 152/154/160 置位并删假存档, 模拟"一周目+二周目均已通关", 从而:
#      - 新游戏直接从"床醒来"进二周目(至日线)
#      - 标题出现 "..." 记忆菜单(需 160&&152, 点它进 Last room 记忆场景)
#      - niko 立绘切换为"记忆"形态(0000_RPG.rb 中 160 控制)
# ============================================================

begin
  # ---- 路径(ModShot 运行时 Oneshot::SAVE_PATH=%APPDATA%\Oneshot, GAME_PATH=文档\My Games\Oneshot) ----
  save_path = if defined?(Oneshot) && Oneshot.const_defined?(:SAVE_PATH)
                Oneshot::SAVE_PATH
              else
                File.join(ENV['APPDATA'].to_s, 'Oneshot')
              end
  game_path = if defined?(Oneshot) && Oneshot.const_defined?(:GAME_PATH)
                Oneshot::GAME_PATH
              else
                File.join(Dir.home, 'Documents', 'My Games', 'Oneshot')
              end
  pset = File.join(save_path, 'p-settings.dat')

  # ---- 1) 读取现有永久标志(若已存在则保留玩家进度/名字) ----
  perma_flags = Array.new(25, false)
  perma_vars  = Array.new(25, 0)
  player_name = 'Niko'
  if File.exist?(pset)
    File.open(pset, 'rb') do |f|
      perma_flags = Marshal.load(f)
      perma_vars  = Marshal.load(f)
      player_name = Marshal.load(f)
    end
  end

  # ---- 2) 置位 Solstice 关键开关 ----
  perma_flags[152 - 151] = true   # 152 "Beat the game once" → 二周目入口(核心)
  perma_flags[154 - 151] = true   # 154 "Saved world once"  → 放太阳结局(前置)
  perma_flags[160 - 151] = true   # 160 "Beat Solstice"     → 直接完成2周目(至日线通关标记)
  # perma_flags[153 - 151] = true # (可选)153 "Smashed bulb once"

  # ---- 3) 写回 p-settings.dat(格式与原版 write_perma_flags 完全一致) ----
  Dir.mkdir(save_path) unless File.exist?(save_path)
  File.open(pset, 'wb') do |f|
    Marshal.dump(perma_flags, f)
    Marshal.dump(perma_vars, f)
    Marshal.dump(player_name, f)
  end

  # ---- 4) 删假存档(模拟"通关后删档", 使结局判定走二周目分支) ----
  fake = File.join(game_path, 'Oneshot', 'save_progress.oneshot')
  fake_deleted = File.exist?(fake)
  File.delete(fake) if fake_deleted

  # ---- 5) 验证标记 + 原验证功能保留 ----
  File.open(File.join(__dir__, 'solstice_unlocked.txt'), 'w') do |f|
    f.puts "OK #{Time.now}"
    f.puts "sw152(Beat game once)=#{perma_flags[1]}  sw154(Saved world)=#{perma_flags[3]}  sw160(Beat Solstice)=#{perma_flags[9]}"
    f.puts "pset=#{pset}"
    f.puts "fake_save_deleted=#{fake_deleted}"
  end

  File.open("mod_loaded.txt", "w") do |f|
    f.puts "mod loaded at #{Time.now}"
    f.puts "Platform: #{System.platform}  Language: #{System.user_language}"
  end
  System.set_window_title("OneShot [mod]")

rescue Exception => e
  File.open(File.join(__dir__, 'solstice_error.txt'), 'w') do |f|
    f.puts e.full_message
  end
end
