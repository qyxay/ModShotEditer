# ============================================================
#  title_screen.rb — 标题界面控制
#
#  OneShot 原始逻辑: 如果存在 save.dat, 启动时直接跳过标题界面
#  进入游戏 (Scene_Title.rb 第41行: if save_exists then $scene = Scene_Map.new)
#
#  本 mod 用 Object.prepend 覆盖全局方法 save_exists:
#    unshow_title: true  → save_exists 返回 true → 无论如何不展示标题, 直接进游戏
#    unshow_title: false → save_exists 返回 false → 一定展示标题界面
#
#  配置: mods/mod/config.json
#    "unshow_title": true   → 不展示标题, 直接进游戏
#    "unshow_title": false  → 一定展示标题界面
# ============================================================

# --- 读取配置 (统一由 _config.rb 加载到 $mod_config) ---
default_config = { "unshow_title" => false }
config = default_config.merge($mod_config || {})

$unshow_title_enabled = config["unshow_title"] ? true : false

# --- 用 Object.prepend 覆盖 save_exists ---
# save_exists 是 SaveLoad.rb 第258行定义的全局方法 (private, 挂在 Object 上)。
# preload 脚本运行时游戏脚本尚未加载, save_exists 还不存在。
# 用 Object.prepend 把补丁模块插入祖先链最前面, 即使游戏脚本后定义
# save_exists, 补丁方法仍优先被调用。
module TitleScreenSaveExistsPatch
  def save_exists
    if $unshow_title_enabled
      true   # unshow_title: true → 不展示标题, 直接进游戏
    else
      false  # unshow_title: false → 一定展示标题
    end
  end
end

Object.prepend(TitleScreenSaveExistsPatch)

# --- 写状态文件 ---
status_path = File.join(__dir__, '..', 'logs', 'title_screen_status.txt')
_log_dir = File.dirname(status_path)
Dir.mkdir(_log_dir) unless File.directory?(_log_dir)
File.open(status_path, 'w') do |f|
  f.puts "unshow_title_enabled = #{$unshow_title_enabled}"
  f.puts "config_source = \$mod_config (unified loader _config.rb)"
  f.puts "config = #{JSON.pretty_generate(config)}"
  f.puts "patch_method = Object.prepend (TitleScreenSaveExistsPatch#save_exists)"
  f.puts "original_behavior = skip title if save.dat exists (Scene_Title.rb:41)"
  f.puts "patched_behavior = unshow_title:true → skip title always; unshow_title:false → show title always"
  f.puts "loaded_at = #{Time.now}"
end
