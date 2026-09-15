import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useStation, type IconMode, type Source } from './store'
import { buildManifest, checkManifest, displayName } from './manifest'
import { Bool, Hint, Row, Slider, Stepper, TextInput } from './components/Controls'
import { Radioport } from './components/Radioport'
import { WORLD_LAYOUTS, WorldRadio, type WorldLayout } from './components/WorldRadio'
import { Tracks } from './components/Tracks'
import { BuildProgress, ToastView, type BuildPhase, type Toast } from './components/Feedback'
import { About } from './components/About'
import { buildZip, modFolder, pickSaveTarget } from './build'
import { stationLogo, VANILLA_STATIONS } from './vanilla'

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

const ICON_GUIDE = 'https://github.com/spuddeh/cp2077-radio-xl/blob/main/red4ext/plugins/RadioXL/stations/README.md#the-icon'

/** A note for an icon the preview cannot draw, with the guide to making one. */
function ownIconNote(first: string) {
  return (
    <>
      {first} The preview cannot load an icon from another mod, so it shows the RadioXL glyph.{' '}
      <a href={ICON_GUIDE} target="_blank" rel="noopener noreferrer">Making a station icon</a>
    </>
  )
}

const ANIMATE_KEY = 'radioxl-builder-animate'
const ECHOES_KEY = 'radioxl-builder-echoes'

const prefersReducedMotion = () => window.matchMedia('(prefers-reduced-motion: reduce)').matches

/** A preview switch as this browser last left it, or its default. */
function loadSwitch(key: string, fallback: boolean): boolean {
  try {
    const saved = localStorage.getItem(key)
    if (saved) return saved === 'on'
  } catch {
    // storage unavailable
  }
  return fallback
}

function saveSwitch(key: string, value: boolean): boolean {
  try {
    localStorage.setItem(key, value ? 'on' : 'off')
  } catch {
    // storage unavailable: the choice lasts for this visit only
  }
  return value
}

