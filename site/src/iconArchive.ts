/**
 * A station icon's texture (.xbm), atlas (.inkatlas) and archive, written from an image with every
 * byte stored uncompressed. The game reads a stored buffer or segment (disk size equal to memory
 * size) the same as a Kraken one, and a browser has no Kraken. `scripts/icon-archive.py` writes the
 * same bytes.
 */

// ---------------------------------------------------------------- hashes

const MASK64 = 0xffffffffffffffffn

export function fnv1a64(s: string): bigint {
  let h = 0xcbf29ce484222325n
  for (const b of new TextEncoder().encode(s)) {
    h ^= BigInt(b)
    h = (h * 0x100000001b3n) & MASK64
  }
  return h
}

/** A CR2W names table hash: FNV1a64 folded to 32 bits. The empty name hashes to 0. */
function nameHash(s: string): number {
  if (s === '' || s === 'None') return 0
  const h = fnv1a64(s)
  return Number(((h >> 32n) ^ h) & 0xffffffffn)
}

const CRC32_TABLE = (() => {
  const t = new Uint32Array(256)
  for (let i = 0; i < 256; i++) {
    let c = i
    for (let k = 0; k < 8; k++) c = c & 1 ? (c >>> 1) ^ 0xedb88320 : c >>> 1
    t[i] = c >>> 0
  }
  return t
})()

function crc32(b: Uint8Array): number {
  let c = 0xffffffff
  for (let i = 0; i < b.length; i++) c = CRC32_TABLE[(c ^ b[i]) & 0xff] ^ (c >>> 8)
  return (c ^ 0xffffffff) >>> 0
}

const CRC64_TABLE = (() => {
  const t: bigint[] = []
  for (let i = 0; i < 256; i++) {
    let c = BigInt(i)
    for (let k = 0; k < 8; k++) c = c & 1n ? (c >> 1n) ^ 0xc96c5795d7870f42n : c >> 1n
    t.push(c)
  }
  return t
})()

/** CRC-64/XZ, the archive index checksum. */
function crc64(b: Uint8Array): bigint {
  let c = MASK64
  for (let i = 0; i < b.length; i++) c = (c >> 8n) ^ CRC64_TABLE[Number((c ^ BigInt(b[i])) & 0xffn)]
  return c ^ MASK64
}

// ---------------------------------------------------------------- bytes

class Writer {
  private buf = new Uint8Array(1024)
  private view = new DataView(this.buf.buffer)
  length = 0

  private room(n: number) {
    if (this.length + n <= this.buf.length) return
    let size = this.buf.length * 2
    while (size < this.length + n) size *= 2
    const next = new Uint8Array(size)
    next.set(this.buf.subarray(0, this.length))
    this.buf = next
    this.view = new DataView(next.buffer)
  }

  u8(v: number) { this.room(1); this.view.setUint8(this.length, v); this.length += 1; return this }
  u16(v: number) { this.room(2); this.view.setUint16(this.length, v, true); this.length += 2; return this }
  u32(v: number) { this.room(4); this.view.setUint32(this.length, v >>> 0, true); this.length += 4; return this }
  i32(v: number) { this.room(4); this.view.setInt32(this.length, v, true); this.length += 4; return this }
  f32(v: number) { this.room(4); this.view.setFloat32(this.length, v, true); this.length += 4; return this }
  u64(v: bigint) { this.room(8); this.view.setBigUint64(this.length, v, true); this.length += 8; return this }
  bytes(b: Uint8Array) { this.room(b.length); this.buf.set(b, this.length); this.length += b.length; return this }
  pad(n: number, byte: number) { this.room(n); this.buf.fill(byte, this.length, this.length + n); this.length += n; return this }

  setU32(at: number, v: number) { this.view.setUint32(at, v >>> 0, true) }
  setU64(at: number, v: bigint) { this.view.setBigUint64(at, v, true) }
  result() { return this.buf.slice(0, this.length) }
}

// ---------------------------------------------------------------- CR2W

type Value =
  | { u8: number } | { u16: number } | { u32: number } | { i32: number } | { f32: number }
  | { name: string } // a CName or an enum value
  | { ref: string } // a depot path, written as an import
  | { handle: number; cls: string } // an export, 1-based
  | { buffer: number } // a buffer, 1-based
  | { fields: Field[] }
  | { array: Field[][] }

type Field = [name: string, type: string, value: Value]

class Cr2w {
  names: string[] = ['']
  paths: string[] = []
  exports: { cls: string; fields: Field[] }[] = []
  buffers: Uint8Array[] = []

  name(s: string) {
    let i = this.names.indexOf(s)
    if (i < 0) i = this.names.push(s) - 1
    return i
  }

  path(p: string) {
    let i = this.paths.indexOf(p)
    if (i < 0) i = this.paths.push(p) - 1
    return i + 1
  }

