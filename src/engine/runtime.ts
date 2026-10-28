// Boots a fresh Luau VM per run, wires the engine's __HOST bridge to the scene mirror,
// layout, renderer, input and filesystem, and drives one engine step per animation frame.

import { LuauState } from 'luau-web'
import { Scene } from './scene'
import { Layout } from './layout'
import { Renderer } from './render'
import { Input } from './input'
import { measure } from './text'
import { b64ToBytes, bytesToB64, Vfs } from './vfs'
import { TextTransfers } from './transfers'
import { executorCrypto } from './crypto'

export type LogLevel = 'print' | 'warn' | 'error' | 'info'
export interface LogEntry {
  level: LogLevel
  text: string
  trace?: string
  time: number
}

type LuauFn = (...args: unknown[]) => Promise<unknown>

const SEP = '\x1f'
// Main previews local work; commit-pinned requests must fetch the actual revision.
const LOCAL_PUBLIC = /\/riftui\/main\/public\/(.+)$/

export class Runtime {
  scene = new Scene()
  layout = new Layout(this.scene)
  renderer: Renderer
  input: Input
  state: LuauState | null = null
  running = false
  touch = false
  profile = ''
  private step: LuauFn | null = null
  private run: LuauFn | null = null
  private busy = false
  private raf = 0
  private last = 0
  private renderDirty = true
  private generation = 0
  // A state must outlive its pending Luau/host calls, including during startup.
  private lifecycle: Promise<void> = Promise.resolve()
  private servedNotice = false
  private transfers = new TextTransfers()
  frameTime = 0
  onLog: (e: LogEntry) => void = () => {}
  onFrame: () => void = () => {}

  constructor(
    private stage: HTMLElement,
    viewport: HTMLElement,
    public vfs: Vfs,
    getScale: () => number,
  ) {
    this.renderer = new Renderer(stage.querySelector('.rbx-root') as HTMLElement, this.scene, this.layout, vfs)
    this.renderer.onImageWarning = (m) => this.log('warn', m)
    this.input = new Input(viewport, stage, this.scene, this.layout, getScale)
    this.input.onRepaint = () => (this.renderDirty = true)
    vfs.onImageLoaded = () => (this.renderDirty = true)
  }

  log(level: LogLevel, text: string, trace?: string) {
    this.onLog({ level, text, trace, time: performance.now() })
  }

  setViewport(w: number, h: number, touch: boolean) {
    this.layout.W = w
    this.layout.H = h
    this.touch = touch
    this.scene.dirty = true
    this.renderDirty = true
    this.input.push('vp', w, h, touch ? 1 : 0)
  }

  private host() {
    return {
      sync: (payload: string) => {
        this.scene.applyOps(payload)
        const { records, canvasFixes } = this.layout.run()
        for (const f of canvasFixes) this.input.push(f)
        this.renderDirty = true
        return records
      },
      measure: (text: string, size: number, family: string, weight: number, style: number, width: number) => {
        const [w, h] = measure({ text, size, font: { family, weight, style }, width, rich: false, lineHeight: 1 })
        return w + SEP + h
      },
      print: (m: string) => this.log('print', m),
      warn: (m: string) => this.log('warn', m),
      error: (m: string, trace: string) => this.log('error', m, trace),
      now: () => Date.now(),
      load: (src: string, name: string) => {
        const res = this.state!.loadstring(src, name, false)
        return res
      },
      fs: (op: string, path: string, data: string) => this.transfers.pack(this.fs(op, path, data)),
      http: async (method: string, url: string, headers: string, body: string) => this.transfers.pack(await this.http(method, url, headers, body)),
      transfer: (op: string, id: string, index: number) => this.transfers.access(op, id, index),
      clipboard: (text: string) => {
        navigator.clipboard?.writeText(text).catch(() => {})
        this.log('info', 'setclipboard: copied ' + text.length + ' characters')
      },
      crypto: async (op: string, data: string, key: string, iv: string) => {
        try { return this.transfers.pack(await executorCrypto(op, data, key, iv)) }
        catch { return 'ERR' + SEP + 'Crypto operation failed' }
      },
      profile: () => this.profile,
      register: (step: LuauFn, run: LuauFn) => {
        this.step = step
        this.run = run
      },
    }
  }

  private fs(op: string, path: string, data: string): string {
    const v = this.vfs
    try {
      switch (op) {
        case 'write':
          v.write(path, b64ToBytes(data))
          return ''
        case 'append': {
          const old = v.read(path) ?? new Uint8Array()
          const add = b64ToBytes(data)
          const out = new Uint8Array(old.length + add.length)
          out.set(old)
          out.set(add, old.length)
          v.write(path, out)
          return ''
        }
        case 'read': {
          const f = v.read(path)
          return f ? bytesToB64(f) : 'ERR' + SEP + `unable to read file '${path}': file does not exist`
        }
        case 'isfile':
          return v.read(path) ? '1' : '0'
        case 'isfolder':
          return v.isFolder(path) ? '1' : '0'
        case 'mkdir':
          v.mkdir(path)
          return ''
        case 'delfile':
          v.delFile(path)
          return ''
        case 'delfolder':
          v.delFolder(path)
          return ''
        case 'list':
          return v.list(path).join(SEP)
        case 'asset':
          return v.read(path) ? 'rbxasset://riftsim/' + path.replace(/\\/g, '/') : 'ERR' + SEP + `getcustomasset: file '${path}' does not exist`
      }
    } catch (e) {
      return 'ERR' + SEP + String(e)
    }
    return 'ERR' + SEP + 'unknown fs op ' + op
  }

