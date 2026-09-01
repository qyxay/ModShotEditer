# ============================================================
#  scan_dialogue_events.rb — 分析地图"对话事件"构成
#
# 对指定地图, 列出每个"玩家可触发"事件(trigger 0/1/2):
#   * 当前激活页(第一个满足条件页)的命令构成(统计非 101/401 命令码)
#   * 是否有自开关条件页(complete_all_dialogues 能否完成)
#   * 含传送/移动路线/AUTORUN 等危险命令?
#
# 目的: 判断 JumpMap free mode 下"放行纯对话"与
#       complete_all_dialogues 覆盖范围是否合理。
#
# 用法: runtime\bin\ruby.exe _analyze\scan_dialogue_events.rb [map_ids...]
# ============================================================
$LOAD_PATH.unshift('C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/runtime/lib/ruby/3.1.0')
require_relative 'oneshot_data'

module RPG
  class MapInfo
    attr_accessor :name, :parent_id
  end
end

# 命令码 → 名称(常用)
CMD_NAME = {
  0 => 'END', 101 => 'ShowText', 401 => 'TextLine', 102 => 'Choices', 402 => 'ChoiceBranch',
  403 => 'ChoiceCancel', 104 => 'NumberInput', 105 => 'TextScroll', 106 => 'Wait',
  108 => 'Comment', 408 => 'CommentLine', 111 => 'CondBranch', 121 => 'SwOp', 122 => 'VarOp',
  123 => 'SelfSwOp', 201 => 'Transfer', 202 => 'EvPos', 203 => 'MapScroll', 204 => 'ShowAnim',
  205 => 'FogProp', 206 => 'Transp', 207 => 'MovePic', 209 => 'MoveRoute', 210 => 'MoveRouteStart',
  211 => 'WaitMove', 212 => 'PrepTrans', 213 => 'ExecTrans', 214 => 'Tone', 215 => 'Flash',
  216 => 'Shake', 218 => 'ShowPic', 221 => 'FadeOut', 222 => 'FadeIn', 223 => 'BGM', 224 => 'BGS',
  225 => 'PicTone', 230 => 'Timer', 231 => 'GameOver', 232 => 'Title', 233 => 'CommonEvent',
  234 => 'Script', 250 => 'PlaySE', 355 => 'Script', 655 => 'ScriptML', 201 => 'Transfer'
}
# 玩家触发的"危险"命令(会抢控制/改状态, 放行需谨慎)
DANGER_CODES = [201, 202, 203, 209, 210, 211, 212, 213, 216, 230, 231, 232, 355, 655, 121, 122, 123, 111, 233]
# 纯对话安全命令(消息展示期间)
SAFE_DIALOGUE = [0, 101, 401, 102, 402, 403, 104, 105, 106, 108, 408, 250, 223, 224]

ids = ARGV.map(&:to_i)
ids = [2, 4, 120, 64] if ids.empty?
infos = Marshal.load(File.binread("#{DATA}/MapInfos.rxdata"))

def page_active?(page, self_sw, switches, vars)
  c = page.condition
  return true unless c
  return false if c.switch1_valid && !switches[c.switch1_id]
  return false if c.switch2_valid && !switches[c.switch2_id]
  return false if c.self_switch_valid && !self_sw[c.self_switch_ch]
  return false if c.variable_valid && c.variable_value && vars[c.variable_id].to_i < c.variable_value.to_i
  true
end

ids.each do |mid|
  map = os_load_map(mid)
  evs = map.instance_variable_get(:@events) || {}
  puts "===== Map #{mid} #{infos[mid].name.inspect} (events=#{evs.size}) ====="
  evs.sort_by { |k, _| k }.each do |eid, ev|
    pages = ev.pages
    next unless pages
    # 收集命令构成(所有页)
    all_codes = pages.flat_map { |pg| (pg.list || []).map { |c| c ? c.code : 0 } }
    has_dlg = all_codes.include?(101)
    # 是否有自开关条件页
    has_self_page = pages.any? { |pg| c = pg.condition; c && c.self_switch_valid }
    # 当前激活页(按顺序第一个满足条件, 无条件即第0页)
    active = pages.find { |pg| page_active?(pg, {}, {}, {}) } || pages[0]
    act_codes = (active.list || []).map { |c| c ? c.code : 0 }.reject { |c| c == 0 }
    trig = active.trigger
    # 危险命令
    dangers = act_codes & DANGER_CODES
    # 只关注玩家可触发的(trigger 0/1/2)且含对话的
    next unless [0, 1, 2].include?(trig) && has_dlg
    puts "  ev#{eid} #{ev.name.to_s[0, 28].inspect} trig=#{trig} pages=#{pages.size} selfpage=#{has_self_page}"
    puts "      active_cmds=#{act_codes.map { |c| CMD_NAME[c] || c }.join(',')}"
    puts "      dangers=#{dangers.map { |c| CMD_NAME[c] || c }.join(',')}" unless dangers.empty?
  end
end
