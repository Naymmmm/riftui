// Reference API, to run behind an HTTPS reverse proxy. No payment/account service included.
import { createServer } from 'node:http'
import { readFile, realpath } from 'node:fs/promises'
import { resolve, sep } from 'node:path'
import { timingSafeEqual } from 'node:crypto'
import { pathToFileURL } from 'node:url'
export function configServer({ directory, authorize, origin } = {}) {
  if (!directory || typeof authorize !== 'function') throw Error('A directory and authorization callback are required')
  return createServer(async (req, res) => {
    const headers = { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', Vary: 'Origin' }
    if (origin && req.headers.origin === origin) Object.assign(headers, { 'Access-Control-Allow-Origin': origin, 'Access-Control-Allow-Headers': 'Authorization', 'Access-Control-Allow-Methods': 'GET, OPTIONS' })
    const send = (status, value) => { res.writeHead(status, headers); res.end(JSON.stringify(value)) }
    if (req.method === 'OPTIONS') { res.writeHead(204, headers); res.end(); return }
    const path = new URL(req.url, 'http://localhost').pathname
    const match = /^\/v1\/configs\/([A-Za-z0-9_-]{1,80})$/.exec(path)
    if (req.method !== 'GET' || !match) { send(404, { error: 'Not found' }); return }
    try {
      const token = /^Bearer (.+)$/.exec(req.headers.authorization || '')?.[1]
      // Replace authorize with your entitlement lookup: token + requested config ID.
      if (!await authorize(token, match[1])) { send(401, { error: 'Access denied' }); return }
      const root = await realpath(directory)
      const file = await realpath(resolve(root, match[1] + '.json'))
      if (!file.startsWith(root + sep)) { send(404, { error: 'Not found' }); return }
      const body = await readFile(file, 'utf8')
      if (Buffer.byteLength(body) > 512 * 1024) { send(413, { error: 'Config too large' }); return }
      const payload = JSON.parse(body)
      send(200, payload)
    } catch { send(404, { error: 'Config unavailable' }) }
  })
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const expected = process.env.RIFT_CONFIG_TOKEN
  if (!expected) throw Error('Set RIFT_CONFIG_TOKEN; the reference server never defaults to public access')
  const server = configServer({
    directory: resolve(process.env.RIFT_CONFIG_DIR || 'private-configs'),
    origin: process.env.RIFT_CONFIG_ORIGIN,
    authorize(token) {
      if (typeof token !== 'string') return false
      const a = Buffer.from(token), b = Buffer.from(expected)
      return a.length === b.length && timingSafeEqual(a, b)
    },
  })
  server.listen(Number(process.env.PORT || 8788), '127.0.0.1', () => console.log('Config API listening on loopback; expose it through HTTPS'))
}
