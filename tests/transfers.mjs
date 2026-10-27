import assert from 'node:assert/strict'
import { TextTransfers, TRANSFER_PREFIX } from '../src/engine/transfers.ts'

const transfers = new TextTransfers()
assert.equal(transfers.pack('small'), 'small')
for (const source of ['A'.repeat(3 * 1024 * 1024), 'a'.repeat(32767) + '😀' + '雪'.repeat(60000)]) {
  const marker = transfers.pack(source)
  assert(marker.startsWith(TRANSFER_PREFIX))
  const [id, count] = marker.slice(TRANSFER_PREFIX.length).split('\x1f')
  const chunks = Array.from({ length: Number(count) }, (_, i) => transfers.access('read', id, i))
  assert(chunks.every(s => s.length <= 32768))
  assert.equal(chunks.join(''), source)
  assert(chunks.every(s => !/[\uD800-\uDBFF]$/.test(s)))
  transfers.access('release', id, 0)
  assert.throws(() => transfers.access('read', id, 0), /unavailable/)
}
const marker = transfers.pack('B'.repeat(100000))
transfers.clear()
assert.throws(() => transfers.access('read', marker.slice(TRANSFER_PREFIX.length).split('\x1f')[0], 0), /unavailable/)
assert.throws(() => transfers.access('read', '0', -1), /Invalid/)
console.log('Large text transfers: ASCII, Unicode, release and teardown passed')
