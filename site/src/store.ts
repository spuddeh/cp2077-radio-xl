import { create } from 'zustand'

export type Source = 'new' | 'radioext' | 'radioxl010'
export type IconMode = 'glyph' | 'record' | 'atlas'

export interface Track {
  id: number
  file: string
  title: string
  ident: boolean
  /** The audio file the zip copies in. */
  source?: File
}

interface StationState {
  source: Source
  frequency: string
  stationName: string
  cname: string
  cnameEdited: boolean
  news: boolean
  gain: number
  iconMode: IconMode
  /** A vanilla station's `UIIcon` record, or `other` for the free-text record. */
  iconChoice: string
  iconRecord: string
  iconPart: string
  iconAtlas: string
  /** An image for the preview only; the zip does not carry it. */
  iconImage: string | null
  tracks: Track[]
  set: (patch: Partial<StationState>) => void
  addFiles: (files: File[]) => void
  updateTrack: (id: number, patch: Partial<Track>) => void
  removeTrack: (id: number) => void
}

let nextId = 1

/** "Artist - Title.mp3" gives "Artist - Title"; the folder part of a path is dropped. */
export function titleFromFile(file: string): string {
  const base = file.split(/[\\/]/).pop() ?? file
  return base.replace(/\.[^.]+$/, '').replace(/_/g, ' ').trim()
}

/** Two files with one name would overwrite each other in the zip, so the second is numbered. */
function uniquePath(path: string, taken: Set<string>): string {
  if (!taken.has(path.toLowerCase())) return path
  const dot = path.lastIndexOf('.')
  const stem = dot > 0 ? path.slice(0, dot) : path
  const ext = dot > 0 ? path.slice(dot) : ''
  for (let n = 2; ; n++) if (!taken.has(`${stem} (${n})${ext}`.toLowerCase())) return `${stem} (${n})${ext}`
}

/** A CName is letters, digits and underscores; the station name is the only input to it. */
export function cnameFrom(name: string): string {
  const slug = name
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
  return slug ? `radio_station_${slug}` : ''
}

export const useStation = create<StationState>((set) => ({
  source: 'new',
  frequency: '',
  stationName: '',
  cname: '',
  cnameEdited: false,
  news: false,
  gain: 1,
  iconMode: 'glyph',
  iconChoice: 'UIIcon.RadioDowntempo',
  iconRecord: '',
  iconPart: '',
  iconAtlas: '',
  iconImage: null,
  tracks: [],
  set: (patch) =>
    set((s) => {
      const next = { ...s, ...patch }
      if ('stationName' in patch && !s.cnameEdited) next.cname = cnameFrom(next.stationName)
      return next
    }),
  addFiles: (files) =>
    set((s) => {
      const taken = new Set(s.tracks.map((t) => t.file.toLowerCase()))
      const added = files.map((source) => {
        const file = uniquePath(`audio/${source.name}`, taken)
        taken.add(file.toLowerCase())
        return { id: nextId++, file, title: titleFromFile(source.name), ident: false, source }
      })
      return { tracks: [...s.tracks, ...added] }
    }),
  updateTrack: (id, patch) => set((s) => ({ tracks: s.tracks.map((t) => (t.id === id ? { ...t, ...patch } : t)) })),
  removeTrack: (id) => set((s) => ({ tracks: s.tracks.filter((t) => t.id !== id) })),
}))
