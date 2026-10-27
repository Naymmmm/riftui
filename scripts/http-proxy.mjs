import { lookup } from 'node:dns/promises'
import { isIP } from 'node:net'
import { request as httpRequest } from 'node:http'
import { request as httpsRequest } from 'node:https'

const MAX_BYTES = 16 * 1024 * 1024
export function publicAddress(address) {
  if (isIP(address) === 4) {
    const [a, b, c] = address.split('.').map(Number)
    return !(a === 0 || a === 10 || a === 127 || a >= 224 ||
      (a === 100 && b >= 64 && b <= 127) ||
      (a === 169 && b === 254) || (a === 172 && b >= 16 && b <= 31) ||
      (a === 192 && (b === 168 || (b === 0 && c === 0))) ||
      (a === 198 && (b === 18 || b === 19)))
  }
  if (isIP(address) === 6) {
    const first = parseInt(address.split(':')[0], 16)
    return first >= 0x2000 && first <= 0x3fff && !address.toLowerCase().startsWith('2001:db8:')
  }
  return false
}
export async function validateTarget(raw, resolve = lookup) {
  let url
  try { url = new URL(raw) } catch { throw new Error('Give an absolute http:// or https:// URL') }
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password) throw new Error('Only public HTTP(S) URLs without embedded credentials are supported')
  if (url.port && url.port !== '80' && url.port !== '443') throw new Error('Only standard HTTP(S) ports are supported')
  const host = url.hostname.replace(/^\[|\]$/g, '')
  const addresses = isIP(host) ? [{ address: host, family: isIP(host) }] : await resolve(host, { all: true, verbatim: true })
  if (!addresses.length || addresses.some(a => !publicAddress(a.address))) throw new Error('Local and private network addresses cannot be proxied')
  return { url, addresses }
}
export async function fetchPublic(raw, { resolve = lookup, request, limit = MAX_BYTES } = {}, redirects = 0) {
  if (redirects > 4) throw new Error('Too many image redirects')
  const { url, addresses } = await validateTarget(raw, resolve)
  const response = await new Promise((resolveResponse, reject) => {
    const send = request || (url.protocol === 'https:' ? httpsRequest : httpRequest)
    const req = send(url, {
      method: 'GET',
      headers: { Accept: '*/*', 'User-Agent': 'RiftSim/0.2 (image preview)' },
      // Connect to the validated DNS result, not a second DNS lookup.
      lookup: (_hostname, options, callback) => {
        if (options?.all) callback(null, addresses)
        else callback(null, addresses[0].address, addresses[0].family)
      },
    }, res => {
      const status = res.statusCode || 502
      if ([301, 302, 303, 307, 308].includes(status) && res.headers.location) {
        res.resume()
        resolveResponse({ redirect: new URL(res.headers.location, url).href })
        return
      }
      const chunks = []
      let bytes = 0
      if (Number(res.headers['content-length']) > limit) { res.destroy(); reject(new Error('Response is larger than 16 MB')); return }
      res.on('data', chunk => {
        bytes += chunk.length
        if (bytes > limit) { res.destroy(); reject(new Error('Response is larger than 16 MB')) }
        else chunks.push(chunk)
      })
      res.on('error', reject)
      res.on('end', () => resolveResponse({ status, headers: res.headers, body: Buffer.concat(chunks) }))
    })
    req.on('error', reject)
    req.setTimeout(15000, () => { req.destroy(new Error('Image download timed out')) })
    req.end()
  })
  if (response.redirect) return fetchPublic(response.redirect, { resolve, request, limit }, redirects + 1)
  return response
}
export function proxyMiddleware(fetcher = fetchPublic) {
  return async (req, res, next) => {
    const local = new URL(req.url || '/', 'http://localhost')
    if (local.pathname !== '/__rift_http') return next()
    res.setHeader('X-Rift-Proxy', '1')
    res.setHeader('Cache-Control', 'no-store')
    res.setHeader('X-Content-Type-Options', 'nosniff')
    const fail = (status, error) => { res.statusCode = status; res.setHeader('Content-Type', 'text/plain; charset=utf-8'); res.end(error) }
    if (req.method !== 'GET') return fail(405, 'The image proxy supports GET only')
    if (req.headers['sec-fetch-site'] === 'cross-site') return fail(403, 'Use the image proxy from this simulator')
    if (req.headers.origin) {
      try { if (new URL(req.headers.origin).host !== req.headers.host) return fail(403, 'Use the image proxy from this simulator') }
      catch { return fail(403, 'Invalid request origin') }
    }
    const target = local.searchParams.get('url')
    if (!target) return fail(400, 'Missing image URL')
    try {
      const remote = await fetcher(target)
      res.statusCode = remote.status
      for (const name of ['content-type', 'content-encoding']) if (remote.headers[name]) res.setHeader(name, remote.headers[name])
      res.end(remote.body)
    } catch (error) { fail(502, error instanceof Error ? error.message : String(error)) }
  }
}
export function riftHttpProxy() {
  return {
    name: 'rift-http-proxy',
    configureServer(server) { server.middlewares.use(proxyMiddleware()) },
    configurePreviewServer(server) { server.middlewares.use(proxyMiddleware()) },
  }
}
