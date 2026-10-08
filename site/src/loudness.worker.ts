/**
 * Measures decoded audio off the page's thread: a full-length track is a few seconds of arithmetic,
 * which would freeze the form. Takes the channels and the sample rate, answers the measurement.
 */
import { measure } from './loudness'

self.onmessage = (e: MessageEvent<{ id: number; channels: Float32Array[]; sampleRate: number }>) => {
  const { id, channels, sampleRate } = e.data
  self.postMessage({ id, result: measure(channels, sampleRate) })
}
