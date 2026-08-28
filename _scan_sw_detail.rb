# perma 段(151-175) + 热点开关 的详细赋值位置
$LOAD_PATH.unshift 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/rmtools'
require 'rxdata_stub'
DATA = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data'
FOCUS = (151..175).to_a + [1, 22, 73, 124, 190, 198, 196, 317, 323]

def page_cmds(pg)
  l = pg.instance_variable_get(:@list); l.is_a?(Array) ? l : []
end

def show(mark, where)
  Dir.glob("#{DATA}/Map[0-9]*.rxdata").sort.each do |f|
    m = File.basename(f) =~ /Map(\d+)\.rxdata/ ? $1.to_i : 0
    map = Marshal.load(File.binread(f))
    map.events.each do |evid, ev|
      ev.pages.each_with_index do |pg, pgid|
        page_cmds(pg).each_with_index do |cmd, ci|
          p = cmd.parameters
          if cmd.code == 121
            (p[0]..p[1]).each do |sw|
              if FOCUS.include?(sw)
                puts "#{where} Map#{m} ev#{evid} '#{ev.name}' pg#{pgid} [#{ci}] 开关#{sw}=#{p[2]}"
              end
            end
          end
        end
      end
    end
  end
  cearr = Marshal.load(File.binread("#{DATA}/CommonEvents.rxdata"))
  cearr.compact.each_with_index do |ce, idx|
    page_cmds(ce).each_with_index do |cmd, ci|
      p = cmd.parameters
      if cmd.code == 121
        (p[0]..p[1]).each do |sw|
          if FOCUS.include?(sw)
            puts "#{where} CE#{idx} '#{ce.instance_variable_get(:@name)}' [#{ci}] 开关#{sw}=#{p[2]}"
          end
        end
      end
    end
  end
end

show(nil, nil)
