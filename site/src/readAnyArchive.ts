/**
 * Reads a dropped archive of any kind into entries the importers understand.
 *
 * A .zip is read here (`readZip`), which slices stored entries out of the file without unpacking it.
 * Everything else, and a Nexus download is usually a .rar or a .7z, goes through libarchive compiled
 * to WebAssembly, which is fetched only when one is dropped.
 */
import type { Entry } from './importStation'
import { readZip } from './readZip'

/** What the page offers to read. libarchive handles the rest of what it knows; these are the names. */
export const ARCHIVE_NAMES = /\.(zip|rar|r\d\d|7z|tar|tgz|gz|bz2|tbz2?|xz|txz|zst|cab|iso|lha|lzh)$/i

export function isArchiveName(name: string): boolean {
  return ARCHIVE_NAMES.test(name)
}

/** The accept list for a file picker, as the browser wants it. */
export const ARCHIVE_ACCEPT = '.zip,.rar,.7z,.tar,.tgz,.gz,.bz2,.xz,.zst,.cab,.iso,application/zip'

interface LibArchiveEntry {
  file: { name: string; size: number; extract: () => Promise<File> }
  path: string
}

export async function readArchiveFile(file: File): Promise<Entry[]> {
  if (/\.zip$/i.test(file.name)) return readZip(file)
  const { Archive } = await import('libarchive.js')
  Archive.init({ workerUrl: `${import.meta.env.BASE_URL}libarchive/worker-bundle.js` })
  let reader
  try {
    reader = await Archive.open(file)
    if (await reader.hasEncryptedData()) throw new Error(`${file.name} is password-protected, so the page cannot read it.`)
    const found = (await reader.getFilesArray()) as LibArchiveEntry[]
    const entries: Entry[] = []
    for (const { file: inner, path } of found) {
      const full = [path, inner.name].filter(Boolean).join('/').replace(/\\/g, '/').replace(/^\/+/, '')
      // extract() unpacks one entry, so a station's audio is only unpacked if it is wanted.
      entries.push({ path: full, size: inner.size, blob: () => inner.extract() })
    }
    if (!entries.length) throw new Error(`${file.name} holds no files.`)
    return entries
  } catch (e) {
    const message = (e as Error).message ?? String(e)
    if (/password-protected|holds no files/.test(message)) throw e
    throw new Error(`${file.name} could not be read: ${message}`)
  }
}
