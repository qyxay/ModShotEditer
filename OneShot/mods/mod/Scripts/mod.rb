# ============================================================
#  mod.rb — ModShot preload 脚本 (在游戏主脚本之前执行)
#  位置: OneShot/mods/mod/Scripts/mod.rb  (由 modshot.json 的 preloadScript 指定)
#  这是你的"写代码"入口: 游戏启动前会先跑这里, 可随意改逻辑
# ============================================================

begin
  # 1) 写标记文件 — 硬证据证明脚本执行了 (会出现在 OneShot 游戏目录)
  File.open("mod_loaded.txt", "w") do |f|
    f.puts "mod loaded at #{Time.now}"
    f.puts "Platform: #{System.platform}  Language: #{System.user_language}"
  end

  # 2) 改窗口标题 — 肉眼可见的 mod 生效证据
  System.set_window_title("OneShot [mod]")

  # 3) OneShot 专属 API 演示 (只读)
  File.open("mod_loaded.txt", "a") do |f|
    f.puts "data_directory = #{System.data_directory}"
  end
rescue Exception => e
  File.open("mod_error.txt", "w") { |f| f.puts(e.full_message) }
end
