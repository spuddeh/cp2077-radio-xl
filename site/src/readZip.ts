/** One file inside a zip, readable without loading the rest. */
export interface ZipEntry {
  path: string
  size: number
  blob: () => Promise<Blob>
}

const EOCD = 0x06054b50
const ZIP64_LOCATOR = 0x07064b50
const ZIP64_EOCD = 0x06064b50
const CENTRAL = 0x02014b50
const LOCAL = 0x04034b50

/**
 * Lists a zip from its central directory. A stored entry is a slice of the zip file itself, so
 * audio costs no memory; a deflated one is inflated with the browser's DecompressionStream.
 * ZIP64 is read, so a zip over 4 GB or 65,535 entries opens too.
 */
export async function readZip(file: Blob): Promise<ZipEntry[]> {
  const tailSize = Math.min(file.size, 65557)
  const tail = new DataView(await file.slice(file.size - tailSize).arrayBuffer())
  let eocd = -1
  for (let i = tail.byteLength - 22; i >= 0; i--) {
    if (tail.getUint32(i, true) === EOCD) {
      eocd = i
      break
    }
  }
  if (eocd < 0) throw new Error('Not a zip file.')

  let count = tail.getUint16(eocd + 10, true)
  let dirSize = tail.getUint32(eocd + 12, true)
  let dirOffset = tail.getUint32(eocd + 16, true)
  if (eocd >= 20 && tail.getUint32(eocd - 20, true) === ZIP64_LOCATOR) {
    const at = Number(tail.getBigUint64(eocd - 12, true))
    const z64 = new DataView(await file.slice(at, at + 56).arrayBuffer())
    if (z64.getUint32(0, true) === ZIP64_EOCD) {
      count = Number(z64.getBigUint64(32, true))
      dirSize = Number(z64.getBigUint64(40, true))
      dirOffset = Number(z64.getBigUint64(48, true))
    }
  }

  const dir = new DataView(await file.slice(dirOffset, dirOffset + dirSize).arrayBuffer())
  const decoder = new TextDecoder()
  const entries: ZipEntry[] = []
  let p = 0
  for (let n = 0; n < count && p + 46 <= dir.byteLength; n++) {
    if (dir.getUint32(p, true) !== CENTRAL) throw new Error('The zip directory is damaged.')
    const method = dir.getUint16(p + 10, true)
    let compressed = dir.getUint32(p + 20, true)
    let size = dir.getUint32(p + 24, true)
    const nameLen = dir.getUint16(p + 28, true)
    const extraLen = dir.getUint16(p + 30, true)
    const commentLen = dir.getUint16(p + 32, true)
    let local = dir.getUint32(p + 42, true)
    const path = decoder.decode(new Uint8Array(dir.buffer, dir.byteOffset + p + 46, nameLen)).replace(/\\/g, '/')

    // ZIP64 extra field: the values that overflowed, in this order.
    for (let e = p + 46 + nameLen; e + 4 <= p + 46 + nameLen + extraLen; ) {
      const id = dir.getUint16(e, true)
      const len = dir.getUint16(e + 2, true)
      if (id === 0x0001) {
        let q = e + 4
        if (size === 0xffffffff) (size = Number(dir.getBigUint64(q, true))), (q += 8)
        if (compressed === 0xffffffff) (compressed = Number(dir.getBigUint64(q, true))), (q += 8)
        if (local === 0xffffffff) local = Number(dir.getBigUint64(q, true))
      }
      e += 4 + len
    }
    p += 46 + nameLen + extraLen + commentLen
    if (path.endsWith('/')) continue

    const localAt = local
    const blob = async () => {
      const head = new DataView(await file.slice(localAt, localAt + 30).arrayBuffer())
      if (head.getUint32(0, true) !== LOCAL) throw new Error(`${path}: the zip entry is damaged.`)
      const start = localAt + 30 + head.getUint16(26, true) + head.getUint16(28, true)
      const data = file.slice(start, start + compressed)
      if (method === 0) return data
      if (method === 8) return new Response(data.stream().pipeThrough(new DecompressionStream('deflate-raw'))).blob()
      throw new Error(`${path}: compression method ${method} is not supported.`)
    }
    entries.push({ path, size, blob })
  }
  return entries
}
