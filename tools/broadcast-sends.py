"""Every CPR Voice Broadcast Send in a Wwise bank: its fixed channel, or the parameter that drives it."""
import struct, sys
SEND_MONO, SEND_STEREO = 207267, 338339
def chunks(b):
    i = 0
    while i + 8 <= len(b):
        tag, size = b[i:i+4], struct.unpack_from('<I', b, i+4)[0]
        yield tag, b[i+8:i+8+size]
        i += 8 + size
def sends(path):
    b = open(path, 'rb').read()
    out = []
    for tag, data in chunks(b):
        if tag != b'HIRC':
            continue
        n = struct.unpack_from('<I', data, 0)[0]; p = 4
        for _ in range(n):
            t, size, oid = struct.unpack_from('<BII', data, p)
            body = data[p+9:p+5+size]
            if t in (16, 17):
                fx, usize = struct.unpack_from('<II', body, 0)
                if fx in (SEND_MONO, SEND_STEREO):
                    blk = body[8:8+usize]
                    vals = struct.unpack('<%df' % (usize // 4), blk)
                    rest = body[8+usize:]
                    nbank = rest[0]; q = 1 + nbank * 6
                    ncurves = struct.unpack_from('<H', rest, q)[0]; q += 2
                    curves = []
                    for _ in range(ncurves):
                        rid, rtype, acc = struct.unpack_from('<IBB', rest, q); q += 6
                        # ParamID is a var-int (1 byte for small ids)
                        pid = rest[q]; q += 1
                        cid, scale, npts = struct.unpack_from('<IBH', rest, q); q += 7
                        pts = [struct.unpack_from('<ffI', rest, q + 12 * k)[:2] for k in range(npts)]; q += 12 * npts
                        curves.append((rid, pid, pts))
                    out.append((oid, 'stereo' if fx == SEND_STEREO else 'mono', vals, curves))
            p += 5 + size
    return out
if __name__ == '__main__':
    for path in sys.argv[1:]:
        s = sends(path)
        fixed = sorted({round(v) for oid, k, vals, curves in s if not any(pid == 0 or (k == 'stereo' and pid == 1) for _, pid, _ in curves) for v in (vals[:2] if k == 'stereo' else vals[:1])})
        driven = sorted({(rid, tuple(pts)) for oid, k, vals, curves in s for rid, pid, pts in curves if pid == 0 or (k == 'stereo' and pid == 1)})
        print(path.split('/')[-1], 'sends', len(s), 'fixed', fixed, 'driven', [(r, p[0], p[-1]) for r, p in driven])
