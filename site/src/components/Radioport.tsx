import { VANILLA_STATIONS } from '../vanilla'
import glyph from '../assets/radioxl-glyph.png'
import { tintedIcon } from './tint'

const ROWS = 7

/**
 * The Radioport's station popup (vehicles_radio.inkwidget), laid out from its widget tree,
 * showing where the station lands on the dial.
 */
export function Radioport(props: {
  frequency: string
  name: string
  nowPlaying: string
  logo?: string
  animate: boolean
}) {
  const freq = Number.parseFloat(props.frequency)
  const own = {
    freq: Number.isFinite(freq) ? freq : Infinity,
    label: [props.frequency, props.name].filter(Boolean).join(' ') || 'Your station',
    own: true,
  }
  const dial = [
    ...VANILLA_STATIONS.map((v) => ({ freq: v.frequency, label: `${v.frequency.toFixed(1)} ${v.name}`, own: false })),
    own,
  ].sort((a, b) => a.freq - b.freq)
  const at = dial.indexOf(own)
  const first = Math.max(0, Math.min(at - 3, dial.length - ROWS))
  const shown = dial.slice(first, first + ROWS)

  return (
    <div className="radioport-wrap">
      <figure className={props.animate ? 'radioport rp-animate' : 'radioport'} aria-label="In-game preview">
        <span className="rp-fluff rp-fluff-top rp-flicker" aria-hidden>
          TRN_TCLAS_800095
        </span>
        <div className="rp-bar rp-top-holder">
          <span className="rp-bracket" aria-hidden />
          <div className="rp-top ink-frame">
            <span className="rp-title">Radioport</span>
          </div>
        </div>

        <div className="rp-now">
          <div className="rp-bar">
            <span className="rp-bracket rp-grow-down" aria-hidden />
            {/* Keyed on the station, so a change replays the switch animation. */}
            <div key={`${props.logo ?? ''}|${props.frequency}|${props.name}`} className="rp-image ink-frame">
              <span
                className="rp-icon"
                style={tintedIcon(props.logo ?? glyph)}
                role="img"
                aria-label={props.logo ? 'Station icon' : 'RadioXL glyph'}
              />
              <pre className="rp-kernel rp-flicker" aria-hidden>
                {'IMAGE NAME:   SILVERBIRCH-3.10.10\nIMAGE TYPE:   ROOT AV92 KERNEL IMAGE\n(LZO COMPRESSED)\nLOAD ADDRESS: 00008000'}
              </pre>
            </div>
          </div>
          <div className="rp-details">
            <span className="rp-fluff rp-now-label">Now playing</span>
            <span className="rp-track">{props.nowPlaying || 'No track'}</span>
            <div className="rp-volume">
              <span>Volume</span>
              <kbd className="ink-frame">A</kbd>
              <span className="rp-volume-value">100%</span>
              <kbd className="ink-frame">D</kbd>
            </div>
          </div>
        </div>

        <div className="rp-listwrap">
          <ol className="rp-list">
            {shown.map((s) => (
              <li key={s.label + s.own} className={s.own ? 'active ink-frame' : undefined}>
                {s.own ? (
                  <span className="rp-eq" aria-hidden>
                    <i />
                    <i />
                    <i />
                    <i />
                  </span>
                ) : (
                  <span className="rp-code" aria-hidden>
                    {'4648181\n4150185\n0001364\n3061213'}
                  </span>
                )}
                {s.label}
              </li>
            ))}
          </ol>
          <span className="rp-scroll" aria-hidden>
            <span style={{ top: `${(first / dial.length) * 100}%`, height: `${(ROWS / dial.length) * 100}%` }} />
          </span>
        </div>

        <div className="rp-foot">
          <span className="rp-fluff rp-fluff-legal rp-flicker" aria-hidden>
            Only CCSR certified and drive 5th class officers are allowed to manipulate, access or disable this
            device.
          </span>
          <span className="rp-hint">
            <kbd className="ink-frame">E</kbd>Select
          </span>
          <span className="rp-hint">
            <svg className="rp-mouse" viewBox="0 0 14 20" aria-hidden>
              <rect x="1" y="1" width="12" height="18" rx="6" fill="none" stroke="currentColor" strokeWidth="1.5" />
              <path d="M7 1v7M1 8h12" stroke="currentColor" strokeWidth="1.5" />
              <path d="M7 1.5a5.5 5.5 0 0 1 5.5 5.5v1H7z" fill="currentColor" />
            </svg>
            Close
          </span>
        </div>
      </figure>

      <p className="rp-caption">
        Dial position {at + 1} of {dial.length}
      </p>
    </div>
  )
}
