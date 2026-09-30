import { useState, type ReactNode } from 'react'
import warning from '../assets/warning-triangle.png'

/** `bare` leaves out the frame behind the control: the game draws its On / Off pair on nothing. */
export function Row(props: { label: string; note?: ReactNode; fault?: string; notice?: ReactNode; bare?: boolean; children: ReactNode }) {
  return (
    <div className="row">
      <label className="row-label">{props.label}</label>
      <div className={props.bare ? 'cell bare' : 'cell ink-frame'}>{props.children}</div>
      {props.notice ? (
        <div className="row-note notice">
          <span className="fault-icon" style={{ maskImage: `url(${warning})` }} aria-hidden />
          <span className="note-text">{props.notice}</span>
        </div>
      ) : null}
      {props.fault ? (
        <div className="row-note fault">
          <span className="fault-icon" style={{ maskImage: `url(${warning})` }} aria-hidden />
          <span className="note-text">{props.fault}</span>
        </div>
      ) : props.note ? (
        <div className="row-note">{props.note}</div>
      ) : null}
    </div>
  )
}

export function Notice(props: { children: ReactNode }) {
  return (
    <div className="row-note notice">
      <span className="fault-icon" style={{ maskImage: `url(${warning})` }} aria-hidden />
      <div className="note-text">{props.children}</div>
    </div>
  )
}

/** Lines to paste somewhere, in a box with a button that copies them. */
export function CopyBlock(props: { text: string }) {
  const [copied, setCopied] = useState(false)
  return (
    <div className="copy-block">
      <pre>{props.text}</pre>
      <button
        type="button"
        className="ink-frame copy-block-button"
        onClick={() =>
          navigator.clipboard.writeText(props.text).then(() => {
            setCopied(true)
            setTimeout(() => setCopied(false), 1500)
          })
        }
      >
        {copied ? 'Copied' : 'Copy'}
      </button>
    </div>
  )
}

export function Fault(props: { children: ReactNode }) {
  return (
    <p className="row-note fault">
      <span className="fault-icon" style={{ maskImage: `url(${warning})` }} aria-hidden />
      <span className="note-text">{props.children}</span>
    </p>
  )
}

export function TextInput(props: {
  value: string
  onChange: (v: string) => void
  placeholder?: string
  inputMode?: 'decimal' | 'text'
  spellCheck?: boolean
}) {
  return (
    <input
      type="text"
      value={props.value}
      placeholder={props.placeholder}
      inputMode={props.inputMode}
      spellCheck={props.spellCheck ?? false}
      onChange={(e) => props.onChange(e.target.value)}
    />
  )
}

export function TextArea(props: { value: string; onChange: (v: string) => void; placeholder?: string; rows?: number }) {
  return (
    <textarea
      value={props.value}
      placeholder={props.placeholder}
      rows={props.rows ?? 4}
      spellCheck
      onChange={(e) => props.onChange(e.target.value)}
    />
  )
}

export function Bool(props: { value: boolean; onChange: (v: boolean) => void }) {
  return (
    <div className="bool">
      <button type="button" className="ink-frame off" aria-pressed={!props.value} onClick={() => props.onChange(false)}>
        Off
      </button>
      <button type="button" className="ink-frame on" aria-pressed={props.value} onClick={() => props.onChange(true)}>
        On
      </button>
    </div>
  )
}

export function Slider(props: {
  value: number
  min: number
  max: number
  step: number
  onChange: (v: number) => void
  format?: (v: number) => string
  /** Given, the value beside the slider can be typed in: it returns the value, or null to refuse the text. */
  parse?: (text: string) => number | null
  disabled?: boolean
}) {
  const shown = props.format ? props.format(props.value) : props.value.toFixed(2)
  // While the field has focus it holds what is being typed; otherwise it shows the value.
  const [draft, setDraft] = useState<string | null>(null)
  const parse = props.parse
  // Reads the field itself, not the draft: a blur that follows the last keystroke can run before
  // React has rendered it. Focusing and leaving changes nothing unless the text says another value.
  const commit = (text: string) => {
    const v = parse ? parse(text) : null
    if (v !== null && v !== Math.round(props.value * 100) / 100) props.onChange(v)
    setDraft(null)
  }
  return (
    <div className="slider">
      <input
        type="range"
        title={props.parse ? 'The arrow keys move this 1% at a time.' : undefined}
        min={props.min}
        max={props.max}
        step={props.step}
        value={props.value}
        disabled={props.disabled}
        onChange={(e) => props.onChange(Number(e.target.value))}
      />
      {parse ? (
        <input
          type="text"
          className="slider-value"
          value={draft ?? shown}
          disabled={props.disabled}
          spellCheck={false}
          aria-label="Level, as a percentage or in dB"
          title="Type a level: 133%, or +2.5 dB. On the slider, the arrow keys move 1%."
          size={Math.max(4, (draft ?? shown).length)}
          onFocus={(e) => {
            setDraft(`${Math.round(props.value * 100)}%`)
            requestAnimationFrame(() => e.target.select())
          }}
          onChange={(e) => setDraft(e.target.value)}
          onBlur={(e) => commit(e.currentTarget.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') e.currentTarget.blur()
            if (e.key === 'Escape') {
              setDraft(null)
              e.currentTarget.blur()
            }
          }}
        />
      ) : (
        <output>{shown}</output>
      )}
    </div>
  )
}

export function Stepper<T extends string>(props: { options: { value: T; label: string }[]; value: T; onChange: (v: T) => void }) {
  const i = Math.max(0, props.options.findIndex((o) => o.value === props.value))
  const step = (d: number) => props.onChange(props.options[(i + d + props.options.length) % props.options.length].value)
  return (
    <div className="stepper">
      <button type="button" className="prev" aria-label="Previous" onClick={() => step(-1)} />
      <span className="stepper-value">{props.options[i].label}</span>
      <button type="button" className="next" aria-label="Next" onClick={() => step(1)} />
      {props.options.length <= 8 ? (
        <div className="stepper-dots" aria-hidden>
          {props.options.map((o, n) => (
            <span key={o.value} className={n === i ? 'here' : undefined} />
          ))}
        </div>
      ) : (
        <div className="stepper-count">
          {i + 1} / {props.options.length}
        </div>
      )}
    </div>
  )
}

export function Hint(props: { keyLabel: string; label: string; onClick?: () => void; disabled?: boolean }) {
  return (
    <button type="button" className="hint" onClick={props.onClick} disabled={props.disabled}>
      <kbd className="ink-frame">{props.keyLabel}</kbd>
      {props.label}
    </button>
  )
}
