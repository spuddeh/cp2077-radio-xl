import { create } from 'zustand'

export type Source = 'new' | 'radioext' | 'radioxl010'
export type IconMode = 'glyph' | 'record' | 'atlas'

export interface Track {
  id: number
  file: string
  title: string
  ident: boolean
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
  iconRecord: string
  iconPart: string
  iconAtlas: string
  tracks: Track[]
  set: (patch: Partial<StationState>) => void
  addFiles: (names: string[]) => void
  updateTrack: (id: number, patch: Partial<Track>) => void
  removeTrack: (id: number) => void
}

let nextId = 1

/** "Artist - Title.mp3" gives "Artist - Title"; the folder part of a path is dropped. */
export function titleFromFile(file: string): string {
  const base = file.split(/[\\/]/).pop() ?? file
  return base.replace(/\.[^.]+$/, '').replace(/_/g, ' ').trim()
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
  iconRecord: '',
  iconPart: '',
  iconAtlas: '',
  tracks: [],
  set: (patch) =>
    set((s) => {
      const next = { ...s, ...patch }
      if ('stationName' in patch && !s.cnameEdited) next.cname = cnameFrom(next.stationName)
      return next
    }),
  addFiles: (names) =>
    set((s) => ({
      tracks: [
        ...s.tracks,
        ...names.map((file) => ({ id: nextId++, file: `audio/${file}`, title: titleFromFile(file), ident: false })),
      ],
    })),
  updateTrack: (id, patch) => set((s) => ({ tracks: s.tracks.map((t) => (t.id === id ? { ...t, ...patch } : t)) })),
  removeTrack: (id) => set((s) => ({ tracks: s.tracks.filter((t) => t.id !== id) })),
}))
