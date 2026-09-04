# -*- coding: utf-8 -*-
require_relative 'oneshot_data'
module RPG
  class CommonEvent
    attr_accessor :name, :trigger, :list
  end
  class EventCommand
    attr_accessor :code, :parameters, :indent
  end
end

CMDNAME = {
  101=>'msg',102=>'msg2',108=>'comment',111=>'cond',112=>'loop',115=>'exit_proc',117=>'CE',
  122=>'var',125=>'sw',129=>'mem',201=>'teleport',223=>'TINT',224=>'flash',231=>'pic',232=>'pic_move',
  235=>'pic_erase',241=>'fadeout',242=>'bgm',250=>'se',281=>'scr_tint',282=>'flash2',301=>'battle',
  355=>'script',401=>'txt',408=>'comment2',411=>'script(c)',412=>'else',413=>'branch_end',505=>'mov',655=>'script(cont)', 105=>'wait',106=>'wait2'
}

ces = Marshal.load(File.binread("#{DATA}/CommonEvents.rxdata"))
ce = ces[42]
puts "=== CE42 #{ce ? ce.name.inspect : 'NIL'} trigger=#{ce ? ce.trigger : '-'} ==="
exit unless ce
list = ce.instance_variable_get(:@list)
indent = 0
list.each do |cmd|
  code = cmd.code
  nm = CMDNAME[code] || "c#{code}"
  p = cmd.parameters
  line = case code
    when 111 then "IF #{p[0..2].inspect}"
    when 411 then "  SCRIPT: #{p[0]}"
    when 355 then "  SCRIPT: #{p[0]}"
    when 655 then "  SCRIPT+: #{p[0]}"
    when 117 then "  CE##{p[0]}"
    when 201 then "  TELE map#{p[0]} (#{p[1]},#{p[2]})"
    when 223 then "  TINT #{p[0].inspect} dur=#{p[1]}"
    when 125 then "  SW#{p[0]}=#{p[1]}"
    when 122 then "  VAR#{p[0]}=#{p[1..3].inspect}"
    when 101 then "  MSG face=#{p[0].inspect} str=#{p[1].inspect}"
    when 401 then "    TXT: #{p[0]}"
    when 105 then "  WAIT #{p[0]}"
    when 106 then "  WAIT2 #{p[0]}"
    when 412,413,112,115 then ""
    else ""
  end
  if code == 401 || code == 101 || code == 411 || code == 355 || code == 655
    puts line
  elsif !line.empty?
    puts "#{'  ' * indent}#{nm} #{line}"
  end
  indent += 1 if code == 111
  indent -= 1 if code == 412
end
