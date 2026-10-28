// Standard executor crypto compatibility, backed by browser Web Crypto.
import { b64ToBytes, bytesToB64 } from './vfs'
const bytes = (s: string) => b64ToBytes(s).slice().buffer as ArrayBuffer
export async function executorCrypto(op: string, data = '', key = '', iv = ''): Promise<string> {
  if (op === 'random') {
    const count = Number(data)
    if (!Number.isInteger(count) || count < 1 || count > 65536) throw Error('Invalid random byte count')
    return bytesToB64(crypto.getRandomValues(new Uint8Array(count)))
  }
  if (op === 'hash') {
    const hash = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes(data)))
    return [...hash].map(n => n.toString(16).padStart(2, '0')).join('')
  }
  if (op !== 'encrypt' && op !== 'decrypt') throw Error('Unsupported crypto operation')
  const aes = await crypto.subtle.importKey('raw', bytes(key), 'AES-CBC', false, [op])
  const result = await crypto.subtle[op]({ name: 'AES-CBC', iv: bytes(iv) }, aes, bytes(data))
  return bytesToB64(new Uint8Array(result))
}
