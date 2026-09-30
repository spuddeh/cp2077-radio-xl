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
import { gainLabel, parseGain, suggestGain, type Suggestion } from '../loudness'
import { measureFile, preview } from '../measure'
import { Bool, CopyBlock, Fault, Notice, Slider } from './Controls'
import { Tooltip } from './Tooltip'

const AUDIO = /\.(wav|mp3|ogg|flac)$/i

/** The level the suggestion aims at, set at build time from tools/level-target/target.json. */
const TARGET = __LEVEL_TARGET__

/** A track's suggestion, or null while unmeasured, unmeasurable or a stream. */
export function suggestionFor(t: Track): Suggestion | null {
  return t.level ? suggestGain(t.level, TARGET) : null
}

/** True when a track's slider already sits on its suggestion. */
function atSuggestion(t: Track): boolean {
  const s = suggestionFor(t)
  return s !== null && Math.abs(t.gain - s.gain) < 0.005
}

/** Tracks whose measurement has been started, so a re-render never starts a second one. */
const measuring = new Set<number>()

export function Tracks() {
  const { tracks, addFiles, addStream, set, updateTrack, updateTracks, autoLevel } = useStation()
  const [confirming, setConfirming] = useState(false)
  const picker = useRef<HTMLInputElement>(null)
  const [over, setOver] = useState(false)
  const [skipped, setSkipped] = useState<string[]>([])
  const [stream, setStream] = useState('')
  const [playing, setPlaying] = useState<number | null>(null)
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

  // With auto level on, every file track is measured once and its level set as the measurement
  // lands; the queue takes them one at a time. Off, nothing is measured: a big station takes minutes.
  useEffect(() => {
    if (!autoLevel) return
    for (const t of tracks) {
      if (t.url || !t.source || t.level !== undefined || measuring.has(t.id)) continue
      measuring.add(t.id)
      measureFile(t.source).then((level) => {
        measuring.delete(t.id)
        const auto = useStation.getState().autoLevel
        updateTrack(t.id, level && auto ? { level, gain: suggestGain(level, TARGET).gain } : { level })
      })
    }
  }, [tracks, updateTrack, autoLevel])

  // Turning auto level on puts every measured track on its suggestion; off leaves them where they are.
  useEffect(() => {
    if (autoLevel) useSuggested()
  }, [autoLevel])

  // A removed track that was playing stops.
  useEffect(() => {
    if (playing !== null && !tracks.some((t) => t.id === playing)) preview.stop()
  }, [tracks, playing])

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

  // Without a save dialog the whole zip is assembled in memory before it downloads, and a large
  // station can fail there with nothing to show for it.
  const streamsToDisk = 'showSaveFilePicker' in window
  const audioBytes = tracks.reduce((sum, t) => sum + (t.source?.size ?? 0), 0)
  const inMemoryWarning = !streamsToDisk && audioBytes > 400 * 1048576
  const pending = autoLevel ? tracks.filter((t) => !t.url && t.source && t.level === undefined).length : 0
  const suggestible = tracks.filter((t) => suggestionFor(t) !== null && !atSuggestion(t)).length
  function useSuggested() {
    updateTracks(
      (t) => suggestionFor(t) !== null,
      (t) => ({ gain: suggestionFor(t)!.gain }),
    )
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
          <strong>Players have to allow this stream.</strong> Put these steps on your station&apos;s page:
          <ol className="notice-steps">
            <li>
              Open <code>red4ext\plugins\AudioXL\AudioXL.ini</code>. With Mod Organizer 2 it is in Overwrite.
            </li>
            <li>
              Set these two lines:
              <CopyBlock text={`allowHttpConnections = true\nallowedHost = ${streamHost}`} />
            </li>
            <li>
              Still silent? The stream moved to another host. AudioXL&apos;s log names it: add an{' '}
              <code>allowedHost</code> line for that one too.
            </li>
          </ol>
        </Notice>
      )}

      {inMemoryWarning && (
        <Notice>
          This station is {(audioBytes / 1048576 / 1024).toFixed(1)} GB of audio, and this browser has no save dialog, so
          the zip is built in memory before it downloads, which can fail for a station this size. Chrome and Edge
          write the zip straight to disk.
        </Notice>
      )}
      {tracks.length > 0 && (
        <>
          <div className="tracks-tools">
            <span className="tracks-hint">
              {pending > 0
                ? `Measuring ${pending} ${pending === 1 ? 'file' : 'files'}. Drag a track by its number to move it.`
                : 'Drag a track by its number to move it.'}
            </span>
            <div className="tracks-buttons">
              <Tooltip
                title="Auto level"
                text={`On, every file is measured and its level set so it plays at the level of the game's own stations (${TARGET.fileLufsTarget} LUFS in the file), as far as its peak allows. Off, the sliders are yours, from where they are.`}
              >
                <div className="auto-level">
                  <span className="auto-level-label">Auto level</span>
                  <Bool value={autoLevel} onChange={(v) => set({ autoLevel: v })} />
                </div>
              </Tooltip>
              {!autoLevel && tracks.some((t) => suggestionFor(t) !== null) && (
                <Tooltip
                  title="Suggested levels"
                  text={`Sets every measured track's level so it plays at the level of the game's own stations (${TARGET.fileLufsTarget} LUFS in the file), as far as its peak allows.`}
                >
                  <button type="button" className="ink-frame use-suggested" disabled={suggestible === 0} onClick={useSuggested}>
                    Use suggested levels
                  </button>
                </Tooltip>
              )}
              <button
                type="button"
                className={confirming ? 'ink-frame remove-all confirm' : 'ink-frame remove-all'}
                onClick={() => {
                  if (!confirming) return setConfirming(true)
                  preview.stop()
                  set({ tracks: [] })
                  setConfirming(false)
                }}
              >
                {confirming ? `Remove all ${tracks.length}? Press again` : 'Remove all'}
              </button>
            </div>
          </div>
          <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={onDragEnd}>
            <SortableContext items={tracks.map((t) => t.id)} strategy={verticalListSortingStrategy}>
              <ol className="tracks">
                {tracks.map((t, i) => (
                  <TrackRow key={t.id} track={t} index={i} playing={playing === t.id} auto={autoLevel} onPlaying={() => setPlaying(preview.playing)} />
                ))}
              </ol>
            </SortableContext>
          </DndContext>
        </>
      )}
    </>
  )
}

