import { readFileSync } from 'node:fs'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// The builder's version, printed in the page footer so a report can say which build it came from,
// and the level target the per-track suggestion aims at. Both are read at build time from the
// files that own them; neither is restated in the page.
const version = JSON.parse(readFileSync(new URL('./package.json', import.meta.url), 'utf-8')).version as string
const target = JSON.parse(readFileSync(new URL('../tools/level-target/target.json', import.meta.url), 'utf-8'))

export default defineConfig({
  base: '/cp2077-radio-xl/',
  plugins: [react()],
  define: {
    __BUILDER_VERSION__: JSON.stringify(version),
    __LEVEL_TARGET__: JSON.stringify({ fileLufsTarget: target.fileLufsTarget, maxGain: target.maxGain }),
  },
})
