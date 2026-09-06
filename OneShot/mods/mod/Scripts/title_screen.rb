# ============================================================
#  title_screen.rb — 标题界面控制 (方案B: 上下文敏感)
#
#  问题(旧方案A): Object.prepend 全局劫持 save_exists, unshow_title=true
#  时 save_exists 永远返回 true, 即使真实没有存档。导致 map1 ev1 idx9
#  条件误判为真 → 执行 real_load 读不存在的存档 → 游戏卡住。
#
#  方案B: save_exists 恢复原版真实文件检查 (FileTest.exist?),
#  单独 patch Scene_Title#main 置上下文标记 $title_screen_context,
#  save_exists 在标题画面上下文里按 unshow_title 返回 true(跳过标题),
#  其余场合(如 map1 ev1 事件命令 111 条件)返回原版真实检查。
#
#  配置: mods/mod/config.json
#    "unshow_title": true   → 不展示标题, 直接进游戏
#    "unshow_title": false  → 展示标题界面
# ============================================================

# --- 读取配置 (统一由 _config.rb 加载到 $mod_config) ---
default_config = { "unshow_title" => false }
config = default_config.merge($mod_config || {})

$unshow_title_enabled = config["unshow_title"] ? true : false

# --- 上下文标记: 是否在 Scene_Title#main 执行中 ---
$title_screen_context = false

# --- Scene_Title#main 补丁: 置上下文标记 ---
module TitleScreenMainContextPatch
  def main
    $title_screen_context = true
    begin
      super
    ensure
      $title_screen_context = false
    end
  end
end

PatchHelper.install('Scene_Title', methods: [:main]) do |k|
  k.prepend(TitleScreenMainContextPatch)
end

# --- save_exists 上下文敏感补丁 ---
# 标题画面上下文 + unshow_title=true → 返回 true(跳过标题);
# 其余场合 → super(原版 FileTest.exist? 真实检查)。
module TitleScreenSaveExistsPatch
  def save_exists
    if $title_screen_context && $unshow_title_enabled
      true
    else
      super
    end
  end
end

Object.prepend(TitleScreenSaveExistsPatch)

# --- 写状态文件 ---
StatusLog.write('title_screen_status.txt', [
  "unshow_title_enabled = #{$unshow_title_enabled}",
  "config_source = $mod_config (unified loader _config.rb)",
  "patch_method = 上下文敏感 (Scene_Title#main 置 $title_screen_context + Object.prepend save_exists)",
  "behavior = 标题上下文+unshow_title→true(跳过标题); 其余→super(原版真实文件检查)",
  "fix = 不再全局劫持 save_exists, 修复无存档时 map1 ev1 误判 real_load 导致卡住",
  "original_save_exists = FileTest.exist?(SAVE_FILE_NAME) (0102_SaveLoad.rb:258)",
  "loaded_at = #{Time.now}"
])
