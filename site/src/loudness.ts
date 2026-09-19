/**
 * Integrated loudness and true peak of decoded audio, the way `tools/level-target.py file` measures
 * a file with ffmpeg's `ebur128`, and the gain that puts the file on the level target.
 *
 * Loudness is EBU R128 / ITU-R BS.1770-4: K-weighting (a high shelf, then a high-pass), 400 ms
 * blocks stepped by 100 ms, an absolute gate at -70 LUFS and a relative gate 10 LU under the
 * gated mean. True peak is the largest sample after 4x oversampling, on any channel.
 *
 * Pure functions over sample arrays, so they run in a worker and under node's test runner alike.
 */

export interface Measurement {
  /** Integrated loudness, LUFS. */
  lufs: number
  /** True peak, dBFS. Above 0 on a hot master. */
  peakDb: number
}

export interface LevelTarget {
  /** The file loudness that lands on the game's median at gain 1. */
  fileLufsTarget: number
  /** The most a manifest may ask for. */
  maxGain: number
}

export interface Suggestion {
  /** The gain that puts the file on the target, or as close as its peak allows. */
  gain: number
  /** The loudness the file plays at with that gain, LUFS. */
  landsAt: number
  /** True when the peak, not the target, decided the gain. */
  peakLimited: boolean
}

/** dB the peak stays under full scale after a raise. AudioXL wraps a sample past it. */
export const PEAK_MARGIN_DB = 1

interface Biquad {
  b0: number
  b1: number
  b2: number
  a1: number
  a2: number
}

/**
 * The two K-weighting stages at a sample rate, from the analogue prototypes the 48 kHz table in
 * BS.1770 was made from. At 48 kHz they reproduce that table.
 */
export function kWeighting(sampleRate: number): [Biquad, Biquad] {
  // Stage 1: a high shelf, +4 dB above about 1.5 kHz.
  const f0 = 1681.974450955533
  const gainDb = 3.999843853973347
  const q = 0.7071752369554196
  const k = Math.tan((Math.PI * f0) / sampleRate)
  const vh = Math.pow(10, gainDb / 20)
  const vb = Math.pow(vh, 0.4996667741545416)
  const a0 = 1 + k / q + k * k
  const shelf: Biquad = {
    b0: (vh + (vb * k) / q + k * k) / a0,
    b1: (2 * (k * k - vh)) / a0,
    b2: (vh - (vb * k) / q + k * k) / a0,
    a1: (2 * (k * k - 1)) / a0,
    a2: (1 - k / q + k * k) / a0,
  }
  // Stage 2: a high-pass at about 38 Hz.
  const f1 = 38.13547087602444
  const q1 = 0.5003270373238773
  const k1 = Math.tan((Math.PI * f1) / sampleRate)
  const d = 1 + k1 / q1 + k1 * k1
  const highPass: Biquad = {
    b0: 1,
    b1: -2,
    b2: 1,
    a1: (2 * (k1 * k1 - 1)) / d,
    a2: (1 - k1 / q1 + k1 * k1) / d,
  }
  return [shelf, highPass]
}

/** Channel weights by position: left, right and centre 1, the surrounds 1.41, anything more 1. */
function channelWeight(index: number, count: number): number {
  if (count >= 5 && (index === 3 || index === 4)) return 1.41
  return 1
}

/**
 * Integrated loudness of the channels given, LUFS. Null when nothing passes the absolute gate,
 * which is what silence measures.
 */
