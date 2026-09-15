import type { ReactNode } from 'react'

export function Row(props: { label: string; note?: string; fault?: string; children: ReactNode }) {
  return (
    <div className="row">
      <label className="row-label">{props.label}</label>
      <div className="cell ink-frame">{props.children}</div>
      {props.fault ? (
        <div className="row-note fault">{props.fault}</div>
      ) : props.note ? (
        <div className="row-note">{props.note}</div>
      ) : null}
    </div>
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
}) {
  return (
    <div className="slider">
      <input
        type="range"
        min={props.min}
        max={props.max}
        step={props.step}
        value={props.value}
        onChange={(e) => props.onChange(Number(e.target.value))}
      />
      <output>{props.format ? props.format(props.value) : props.value.toFixed(2)}</output>
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
