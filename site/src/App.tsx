import { useMemo } from 'react'
import { useStation, type IconMode, type Source } from './store'
import { buildManifest, checkManifest, displayName } from './manifest'
import { Bool, Hint, Row, Slider, Stepper, TextInput } from './components/Controls'
import { Radioport } from './components/Radioport'
import { Tracks } from './components/Tracks'
import { VANILLA_STATIONS } from './vanilla'

const SOURCES: { value: Source; label: string }[] = [
  { value: 'new', label: 'New station' },
  { value: 'radioext', label: 'From RadioExt' },
  { value: 'radioxl010', label: 'From RadioXL 0.1.0' },
]

const ICON_RECORDS = [
  ...VANILLA_STATIONS.map((v) => ({ value: v.icon, label: `${v.frequency.toFixed(1)} ${v.name}` })),
  { value: 'other', label: 'Other' },
]

const ICON_MODES: { value: IconMode; label: string }[] = [
  { value: 'glyph', label: 'RadioXL glyph' },
  { value: 'record', label: 'Existing icon' },
  { value: 'atlas', label: 'Own atlas' },
]

/** The manifest's gain as a percentage and the level change it makes. */
function volumeLabel(gain: number): string {
  const pct = `${Math.round(gain * 100)}%`
  if (gain <= 0) return `${pct} (silent)`
  if (gain >= 1) return pct
  return `${pct} (${(20 * Math.log10(gain)).toFixed(1)} dB)`
}

export function App() {
  const s = useStation()
  const faults = useMemo(() => checkManifest(s), [s])
  const faultFor = (field: string) => faults.find((f) => f.field === field)?.message
  const manifest = useMemo(() => JSON.stringify(buildManifest(s), null, 2), [s])
  const firstSong = s.tracks.find((t) => !t.ident)

  return (
    <div className="shell">
      <header className="masthead">
        <h1>
          Station builder <span>RadioXL</span>
        </h1>
        <p>Runs in this browser. Files are read here and never uploaded.</p>
      </header>

      <nav className="tabs" aria-label="Start from">
        {SOURCES.map((o) => (
          <button key={o.value} type="button" aria-current={s.source === o.value} onClick={() => s.set({ source: o.value })}>
            {o.label}
          </button>
        ))}
      </nav>

      <main className="workspace">
        <section className="form">
          {s.source !== 'new' ? (
            <p className="pending">Converting a {s.source === 'radioext' ? 'RadioExt' : 'RadioXL 0.1.0'} station is not built yet.</p>
          ) : (
            <>
              <h2 className="section">Station</h2>
              <Row label="Frequency" note="Decides the station's place on the dial." fault={s.frequency ? faultFor('frequency') : undefined}>
                <TextInput value={s.frequency} onChange={(v) => s.set({ frequency: v })} placeholder="90.5" inputMode="decimal" />
              </Row>
              <Row label="Name">
                <TextInput value={s.stationName} onChange={(v) => s.set({ stationName: v })} placeholder="Hangouts FM" spellCheck />
              </Row>
              <Row
                label="Station ID"
                note="Unique across every installed station mod."
                fault={s.stationName || s.cnameEdited ? faultFor('cname') : undefined}
              >
                <TextInput value={s.cname} onChange={(v) => s.set({ cname: v, cnameEdited: true })} placeholder="radio_station_hangouts_fm" />
              </Row>
              <Row label="News" note="Stanley's bulletins and greetings, and N54 News.">
                <Bool value={s.news} onChange={(v) => s.set({ news: v })} />
              </Row>
              <Row label="Volume" note="100% plays the files as recorded. Turn it down if the station sounds louder than the game's own stations.">
                <Slider value={s.gain} min={0} max={1} step={0.05} onChange={(v) => s.set({ gain: v })} format={volumeLabel} />
              </Row>
              <Row label="Icon" fault={faultFor('icon')}>
                <Stepper options={ICON_MODES} value={s.iconMode} onChange={(v) => s.set({ iconMode: v })} />
              </Row>
              {s.iconMode === 'record' && (
                <>
                  <Row label="Station icon" note={s.iconChoice === 'other' ? undefined : s.iconChoice}>
                    <Stepper options={ICON_RECORDS} value={s.iconChoice} onChange={(v) => s.set({ iconChoice: v })} />
                  </Row>
                  {s.iconChoice === 'other' && (
                    <Row label="Record" note="Any UIIcon record. One that does not exist falls back to the RadioXL glyph.">
                      <TextInput value={s.iconRecord} onChange={(v) => s.set({ iconRecord: v })} placeholder="UIIcon.MyStation" />
                    </Row>
                  )}
                </>
              )}
              {s.iconMode === 'atlas' && (
                <>
                  <Row label="Atlas">
                    <TextInput value={s.iconAtlas} onChange={(v) => s.set({ iconAtlas: v })} placeholder="mymod\gui\icons.inkatlas" />
                  </Row>
                  <Row label="Part">
                    <TextInput value={s.iconPart} onChange={(v) => s.set({ iconPart: v })} placeholder="my_station" />
                  </Row>
                </>
              )}

              <h2 className="section">
                Tracks <span className="count">{s.tracks.length}</span>
              </h2>
              <Tracks />
            </>
          )}
        </section>

        <aside className="side">
          <Radioport frequency={s.frequency.trim()} name={s.stationName.trim()} nowPlaying={firstSong?.title ?? ''} />
          <details className="json">
            <summary>station.json</summary>
            <pre>{manifest}</pre>
          </details>
        </aside>
      </main>

      <footer className="footer">
        <div className="hints">
          <Hint keyLabel="Z" label="Build .zip" disabled={faults.length > 0} />
          <Hint keyLabel="C" label="Copy station.json" onClick={() => navigator.clipboard.writeText(manifest)} />
        </div>
        <span className="footer-state">
          {faults.length === 0 ? `${displayName(s)} is ready` : `${faults.length} to fix before building`}
        </span>
      </footer>

      <footer className="colophon">
        <nav aria-label="Links">
          <a href="https://www.nexusmods.com/cyberpunk2077/mods/33488">RadioXL on Nexus Mods</a>
          <a href="https://github.com/spuddeh/cp2077-radio-xl">Source on GitHub</a>
          <a href="https://www.cdprojektred.com/en/fan-content">CD PROJEKT RED fan content guidelines</a>
        </nav>
        <p>
          An unofficial fan work, not approved or endorsed by CD PROJEKT RED. Cyberpunk 2077 and its
          station names belong to CD PROJEKT RED.
        </p>
      </footer>
    </div>
  )
}
