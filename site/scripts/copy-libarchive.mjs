// Puts libarchive's worker and its wasm where the page can fetch them at runtime. The worker loads
// libarchive.wasm from its own folder, so the two travel together, and neither is committed.
import { mkdir, copyFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const from = join(here, '..', 'node_modules', 'libarchive.js', 'dist')
const to = join(here, '..', 'public', 'libarchive')

await mkdir(to, { recursive: true })
for (const name of ['worker-bundle.js', 'libarchive.wasm']) {
  await copyFile(join(from, name), join(to, name))
}
console.log(`libarchive: worker and wasm copied to public/libarchive`)
