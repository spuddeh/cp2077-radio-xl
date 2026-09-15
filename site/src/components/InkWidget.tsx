import { forwardRef, useImperativeHandle, useRef, type CSSProperties, type ReactNode } from 'react'

export interface InkNode {
  path: string
  name: string
  kind: 'canvas' | 'image' | 'text' | 'rect'
  x: number
  y: number
  w: number
  h: number
  translate?: number[]
  scale?: number[]
  rotation?: number
  pivot?: number[]
  opacity?: number
  color?: string
  part?: string
  text?: string
  fontSize?: number
  weight?: string
  upper?: boolean
  align?: string
  fit?: boolean
  children?: InkNode[]
}

interface Step {
  at: number
  to: number
  from: number | number[]
  value: number | number[]
  easing: string
}

export interface InkSequence {
  duration: number
  targets: Record<string, Partial<Record<'opacity' | 'translate' | 'scale' | 'size', Step[]>>>
}

export interface InkWidgetData {
  tree: InkNode
  sequences: Record<string, InkSequence>
}

export interface InkWidgetHandle {
  /** Plays a sequence from the start; resolves when it ends. With animate off it resolves at once. */
  play: (name: string, rate?: number) => Promise<void>
}

const PARTS = import.meta.glob<string>('../assets/ink/*.png', { eager: true, import: 'default' })
const partUrl = (part: string) => PARTS[`../assets/ink/${part.replace(/ /g, '_')}.png`]

const WEIGHTS: Record<string, number> = { Regular: 400, Medium: 500, 'Semi-Bold': 600, Bold: 700 }

/** Atlas plates that stretch badly, drawn as chamfered frames at the same colour and opacity. */
const FRAMED_PARTS = new Set(['item_cell_bg', 'item_cell_fg'])

/**
 * A game widget drawn from the tree scripts/ink-widgets.py exported, at the given scale of its
 * authored size, with its library animations played through the Web Animations API.
 */
export const InkWidget = forwardRef<
  InkWidgetHandle,
  {
    data: InkWidgetData
    scale: number
    animate: boolean
    /** Replacement text for a text widget, by widget path. */
    texts?: Record<string, string>
    /** Replacement style for a widget, by widget path. */
    styles?: Record<string, CSSProperties>
    /** Replacement content for a widget, by widget path. */
    slots?: Record<string, ReactNode>
    className?: string
  }