export function integratedLoudness(channels: Float32Array[], sampleRate: number): number | null {
  if (channels.length === 0) return null
  const length = channels[0].length
  const step = Math.round(sampleRate * 0.1)
  const steps = Math.floor(length / step)
  if (steps < 4) return null
  const [shelf, highPass] = kWeighting(sampleRate)

  // Mean square of the K-weighted signal per 100 ms step, summed over channels with their weights.
  // A 400 ms block is four consecutive steps.
  const stepPower = new Float64Array(steps)
  for (let c = 0; c < channels.length; c++) {
    const x = channels[c]
    const w = channelWeight(c, channels.length)
    let s1 = 0
    let s2 = 0
    let h1 = 0
    let h2 = 0
    for (let i = 0; i < steps; i++) {
      let sum = 0
      const end = (i + 1) * step
      for (let n = i * step; n < end; n++) {
        const v = x[n]
        // Transposed direct form II, both stages.
        const y1 = shelf.b0 * v + s1
        s1 = shelf.b1 * v - shelf.a1 * y1 + s2
        s2 = shelf.b2 * v - shelf.a2 * y1
        const y2 = highPass.b0 * y1 + h1
        h1 = highPass.b1 * y1 - highPass.a1 * y2 + h2
        h2 = highPass.b2 * y1 - highPass.a2 * y2
        sum += y2 * y2
      }
      stepPower[i] += (w * sum) / step
    }
  }

  const blocks = steps - 3
  const power = new Float64Array(blocks)
  for (let j = 0; j < blocks; j++) {
    power[j] = (stepPower[j] + stepPower[j + 1] + stepPower[j + 2] + stepPower[j + 3]) / 4
  }
  const toLufs = (z: number) => -0.691 + 10 * Math.log10(z)

  // The absolute gate, then the relative gate 10 LU under the mean of what passed it.
  const absolute = Math.pow(10, (-70 + 0.691) / 10)
  let count = 0
  let sum = 0
  for (let j = 0; j < blocks; j++) {
    if (power[j] > absolute) {
      count++
      sum += power[j]
    }
  }
  if (count === 0) return null
  const relative = Math.pow(10, (toLufs(sum / count) - 10 + 0.691) / 10)
  count = 0
  sum = 0
  for (let j = 0; j < blocks; j++) {
    if (power[j] > absolute && power[j] > relative) {
      count++
      sum += power[j]
    }
  }
  if (count === 0) return null
  return toLufs(sum / count)
}

/** The 4x interpolation filter: 48 taps of a windowed sinc, split into its four phases. */
function interpolationPhases(): Float64Array[] {
  const over = 4
  const taps = 48
  const centre = (taps - 1) / 2
  const phases: Float64Array[] = []
  for (let p = 0; p < over; p++) {
    const phase = new Float64Array(taps / over)
    let sum = 0
    for (let m = 0; m < taps / over; m++) {
      const n = m * over + p
      const t = (n - centre) / over
      const sinc = t === 0 ? 1 : Math.sin(Math.PI * t) / (Math.PI * t)
      const window = 0.42 - 0.5 * Math.cos((2 * Math.PI * n) / (taps - 1)) + 0.08 * Math.cos((4 * Math.PI * n) / (taps - 1))
      phase[m] = sinc * window
      sum += phase[m]
    }
    // Each phase passes a constant at unity, so a flat signal reads its own level.
    for (let m = 0; m < phase.length; m++) phase[m] /= sum
    phases.push(phase)
  }
  return phases
}

const PHASES = interpolationPhases()

/** True peak over every channel, dBFS: the largest sample after 4x oversampling. */
export function truePeakDb(channels: Float32Array[]): number | null {
  let peak = 0
  const span = PHASES[0].length
  for (const x of channels) {
    for (let n = 0; n < x.length; n++) {
      const raw = Math.abs(x[n])
      if (raw > peak) peak = raw
      for (const phase of PHASES) {
        let y = 0
        for (let m = 0; m < span; m++) {
          const i = n - m
          if (i >= 0) y += phase[m] * x[i]
        }
        const a = Math.abs(y)
        if (a > peak) peak = a
      }
    }
  }
  if (peak === 0) return null
  return 20 * Math.log10(peak)
}

/** Both readings for the channels given, or null for audio that cannot be measured. */
export function measure(channels: Float32Array[], sampleRate: number): Measurement | null {
  const lufs = integratedLoudness(channels, sampleRate)
  const peakDb = truePeakDb(channels)
  if (lufs === null || peakDb === null) return null
  return { lufs, peakDb }
}

/**
 * The gain that lands the file on the target, bounded by its own peak: a raise must keep the peak
 * under full scale by the margin, and a cut never wraps. The same arithmetic as
 * `tools/level-target.py file`.
 */
export function suggestGain(m: Measurement, target: LevelTarget, margin = PEAK_MARGIN_DB): Suggestion {
  const wantedDb = target.fileLufsTarget - m.lufs
  const allowedDb = -margin - m.peakDb
  const db = wantedDb > 0 ? Math.max(0, Math.min(wantedDb, allowedDb)) : wantedDb
  const gain = Math.round(Math.min(target.maxGain, Math.max(0, Math.pow(10, db / 20))) * 100) / 100
  const landsAt = gain > 0 ? m.lufs + 20 * Math.log10(gain) : -Infinity
  return { gain, landsAt, peakLimited: wantedDb > 0 && allowedDb < wantedDb }
}

/** A gain as the page shows it: a percentage, and the level change it makes. */
export function gainLabel(gain: number): string {
  const pct = `${Math.round(gain * 100)}%`
  if (gain <= 0) return `${pct} (silent)`
  if (Math.abs(gain - 1) < 0.001) return pct
  const db = 20 * Math.log10(gain)
  return `${pct} (${db > 0 ? '+' : ''}${db.toFixed(1)} dB)`
}
