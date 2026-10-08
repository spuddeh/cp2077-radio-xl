import { useState } from 'react'
import { useStation } from '../store'

/**
 * What an opened station's folder and its track list disagree on, each offered as a checklist:
 * audio files no track names, to add, and tracks with no audio file, to remove. A file left
 * unticked stays as it was.
 */
export function ImportOffers() {
  const unlisted = useStation((s) => s.unlisted)
  const tracks = useStation((s) => s.tracks)
  const addUnlisted = useStation((s) => s.addUnlisted)
  const removeTracks = useStation((s) => s.removeTracks)
  const missing = tracks.filter((t) => !t.url && !t.source)

  return (
    <>
      {unlisted.length > 0 && (
        <Offer
          heading={`${unlisted.length} audio ${unlisted.length === 1 ? 'file is' : 'files are'} not in the station`}
          note="Ticked files become tracks and are measured like any song you add. Unticked ones go back into the zip as they are."
          items={unlisted.map((u) => ({ key: u.file, label: u.file }))}
          action="Add"
          onApply={addUnlisted}
        />
      )}
      {missing.length > 0 && (
        <Offer
          heading={`${missing.length} ${missing.length === 1 ? 'track has' : 'tracks have'} no audio file`}
          note="Ticked tracks are removed from the station. Unticked ones stay, and the station refuses to build until each has its file."
          items={missing.map((t) => ({ key: String(t.id), label: t.file }))}
          action="Remove"
          onApply={(keys) => removeTracks(keys.map(Number))}
        />
      )}
    </>
  )
}

function Offer(props: {
  heading: string
  note: string
  items: { key: string; label: string }[]
  action: string
  onApply: (keys: string[]) => void
}) {
  const [off, setOff] = useState<Set<string>>(new Set())
  const picked = props.items.filter((i) => !off.has(i.key)).map((i) => i.key)
  const toggle = (key: string) =>
    setOff((prev) => {
      const next = new Set(prev)
      if (next.has(key)) next.delete(key)
      else next.add(key)
      return next
    })

  return (
    <div className="import-offer">
      <div className="import-offer-heading">{props.heading}</div>
      <div className="import-offer-note">{props.note}</div>
      <ul className="import-offer-list">
        {props.items.map((i) => (
          <li key={i.key}>
            <label>
              <input type="checkbox" checked={!off.has(i.key)} onChange={() => toggle(i.key)} />
              <span>{i.label}</span>
            </label>
          </li>
        ))}
      </ul>
      <button type="button" className="ink-frame import-offer-apply" disabled={picked.length === 0} onClick={() => props.onApply(picked)}>
        {props.action} {picked.length}
      </button>
    </div>
  )
}
