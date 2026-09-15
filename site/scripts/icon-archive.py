"""PNG -> .xbm + .inkatlas + .archive, every byte uncompressed. No WolvenKit, no Oodle.

Prototype of what the station builder page would do in the browser.

usage: python icon-archive.py <png> <depot folder> <part name> <out dir> [archive name]
e.g.   python icon-archive.py logo.png mystation\\gui mystation out MyStation
"""
import struct, sys, os, zlib, hashlib, time

from PIL import Image

# ---------------------------------------------------------------- hashes

def fnv1a64(s: str) -> int:
    h = 0xcbf29ce484222325
    for b in s.encode('utf-8'):
        h ^= b
        h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF
    return h


def name_hash(s: str) -> int:
    """CR2W names table hash: FNV1a64 folded to 32 bits. '' and 'None' hash to 0."""
    if s in ('', 'None'):
        return 0
    h = fnv1a64(s)
    return ((h >> 32) ^ h) & 0xFFFFFFFF


_CRC64_TABLE = []
for _i in range(256):
    _c = _i
    for _ in range(8):
        _c = (_c >> 1) ^ 0xC96C5795D7870F42 if _c & 1 else _c >> 1
    _CRC64_TABLE.append(_c)


def crc64(b: bytes) -> int:
    """CRC-64/XZ, as the archive index uses."""
    c = 0xFFFFFFFFFFFFFFFF
    for x in b:
        c = (c >> 8) ^ _CRC64_TABLE[(c ^ x) & 0xFF]
    return c ^ 0xFFFFFFFFFFFFFFFF


def sanitize_path(p: str) -> str:
    return p.replace('/', '\\').lower()

# ---------------------------------------------------------------- CR2W values
# A class is a list of (field name, red type name, value). A value is one of:
#   ('u8'|'u16'|'u32'|'i32'|'f32', number)   ('cname', str)   ('enum', str)
#   ('ref', depot path)   ('handle', export index, 1-based)   ('buffer', index, 1-based)
#   ('class', fields)     ('array', [fields, ...])


class CR2W:
    def __init__(self):
        self.names = ['']
        self.paths = []
        self.exports = []   # (class name, fields)
        self.buffers = []   # (flags, bytes)

    def name(self, s):
        if s not in self.names:
            self.names.append(s)
        return self.names.index(s)

    def path(self, p):
        if p not in self.paths:
            self.paths.append(p)
        return self.paths.index(p) + 1

    def ser_class(self, fields):
        out = bytearray(b'\0')
        for fname, tname, value in fields:
            n = self.name(fname)
            t = self.name(tname)
            v = self.ser_value(value)
            out += struct.pack('<HHI', n, t, len(v) + 4) + v
        out += b'\0\0'
        return bytes(out)

    def ser_value(self, value):
        kind, v = value
        if kind in ('u8', 'u16', 'u32', 'i32', 'f32'):
            return struct.pack('<' + {'u8': 'B', 'u16': 'H', 'u32': 'I', 'i32': 'i', 'f32': 'f'}[kind], v)
        if kind in ('cname', 'enum'):
            return struct.pack('<H', self.name(v))
        if kind == 'ref':
            return struct.pack('<H', self.path(v))
        if kind == 'handle':
            idx, cls = v
            self.name(cls)
            return struct.pack('<i', idx)
        if kind == 'buffer':
            return struct.pack('<H', v)
        if kind == 'class':
            return self.ser_class(v)
        if kind == 'array':
            return struct.pack('<I', len(v)) + b''.join(self.ser_class(x) for x in v)
        raise ValueError(kind)

    def write(self):
        # Serialising the exports registers every name, so it runs before the tables are sized.
        self.name(self.exports[0][0])
        export_data = []
        for cls, fields in self.exports:
            self.name(cls)
            export_data.append(self.ser_class(fields))

        strings = bytearray()
        name_off = []
        for s in self.names:
            name_off.append(len(strings))
            strings += s.encode('utf-8') + b'\0'
        path_off = []
        for p in self.paths:
            path_off.append(len(strings))
            strings += p.encode('utf-8') + b'\0'

        names_tbl = b''.join(struct.pack('<II', o, name_hash(s)) for o, s in zip(name_off, self.names))
        imports_tbl = b''.join(struct.pack('<IHH', o, 0, 4) for o in path_off)
        props_tbl = struct.pack('<HHHHQ', 0, 0, 0, 0, 0)
        exports_len = 24 * len(self.exports)
        buffers_len = 24 * len(self.buffers)

        pos = 160
        tables = [(0, 0, 0)] * 10
        tables[0] = (pos, len(strings), zlib.crc32(strings)); pos += len(strings)
        tables[1] = (pos, len(self.names), zlib.crc32(names_tbl)); pos += len(names_tbl)
        if self.paths:
            tables[2] = (pos, len(self.paths), zlib.crc32(imports_tbl)); pos += len(imports_tbl)
        tables[3] = (pos, 1, zlib.crc32(props_tbl)); pos += len(props_tbl)
        exports_pos = pos; pos += exports_len
        buffers_pos = pos; pos += buffers_len

        exports_tbl = bytearray()
        for (cls, _), data in zip(self.exports, export_data):
            exports_tbl += struct.pack('<HHIIIII', self.name(cls), 0, 0, len(data), pos, 0, 0)
            pos += len(data)
        objects_end = pos
        tables[4] = (exports_pos, len(self.exports), zlib.crc32(exports_tbl))

        buffers_tbl = bytearray()
        buffer_data = bytearray()
        for i, (flags, data) in enumerate(self.buffers):
            buffers_tbl += struct.pack('<IIIIII', flags, i, pos, len(data), len(data), zlib.crc32(data))
            buffer_data += data
            pos += len(data)
        if self.buffers:
            tables[5] = (buffers_pos, len(self.buffers), zlib.crc32(buffers_tbl))
        buffers_end = pos

        crc_src = b'CR2W' + struct.pack('<IIQIIIII', 195, 0, 0, 0, objects_end, buffers_end, 0xDEADBEEF, 6)
        crc_src += b''.join(struct.pack('<III', *t) for t in tables)
        header = b'CR2W' + struct.pack('<IIQIIIII', 195, 0, 0, 0, objects_end, buffers_end, zlib.crc32(crc_src), 6)
        header += b''.join(struct.pack('<III', *t) for t in tables)

        out = header + strings + names_tbl + (imports_tbl if self.paths else b'') + props_tbl
        out += exports_tbl + buffers_tbl + b''.join(export_data) + buffer_data
        assert len(out) == buffers_end
        return bytes(out), objects_end