export function App() {
  const s = useStation()
  const faults = useMemo(() => checkManifest(s), [s])
  const faultFor = (field: string) => faults.find((f) => f.field === field)?.message
  const manifest = useMemo(() => JSON.stringify(buildManifest(s), null, 2), [s])
  const firstSong = s.tracks.find((t) => !t.ident)
  const [preview, setPreview] = useState<'radioport' | WorldLayout>('radioport')
  const [animate, setAnimate] = useState(() => loadSwitch(ANIMATE_KEY, !prefersReducedMotion()))
  const [echoes, setEchoes] = useState(() => loadSwitch(ECHOES_KEY, true))
  const toggleAnimate = () => setAnimate(saveSwitch(ANIMATE_KEY, !animate))
  const toggleEchoes = () => setEchoes(saveSwitch(ECHOES_KEY, !echoes))
  const logo = s.iconMode === 'record' ? stationLogo(s.iconChoice) : s.iconMode === 'atlas' ? (s.iconImage ?? undefined) : undefined
  const hasWork = s.tracks.length > 0 || s.stationName !== '' || s.frequency !== ''
  const [about, setAbout] = useState(false)

  const [toast, setToast] = useState<Toast | null>(null)
  const toastId = useRef(1)
  const notify = useCallback((title: string, message: string) => setToast({ id: toastId.current++, title, message }), [])
  const closeToast = useCallback(() => setToast(null), [])

  const [build, setBuild] = useState<{ phase: BuildPhase; written: number; total: number; file: string } | null>(null)
  const closeBuild = useCallback(() => {
    setBuild((b) => {
      if (b?.phase === 'done') notify('Station built', b.file)
      if (b?.phase === 'failed') notify('Build failed', b.file)
      return null
    })
  }, [notify])

  const copyManifest = () =>
    navigator.clipboard.writeText(manifest).then(
      () => notify('Copied', 'station.json is on the clipboard'),
      () => notify('Copy failed', 'The browser refused clipboard access'),
    )

  const startBuild = async () => {
    if (faults.length > 0 || build) return
    const folder = modFolder(s.stationName, s.cname)
    const file = `${folder}.zip`
    let target = null
    try {
      // The save dialog has to open straight from the click, before any other work.
      target = await pickSaveTarget(file)
    } catch (e) {
      if ((e as DOMException).name === 'AbortError') return
    }
    setBuild({ phase: 'running', written: 0, total: 0, file })
    let frame = 0
    try {
      await buildZip({
        folder,
        manifest,
        tracks: s.tracks,
        target,
        onProgress: ({ written, total }) => {
          // One state update per frame, however many chunks arrive in it.
          cancelAnimationFrame(frame)
          frame = requestAnimationFrame(() => setBuild((b) => b && { ...b, written, total }))
        },
      })
      cancelAnimationFrame(frame)
      setBuild((b) => b && { ...b, phase: 'done', written: b.total })
    } catch {
      cancelAnimationFrame(frame)
      setBuild((b) => b && { ...b, phase: 'failed' })
    }
  }

  // The footer hints are the page's keys, as they are the game's; typing in a field is left alone.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const el = e.target as HTMLElement
      if (e.repeat || e.ctrlKey || e.metaKey || e.altKey || el.closest('input, textarea, select, [contenteditable]')) return
      if (e.key === 'z' || e.key === 'Z') startBuild()
      if (e.key === 'c' || e.key === 'C') copyManifest()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  })

  // Closing or reloading the tab loses everything entered, so the browser asks first.
  useEffect(() => {
    if (!hasWork) return
    const warn = (e: BeforeUnloadEvent) => e.preventDefault()
    window.addEventListener('beforeunload', warn)
    return () => window.removeEventListener('beforeunload', warn)
  }, [hasWork])

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
          <button
            key={o.value}
            type="button"
            aria-current={!about && s.source === o.value}
            onClick={() => {
              setAbout(false)
              s.set({ source: o.value })
            }}
          >
            {o.label}
          </button>
        ))}
        <button type="button" className="tab-about" aria-current={about} onClick={() => setAbout(true)}>
          About
        </button>
      </nav>

      {about ? (
        <About />
      ) : (


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
                    <Row label="Record" note={ownIconNote('Any UIIcon record. One that does not exist shows the RadioXL glyph in game too.')}>
                      <TextInput value={s.iconRecord} onChange={(v) => s.set({ iconRecord: v })} placeholder="UIIcon.MyStation" />
                    </Row>
                  )}
                </>
              )}
              {s.iconMode === 'atlas' && (
                <>
                  <Row
                    label="Atlas"
                    note={
                      <>
                        The .inkatlas path inside your station&apos;s archive. The preview cannot read an archive, so
                        choose the same image below to see it.{' '}
                        <a href={ICON_GUIDE} target="_blank" rel="noopener noreferrer">
                          Making a station icon
                        </a>
                      </>
                    }
                  >
                    <TextInput value={s.iconAtlas} onChange={(v) => s.set({ iconAtlas: v })} placeholder="mymod\gui\icons.inkatlas" />
                  </Row>
                  <Row label="Part">
                    <TextInput value={s.iconPart} onChange={(v) => s.set({ iconPart: v })} placeholder="my_station" />
                  </Row>
                  <Row
                    label="Preview image"
                    note="Shows your icon in the previews, tinted the way the game tints it. The zip does not include it: the icon still goes in your own archive."
                  >
                    <label className="file-pick">
                      <span>{s.iconImage ? 'Change image' : 'Choose a PNG'}</span>
                      <input
                        type="file"
                        accept="image/png,image/webp,image/svg+xml"
                        hidden
                        onChange={(e) => {
                          const f = e.target.files?.[0]
                          if (!f) return
                          if (s.iconImage) URL.revokeObjectURL(s.iconImage)
                          s.set({ iconImage: URL.createObjectURL(f) })
                          e.target.value = ''
                        }}
                      />
                    </label>
                    {s.iconImage && (
                      <button
                        type="button"
                        className="link file-clear"
                        onClick={() => {
                          URL.revokeObjectURL(s.iconImage!)
                          s.set({ iconImage: null })
                        }}
                      >
                        Remove
                      </button>
                    )}
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
          <nav className="preview-tabs" aria-label="Preview">
            <button type="button" aria-current={preview === 'radioport'} onClick={() => setPreview('radioport')}>
              Radioport
            </button>
            {WORLD_LAYOUTS.map((l) => (
              <button key={l.value} type="button" aria-current={preview === l.value} onClick={() => setPreview(l.value)}>
                <span className="sub">World radio </span>
                {l.label}
              </button>
            ))}
          </nav>
          <div className="preview-switches">
            {preview !== 'radioport' && (
              <button type="button" className="ink-frame animate-toggle" aria-pressed={echoes} onClick={toggleEchoes}>
                Echoes {echoes ? 'on' : 'off'}
              </button>
            )}
            <button type="button" className="ink-frame animate-toggle" aria-pressed={animate} onClick={toggleAnimate}>
              Animation {animate ? 'on' : 'off'}
            </button>
          </div>
          {preview === 'radioport' ? (
            <Radioport
              frequency={s.frequency.trim()}
              name={s.stationName.trim()}
              nowPlaying={firstSong?.title ?? ''}
              logo={logo}
              animate={animate}
            />
          ) : (
            <WorldRadio layout={preview} name={displayName(s) || 'Your station'} logo={logo} animate={animate} echoes={echoes} />
          )}
          <details className="json">
            <summary>station.json</summary>
            <pre>{manifest}</pre>
          </details>
        </aside>
      </main>
      )}

      <footer className="footer">
        <div className="hints">
          <Hint keyLabel="Z" label="Build .zip" disabled={faults.length > 0 || build !== null} onClick={startBuild} />
          <Hint keyLabel="C" label="Copy station.json" onClick={copyManifest} />
        </div>
        <span className="footer-state">
          {faults.length === 0 ? `${displayName(s)} is ready` : `${faults.length} to fix before building`}
        </span>
      </footer>

      {(build || toast) && <div className={animate ? 'feedback-fade animate' : 'feedback-fade'} aria-hidden />}
      <BuildProgress
        phase={build?.phase ?? null}
        title={`Building ${build?.file ?? ''}`}
        written={build?.written ?? 0}
        total={build?.total ?? 0}
        animate={animate}
        onFinished={closeBuild}
      />
      {toast && <ToastView key={toast.id} toast={toast} animate={animate} onDone={closeToast} />}

      <footer className="colophon">
        <nav aria-label="Links">
          <a href="https://www.nexusmods.com/cyberpunk2077/mods/33488" target="_blank" rel="noopener noreferrer">RadioXL on Nexus Mods</a>
          <a href="https://github.com/spuddeh/cp2077-radio-xl" target="_blank" rel="noopener noreferrer">Source on GitHub</a>
          <a href="https://www.cdprojektred.com/en/fan-content" target="_blank" rel="noopener noreferrer">CD PROJEKT RED fan content guidelines</a>
        </nav>
        <p>
          An unofficial fan work, not approved or endorsed by CD PROJEKT RED. Cyberpunk 2077 and its
          station names belong to CD PROJEKT RED.
        </p>
      </footer>
    </div>
  )
}
