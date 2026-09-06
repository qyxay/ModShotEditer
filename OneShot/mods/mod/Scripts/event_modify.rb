# ============================================================
#  event_modify.rb — 运行时事件修改
#
#  检测 settings/event_modify.json, 应用事件修改:
#    - move_event:    移动事件位置 {event_id, x, y, dir}
#    - set_through:   设置可通行性 {event_id, through}
#    - set_dialog:    设置对话内容 {event_id, page_index, command_index, text}
#    - set_self_switch: 设置 self switch {event_id, ch, value}
#
#  修改同时作用于运行时 ($game_map.events) 和数据地图 ($data_maps),
#  重新加载地图后仍生效。
# ============================================================

require 'json'
require 'fileutils'

module EventModify
  SETTINGS_DIR = File.join(__dir__, '..', 'settings')
  MODIFY_FILE = File.join(SETTINGS_DIR, 'event_modify.json')

  def self.ensure_dir
    FileUtils.mkdir_p(SETTINGS_DIR) unless Dir.exist?(SETTINGS_DIR)
  end

  def self.check
    return unless File.exist?(MODIFY_FILE)
    begin
      raw = File.read(MODIFY_FILE, encoding: 'UTF-8')
      req = JSON.parse(raw)
      File.delete(MODIFY_FILE)  # 立即删除, 避免重复执行

      op = req["op"]
      event_id = req["event_id"].to_i
      return unless event_id > 0

      ev = $game_map.events[event_id]
      return unless ev
      event_data = ev.instance_variable_get(:@event)

      case op
      when "move_event"
        x = req["x"].to_i
        y = req["y"].to_i
        dir = req["dir"].to_i
        dir = 2 unless [2, 4, 6, 8].include?(dir)
        ev.moveto(x, y)
        ev.direction = dir
        if event_data
          event_data.x = x
          event_data.y = y
        end
        StatusLog.append("settings.log", "event_modify move: ##{event_id} -> (#{x},#{y}) dir=#{dir}")

      when "set_through"
        through = req["through"] ? true : false
        ev.through = through
        # 同时修改所有事件页的 through
        if event_data && event_data.respond_to?(:pages)
          event_data.pages.each { |p| p.through = through }
        end
        ev.refresh if ev.respond_to?(:refresh)
        StatusLog.append("settings.log", "event_modify through: ##{event_id} = #{through}")

      when "set_dialog"
        page_index = req["page_index"].to_i
        command_index = req["command_index"].to_i
        text = req["text"].to_s
        if event_data && event_data.respond_to?(:pages) &&
           event_data.pages[page_index] &&
           event_data.pages[page_index].list[command_index]
          cmd = event_data.pages[page_index].list[command_index]
          if cmd.code == 101 || cmd.code == 401  # 显示文字
            cmd.parameters[0] = text
            ev.refresh if ev.respond_to?(:refresh)
            StatusLog.append("settings.log", "event_modify dialog: ##{event_id} p#{page_index} c#{command_index} = #{text[0,30]}...")
          else
            StatusLog.append("settings.log", "event_modify dialog FAIL: command code=#{cmd.code} not 101/401")
          end
        else
          StatusLog.append("settings.log", "event_modify dialog FAIL: invalid page/command index")
        end

      when "set_self_switch"
        ch = req["ch"].to_s.upcase
        value = req["value"] ? true : false
        if ["A", "B", "C", "D"].include?(ch)
          key = [$game_map.map_id, event_id, ch]
          $game_self_switches[key] = value
          ev.refresh if ev.respond_to?(:refresh)
          StatusLog.append("settings.log", "event_modify self_switch: ##{event_id} #{ch}=#{value}")
        end

      else
        StatusLog.append("settings.log", "event_modify unknown op: #{op}")
      end
    rescue StandardError => e
      StatusLog.append("settings.log", "event_modify FAIL: #{e.message}")
    end
  end
end

# --- Patch Scene_Map#update ---
module EventModifyPatch
  def update
    EventModify.check
    super
  end
end

PatchHelper.install("Scene_Map", methods: [:update]) do |k|
  k.prepend(EventModifyPatch)
end

EventModify.ensure_dir
StatusLog.append("settings.log", "event_modify loaded")
