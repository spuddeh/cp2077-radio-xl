/**
 * The files the browser tests hand to the page, written to a temporary folder: a small icon, a
 * stand-in audio file, and a RadioExt station as a zip. They are built here rather than committed,
 * so nothing binary lives in the repo.
 */
import { mkdtemp, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { deflateSync, crc32 } from 'node:zlib'

/**
 * A WAV the page can decode and measure: 16-bit stereo PCM at 48 kHz, a 997 Hz sine at -20 dBFS on
 * both channels, which reads -20.0 LUFS and peaks at -20.0 dBFS.
 */
function toneWav(seconds = 3, rate = 48000, dbfs = -20) {
  const frames = seconds * rate
  const data = Buffer.alloc(frames * 4)
  const amplitude = Math.pow(10, dbfs / 20) * 32767
  for (let n = 0; n < frames; n++) {
    const v = Math.round(amplitude * Math.sin((2 * Math.PI * 997 * n) / rate))
    data.writeInt16LE(v, n * 4)
    data.writeInt16LE(v, n * 4 + 2)
  }
  const header = Buffer.alloc(44)
  header.write('RIFF', 0, 'latin1')
  header.writeUInt32LE(36 + data.length, 4)
  header.write('WAVE', 8, 'latin1')
  header.write('fmt ', 12, 'latin1')
  header.writeUInt32LE(16, 16)
  header.writeUInt16LE(1, 20) // PCM
  header.writeUInt16LE(2, 22) // channels
  header.writeUInt32LE(rate, 24)
  header.writeUInt32LE(rate * 4, 28)
  header.writeUInt16LE(4, 32)
  header.writeUInt16LE(16, 34)
  header.write('data', 36, 'latin1')
  header.writeUInt32LE(data.length, 40)
  return Buffer.concat([header, data])
}

/** FNV-1a 64 over the lowercase path, the archive's file hash. */
function fnv1a64(text) {
  let hash = 0xcbf29ce484222325n
  for (const byte of Buffer.from(text.toLowerCase(), 'utf8')) {
    hash ^= BigInt(byte)
    hash = (hash * 0x100000001b3n) & 0xffffffffffffffffn
  }
  return hash
}

/** The smallest RDAR archive that lists a path: header, index, one file entry, one segment. */
function archiveListing(path) {
  const indexPos = 40
  const tableAt = indexPos + 16
  const filesAt = tableAt + 12
  const segsAt = filesAt + 56
  const out = Buffer.alloc(segsAt + 16)
  out.write('RDAR', 0, 'latin1')
  out.writeBigUInt64LE(BigInt(indexPos), 8)
  out.writeUInt32LE(1, tableAt) // files
  out.writeUInt32LE(1, tableAt + 4) // segments
  out.writeUInt32LE(0, tableAt + 8) // dependencies
  out.writeBigUInt64LE(fnv1a64(path), filesAt)
  out.writeUInt32LE(0, filesAt + 20)
  out.writeUInt32LE(1, filesAt + 24)
  return out
}

/** A PNG of one colour, written by hand: the page only needs something with pixels. */
function png(width, height, [r, g, b, a]) {
  const chunk = (type, body) => {
    const head = Buffer.concat([Buffer.from(type, 'latin1'), body])
    const out = Buffer.alloc(head.length + 8)
    out.writeUInt32BE(body.length, 0)
    head.copy(out, 4)
    out.writeUInt32BE(crc32(head) >>> 0, head.length + 4)
    return out
  }
  const ihdr = Buffer.alloc(13)
  ihdr.writeUInt32BE(width, 0)
  ihdr.writeUInt32BE(height, 4)
  ihdr[8] = 8 // bit depth
  ihdr[9] = 6 // RGBA
  const raw = Buffer.alloc(height * (1 + width * 4))
  for (let y = 0; y < height; y++) {
    const row = y * (1 + width * 4)
    for (let x = 0; x < width; x++) {
      raw.set([r, g, b, a], row + 1 + x * 4)
    }
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw)),
    chunk('IEND', Buffer.alloc(0)),
  ])
}

