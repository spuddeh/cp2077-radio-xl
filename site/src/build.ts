import { downloadZip, predictLength } from 'client-zip'
import type { Track } from './store'

export interface BuildProgress {
  written: number
  total: number
}

/** The mod folder name: the station's name with anything outside letters and digits removed. */
export function modFolder(stationName: string, cname: string): string {
  const words = stationName.normalize('NFKD').replace(/[\u0300-\u036f]/g, '').match(/[A-Za-z0-9]+/g)
  return words?.map((w) => w[0].toUpperCase() + w.slice(1)).join('') || cname || 'Station'
}

interface SaveTarget {
  writable: WritableStream<Uint8Array>
}

type SavePicker = (options: {
  suggestedName: string
  types: { description: string; accept: Record<string, string[]> }[]
}) => Promise<{ createWritable: () => Promise<WritableStream<Uint8Array>> }>

/**
 * Asks where to save, where the browser can write straight to a file. Must run inside the click,
 * before anything is awaited, or the browser refuses the picker. Resolves to null when the browser
 * has no picker, and throws AbortError when the user cancels.
 */
export async function pickSaveTarget(fileName: string): Promise<SaveTarget | null> {
  const picker = (window as unknown as { showSaveFilePicker?: SavePicker }).showSaveFilePicker
  if (!picker) return null
  const handle = await picker({
    suggestedName: fileName,
    types: [{ description: 'Zip archive', accept: { 'application/zip': ['.zip'] } }],
  })
  return { writable: await handle.createWritable() }
}

/**
 * Writes the installable zip: the manifest and every track's audio under the station's folder.
 * Audio is stored, not compressed, and streamed, so a large station is never held twice in memory
 * where the browser can write to a file.
 */
export async function buildZip(opts: {
  folder: string
  manifest: string
  tracks: Track[]
  target: SaveTarget | null
  onProgress: (p: BuildProgress) => void
}): Promise<void> {
  const base = `red4ext/plugins/RadioXL/stations/${opts.folder}/`
  const manifestFile = new File([opts.manifest], 'station.json', { type: 'application/json' })
  const entries = [
    { name: base + 'station.json', input: manifestFile },
    ...opts.tracks.flatMap((t) => (t.source ? [{ name: base + t.file, input: t.source }] : [])),
  ]
  const total = Number(predictLength(entries.map((e) => ({ name: e.name, size: e.input.size }))))
  let written = 0
  opts.onProgress({ written, total })

  const counter = new TransformStream<Uint8Array, Uint8Array>({
    transform(chunk, controller) {
      written += chunk.byteLength
      opts.onProgress({ written, total })
      controller.enqueue(chunk)
    },
  })
  const stream = downloadZip(entries, { length: total }).body!.pipeThrough(counter)

  if (opts.target) {
    await stream.pipeTo(opts.target.writable)
    return
  }
  const blob = await new Response(stream).blob()
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = `${opts.folder}.zip`
  link.click()
  setTimeout(() => URL.revokeObjectURL(url), 10_000)
}
