import { readZip, type ZipEntry } from './readZip'
import { isArchiveName, readArchiveFile } from './readAnyArchive'
import { VANILLA_STATIONS } from './vanilla'
import type { IconMode } from './store'
import { iconFromArchive } from './readArchive'

export interface ImportedTrack {
  file: string
  url?: string
  title: string
  ident: boolean
  source?: Blob
}

/** A file in the dropped mod that is not the manifest or a track, carried into the zip unchanged. */
export interface ExtraFile {
  path: string
  source: Blob
}

export interface ImportedStation {
  folder: string
  frequency: string
  stationName: string
  cname: string
  news: boolean
  gain: number
  iconMode: IconMode
  iconChoice: string
  iconRecord: string
  iconPart: string
  iconAtlas: string
  /** The icon read back out of the station's own archive, for the preview. */
  iconImage: string | null
  iconImageSize: [number, number] | null
  /** True when the station carries an icon archive the page cannot read. */
  iconArchiveUnreadable: boolean
  tracks: ImportedTrack[]
  extras: ExtraFile[]
  /** What the import could not bring across, for the page to say. */
  notes: string[]
}

export type Entry = Pick<ZipEntry, 'path' | 'size' | 'blob'>

const KNOWN = new Set(['name', 'frequency', 'displayName', 'news', 'gain', 'icon', 'atlas', 'tracks'])
const TRACK_KEYS = new Set(['file', 'url', 'title', 'ident'])
/** Mod manager and OS files that are not part of a mod. */
const JUNK = /(^|\/)(meta\.ini|desktop\.ini|thumbs\.db|\.ds_store)$/i

/** Files from a folder picker or a drop, with their paths inside the dropped folder. */
export function entriesFromFiles(files: File[]): Entry[] {
  return files.map((f) => ({
    path: (f.webkitRelativePath || (f as File & { importPath?: string }).importPath || f.name).replace(/\\/g, '/'),
    size: f.size,
    blob: async () => f,
  }))
}

/** Everything under the dropped items, walking folders. A single .zip is opened. */
export async function entriesFromDrop(items: DataTransferItemList): Promise<Entry[]> {
  const roots = [...items].map((i) => i.webkitGetAsEntry()).filter((e): e is FileSystemEntry => !!e)
  if (roots.length === 1 && roots[0].isFile && isArchiveName(roots[0].name)) {
    const file = await new Promise<File>((ok, fail) => (roots[0] as FileSystemFileEntry).file(ok, fail))
    return readArchiveFile(file)
  }
  const out: Entry[] = []
  const walk = async (entry: FileSystemEntry, prefix: string): Promise<void> => {
    if (entry.isFile) {
      const file = await new Promise<File>((ok, fail) => (entry as FileSystemFileEntry).file(ok, fail))
      out.push({ path: prefix + entry.name, size: file.size, blob: async () => file })
      return
    }
    const reader = (entry as FileSystemDirectoryEntry).createReader()
    // readEntries returns a batch at a time; an empty batch means the folder is done.
    for (;;) {
      const batch = await new Promise<FileSystemEntry[]>((ok, fail) => reader.readEntries(ok, fail))
      if (!batch.length) break
      for (const child of batch) await walk(child, prefix + entry.name + '/')
    }
  }
  for (const root of roots) await walk(root, '')
  return out
}

export { readZip }
export { readArchiveFile } from './readAnyArchive'

/**
 * Reads a RadioXL station mod: the first station.json found, its fields into the form, each track
 * matched to its audio by path, and every other file kept to go back into the zip.
 */
