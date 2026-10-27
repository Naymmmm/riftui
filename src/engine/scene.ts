// JS mirror of the Luau Instance tree, fed by the op batches the engine flushes.

export type Color = { r: number; g: number; b: number }
export type UDim = { s: number; o: number }
export type UDim2 = { xs: number; xo: number; ys: number; yo: number }
export type Vec2 = { x: number; y: number }
export type EnumVal = { enum: string; name: string; value: number }
export type FontVal = { family: string; weight: number; style: number }
export type RectVal = { x0: number; y0: number; x1: number; y1: number }
export type Keypoint = { t: number; r: number; g: number; b: number }
export type NumKey = { t: number; v: number }
export type Value =
  | null
  | boolean
  | number
  | string
  | Color
  | UDim
  | UDim2
  | Vec2
  | EnumVal
  | FontVal
  | RectVal
  | Keypoint[]
  | NumKey[]
  | { ref: number }
  | { v3: [number, number, number] }
  | { range: [number, number] }

export type Kind = 'b' | 'n' | 's' | 'U2' | 'U' | 'V2' | 'V3' | 'C3' | 'E' | 'I' | 'F' | 'R' | 'CS' | 'NS' | 'NR' | 'x'

export interface Node {
  id: number
  cls: string
  props: Record<string, Value>
  kinds: Record<string, Kind>
  parent: Node | null
  children: Node[]
  order: number
  // layout results (screen space, including the topbar)
  x: number
  y: number
  w: number
  h: number
  scale: number
  // clip rect inherited from ClipsDescendants ancestors
  clip: RectVal | null
  rendered: boolean
  textSize: number
  // last values reported back to Luau
  reported: Record<string, string>
  dom?: unknown
}

const SEP = '\x1f'
const REC = '\x1e'

export function decode(f: string[], i: number): [Kind, Value] {
  const tag = f[i] as Kind
  const n = (k: number) => parseFloat(f[i + k])
  switch (tag) {
    case 'b':
      return [tag, f[i + 1] === '1']
    case 'n':
      return [tag, n(1)]
    case 's':
      return [tag, f[i + 1] ?? '']
    case 'U2':
      return [tag, { xs: n(1), xo: n(2), ys: n(3), yo: n(4) }]
    case 'U':
      return [tag, { s: n(1), o: n(2) }]
    case 'V2':
      return [tag, { x: n(1), y: n(2) }]
    case 'V3':
      return [tag, { v3: [n(1), n(2), n(3)] }]
    case 'C3':
      return [tag, { r: n(1), g: n(2), b: n(3) }]
    case 'E':
      return [tag, { enum: f[i + 1], name: f[i + 2], value: n(3) }]
    case 'I':
      return [tag, { ref: n(1) }]
    case 'F':
      return [tag, { family: f[i + 1], weight: n(2), style: n(3) }]
    case 'R':
      return [tag, { x0: n(1), y0: n(2), x1: n(3), y1: n(4) }]
    case 'CS': {
      const count = n(1)
      const kps: Keypoint[] = []
      for (let k = 0; k < count; k++) kps.push({ t: n(2 + k * 4), r: n(3 + k * 4), g: n(4 + k * 4), b: n(5 + k * 4) })
      return [tag, kps]
    }
    case 'NS': {
      const count = n(1)
      const kps: NumKey[] = []
      for (let k = 0; k < count; k++) kps.push({ t: n(2 + k * 2), v: n(3 + k * 2) })
      return [tag, kps]
    }
    case 'NR':
      return [tag, { range: [n(1), n(2)] }]
    default:
      return ['x', null]
  }
}

export function encode(kind: Kind, v: Value): string {
  switch (kind) {
    case 'b':
      return 'b' + SEP + (v ? '1' : '0')
    case 'n':
      return 'n' + SEP + String(v)
    case 's':
      return 's' + SEP + String(v ?? '')
    case 'C3': {
      const c = v as Color
      return ['C3', c.r, c.g, c.b].join(SEP)
    }
    case 'V2': {
      const c = v as Vec2
      return ['V2', c.x, c.y].join(SEP)
    }
    case 'U2': {
      const c = v as UDim2
      return ['U2', c.xs, c.xo, c.ys, c.yo].join(SEP)
    }
    case 'U': {
      const c = v as UDim
      return ['U', c.s, c.o].join(SEP)
    }
    case 'E': {
      const e = v as EnumVal
      return ['E', e.enum, e.name].join(SEP)
    }
    default:
      return 'x'
  }
}

