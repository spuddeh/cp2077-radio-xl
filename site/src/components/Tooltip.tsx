import { useId, useState, type ReactElement, cloneElement } from 'react'

/**
 * tooltipslibrary_4k.inkwidget simpleTooltip: a tab on the left, a dark framed body with a title,
 * a separator and a description. It opens on hover and on keyboard focus.
 */
export function Tooltip(props: { title: string; text: string; children: ReactElement<{ 'aria-describedby'?: string }> }) {
  const [open, setOpen] = useState(false)
  const id = useId()
  return (
    <span
      className="tooltip-anchor"
      onPointerEnter={() => setOpen(true)}
      onPointerLeave={() => setOpen(false)}
      onFocus={() => setOpen(true)}
      onBlur={() => setOpen(false)}
    >
      {cloneElement(props.children, { 'aria-describedby': id })}
      <span id={id} role="tooltip" className={open ? 'tooltip open' : 'tooltip'}>
        <span className="tooltip-tab" aria-hidden />
        <span className="tooltip-body ink-frame">
          <span className="tooltip-title">{props.title}</span>
          <span className="tooltip-text">{props.text}</span>
        </span>
      </span>
    </span>
  )
}
