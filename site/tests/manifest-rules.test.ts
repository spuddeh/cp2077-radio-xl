/**
 * The page's checker against the plugin's own rules.
 *
 * Each case is a station.json the plugin accepts or refuses, taken from `plugin/tests/ManifestTests.cpp`.
 * A case is read into form state the way an opened station is, then checked and written back out, so
 * a rule the plugin enforces and the page does not shows up as a station the page would offer to
 * build and RadioXL would skip.
 *
 * Out of scope here: JSON syntax (the page writes its manifest with JSON.stringify) and wrong types
 * (the form holds typed state), which the plugin's own tests cover.
 *
 * Run with `npm test`.
 */
import { strict as assert } from 'node:assert'
import { test } from 'node:test'

import { buildManifest, checkManifest, type ManifestInput } from '../src/manifest.ts'
import type { Track } from '../src/store.ts'

/** Form state as an opened station would leave it, from a manifest's own JSON. */
function asFormState(manifest: Record<string, unknown>): ManifestInput {
  const display = typeof manifest.displayName === 'string' ? manifest.displayName : ''
  const parts = display.match(/^\s*(\d{2,3}(?:\.\d+)?)\s*(.*)$/)
  const icon = typeof manifest.icon === 'string' ? manifest.icon : ''
  const atlas = typeof manifest.atlas === 'string' ? manifest.atlas : ''
  const tracks: Track[] = (Array.isArray(manifest.tracks) ? manifest.tracks : []).map((raw, i) => {
    const t = (raw ?? {}) as Record<string, unknown>
    const url = typeof t.url === 'string' ? t.url : undefined
    return {
      id: i + 1,
      file: typeof t.file === 'string' ? t.file : '',
      title: typeof t.title === 'string' ? t.title : '',
      ident: t.ident === true,
      url,
      // A track with a file stands for one whose audio was found beside the manifest.
      source: url ? undefined : new Blob([new Uint8Array(4)]),
    }
  })
  return {
    frequency: parts ? parts[1] : '',
    stationName: parts ? parts[2].trim() : display,
    cname: typeof manifest.name === 'string' ? manifest.name : '',
    news: manifest.news === true,
    gain: typeof manifest.gain === 'number' ? manifest.gain : 1,
    iconMode: atlas ? 'atlas' : icon ? 'record' : 'glyph',
    iconChoice: icon && !atlas ? 'other' : 'UIIcon.RadioDowntempo',
    iconRecord: icon && !atlas ? icon : '',
    iconPart: atlas ? icon : '',
    iconAtlas: atlas,
    iconImage: null,
    iconImageSize: null,
    iconImageHasPixels: true,
    tracks,
  }
}

const GOOD = {
  name: 'radio_station_20_tool',
  displayName: '104.9 Tool FM',
  icon: 'tool_fm',
  atlas: 'toolfm\\gui\\tool_fm.inkatlas',
  news: true,
  tracks: [
    { file: 'audio/Tool - Vicarious.mp3', title: 'Tool - Vicarious' },
    { file: 'audio/Tool - Jambi.mp3', title: 'Tool - Jambi' },
  ],
}

/** A copy of the good manifest with one thing changed. */
function like(patch: Record<string, unknown>): Record<string, unknown> {
  return { ...structuredClone(GOOD), ...patch }
}

const REFUSED: [name: string, manifest: Record<string, unknown>][] = [
  ['name missing', like({ name: '' })],
  ['name with a space', like({ name: 'my station' })],
  ['tracks empty', like({ tracks: [] })],
  ['track file empty', like({ tracks: [{ file: '' }] })],
  ['every track an ident', like({ tracks: [{ file: 'a.mp3', ident: true }] })],
  ['url not http', like({ tracks: [{ url: 'ftp://h/s' }] })],
  ['url beside other tracks', like({ tracks: [{ url: 'http://h/s' }, { file: 'a.mp3' }] })],
  ['a url ident', like({ tracks: [{ url: 'http://h/s', ident: true }] })],
  ['an atlas part with no atlas', like({ icon: 'tool_fm', atlas: '' })],
]

const ACCEPTED: [name: string, manifest: Record<string, unknown>][] = [
  ['the good manifest', GOOD],
  ['an icon record and no atlas', like({ icon: 'UIIcon.RadioHipHop', atlas: '' })],
  ['no icon at all', like({ icon: '', atlas: '' })],
  ['a stream as the one track', like({ tracks: [{ url: 'https://ice1.somafm.com/groovesalad-128-mp3' }] })],
  ['idents beside songs', like({ tracks: [{ file: 'a.mp3', title: 'A' }, { file: 'ad.mp3', ident: true }] })],
  ['a gain below 1', like({ gain: 0.5 })],
  ['news off', like({ news: false })],
]

for (const [name, manifest] of REFUSED) {
  test(`refused: ${name}`, () => {
    const faults = checkManifest(asFormState(manifest))
    assert.ok(faults.length > 0, `the page would have offered to build this: ${JSON.stringify(manifest)}`)
  })
}

for (const [name, manifest] of ACCEPTED) {
  test(`accepted: ${name}`, () => {
    const faults = checkManifest(asFormState(manifest))
    assert.deepEqual(faults, [], `the page refused a manifest the plugin takes: ${JSON.stringify(faults)}`)
  })
}

test('a manifest the page writes reads back the same', () => {
  const state = asFormState(GOOD)
  const written = buildManifest(state)
  assert.equal(written.name, GOOD.name)
  assert.equal(written.displayName, GOOD.displayName)
  assert.equal(written.icon, GOOD.icon)
  assert.equal(written.atlas, GOOD.atlas)
  assert.equal(written.news, true)
  assert.deepEqual(written.tracks, GOOD.tracks.map((t) => ({ file: t.file, title: t.title })))
  assert.deepEqual(checkManifest(asFormState(written)), [])
})

test('a track with both a file and a stream keeps the stream', () => {
  // The plugin refuses a track with both, so opening one keeps the stream and drops the file.
  const state = asFormState(like({ tracks: [{ url: 'https://h/s.mp3', file: 'a.mp3' }] }))
  state.tracks[0].file = 'a.mp3'
  const written = buildManifest(state)
  assert.deepEqual(written.tracks, [{ url: 'https://h/s.mp3' }])
})

test('a stream keeps its url and nothing else', () => {
  const written = buildManifest(asFormState(like({ tracks: [{ url: 'https://h/s.mp3' }] })))
  assert.deepEqual(written.tracks, [{ url: 'https://h/s.mp3' }])
})

test('an ident is written without a title', () => {
  const written = buildManifest(asFormState(like({ tracks: [{ file: 'a.mp3', title: 'A' }, { file: 'ad.mp3', title: 'x', ident: true }] })))
  assert.deepEqual(written.tracks, [{ file: 'a.mp3', title: 'A' }, { file: 'ad.mp3', ident: true }])
})