export async function importStation(entries: Entry[]): Promise<ImportedStation> {
  const manifests = entries.filter((e) => /(^|\/)station\.json$/i.test(e.path))
  if (!manifests.length) throw new Error('No station.json was found. Drop the station mod, its zip or its folder.')
  const manifestEntry = manifests.find((e) => /stations\/[^/]+\/station\.json$/i.test(e.path)) ?? manifests[0]
  const base = manifestEntry.path.slice(0, manifestEntry.path.length - 'station.json'.length)
  const notes: string[] = []
  if (manifests.length > 1) notes.push(`${manifests.length} station.json files were found; ${manifestEntry.path} was opened.`)

  const text = (await (await manifestEntry.blob()).text()).replace(/^\uFEFF/, '')
  let m: Record<string, unknown>
  try {
    m = JSON.parse(text)
  } catch (e) {
    throw new Error(`station.json is not valid JSON: ${(e as Error).message}`)
  }
  if (!m || typeof m !== 'object' || Array.isArray(m)) throw new Error('station.json does not hold a station.')

  const ignored = Object.keys(m).filter((k) => !KNOWN.has(k))
  if (ignored.length) notes.push(`Keys RadioXL does not read were left out: ${ignored.join(', ')}.`)

  // The frequency is its own field; a manifest written for 0.3.0 carried it at the front of the
  // display name, and the plugin still reads it from there, so the page does too.
  const display = typeof m.displayName === 'string' ? m.displayName : ''
  const leading = display.match(/^\s*(\d{2,3}(?:\.\d+)?)\s*(.*)$/)
  const field = typeof m.frequency === 'number' && Number.isFinite(m.frequency) ? m.frequency : null
  const frequency = field !== null ? String(field) : leading ? leading[1] : ''
  const stationName = leading ? leading[2].trim() : display.trim()
  if (field === null && leading) notes.push(`The frequency ${leading[1]} was read from the front of the name; RadioXL now takes it as its own field, which Build .zip writes.`)
  if (field !== null && leading) notes.push(`The name started with ${leading[1]} and the manifest also had frequency ${field}. The field was kept; the number was taken off the name.`)
  const icon = typeof m.icon === 'string' ? m.icon : ''
  const atlas = typeof m.atlas === 'string' ? m.atlas : ''
  const vanilla = VANILLA_STATIONS.find((v) => v.icon === icon)

  const byPath = new Map(entries.map((e) => [e.path.toLowerCase(), e]))
  const used = new Set<string>([manifestEntry.path.toLowerCase()])
  const tracks: ImportedTrack[] = []
  for (const raw of Array.isArray(m.tracks) ? m.tracks : []) {
    if (!raw || typeof raw !== 'object') continue
    const t = raw as Record<string, unknown>
    const extraKeys = Object.keys(t).filter((k) => !TRACK_KEYS.has(k))
    if (extraKeys.length) notes.push(`Track keys RadioXL does not read were left out: ${extraKeys.join(', ')}.`)
    const title = typeof t.title === 'string' ? t.title : ''
    const ident = t.ident === true
    if (typeof t.url === 'string') {
      // The plugin refuses a track with both. A stream already plays on its own, so the url is the
      // track and the file beside it goes; an ident cannot be a stream either.
      if (typeof t.file === 'string' && t.file.trim())
        notes.push(`A track named both a stream and a file (${t.file}). The stream was kept: a stream plays on its own.`)
      if (ident) notes.push('A stream was marked as an ident, which RadioXL refuses. It came across as an ordinary track.')
      tracks.push({ file: '', url: t.url, title, ident: false })
      continue
    }
    if (typeof t.file !== 'string') continue
    const file = t.file.replace(/\\/g, '/')
    const entry = byPath.get((base + file).toLowerCase())
    if (entry) used.add(entry.path.toLowerCase())
    tracks.push({ file, title, ident, source: entry ? await entry.blob() : undefined })
  }
  const missing = tracks.filter((t) => !t.url && !t.source).length
  if (missing) notes.push(`${missing} track${missing > 1 ? 's have' : ' has'} no audio file in what was dropped.`)

  // Other files keep their place in the mod: paths are taken from the mod's root (the folder that
  // holds red4ext/), and a station folder dropped on its own is put back under stations/.
  const underRed4ext = manifestEntry.path.toLowerCase().indexOf('red4ext/')
  const modRoot = underRed4ext >= 0 ? manifestEntry.path.slice(0, underRed4ext) : null
  const folderName = (base.match(/([^/]+)\/$/) ?? [])[1] ?? ''
  const extras: ExtraFile[] = []
  for (const e of entries) {
    if (used.has(e.path.toLowerCase()) || JUNK.test(e.path)) continue
    let rel: string
    if (modRoot !== null && e.path.startsWith(modRoot)) rel = e.path.slice(modRoot.length)
    else if (modRoot === null && e.path.startsWith(base)) rel = `red4ext/plugins/RadioXL/stations/${folderName}/${e.path.slice(base.length)}`
    else rel = e.path
    extras.push({ path: rel, source: await e.blob() })
  }
  if (extras.length) notes.push(`Carried over unchanged: ${extras.map((x) => x.path).join(', ')}.`)

  // An archive this page wrote stores its icon uncompressed, so the preview can show it again.
  let iconPreview: { url: string; size: [number, number] } | null = null
  const archive = atlas ? extras.find((x) => /\.archive$/i.test(x.path)) : undefined
  if (archive) {
    iconPreview = await iconFromArchive(await archive.source, atlas)
    notes.push(
      iconPreview
        ? 'The preview icon was read from that archive.'
        : 'The icon archive is compressed, so the preview cannot read it. Choose an image to see the icon.',
    )
  }

  return {
    folder: folderName,
    frequency,
    stationName,
    cname: typeof m.name === 'string' ? m.name : '',
    news: m.news === true,
    gain: typeof m.gain === 'number' ? Math.max(0, Math.min(1, m.gain)) : 1,
    iconMode: atlas ? 'atlas' : icon ? 'record' : 'glyph',
    iconChoice: vanilla ? vanilla.icon : icon && !atlas ? 'other' : 'UIIcon.RadioDowntempo',
    iconRecord: !vanilla && !atlas ? icon : '',
    iconPart: atlas ? icon : '',
    iconAtlas: atlas,
    iconImage: iconPreview?.url ?? null,
    iconImageSize: iconPreview?.size ?? null,
    iconArchiveUnreadable: !!archive && !iconPreview,
    tracks,
    extras,
    notes,
  }
}
