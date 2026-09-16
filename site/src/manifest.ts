import { defaultIconTarget, type Track } from './store'

export interface ManifestInput {
  frequency: string
  stationName: string
  cname: string
  news: boolean
  gain: number
  iconMode: 'glyph' | 'record' | 'image' | 'atlas'
  iconChoice: string
  iconRecord: string
  iconPart: string
  iconAtlas: string
  /** In image mode, Build .zip writes the icon's archive from it. In atlas mode it is for the preview only. */
  iconImage: string | null
  iconImageSize: [number, number] | null
  iconImageHasPixels: boolean
  tracks: Track[]
}

/** The largest icon worth making, per side. PHONKWAVE Radio's is exactly this. */
export const ICON_IMAGE_RECOMMENDED = 500

/** Whether Build .zip writes the icon's texture, atlas and archive. */
export function generatesIcon(s: Pick<ManifestInput, 'iconMode' | 'iconImage'>): boolean {
  return s.iconMode === 'image' && s.iconImage !== null
}

/**
 * The part and atlas the manifest names. A generated icon fills an empty field from the station ID
 * and writes the path in lowercase, so the manifest and the archive name the same resource.
 */
export function iconTarget(s: Pick<ManifestInput, 'iconMode' | 'iconImage' | 'iconPart' | 'iconAtlas' | 'cname'>): { part: string; atlas: string } {
  const part = s.iconPart.trim()
  const atlas = s.iconAtlas.trim().replace(/\//g, '\\')
  if (!generatesIcon(s)) return { part, atlas }
  const fallback = defaultIconTarget(s.cname)
  return { part: part || fallback.part, atlas: (atlas || fallback.atlas).toLowerCase() }
}

/**
 * An `icon` the plugin reads as a TweakDB record rather than an atlas part: `UIIcon.` and at least
 * one character after it (`IsIconRecord` in Manifest.hpp). Anything else is a part, which needs an atlas.
 */
export function isIconRecord(icon: string): boolean {
  return /^UIIcon\..+/.test(icon.trim())
}

export interface Fault {
  field: string
  message: string
}

/** The label the game shows: the frequency, then the name, as the plugin composes it. */
export function displayName(s: Pick<ManifestInput, 'frequency' | 'stationName'>): string {
  return [s.frequency.trim(), s.stationName.trim()].filter(Boolean).join(' ')
}

/** The station.json the plugin reads. Keys at their defaults are left out. */
export function buildManifest(s: ManifestInput): Record<string, unknown> {
  const m: Record<string, unknown> = { name: s.cname }
  const frequency = Number.parseFloat(s.frequency.trim())
  if (Number.isFinite(frequency)) m.frequency = frequency
  if (s.stationName.trim()) m.displayName = s.stationName.trim()
  if (s.news) m.news = true
  if (s.gain < 1) m.gain = Math.round(s.gain * 100) / 100
  if (s.iconMode === 'record') {
    const record = s.iconChoice === 'other' ? s.iconRecord.trim() : s.iconChoice
    if (record) m.icon = record
  }
  if (s.iconMode === 'atlas' || s.iconMode === 'image') {
    const target = iconTarget(s)
    m.icon = target.part
    m.atlas = target.atlas
  }
  m.tracks = s.tracks.map((t) => {
    const out: Record<string, unknown> = t.url ? { url: t.url } : { file: t.file }
    if (t.ident) out.ident = true
    else if (t.title) out.title = t.title
    return out
  })
  return m
}

/** The refusals in plugin/src/Manifest.hpp that a form can reach. */
export function checkManifest(s: ManifestInput): Fault[] {
  const faults: Fault[] = []
  if (!s.cname) faults.push({ field: 'cname', message: 'A station needs an ID.' })
  else if (!/^[A-Za-z0-9_]+$/.test(s.cname))
    faults.push({ field: 'cname', message: 'Letters, digits and underscores only.' })
  if (!/^\d{2,3}(\.\d{1,2})?$/.test(s.frequency.trim()))
    faults.push({ field: 'frequency', message: 'A station needs a frequency, such as 90.5. It decides the place on the dial, and RadioXL refuses a station without one.' })
  if (s.tracks.length === 0) faults.push({ field: 'tracks', message: 'A station needs at least one song.' })
  else if (s.tracks.every((t) => t.ident))
    faults.push({ field: 'tracks', message: 'Every track is an ident. A station needs at least one song.' })
  const missing = s.tracks.filter((t) => !t.url && !t.source)
  if (missing.length)
    faults.push({ field: 'tracks', message: `No audio for ${missing.map((t) => t.file).join(', ')}. Remove the track or open the station with its files.` })
  if (s.tracks.some((t) => t.url) && s.tracks.length > 1)
    faults.push({ field: 'tracks', message: 'A station with a stream plays that stream only; remove the other tracks.' })
  // A station opened or converted can carry a track the form would not have made.
  const badUrl = s.tracks.filter((t) => t.url && !/^https?:\/\//i.test(t.url))
  if (badUrl.length)
    faults.push({ field: 'tracks', message: `A stream URL starts with http:// or https://: ${badUrl.map((t) => t.url).join(', ')}` })
  if (s.tracks.some((t) => t.url && t.ident))
    faults.push({ field: 'tracks', message: 'A stream cannot be an ident. An ident is a file that plays between songs.' })
  if (s.tracks.some((t) => !t.url && !t.file.trim()))
    faults.push({ field: 'tracks', message: 'A track has no file name.' })
  if (s.iconMode === 'record' && s.iconChoice === 'other' && !s.iconRecord.trim())
    faults.push({ field: 'icon', message: 'Name the icon record, or pick a station.' })
  else if (s.iconMode === 'record' && s.iconChoice === 'other' && !isIconRecord(s.iconRecord))
    faults.push({ field: 'icon', message: 'An icon record starts with UIIcon. and a name. RadioXL reads anything else as an atlas part, which needs its atlas.' })
  if (s.iconMode === 'atlas' && (!s.iconPart.trim() || !s.iconAtlas.trim()))
    faults.push({ field: 'icon', message: 'An atlas part needs both the part name and the atlas path.' })
  if (s.iconMode === 'image' && !s.iconImage)
    faults.push({ field: 'icon', message: 'Choose the image to make the icon from.' })
  if (generatesIcon(s)) {
    const { part, atlas } = iconTarget(s)
    // An empty field with no station ID yet names nothing; the station ID's own fault reports that.
    const named = s.cname !== '' || (s.iconPart.trim() !== '' && s.iconAtlas.trim() !== '')
    if (named && !/^[\x21-\x7e]+$/.test(part))
      faults.push({ field: 'icon', message: 'The part name is plain letters, digits and punctuation, with no spaces.' })
    if (named && !/^[a-z0-9_\-.]+(\\[a-z0-9_\-.]+)*\.inkatlas$/.test(atlas))
      faults.push({ field: 'icon', message: 'The atlas path is folders of letters, digits and underscores, ending in .inkatlas.' })
    else if (named && /^(base|ep1)\\/.test(atlas))
      faults.push({ field: 'icon', message: 'The atlas path must not start with base\\ or ep1\\. A path there can replace a file of the game.' })
    const size = s.iconImageSize
    if (size && (size[0] === 0 || size[1] === 0))
      faults.push({ field: 'icon', message: 'The icon image has no size. An SVG needs a width and height.' })
    if (!s.iconImageHasPixels)
      faults.push({ field: 'icon', message: 'Every pixel of the icon image is transparent, so nothing would show.' })
  }
  return faults
}