# ---------------------------------------------------------------- pixels

def _s2l(c):
    c /= 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _l2s(v):
    return 12.92 * v if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055


_S2L = [_s2l(c) for c in range(256)]


def premultiplied_flipped_rgba(img: Image.Image) -> bytes:
    """RGBA8, bottom row first, colour premultiplied by alpha in linear light (what WolvenKit writes)."""
    img = img.convert('RGBA')
    w, h = img.size
    src = img.tobytes()
    cache = {}
    out = bytearray(w * h * 4)
    for y in range(h):
        row_src = (h - 1 - y) * w * 4
        row_dst = y * w * 4
        for x in range(0, w * 4, 4):
            r, g, b, a = src[row_src + x:row_src + x + 4]
            if a == 255:
                px = (r, g, b, a)
            elif a == 0:
                px = (0, 0, 0, 0)
            else:
                px = []
                for c in (r, g, b):
                    k = (c, a)
                    if k not in cache:
                        cache[k] = int(_l2s(_S2L[c] * a / 255) * 255 + 0.5)
                    px.append(cache[k])
                px = (*px, a)
            out[row_dst + x:row_dst + x + 4] = bytes(px)
    return bytes(out)

# ---------------------------------------------------------------- resources

def build_xbm(img: Image.Image) -> bytes:
    w, h = img.size
    size = w * h * 4
    f = CR2W()
    f.exports.append(('CBitmapTexture', [
        ('cookingPlatform', 'ECookingPlatform', ('enum', 'PLATFORM_PC')),
        ('width', 'Uint32', ('u32', w)),
        ('height', 'Uint32', ('u32', h)),
        ('setup', 'STextureGroupSetup', ('class', [
            ('group', 'GpuWrapApieTextureGroup', ('enum', 'TEXG_Generic_UI')),
            ('isStreamable', 'Bool', ('u8', 0)),
            ('hasMipchain', 'Bool', ('u8', 0)),
            ('isGamma', 'Bool', ('u8', 1)),
            ('allowTextureDowngrade', 'Bool', ('u8', 0)),
        ])),
        ('renderTextureResource', 'rendRenderTextureResource', ('class', [
            ('renderResourceBlobPC', 'handle:IRenderResourceBlob', ('handle', (2, 'rendRenderTextureBlobPC'))),
        ])),
    ]))
    f.exports.append(('rendRenderTextureBlobPC', [
        ('header', 'rendRenderTextureBlobHeader', ('class', [
            ('version', 'Uint32', ('u32', 2)),
            ('sizeInfo', 'rendRenderTextureBlobSizeInfo', ('class', [
                ('width', 'Uint16', ('u16', w)),
                ('height', 'Uint16', ('u16', h)),
            ])),
            ('textureInfo', 'rendRenderTextureBlobTextureInfo', ('class', [
                ('textureDataSize', 'Uint32', ('u32', size)),
                ('sliceSize', 'Uint32', ('u32', size)),
                ('dataAlignment', 'Uint32', ('u32', 8)),
                ('sliceCount', 'Uint16', ('u16', 1)),
                ('mipCount', 'Uint8', ('u8', 1)),
            ])),
            ('mipMapInfo', 'array:rendRenderTextureBlobMipMapInfo', ('array', [[
                ('layout', 'rendRenderTextureBlobMemoryLayout', ('class', [
                    ('rowPitch', 'Uint32', ('u32', w * 4)),
                    ('slicePitch', 'Uint32', ('u32', size)),
                ])),
                ('placement', 'rendRenderTextureBlobPlacement', ('class', [
                    ('size', 'Uint32', ('u32', size)),
                ])),
            ]])),
            ('flags', 'Uint32', ('u32', 1)),
        ])),
        ('textureData', 'serializationDeferredDataBuffer', ('buffer', 1)),
    ]))
    f.buffers.append((131072, premultiplied_flipped_rgba(img)))
    return f.write()[0]


