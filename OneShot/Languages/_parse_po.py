import re, io, sys
sys.stdout.reconfigure(encoding="utf-8")
p = r"C:\Users\Qyxay\Desktop\OneShot\Languages\zh_CN.po"
raw = open(p, "rb").read()
print("po 文件大小:", len(raw))
# 尝试 utf-8 / utf-8-sig / gbk
for enc in ("utf-8-sig", "utf-8", "gbk"):
    try:
        txt = raw.decode(enc)
        print("解码成功:", enc)
        break
    except Exception as e:
        print("解码失败", enc, str(e)[:60])
head = txt[:800]
print("---- 头部 ----")
print(head)
print("---- 前3条 msgid/msgstr ----")
m = re.findall(r'msgid "([^"]*)"\nmsgstr "([^"]*)"', txt)
print("简单匹配条数:", len(m))
if m:
    for a, b in m[:5]:
        print("EN:", repr(a), "=> CN:", repr(b))
