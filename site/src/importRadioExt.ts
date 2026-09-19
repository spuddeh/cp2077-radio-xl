/**
 * Reads a RadioExt station into the form: its `metadata.json`, its audio files and its icon.
 *
 * RadioExt keeps a station as a folder of audio beside a `metadata.json`, under
 * `bin/x64/plugins/cyber_engine_tweaks/mods/radioExt/radios/<station>/`. Its icon lives in the mod's
 * own `.archive`, which is carried across untouched; nothing is converted in place. The mapping is
 * the one in `tools/radioext-to-radioxl.py`.
 */
import type { Entry, ExtraFile, ImportedStation, ImportedTrack } from './importStation'
import { cnameFrom } from './store'
import { VANILLA_STATIONS } from './vanilla'
import { iconFromArchive } from './readArchive'

const AUDIO = /\.(wav|mp3|ogg|flac)$/i
/** Keys RadioExt writes that carry across, so anything else can be named in a note. */
const KNOWN = new Set(['displayName', 'fm', 'volume', 'order', 'icon', 'customIcon', 'streamInfo'])

function titleOf(file: string): string {
  return (file.split('/').pop() ?? file).replace(/\.[^.]+$/, '')
}

export async function importRadioExt(entries: Entry[]): Promise<ImportedStation> {
  const metas = entries.filter((e) => /(^|\/)metadata\.json$/i.test(e.path))
  if (!metas.length) throw new Error('No metadata.json was found. Drop the RadioExt station folder, or the mod that holds it.')
  const metaEntry = metas.find((e) => /radios\/[^/]+\/metadata\.json$/i.test(e.path)) ?? metas[0]
  const base = metaEntry.path.slice(0, metaEntry.path.length - 'metadata.json'.length)
  const notes: string[] = []
  if (metas.length > 1) notes.push(`${metas.length} stations were found; ${metaEntry.path} was read.`)

  const text = (await (await metaEntry.blob()).text()).replace(/^\uFEFF/, '')
  let m: Record<string, unknown>
  try {
    m = JSON.parse(text)
  } catch (e) {
    throw new Error(`metadata.json is not valid JSON: ${(e as Error).message}`)
  }
  if (!m || typeof m !== 'object' || Array.isArray(m)) throw new Error('metadata.json does not hold a station.')

  const ignored = Object.keys(m).filter((k) => !KNOWN.has(k))
  if (ignored.length) notes.push(`RadioExt keys with nothing to map to were left out: ${ignored.join(', ')}.`)

  // RadioExt's "fm" maps straight onto the manifest's frequency; the number RadioExt authors also
  // put at the front of the display name is taken off the name and used only when "fm" is absent.
  const display = typeof m.displayName === 'string' ? m.displayName.trim() : ''
  const parts = display.match(/^\s*(\d{2,3}(?:\.\d+)?)\s*(.*)$/)
  const fm = typeof m.fm === 'number' && Number.isFinite(m.fm) ? m.fm : null
  const frequency = fm !== null ? String(fm) : parts ? parts[1] : ''
  const stationName = parts ? parts[2].trim() : display
  if (fm === null && parts) notes.push(`The station has no "fm", so the frequency ${parts[1]} came from the front of its name.`)
  if (fm !== null && parts && Number.parseFloat(parts[1]) !== fm) notes.push(`The name started with ${parts[1]} but "fm" is ${fm}. The frequency is ${fm}; the number was taken off the name.`)

  // RadioExt's volume was tuned against RadioExt's own player, which says nothing about the level
  // on RadioXL's chain, and auto level puts every track on the game's own level as the files are
  // measured. A station Volume other than 100% on top of that moves the whole station off target
  // by exactly RadioExt's number, so the station comes across at 100% and the note says what it was.
  const volume = typeof m.volume === 'number' ? m.volume : 1
  const gain = 1
  if (Math.abs(volume - 1) >= 0.005)
    notes.push(
      `RadioExt's volume was ${volume}. It was set against RadioExt's own player, so the station comes across at 100%: Auto level puts each track on the game's own level. Set the Volume slider yourself only if you turn Auto level off.`,
    )

  const stream = (m.streamInfo ?? {}) as Record<string, unknown>
  const streamUrl = stream.isStream === true && typeof stream.streamURL === 'string' ? stream.streamURL.trim() : ''

  const tracks: ImportedTrack[] = []
  const used = new Set<string>([metaEntry.path.toLowerCase()])
  if (streamUrl) {
    tracks.push({ file: '', url: streamUrl, title: '', ident: false, gain: 1 })
    notes.push('This station is a stream, so it came across as one url track.')
  } else {
    const audio = entries.filter((e) => e.path.toLowerCase().startsWith(base.toLowerCase()) && AUDIO.test(e.path))
    const name = (e: Entry) => e.path.slice(base.length)
    const order = (Array.isArray(m.order) ? m.order : []).filter((x): x is string => typeof x === 'string')
    const ranked = [...audio].sort((a, b) => {
      const ia = order.indexOf(name(a))
      const ib = order.indexOf(name(b))
      if (ia !== ib) return (ia < 0 ? order.length : ia) - (ib < 0 ? order.length : ib)
      return name(a).localeCompare(name(b))
    })
    for (const e of ranked) {
      used.add(e.path.toLowerCase())
      tracks.push({ file: `audio/${name(e)}`, title: titleOf(e.path), ident: false, source: await e.blob(), gain: 1 })
    }
    if (!ranked.length) notes.push('No audio file was found beside metadata.json.')
  }

  const custom = (m.customIcon ?? {}) as Record<string, unknown>
  const atlas = custom.useCustom === true && typeof custom.inkAtlasPath === 'string' ? custom.inkAtlasPath : ''
  const part = typeof custom.inkAtlasPart === 'string' ? custom.inkAtlasPart : ''
  const record = typeof m.icon === 'string' ? m.icon : ''
  const vanilla = VANILLA_STATIONS.find((v) => v.icon === record)

  // The icon is in the mod's own archive; it is carried across, at the path a mod manager installs.
  const extras: ExtraFile[] = []
  for (const e of entries) {
    if (used.has(e.path.toLowerCase()) || !/\.archive$/i.test(e.path)) continue
    extras.push({ path: `archive/pc/mod/${e.path.split('/').pop()}`, source: await e.blob() })
  }
  if (atlas && !extras.length)
    notes.push(`The icon is ${part} in ${atlas}, which is in the mod's own archive. Drop the whole mod to carry it across, or add the archive to the zip yourself.`)
  if (extras.length) notes.push(`Carried over unchanged: ${extras.map((x) => x.path).join(', ')}.`)

  let icon: { url: string; size: [number, number] } | null = null
  if (atlas && extras.length) {
    for (const e of extras) {
      icon = await iconFromArchive(e.source, atlas)
      if (icon) break
    }
    notes.push(
      icon
        ? 'The preview icon was read from that archive.'
        : 'The icon archive is compressed, so the preview cannot read it. Choose an image to see the icon.',
    )
  }

  // RadioExt's label was the name as written, so a name with no number in it showed none.
  const showFrequency = parts !== null
  if (!showFrequency && stationName) notes.push('The name carried no frequency, so the label keeps it off. Show frequency turns it back on.')

  return {
    folder: '',
    frequency,
    showFrequency,
    stationName,
    cname: cnameFrom(stationName),
    news: false,
    gain,
    iconMode: atlas ? 'atlas' : record ? 'record' : 'glyph',
    iconChoice: vanilla ? vanilla.icon : record && !atlas ? 'other' : 'UIIcon.RadioDowntempo',
    iconRecord: !vanilla && !atlas ? record : '',
    iconPart: atlas ? part : '',
    iconAtlas: atlas,
    iconImage: icon?.url ?? null,
    iconImageSize: icon?.size ?? null,
    iconArchiveUnreadable: !!atlas && extras.length > 0 && !icon,
    tracks,
    extras,
    notes,
  }
}
