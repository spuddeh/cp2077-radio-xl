import { create } from 'zustand'

import type { ImportedStation } from './importStation'
import type { Measurement } from './loudness'

export type Source = 'new' | 'radioext'
export type IconMode = 'glyph' | 'record' | 'image' | 'atlas'

/** The name a generated icon takes before the station has an ID. */
export const ICON_TARGET_FALLBACK = 'my_station'

/** The part and atlas a generated icon takes from the station ID. */
export function defaultIconTarget(cname: string): { part: string; atlas: string } {
  const name = cname || ICON_TARGET_FALLBACK
  return { part: name, atlas: `${name}\\gui\\${name}.inkatlas` }
}

export interface Track {
  id: number
  file: string
  title: string
  ident: boolean
  /** In place of file: a stream. */
  url?: string
  /** The audio the zip copies in. Missing when an opened station's file was not found. */
  source?: Blob
  /** This track's own level, multiplied with the station's. 1 is the file as recorded. */
  gain: number
  /**
   * The file's loudness and peak once measured; null for a file the browser could not read, and
   * absent while the measurement is still to come. A stream is never measured.
   */
  level?: Measurement | null
}

interface StationState {
  source: Source
  frequency: string
  /** Off, the label is the name alone; the frequency still places the station on the dial. */
  showFrequency: boolean
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
  /** In image mode, the image Build .zip writes the icon archive from; in atlas mode, the preview only. */
  iconImage: string | null
  /** Its pixel size, for the note on how the game will size it. */
  iconImageSize: [number, number] | null
  /** False when every pixel is transparent, which would show nothing in game. */
  iconImageHasPixels: boolean
  /** Set once the atlas or part is typed in, so the station ID stops filling them. */
  iconTargetEdited: boolean
  /** An opened station's icon archive that the page cannot read, so the preview has no icon. */
  iconArchiveUnreadable: boolean
  tracks: Track[]
  /**
   * On, every measured track's level is its suggestion and its slider is read-only. Off, the
   * sliders are the author's, starting from whatever they hold. Opening a station that carries a
   * track gain turns it off, because those levels were set on purpose.
   */
  autoLevel: boolean
  /** The mod folder to write, kept from an opened station so a rebuild replaces it. */
  folder: string | null
  /** Files from an opened station that go back into the zip unchanged. */
  extras: { path: string; source: Blob }[]
  /** What the last open or conversion could not bring across, kept while the station is in the form. */
  notes: string[]
  set: (patch: Partial<StationState>) => void
  addFiles: (files: File[]) => void
  /** A stream track. A station with one plays that stream only, so it replaces the track list. */
  addStream: (url: string) => void
  updateTrack: (id: number, patch: Partial<Track>) => void
  /** The same patch on every track the predicate picks, in one update. */
  updateTracks: (pick: (t: Track) => boolean, patch: (t: Track) => Partial<Track>) => void
  removeTrack: (id: number) => void
  openStation: (station: ImportedStation) => void
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
  showFrequency: true,
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
  iconImageSize: null,
  iconImageHasPixels: true,
  iconTargetEdited: false,
  iconArchiveUnreadable: false,
  tracks: [],
  autoLevel: true,
  folder: null,
  extras: [],
  notes: [],
  set: (patch) =>
    set((s) => {
      const next = { ...s, ...patch }
      if ('stationName' in patch && !s.cnameEdited) next.cname = cnameFrom(next.stationName)
      // Choosing an image means the page makes a new icon, so a path an opened or converted station
      // carried has nothing left to point at: the station ID's defaults take over until typed in.
      if (patch.iconMode === 'image' && s.iconMode !== 'image') next.iconTargetEdited = false
      if (next.iconMode === 'image' && !next.iconTargetEdited) {
        const target = defaultIconTarget(next.cname)
        next.iconPart = target.part
        next.iconAtlas = target.atlas
      }
      return next
    }),
  addFiles: (files) =>
    set((s) => {
      const taken = new Set(s.tracks.map((t) => t.file.toLowerCase()))
      const added = files.map((source) => {
        const file = uniquePath(`audio/${source.name}`, taken)
        taken.add(file.toLowerCase())
        return { id: nextId++, file, title: titleFromFile(source.name), ident: false, source, gain: 1 }
      })
      return { tracks: [...s.tracks, ...added] }
    }),
  addStream: (url) => set({ tracks: [{ id: nextId++, file: '', title: '', ident: false, url, gain: 1 }] }),
  updateTrack: (id, patch) => set((s) => ({ tracks: s.tracks.map((t) => (t.id === id ? { ...t, ...patch } : t)) })),
  updateTracks: (pick, patch) => set((s) => ({ tracks: s.tracks.map((t) => (pick(t) ? { ...t, ...patch(t) } : t)) })),
  removeTrack: (id) => set((s) => ({ tracks: s.tracks.filter((t) => t.id !== id) })),
  openStation: (st) =>
    set({
      source: 'new',
      frequency: st.frequency,
      showFrequency: st.showFrequency,
      stationName: st.stationName,
      cname: st.cname,
      cnameEdited: true,
      news: st.news,
      gain: st.gain,
      iconMode: st.iconMode,
      iconChoice: st.iconChoice,
      iconRecord: st.iconRecord,
      iconPart: st.iconPart,
      iconAtlas: st.iconAtlas,
      iconImage: st.iconImage,
      iconImageSize: st.iconImageSize,
      iconImageHasPixels: true,
      iconTargetEdited: true,
      iconArchiveUnreadable: st.iconArchiveUnreadable,
      tracks: st.tracks.map((t) => ({ id: nextId++, ...t })),
      autoLevel: !st.tracks.some((t) => Math.abs(t.gain - 1) >= 0.005),
      folder: st.folder || null,
      extras: st.extras,
      notes: st.notes,
    }),
}))
