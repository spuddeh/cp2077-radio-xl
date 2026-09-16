import { useEffect, useRef, useState } from 'react'
import {
  DndContext,
  KeyboardSensor,
  PointerSensor,
  closestCenter,
  useSensor,
  useSensors,
  type DragEndEvent,
} from '@dnd-kit/core'
import { SortableContext, arrayMove, sortableKeyboardCoordinates, useSortable, verticalListSortingStrategy } from '@dnd-kit/sortable'
import { CSS } from '@dnd-kit/utilities'
import { useStation, type Track } from '../store'
import { Fault, Notice } from './Controls'
import { Tooltip } from './Tooltip'

const AUDIO = /\.(wav|mp3|ogg|flac)$/i

export function Tracks() {
  const { tracks, addFiles, addStream, set } = useStation()
  const [confirming, setConfirming] = useState(false)
  const picker = useRef<HTMLInputElement>(null)
  const [over, setOver] = useState(false)
  const [skipped, setSkipped] = useState<string[]>([])
  const [stream, setStream] = useState('')
  const streamOk = /^https?:\/\/\S+$/i.test(stream.trim())
  const addStreamTrack = () => {
    if (!streamOk) return
    addStream(stream.trim())
    setStream('')
  }
  // The host a player has to allow, taken from the stream the station carries.
  const streamHost = (() => {
    const url = tracks.find((t) => t.url)?.url
    if (!url) return ''
    try {
      return new URL(url).hostname
    } catch {
      return ''
    }
  })()
  const sensors = useSensors(
    // A small travel before a drag starts, so a click on the handle is still a click.
    useSensor(PointerSensor, { activationConstraint: { distance: 4 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  )

  // Remove all asks for a second press, which it waits a few seconds for.
  useEffect(() => {
    if (!confirming) return
    const t = setTimeout(() => setConfirming(false), 4000)
    return () => clearTimeout(t)
  }, [confirming])

  const take = (files: File[]) => {
    setSkipped(files.filter((f) => !AUDIO.test(f.name)).map((f) => f.name))
    addFiles(files.filter((f) => AUDIO.test(f.name)))
  }

  const onDragEnd = ({ active, over: target }: DragEndEvent) => {
    if (!target || active.id === target.id) return
    const from = tracks.findIndex((t) => t.id === active.id)
    const to = tracks.findIndex((t) => t.id === target.id)
    set({ tracks: arrayMove(tracks, from, to) })
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
          take([...e.dataTransfer.files])
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
          onChange={(e) => {
            take([...(e.target.files ?? [])])
            e.target.value = ''
          }}
        />
      </div>
      {skipped.length > 0 && <Fault>Not an audio file AudioXL reads: {skipped.join(', ')}</Fault>}

      <div className="stream-add">
        <label htmlFor="stream-url">Or a stream, which plays in place of any files:</label>
        <div className="stream-row">
          <div className="cell ink-frame">
            <input
              id="stream-url"
              type="text"
              value={stream}
              spellCheck={false}
              placeholder="https://example.com/stream.mp3"
              onChange={(e) => setStream(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') addStreamTrack()
              }}
            />
          </div>
          <button type="button" className="ink-frame stream-button" disabled={!streamOk} onClick={addStreamTrack}>
            Add stream
          </button>
        </div>
        {stream.trim() !== '' && !streamOk && <Fault>A stream URL starts with http:// or https://</Fault>}
      </div>
      {streamHost && (
        <Notice>
          A stream plays only once the player allows it: AudioXL fetches nothing unless{' '}
          <code>red4ext\plugins\AudioXL\AudioXL.ini</code> carries{' '}
          <code>allowHttpConnections = true</code> and <code>allowedHost = {streamHost}</code>. No mod can set that,
          so say it on the station&apos;s own page. AudioXL writes that file on first start with everything off; under
          Mod Organizer 2 it is in Overwrite.
        </Notice>
      )}

      {tracks.length > 0 && (
        <>
          <div className="tracks-tools">
            <span className="tracks-hint">Drag a track by its number to move it.</span>
            <button
              type="button"
              className={confirming ? 'ink-frame remove-all confirm' : 'ink-frame remove-all'}
              onClick={() => {
                if (!confirming) return setConfirming(true)
                set({ tracks: [] })
                setConfirming(false)
              }}
            >
              {confirming ? `Remove all ${tracks.length}? Press again` : 'Remove all'}
            </button>
          </div>
          <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={onDragEnd}>
            <SortableContext items={tracks.map((t) => t.id)} strategy={verticalListSortingStrategy}>
              <ol className="tracks">
                {tracks.map((t, i) => (
                  <TrackRow key={t.id} track={t} index={i} />
                ))}
              </ol>
            </SortableContext>
          </DndContext>
        </>
      )}
    </>
  )
}

function TrackRow(props: { track: Track; index: number }) {
  const { updateTrack, removeTrack } = useStation()
  const t = props.track
  const { attributes, listeners, setNodeRef, setActivatorNodeRef, transform, transition, isDragging } = useSortable({ id: t.id })
  return (
    <li
      ref={setNodeRef}
      className={isDragging ? 'track dragging' : 'track'}
      style={{ transform: CSS.Translate.toString(transform), transition }}
    >
      <button
        type="button"
        ref={setActivatorNodeRef}
        className="track-no"
        aria-label={`Move track ${props.index + 1}`}
        {...attributes}
        {...listeners}
      >
        {String(props.index + 1).padStart(2, '0')}
      </button>
      <div className="cell ink-frame track-title">
        {t.url ? (
          // A stream is its URL: the row is the address, which is the whole track.
          <span className="track-stream">{t.url}</span>
        ) : t.ident ? (
          <span className="track-ident">No title - plays between songs</span>
        ) : (
          <input type="text" value={t.title} spellCheck={false} onChange={(e) => updateTrack(t.id, { title: e.target.value })} />
        )}
        <span className={!t.url && !t.source ? 'track-file missing' : 'track-file'}>
          {t.url ? 'Stream' : t.source ? t.file : `${t.file} (no audio file)`}
        </span>
      </div>
      {t.url ? null : (
      <Tooltip
        title="Ident"
        text="A station ident, jingle or ad. One plays between songs after every third song, and it shows no title."
      >
        <button
          type="button"
          className="ink-frame track-ident-toggle"
          aria-pressed={t.ident}
          onClick={() => updateTrack(t.id, { ident: !t.ident })}
        >
          Ident
        </button>
      </Tooltip>
      )}
      <button type="button" className="track-remove" aria-label={`Remove ${t.file}`} onClick={() => removeTrack(t.id)} />
    </li>
  )
}
