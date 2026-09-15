import { useRef, useState } from 'react'
import { useStation } from '../store'
import { Fault } from './Controls'

const AUDIO = /\.(wav|mp3|ogg|flac)$/i

export function Tracks() {
  const { tracks, addFiles, updateTrack, removeTrack } = useStation()
  const picker = useRef<HTMLInputElement>(null)
  const [over, setOver] = useState(false)
  const [skipped, setSkipped] = useState<string[]>([])

  const take = (names: string[]) => {
    setSkipped(names.filter((n) => !AUDIO.test(n)))
    addFiles(names.filter((n) => AUDIO.test(n)))
  }

  return (
    <>
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
          take([...e.dataTransfer.files].map((f) => f.name))
        }}
      >
        <span>Drop audio files here, or</span>
        <button type="button" className="link" onClick={() => picker.current?.click()}>
          choose files
        </button>
        <span className="drop-formats">WAV / MP3 / OGG / FLAC</span>
        <input
          ref={picker}
          type="file"
          multiple
          accept=".wav,.mp3,.ogg,.flac"
          hidden
          onChange={(e) => take([...(e.target.files ?? [])].map((f) => f.name))}
        />
      </div>
      {skipped.length > 0 && <Fault>Not an audio file AudioXL reads: {skipped.join(', ')}</Fault>}

      {tracks.length > 0 && (
        <ol className="tracks">
          <li className="tracks-head" aria-hidden>
            <span>#</span>
            <span>Title</span>
            <span />
            <span />
          </li>
          {tracks.map((t, i) => (
            <li key={t.id} className="track">
              <span className="track-no">{String(i + 1).padStart(2, '0')}</span>
              <div className="cell ink-frame track-title">
                {t.ident ? (
                  <span className="track-ident">No title - plays between songs</span>
                ) : (
                  <input type="text" value={t.title} spellCheck={false} onChange={(e) => updateTrack(t.id, { title: e.target.value })} />
                )}
                <span className="track-file">{t.file}</span>
              </div>
              <button
                type="button"
                className="ink-frame track-ident-toggle"
                aria-pressed={t.ident}
                onClick={() => updateTrack(t.id, { ident: !t.ident })}
              >
                Ident
              </button>
              <button type="button" className="track-remove" aria-label={`Remove ${t.file}`} onClick={() => removeTrack(t.id)} />
            </li>
          ))}
        </ol>
      )}
    </>
  )
}
