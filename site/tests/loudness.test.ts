/**
 * The loudness meter against signals whose reading is known, and the suggestion against the
 * arithmetic of `tools/level-target.py file`.
 *
 * EBU Tech 3341 gives the checks: a 997 Hz sine at -23 dBFS on both channels reads -23.0 LUFS, and
 * the same at -33 dBFS reads -33.0, within 0.1 LU. The gates are checked with silence and with a
 * quiet passage that the relative gate must leave out.
 *
 * Run with `npm test`.
 */
import { strict as assert } from 'node:assert'
import { test } from 'node:test'

import { gainLabel, integratedLoudness, kWeighting, measure, suggestGain, truePeakDb } from '../src/loudness.ts'

const RATE = 48000

/** A sine on every channel, at a level in dBFS (peak), for a number of seconds. */
function sine(dbfs: number, seconds: number, channels = 2, hz = 997, rate = RATE): Float32Array[] {
  const amplitude = Math.pow(10, dbfs / 20)
  const length = Math.round(seconds * rate)
  const one = new Float32Array(length)
  for (let n = 0; n < length; n++) one[n] = amplitude * Math.sin((2 * Math.PI * hz * n) / rate)
  return Array.from({ length: channels }, () => one.slice())
}

function concat(a: Float32Array[], b: Float32Array[]): Float32Array[] {
  return a.map((x, i) => {
    const out = new Float32Array(x.length + b[i].length)
    out.set(x)
    out.set(b[i], x.length)
    return out
  })
}

test('the K-weighting at 48 kHz is the table in BS.1770', () => {
  const [shelf, highPass] = kWeighting(48000)
  const close = (a: number, b: number) => assert.ok(Math.abs(a - b) < 1e-6, `${a} vs ${b}`)
  close(shelf.b0, 1.53512485958697)
  close(shelf.b1, -2.69169618940638)
  close(shelf.b2, 1.19839281085285)
  close(shelf.a1, -1.69065929318241)
  close(shelf.a2, 0.73248077421585)
  close(highPass.a1, -1.99004745483398)
  close(highPass.a2, 0.99007225036621)
})

test('a -23 dBFS stereo sine reads -23.0 LUFS', () => {
  const lufs = integratedLoudness(sine(-23, 10), RATE)
  assert.ok(lufs !== null && Math.abs(lufs + 23) < 0.1, `${lufs}`)
})

test('a -33 dBFS stereo sine reads -33.0 LUFS, and one channel alone reads 3 dB less', () => {
  const both = integratedLoudness(sine(-33, 10), RATE)
  assert.ok(both !== null && Math.abs(both + 33) < 0.1, `${both}`)
  const one = integratedLoudness(sine(-33, 10, 1), RATE)
  assert.ok(one !== null && Math.abs(one + 36.01) < 0.1, `${one}`)
})

test('the same at 44.1 kHz', () => {
  const lufs = integratedLoudness(sine(-23, 10, 2, 997, 44100), 44100)
  assert.ok(lufs !== null && Math.abs(lufs + 23) < 0.1, `${lufs}`)
})

test('silence has no loudness, and silence around a tone does not lower it', () => {
  assert.equal(integratedLoudness([new Float32Array(RATE * 5), new Float32Array(RATE * 5)], RATE), null)
  const padded = concat(concat(sine(-80, 5), sine(-23, 10)), sine(-80, 5))
  // The blocks that straddle an edge are half tone and pass the relative gate, so the reading sits
  // a little under the tone's own.
  const lufs = integratedLoudness(padded, RATE)
  assert.ok(lufs !== null && Math.abs(lufs + 23) < 0.2, `the absolute gate should drop the -80 dBFS passages: ${lufs}`)
})

test('the relative gate leaves out a passage more than 10 LU under the rest', () => {
  // EBU Tech 3341 case 9 in spirit: 20 s at -36 dBFS beside 20 s at -23 reads -23.0.
  const lufs = integratedLoudness(concat(sine(-36, 20), sine(-23, 20)), RATE)
  assert.ok(lufs !== null && Math.abs(lufs + 23) < 0.1, `${lufs}`)
})

