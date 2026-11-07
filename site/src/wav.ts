/**
 * Whether a WAV will play in game, and the conversion for one that will not. AudioXL takes a WAV
 * only with its `fmt` chunk first, format tag 1, and a walk from chunk to chunk with no pad byte that
 * reaches `data`, at 500 MB or less. Past that, the game's audio engine plays 16-bit integer samples
 * only: a 24-bit file passes AudioXL's own check and is silent.
 */

const MAX_BYTES = 0x1f400000
const MIN_BYTES = 0x40
const MAX_RATE = 192000
const MAX_CHANNELS = 8
const CHUNK_FRAMES = 1 << 18

export interface WavFault {
  /** What is wrong with the file, to follow "This WAV won't play in game:". */
  reason: string
  /** False when the file needs a re-export or another format, not this page's conversion. */
  convertible: boolean
}

/** What a conversion reads from a file, wherever its chunks sit. */
export interface WavLayout {
  encoding: 'int' | 'float' | 'other'
  bits: number
  channels: number
  rate: number
  dataStart: number
  dataSize: number
}

async function bytes(blob: Blob, from: number, count: number): Promise<DataView> {
  return new DataView(await blob.slice(from, from + count).arrayBuffer())
}

function tagAt(view: DataView, at: number): string {
  return String.fromCharCode(view.getUint8(at), view.getUint8(at + 1), view.getUint8(at + 2), view.getUint8(at + 3))
}

/** The file's format and audio by the RIFF rules, pad bytes included. Null when it has neither. */
export async function readLayout(blob: Blob): Promise<WavLayout | null> {
  if (blob.size < 12) return null
  const head = await bytes(blob, 0, 12)
  const magic = tagAt(head, 0)
  if ((magic !== 'RIFF' && magic !== 'RF64') || tagAt(head, 8) !== 'WAVE') return null
  let fmt: DataView | null = null
  let bigData = 0
  let at = 12
  while (at + 8 <= blob.size) {
    const chunk = await bytes(blob, at, 8)
    const id = tagAt(chunk, 0)
    const size = chunk.getUint32(4, true)
    const body = at + 8
    if (id === 'ds64') {
      const ds64 = await bytes(blob, body, 16)
      bigData = Number(ds64.getBigUint64(8, true))
    } else if (id === 'fmt ' && size >= 16) {
      fmt = await bytes(blob, body, Math.min(size, 40))
    } else if (id === 'data') {
      if (!fmt) return null
      const declared = size === 0xffffffff && bigData ? bigData : size
      const dataSize = declared === 0 || body + declared > blob.size ? blob.size - body : declared
      return { ...describeFormat(fmt), dataStart: body, dataSize }
    }
    at = body + size + (size & 1)
  }
  return null
}

function describeFormat(fmt: DataView): Omit<WavLayout, 'dataStart' | 'dataSize'> {
  const tag = fmt.getUint16(0, true)
  // An extensible header names the real format in the first two bytes of its sub-format.
  const real = tag === 0xfffe && fmt.byteLength >= 26 ? fmt.getUint16(24, true) : tag
  return {
    encoding: real === 1 ? 'int' : real === 3 ? 'float' : 'other',
    channels: fmt.getUint16(2, true),
    rate: fmt.getUint32(4, true),
    bits: fmt.getUint16(14, true),
  }
}

function canConvert(l: WavLayout): boolean {
  const known = l.encoding === 'int' ? [8, 16, 24, 32].includes(l.bits) : l.encoding === 'float' && [32, 64].includes(l.bits)
  return (
    known &&
    l.channels >= 1 &&
    l.channels <= MAX_CHANNELS &&
    l.rate >= 1 &&
    l.rate <= MAX_RATE &&
    l.dataSize >= l.channels * (l.bits / 8)
  )
}

function convertedBytes(l: WavLayout): number {
  return 44 + Math.floor(l.dataSize / (l.channels * (l.bits / 8))) * l.channels * 2
}

/** True when AudioXL's own walk, which skips no pad byte, reaches a `data` chunk inside the file. */
async function plainWalkReachesData(blob: Blob, fmtSize: number): Promise<boolean> {
  let at = 20 + fmtSize
  while (at + 8 <= blob.size) {
    const chunk = await bytes(blob, at, 8)
    const size = chunk.getUint32(4, true)
    if (tagAt(chunk, 0) === 'data') return at + 8 + size <= blob.size
    at += 8 + size
  }
  return false
}

function depthName(l: WavLayout): string {
  if (l.encoding === 'float') return `${l.bits}-bit float`
  if (l.encoding === 'int') return `${l.bits}-bit`
  return 'not PCM audio'
}

