import { downloadZip, predictLength } from 'client-zip'
import type { Track } from './store'
import { buildIconArchive } from './iconArchive'

/**
 * An image's straight RGBA pixels, top row first, at its own size. WebGL with premultiplication off
 * reads the decoded values exactly; a 2D canvas stores premultiplied 8-bit colour and loses precision
 * wherever alpha is low, so it is the fallback only.
 */
async function imagePixels(url: string): Promise<{ rgba: Uint8Array | Uint8ClampedArray; width: number; height: number }> {
  const img = new Image()
  img.src = url
  await img.decode()
  const width = img.naturalWidth
  const height = img.naturalHeight
  const exact = webglPixels(img, width, height)
  if (exact) return { rgba: exact, width, height }
  const canvas = document.createElement('canvas')
  canvas.width = width
  canvas.height = height
  const ctx = canvas.getContext('2d', { willReadFrequently: true })
  if (!ctx) throw new Error('No 2D canvas')
  ctx.drawImage(img, 0, 0)
  return { rgba: ctx.getImageData(0, 0, width, height).data, width, height }
}

/** Reads an image through a WebGL texture, top row first. Null where WebGL is unavailable. */
function webglPixels(img: HTMLImageElement, width: number, height: number): Uint8Array | null {
  const canvas = document.createElement('canvas')
  const gl = canvas.getContext('webgl')
  if (!gl) return null
  try {
    gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false)
    gl.pixelStorei(gl.UNPACK_COLORSPACE_CONVERSION_WEBGL, gl.NONE)
    const texture = gl.createTexture()
    gl.bindTexture(gl.TEXTURE_2D, texture)
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, img)
    const fb = gl.createFramebuffer()
    gl.bindFramebuffer(gl.FRAMEBUFFER, fb)
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture, 0)
    if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) !== gl.FRAMEBUFFER_COMPLETE) return null
    // readPixels returns the texture's row 0 first, which is the image's top row as uploaded.
    const out = new Uint8Array(width * height * 4)
    gl.readPixels(0, 0, width, height, gl.RGBA, gl.UNSIGNED_BYTE, out)
    return gl.getError() === gl.NO_ERROR ? out : null
  } finally {
    gl.getExtension('WEBGL_lose_context')?.loseContext()
  }
}

/** The station's icon archive, written from an image, at the path a mod manager installs it to. */
export async function iconArchiveFile(opts: { image: string; atlas: string; part: string; folder: string }) {
  const { rgba, width, height } = await imagePixels(opts.image)
  const bytes = buildIconArchive(rgba, width, height, opts.atlas, opts.part)
  return { path: `archive/pc/mod/${opts.folder}.archive`, source: new Blob([bytes as BlobPart]) }
}

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
  extras: { path: string; source: Blob }[]
  target: SaveTarget | null
  onProgress: (p: BuildProgress) => void
}): Promise<void> {
  const base = `red4ext/plugins/RadioXL/stations/${opts.folder}/`
  const manifestFile = new File([opts.manifest], 'station.json', { type: 'application/json' })
  const written = new Set<string>()
  const entries: { name: string; input: Blob; size: number }[] = []
  const add = (name: string, input: Blob) => {
    if (written.has(name.toLowerCase())) return
    written.add(name.toLowerCase())
    entries.push({ name, input, size: input.size })
  }
  add(base + 'station.json', manifestFile)
  for (const t of opts.tracks) if (t.source && !t.url) add(base + t.file, t.source)
  for (const x of opts.extras) add(x.path, x.source)
  const total = Number(predictLength(entries.map((e) => ({ name: e.name, size: e.size }))))
  let done = 0
  opts.onProgress({ written: done, total })

  const counter = new TransformStream<Uint8Array, Uint8Array>({
    transform(chunk, controller) {
      done += chunk.byteLength
      opts.onProgress({ written: done, total })
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
