/**
 * The files the browser tests hand to the page, written to a temporary folder: a small icon, a
 * stand-in audio file, and a RadioExt station as a zip. They are built here rather than committed,
 * so nothing binary lives in the repo.
 */
import { mkdtemp, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { deflateSync, crc32 } from 'node:zlib'

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
  const radioExt = join(dir, 'radioext-station.zip')
  await writeFile(icon, png(24, 16, [255, 255, 255, 255]))
  await writeFile(song, Buffer.alloc(4096))
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
  return { dir, icon, song, radioExt }
}