  private async http(method: string, url: string, headersJson: string, body: string): Promise<string> {
    let target = url
    const local = LOCAL_PUBLIC.exec(url)
    if (local) target = '/' + local[1]
    try {
      const headers = JSON.parse(headersJson || '{}')
      let res: Response
      try {
        res = await fetch(target, {
          method,
          headers: Array.isArray(headers) ? {} : headers,
          body: method === 'GET' || method === 'HEAD' || !body ? undefined : (b64ToBytes(body).slice().buffer as ArrayBuffer),
        })
      } catch (directError) {
        if (local || method !== 'GET' || Object.keys(headers || {}).some(k => /^(authorization|x-api-key)$/i.test(k)) || !/^https?:\/\//i.test(url)) throw directError
        res = await fetch('/__rift_http?url=' + encodeURIComponent(url))
        if (res.headers.get('X-Rift-Proxy') !== '1') {
          throw new Error('The browser blocked this URL and this host has no RiftSim image proxy. Use pnpm dev or pnpm preview, or a CORS-enabled image URL.')
        }
      }
      const bytes = new Uint8Array(await res.arrayBuffer())
      const h: Record<string, string> = {}
      res.headers.forEach((v, k) => (h[k] = v))
      if (local && !this.servedNotice) {
        this.servedNotice = true
        this.log('info', `HttpGet …/riftui/main/public/* is served from this simulator, so the script's real URLs work unchanged.`)
      }
      return res.status + SEP + bytesToB64(bytes) + SEP + JSON.stringify(h)
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e)
      return '0' + SEP + btoa(unescape(encodeURIComponent(msg))) + SEP + '{}'
    }
  }

  start(source: string, name: string): Promise<void> {
    const gen = ++this.generation
    this.running = false
    cancelAnimationFrame(this.raf)
    const pending = this.lifecycle.then(async () => {
      if (gen !== this.generation) return
      await this.stopCurrent()
      if (gen !== this.generation) return
      await this.startCurrent(source, name, gen)
    })
    this.lifecycle = pending.catch(() => {})
    return pending
  }

  private async startCurrent(source: string, name: string, gen: number) {
    this.servedNotice = false
    const w = this.layout.W
    const h = this.layout.H
    this.input.reset()
    this.renderer.clear()
    this.scene = new Scene()
    this.layout = new Layout(this.scene)
    this.layout.W = w
    this.layout.H = h
    this.renderer.scene = this.scene
    this.renderer.layout = this.layout
    this.input.scene = this.scene
    this.input.layout = this.layout
    this.input.push('vp', w, h, this.touch ? 1 : 0)

    const engine = await (await fetch('/engine.luau')).text()
    if (gen !== this.generation) return
    const state = await LuauState.createAsync({ __HOST: this.host() })
    if (gen !== this.generation) {
      state.destroy()
      return
    }
    this.state = state
    const boot = state.loadstring(engine, '=engine', false)
    if (typeof boot === 'string') {
      this.log('error', 'engine failed to compile: ' + boot)
      return
    }
    await boot()
    if (gen !== this.generation) return
    if (!this.step || !this.run) {
      this.log('error', 'engine did not register')
      return
    }
    this.running = true
    this.last = performance.now()
    await this.step(0, this.input.flush())
    if (gen !== this.generation) return
    this.log('info', `Running ${name}`)
    await this.run(source, name)
    if (gen !== this.generation) return
    this.renderDirty = true
    this.loop()
  }

  private loop = () => {
    if (!this.running) return
    this.raf = requestAnimationFrame(this.loop)
    if (this.busy || !this.step) return
    const now = performance.now()
    const dt = Math.min((now - this.last) / 1000, 0.1)
    this.last = now
    this.busy = true
    const t0 = performance.now()
    this.step(dt, this.input.flush())
      .catch((e: unknown) => this.log('error', 'step: ' + String(e)))
      .finally(() => {
        this.busy = false
        this.frameTime = performance.now() - t0
        this.input.handleFocusRequests()
        if (this.renderDirty) {
          this.renderDirty = false
          this.renderer.render()
          this.input.refreshEditor()
        }
        this.onFrame()
      })
  }

  stop(): Promise<void> {
    ++this.generation
    this.running = false
    cancelAnimationFrame(this.raf)
    const pending = this.lifecycle.then(() => this.stopCurrent())
    this.lifecycle = pending.catch(() => {})
    return pending
  }

  private async stopCurrent() {
    this.running = false
    cancelAnimationFrame(this.raf)
    while (this.busy) await new Promise((r) => setTimeout(r, 5))
    if (this.state) {
      try {
        this.state.destroy()
      } catch {
        /* already gone */
      }
    }
    this.state = null
    this.transfers.clear()
    this.step = null
    this.run = null
    this.input.reset()
    this.renderer.clear()
  }

  forceRender() {
    this.renderDirty = true
    this.input.push('rl')
  }

  // Properties panel edits arrive as engine events so Luau stays the source of truth
  editProperty(id: number, prop: string, encoded: string) {
    this.input.push('ps', id, prop, encoded)
  }
}
