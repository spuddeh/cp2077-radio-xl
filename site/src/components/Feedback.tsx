import { useEffect, useRef } from 'react'
import { InkWidget, type InkWidgetData, type InkWidgetHandle } from './InkWidget'
import progressData from '../ink/progress.json'
import toastData from '../ink/toast.json'
import glyph from '../assets/radioxl-glyph.png'

const PROGRESS = progressData as unknown as InkWidgetData
const TOAST = toastData as unknown as InkWidgetData

const BAR = 'wrapper/Personal_Link_Main_Elements_Canvas/Process_Bar_Main_Line'
const BAR_EXTRA = 'wrapper/Personal_Link_Main_Elements_Canvas/Process_Bar_Extra_Line'
const HEADER = 'wrapper/Quickhack_Elements_Canvas/Attention_Flex_TEXT'
const LOADING = 'wrapper/Quickhack_Elements_Canvas/loading_Canvas/loading_text_Panel/LOADING_text'
const PERCENT = 'wrapper/Quickhack_Elements_Canvas/loading_Canvas/loading_text_Panel/LOADING_Percentage_text'
const CONNECTION = 'wrapper/Quickhack_Elements_Canvas/loading_Canvas/inkTextWidget11'
const PERCENT_SIGN = 'wrapper/Quickhack_Elements_Canvas/loading_Canvas/loading_text_Panel/LOADING_PRCT_text'
const COMPLETED = 'wrapper/Quickhack_Elements_Canvas/LOADING_COMPLETE_text'
const FAILED = 'wrapper/Quickhack_Elements_Canvas/LOADING_FAILED_text'

const TOAST_TITLE = 'Item_recived_All/LeftCorner_Ico/NewItemReceived/New_Item'
const TOAST_ICON = 'Item_recived_All/L_R/Plate/inkFlexWidget9/Item_Icon'
const TOAST_SHADOW = 'shadowBlob'

/** HUDProgressBarController: the bar is 996 authored pixels at 100%. */
const BAR_WIDTH = 996

export type BuildPhase = 'running' | 'done' | 'failed'

/**
 * hud_progress_bar.inkwidget: Quickhack_Intro as a build starts, the bar and percentage while it
 * runs, then Quickhack_Outro (completed) or Quickhack_Outro_Failed.
 */
export function BuildProgress(props: {
  phase: BuildPhase | null
  title: string
  written: number
  total: number
  animate: boolean
  onFinished: () => void
}) {
  const widget = useRef<InkWidgetHandle>(null)
  const { phase, animate, onFinished } = props

  useEffect(() => {
    if (!phase) return
    const hold = (ms: number) => new Promise((r) => setTimeout(r, animate ? 0 : ms))
    if (phase === 'running') widget.current?.play('Quickhack_Intro')
    if (phase === 'done' || phase === 'failed') {
      let cancelled = false
      widget.current
        ?.play(phase === 'done' ? 'Quickhack_Outro' : 'Quickhack_Outro_Failed')
        .then(() => hold(1200))
        .then(() => !cancelled && onFinished())
      return () => {
        cancelled = true
      }
    }
  }, [phase, animate, onFinished])

  if (!phase) return null
  // The bar spans the middle 1000 of the widget's 2000 authored pixels; fit that to the window.
  const scale = Math.min(0.7, (window.innerWidth - 32) / 1000)
  const share = props.total ? Math.min(1, props.written / props.total) : 0
  const mb = (b: number) => (b / 1048576).toFixed(1)
  return (
    <div className="build-overlay" role="status" aria-live="polite">
      <InkWidget
        ref={widget}
        data={PROGRESS}
        scale={scale}
        animate={animate}
        className="build-progress"
        texts={{
          [HEADER]: props.title,
          [LOADING]: 'Writing',
          // The panel spaces its three texts at their authored widths; one string keeps the sign on the number.
          [PERCENT]: `${Math.round(share * 100)}%`,
          [PERCENT_SIGN]: '',
          [CONNECTION]: `${mb(props.written)} / ${mb(props.total)} MB`,
          [COMPLETED]: 'Saved',
          [FAILED]: 'Failed',
        }}
        styles={{
          [BAR]: { width: share * BAR_WIDTH },
          [BAR_EXTRA]: { display: 'none' },
          ...(!animate && phase === 'done' ? { [COMPLETED]: { opacity: 1 }, [HEADER]: { opacity: 0 } } : {}),
          ...(!animate && phase === 'failed' ? { [FAILED]: { opacity: 1 }, [HEADER]: { opacity: 0 } } : {}),
        }}
      />
      <span className="visually-hidden">{`${props.title}: ${Math.round(share * 100)}%`}</span>
    </div>
  )
}

export interface Toast {
  id: number
  title: string
  message: string
}

/** items_update.inkwidget Item_Received_SMALL: plays its whole life, in, hold and out, then ends. */
export function ToastView(props: { toast: Toast; animate: boolean; onDone: () => void }) {
  const widget = useRef<InkWidgetHandle>(null)
  const { animate, onDone } = props
  useEffect(() => {
    let cancelled = false
    const ready = animate ? widget.current?.play('Item_Received_SMALL') : new Promise((r) => setTimeout(r, 3000))
    ready?.then(() => !cancelled && onDone())
    return () => {
      cancelled = true
    }
  }, [animate, onDone])
  return (
    <div className="toast" role="status" aria-live="polite">
      <InkWidget
        ref={widget}
        data={TOAST}
        scale={Math.min(0.7, (window.innerWidth - 32) / 900)}
        animate={animate}
        texts={{ [TOAST_TITLE]: props.toast.title }}
        // The page fade behind every notification replaces the widget's shadow blob, which would draw
        // a darker ring on top of it.
        styles={{ [TOAST_SHADOW]: { display: 'none' } }}
        slots={{
          [TOAST_ICON]: (
            <div className="toast-item">
              <span className="toast-glyph" style={{ maskImage: `url(${glyph})` }} />
              <span className="toast-message">{props.toast.message}</span>
            </div>
          ),
        }}
      />
      <span className="visually-hidden">{`${props.toast.title}: ${props.toast.message}`}</span>
    </div>
  )
}
