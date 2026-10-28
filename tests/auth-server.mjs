import assert from 'node:assert/strict'
import { authServer } from '../scripts/auth/server.mjs'
const seen = []
const server = authServer({
  authorize: (key, hwid) => { seen.push(hwid); return key === 'good-key' ? true : key === 'old-key' ? 'Key expired' : false },
  script: () => 'print("hub")',
  limit: 5,
})
await new Promise(r => server.listen(0, '127.0.0.1', r))
const url = `http://127.0.0.1:${server.address().port}/v1/script`
const get = (key, extra = {}) => fetch(url, { headers: key ? { Authorization: 'Bearer ' + key, ...extra } : extra })
try {
  let r = await get()
  assert.equal(r.status, 401)
  assert.equal((await r.json()).error, 'Invalid key.')
  r = await get('old-key')
  assert.equal(r.status, 401)
  assert.equal((await r.json()).error, 'Key expired')
  r = await get('good-key', { 'X-Rift-Hwid': 'machine-1' })
  assert.equal(r.status, 200)
  assert.match(r.headers.get('content-type'), /^text\/plain/)
  assert.equal(r.headers.get('cache-control'), 'no-store')
  assert.equal(await r.text(), 'print("hub")')
  assert.equal(seen.at(-1), 'machine-1')
  assert.equal((await fetch(url.replace('/v1/script', '/v1/other'))).status, 404)
  await get('wrong'); await get('wrong')
  r = await get('good-key')
  assert.equal(r.status, 429, 'attempt budget applies per client')
} finally { await new Promise(r => server.close(r)) }
assert.throws(() => authServer({}))
console.log('Auth server: bearer keys, refusal reasons, HWID header, text script, no-store, attempt limit passed')
