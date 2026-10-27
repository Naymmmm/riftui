// luau-web marshals returned strings through the WASM stack. Large strings must
// cross in bounded pieces, then be joined on the Luau heap.
const CHUNK_SIZE = 32 * 1024
export const TRANSFER_PREFIX = '\x1fRIFT_TRANSFER\x1f'

export class TextTransfers {
  private nextId = 0
  private pending = new Map<string, string[]>()

  pack(text: string): string {
    if (text.length <= CHUNK_SIZE) return text
    const chunks: string[] = []
    for (let start = 0; start < text.length;) {
      let end = Math.min(start + CHUNK_SIZE, text.length)
      // Keep surrogate pairs together when transferring non-ASCII filenames.
      const last = text.charCodeAt(end - 1)
      if (end < text.length && last >= 0xd800 && last <= 0xdbff) end--
      chunks.push(text.slice(start, end))
      start = end
    }
    const id = String(++this.nextId)
    this.pending.set(id, chunks)
    return TRANSFER_PREFIX + id + '\x1f' + chunks.length
  }

  access(op: string, id: string, index: number): string {
    if (op === 'release') { this.pending.delete(id); return '' }
    if (op !== 'read' || !Number.isInteger(index) || index < 0) throw new Error('Invalid transfer operation')
    const chunks = this.pending.get(id)
    if (!chunks || index >= chunks.length) throw new Error('Transfer chunk is unavailable')
    return chunks[index]
  }

  clear() { this.pending.clear() }
}
