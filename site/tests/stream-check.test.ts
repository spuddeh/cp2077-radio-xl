/**
 * Following a stream to every host AudioXL.ini must allow (#55). `fetch` is replaced, so these run
 * without a network: the page's own check needs a stream that allows cross-origin reads.
 *
 * Run with `npm test`.
 */
import { strict as assert } from 'node:assert'
import { afterEach, test } from 'node:test'

import { followStream, iniLines } from '../src/streamCheck.ts'

const realFetch = globalThis.fetch
afterEach(() => {
  globalThis.fetch = realFetch
})

/** A fetch that answers with a response whose final address is `landsOn`. */
function fetchLanding(landsOn: string): typeof fetch {
  return (async () => ({ url: landsOn }) as Response) as typeof fetch
}

test('a stream that redirects lists both hosts, its own first', async () => {
  globalThis.fetch = fetchLanding('https://regiocast.streamabc.net/regc-radiobobdeathmetal')
  const check = await followStream('https://streams.radiobob.de/deathmetal/mp3-192/streams.radiobob.de/', 'https:')
  assert.deepEqual(check, { hosts: ['streams.radiobob.de', 'regiocast.streamabc.net'], checked: true })
})

test('a stream that stays put lists its one host', async () => {
  globalThis.fetch = fetchLanding('https://stream.example.com/live.mp3')
  const check = await followStream('https://stream.example.com/live.mp3', 'https:')
  assert.deepEqual(check, { hosts: ['stream.example.com'], checked: true })
})

test('a stream the page cannot read is reported unchecked, with its own host', async () => {
  globalThis.fetch = (async () => {
    throw new TypeError('Failed to fetch')
  }) as typeof fetch
  const check = await followStream('https://nocors.example.com/live', 'https:')
  assert.deepEqual(check, { hosts: ['nocors.example.com'], checked: false, why: 'blocked' })
})

test('an http stream is not fetched from an https page', async () => {
  let called = false
  globalThis.fetch = (async () => {
    called = true
    return { url: '' } as Response
  }) as typeof fetch
  const check = await followStream('http://s1.yumicoradio.net:8000/stream', 'https:')
  assert.deepEqual(check, { hosts: ['s1.yumicoradio.net'], checked: false, why: 'mixed' })
  assert.equal(called, false)
})

test('a stream that never answers is given up on', async () => {
  globalThis.fetch = ((_url: string, init?: RequestInit) =>
    new Promise((_resolve, reject) => init?.signal?.addEventListener('abort', () => reject(new Error('aborted'))))) as typeof fetch
  const check = await followStream('https://slow.example.com/live', 'https:', 20)
  assert.deepEqual(check, { hosts: ['slow.example.com'], checked: false, why: 'timeout' })
})

test('the ini lines switch streams on and allow every host', () => {
  assert.equal(
    iniLines(['streams.radiobob.de', 'regiocast.streamabc.net']),
    'allowHttpConnections = true\nallowedHost = streams.radiobob.de\nallowedHost = regiocast.streamabc.net',
  )
})
