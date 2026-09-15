import type { Track } from './store'

export interface ManifestInput {
  frequency: string
  stationName: string
  cname: string
  news: boolean
  gain: number
  iconMode: 'glyph' | 'record' | 'atlas'
  iconChoice: string
  iconRecord: string
  iconPart: string
  iconAtlas: string
  tracks: Track[]
}

export interface Fault {
  field: string
  message: string
}

export function displayName(s: Pick<ManifestInput, 'frequency' | 'stationName'>): string {
  return [s.frequency.trim(), s.stationName.trim()].filter(Boolean).join(' ')
}

/** The station.json the plugin reads. Keys at their defaults are left out. */
export function buildManifest(s: ManifestInput): Record<string, unknown> {
  const m: Record<string, unknown> = { name: s.cname, displayName: displayName(s) }
  if (s.news) m.news = true
  if (s.gain < 1) m.gain = Math.round(s.gain * 100) / 100
  if (s.iconMode === 'record') {
    const record = s.iconChoice === 'other' ? s.iconRecord.trim() : s.iconChoice
    if (record) m.icon = record
  }
  if (s.iconMode === 'atlas') {
    m.icon = s.iconPart
    m.atlas = s.iconAtlas.replace(/\//g, '\\')
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
  if (!/^\d{2,3}(\.\d)?$/.test(s.frequency.trim()))
    faults.push({ field: 'frequency', message: 'Without a number at the front, the station goes after every station that has one.' })
  if (s.tracks.length === 0) faults.push({ field: 'tracks', message: 'A station needs at least one song.' })
  else if (s.tracks.every((t) => t.ident))
    faults.push({ field: 'tracks', message: 'Every track is an ident. A station needs at least one song.' })
  const missing = s.tracks.filter((t) => !t.url && !t.source)
  if (missing.length)
    faults.push({ field: 'tracks', message: `No audio for ${missing.map((t) => t.file).join(', ')}. Remove the track or open the station with its files.` })
  if (s.tracks.some((t) => t.url) && s.tracks.length > 1)
    faults.push({ field: 'tracks', message: 'A station with a stream plays that stream only; remove the other tracks.' })
  if (s.iconMode === 'record' && s.iconChoice === 'other' && !s.iconRecord.trim())
    faults.push({ field: 'icon', message: 'Name the icon record, or pick a station.' })
  if (s.iconMode === 'atlas' && (!s.iconPart || !s.iconAtlas))
    faults.push({ field: 'icon', message: 'An atlas part needs both the part name and the atlas path.' })
  return faults
}