/** A zip with its entries stored, which is all the page's reader needs. */
function zip(files) {
  const parts = []
  const central = []
  let offset = 0
  for (const [name, data] of files) {
    const nameBytes = Buffer.from(name, 'utf8')
    const body = Buffer.from(data)
    const sum = crc32(body) >>> 0
    const local = Buffer.alloc(30)
    local.writeUInt32LE(0x04034b50, 0)
    local.writeUInt16LE(20, 4)
    local.writeUInt16LE(0x800, 6) // names are UTF-8
    local.writeUInt32LE(sum, 14)
    local.writeUInt32LE(body.length, 18)
    local.writeUInt32LE(body.length, 22)
    local.writeUInt16LE(nameBytes.length, 26)
    parts.push(local, nameBytes, body)

    const entry = Buffer.alloc(46)
    entry.writeUInt32LE(0x02014b50, 0)
    entry.writeUInt16LE(20, 4)
    entry.writeUInt16LE(20, 6)
    entry.writeUInt16LE(0x800, 8)
    entry.writeUInt32LE(sum, 16)
    entry.writeUInt32LE(body.length, 20)
    entry.writeUInt32LE(body.length, 24)
    entry.writeUInt16LE(nameBytes.length, 28)
    entry.writeUInt32LE(offset, 42)
    central.push(entry, nameBytes)
    offset += local.length + nameBytes.length + body.length
  }
  const directory = Buffer.concat(central)
  const end = Buffer.alloc(22)
  end.writeUInt32LE(0x06054b50, 0)
  end.writeUInt16LE(files.length, 8)
  end.writeUInt16LE(files.length, 10)
  end.writeUInt32LE(directory.length, 12)
  end.writeUInt32LE(offset, 16)
  return Buffer.concat([...parts, directory, end])
}

export async function writeFixtures() {
  const dir = await mkdtemp(join(tmpdir(), 'radioxl-fixtures-'))
  const icon = join(dir, 'icon.png')
  const song = join(dir, 'A Song.mp3')
  const tone = join(dir, 'Tone.wav')
  const radioExt = join(dir, 'radioext-station.zip')
  const radioExtBase = join(dir, 'radioext-base-atlas.zip')
  const ownArchive = join(dir, 'own_icons.archive')
  const gone = join(dir, 'Gone.mp3')
  await writeFile(gone, Buffer.alloc(2048))
  await writeFile(ownArchive, archiveListing('ownstation\\gui\\icons.inkatlas'))
  await writeFile(icon, png(24, 16, [255, 255, 255, 255]))
  await writeFile(song, Buffer.alloc(4096))
  await writeFile(tone, toneWav())
  const base = 'bin/x64/plugins/cyber_engine_tweaks/mods/radioExt/radios/test_station'
  await writeFile(
    radioExt,
    zip([
      [
        `${base}/metadata.json`,
        JSON.stringify({
          displayName: '88.8 Converted Station',
          fm: 88.8,
          volume: 2.5,
          icon: 'UIIcon.Stealth',
          customIcon: { inkAtlasPath: 'teststation\\gui\\icons.inkatlas', inkAtlasPart: 'icon_part', useCustom: true },
          streamInfo: { streamURL: '', isStream: false },
          order: ['Second.mp3', 'First.mp3'],
        }),
      ],
      [`${base}/First.mp3`, Buffer.alloc(2048)],
      [`${base}/Second.mp3`, Buffer.alloc(2048)],
      ['archive/pc/mod/test_station.archive', Buffer.alloc(512)],
    ]),
  )
  // A RadioExt station pointing its icon at one of the game's own atlases, with no archive: the
  // shape of the report in #48.
  const base2 = 'bin/x64/plugins/cyber_engine_tweaks/mods/radioExt/radios/dock_station'
  await writeFile(
    radioExtBase,
    zip([
      [
        `${base2}/metadata.json`,
        JSON.stringify({
          displayName: '66.6 Dock Station',
          fm: 66.6,
          volume: 1,
          icon: 'UIIcon.Stealth',
          customIcon: { inkAtlasPath: 'base\\gameplay\\gui\\ipod_screens\\ipd_jamies.inkatlas', inkAtlasPart: 'jamie', useCustom: true },
          streamInfo: { streamURL: '', isStream: false },
          order: ['Only.mp3'],
        }),
      ],
      [`${base2}/Only.mp3`, Buffer.alloc(2048)],
    ]),
  )
  return { dir, icon, song, tone, radioExt, radioExtBase, ownArchive, gone }
}
