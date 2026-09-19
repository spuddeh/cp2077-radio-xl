/**
 * The page in a browser, end to end: build a station with an icon, open the zip it wrote, convert a
 * RadioExt station, and add a stream. What these cover that the unit tests cannot is the parts that
 * only exist in a browser - the icon writer's pixels, the zip, and reading an archive back.
 *
 * Run with `npm run test:browser`. Skips when no Chrome is installed.
 */
import { strict as assert } from 'node:assert'
import { after, before, describe, test } from 'node:test'

import { findChrome, openPage, serve } from './harness.mjs'
import { writeFixtures } from './fixtures.mjs'

const chrome = findChrome()
const PORT = 4319
const DEBUG_PORT = 9421

describe('the station builder in a browser', { skip: chrome ? false : 'no Chrome found (set CHROME)' }, () => {
  let server
  let page
  let files

  before(async () => {
    files = await writeFixtures()
    server = await serve(PORT)
    page = await openPage(chrome, server.base, DEBUG_PORT)
  })

  after(() => {
    page?.close()
    server?.stop()
  })

  /** The form's text inputs, in the order the page lays them out. */
  const setField = (index, value) =>
    page.evaluate(`(() => {
      const el = [...document.querySelectorAll('.form input[type=text]')][${index}]
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(el, ${JSON.stringify(value)})
      el.dispatchEvent(new Event('input', { bubbles: true }))
      return el.value
    })()`)

  const build = async () => {
    // A build that has just finished still holds the progress panel, and the button with it.
    await page.waitFor("!document.querySelector('.build-overlay')")
    await page.evaluate(`(() => {
      window.__zip = undefined
      const button = [...document.querySelectorAll('button.hint')].find((b) => b.textContent.includes('Build .zip'))
      if (button.disabled) throw new Error('Build .zip is disabled: ' + document.querySelector('.footer-state').textContent)
      button.click()
      return 1
    })()`)
    await page.waitFor('!!window.__zip')
    return page.evaluate(`(async () => {
      const bytes = new Uint8Array(await window.__zip.arrayBuffer())
      let binary = ''
      for (let i = 0; i < bytes.length; i += 32768) binary += String.fromCharCode(...bytes.subarray(i, i + 32768))
      return btoa(binary)
    })()`)
  }

  /** The entry names of a stored zip, read from its central directory. */
  const zipNames = (base64) => {
    const data = Buffer.from(base64, 'base64')
    const names = []
    for (let i = 0; i < data.length - 4; i++) {
      if (data.readUInt32LE(i) !== 0x02014b50) continue
      const length = data.readUInt16LE(i + 28)
      names.push(data.toString('utf8', i + 46, i + 46 + length))
    }
    return names
  }

  test('builds a station whose icon archive it wrote itself', async () => {
    await setField(0, '99.7')
    await setField(1, 'Browser Test')
    await page.evaluate(`(async () => {
      const modes = document.querySelectorAll('.stepper .prev')
      for (let i = 0; i < 2; i++) { modes[0].click(); await new Promise((r) => setTimeout(r, 150)) }
      return 1
    })()`)
    await page.setFile('.file-pick input[type=file]', files.icon)
    await page.setFile('input[accept=".wav,.mp3,.ogg,.flac"]', files.song)
    await page.waitFor("document.querySelectorAll('.track').length === 1")

    const state = await page.evaluate(`(() => document.querySelector('.footer-state').textContent + ' | ' + [...document.querySelectorAll('.row-note.fault')].map((e) => e.textContent).join(' ~ '))()`)
    assert.match(state, /is ready/, state)

    const names = zipNames(await build())
    assert.deepEqual(names, [
      'red4ext/plugins/RadioXL/stations/BrowserTest/station.json',
      'red4ext/plugins/RadioXL/stations/BrowserTest/audio/A Song.mp3',
      'archive/pc/mod/BrowserTest.archive',
    ])
    assert.equal(await page.evaluate('window.__download'), 'BrowserTest - RadioXL.zip')
    assert.deepEqual(await page.errors(), [])
  })

  test('reads its own icon back out of the zip it wrote', async () => {
    await page.evaluate(`(async () => {
      const file = new File([window.__zip], 'BrowserTest - RadioXL.zip', { type: 'application/zip' })
      const transfer = new DataTransfer()
      transfer.items.add(file)
      const input = document.querySelector('.open-station input[type=file]')
      input.files = transfer.files
      input.dispatchEvent(new Event('change', { bubbles: true }))
      return 1
    })()`)
    await page.waitFor(`(() => {
      const replace = [...document.querySelectorAll('button')].find((b) => b.textContent.trim() === 'Replace')
      if (replace) replace.click()
      return !replace
    })()`)
    await page.waitFor("!!document.querySelector('.rp-image [aria-label]')")

    const icon = await page.evaluate(`(() => {
      const image = document.querySelector('.rp-image [aria-label]')
      return JSON.stringify({ label: image.getAttribute('aria-label'), style: image.getAttribute('style') ?? '' })
    })()`)
    const { label, style } = JSON.parse(icon)
    assert.equal(label, 'Station icon', 'the preview should show the icon read from the archive')
    assert.match(style, /blob:/, 'the icon should come from the archive, not from a file the page still holds')
    assert.deepEqual(await page.errors(), [])
  })

  test('measures a file and levels it, and off auto level the slider is yours', async () => {
    // A 997 Hz sine at -20 dBFS: -20.0 LUFS, peak -20.0 dBFS. Against the -11.1 LUFS target that
    // wants +8.9 dB, which the peak allows, so the level is 2.79. Auto level is on by default, so
    // the measurement sets it and the slider is read-only.
    await page.setFile('input[accept=".wav,.mp3,.ogg,.flac"]', files.tone)
    await page.waitFor("document.querySelectorAll('.track').length === 2")
    await page.waitFor(`[...document.querySelectorAll('.track-reading')].some((e) => e.textContent.includes('LUFS'))`)

    const readings = JSON.parse(await page.evaluate("JSON.stringify([...document.querySelectorAll('.track-reading')].map((e) => e.textContent))"))
    const tone = readings.find((r) => r.includes('LUFS'))
    assert.match(tone, /^-(19\.9|20\.0|20\.1) LUFS, peak -(19\.9|20\.0|20\.1) dBFS\./, tone)
    assert.match(tone, /Levelled to 279% \(\+8\.9 dB\)/, tone)
    // The stand-in mp3 is not audio the browser can decode, and says so without a fault.
    assert.ok(readings.some((r) => r.includes('could not read the file')), JSON.stringify(readings))
    const state = await page.evaluate("document.querySelector('.footer-state').textContent")
    assert.match(state, /is ready/, state)
    let manifest = JSON.parse(await page.evaluate("document.querySelector('.json pre').textContent"))
    assert.deepEqual(manifest.tracks.map((t) => t.gain), [undefined, 2.79], JSON.stringify(manifest.tracks))
    assert.equal(await page.evaluate("[...document.querySelectorAll('.track-level input[type=range]')][1].disabled"), true)
    assert.equal(await page.evaluate("!!document.querySelector('.use-suggested')"), false)

    // Off: the slider keeps its value and comes alive; moved by hand, the suggestion is offered again.
    await page.evaluate("document.querySelector('.auto-level .off').click()")
    await page.waitFor("[...document.querySelectorAll('.track-level input[type=range]')][1].disabled === false")
    manifest = JSON.parse(await page.evaluate("document.querySelector('.json pre').textContent"))
    assert.equal(manifest.tracks[1].gain, 2.79, 'turning auto level off keeps the level')
    await page.waitFor(`[...document.querySelectorAll('.track-reading')].some((e) => e.textContent.includes('At the suggested level'))`)
    await page.evaluate(`(() => {
      const slider = [...document.querySelectorAll('.track-level input[type=range]')][1]
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(slider, '1')
      slider.dispatchEvent(new Event('input', { bubbles: true }))
      return 1
    })()`)
    await page.waitFor(`[...document.querySelectorAll('.track-reading')].some((e) => e.textContent.includes('Suggested 279%'))`)
    await page.evaluate("document.querySelector('.use-suggested').click()")
    await page.waitFor(`[...document.querySelectorAll('.track-reading')].some((e) => e.textContent.includes('At the suggested level'))`)
    assert.equal(await page.evaluate("document.querySelector('.use-suggested').disabled"), true)

    // Back on: every measured track returns to its suggestion and the button goes away.
    await page.evaluate(`(() => {
      const slider = [...document.querySelectorAll('.track-level input[type=range]')][1]
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(slider, '0.5')
      slider.dispatchEvent(new Event('input', { bubbles: true }))
      document.querySelector('.auto-level .on').click()
      return 1
    })()`)
    await page.waitFor(`[...document.querySelectorAll('.track-reading')].some((e) => e.textContent.includes('Levelled to 279%'))`)
    assert.equal(await page.evaluate("!!document.querySelector('.use-suggested')"), false)
    assert.match(await page.evaluate("document.querySelector('.builder-version').textContent"), /^Station builder \d+\.\d+\.\d+$/)
    assert.deepEqual(await page.errors(), [])
  })

  test('converts a RadioExt station, order and archive included', async () => {
    await page.evaluate(`(async () => {
      [...document.querySelectorAll('.tabs button')].find((b) => b.textContent.includes('RadioExt')).click()
      return 1
    })()`)
    await page.waitFor("!!document.querySelector('.open-station input[type=file]')")
    await page.setFile('.open-station input[type=file]', files.radioExt)
    await page.waitFor(`(() => {
      const replace = [...document.querySelectorAll('button')].find((b) => b.textContent.trim() === 'Replace')
      if (replace) replace.click()
      return !replace && !!document.querySelector('.track')
    })()`)

    const read = JSON.parse(
      await page.evaluate(`(() => JSON.stringify({
        fields: [...document.querySelectorAll('.form input[type=text]')].slice(0, 5).map((i) => i.value),
        tracks: [...document.querySelectorAll('.track-title')].map((e) => e.textContent),
        notes: [...document.querySelectorAll('.open-notes li')].map((e) => e.textContent),
        manifest: document.querySelector('.json pre').textContent,
      }))()`),
    )
    assert.equal(read.fields[0], '88.8')
    assert.equal(read.fields[1], 'Converted Station')
    assert.equal(read.fields[2], 'radio_station_converted_station')
    assert.equal(read.fields[3], 'teststation\\gui\\icons.inkatlas')
    assert.equal(read.fields[4], 'icon_part')
    assert.ok(
      read.tracks[0].includes('Second') && read.tracks[1].includes('First'),
      `RadioExt's own order decides the tracks, got ${JSON.stringify(read.tracks)}`,
    )
    assert.ok(
      read.notes.some((n) => n.includes("Volume 2.5 came from RadioExt's own player")),
      `the volume note is missing: ${JSON.stringify(read.notes)}`,
    )
    assert.equal(read.manifest.includes('"gain": 2.5'), true, `RadioExt's volume should come across as written: ${read.manifest}`)
    assert.deepEqual(zipNames(await build()).filter((n) => n.endsWith('.archive')), ['archive/pc/mod/test_station.archive'])
    assert.deepEqual(await page.errors(), [])
  })

  test('an image chosen after a RadioExt import replaces the imported atlas path (#48)', async () => {
    await page.evaluate(`[...document.querySelectorAll('.tabs button')].find((b) => b.textContent.includes('RadioExt')).click(); 1`)
    await page.waitFor("!!document.querySelector('.open-station input[type=file]')")
    await page.setFile('.open-station input[type=file]', files.radioExtBase)
    await page.waitFor(`(() => {
      const replace = [...document.querySelectorAll('button')].find((b) => b.textContent.trim() === 'Replace')
      if (replace) replace.click()
      return !replace && [...document.querySelectorAll('.form input[type=text]')].some((i) => i.value.startsWith('base\\\\'))
    })()`)
    // Own atlas is one step past From an image on the icon stepper.
    await page.evaluate(`(async () => {
      document.querySelectorAll('.stepper .prev')[0].click()
      await new Promise((r) => setTimeout(r, 150))
      return 1
    })()`)
    await page.setFile('.file-pick input[type=file]', files.icon)
    await page.waitFor("document.querySelector('.footer-state').textContent.includes('is ready')")
    const fields = JSON.parse(await page.evaluate("JSON.stringify([...document.querySelectorAll('.form input[type=text]')].map((i) => i.value))"))
    assert.ok(fields.some((v) => v === 'radio_station_dock_station\\gui\\radio_station_dock_station.inkatlas'), `the atlas should be the station's own: ${JSON.stringify(fields)}`)
    assert.ok(!fields.some((v) => v.startsWith('base\\')), `the imported base\\ path should be gone: ${JSON.stringify(fields)}`)
    assert.deepEqual(zipNames(await build()).filter((n) => n.endsWith('.archive')), ['archive/pc/mod/DockStation.archive'])
    assert.deepEqual(await page.errors(), [])
  })

  test('a stream station is one url track, and says what the player must allow', async () => {
    await page.evaluate(`(async () => {
      const remove = document.querySelector('.remove-all')
      remove.click(); remove.click()
      await new Promise((r) => setTimeout(r, 200))
      const url = document.querySelector('#stream-url')
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(url, 'https://stream.example.com/live.mp3')
      url.dispatchEvent(new Event('input', { bubbles: true }))
      await new Promise((r) => setTimeout(r, 200))
      document.querySelector('.stream-button').click()
      return 1
    })()`)
    await page.waitFor("document.querySelectorAll('.track').length === 1")

    const manifest = JSON.parse(await page.evaluate("document.querySelector('.json pre').textContent"))
    assert.deepEqual(manifest.tracks, [{ url: 'https://stream.example.com/live.mp3' }])
    const notices = JSON.parse(await page.evaluate("JSON.stringify([...document.querySelectorAll('.row-note.notice')].map((e) => e.textContent))"))
    assert.ok(
      notices.some((n) => n.includes('allowedHost = stream.example.com')),
      `the AudioXL.ini warning should name the host: ${JSON.stringify(notices)}`,
    )

    // A warning row is a flex line of the icon and ONE block of text. Text left loose in it becomes a
    // flex item per word, which is what broke the page when this warning was first written.
    const layout = JSON.parse(
      await page.evaluate(`(() => {
        const form = document.querySelector('.form').getBoundingClientRect()
        const notice = [...document.querySelectorAll('.row-note.notice')].find((e) => e.textContent.includes('AudioXL.ini'))
        const box = notice.getBoundingClientRect()
        return JSON.stringify({
          formWidth: Math.round(form.width),
          noticeWidth: Math.round(box.width),
          items: notice.childElementCount,
          looseText: [...notice.childNodes].filter((n) => n.nodeType === 3 && n.textContent.trim()).length,
          overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
        })
      })()`),
    )
    assert.equal(layout.noticeWidth, layout.formWidth, 'the warning should fill the form column, no wider and no narrower')
    assert.equal(layout.items, 2, 'a warning row holds the icon and one block of text')
    assert.equal(layout.looseText, 0, 'text loose in the row becomes a flex item per word')
    assert.equal(layout.overflow, 0, 'the page should not scroll sideways')
    assert.deepEqual(await page.errors(), [])
  })
})
