// Reference key gate for Rift:CreateAuth, to run behind an HTTPS reverse proxy.
// GET /v1/script with "Authorization: Bearer <key>" (and X-Rift-Hwid when SendHwid is on)
// answers 200 with the hub script as text, or a JSON { error } the auth card shows.
// No key store, payment or obfuscation included: plug yours into authorize and script.
import { createServer } from 'node:http'
import { readFile } from 'node:fs/promises'
import { resolve } from 'node:path'
import { timingSafeEqual } from 'node:crypto'
import { pathToFileURL } from 'node:url'
export function authServer({ authorize, script, limit = 10, window = 60_000, trustProxy = false } = {}) {
  if (typeof authorize !== 'function' || typeof script !== 'function') throw Error('authorize and script callbacks are required')
  const attempts = new Map()
  return createServer(async (req, res) => {
    const headers = { 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' }
    const send = (status, value, type = 'application/json') => {
      res.writeHead(status, { ...headers, 'Content-Type': type + '; charset=utf-8' })
      res.end(type === 'application/json' ? JSON.stringify(value) : value)
    }
    if (req.method !== 'GET' || new URL(req.url, 'http://localhost').pathname !== '/v1/script') { send(404, { error: 'Not found' }); return }
    // Per-client attempt budget, so keys can't be guessed quickly.
    const client = (trustProxy && String(req.headers['x-forwarded-for'] || '').split(',')[0].trim()) || req.socket.remoteAddress
    const now = Date.now()
    const recent = (attempts.get(client) || []).filter(t => now - t < window)
    if (recent.length >= limit) { send(429, { error: 'Too many attempts. Wait a minute, then try again.' }); return }
    recent.push(now)
    attempts.set(client, recent)
    const key = /^Bearer (.{1,512})$/.exec(req.headers.authorization || '')?.[1]
    const hwid = typeof req.headers['x-rift-hwid'] === 'string' ? req.headers['x-rift-hwid'].slice(0, 200) : undefined
    try {
      // authorize returns true, false, or a string explaining the refusal ("Key expired").
      const verdict = key ? await authorize(key, hwid) : false
      if (verdict !== true) { send(401, { error: typeof verdict === 'string' ? verdict : 'Invalid key.' }); return }
      send(200, await script(key, hwid), 'text/plain')
    } catch { send(500, { error: 'Server error' }) }
  })
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const keys = (process.env.RIFT_AUTH_KEYS || '').split(',').map(k => k.trim()).filter(Boolean)
  if (!keys.length) throw Error('Set RIFT_AUTH_KEYS to a comma-separated list; the reference server never defaults to open access')
  const file = resolve(process.env.RIFT_AUTH_SCRIPT || 'hub.luau')
  const server = authServer({
    authorize(key) {
      const a = Buffer.from(key)
      return keys.some(k => { const b = Buffer.from(k); return a.length === b.length && timingSafeEqual(a, b) })
    },
    script: () => readFile(file, 'utf8'),
    trustProxy: process.env.RIFT_AUTH_TRUST_PROXY === '1',
  })
  server.listen(Number(process.env.PORT || 8789), '127.0.0.1', () => console.log('Auth API listening on loopback; expose it through HTTPS'))
}
