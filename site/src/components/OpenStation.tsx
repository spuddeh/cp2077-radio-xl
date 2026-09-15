import { useRef, useState } from 'react'
import { entriesFromDrop, entriesFromFiles, importStation, readZip, type ImportedStation } from '../importStation'
import { useStation } from '../store'
import { Fault } from './Controls'

/**
 * Opens a RadioXL station mod (its .zip, or its folder) into the form. Opening over a station that
 * already has work asks first, since the form holds one station.
 */
export function OpenStation(props: { hasWork: boolean; onOpened: (name: string) => void }) {
  const openStation = useStation((s) => s.openStation)
  const zipPicker = useRef<HTMLInputElement>(null)
  const folderPicker = useRef<HTMLInputElement>(null)
  const [over, setOver] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [notes, setNotes] = useState<string[]>([])
  const [pending, setPending] = useState<ImportedStation | null>(null)

  const apply = (station: ImportedStation) => {
    openStation(station)
    setNotes(station.notes)
    setPending(null)
    props.onOpened([station.frequency, station.stationName].filter(Boolean).join(' ') || station.cname)
  }

  const read = async (load: () => Promise<Parameters<typeof importStation>[0]>) => {
    setBusy(true)
    setError(null)
    setNotes([])
    try {
      const station = await importStation(await load())
      if (props.hasWork) setPending(station)
      else apply(station)
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="open-station">
      <div
        className={`drop ink-frame${over ? ' over' : ''}`}
        onDragOver={(e) => {
          e.preventDefault()
          setOver(true)
        }}
        onDragLeave={() => setOver(false)}
        onDrop={(e) => {
          e.preventDefault()
          setOver(false)
          const items = e.dataTransfer.items
          read(() => entriesFromDrop(items))
        }}
      >
        <span>{busy ? 'Reading the station...' : 'Edit a RadioXL station: drop its .zip or folder here, or choose a'}</span>
        {!busy && (
          <>
            <button type="button" className="link" onClick={() => zipPicker.current?.click()}>
              zip
            </button>
            <span>or</span>
            <button type="button" className="link" onClick={() => folderPicker.current?.click()}>
              folder
            </button>
          </>
        )}
        <input
          ref={zipPicker}
          type="file"
          accept=".zip,application/zip"
          hidden
          onChange={(e) => {
            const f = e.target.files?.[0]
            e.target.value = ''
            if (f) read(() => readZip(f))
          }}
        />
        <input
          ref={folderPicker}
          type="file"
          hidden
          {...({ webkitdirectory: '' } as object)}
          onChange={(e) => {
            const files = [...(e.target.files ?? [])]
            e.target.value = ''
            if (files.length) read(async () => entriesFromFiles(files))
          }}
        />
      </div>

      {error && <Fault>{error}</Fault>}
      {pending && (
        <div className="open-confirm">
          <span>
            Replace the station in the form with{' '}
            {[pending.frequency, pending.stationName].filter(Boolean).join(' ') || pending.cname}?
          </span>
          <button type="button" className="ink-frame remove-all confirm" onClick={() => apply(pending)}>
            Replace
          </button>
          <button type="button" className="ink-frame remove-all" onClick={() => setPending(null)}>
            Cancel
          </button>
        </div>
      )}
      {notes.length > 0 && (
        <ul className="open-notes">
          {notes.map((n) => (
            <li key={n}>{n}</li>
          ))}
        </ul>
      )}
    </div>
  )
}
