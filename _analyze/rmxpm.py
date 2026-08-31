# -*- coding: utf-8 -*-
# Ruby Marshal 4.8 解码器（OneShot/RPG Maker XP 数据文件专用）
import sys, zlib

def rf(buf, pos):
    b = buf[pos]; pos += 1
    if b == 0x00: return 0, pos
    if 0x01 <= b <= 0x7F: return b, pos
    if b == 0x80: return buf[pos], pos + 1
    if b == 0x81: return int.from_bytes(buf[pos:pos+2], 'little', signed=False), pos + 2
    if b == 0x82: return int.from_bytes(buf[pos:pos+4], 'little', signed=False), pos + 4
    if b == 0x83: return int.from_bytes(buf[pos:pos+8], 'little', signed=False), pos + 8
    return b - 0x100, pos  # 0x84..0xFF negative

def rv(buf, pos, sym, depth=0):
    if depth > 120: raise Exception("deep")
    t = buf[pos]; pos += 1
    if t == 0x22:  # String
        n, pos = rf(buf, pos); return buf[pos:pos+n], pos+n
    if t == 0x3A:  # Symbol (new)
        n, pos = rf(buf, pos); s = buf[pos:pos+n].decode('utf-8', 'replace'); sym.append(s); return s, pos+n
    if t == 0x3B:  # Symbol link
        i, pos = rf(buf, pos); return sym[i], pos
    if t == 0x69:  # Fixnum
        return rf(buf, pos)
    if t == 0x6C:  # Bignum
        n, pos = rf(buf, pos)
        sgn = buf[pos]; pos += 1
        val = int.from_bytes(buf[pos:pos+n], 'little', signed=False); pos += n
        return (-val if sgn == ord('-') else val), pos
    if t == 0x72:  # Regexp (Ruby 2.x: no encoding field)
        n, pos = rf(buf, pos)
        s = buf[pos:pos+n].decode('utf-8', 'replace'); pos += n
        opts, pos = rf(buf, pos)
        return ("<regexp:%s>" % s,), pos
    if t == 0x5B:  # Array
        n, pos = rf(buf, pos); out = []
        for _ in range(n):
            v, pos = rv(buf, pos, sym, depth+1); out.append(v)
        return out, pos
    if t == 0x7B:  # Hash
        n, pos = rf(buf, pos); out = {}
        for _ in range(n):
            k, pos = rv(buf, pos, sym, depth+1); v, pos = rv(buf, pos, sym, depth+1); out[k] = v
        return out, pos
    if t == 0x49:  # IVar (encoding wrapper)
        obj, pos = rv(buf, pos, sym, depth+1)
        n, pos = rf(buf, pos)
        for _ in range(n):
            k, pos = rv(buf, pos, sym, depth+1); v, pos = rv(buf, pos, sym, depth+1)
        return obj, pos
    if t == 0x6F:  # Object
        name, pos = rv(buf, pos, sym, depth+1)
        n, pos = rf(buf, pos)
        iv = {}
        for _ in range(n):
            k, pos = rv(buf, pos, sym, depth+1); v, pos = rv(buf, pos, sym, depth+1); iv[k] = v
        return (name, iv), pos
    if t == 0x00: return None, pos
    if t == 0x54: return True, pos
    if t == 0x46: return False, pos
    if t == 0x3C:  # class
        n, pos = rf(buf, pos); return ("<class>",), pos
    if t == 0x3D:  # module
        n, pos = rf(buf, pos); return ("<module>",), pos
    if t == 0x6D:  # module/class of
        name, pos = rv(buf, pos, sym, depth+1); return ("<modof:%s>" % name,), pos
    raise Exception("type %02X at %d" % (t, pos-1))

def load(path):
    b = open(path, 'rb').read()
    assert b[:2] == b'\x04\x08'
    # Ruby 1.9+/2.x Marshal pre-registers :EOS and :encoding symbols at index 0/1
    sym = ['EOS', 'encoding']
    pos = 2
    v, pos = rv(b, pos, sym)
    return v, b, pos, sym

if __name__ == '__main__':
    path = sys.argv[1]
    v, b, pos, sym = load(path)
    def fmt(x, d=0):
        ind = '  ' * d
        if isinstance(x, tuple) and len(x) == 2 and isinstance(x[0], str):
            name, iv = x
            print("%s<%s>" % (ind, name))
            for k, val in iv.items():
                print("%s  %s = " % (ind, k), end='')
                if isinstance(val, (dict, list)) or (isinstance(val, tuple) and len(val)==2):
                    print()
                    fmt(val, d+2)
                else:
                    print(repr(val)[:80])
        elif isinstance(x, dict):
            print("%s{dict %d}" % (ind, len(x)))
            for k, val in x.items():
                print("%s  %r:" % (ind, k), end='')
                if isinstance(val, (dict, list)) or (isinstance(val, tuple) and len(val)==2):
                    print()
                    fmt(val, d+2)
                else:
                    print(' ', repr(val)[:80])
        elif isinstance(x, list):
            print("%s[list %d]" % (ind, len(x)))
            for i, val in enumerate(x[:200]):
                print("%s  [%d]:" % (ind, i), end='')
                if isinstance(val, (dict, list)) or (isinstance(val, tuple) and len(val)==2):
                    print()
                    fmt(val, d+2)
                else:
                    print(' ', repr(val)[:80])
        else:
            print("%s%r" % (ind, x)[:120])
    fmt(v)
