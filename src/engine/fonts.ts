// Local Roblox font-family JSON backed by executor workspace TTF files.
import type { Vfs } from './vfs'
const registered = new Map<string, string>()
let serial = 0
export const localFontCss = (family: string) => registered.get(family)

export class LocalFonts {
  private loaded = new Map<string, { css: string; fonts: FontFace[]; info: object }>()
  constructor(private vfs: Vfs, private changed: () => void) {}
  private bytes(id: string) {
    const prefix = 'rbxasset://riftsim/'
    if (!id.startsWith(prefix)) throw new Error('Only local workspace font assets are supported')
    const bytes = this.vfs.read(id.slice(prefix.length))
    if (!bytes) throw new Error('Font asset is missing')
    return bytes
  }
  async load(id: string): Promise<string> {
    const existing = this.loaded.get(id)
    if (existing) return JSON.stringify(existing.info)
    const family = JSON.parse(new TextDecoder().decode(this.bytes(id)))
    if (typeof family.name !== 'string' || !Array.isArray(family.faces) || !family.faces.length || family.faces.length > 32) throw new Error('Invalid font family')
    const css = `RiftLocal_${++serial}`
    const fonts = await Promise.all(family.faces.map(async (face: { assetId: string; weight: number; style: string }) => {
      if (!Number.isFinite(face.weight) || face.weight < 100 || face.weight > 900 || !['normal', 'italic'].includes(face.style)) throw new Error('Invalid font face')
      const font = new FontFace(css, this.bytes(face.assetId).slice().buffer as ArrayBuffer, { weight: String(face.weight), style: face.style })
      return await font.load()
    }))
    const info = { Name: family.name, Faces: family.faces.map((f: { name: string; weight: number; style: string }) => ({ Name: f.name, Weight: f.weight, Style: f.style })) }
    for (const font of fonts) document.fonts.add(font)
    this.loaded.set(id, { css, fonts, info })
    registered.set(id, css)
    this.changed()
    return JSON.stringify(info)
  }
  clear() {
    for (const [id, entry] of this.loaded) {
      if (registered.get(id) === entry.css) registered.delete(id)
      for (const font of entry.fonts) document.fonts.delete(font)
    }
    this.loaded.clear()
    this.changed()
  }
}
