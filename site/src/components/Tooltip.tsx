import { cloneElement, useEffect, useId, useRef, useState, type ReactElement } from 'react'

/** How long the pointer rests on the button before the tooltip opens, so passing over does not. */
const HOVER_DELAY = 600

/**
 * tooltipslibrary_4k.inkwidget simpleTooltip: a tab on the left, a dark framed body with a title,
 * a separator and a description. It opens after the pointer rests on its button, or at once on
 * keyboard focus.
 */
export function Tooltip(props: { title: string; text: string; children: ReactElement<{ 'aria-describedby'?: string }> }) {
  const [open, setOpen] = useState(false)
  const timer = useRef(0)
  const id = useId()
  useEffect(() => () => clearTimeout(timer.current), [])
  const close = () => {
    clearTimeout(timer.current)
    setOpen(false)
  }
  return (
    <span
      className="tooltip-anchor"
      onPointerEnter={() => {
        clearTimeout(timer.current)
        timer.current = window.setTimeout(() => setOpen(true), HOVER_DELAY)
      }}
      onPointerLeave={close}
      onPointerDown={close}
      onFocus={(e) => {
        if (e.target.matches(':focus-visible')) setOpen(true)
      }}
      onBlur={close}
    >
      {cloneElement(props.children, { 'aria-describedby': id })}
      <span id={id} role="tooltip" className={open ? 'tooltip open' : 'tooltip'}>
        <span className="tooltip-tab ink-frame cut-bl" aria-hidden />
        <span className="tooltip-body ink-frame">
          <span className="tooltip-title">{props.title}</span>
          <span className="tooltip-text">{props.text}</span>
        </span>
      </span>
    </span>
  )
}
