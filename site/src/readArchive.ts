/**
 * Reads an icon back out of a .archive this page wrote, so an opened station previews its own icon.
 *
 * Only stored data is readable here: a segment or CR2W buffer whose disk size differs from its memory
 * size is Kraken-compressed, and a browser has no Kraken. The same goes for a block-compressed
 * texture. An archive from WolvenKit is both, so it reads as null and the page asks for an image.
 */
import { fnv1a64 } from './iconArchive'

interface Segment {
  offset: number
  zsize: number
  size: number
}

interface ArchiveFile {
  hash: bigint
  segments: Segment[]
}

/** The file entries of a RDAR archive, or null when the bytes are not one. */
function readIndex(data: DataView): ArchiveFile[] | null {
  if (data.byteLength < 40 || data.getUint32(0, true) !== 0x52414452) return null
  const indexPos = Number(data.getBigUint64(8, true))
  if (indexPos <= 0 || indexPos + 28 > data.byteLength) return null
  const tableAt = indexPos + 16
  const fileCount = data.getUint32(tableAt, true)
  const segCount = data.getUint32(tableAt + 4, true)
  const depCount = data.getUint32(tableAt + 8, true)
  const filesAt = tableAt + 12
  const segsAt = filesAt + 56 * fileCount
  if (segsAt + 16 * segCount + 8 * depCount > data.byteLength) return null
  const segments: Segment[] = []
  for (let i = 0; i < segCount; i++) {
    const at = segsAt + 16 * i
    segments.push({ offset: Number(data.getBigUint64(at, true)), zsize: data.getUint32(at + 8, true), size: data.getUint32(at + 12, true) })
  }
  const files: ArchiveFile[] = []
  for (let i = 0; i < fileCount; i++) {
    const at = filesAt + 56 * i
    files.push({ hash: data.getBigUint64(at, true), segments: segments.slice(data.getUint32(at + 20, true), data.getUint32(at + 24, true)) })
  }
  return files
}

interface Cr2wFile {
  names: string[]
  imports: string[]
  exports: { cls: string; at: number; size: number }[]
  buffers: { offset: number; disk: number; mem: number }[]
  bytes: Uint8Array
}

function readCr2w(bytes: Uint8Array): Cr2wFile | null {
  const d = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength)
  if (bytes.length < 160 || String.fromCharCode(...bytes.subarray(0, 4)) !== 'CR2W') return null
  const table = (i: number) => ({ offset: d.getUint32(40 + 12 * i, true), count: d.getUint32(44 + 12 * i, true) })
  const strings = table(0)
  const text = (at: number) => {
    let end = at
    while (end < bytes.length && bytes[end] !== 0) end++
    return new TextDecoder().decode(bytes.subarray(at, end))
  }
  const names: string[] = []
  const nameTable = table(1)
  for (let i = 0; i < nameTable.count; i++) names.push(text(strings.offset + d.getUint32(nameTable.offset + 8 * i, true)))
  const imports: string[] = []
  const importTable = table(2)
  for (let i = 0; i < importTable.count; i++) imports.push(text(strings.offset + d.getUint32(importTable.offset + 8 * i, true)))
  const exports: { cls: string; at: number; size: number }[] = []
  const exportTable = table(4)
  for (let i = 0; i < exportTable.count; i++) {
    const at = exportTable.offset + 24 * i
    exports.push({ cls: names[d.getUint16(at, true)] ?? '', size: d.getUint32(at + 8, true), at: d.getUint32(at + 12, true) })
  }
  const buffers: { offset: number; disk: number; mem: number }[] = []
  const bufferTable = table(5)
  for (let i = 0; i < bufferTable.count; i++) {
    const at = bufferTable.offset + 24 * i
    buffers.push({ offset: d.getUint32(at + 8, true), disk: d.getUint32(at + 12, true), mem: d.getUint32(at + 16, true) })
  }
  return { names, imports, exports, buffers, bytes }
}

/**
 * A class's fields, by name. A field's value is its raw bytes; a nested class is read again on
 * demand, which is all this needs.
 */
function fields(f: Cr2wFile, at: number, end: number): Map<string, { type: string; at: number; end: number }> {
  const d = new DataView(f.bytes.buffer, f.bytes.byteOffset, f.bytes.byteLength)
  const out = new Map<string, { type: string; at: number; end: number }>()
  let pos = at + 1
  while (pos + 2 <= end) {
    const nameIndex = d.getUint16(pos, true)
    if (nameIndex === 0) break
    const type = f.names[d.getUint16(pos + 2, true)] ?? ''
    const size = d.getUint32(pos + 4, true)
    out.set(f.names[nameIndex] ?? '', { type, at: pos + 8, end: pos + 4 + size })
    pos = pos + 4 + size
  }
  return out
}

/** A texture the page can read: uncompressed RGBA8, as this page writes it. */
interface IconTexture {
  width: number
  height: number
  /** Straight RGBA, top row first. */
  rgba: Uint8ClampedArray
}

const UNPREMULTIPLY = (() => {
  const toLinear = (c: number) => {
    const v = c / 255
    return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4
  }
  const toSrgb = (v: number) => (v <= 0.0031308 ? 12.92 * v : 1.055 * v ** (1 / 2.4) - 0.055)
  const t = new Uint8Array(65536)
  for (let p = 0; p < 256; p++) {
    const lin = toLinear(p)
    for (let a = 1; a < 256; a++) t[(a << 8) | p] = Math.min(255, Math.floor(toSrgb(Math.min(1, (lin * 255) / a)) * 255 + 0.5))
  }
  return t
})()