  private fields(out: Writer, fields: Field[]) {
    out.u8(0)
    for (const [name, type, value] of fields) {
      out.u16(this.name(name)).u16(this.name(type))
      const v = new Writer()
      this.value(v, value)
      out.u32(v.length + 4).bytes(v.result())
    }
    out.u16(0)
  }

  private value(out: Writer, v: Value) {
    if ('u8' in v) out.u8(v.u8)
    else if ('u16' in v) out.u16(v.u16)
    else if ('u32' in v) out.u32(v.u32)
    else if ('i32' in v) out.i32(v.i32)
    else if ('f32' in v) out.f32(v.f32)
    else if ('name' in v) out.u16(this.name(v.name))
    else if ('ref' in v) out.u16(this.path(v.ref))
    else if ('handle' in v) {
      this.name(v.cls)
      out.i32(v.handle)
    } else if ('buffer' in v) out.u16(v.buffer)
    else if ('fields' in v) this.fields(out, v.fields)
    else {
      out.u32(v.array.length)
      for (const f of v.array) this.fields(out, f)
    }
  }

  write(): Uint8Array {
    // Serialising the exports registers every name, so it runs before the tables are laid out.
    this.name(this.exports[0].cls)
    const exportData = this.exports.map((e) => {
      this.name(e.cls)
      const w = new Writer()
      this.fields(w, e.fields)
      return w.result()
    })

    const enc = new TextEncoder()
    const strings = new Writer()
    const nameOffsets = this.names.map((s) => {
      const at = strings.length
      strings.bytes(enc.encode(s)).u8(0)
      return at
    })
    const pathOffsets = this.paths.map((p) => {
      const at = strings.length
      strings.bytes(enc.encode(p)).u8(0)
      return at
    })
    const stringBytes = strings.result()

    const namesTbl = new Writer()
    this.names.forEach((s, i) => namesTbl.u32(nameOffsets[i]).u32(nameHash(s)))
    const importsTbl = new Writer()
    for (const at of pathOffsets) importsTbl.u32(at).u16(0).u16(4)
    const propsTbl = new Writer().u16(0).u16(0).u16(0).u16(0).u64(0n)

    const tables: [number, number, number][] = Array.from({ length: 10 }, () => [0, 0, 0])
    let pos = 160
    tables[0] = [pos, stringBytes.length, crc32(stringBytes)]
    pos += stringBytes.length
    tables[1] = [pos, this.names.length, crc32(namesTbl.result())]
    pos += namesTbl.length
    if (this.paths.length) {
      tables[2] = [pos, this.paths.length, crc32(importsTbl.result())]
      pos += importsTbl.length
    }
    tables[3] = [pos, 1, crc32(propsTbl.result())]
    pos += propsTbl.length
    const exportsPos = pos
    pos += 24 * this.exports.length
    const buffersPos = pos
    pos += 24 * this.buffers.length

    const exportsTbl = new Writer()
    this.exports.forEach((e, i) => {
      exportsTbl.u16(this.name(e.cls)).u16(0).u32(0).u32(exportData[i].length).u32(pos).u32(0).u32(0)
      pos += exportData[i].length
    })
    const objectsEnd = pos
    tables[4] = [exportsPos, this.exports.length, crc32(exportsTbl.result())]

    const buffersTbl = new Writer()
    this.buffers.forEach((b, i) => {
      buffersTbl.u32(131072).u32(i).u32(pos).u32(b.length).u32(b.length).u32(crc32(b))
      pos += b.length
    })
    if (this.buffers.length) tables[5] = [buffersPos, this.buffers.length, crc32(buffersTbl.result())]
    const buffersEnd = pos

    const header = (crc: number) => {
      const h = new Writer()
      h.bytes(enc.encode('CR2W')).u32(195).u32(0).u64(0n).u32(0).u32(objectsEnd).u32(buffersEnd).u32(crc).u32(6)
      for (const t of tables) h.u32(t[0]).u32(t[1]).u32(t[2])
      return h.result()
    }

    const out = new Writer()
    out.bytes(header(crc32(header(0xdeadbeef))))
    out.bytes(stringBytes).bytes(namesTbl.result())
    if (this.paths.length) out.bytes(importsTbl.result())
    out.bytes(propsTbl.result()).bytes(exportsTbl.result()).bytes(buffersTbl.result())
    for (const d of exportData) out.bytes(d)
    for (const b of this.buffers) out.bytes(b)
    return out.result()
  }
}

// ---------------------------------------------------------------- pixels

