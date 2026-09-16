import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { defaultIconTarget, useStation, type IconMode, type Source } from './store'
import { buildManifest, checkManifest, displayName, generatesIcon, ICON_IMAGE_RECOMMENDED, iconTarget } from './manifest'
import { Bool, Hint, Row, Slider, Stepper, TextInput } from './components/Controls'
import { Radioport } from './components/Radioport'
import { LOGO_MAX, WORLD_LAYOUTS, WorldRadio, type WorldLayout } from './components/WorldRadio'
import { Tracks } from './components/Tracks'
import { BuildProgress, ToastView, type BuildPhase, type Toast } from './components/Feedback'
import { About } from './components/About'
import { OpenStation } from './components/OpenStation'
import { buildZip, iconArchiveFile, iconTextureSize, modFolder, pickSaveTarget } from './build'
import { stationLogo, VANILLA_STATIONS } from './vanilla'

const SOURCES: { value: Source; label: string }[] = [
  { value: 'new', label: 'New station' },
  { value: 'radioext', label: 'From RadioExt' },
]

const ICON_RECORDS = [
  ...VANILLA_STATIONS.map((v) => ({ value: v.icon, label: `${v.frequency.toFixed(1)} ${v.name}` })),
  { value: 'other', label: 'Other' },
]

const ICON_MODES: { value: IconMode; label: string }[] = [
  { value: 'glyph', label: 'RadioXL glyph' },
  { value: 'record', label: 'Existing icon' },
  { value: 'image', label: 'From an image' },
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

/**
 * Whether any pixel of an image is not transparent, read from a copy scaled to at most 256 px. A
 * browser that refuses the pixels (a cross-origin image) counts as having them.
 */
function hasOpaquePixels(img: HTMLImageElement): boolean {
  const scale = Math.min(1, 256 / Math.max(img.naturalWidth, img.naturalHeight, 1))
  const w = Math.max(1, Math.round(img.naturalWidth * scale))
  const h = Math.max(1, Math.round(img.naturalHeight * scale))
  const canvas = document.createElement('canvas')
  canvas.width = w
  canvas.height = h
  const ctx = canvas.getContext('2d', { willReadFrequently: true })
  if (!ctx) return true
  ctx.drawImage(img, 0, 0, w, h)
  try {
    const { data } = ctx.getImageData(0, 0, w, h)
    for (let i = 3; i < data.length; i += 4) if (data[i] !== 0) return true
    return false
  } catch {
    return true
  }
}

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
  const logo = s.iconMode === 'record' ? stationLogo(s.iconChoice) : s.iconMode === 'atlas' || s.iconMode === 'image' ? (s.iconImage ?? undefined) : undefined
  const imagePicker = (
    <>
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
            const url = URL.createObjectURL(f)
            s.set({ iconImage: url, iconImageSize: null, iconImageHasPixels: true })
            const img = new Image()
            img.onload = () =>
              s.set({ iconImageSize: [img.naturalWidth, img.naturalHeight], iconImageHasPixels: hasOpaquePixels(img) })
            img.src = url
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
            s.set({ iconImage: null, iconImageSize: null, iconImageHasPixels: true })
          }}
        >
          Remove
        </button>
      )}
    </>
  )
  const imageSizeNote = s.iconImageSize && (
    <>
      {' '}
      This image is {s.iconImageSize[0]} x {s.iconImageSize[1]} px, and the previews draw it at that size, as a world
      radio does. The game&apos;s own logos are 240 to {LOGO_MAX.w} px wide and 130 to {LOGO_MAX.h} px tall;{' '}
      {ICON_IMAGE_RECOMMENDED} x {ICON_IMAGE_RECOMMENDED} px is as large as one is worth making, and a tall one covers
      more of a world radio&apos;s screen.
    </>
  )
  const textureSize = s.iconImageSize && iconTextureSize(s.iconImageSize)
  const scaledNotice = s.iconImageSize && textureSize && textureSize[0] !== s.iconImageSize[0] && (
    <>
      Larger than {ICON_IMAGE_RECOMMENDED} x {ICON_IMAGE_RECOMMENDED} px, so the icon is written at{' '}
      {textureSize[0]} x {textureSize[1]} px.
    </>
  )
  const archiveNotice = s.iconArchiveUnreadable && !s.iconImage && (
    <>
      This station&apos;s icon archive is compressed, which this page cannot read. Choose an image to see the icon in
      the previews; the archive itself goes back into the zip untouched.
    </>
  )

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
    const folder = s.folder ?? modFolder(s.stationName, s.cname)
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
      let extras = s.extras
      if (generatesIcon(s)) {
        const { part, atlas } = iconTarget(s)
        const icon = await iconArchiveFile({ image: s.iconImage!, size: s.iconImageSize!, atlas, part, folder })
        // A station mod carries one icon archive; an opened station's old one would name the same atlas.
        extras = [icon, ...s.extras.filter((x) => !/\.archive$/i.test(x.path))]
      }
      await buildZip({
        folder,
        manifest,
        tracks: s.tracks,
        extras,
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
            <p className="pending">Converting a RadioExt station is not built yet.</p>
          ) : (
            <>
              <OpenStation hasWork={hasWork} onOpened={(name) => notify('Station opened', name)} />
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
              {s.iconMode === 'image' && (
                <>
                  <Row
                    label="Icon image"
                    notice={scaledNotice || undefined}
                    note={
                      <>
                        Build .zip makes the icon&apos;s texture, atlas and archive from this image. Draw it white on a
                        transparent background: the Radioport tints the icon with the UI&apos;s colour, as the previews
                        show.
                        {imageSizeNote}
                      </>
                    }
                  >
                    {imagePicker}
                  </Row>
                  <Row label="Atlas" note="The .inkatlas path the archive holds.">
                    <TextInput
                      value={s.iconAtlas}
                      onChange={(v) => s.set({ iconAtlas: v, iconTargetEdited: true })}
                      placeholder={defaultIconTarget(s.cname).atlas || 'mymod\\gui\\icons.inkatlas'}
                    />
                  </Row>
                  <Row label="Part" note="The icon's name in the atlas.">
                    <TextInput
                      value={s.iconPart}
                      onChange={(v) => s.set({ iconPart: v, iconTargetEdited: true })}
                      placeholder={defaultIconTarget(s.cname).part || 'my_station'}
                    />
                  </Row>
                </>
              )}
              {s.iconMode === 'atlas' && (
                <>
                  <Row
                    label="Atlas"
                    note={
                      <>
                        The .inkatlas path inside your station&apos;s archive. Add the archive to the zip yourself, or open
                        a station that already has it.{' '}
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
                    notice={archiveNotice || undefined}
                    note={
                      <>
                        Shows your icon in the previews, tinted the way the game tints it. The zip does not include it.
                        {imageSizeNote}
                      </>
                    }
                  >
                    {imagePicker}
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