/** Null when the WAV will play, else what is wrong with it. */
export async function checkWav(blob: Blob): Promise<WavFault | null> {
  const layout = await readLayout(blob)
  if (!layout) return { reason: 'the page cannot read it as a WAV', convertible: false }

  const reason = await playReason(blob, layout)
  if (!reason) return null
  if (layout.encoding === 'other') {
    return { reason: `${reason}. Export it from your audio editor as 16-bit PCM, or as FLAC`, convertible: false }
  }
  if (!canConvert(layout)) return { reason: `${reason}. Export it from your audio editor as 16-bit PCM`, convertible: false }
  if (convertedBytes(layout) > MAX_BYTES) {
    return { reason: `${reason}, and at 16-bit it is still over the 500 MB limit. Use FLAC, or split it`, convertible: false }
  }
  return { reason, convertible: true }
}

async function playReason(blob: Blob, l: WavLayout): Promise<string | null> {
  if (l.encoding !== 'int' || l.bits !== 16) return depthName(l)
  if (blob.size > MAX_BYTES) return 'over the 500 MB limit'
  if (blob.size < MIN_BYTES) return 'too short'
  const h = await bytes(blob, 0, 36)
  const fmtFirst = tagAt(h, 0) === 'RIFF' && tagAt(h, 12) === 'fmt '
  if (!fmtFirst) return 'its format section is not first in the file'
  if (h.getUint16(20, true) !== 1) return 'it has an extended header'
  if (l.channels < 1 || l.channels > MAX_CHANNELS) return `${l.channels} channels`
  if (l.rate < 1 || l.rate > MAX_RATE) return `a sample rate of ${l.rate} Hz`
  const frameBytes = l.channels * 2
  if (h.getUint32(28, true) !== frameBytes * l.rate || h.getUint16(32, true) !== frameBytes) {
    return 'its header contradicts itself'
  }
  if (!(await plainWalkReachesData(blob, h.getUint32(16, true)))) return 'an odd-sized section hides its audio'
  return null
}

function header(l: WavLayout, dataBytes: number): ArrayBuffer {
  const out = new DataView(new ArrayBuffer(44))
  const put = (at: number, text: string) => {
    for (let i = 0; i < text.length; i++) out.setUint8(at + i, text.charCodeAt(i))
  }
  put(0, 'RIFF')
  out.setUint32(4, 36 + dataBytes, true)
  put(8, 'WAVE')
  put(12, 'fmt ')
  out.setUint32(16, 16, true)
  out.setUint16(20, 1, true)
  out.setUint16(22, l.channels, true)
  out.setUint32(24, l.rate, true)
  out.setUint32(28, l.rate * l.channels * 2, true)
  out.setUint16(32, l.channels * 2, true)
  out.setUint16(34, 16, true)
  put(36, 'data')
  out.setUint32(40, dataBytes, true)
  return out.buffer
}

function to16(unit: number): number {
  if (Number.isNaN(unit)) return 0
  const scaled = Math.round(unit * 32768)
  return scaled > 32767 ? 32767 : scaled < -32768 ? -32768 : scaled
}

/** One sample as a value where full scale is 1. */
function reader(l: WavLayout): (view: DataView, at: number) => number {
  if (l.encoding === 'float') {
    return l.bits === 64 ? (v, at) => v.getFloat64(at, true) : (v, at) => v.getFloat32(at, true)
  }
  switch (l.bits) {
    case 8:
      return (v, at) => (v.getUint8(at) - 128) / 128
    case 16:
      return (v, at) => v.getInt16(at, true) / 32768
    case 24:
      return (v, at) => ((v.getInt8(at + 2) << 16) | (v.getUint8(at + 1) << 8) | v.getUint8(at)) / 8388608
    default:
      return (v, at) => v.getInt32(at, true) / 2147483648
  }
}

/** The same audio as a plain 16-bit PCM WAV. A file already 16-bit keeps its samples exactly. */
export async function convertWav(blob: Blob, onProgress?: (fraction: number) => void): Promise<Blob> {
  const l = await readLayout(blob)
  if (!l || !canConvert(l)) throw new Error('The page cannot convert this file.')
  const inSample = l.bits / 8
  const inFrame = inSample * l.channels
  const frames = Math.floor(l.dataSize / inFrame)
  const outBytes = frames * l.channels * 2
  if (l.encoding === 'int' && l.bits === 16) {
    return new Blob([header(l, outBytes), blob.slice(l.dataStart, l.dataStart + outBytes)], { type: 'audio/wav' })
  }
  const read = reader(l)
  const parts: BlobPart[] = [header(l, outBytes)]
  for (let done = 0; done < frames; done += CHUNK_FRAMES) {
    const count = Math.min(CHUNK_FRAMES, frames - done)
    const from = l.dataStart + done * inFrame
    const input = await bytes(blob, from, count * inFrame)
    const output = new DataView(new ArrayBuffer(count * l.channels * 2))
    const samples = count * l.channels
    for (let i = 0; i < samples; i++) output.setInt16(i * 2, to16(read(input, i * inSample)), true)
    parts.push(output.buffer)
    onProgress?.((done + count) / frames)
  }
  return new Blob(parts, { type: 'audio/wav' })
}