>(function InkWidget(props, ref) {
  const root = useRef<HTMLDivElement>(null)

  useImperativeHandle(ref, () => ({
    play: (name, rate = 1) => {
      const seq = props.data.sequences[name]
      if (!seq || !root.current || !props.animate) return Promise.resolve()
      return playSequence(root.current, seq, rate)
    },
  }))

  const draw = (n: InkNode): ReactNode => {
    const style: CSSProperties = {
      position: 'absolute',
      left: n.x,
      top: n.y,
      width: n.w,
      height: n.h,
      ...(n.translate ? { translate: `${n.translate[0]}px ${n.translate[1]}px` } : {}),
      ...(n.scale ? { scale: `${n.scale[0]} ${n.scale[1]}` } : {}),
      ...(n.rotation ? { rotate: `${n.rotation}deg` } : {}),
      transformOrigin: n.pivot ? `${n.pivot[0] * 100}% ${n.pivot[1] * 100}%` : '50% 50%',
      ...(n.opacity !== undefined ? { opacity: n.opacity } : {}),
      ...props.styles?.[n.path],
    }
    const attrs = { key: n.path || n.name, 'data-ink': n.path }
    const slot = props.slots?.[n.path]

    if (n.kind === 'canvas') {
      return (
        <div {...attrs} style={style}>
          {n.children?.map(draw)}
        </div>
      )
    }
    if (slot !== undefined) {
      return (
        <div {...attrs} style={style}>
          {slot}
        </div>
      )
    }
    if (n.kind === 'rect') return <div {...attrs} style={{ ...style, background: n.color }} />
    if (n.kind === 'image' && n.part && FRAMED_PARTS.has(n.part)) {
      const frame = n.part.endsWith('_bg')
        ? ({ '--fill': n.color, '--edge': 'transparent' } as CSSProperties)
        : ({ '--fill': 'transparent', '--edge': n.color } as CSSProperties)
      return <div {...attrs} className="ink-frame" style={{ ...style, ...frame, '--cut': '24px' } as CSSProperties} />
    }
    if (n.kind === 'image' && n.part) {
      return (
        <div
          {...attrs}
          style={{ ...style, background: n.color, maskImage: `url(${partUrl(n.part)})`, maskSize: '100% 100%' }}
        />
      )
    }
    if (n.kind === 'text') {
      return (
        <div
          {...attrs}
          style={{
            ...style,
            ...(n.fit ? { width: 'auto', height: 'auto' } : { overflow: 'hidden' }),
            whiteSpace: 'nowrap',
            lineHeight: 1,
            color: n.color,
            fontSize: n.fontSize,
            fontWeight: WEIGHTS[n.weight ?? 'Medium'] ?? 500,
            textTransform: n.upper ? 'uppercase' : undefined,
            textAlign: (n.align ?? 'Left').toLowerCase() as CSSProperties['textAlign'],
          }}
        >
          {props.texts?.[n.path] ?? n.text}
        </div>
      )
    }
    return null
  }

  const t = props.data.tree
  return (
    <div className={props.className} style={{ position: 'relative', width: t.w * props.scale, height: t.h * props.scale }}>
      {/* Decorative: the game's fluff text is not content, so the widget is hidden from assistive tech. */}
      <div
        ref={root}
        aria-hidden
        style={{ position: 'absolute', left: 0, top: 0, width: t.w, height: t.h, transform: `scale(${props.scale})`, transformOrigin: '0 0' }}
      >
        {t.children?.map(draw)}
      </div>
    </div>
  )
})

/**
 * Each target's interpolators become keyframes per property. A step's start value is written at
 * its start time with its easing, and its end value at its end time; the first start value is also
 * applied from time 0, and the last value holds after the sequence ends.
 */
function playSequence(root: HTMLElement, seq: InkSequence, rate = 1): Promise<void> {
  const duration = Math.max(seq.duration, 0.001) * 1000
  const animations: Animation[] = []
  for (const [path, tracks] of Object.entries(seq.targets)) {
    const el = root.querySelector<HTMLElement>(`[data-ink="${CSS.escape(path)}"]`)
    if (!el) continue
    for (const [prop, steps] of Object.entries(tracks)) {
      if (!steps?.length) continue
      const frames: Keyframe[] = []
      const offset = (s: number) => Math.min(1, Math.max(0, (s * 1000) / duration))
      frames.push({ offset: 0, ...css(prop, steps[0].from) })
      for (const step of steps) {
        frames.push({ offset: offset(step.at), easing: step.easing, ...css(prop, step.from) })
        frames.push({ offset: offset(step.to), ...css(prop, step.value) })
      }
      frames.sort((a, b) => (a.offset as number) - (b.offset as number))
      frames.push({ offset: 1, ...css(prop, steps[steps.length - 1].value) })
      const animation = el.animate(frames, { duration, fill: 'both' })
      animation.playbackRate = rate
      animations.push(animation)
    }
  }
  return Promise.all(animations.map((a) => a.finished)).then(() => undefined, () => undefined)
}

function css(prop: string, v: number | number[]): Keyframe {
  const [x, y] = Array.isArray(v) ? v : [v, v]
  switch (prop) {
    case 'opacity':
      return { opacity: x }
    case 'translate':
      return { translate: `${x}px ${y}px` }
    case 'scale':
      return { scale: `${x} ${y}` }
    case 'size':
      return { width: `${x}px`, height: `${y}px` }
  }
  return {}
}
