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

import { buildManifest, checkManifest, displayName, type ManifestInput } from '../src/manifest.ts'
import type { Track } from '../src/store.ts'

/** The description as importStation reads it: the en-us text in the form, the other languages carried. */
function descriptionOf(raw: unknown): { description: string; descriptionLanguages: Record<string, string> } {
  if (typeof raw === 'string') return { description: raw, descriptionLanguages: {} }
  const languages: Record<string, string> = {}
  let description = ''
  if (raw && typeof raw === 'object') {
    for (const [code, text] of Object.entries(raw as Record<string, unknown>)) {
      if (typeof text !== 'string') continue
      if (code === 'en-us') description = text
      else languages[code] = text
    }
  }
  return { description, descriptionLanguages: languages }
}

/** Form state as an opened station would leave it, from a manifest's own JSON. */
function asFormState(manifest: Record<string, unknown>): ManifestInput {
  const display = typeof manifest.displayName === 'string' ? manifest.displayName : ''
  const parts = display.match(/^\s*(\d{2,3}(?:\.\d+)?)\s*(.*)$/)
  const field = typeof manifest.frequency === 'number' ? manifest.frequency : null
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
      gain: typeof t.gain === 'number' ? t.gain : 1,
      // A track with a file stands for one whose audio was found beside the manifest.
      source: url ? undefined : new Blob([new Uint8Array(4)]),
    }
  })
  return {
    frequency: field !== null ? String(field) : parts ? parts[1] : '',
    showFrequency: manifest.showFrequency !== false,
    stationName: parts ? parts[2].trim() : display,
    cname: typeof manifest.name === 'string' ? manifest.name : '',
    news: manifest.news === true,
    gain: typeof manifest.gain === 'number' ? manifest.gain : 1,
    ...descriptionOf(manifest.description),
    extensions:
      manifest.extensions && typeof manifest.extensions === 'object' ? (manifest.extensions as Record<string, unknown>) : null,
    iconMode: atlas ? 'atlas' : icon ? 'record' : 'glyph',
    iconChoice: icon && !atlas ? 'other' : 'UIIcon.RadioDowntempo',
    iconRecord: icon && !atlas ? icon : '',
    iconPart: atlas ? icon : '',
    iconAtlas: atlas,
    iconImage: null,
    iconImageSize: null,
    iconImageHasPixels: true,
    iconArchive: null,
    iconArchiveHasAtlas: null,
    tracks,
  }
}

const GOOD = {
  name: 'radio_station_20_tool',
  frequency: 104.9,
  displayName: 'Tool FM',
  icon: 'tool_fm',
  atlas: 'toolfm\\gui\\tool_fm.inkatlas',
  news: true,
  tracks: [
    { file: 'audio/Tool - Vicarious.mp3', title: 'Tool - Vicarious' },
    { file: 'audio/Tool - Jambi.mp3', title: 'Tool - Jambi' },
  ],
}

/** A copy of the good manifest with one thing changed; a key set to undefined is left out. */
function like(patch: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = { ...structuredClone(GOOD), ...patch }
  for (const key of Object.keys(out)) if (out[key] === undefined) delete out[key]
  return out
}

const REFUSED: [name: string, manifest: Record<string, unknown>][] = [
  ['name missing', like({ name: '' })],
  ['name with a space', like({ name: 'my station' })],
  ['no frequency anywhere', like({ frequency: undefined, displayName: 'Tool FM' })],
  ['frequency of zero', like({ frequency: 0 })],
  ['no name', like({ displayName: undefined })],
  ['a name ending with a number', like({ displayName: 'Tool FM 104.9' })],
  ['a name containing the frequency', like({ displayName: 'Tool 104.9 FM' })],
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
  ['a frequency with two decimals', like({ frequency: 88.85 })],
  ["a name starting with a band's number", like({ displayName: '30H!3 Radio' })],
  ['an icon record and no atlas', like({ icon: 'UIIcon.RadioHipHop', atlas: '' })],
  ['no icon at all', like({ icon: '', atlas: '' })],
  ['a stream as the one track', like({ tracks: [{ url: 'https://ice1.somafm.com/groovesalad-128-mp3' }] })],
  ['idents beside songs', like({ tracks: [{ file: 'a.mp3', title: 'A' }, { file: 'ad.mp3', ident: true }] })],
  ['a gain below 1', like({ gain: 0.5 })],
  ['a gain above 1', like({ gain: 2.5 })],
  ['a track gain', like({ tracks: [{ file: 'a.mp3', gain: 0.8 }, { file: 'b.mp3', gain: 2.5 }] })],
  ['a stream with a gain', like({ tracks: [{ url: 'https://h/s', gain: 0.7 }] })],
  ['news off', like({ news: false })],
  ['the frequency hidden from the label', like({ showFrequency: false })],
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
  assert.equal(written.frequency, GOOD.frequency)
  assert.equal(written.displayName, GOOD.displayName)
  assert.equal(written.icon, GOOD.icon)
  assert.equal(written.atlas, GOOD.atlas)
  assert.equal(written.news, true)
  assert.deepEqual(written.tracks, GOOD.tracks.map((t) => ({ file: t.file, title: t.title })))
  assert.deepEqual(checkManifest(asFormState(written)), [])
})

