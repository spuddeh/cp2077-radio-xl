/**
 * The store's rule for auto level on open: a station that carries a track gain was levelled on
 * purpose, so it opens with auto level off; one without opens with it on.
 *
 * Run with `npm test`.
 */
import { strict as assert } from 'node:assert'
import { test } from 'node:test'

import { useStation } from '../src/store.ts'
import type { ImportedStation } from '../src/importStation.ts'

function station(tracks: ImportedStation['tracks']): ImportedStation {
  return {
    folder: 'Test',
    frequency: '90.5',
    stationName: 'Test',
    cname: 'radio_station_test',
    news: false,
    gain: 1,
    iconMode: 'glyph',
    iconChoice: 'UIIcon.RadioDowntempo',
    iconRecord: '',
    iconPart: '',
    iconAtlas: '',
    iconImage: null,
    iconImageSize: null,
    iconArchiveUnreadable: false,
    tracks,
    extras: [],
    notes: [],
  }
}

test('auto level is on to begin with, and a new file arrives at 100%', () => {
  assert.equal(useStation.getState().autoLevel, true)
  useStation.getState().addFiles([new File([new Uint8Array(4)], 'a.mp3')])
  assert.deepEqual(useStation.getState().tracks.map((t) => t.gain), [1])
})

test('a station with no track gain opens with auto level on', () => {
  useStation.getState().set({ autoLevel: false })
  useStation.getState().openStation(station([{ file: 'a.mp3', title: 'A', ident: false, gain: 1 }]))
  assert.equal(useStation.getState().autoLevel, true)
})

test('a station with a track gain opens with auto level off, the gain kept', () => {
  useStation.getState().openStation(station([{ file: 'a.mp3', title: 'A', ident: false, gain: 1 }, { file: 'b.mp3', title: 'B', ident: false, gain: 0.8 }]))
  assert.equal(useStation.getState().autoLevel, false)
  assert.deepEqual(useStation.getState().tracks.map((t) => t.gain), [1, 0.8])
})

test('updateTracks patches only the tracks picked', () => {
  useStation.getState().updateTracks((t) => t.file === 'b.mp3', () => ({ gain: 2 }))
  assert.deepEqual(useStation.getState().tracks.map((t) => t.gain), [1, 2])
})
