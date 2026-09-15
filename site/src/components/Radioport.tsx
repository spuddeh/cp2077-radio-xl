import { VANILLA_STATIONS } from '../vanilla'

/**
 * The Radioport's station popup (vehicles_radio.inkwidget), laid out from its widget tree at
 * half scale, showing where the station lands on the dial.
 */
export function Radioport(props: { frequency: string; name: string; nowPlaying: string }) {
  const freq = Number.parseFloat(props.frequency)
  const own = { freq: Number.isFinite(freq) ? freq : Infinity, label: [props.frequency, props.name].filter(Boolean).join(' ') || 'Your station', own: true }
  const dial = [...VANILLA_STATIONS.map(([f, n]) => ({ freq: f, label: `${f.toFixed(1)} ${n}`, own: false })), own]
    .sort((a, b) => a.freq - b.freq)
  const at = dial.indexOf(own)
  const shown = dial.slice(Math.max(0, Math.min(at - 3, dial.length - 7)), Math.max(0, Math.min(at - 3, dial.length - 7)) + 7)

  return (
    <figure className="radioport" aria-label="In-game preview">
      <div className="rp-top ink-frame">
        <span className="rp-bracket" aria-hidden />
        <span className="rp-title">Radioport</span>
        <span className="rp-fluff">TRN_TCLAS_800095</span>
      </div>

      <div className="rp-now">
        <div className="rp-image">
          <span className="rp-bracket tall" aria-hidden />
          <pre className="rp-kernel" aria-hidden>{'IMAGE NAME:   SILVERBIRCH-3.10.10\nIMAGE TYPE:   ROOT AV92 KERNEL IMAGE'}</pre>
          <RadioGlyph />
        </div>
        <div className="rp-details">
          <span className="rp-fluff">Now playing</span>
          <span className="rp-track">{props.nowPlaying || '\u00a0'}</span>
        </div>
      </div>

      <ol className="rp-list">
        {shown.map((s) => (
          <li key={s.label + s.own} className={s.own ? 'active ink-frame' : undefined}>
            {s.own && (
              <span className="rp-eq" aria-hidden>
                <i /><i /><i /><i />
              </span>
            )}
            {s.label}
          </li>
        ))}
      </ol>

      <figcaption className="rp-caption">
        Dial position {at + 1} of {dial.length}
      </figcaption>
    </figure>
  )
}

/** Stand-in for the RadioXL glyph a station with no icon gets. */
function RadioGlyph() {
  return (
    <svg className="rp-icon" viewBox="0 0 64 64" aria-hidden>
      <path d="M14 22 h36 v28 h-36 z" fill="none" stroke="currentColor" strokeWidth="2" />
      <path d="M20 22 L44 10" stroke="currentColor" strokeWidth="2" />
      <circle cx="40" cy="36" r="7" fill="none" stroke="currentColor" strokeWidth="2" />
      <path d="M19 30 h10 M19 36 h10 M19 42 h10" stroke="currentColor" strokeWidth="2" />
    </svg>
  )
}