function TrackRow(props: { track: Track; index: number; playing: boolean; auto: boolean; onPlaying: () => void }) {
  const { updateTrack, removeTrack } = useStation()
  const t = props.track
  const { attributes, listeners, setNodeRef, setActivatorNodeRef, transform, transition, isDragging } = useSortable({ id: t.id })
  const suggestion = suggestionFor(t)
  // A page served over https may not play an http stream: the browser blocks the mixed content.
  const blockedHere = !!t.url && location.protocol === 'https:' && /^http:/i.test(t.url)
  const canPlay = t.url ? !blockedHere : !!t.source
  const failed = !!t.url && preview.failed === t.id && !props.playing
  // Auto level owns the slider of a track it has measured; a stream or an unreadable file is the author's.
  const automatic = props.auto && suggestion !== null
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
        {t.ident ? (
          <span className="track-ident">No title - plays between songs</span>
        ) : (
          <input
            type="text"
            value={t.title}
            spellCheck={false}
            placeholder={t.url ? 'Title shown while the stream plays (optional)' : ''}
            onChange={(e) => updateTrack(t.id, { title: e.target.value })}
          />
        )}
        <span className={!t.url && !t.source ? 'track-file missing' : 'track-file'}>
          {t.url ? t.url : t.source ? t.file : `${t.file} (no audio file)`}
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

      <div className="track-level">
        <Tooltip
          title={props.playing ? 'Stop' : 'Play'}
          text={
            t.url
              ? 'Hear the stream, to check it is the station you meant. Above 100% it plays at 100%. Starting one stops any other.'
              : 'Hear this track at the level set here. Starting one stops any other.'
          }
        >
          <button
            type="button"
            className="ink-frame track-play"
            aria-pressed={props.playing}
            aria-label={props.playing ? `Stop ${t.file}` : `Play ${t.file}`}
            disabled={!canPlay}
            onClick={() => {
              if (props.playing) preview.stop()
              else if (t.url) void preview.playStream(t.id, t.url, t.gain, props.onPlaying)
              else if (t.source) void preview.play(t.id, t.source, t.gain, props.onPlaying)
            }}
          />
        </Tooltip>
        <Slider
          value={t.gain}
          min={0}
          max={4}
          step={0.01}
          disabled={automatic}
          onChange={(v) => {
            updateTrack(t.id, { gain: v })
            preview.setGain(t.id, v)
          }}
          format={gainLabel}
          parse={parseGain}
        />
        <span className="track-reading">
          {t.url ? (
            <>
              {blockedHere ? (
                <>
                  This page cannot play an http:// stream, the browser blocks it here.{' '}
                  <a href={t.url} target="_blank" rel="noreferrer">
                    Open the stream
                  </a>{' '}
                  to hear it.{' '}
                </>
              ) : failed ? (
                'The stream did not play: check the address, or whether the station is on air. '
              ) : null}
              A stream cannot be measured ahead of time. Set its level by ear against a vanilla station.
            </>
          ) : !t.source ? (
            ''
          ) : t.level === undefined ? (
            props.auto ? 'Measuring' : ''
          ) : t.level === null ? (
            'This browser could not read the file, so no level is suggested.'
          ) : (
            <>
              {t.level.lufs.toFixed(1)} LUFS, peak {t.level.peakDb > 0 ? '+' : ''}
              {t.level.peakDb.toFixed(1)} dBFS.{' '}
              {suggestion && automatic ? (
                <span className="track-suggested">Levelled to {gainLabel(suggestion.gain)}{suggestion.peakLimited ? ', as far as the peak allows' : ''}.</span>
              ) : suggestion && atSuggestion(t) ? (
                <span className="track-suggested">At the suggested level{suggestion.peakLimited ? ', as far as the peak allows' : ''}.</span>
              ) : suggestion ? (
                <>
                  Suggested {gainLabel(suggestion.gain)}
                  {suggestion.peakLimited ? ', limited by the peak' : ''}{' '}
                  <button type="button" className="link track-use" onClick={() => updateTrack(t.id, { gain: suggestion.gain })}>
                    use it
                  </button>
                </>
              ) : null}
            </>
          )}
        </span>
      </div>
    </li>
  )
}