test('true peak of a sine is its amplitude, and a crest between samples is found', () => {
  const peak = truePeakDb(sine(-6, 1))
  assert.ok(peak !== null && Math.abs(peak + 6) < 0.05, `${peak}`)
  // A full-scale sine sampled so that no sample lands on the crest: the samples sit under 0 dBFS,
  // the true peak does not.
  const rate = 48000
  const length = rate
  const x = new Float32Array(length)
  for (let n = 0; n < length; n++) x[n] = Math.sin((2 * Math.PI * 12000 * n) / rate + Math.PI / 4)
  let sample = 0
  for (const v of x) sample = Math.max(sample, Math.abs(v))
  const truePeak = truePeakDb([x])
  assert.ok(sample < 0.72, `the samples miss the crest: ${sample}`)
  assert.ok(truePeak !== null && truePeak > -0.3 && truePeak < 0.3, `the oversampled peak finds it: ${truePeak}`)
})

test('measure gives both readings, or null for silence', () => {
  const m = measure(sine(-23, 10), RATE)
  assert.ok(m && Math.abs(m.lufs + 23) < 0.1 && Math.abs(m.peakDb + 23) < 0.05, JSON.stringify(m))
  assert.equal(measure([new Float32Array(RATE * 5)], RATE), null)
})

const TARGET = { fileLufsTarget: -11.1, maxGain: 4 }

test('the suggestion is what level-target.py file prints', () => {
  // Tool FM's files through the tool, 2026-09-19: lufs, peak, and the gain it printed.
  const cases: [number, number, number, boolean][] = [
    [-7.4, 1.3, 0.65, false],
    [-10.9, 1.1, 0.98, false],
    [-11.7, 0.3, 1.0, true],
    [-9.2, 1.3, 0.8, false],
    [-22.9, -8.4, 2.34, true],
    [-16.5, -1.9, 1.11, true],
    [-10.4, 1.7, 0.92, false],
    [-7.8, 2.0, 0.68, false],
    [-8.6, 1.0, 0.75, false],
    [-20.8, -2.6, 1.2, true],
    [-11.8, 0.8, 1.0, true],
  ]
  for (const [lufs, peakDb, gain, limited] of cases) {
    const s = suggestGain({ lufs, peakDb }, TARGET)
    assert.equal(s.gain, gain, `${lufs} LUFS, peak ${peakDb}: ${JSON.stringify(s)}`)
    assert.equal(s.peakLimited, limited, `${lufs} LUFS, peak ${peakDb}: ${JSON.stringify(s)}`)
  }
})

test('a cut is never peak-limited, a raise is bounded by the peak, and nothing passes 4', () => {
  const cut = suggestGain({ lufs: -5, peakDb: 3 }, TARGET)
  assert.equal(cut.gain, 0.5)
  assert.equal(cut.peakLimited, false)
  assert.ok(Math.abs(cut.landsAt + 11.1) < 0.1, `${cut.landsAt}`)
  const raise = suggestGain({ lufs: -20, peakDb: -20 }, TARGET)
  assert.equal(raise.gain, 2.79)
  assert.equal(raise.peakLimited, false)
  const capped = suggestGain({ lufs: -30, peakDb: -30 }, TARGET)
  assert.equal(capped.gain, 4)
  const atMargin = suggestGain({ lufs: -20, peakDb: -1 }, TARGET)
  assert.equal(atMargin.gain, 1)
  assert.equal(atMargin.peakLimited, true)
})

test('the gain label reads as the station slider does', () => {
  assert.equal(gainLabel(1), '100%')
  assert.equal(gainLabel(0.5), '50% (-6.0 dB)')
  assert.equal(gainLabel(2), '200% (+6.0 dB)')
  assert.equal(gainLabel(0), '0% (silent)')
})
