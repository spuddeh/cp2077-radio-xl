/**
 * The browser side of a track's level: decoding a file for measurement, the one-at-a-time queue
 * that keeps a big drop from decoding everything at once, and the preview player that plays a
 * track through the gain the slider holds.
 */
import type { Measurement } from './loudness'

let context: AudioContext | null = null

function audioContext(): AudioContext {
  if (!context) context = new AudioContext()
  return context
}

let worker: Worker | null = null
let nextJob = 1
const pending = new Map<number, (m: Measurement | null) => void>()

function measurer(): Worker {
  if (!worker) {
    worker = new Worker(new URL('./loudness.worker.ts', import.meta.url), { type: 'module' })
    worker.onmessage = (e: MessageEvent<{ id: number; result: Measurement | null }>) => {
      pending.get(e.data.id)?.(e.data.result)
      pending.delete(e.data.id)
    }
  }
  return worker
}

/** A file's channels as the browser decodes them. Throws on a file the browser cannot decode. */
async function decode(blob: Blob): Promise<{ channels: Float32Array[]; sampleRate: number }> {
  const buffer = await audioContext().decodeAudioData(await blob.arrayBuffer())
  const channels: Float32Array[] = []
  for (let c = 0; c < buffer.numberOfChannels; c++) channels.push(buffer.getChannelData(c).slice())
  return { channels, sampleRate: buffer.sampleRate }
}

let queue: Promise<unknown> = Promise.resolve()

/**
 * Measures a file, one file at a time across every caller. Null for a file the browser cannot
 * decode or that holds nothing measurable.
 */
export function measureFile(blob: Blob): Promise<Measurement | null> {
  const job = queue.then(async () => {
    let decoded
    try {
      decoded = await decode(blob)
    } catch {
      return null
    }
    const id = nextJob++
    return new Promise<Measurement | null>((resolve) => {
      pending.set(id, resolve)
      measurer().postMessage(
        { id, channels: decoded.channels, sampleRate: decoded.sampleRate },
        decoded.channels.map((c) => c.buffer),
      )
    })
  })
  queue = job.catch(() => undefined)
  return job
}

/**
 * One player for the whole page: an audio element through a gain node, so a track is heard at the
 * level its slider holds. Starting a track stops whichever was playing.
 */
class Preview {
  private element: HTMLAudioElement | null = null
  private gain: GainNode | null = null
  private url: string | null = null
  private onChange: (() => void) | null = null
  playing: number | null = null

  private setup(): { element: HTMLAudioElement; gain: GainNode } {
    if (this.element && this.gain) return { element: this.element, gain: this.gain }
    const ctx = audioContext()
    const element = new Audio()
    element.crossOrigin = 'anonymous'
    const source = ctx.createMediaElementSource(element)
    const gain = ctx.createGain()
    source.connect(gain)
    gain.connect(ctx.destination)
    element.onended = () => this.stop()
    element.onerror = () => this.stop()
    this.element = element
    this.gain = gain
    return { element, gain }
  }

  /** Plays a track's audio at a gain, from the start. */
  async play(id: number, blob: Blob, gain: number, onChange: () => void): Promise<void> {
    this.stop()
    const { element, gain: node } = this.setup()
    await audioContext().resume()
    this.url = URL.createObjectURL(blob)
    element.src = this.url
    node.gain.value = gain
    this.playing = id
    this.onChange = onChange
    onChange()
    try {
      await element.play()
    } catch {
      this.stop()
    }
  }

  /** The gain the playing track is heard at, live as the slider moves. */
  setGain(id: number, gain: number): void {
    if (this.playing === id && this.gain) this.gain.gain.value = gain
  }

  stop(): void {
    if (this.element) {
      this.element.pause()
      this.element.removeAttribute('src')
      this.element.load()
    }
    if (this.url) URL.revokeObjectURL(this.url)
    this.url = null
    const change = this.onChange
    this.playing = null
    this.onChange = null
    change?.()
  }
}

export const preview = new Preview()
