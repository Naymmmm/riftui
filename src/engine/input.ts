// Turns browser pointer/keyboard events on the game viewport into the event stream the
// Luau engine dispatches: UserInputService events, GuiObject MouseEnter/Leave, InputBegan,
// GuiButton clicks, ScrollingFrame wheel scrolling and real text editing for TextBoxes.

import { cssFamily } from './text'
import { isButton, isGuiObject, P, type FontVal, type Node, type Scene } from './scene'
import type { Layout } from './layout'

const SEP = '\x1f'

const CODE_TO_KEY: Record<string, string> = {
  Space: 'Space', Enter: 'Return', NumpadEnter: 'KeypadEnter', Escape: 'Escape', Backspace: 'Backspace', Tab: 'Tab',
  ShiftLeft: 'LeftShift', ShiftRight: 'RightShift', ControlLeft: 'LeftControl', ControlRight: 'RightControl',
  AltLeft: 'LeftAlt', AltRight: 'RightAlt', MetaLeft: 'LeftSuper', MetaRight: 'RightSuper', CapsLock: 'CapsLock',
  ArrowUp: 'Up', ArrowDown: 'Down', ArrowLeft: 'Left', ArrowRight: 'Right', Insert: 'Insert', Delete: 'Delete',
  Home: 'Home', End: 'End', PageUp: 'PageUp', PageDown: 'PageDown', Backquote: 'Backquote', Minus: 'Minus',
  Equal: 'Equals', BracketLeft: 'LeftBracket', BracketRight: 'RightBracket', Backslash: 'BackSlash',
  Semicolon: 'Semicolon', Quote: 'Quote', Comma: 'Comma', Period: 'Period', Slash: 'Slash',
  NumpadDecimal: 'KeypadPeriod', NumpadDivide: 'KeypadDivide', NumpadMultiply: 'KeypadMultiply',
  NumpadSubtract: 'KeypadMinus', NumpadAdd: 'KeypadPlus',
}
const DIGITS = ['Zero', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine']

export function keyCodeName(code: string): string | null {
  if (CODE_TO_KEY[code]) return CODE_TO_KEY[code]
  let m = /^Key([A-Z])$/.exec(code)
  if (m) return m[1]
  m = /^Digit(\d)$/.exec(code)
  if (m) return DIGITS[+m[1]]
  m = /^Numpad(\d)$/.exec(code)
  if (m) return 'Keypad' + DIGITS[+m[1]]
  m = /^F(\d{1,2})$/.exec(code)
  if (m && +m[1] <= 15) return 'F' + m[1]
  return null
}

export class Input {
  private events: string[] = []
  private hovered = new Set<number>()
  private pressed: Map<number, Node> = new Map() // button index -> target button
  private mouse = { x: 0, y: 0 }
  private editor: HTMLInputElement | HTMLTextAreaElement | null = null
  private editing: Node | null = null
  private stateNodes = new Set<number>()
  private touchScroll: { node: Node; x: number; y: number; startX: number; startY: number; canvasX: number; canvasY: number; dragging: boolean } | null = null
  enabled = true
  onRepaint: () => void = () => {}

  constructor(
    private viewport: HTMLElement,
    private stage: HTMLElement,
    public scene: Scene,
    public layout: Layout,
    private getScale: () => number,
  ) {
    viewport.addEventListener('pointermove', (e) => this.move(e))
    viewport.addEventListener('pointerdown', (e) => this.down(e))
    viewport.addEventListener('pointerup', (e) => this.up(e))
    viewport.addEventListener('pointercancel', (e) => this.up(e))
    viewport.addEventListener('wheel', (e) => this.wheel(e), { passive: false })
    viewport.addEventListener('contextmenu', (e) => e.preventDefault())
    viewport.addEventListener('keydown', (e) => this.key(e, true))
    viewport.addEventListener('keyup', (e) => this.key(e, false))
    viewport.addEventListener('pointerleave', () => this.leaveAll())
    viewport.addEventListener('focus', () => this.push('focus', 1))
    viewport.addEventListener('blur', () => this.push('focus', 0))
  }

  push(...f: (string | number)[]) {
    this.events.push(f.join(SEP))
  }

  flush(): string {
    const s = this.events.join('\x1e')
    this.events = []
    return s
  }

  reset() {
    this.events = []
    this.touchScroll = null
    this.hovered.clear()
    this.pressed.clear()
    this.stateNodes.clear()
    this.stopEditing(false, false)
  }

  private toSim(e: PointerEvent | WheelEvent): { x: number; y: number } {
    const r = this.stage.getBoundingClientRect()
    const s = this.getScale()
    return { x: Math.round((e.clientX - r.left) / s), y: Math.round((e.clientY - r.top) / s) }
  }

  // GuiObjects under a point, topmost first
  stackAt(x: number, y: number): Node[] {
    const out: Node[] = []
    const guis = this.layout.renderedGuis
    for (let gi = guis.length - 1; gi >= 0; gi--) {
      const gui = guis[gi]
      if (!gui.rendered) continue
      const local: Node[] = []
      const walk = (n: Node) => {
        const kids = n.children.filter((c) => isGuiObject(c) && c.rendered)
        kids.sort((a, b) => P.num(a, 'ZIndex', 1) - P.num(b, 'ZIndex', 1) || a.order - b.order)
        for (const c of kids) {
          const inClip = !c.clip || (x >= c.clip.x0 && x <= c.clip.x1 && y >= c.clip.y0 && y <= c.clip.y1)
          if (inClip && x >= c.x && x < c.x + c.w && y >= c.y && y < c.y + c.h && P.bool(c, 'Interactable', true)) local.push(c)
          walk(c)
        }
      }
      walk(gui)
      // later in paint order = on top
      out.push(...local.reverse())
    }
    return out
  }

  private gameProcessed(stack: Node[]) {
    return stack.some((n) => P.bool(n, 'Active') || isButton(n) || n.cls === 'TextBox')
  }

  // objects that receive GuiObject.InputBegan: everything down to and including the first Active one
  private receivers(stack: Node[]) {
    const out: Node[] = []
    for (const n of stack) {
      out.push(n)
      if (P.bool(n, 'Active')) break
    }
    return out
  }

  private target(stack: Node[]): Node | null {
    for (const n of stack) {
      if (isButton(n) || n.cls === 'TextBox') return n
      if (P.bool(n, 'Active')) return null
    }
    return null
  }

  private setGuiState(n: Node, state: string) {
    if (P.str(n, 'GuiState') === state) return
    this.push('gs', n.id, state)
    n.props.GuiState = state
    this.stateNodes.add(n.id)
    this.onRepaint()
  }

  private updateHover(x: number, y: number) {
    const stack = this.stackAt(x, y)
    const now = new Set(stack.map((n) => n.id))
    for (const id of this.hovered) {
      if (!now.has(id)) {
        this.push('ge', id, 'MouseLeave', x, y)
        const n = this.scene.get(id)
        if (n && isButton(n) && !this.isPressed(n)) this.setGuiState(n, 'Idle')
      }
    }
    for (const n of [...stack].reverse()) {
      if (!this.hovered.has(n.id)) this.push('ge', n.id, 'MouseEnter', x, y)
      else this.push('ge', n.id, 'MouseMoved', x, y)
    }
    this.hovered = now
    const t = this.target(stack)
    if (t && isButton(t) && !this.isPressed(t)) this.setGuiState(t, 'Hover')
    return stack
  }

  private isPressed(n: Node) {
    for (const p of this.pressed.values()) if (p === n) return true
    return false
  }

  private leaveAll() {
    for (const id of this.hovered) {
      this.push('ge', id, 'MouseLeave', this.mouse.x, this.mouse.y)
      const n = this.scene.get(id)
      if (n && isButton(n)) this.setGuiState(n, 'Idle')
    }
    this.hovered.clear()
  }

  private move(e: PointerEvent) {
    if (!this.enabled) return
    const p = this.toSim(e)
    if (p.x === this.mouse.x && p.y === this.mouse.y) return
    if (e.pointerType === 'touch' && this.touchScroll) {
      const t = this.touchScroll
      const dx = p.x - t.startX, dy = p.y - t.startY
      const horizontal = P.enm(t.node, 'ScrollingDirection', 'XY') === 'X'
      if (!t.dragging && Math.abs(horizontal ? dx : dy) > 8 && Math.abs(horizontal ? dx : dy) > Math.abs(horizontal ? dy : dx)) {
        t.dragging = true
        for (const n of this.pressed.values()) this.setGuiState(n, 'Idle')
        this.pressed.clear()
      }
      if (t.dragging) {
        const c = (t.node as Node & { canvas?: { maxX: number; maxY: number } }).canvas
        if (c) this.push('cp', t.node.id, horizontal ? Math.max(0, Math.min(c.maxX, t.canvasX - dx / t.node.scale)) : t.canvasX, horizontal ? t.canvasY : Math.max(0, Math.min(c.maxY, t.canvasY - dy / t.node.scale)))
        this.mouse = p
        return
      }
    }
    this.mouse = p
    const stack = this.updateHover(p.x, p.y)
    for (const n of this.receivers(stack)) this.push('gi', n.id, 'InputChanged', 'm')
    this.push('mm', p.x, p.y, this.gameProcessed(stack) ? 1 : 0)
  }

  private down(e: PointerEvent) {
    if (!this.enabled) return
    this.viewport.focus({ preventScroll: true })
    if (e.target !== this.editor) e.preventDefault()
    this.viewport.setPointerCapture(e.pointerId)
    const p = this.toSim(e)
    this.mouse = p
    const btn = e.button === 2 ? 2 : e.button === 1 ? 3 : 1
    const stack = this.updateHover(p.x, p.y)
    const gp = this.gameProcessed(stack)
    if (e.pointerType === 'touch') {
      this.touchScroll = null
      const node = stack.find((n) => n.cls === 'ScrollingFrame' && P.bool(n, 'ScrollingEnabled', true) && ((n as Node & { canvas?: { maxX: number; maxY: number } }).canvas?.maxY ?? 0) > 0)
      if (node) {
        const c = (node as Node & { canvas: { x: number; y: number } }).canvas
        this.touchScroll = { node, x: p.x, y: p.y, startX: p.x, startY: p.y, canvasX: c.x, canvasY: c.y, dragging: false }
      }
    }
    const t = this.target(stack)
    if (this.editing && t !== this.editing) this.stopEditing(false, true)
    for (const n of this.receivers(stack)) this.push('gi', n.id, 'InputBegan', 'b' + btn)
    if (t && isButton(t)) {
      this.pressed.set(btn, t)
      if (btn === 1) this.setGuiState(t, 'Press')
      this.push('gb', t.id, `MouseButton${btn === 3 ? 1 : btn}Down`, p.x, p.y)
    }
    this.push('md', btn, p.x, p.y, gp ? 1 : 0)
    if (t && t.cls === 'TextBox' && btn === 1 && P.bool(t, 'TextEditable', true)) {
      // focus after the down event so the box can react to Focused in order
      setTimeout(() => this.startEditing(t), 0)
    }
  }

  private up(e: PointerEvent) {
    if (!this.enabled) return
    const p = this.toSim(e)
    this.mouse = p
    const btn = e.button === 2 ? 2 : e.button === 1 ? 3 : 1
    const stack = this.stackAt(p.x, p.y)
    const gp = this.gameProcessed(stack)
    for (const n of this.receivers(stack)) this.push('gi', n.id, 'InputEnded', 'b' + btn)
    const pressed = this.pressed.get(btn)
    this.pressed.delete(btn)
    const t = this.target(stack)
    const cancelled = e.type === 'pointercancel' || this.touchScroll?.dragging
    this.touchScroll = null
    if (pressed) {
      const b = btn === 3 ? 1 : btn
      if (t === pressed && !cancelled) {
        this.push('gb', pressed.id, `MouseButton${b}Up`, p.x, p.y)
        this.push('gb', pressed.id, `MouseButton${b}Click`)
        if (btn === 1) this.push('gb', pressed.id, 'Activated', 1)
      }
      this.setGuiState(pressed, t === pressed ? 'Hover' : 'Idle')
    } else if (t && isButton(t)) {
      this.push('gb', t.id, `MouseButton${btn === 3 ? 1 : btn}Up`, p.x, p.y)
    }
    this.push('mu', btn, p.x, p.y, gp ? 1 : 0)
    if (e.pointerType === 'touch') this.leaveAll()
  }

  private wheel(e: WheelEvent) {
    if (!this.enabled) return
    e.preventDefault()
    const p = this.toSim(e)
    const stack = this.stackAt(p.x, p.y)
    const dir = e.deltaY < 0 ? 1 : -1
    for (const n of this.receivers(stack)) {
      this.push('gi', n.id, 'InputChanged', 'w')
      this.push('ge', n.id, dir > 0 ? 'MouseWheelForward' : 'MouseWheelBackward', p.x, p.y)
    }
    this.push('mw', dir, p.x, p.y, this.gameProcessed(stack) ? 1 : 0)
    for (const n of stack) {
      if (n.cls !== 'ScrollingFrame' || !P.bool(n, 'ScrollingEnabled', true)) continue
      const c = (n as Node & { canvas?: { x: number; y: number; maxX: number; maxY: number } }).canvas
      if (!c) continue
      const horizontal = P.enm(n, 'ScrollingDirection', 'XY') === 'X' || (e.shiftKey && c.maxX > 0)
      const delta = (e.deltaMode === 1 ? e.deltaY * 16 : e.deltaY) * 0.7
      const max = horizontal ? c.maxX : c.maxY
      if (max <= 0) continue
      const cur = horizontal ? c.x : c.y
      const next = Math.min(Math.max(cur + delta / n.scale, 0), max)
      if (next === cur) continue
      if (horizontal) this.push('cp', n.id, next, c.y)
      else this.push('cp', n.id, c.x, next)
      break
    }
  }

  private key(e: KeyboardEvent, down: boolean) {
    if (!this.enabled) return
    const name = keyCodeName(e.code)
    if (!name) return
    if (e.target === this.viewport) e.preventDefault()
    this.push(down ? 'kd' : 'ku', name, this.editing ? 1 : 0)
  }

  // ---- TextBox editing with a real input over the box ------------------
  handleFocusRequests() {
    for (const r of this.scene.focusRequests.splice(0)) {
      const n = this.scene.get(r.id)
      if (!n) continue
      if (r.mode === '1') this.startEditing(n)
      else if (this.editing === n) this.stopEditing(r.mode === '2', true)
    }
  }

  private startEditing(n: Node) {
    if (this.editing === n) return
    if (this.editing) this.stopEditing(false, true)
    if (!n.rendered) return
    const multi = P.bool(n, 'MultiLine')
    const el = multi ? document.createElement('textarea') : document.createElement('input')
    el.className = 'rbx-editor'
    const font = n.props.FontFace as FontVal | undefined
    if (P.bool(n, 'ClearTextOnFocus', true)) {
      this.push('tx', n.id, '')
      n.props.Text = ''
    }
    el.value = P.str(n, 'Text')
    this.editing = n
    n.dataset_editing = true
    this.place(el, n, font)
    el.addEventListener('input', () => this.push('tx', n.id, el.value.replace(/[\x1e\x1f]/g, '')))
    el.addEventListener('keydown', (e) => {
      const kname = keyCodeName((e as KeyboardEvent).code)
      if (kname) this.push('kd', kname, 1)
      if ((e as KeyboardEvent).key === 'Enter' && !multi) {
        e.preventDefault()
        this.stopEditing(true, true)
      } else if ((e as KeyboardEvent).key === 'Escape') this.stopEditing(false, true)
      e.stopPropagation()
    })
    el.addEventListener('keyup', (e) => {
      const kname = keyCodeName((e as KeyboardEvent).code)
      if (kname) this.push('ku', kname, 1)
      e.stopPropagation()
    })
    el.addEventListener('blur', () => {
      if (this.editing === n) this.stopEditing(false, true)
    })
    el.addEventListener('pointerdown', (e) => e.stopPropagation())
    this.editor = el
    this.stage.appendChild(el)
    el.focus()
    this.push('tf', n.id)
    this.onRepaint()
  }

  private place(el: HTMLElement, n: Node, font: FontVal | undefined) {
    const pad = this.scene.component(n, 'UIPadding')
    const pv = (k: string, base: number) => {
      if (!pad) return 0
      const v = P.udim(pad, k)
      return v.s * base + v.o * n.scale
    }
    const xa = P.enm(n, 'TextXAlignment', 'Center')
    el.style.cssText =
      `position:absolute;left:${n.x}px;top:${n.y}px;width:${n.w}px;height:${n.h}px;z-index:100000;box-sizing:border-box;` +
      `padding:${pv('PaddingTop', n.h)}px ${pv('PaddingRight', n.w)}px ${pv('PaddingBottom', n.h)}px ${pv('PaddingLeft', n.w)}px;` +
      `background:transparent;border:0;outline:none;resize:none;margin:0;` +
      `font-family:${cssFamily(font)};font-weight:${font?.weight ?? 400};font-size:${n.textSize || P.num(n, 'TextSize', 14)}px;` +
      `color:rgb(${[P.color(n, 'TextColor3').r, P.color(n, 'TextColor3').g, P.color(n, 'TextColor3').b].map((v) => Math.round(v * 255)).join(',')});` +
      `caret-color:currentColor;text-align:${xa === 'Left' ? 'left' : xa === 'Right' ? 'right' : 'center'};`
  }

  refreshEditor() {
    if (this.editing && this.editor) {
      if (!this.scene.get(this.editing.id) || !this.editing.rendered) this.stopEditing(false, true)
      else this.place(this.editor, this.editing, this.editing.props.FontFace as FontVal | undefined)
    }
  }

  private stopEditing(enter: boolean, notify: boolean) {
    const n = this.editing
    const el = this.editor
    this.editing = null
    this.editor = null
    if (n) n.dataset_editing = false
    if (el) {
      el.remove()
      if (document.activeElement === document.body) this.viewport.focus({ preventScroll: true })
    }
    if (n && notify) this.push('tl', n.id, enter ? 1 : 0)
    this.onRepaint()
  }
}
