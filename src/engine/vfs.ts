// The executor "workspace" folder: files written by writefile, persisted in IndexedDB so
// cached assets and configs survive reloads, exactly like a real executor's workspace.

const DB = 'riftsim'
const STORE = 'workspace'

function openDb(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB, 1)
    req.onupgradeneeded = () => req.result.createObjectStore(STORE)
    req.onsuccess = () => resolve(req.result)
    req.onerror = () => reject(req.error)
  })
}

export function b64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64)
  const out = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i)
  return out
}
export function bytesToB64(bytes: Uint8Array): string {
  let bin = ''
  const chunk = 0x8000
  for (let i = 0; i < bytes.length; i += chunk) bin += String.fromCharCode(...bytes.subarray(i, i + chunk))
  return btoa(bin)
}

const norm = (p: string) => p.replace(/\\/g, '/').replace(/^\.?\/+/, '').replace(/\/+$/, '')

export class Vfs {
  files = new Map<string, Uint8Array>()
  folders = new Set<string>()
  private urls = new Map<string, string>()
  private sizes = new Map<string, { w: number; h: number } | null>()
  private db: IDBDatabase | null = null
  onImageLoaded: () => void = () => {}
  onChange: () => void = () => {}

  async load() {
    try {
      this.db = await openDb()
      const tx = this.db.transaction(STORE, 'readonly')
      const store = tx.objectStore(STORE)
      await new Promise<void>((resolve) => {
        const req = store.openCursor()
        req.onsuccess = () => {
          const cur = req.result
          if (!cur) return resolve()
          const key = String(cur.key)
          if (key.startsWith('dir:')) this.folders.add(key.slice(4))
          else this.files.set(key, new Uint8Array(cur.value as ArrayBuffer))
          cur.continue()
        }
        req.onerror = () => resolve()
      })
    } catch {
      this.db = null
    }
  }

  private persist(key: string, value: ArrayBuffer | string | null) {
    if (!this.db) return
    const tx = this.db.transaction(STORE, 'readwrite')
    const store = tx.objectStore(STORE)
    if (value === null) store.delete(key)
    else store.put(value, key)
  }

  private parentsOf(path: string) {
    const parts = path.split('/')
    for (let i = 1; i < parts.length; i++) {
      const dir = parts.slice(0, i).join('/')
      if (!this.folders.has(dir)) {
        this.folders.add(dir)
        this.persist('dir:' + dir, '1')
      }
    }
  }

  write(path: string, bytes: Uint8Array) {
    path = norm(path)
    this.files.set(path, bytes)
    this.parentsOf(path)
    const url = this.urls.get(path)
    if (url) {
      URL.revokeObjectURL(url)
      this.urls.delete(path)
      this.sizes.delete(url)
    }
    this.persist(path, bytes.slice().buffer)
    this.onChange()
  }

  read(path: string) {
    return this.files.get(norm(path))
  }

  mkdir(path: string) {
    path = norm(path)
    this.parentsOf(path + '/x')
    this.onChange()
  }

  isFolder(path: string) {
    return this.folders.has(norm(path))
  }

  delFile(path: string) {
    path = norm(path)
    this.files.delete(path)
    this.persist(path, null)
    this.onChange()
  }

  delFolder(path: string) {
    path = norm(path)
    for (const f of [...this.files.keys()]) if (f.startsWith(path + '/')) this.delFile(f)
    for (const d of [...this.folders]) if (d === path || d.startsWith(path + '/')) {
      this.folders.delete(d)
      this.persist('dir:' + d, null)
    }
    this.onChange()
  }

  list(path: string): string[] {
    path = norm(path)
    const prefix = path ? path + '/' : ''
    const out = new Set<string>()
    for (const f of [...this.files.keys(), ...this.folders]) {
      if (!f.startsWith(prefix)) continue
      const rest = f.slice(prefix.length)
      if (!rest) continue
      out.add(prefix + rest.split('/')[0])
    }
    return [...out].sort()
  }

  async reset() {
    for (const u of this.urls.values()) URL.revokeObjectURL(u)
    this.urls.clear()
    this.sizes.clear()
    this.files.clear()
    this.folders.clear()
    if (this.db) {
      const tx = this.db.transaction(STORE, 'readwrite')
      tx.objectStore(STORE).clear()
    }
    this.onChange()
  }

  assetUrl(path: string): string | null {
    path = norm(path)
    const cached = this.urls.get(path)
    if (cached) return cached
    const bytes = this.files.get(path)
    if (!bytes) return null
    const type = path.endsWith('.png') ? 'image/png' : path.endsWith('.jpg') || path.endsWith('.jpeg') ? 'image/jpeg' : path.endsWith('.webp') ? 'image/webp' : 'application/octet-stream'
    const url = URL.createObjectURL(new Blob([bytes.slice().buffer], { type }))
    this.urls.set(path, url)
    return url
  }

  imageSize(url: string): { w: number; h: number } | null {
    if (this.sizes.has(url)) return this.sizes.get(url) ?? null
    this.sizes.set(url, null)
    const img = new Image()
    img.onload = () => {
      this.sizes.set(url, { w: img.naturalWidth, h: img.naturalHeight })
      this.onImageLoaded()
    }
    img.src = url
    return null
  }
}
