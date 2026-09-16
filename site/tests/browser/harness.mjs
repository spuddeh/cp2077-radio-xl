/**
 * Drives the built page in headless Chrome over the DevTools protocol, with no test-only code in the
 * page itself. Serves `dist/` with vite preview, so what is tested is what is deployed.
 *
 * Chrome is found through CHROME, then the usual install paths. Without one the tests skip: a
 * contributor with no Chrome still gets `npm test`.
 */
import { spawn } from 'node:child_process'
import { existsSync } from 'node:fs'
import { once } from 'node:events'
import { fileURLToPath } from 'node:url'

const CHROME_PATHS = [
  process.env.CHROME,
  '/usr/bin/google-chrome',
  '/usr/bin/google-chrome-stable',
  '/usr/bin/chromium-browser',
  '/usr/bin/chromium',
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
]

export function findChrome() {
  return CHROME_PATHS.find((p) => p && existsSync(p)) ?? null
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

async function waitFor(check, { timeout = 30000, step = 250 } = {}) {
  const until = Date.now() + timeout
  for (;;) {
    const value = await check()
    if (value) return value
    if (Date.now() > until) throw new Error('timed out waiting for the page')
    await sleep(step)
  }
}

/** vite preview on its own port, ready once it answers. */
export async function serve(port) {
  const npm = process.platform === 'win32' ? 'npm.cmd' : 'npm'
  const server = spawn(npm, ['run', 'preview', '--', '--port', String(port), '--strictPort'], {
    cwd: fileURLToPath(new URL('../..', import.meta.url)),
    stdio: 'ignore',
    shell: process.platform === 'win32',
  })
  const base = `http://localhost:${port}/cp2077-radio-xl/`
  await waitFor(async () => {
    try {
      return (await fetch(base)).ok
    } catch {
      return false
    }
  })
  return { base, stop: () => server.kill() }
}

/** A page under Chrome, with the few protocol calls these tests need. */
export async function openPage(chrome, url, port) {
  const browser = spawn(chrome, [
    '--headless=new',
    '--disable-gpu',
    `--remote-debugging-port=${port}`,
    '--remote-allow-origins=*',
    `--user-data-dir=${process.env.TEMP ?? '/tmp'}/radioxl-page-test-${port}`,
    'about:blank',
  ], { stdio: 'ignore' })

  const targets = await waitFor(async () => {
    try {
      return await (await fetch(`http://127.0.0.1:${port}/json`)).json()
    } catch {
      return null
    }
  })
  const target = targets.find((t) => t.type === 'page')
  const socket = new WebSocket(target.webSocketDebuggerUrl)
  await once(socket, 'open')

  let id = 0
  const pending = new Map()
  socket.addEventListener('message', (event) => {
    const message = JSON.parse(event.data)
    const settle = pending.get(message.id)
    if (settle) {
      pending.delete(message.id)
      settle(message.result ?? message)
    }
  })
  const call = (method, params = {}) =>
    new Promise((done) => {
      id += 1
      pending.set(id, done)
      socket.send(JSON.stringify({ id, method, params }))
    })

  const evaluate = async (expression) => {
    const result = await call('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true })
    if (result.exceptionDetails) throw new Error(`page threw: ${JSON.stringify(result.exceptionDetails).slice(0, 400)}`)
    return result.result?.value
  }

  await call('DOM.enable')
  await call('Emulation.setDeviceMetricsOverride', { width: 1440, height: 1200, deviceScaleFactor: 1, mobile: false })
  await call('Page.navigate', { url })
  await waitFor(() => evaluate("!!document.querySelector('.tabs button')"))
  // The save picker would open a real dialog; the download is caught instead of written to disk.
  await evaluate(`
    window.showSaveFilePicker = undefined
    window.__errors = []
    addEventListener('unhandledrejection', (e) => __errors.push(String(e.reason?.stack ?? e.reason)))
    const make = URL.createObjectURL
    URL.createObjectURL = function (blob) { if (blob instanceof Blob && !(blob instanceof File)) window.__zip = blob; return make.call(URL, blob) }
    const click = HTMLAnchorElement.prototype.click
    HTMLAnchorElement.prototype.click = function () { if (this.download) { window.__download = this.download; return } return click.call(this) }
    1
  `)

  return {
    evaluate,
    waitFor: (expression, options) => waitFor(() => evaluate(expression), options),
    /** Hands a real file on disk to a file input, as a person picking it would. */
    async setFile(selector, path) {
      const node = await call('Runtime.evaluate', { expression: `document.querySelector(${JSON.stringify(selector)})` })
      await call('DOM.setFileInputFiles', { files: [path], objectId: node.result.objectId })
    },
    errors: () => evaluate('JSON.stringify(window.__errors)').then(JSON.parse),
    close: () => browser.kill(),
  }
}