/** sRGB byte and alpha to the premultiplied sRGB byte, premultiplied in linear light. */
const PREMULTIPLY = (() => {
  const toLinear = (c: number) => {
    const v = c / 255
    return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4
  }
  const toSrgb = (v: number) => (v <= 0.0031308 ? 12.92 * v : 1.055 * v ** (1 / 2.4) - 0.055)
  const t = new Uint8Array(65536)
  for (let c = 0; c < 256; c++) {
    const lin = toLinear(c)
    for (let a = 0; a < 256; a++) t[(a << 8) | c] = Math.floor(toSrgb((lin * a) / 255) * 255 + 0.5)
  }
  return t
})()

/** Straight RGBA, top row first, to the texture's pixels: bottom row first, premultiplied. */
export function texturePixels(rgba: Uint8Array | Uint8ClampedArray, width: number, height: number): Uint8Array {
  const out = new Uint8Array(width * height * 4)
  const row = width * 4
  for (let y = 0; y < height; y++) {
    const src = (height - 1 - y) * row
    const dst = y * row
    for (let x = 0; x < row; x += 4) {
      const a = rgba[src + x + 3]
      if (a === 0) continue
      const k = a << 8
      out[dst + x] = PREMULTIPLY[k | rgba[src + x]]
      out[dst + x + 1] = PREMULTIPLY[k | rgba[src + x + 1]]
      out[dst + x + 2] = PREMULTIPLY[k | rgba[src + x + 2]]
      out[dst + x + 3] = a
    }
  }
  return out
}

// ---------------------------------------------------------------- resources

/** TEXG_Generic_UI, TRF_TrueColor, TCM_None, no mips, not streamable. */
export function buildXbm(rgba: Uint8Array | Uint8ClampedArray, width: number, height: number): Uint8Array {
  const size = width * height * 4
  const f = new Cr2w()
  f.exports.push({
    cls: 'CBitmapTexture',
    fields: [
      ['cookingPlatform', 'ECookingPlatform', { name: 'PLATFORM_PC' }],
      ['width', 'Uint32', { u32: width }],
      ['height', 'Uint32', { u32: height }],
      ['setup', 'STextureGroupSetup', { fields: [
        ['group', 'GpuWrapApieTextureGroup', { name: 'TEXG_Generic_UI' }],
        ['isStreamable', 'Bool', { u8: 0 }],
        ['hasMipchain', 'Bool', { u8: 0 }],
        ['isGamma', 'Bool', { u8: 1 }],
        ['allowTextureDowngrade', 'Bool', { u8: 0 }],
      ] }],
      ['renderTextureResource', 'rendRenderTextureResource', { fields: [
        ['renderResourceBlobPC', 'handle:IRenderResourceBlob', { handle: 2, cls: 'rendRenderTextureBlobPC' }],
      ] }],
    ],
  })
  f.exports.push({
    cls: 'rendRenderTextureBlobPC',
    fields: [
      ['header', 'rendRenderTextureBlobHeader', { fields: [
        ['version', 'Uint32', { u32: 2 }],
        ['sizeInfo', 'rendRenderTextureBlobSizeInfo', { fields: [
          ['width', 'Uint16', { u16: width }],
          ['height', 'Uint16', { u16: height }],
        ] }],
        ['textureInfo', 'rendRenderTextureBlobTextureInfo', { fields: [
          ['textureDataSize', 'Uint32', { u32: size }],
          ['sliceSize', 'Uint32', { u32: size }],
          ['dataAlignment', 'Uint32', { u32: 8 }],
          ['sliceCount', 'Uint16', { u16: 1 }],
          ['mipCount', 'Uint8', { u8: 1 }],
        ] }],
        ['mipMapInfo', 'array:rendRenderTextureBlobMipMapInfo', { array: [[
          ['layout', 'rendRenderTextureBlobMemoryLayout', { fields: [
            ['rowPitch', 'Uint32', { u32: width * 4 }],
            ['slicePitch', 'Uint32', { u32: size }],
          ] }],
          ['placement', 'rendRenderTextureBlobPlacement', { fields: [['size', 'Uint32', { u32: size }]] }],
        ]] }],
        ['flags', 'Uint32', { u32: 1 }],
      ] }],
      ['textureData', 'serializationDeferredDataBuffer', { buffer: 1 }],
    ],
  })
  f.buffers.push(texturePixels(rgba, width, height))
  return f.write()
}

