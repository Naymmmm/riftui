import assert from 'node:assert/strict'
import { mkdtemp, writeFile, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { encryptConfig, decryptConfig } from '../scripts/config/crypto.mjs'
import { configServer } from '../scripts/config/server.mjs'
const key = Buffer.alloc(32, 7).toString('base64') // Public test fixture, never a real secret.
const payload = { Hub: 'unit', Name: 'test', Data: { Flags: { Enabled: { Value: true } } } }
const a = encryptConfig(payload, key), b = encryptConfig(payload, key)
assert.deepEqual(decryptConfig(a, key), payload)
assert.notEqual(a.IV, b.IV)
assert.notEqual(a.Ciphertext, b.Ciphertext)
assert(!JSON.stringify(a).includes('Enabled'))
assert.throws(() => decryptConfig(a, Buffer.alloc(32, 8).toString('base64')))
for (const field of ['IV', 'Ciphertext', 'Tag']) {
  const changed = structuredClone(a)
  changed[field] = (changed[field][0] === 'A' ? 'B' : 'A') + changed[field].slice(1)
  assert.throws(() => decryptConfig(changed, key), field + ' was not authenticated')
}
assert.throws(() => encryptConfig(payload, 'password'))
const dir = await mkdtemp(join(tmpdir(), 'rift-configs-'))
await writeFile(join(dir, 'premium.json'), JSON.stringify(a))
const server = configServer({ directory: dir, origin: 'https://docs.invalid', authorize: (token, id) => token === 'test-token' && id === 'premium' })
await new Promise(r => server.listen(0, '127.0.0.1', r))
const url = `http://127.0.0.1:${server.address().port}/v1/configs/`
try {
  assert.equal((await fetch(url + 'premium')).status, 401)
  assert.equal((await fetch(url + 'premium', {headers:{Authorization:'Bearer wrong'}})).status, 401)
  const response = await fetch(url + 'premium', {headers:{Authorization:'Bearer test-token',Origin:'https://docs.invalid'}})
  assert.equal(response.status, 200)
  assert.equal(response.headers.get('access-control-allow-origin'), 'https://docs.invalid')
  assert.equal(response.headers.get('cache-control'), 'no-store')
  assert.deepEqual(decryptConfig(await response.json(), key), payload)
  assert.equal((await fetch(url + '../secret', {headers:{Authorization:'Bearer test-token'}})).status, 404)
  assert.equal((await fetch(url + 'another', {headers:{Authorization:'Bearer test-token'}})).status, 401)
} finally { await new Promise(r => server.close(r)); await rm(dir, {recursive:true}) }
console.log('Encrypted format: random IVs, round trip, tamper/wrong-key rejection; server auth, per-config access, CORS and path isolation passed')
