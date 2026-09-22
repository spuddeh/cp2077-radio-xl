/**
 * A file the browser cannot open reaches script as a bare `TypeError`, which names nothing the
 * person can act on. The advice does, and a long track name is what it leads with.
 *
 * Run with `npm test`.
 */
import { strict as assert } from 'node:assert'
import { test } from 'node:test'

import { readFailureAdvice } from '../src/build.ts'

const long =
  "No Love In The House Of Gold - overpopulation at the end of everything is less of a worry, haha ('a letter to you' from mother 3).mp3"

test('a long name is told its length and the 260-character limit', () => {
  const advice = readFailureAdvice(long)
  assert.match(advice, new RegExp(String(long.length)))
  assert.match(advice, /260/)
  assert.match(advice, /Shorten the name/)
})

test('a short name is told the file is gone, with no talk of length', () => {
  const advice = readFailureAdvice('audio/track.mp3')
  assert.match(advice, /moved, renamed or deleted/)
  assert.doesNotMatch(advice, /260/)
})