function readTexture(f: Cr2wFile): IconTexture | null {
  const root = f.exports[0]
  if (!root || root.cls !== 'CBitmapTexture') return null
  const d = new DataView(f.bytes.buffer, f.bytes.byteOffset, f.bytes.byteLength)
  const top = fields(f, root.at, root.at + root.size)
  const width = top.get('width') ? d.getUint32(top.get('width')!.at, true) : 0
  const height = top.get('height') ? d.getUint32(top.get('height')!.at, true) : 0
  const setup = top.get('setup')
  if (width <= 0 || height <= 0 || !setup) return null
  const group = fields(f, setup.at, setup.end)
  const raw = group.get('rawFormat')
  const compression = group.get('compression')
  // Both are left out at their defaults, TRF_TrueColor and TCM_None, which is what this page writes.
  if (raw && f.names[d.getUint16(raw.at, true)] !== 'TRF_TrueColor') return null
  if (compression && f.names[d.getUint16(compression.at, true)] !== 'TCM_None') return null
  const buffer = f.buffers[0]
  if (!buffer || buffer.disk !== buffer.mem || buffer.mem !== width * height * 4) return null
  const px = f.bytes.subarray(buffer.offset, buffer.offset + buffer.disk)
  const rgba = new Uint8ClampedArray(width * height * 4)
  const row = width * 4
  for (let y = 0; y < height; y++) {
    const src = (height - 1 - y) * row
    const dst = y * row
    for (let x = 0; x < row; x += 4) {
      const a = px[src + x + 3]
      rgba[dst + x + 3] = a
      if (a === 0) continue
      const k = a << 8
      rgba[dst + x] = UNPREMULTIPLY[k | px[src + x]]
      rgba[dst + x + 1] = UNPREMULTIPLY[k | px[src + x + 1]]
      rgba[dst + x + 2] = UNPREMULTIPLY[k | px[src + x + 2]]
    }
  }
  return { width, height, rgba }
}

/** The .xbm an .inkatlas names, as a depot path. */
function textureOfAtlas(f: Cr2wFile): string | null {
  const root = f.exports[0]
  if (!root || root.cls !== 'inkTextureAtlas') return null
  return f.imports.find((p) => p.toLowerCase().endsWith('.xbm')) ?? null
}

/**
 * Whether an archive's index lists a path. The index is never compressed, so this reads any
 * WolvenKit archive. Null when the bytes are not an archive at all.
 */
export async function archiveHasPath(archive: Blob, path: string): Promise<boolean | null> {
  try {
    const files = readIndex(new DataView(await archive.arrayBuffer()))
    if (!files) return null
    const hash = fnv1a64(path.replace(/\//g, '\\').toLowerCase())
    return files.some((f) => f.hash === hash)
  } catch {
    return null
  }
}

/**
 * The icon an archive holds for that atlas path, as an image the page can draw. Null when the
 * archive does not hold it, or holds it compressed.
 */
export async function iconFromArchive(archive: Blob, atlasPath: string): Promise<{ url: string; size: [number, number] } | null> {
  try {
    const bytes = new Uint8Array(await archive.arrayBuffer())
    const view = new DataView(bytes.buffer)
    const files = readIndex(view)
    if (!files) return null
    const stored = (file: ArchiveFile, index: number): Uint8Array | null => {
      const s = file.segments[index]
      if (!s || s.zsize !== s.size) return null
      return bytes.subarray(s.offset, s.offset + s.size)
    }
    const read = (path: string): Cr2wFile | null => {
      const hash = fnv1a64(path.replace(/\//g, '\\').toLowerCase())
      const file = files.find((f) => f.hash === hash)
      if (!file) return null
      const head = stored(file, 0)
      const parsed = head && readCr2w(head)
      if (!parsed) return null
      // Each buffer is its own segment; the reader wants them where the file's own table says.
      const whole = new Uint8Array(parsed.buffers.reduce((end, b) => Math.max(end, b.offset + b.disk), head!.length))
      whole.set(head!)
      for (let i = 0; i < parsed.buffers.length; i++) {
        const buffer = stored(file, i + 1)
        if (!buffer) return null
        whole.set(buffer, parsed.buffers[i].offset)
      }
      return { ...parsed, bytes: whole }
    }
    const atlas = read(atlasPath)
    const texturePath = atlas && textureOfAtlas(atlas)
    const texture = texturePath ? read(texturePath) : null
    const icon = texture && readTexture(texture)
    if (!icon) return null
    const canvas = document.createElement('canvas')
    canvas.width = icon.width
    canvas.height = icon.height
    const ctx = canvas.getContext('2d')
    if (!ctx) return null
    const image = ctx.createImageData(icon.width, icon.height)
    image.data.set(icon.rgba)
    ctx.putImageData(image, 0, 0)
    const blob = await new Promise<Blob | null>((done) => canvas.toBlob(done, 'image/png'))
    if (!blob) return null
    return { url: URL.createObjectURL(blob), size: [icon.width, icon.height] }
  } catch {
    return null
  }
}
