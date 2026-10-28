// Node reference implementation of RiftUI's interoperable encrypted config format.
import { createCipheriv, createDecipheriv, createHmac, randomBytes, timingSafeEqual } from 'node:crypto'
export const LIMIT = 256 * 1024
export const FORMAT = 'riftui-encrypted-config'
export const ALGORITHM = 'AES-256-CBC-HMAC-SHA256'
const hmac = (key, value) => createHmac('sha256', key).update(value).digest()
function keys(key) {
  if (typeof key !== 'string' || !/^[A-Za-z0-9+/]{43}=$/.test(key)) throw Error('A random 32-byte Base64 key is required')
  const raw = Buffer.from(key, 'base64')
  if (raw.length !== 32 || raw.toString('base64') !== key) throw Error('Invalid key')
  return [hmac(raw, 'RiftUI config encryption v1'), hmac(raw, 'RiftUI config authentication v1')]
}
export function authenticatedText(e) { return `${FORMAT}\0${1}\0${ALGORITHM}\0${e.IV}\0${e.Ciphertext}` }
export function encryptConfig(payload, key) {
  const json = JSON.stringify(payload)
  if (Buffer.byteLength(json) > LIMIT) throw Error('Config too large')
  const [aesKey, macKey] = keys(key)
  const iv = randomBytes(16)
  const cipher = createCipheriv('aes-256-cbc', aesKey, iv)
  const e = { Format: FORMAT, Version: 1, Algorithm: ALGORITHM, IV: iv.toString('base64'), Ciphertext: Buffer.concat([cipher.update(json, 'utf8'), cipher.final()]).toString('base64') }
  e.Tag = hmac(macKey, authenticatedText(e)).toString('hex')
  return e
}
export function decryptConfig(e, key) {
  const [aesKey, macKey] = keys(key)
  if (!e || e.Format !== FORMAT || e.Version !== 1 || e.Algorithm !== ALGORITHM || typeof e.IV !== 'string' || e.IV.length !== 24 || typeof e.Ciphertext !== 'string' || e.Ciphertext.length > LIMIT * 2 || typeof e.Tag !== 'string' || !/^[a-f0-9]{64}$/.test(e.Tag)) throw Error('Invalid encrypted config')
  if (!timingSafeEqual(Buffer.from(e.Tag, 'hex'), hmac(macKey, authenticatedText(e)))) throw Error('Config authentication failed')
  const decipher = createDecipheriv('aes-256-cbc', aesKey, Buffer.from(e.IV, 'base64'))
  const plain = Buffer.concat([decipher.update(Buffer.from(e.Ciphertext, 'base64')), decipher.final()])
  if (plain.length > LIMIT) throw Error('Config too large')
  return JSON.parse(plain.toString('utf8'))
}
