require 'zlib'

DATA_PATH = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/OneShot/Data/xScripts.rxdata'
OUT_DIR   = 'C:/Users/Qyxay/Desktop/onehsot/ModShot-mkxp-z/_scripts_dump'

Dir.mkdir(OUT_DIR) unless Dir.exist?(OUT_DIR)

raw = File.binread(DATA_PATH)
data = Marshal.load(raw)

puts "entries: #{data.size}"
data.each_with_index do |e, idx|
  id   = e[0]
  name = e[1].to_s
  src  = e[2].to_s

  if src.bytesize > 2 && src.getbyte(0) == 0x78
    begin
      src = Zlib::Inflate.inflate(src)
    rescue StandardError
    end
  end

  safe = name.gsub(/[^0-9A-Za-z_.-]/, '_')
  fname = "#{idx.to_s.rjust(3, '0')}_#{safe}.rb"
  File.write(File.join(OUT_DIR, fname), src)
end
puts 'done'
