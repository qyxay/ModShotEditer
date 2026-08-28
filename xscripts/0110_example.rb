# ============================================
# 示例 Mod 脚本
# 功能：1. 游戏开始时显示一段对话
#       2. 按确认键(Z/空格)显示一段对话
#
# OneShot 按键常量（不是标准的 A/B/C）：
#   Input::ACTION  = Z / 空格 / 回车（确认）
#   Input::CANCEL  = X / Esc（取消）
#   Input::MENU    = 菜单键
#   Input::ITEMS   = 物品键
#   Input::RUN     = Shift（跑步）
#   Input::UP/DOWN/LEFT/RIGHT = 方向键
#   Input::R / Input::L = PageUp / PageDown
#
# 使用方法：
#   ruby inject.rb my_mods/example.rb
#   然后把生成的 xScripts_output.rxdata 复制到 OneShot\Data\
# ============================================

# --- 功能1：开场对话 ---
$mod_intro_shown = false unless defined?($mod_intro_shown)

class Scene_Map
  alias_method :mod_original_update, :update

  def update
    # 第一次进入地图时显示对话
    if !$mod_intro_shown && $game_temp.message_text.nil?
      $mod_intro_shown = true
      $game_temp.message_text =
        "Welcome to my mod!\n" +
        "This dialogue shows at game start.\n" +
        "Press Z or Space to trigger another one.\n!"
    end

    # 按确认键(Z/空格)显示对话
    if Input.trigger?(Input::ACTION) && $game_temp.message_text.nil?
      $game_temp.message_text = "You pressed the confirm button!\n!"
    end

    mod_original_update
  end
end
