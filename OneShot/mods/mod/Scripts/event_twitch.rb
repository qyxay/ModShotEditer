# ============================================================
#  event_twitch.rb — "角色抽搐"防护 (事件反复触发抑制)
#
#  现象: 跳关后, 部分"玩家接触触发 + 推玩家"的事件(如楼梯/门槛)会反复触发:
#        玩家站在触发格上, 事件 move route 试图把玩家推开(爬楼梯/阻挡),
#        但推的方向不可达(墙/边界/跳关后状态错位) → 移动失败 → 玩家没被
#        推走 → 还在触发格上 → 事件又触发 → 又推(失败) → 每帧反复 →
#        角色抽搐, 且玩家被"挡住"进不去。
#        skip_event 开关不影响(这些命令非等待类, 快进/正常都会反复)。
#
#  修复: 对含"作用于玩家的 move route"(209/212 目标=-1)的事件做触发抑制
#        —— 若玩家位置与上次触发时相同(说明事件没把玩家推走, 移动失败),
#        抑制后续触发, 直到玩家主动移动(位置变化)后才解除。
#        正常游戏(事件成功推走玩家 / 对话等非推人事件)不受影响。
#
#  纯 preload 实现, 用 PatchHelper.install 在 Game_Event#start 前挂补丁。
# ============================================================

module EventTwitchGuardPatch
  def start
    # 懒检测: 该事件是否含"作用于玩家的 move route" (209/212 目标=-1)
    unless defined?(@twitch_guard_checked)
      @twitch_guard_checked = true
      @twitch_guard_push = false
      if @list
        @list.each do |cmd|
          if cmd && [209, 212].include?(cmd.code)
            params = begin
              cmd.parameters
            rescue StandardError
              []
            end
            if params.is_a?(Array) && params[0].to_i == -1
              @twitch_guard_push = true
              break
            end
          end
        end
      end
    end
    if @twitch_guard_push
      pos = [$game_player.x, $game_player.y]
      # 玩家与上次触发时位置相同 → 事件没把玩家推走(移动失败) → 抑制
      if @twitch_guard_pos == pos && @twitch_guard_pos
        return
      end
      @twitch_guard_pos = pos
    end
    super
  end

  def update
    # 玩家主动移动(位置与记录不同) → 解除抑制, 允许下次正常触发
    if @twitch_guard_push && @twitch_guard_pos
      cur = [$game_player.x, $game_player.y]
      @twitch_guard_pos = nil if cur != @twitch_guard_pos
    end
    super
  end
end

# --- Game_Event#start/update 就绪后挂补丁 ---
PatchHelper.install('Game_Event', methods: [:start, :update]) do |k|
  k.prepend(EventTwitchGuardPatch)
end

# --- 写状态文件 ---
StatusLog.write('event_twitch_status.txt', [
  "event_twitch loaded at = #{Time.now}",
  "patch = Game_Event#start 触发抑制 (仅含 209/212 目标=-1 的推玩家事件)",
  "rule = 玩家位置与上次触发相同 → 抑制; 玩家移动(位置变) → 解除",
  "purpose = 跳关后楼梯/门槛等推人事件反复触发导致的角色抽搐 + 阻止进入"
])