def build_inkatlas(xbm_path: str, part: str, w: int, h: int, rect=None) -> bytes:
    left, top, right, bottom = rect or (0, 0, w, h)
    f = CR2W()
    f.exports.append(('inkTextureAtlas', [
        ('cookingPlatform', 'ECookingPlatform', ('enum', 'PLATFORM_PC')),
        ('texture', 'raRef:CBitmapTexture', ('ref', xbm_path)),
        ('slots', '[3]inkTextureSlot', ('array', [
            [
                ('texture', 'raRef:CBitmapTexture', ('ref', xbm_path)),
                ('parts', 'array:inkTextureAtlasMapper', ('array', [[
                    ('partName', 'CName', ('cname', part)),
                    ('clippingRectInPixels', 'Rect', ('class', [
                        ('left', 'Int32', ('i32', left)),
                        ('top', 'Int32', ('i32', top)),
                        ('right', 'Int32', ('i32', right)),
                        ('bottom', 'Int32', ('i32', bottom)),
                    ])),
                    ('clippingRectInUVCoords', 'RectF', ('class', [
                        ('Left', 'Float', ('f32', left / w)),
                        ('Top', 'Float', ('f32', top / h)),
                        ('Right', 'Float', ('f32', right / w)),
                        ('Bottom', 'Float', ('f32', bottom / h)),
                    ])),
                ]])),
            ],
            [],
            [],
        ])),
    ]))
    return f.write()[0]


def _filetime_now():
    return int(time.time() * 10_000_000) + 116444736000000000


def build_archive(files) -> bytes:
    """files: [(depot path, CR2W bytes)]. Every segment stored, zsize == size."""
    entries = sorted(((fnv1a64(sanitize_path(p)), sanitize_path(p), d) for p, d in files), key=lambda e: e[0])

    lxrs_body = b''.join(p.encode('latin-1') + b'\0' for _, p, _ in entries)
    lxrs = struct.pack('<IIiii', 0x4C585253, 1, len(lxrs_body), len(lxrs_body), len(entries)) + lxrs_body

    body = bytearray(b'\0' * 172) + lxrs
    file_rows, segs = [], []
    stamp = _filetime_now()
    for h, p, d in entries:
        _, _, _, _, objects_end, buffers_end, _, _ = struct.unpack_from('<IIQIIIII', d, 4)
        buf_off, buf_n, _ = struct.unpack_from('<III', d, 40 + 12 * 5)
        first = len(segs)
        segs.append((len(body), objects_end, objects_end))
        body += d[:objects_end]
        for i in range(buf_n):
            _, _, off, disk, mem, _ = struct.unpack_from('<IIIIII', d, buf_off + 24 * i)
            assert disk == mem, 'buffers must be stored uncompressed'
            segs.append((len(body), disk, mem))
            body += d[off:off + disk]
        inline = buf_n - 1 if buf_n > 0 else 0
        file_rows.append(struct.pack('<QqIIIII', h, stamp, inline, first, len(segs), 0, 0) + hashlib.sha1(b'').digest())

    def pad_page(b):
        b += b'\xD9' * (4096 - len(b) % 4096)

    pad_page(body)
    index_pos = len(body)
    table = struct.pack('<III', len(file_rows), len(segs), 0) + b''.join(file_rows)
    table += b''.join(struct.pack('<QII', *s) for s in segs)
    index = struct.pack('<IIQ', 8, len(table) + 8, crc64(table)) + table
    body += index
    pad_page(body)

    header = struct.pack('<IIQIQIQ', 0x52414452, 12, index_pos, len(index), 0, 0, len(body))
    header += struct.pack('<Q', len(lxrs))
    body[0:len(header)] = header
    return bytes(body)


def main():
    png, folder, part, out_dir = sys.argv[1:5]
    archive_name = sys.argv[5] if len(sys.argv) > 5 else part
    folder = folder.strip('\\/').replace('/', '\\')
    img = Image.open(png)
    w, h = img.size
    xbm_path = f'{folder}\\{part}.xbm'
    atlas_path = f'{folder}\\{part}.inkatlas'
    xbm = build_xbm(img)
    atlas = build_inkatlas(xbm_path, part, w, h)
    os.makedirs(os.path.join(out_dir, 'loose', folder), exist_ok=True)
    open(os.path.join(out_dir, 'loose', xbm_path), 'wb').write(xbm)
    open(os.path.join(out_dir, 'loose', atlas_path), 'wb').write(atlas)
    arch = build_archive([(xbm_path, xbm), (atlas_path, atlas)])
    open(os.path.join(out_dir, archive_name + '.archive'), 'wb').write(arch)
    print(f'{xbm_path}: {len(xbm)} bytes, {w}x{h}')
    print(f'{atlas_path}: {len(atlas)} bytes, part "{part}"')
    print(f'{archive_name}.archive: {len(arch)} bytes')


if __name__ == '__main__':
    main()