/** One part covering the whole texture. */
export function buildInkatlas(xbmPath: string, part: string, width: number, height: number): Uint8Array {
  const f = new Cr2w()
  f.exports.push({
    cls: 'inkTextureAtlas',
    fields: [
      ['cookingPlatform', 'ECookingPlatform', { name: 'PLATFORM_PC' }],
      ['texture', 'raRef:CBitmapTexture', { ref: xbmPath }],
      ['slots', '[3]inkTextureSlot', { array: [
        [
          ['texture', 'raRef:CBitmapTexture', { ref: xbmPath }],
          ['parts', 'array:inkTextureAtlasMapper', { array: [[
            ['partName', 'CName', { name: part }],
            ['clippingRectInPixels', 'Rect', { fields: [
              ['left', 'Int32', { i32: 0 }],
              ['top', 'Int32', { i32: 0 }],
              ['right', 'Int32', { i32: width }],
              ['bottom', 'Int32', { i32: height }],
            ] }],
            ['clippingRectInUVCoords', 'RectF', { fields: [
              ['Left', 'Float', { f32: 0 }],
              ['Top', 'Float', { f32: 0 }],
              ['Right', 'Float', { f32: 1 }],
              ['Bottom', 'Float', { f32: 1 }],
            ] }],
          ]] }],
        ],
        [],
        [],
      ] }],
    ],
  })
  return f.write()
}

const SHA1_EMPTY = Uint8Array.from([
  0xda, 0x39, 0xa3, 0xee, 0x5e, 0x6b, 0x4b, 0x0d, 0x32, 0x55, 0xbf, 0xef, 0x95, 0x60, 0x18, 0x90, 0xaf, 0xd8, 0x07, 0x09,
])

/** Files are CR2W resources at their depot paths. Laid out the way WolvenKit lays out an archive. */
export function buildArchive(files: { path: string; data: Uint8Array }[], timestamp = new Date()): Uint8Array {
  const entries = files
    .map((f) => ({ path: f.path.replace(/\//g, '\\').toLowerCase(), data: f.data }))
    .map((f) => ({ ...f, hash: fnv1a64(f.path) }))
    .sort((a, b) => (a.hash < b.hash ? -1 : a.hash > b.hash ? 1 : 0))

  const lxrsBody = new Writer()
  for (const e of entries) lxrsBody.bytes(new TextEncoder().encode(e.path)).u8(0)
  const lxrs = new Writer().u32(0x4c585253).u32(1).u32(lxrsBody.length).u32(lxrsBody.length).u32(entries.length)
  lxrs.bytes(lxrsBody.result())

  const out = new Writer()
  out.pad(172, 0).bytes(lxrs.result())
  const stamp = BigInt(timestamp.getTime()) * 10000n + 116444736000000000n
  const rows = new Writer()
  const segs = new Writer()
  let segCount = 0
  for (const e of entries) {
    const d = new DataView(e.data.buffer, e.data.byteOffset, e.data.byteLength)
    const objectsEnd = d.getUint32(24, true)
    const bufOff = d.getUint32(40 + 12 * 5, true)
    const bufCount = d.getUint32(44 + 12 * 5, true)
    const first = segCount
    segs.u64(BigInt(out.length)).u32(objectsEnd).u32(objectsEnd)
    out.bytes(e.data.subarray(0, objectsEnd))
    segCount++
    for (let i = 0; i < bufCount; i++) {
      const off = d.getUint32(bufOff + 24 * i + 8, true)
      const disk = d.getUint32(bufOff + 24 * i + 12, true)
      segs.u64(BigInt(out.length)).u32(disk).u32(d.getUint32(bufOff + 24 * i + 16, true))
      out.bytes(e.data.subarray(off, off + disk))
      segCount++
    }
    rows.u64(e.hash).u64(stamp).u32(bufCount > 0 ? bufCount - 1 : 0).u32(first).u32(segCount).u32(0).u32(0).bytes(SHA1_EMPTY)
  }

  const padPage = () => out.pad(4096 - (out.length % 4096), 0xd9)
  padPage()
  const indexPos = out.length
  const table = new Writer().u32(entries.length).u32(segCount).u32(0).bytes(rows.result()).bytes(segs.result()).result()
  out.u32(8).u32(table.length + 8).u64(crc64(table)).bytes(table)
  const indexSize = out.length - indexPos
  padPage()

  const result = out.result()
  const h = new DataView(result.buffer)
  h.setUint32(0, 0x52414452, true)
  h.setUint32(4, 12, true)
  h.setBigUint64(8, BigInt(indexPos), true)
  h.setUint32(16, indexSize, true)
  h.setBigUint64(32, BigInt(result.length), true)
  h.setBigUint64(40, BigInt(lxrs.length), true)
  return result
}

/** The archive for one icon: its texture next to its atlas, both named from the atlas path. */
export function buildIconArchive(rgba: Uint8Array | Uint8ClampedArray, width: number, height: number, atlasPath: string, part: string): Uint8Array {
  const atlas = atlasPath.replace(/\//g, '\\')
  const xbm = atlas.replace(/\.inkatlas$/i, '.xbm')
  return buildArchive([
    { path: xbm, data: buildXbm(rgba, width, height) },
    { path: atlas, data: buildInkatlas(xbm, part, width, height) },
  ])
}
