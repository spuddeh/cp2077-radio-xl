/**
 * Where a stream leads. AudioXL checks every host a stream passes through against AudioXL.ini, so
 * a stream that redirects needs an `allowedHost` line for the host it lands on as well.
 *
 * The page follows the stream itself: `fetch` resolves on the response headers, `response.url` is
 * the address it ended at, and the request is then cancelled, since a stream never ends. That works
 * only for a stream that allows cross-origin reads, and it sees the first and the last host of a
 * chain, not any between them.
 */

export interface StreamCheck {
  /** Every host to allow, the stream's own first. */
  hosts: string[]
  /** False when the page could not follow the stream: `why` says what stopped it. */
  checked: boolean
  why?: 'mixed' | 'blocked' | 'timeout'
}

export function hostOf(url: string): string {
  try {
    return new URL(url).hostname
  } catch {
    return ''
  }
}

/** The AudioXL.ini lines a player needs for these hosts. */
export function iniLines(hosts: string[]): string {
  return ['allowHttpConnections = true', ...hosts.map((h) => `allowedHost = ${h}`)].join('\n')
}

export async function followStream(url: string, pageProtocol: string, timeoutMs = 8000): Promise<StreamCheck> {
  const first = hostOf(url)
  // An https page may not fetch an http stream at all.
  if (pageProtocol === 'https:' && /^http:/i.test(url)) return { hosts: [first], checked: false, why: 'mixed' }
  const controller = new AbortController()
  let timedOut = false
  const timer = setTimeout(() => {
    timedOut = true
    controller.abort()
  }, timeoutMs)
  try {
    const response = await fetch(url, { signal: controller.signal })
    const last = hostOf(response.url)
    controller.abort()
    const hosts = last && last !== first ? [first, last] : [first]
    return { hosts, checked: true }
  } catch {
    return { hosts: [first], checked: false, why: timedOut ? 'timeout' : 'blocked' }
  } finally {
    clearTimeout(timer)
  }
}