const GUI_OBJECTS = new Set([
  'Frame',
  'CanvasGroup',
  'TextLabel',
  'TextButton',
  'TextBox',
  'ImageLabel',
  'ImageButton',
  'ScrollingFrame',
])
export const isGuiObject = (n: Node) => GUI_OBJECTS.has(n.cls)
export const isButton = (n: Node) => n.cls === 'TextButton' || n.cls === 'ImageButton'
export const isText = (n: Node) => n.cls === 'TextLabel' || n.cls === 'TextButton' || n.cls === 'TextBox'
export const isImage = (n: Node) => n.cls === 'ImageLabel' || n.cls === 'ImageButton'

export class Scene {
  nodes = new Map<number, Node>()
  structureVersion = 0
  propVersion = 0
  dirty = true
  private orderCounter = 0
  focusRequests: Array<{ id: number; mode: string }> = []

  get(id: number) {
    return this.nodes.get(id)
  }

  root(): Node | undefined {
    for (const n of this.nodes.values()) if (n.cls === 'DataModel') return n
    return undefined
  }

  applyOps(payload: string) {
    if (!payload) return
    for (const rec of payload.split(REC)) {
      if (!rec) continue
      const f = rec.split(SEP)
      const op = f[0]
      const id = +f[1]
      if (op === 'c') {
        this.nodes.set(id, {
          id,
          cls: f[2],
          props: {},
          kinds: {},
          parent: null,
          children: [],
          order: this.orderCounter++,
          x: 0,
          y: 0,
          w: 0,
          h: 0,
          scale: 1,
          clip: null,
          rendered: false,
          textSize: 0,
          reported: {},
        })
        this.structureVersion++
      } else if (op === 'p') {
        const node = this.nodes.get(id)
        if (!node) continue
        const prop = f[2]
        const [kind, value] = decode(f, 3)
        if (prop === 'Parent') {
          this.reparent(node, kind === 'I' ? this.nodes.get((value as { ref: number }).ref) ?? null : null)
        } else {
          node.props[prop] = value
          node.kinds[prop] = kind
          if (prop === 'Name') this.structureVersion++
        }
        this.propVersion++
      } else if (op === 'd') {
        const node = this.nodes.get(id)
        if (node) this.remove(node)
      } else if (op === 'f') {
        this.focusRequests.push({ id, mode: f[2] })
      }
      this.dirty = true
    }
  }

  private reparent(node: Node, parent: Node | null) {
    if (node.parent) {
      const i = node.parent.children.indexOf(node)
      if (i >= 0) node.parent.children.splice(i, 1)
    }
    node.parent = parent
    if (parent) {
      node.order = this.orderCounter++
      parent.children.push(node)
    }
    this.structureVersion++
  }

  private remove(node: Node) {
    this.reparent(node, null)
    const drop = (n: Node) => {
      this.nodes.delete(n.id)
      for (const c of n.children) drop(c)
    }
    drop(node)
    this.structureVersion++
  }

  // UI component children (UICorner, UIStroke...) of a node
  component(node: Node, cls: string): Node | undefined {
    for (const c of node.children) if (c.cls === cls) return c
    return undefined
  }
}

export const P = {
  bool: (n: Node, k: string, d = false) => (n.props[k] as boolean | undefined) ?? d,
  num: (n: Node, k: string, d = 0) => (n.props[k] as number | undefined) ?? d,
  str: (n: Node, k: string, d = '') => (n.props[k] as string | undefined) ?? d,
  enm: (n: Node, k: string, d = '') => (n.props[k] as EnumVal | undefined)?.name ?? d,
  color: (n: Node, k: string): Color => (n.props[k] as Color | undefined) ?? { r: 1, g: 1, b: 1 },
  udim2: (n: Node, k: string): UDim2 => (n.props[k] as UDim2 | undefined) ?? { xs: 0, xo: 0, ys: 0, yo: 0 },
  udim: (n: Node, k: string): UDim => (n.props[k] as UDim | undefined) ?? { s: 0, o: 0 },
  vec2: (n: Node, k: string): Vec2 => (n.props[k] as Vec2 | undefined) ?? { x: 0, y: 0 },
}