test('an Own atlas archive that does not list the atlas path is a fault; one that does is not', () => {
  const state = asFormState(GOOD)
  state.iconArchive = { name: 'x.archive' }
  state.iconArchiveHasAtlas = false
  assert.ok(checkManifest(state).some((f) => f.message.includes('does not hold')))
  state.iconArchiveHasAtlas = null
  assert.ok(checkManifest(state).some((f) => f.message.includes('not a game archive')))
  state.iconArchiveHasAtlas = true
  assert.deepEqual(checkManifest(state), [])
})

test('showFrequency is written only when off, and the name rules still hold', () => {
  const hidden = asFormState(like({ showFrequency: false }))
  assert.equal(buildManifest(hidden).showFrequency, false)
  assert.equal(displayName(hidden), 'Tool FM')
  assert.equal(buildManifest(asFormState(GOOD)).showFrequency, undefined)
  assert.equal(displayName(asFormState(GOOD)), '104.9 Tool FM')
  assert.ok(checkManifest(asFormState(like({ showFrequency: false, displayName: 'Tool FM 101.1' }))).length > 0, 'a hidden frequency does not let one into the name')
})

test('a track gain is written only when it is not 1, and reads back', () => {
  const state = asFormState(like({ tracks: [{ file: 'a.mp3', title: 'A', gain: 0.8 }, { file: 'b.mp3', title: 'B' }, { file: 'c.mp3', title: 'C', gain: 1.004 }] }))
  const written = buildManifest(state)
  assert.deepEqual(written.tracks, [{ file: 'a.mp3', title: 'A', gain: 0.8 }, { file: 'b.mp3', title: 'B' }, { file: 'c.mp3', title: 'C' }])
  const again = asFormState(written)
  assert.deepEqual(again.tracks.map((t) => t.gain), [0.8, 1, 1])
  assert.deepEqual(checkManifest(again), [])
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

// RadioXL refuses a name that starts with the frequency; opening such a station on the page moves
// the number into the field, so what the page writes back is a manifest RadioXL takes.
test('a 0.3.0 manifest opened on the page is written back with the field', () => {
  const written = buildManifest(asFormState(like({ frequency: undefined, displayName: '104.9 Tool FM' })))
  assert.equal(written.frequency, 104.9)
  assert.equal(written.displayName, 'Tool FM')
  assert.deepEqual(checkManifest(asFormState(written)), [])
})

test('a plain description is written as one text', () => {
  const written = buildManifest(asFormState(like({ description: 'Pirate signal out of Kabuki.' })))
  assert.equal(written.description, 'Pirate signal out of Kabuki.')
})

test('a description in several languages is written back with every language', () => {
  const description = { 'en-us': 'Pirate signal.', 'de-de': 'Piratensender.' }
  const written = buildManifest(asFormState(like({ description })))
  assert.deepEqual(written.description, description)
})

test('no description writes no key', () => {
  assert.equal('description' in buildManifest(asFormState(GOOD)), false)
})

// The plugin counts characters, not bytes, and leaves out a description past 1000.
test('a description past 1000 characters is a fault, and 1000 of them is not', () => {
  const fits = 'é'.repeat(1000)
  assert.deepEqual(checkManifest(asFormState(like({ description: fits }))), [])
  const faults = checkManifest(asFormState(like({ description: fits + '!' })))
  assert.deepEqual(faults.map((f) => f.field), ['description'])
})

test('extensions are written back unchanged', () => {
  const extensions = { NpcCarStereo: { weight: 2, districts: ['Watson'] } }
  const written = buildManifest(asFormState(like({ extensions })))
  assert.deepEqual(written.extensions, extensions)
})
