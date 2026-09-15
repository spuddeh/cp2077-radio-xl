import { useEffect, useRef, useState, type CSSProperties } from 'react'
import layouts from '../world/layouts.json'
import glyph from '../assets/radioxl-glyph.png'

export type WorldLayout = keyof typeof layouts

export const WORLD_LAYOUTS: { value: WorldLayout; label: string }[] = [
  { value: 'square', label: 'Square' },
  { value: 'long', label: 'Wide' },
  { value: 'tall', label: 'Tall' },
  { value: 'boombox', label: 'Boombox' },
]

interface InkNode {
  kind: string
  name: string
  x: number
  y: number
  w: number
  h: number
  scale?: number[]
  rotation?: number
  opacity?: number
  color?: string
  part?: string
  role?: string
  text?: string
  fontSize?: number
  weight?: string
  upper?: boolean
  align?: string
  fit?: boolean
  children?: InkNode[]
}

const PARTS = import.meta.glob<string>('../assets/world/*.png', { eager: true, import: 'default' })
const partUrl = (part: string) => PARTS[`../assets/world/${part.replace(/ /g, '_')}.png`]

/** Bar heights for the eleven equaliser columns, as a fraction of the column. */
const EQ = [0.55, 0.72, 0.86, 0.9, 0.82, 0.78, 0.66, 0.5, 0.36, 0.44, 0.3]

const WEIGHTS: Record<string, number> = { Regular: 400, Medium: 500, 'Semi-Bold': 600, Bold: 700 }

/** The tall radio's screen is the wide layout turned on its side. */
const ROTATED: WorldLayout[] = ['tall']

const MAX_HEIGHT = 520

/**
 * A world radio's screen, drawn from the widget tree of its radio_ui inkwidget. Positions are
 * computed at build time by scripts/world-radios.py; this only draws them.
 */
export function WorldRadio(props: { layout: WorldLayout; name: string; logo?: string }) {
  const frame = useRef<HTMLDivElement>(null)
  const width = useWidth(frame)
  const root = layouts[props.layout] as InkNode
  const logoUrl = props.logo ?? glyph
  const logoSize = useImageSize(logoUrl)
  const rotated = ROTATED.includes(props.layout)
  const boxW = rotated ? root.h : root.w
  const boxH = rotated ? root.w : root.h
  const scale = Math.min(width / boxW, MAX_HEIGHT / boxH)

  const draw = (n: InkNode, eqIndex?: number): React.ReactNode => {
    const style: CSSProperties = { left: n.x, top: n.y, width: n.w, height: n.h }
    const transforms = []
    if (n.rotation) transforms.push(`rotate(${n.rotation}deg)`)
    if (n.scale) transforms.push(`scale(${n.scale[0]}, ${n.scale[1]})`)
    if (transforms.length) style.transform = transforms.join(' ')
    if (n.opacity !== undefined) style.opacity = n.opacity

    if (n.kind === 'canvas') {
      const eq = /^eq\d\d$/.test(n.name) ? Number(n.name.slice(2)) - 1 : undefined
      return (
        <div key={n.name + n.x + n.y} className={eq === undefined ? 'wr-node' : 'wr-node wr-eq'} style={style}>
          {n.children?.map((c) => draw(c, eq))}
        </div>
      )
    }
    if (n.kind === 'image' && n.role === 'logo') {
      const [lw, lh] = logoSize
      return (
        <span
          key="logo"
          className="wr-node wr-image"
          style={{
            ...style,
            left: n.x + n.w / 2 - lw / 2,
            top: n.y + n.h / 2 - lh / 2,
            width: lw,
            height: lh,
            background: n.color,
            maskImage: `url(${logoUrl})`,
          }}
        />
      )
    }
    if (n.kind === 'image' && n.part) {
      if (eqIndex !== undefined) {
        // The bar rests below its column and the animation raises it; drawn part-way up.
        style.top = n.h * (1 - EQ[eqIndex % EQ.length]) + 4
      }
      return (
        <span
          key={n.name + n.x + n.y}
          className="wr-node wr-image"
          style={{ ...style, background: n.color, maskImage: `url(${partUrl(n.part)})` }}
        />
      )
    }
    if (n.kind === 'text') {
      const text = n.role === 'name' ? props.name : (n.text ?? '')
      return (
        <span
          key={n.name + n.x + n.y}
          className={n.fit ? 'wr-node wr-text fit' : 'wr-node wr-text'}
          style={{
            ...style,
            ...(n.fit ? { width: 'auto', height: 'auto' } : {}),
            color: n.color,
            fontSize: n.fontSize,
            fontWeight: WEIGHTS[n.weight ?? 'Medium'] ?? 500,
            textTransform: n.upper ? 'uppercase' : undefined,
            textAlign: (n.align ?? 'Left').toLowerCase() as CSSProperties['textAlign'],
          }}
        >
          {text}
        </span>
      )
    }
    return null
  }

  return (
    <div ref={frame} className="world-radio-frame">
    <div className="world-radio" style={{ width: boxW * scale, height: boxH * scale }}>
      <div
        className="wr-screen"
        style={{
          width: root.w,
          height: root.h,
          transform: rotated
            ? `translate(${boxW * scale}px, 0) rotate(90deg) scale(${scale})`
            : `scale(${scale})`,
        }}
      >
        {root.children?.map((c) => draw(c))}
      </div>
    </div>
    </div>
  )
}

function useWidth(ref: React.RefObject<HTMLDivElement | null>): number {
  const [width, setWidth] = useState(480)
  useEffect(() => {
    if (!ref.current) return
    const observer = new ResizeObserver(([entry]) => setWidth(entry.contentRect.width))
    observer.observe(ref.current)
    return () => observer.disconnect()
  }, [ref])
  return width
}

function useImageSize(url: string): [number, number] {
  const [size, setSize] = useState<[number, number]>([256, 256])
  useEffect(() => {
    const img = new Image()
    img.onload = () => setSize([img.naturalWidth, img.naturalHeight])
    img.src = url
  }, [url])
  return size
}
