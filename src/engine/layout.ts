// Roblox GuiObject layout: UDim2 sizing, AnchorPoint, SizeConstraint, AutomaticSize,
// UIPadding, UIListLayout, UIGridLayout, UIScale, UISizeConstraint,
// UIAspectRatioConstraint, ScrollingFrame canvases, TextScaled and TextBounds.
// Everything is computed in a scale root's local units and mapped to screen pixels.

import { measure, stripRich } from './text'
import { isGuiObject, isText, P, type FontVal, type Node, type RectVal, type Scene } from './scene'

interface Frame {
  ox: number
  oy: number
  k: number
}

const SEP = '\x1f'

export class Layout {
  inset = 58
  W = 1280
  H = 720
  private pass = 0
  private sizeCache = new Map<Node, Map<string, [number, number]>>()
  // screen pixels per local unit for the frame being laid out; text is measured at its drawn size
  private k = 1
  private records: string[] = []
  private canvasFixes: string[] = []
  renderedGuis: Node[] = []

  constructor(private scene: Scene) {}

  run(): { records: string; canvasFixes: string[] } {
    this.pass++
    this.sizeCache.clear()
    this.records = []
    this.canvasFixes = []
    for (const n of this.scene.nodes.values()) n.rendered = false
    this.renderedGuis = this.collectGuis()
    for (const gui of this.renderedGuis) this.layoutScreenGui(gui)
    return { records: this.records.join('\x1e'), canvasFixes: this.canvasFixes }
  }

  private collectGuis(): Node[] {
    const out: Node[] = []
    const root = this.scene.root()
    if (!root) return out
    const containers: Node[] = []
    for (const svc of root.children) {
      if (svc.cls === 'CoreGui') containers.push(svc)
      if (svc.cls === 'Players') {
        for (const p of svc.children) for (const pg of p.children) if (pg.cls === 'PlayerGui') containers.push(pg)
      }
    }
    const walk = (n: Node) => {
      for (const c of n.children) {
        if (c.cls === 'ScreenGui') out.push(c)
        else if (!isGuiObject(c)) walk(c)
      }
    }
    for (const c of containers) walk(c)
    out.sort((a, b) => P.num(a, 'DisplayOrder') - P.num(b, 'DisplayOrder') || a.order - b.order)
    return out
  }

  private report(n: Node, kind: string, payload: string) {
    if (n.reported[kind] !== payload) {
      n.reported[kind] = payload
      this.records.push(kind + SEP + n.id + SEP + payload)
    }
  }

  private layoutScreenGui(gui: Node) {
    const ignore = P.bool(gui, 'IgnoreGuiInset')
    const top = ignore ? 0 : this.inset
    gui.x = 0
    gui.y = top
    gui.w = this.W
    gui.h = this.H - top
    gui.scale = 1
    gui.clip = null
    gui.rendered = P.bool(gui, 'Enabled', true)
    this.report(gui, 'a', [0, top - this.inset, this.W, this.H - top].map(fmt).join(SEP))
    const uiScale = this.scene.component(gui, 'UIScale')
    const s = uiScale ? P.num(uiScale, 'Scale', 1) : 1
    const frame: Frame = { ox: 0, oy: top, k: s }
    this.k = s
    this.layoutChildren(gui, { x: 0, y: 0, w: gui.w / s, h: gui.h / s }, frame, null, gui.rendered)
  }

  // ---- sizing ----------------------------------------------------------
  private padding(n: Node, w: number, h: number) {
    const p = this.scene.component(n, 'UIPadding')
    if (!p) return { t: 0, r: 0, b: 0, l: 0 }
    const u = (k: string, base: number) => {
      const v = P.udim(p, k)
      return v.s * base + v.o
    }
    return { t: u('PaddingTop', h), r: u('PaddingRight', w), b: u('PaddingBottom', h), l: u('PaddingLeft', w) }
  }

  private baseSize(n: Node, pw: number, ph: number): [number, number] {
    const s = P.udim2(n, 'Size')
    const sc = P.enm(n, 'SizeConstraint', 'RelativeXY')
    let w: number
    let h: number
    if (sc === 'RelativeXX') {
      w = s.xs * pw + s.xo
      h = s.ys * pw + s.yo
    } else if (sc === 'RelativeYY') {
      w = s.xs * ph + s.xo
      h = s.ys * ph + s.yo
    } else {
      w = s.xs * pw + s.xo
      h = s.ys * ph + s.yo
    }
    return [w, h]
  }

  private constrain(n: Node, w: number, h: number): [number, number] {
    const ar = this.scene.component(n, 'UIAspectRatioConstraint')
    if (ar) {
      const r = P.num(ar, 'AspectRatio', 1) || 1
      const type = P.enm(ar, 'AspectType', 'FitWithinMaxSize')
      if (type === 'ScaleWithParentSize') {
        if (P.enm(ar, 'DominantAxis', 'Width') === 'Width') h = w / r
        else w = h * r
      } else if (w / Math.max(h, 1e-6) > r) w = h * r
      else h = w / r
    }
    const sc = this.scene.component(n, 'UISizeConstraint')
    if (sc) {
      const mn = P.vec2(sc, 'MinSize')
      const mx = P.vec2(sc, 'MaxSize')
      w = Math.min(Math.max(w, mn.x), mx.x)
      h = Math.min(Math.max(h, mn.y), mx.y)
    }
    return [Math.max(0, w), Math.max(0, h)]
  }

  private visibleKids(n: Node): Node[] {
    return n.children.filter((c) => isGuiObject(c) && P.bool(c, 'Visible', true))
  }

  private sortForLayout(kids: Node[], layout: Node): Node[] {
    const byName = P.enm(layout, 'SortOrder', 'LayoutOrder') === 'Name'
    return [...kids].sort((a, b) => {
      if (byName) return P.str(a, 'Name').localeCompare(P.str(b, 'Name')) || a.order - b.order
      return P.num(a, 'LayoutOrder') - P.num(b, 'LayoutOrder') || a.order - b.order
    })
  }

  // Size of a node given its parent's content size, with AutomaticSize resolved.
  size(n: Node, pw: number, ph: number): [number, number] {
    const key = pw.toFixed(2) + ',' + ph.toFixed(2) + ',' + this.k
    let m = this.sizeCache.get(n)
    const hit = m?.get(key)
    if (hit) return hit
    let [w, h] = this.constrain(n, ...this.baseSize(n, pw, ph))
    const auto = P.enm(n, 'AutomaticSize', 'None')
    if (auto !== 'None' && n.cls !== 'ScrollingFrame') {
      const autoX = auto === 'X' || auto === 'XY'
      const autoY = auto === 'Y' || auto === 'XY'
      const pad = this.padding(n, w, h)
      const [ew, eh] = this.contentExtent(n, w, h, autoX)
      if (autoX) w = Math.max(w, ew + pad.l + pad.r)
      if (autoY) h = Math.max(h, eh + pad.t + pad.b)
      ;[w, h] = this.constrain(n, w, h)
    }
    if (!m) {
      m = new Map()
      this.sizeCache.set(n, m)
    }
    m.set(key, [w, h])
    return [w, h]
  }

  private contentExtent(n: Node, w: number, h: number, autoX: boolean): [number, number] {
    const pad = this.padding(n, w, h)
    const cw = Math.max(0, w - pad.l - pad.r)
    const ch = Math.max(0, h - pad.t - pad.b)
    let ew = 0
    let eh = 0
    if (isText(n)) {
      const [tw, th] = this.textBounds(n, autoX ? 0 : cw, P.num(n, 'TextSize', 14))
      ew = tw
      eh = th
    }
    const kids = this.visibleKids(n)
    const list = this.scene.component(n, 'UIListLayout')
    const grid = this.scene.component(n, 'UIGridLayout')
    if (list) {
      const [lw, lh] = this.listContent(list, this.sortForLayout(kids, list), cw, ch)
      ew = Math.max(ew, lw)
      eh = Math.max(eh, lh)
    } else if (grid) {
      const g = this.gridGeometry(grid, kids.length, cw, ch)
      ew = Math.max(ew, g.contentW)
      eh = Math.max(eh, g.contentH)
    } else {
      for (const c of kids) {
        const [sw, sh] = this.size(c, cw, ch)
        const pos = P.udim2(c, 'Position')
        const ap = P.vec2(c, 'AnchorPoint')
        const x = pos.xs * cw + pos.xo - ap.x * sw
        const y = pos.ys * ch + pos.yo - ap.y * sh
        ew = Math.max(ew, x + sw)
        eh = Math.max(eh, y + sh)
      }
    }
    return [ew, eh]
  }

  private listContent(list: Node, kids: Node[], cw: number, ch: number): [number, number] {
    const vertical = P.enm(list, 'FillDirection', 'Vertical') === 'Vertical'
    const padU = P.udim(list, 'Padding')
    const gap = padU.s * (vertical ? ch : cw) + padU.o
    let main = 0
    let cross = 0
    kids.forEach((c, i) => {
      const [sw, sh] = this.size(c, cw, ch)
      main += (vertical ? sh : sw) + (i > 0 ? gap : 0)
      cross = Math.max(cross, vertical ? sw : sh)
    })
    return vertical ? [cross, main] : [main, cross]
  }

  private gridGeometry(grid: Node, count: number, cw: number, ch: number) {
    const cs = P.udim2(grid, 'CellSize')
    const cp = P.udim2(grid, 'CellPadding')
    const cellW = cs.xs * cw + cs.xo
    const cellH = cs.ys * ch + cs.yo
    const padX = cp.xs * cw + cp.xo
    const padY = cp.ys * ch + cp.yo
    const horizontal = P.enm(grid, 'FillDirection', 'Horizontal') === 'Horizontal'
    const maxCells = P.num(grid, 'FillDirectionMaxCells', 0)
    let perLine = horizontal ? Math.floor((cw + padX) / Math.max(1, cellW + padX)) : Math.floor((ch + padY) / Math.max(1, cellH + padY))
    perLine = Math.max(1, perLine)
    if (maxCells > 0) perLine = Math.min(perLine, maxCells)
    const lines = Math.ceil(count / perLine)
    const cols = horizontal ? Math.min(count, perLine) : lines
    const rows = horizontal ? lines : Math.min(count, perLine)
    return {
      cellW,
      cellH,
      padX,
      padY,
      perLine,
      horizontal,
      cols,
      rows,
      contentW: cols > 0 ? cols * cellW + (cols - 1) * padX : 0,
      contentH: rows > 0 ? rows * cellH + (rows - 1) * padY : 0,
    }
  }

  // ---- text ------------------------------------------------------------
  // Browser glyph widths don't scale linearly with font size, so measuring at the base size and
  // multiplying by the UIScale undershoots and the drawn text overflows its automatic size.
  private textBounds(n: Node, wrapWidth: number, size: number, k = this.k * this.ownScale(n)): [number, number] {
    const rich = P.bool(n, 'RichText')
    let text = P.str(n, 'Text')
    if (n.cls === 'TextBox' && text === '') text = ''
    const wrapped = P.bool(n, 'TextWrapped') || P.bool(n, 'TextScaled')
    const [w, h] = measure({
      text,
      size: size * k,
      font: n.props.FontFace as FontVal | undefined,
      width: wrapped ? wrapWidth * k : 0,
      rich,
      lineHeight: P.num(n, 'LineHeight', 1),
    })
    return [w / k, h / k]
  }

  private ownScale(n: Node) {
    const uiScale = this.scene.component(n, 'UIScale')
    return uiScale ? P.num(uiScale, 'Scale', 1) : 1
  }

  private resolveText(n: Node, cw: number, ch: number, k: number) {
    let size = P.num(n, 'TextSize', 14)
    if (P.bool(n, 'TextScaled')) {
      const c = this.scene.component(n, 'UITextSizeConstraint')
      const lo0 = c ? P.num(c, 'MinTextSize', 1) : 1
      const hi0 = c ? P.num(c, 'MaxTextSize', 100) : 100
      let lo = Math.max(1, lo0)
      let hi = Math.min(100, hi0)
      if (stripRich(P.str(n, 'Text')) === '') size = hi
      else {
        while (lo < hi) {
          const mid = Math.ceil((lo + hi) / 2)
          const [tw, th] = this.textBounds(n, cw, mid, k)
          if (tw <= cw + 0.5 && th <= ch + 0.5) lo = mid
          else hi = mid - 1
        }
        size = lo
      }
    }
    const [tw, th] = this.textBounds(n, cw, size, k)
    n.textSize = size * k
    const fits = tw <= cw + 0.5 && th <= ch + 0.5
    this.report(n, 't', [fmt(tw * k), fmt(th * k), fits ? '1' : '0'].join(SEP))
  }

  // ---- placement -------------------------------------------------------
  private toScreen(f: Frame, x: number, y: number): [number, number] {
    return [f.ox + x * f.k, f.oy + y * f.k]
  }

  private place(n: Node, lx: number, ly: number, w: number, h: number, frame: Frame, clip: RectVal | null, visible: boolean) {
    // UIScale on this node scales it about its anchor point and starts a new frame for its children
    const uiScale = this.scene.component(n, 'UIScale')
    const s = uiScale ? P.num(uiScale, 'Scale', 1) : 1
    let bx = lx
    let by = ly
    let bw = w
    let bh = h
    if (s !== 1) {
      const ap = P.vec2(n, 'AnchorPoint')
      const axL = lx + ap.x * w
      const ayL = ly + ap.y * h
      bw = w * s
      bh = h * s
      bx = axL - ap.x * bw
      by = ayL - ap.y * bh
    }
    const [sx, sy] = this.toScreen(frame, bx, by)
    n.x = sx
    n.y = sy
    n.w = bw * frame.k
    n.h = bh * frame.k
    n.scale = frame.k * s
    n.clip = clip
    n.rendered = visible && P.bool(n, 'Visible', true)
    this.report(n, 'a', [fmt(n.x), fmt(n.y - this.inset), fmt(n.w), fmt(n.h)].join(SEP))

    const childFrame: Frame = s !== 1 ? { ox: sx, oy: sy, k: frame.k * s } : frame
    const originX = s !== 1 ? 0 : lx
    const originY = s !== 1 ? 0 : ly
    const pad = this.padding(n, w, h)
    let content = { x: originX + pad.l, y: originY + pad.t, w: Math.max(0, w - pad.l - pad.r), h: Math.max(0, h - pad.t - pad.b) }

    if (isText(n)) this.resolveText(n, content.w, content.h, childFrame.k)

    let childClip = clip
    const clips = P.bool(n, 'ClipsDescendants') || n.cls === 'ScrollingFrame' || n.cls === 'CanvasGroup'
    if (clips) {
      const r = { x0: n.x, y0: n.y, x1: n.x + n.w, y1: n.y + n.h }
      childClip = clip ? { x0: Math.max(r.x0, clip.x0), y0: Math.max(r.y0, clip.y0), x1: Math.min(r.x1, clip.x1), y1: Math.min(r.y1, clip.y1) } : r
    }

    const parentK = this.k
    this.k = childFrame.k
    if (n.cls === 'ScrollingFrame') content = this.scrollCanvas(n, w, h, originX, originY, pad, childFrame)
    this.layoutChildren(n, content, childFrame, childClip, n.rendered)
    this.k = parentK
  }

  private scrollCanvas(n: Node, w: number, h: number, ox: number, oy: number, pad: { t: number; r: number; b: number; l: number }, frame: Frame) {
    const thickness = P.num(n, 'ScrollBarThickness', 12)
    const cs = P.udim2(n, 'CanvasSize')
    let winW = w
    let winH = h
    let canvasW = cs.xs * winW + cs.xo
    let canvasH = cs.ys * winH + cs.yo
    const auto = P.enm(n, 'AutomaticCanvasSize', 'None')
    const extent = () => {
      const [ew, eh] = this.contentExtent(n, canvasW, canvasH, false)
      if (auto === 'X' || auto === 'XY') canvasW = Math.max(canvasW, ew + pad.l + pad.r)
      if (auto === 'Y' || auto === 'XY') canvasH = Math.max(canvasH, eh + pad.t + pad.b)
    }
    if (auto !== 'None') {
      // AutomaticCanvasSize grows the canvas past CanvasSize to fit the content
      canvasW = Math.max(cs.xs * winW + cs.xo, 0)
      canvasH = Math.max(cs.ys * winH + cs.yo, 0)
      if (auto === 'Y' || auto === 'XY') canvasH = cs.yo
      if (auto === 'X' || auto === 'XY') canvasW = cs.xo
      if (auto === 'Y') canvasW = Math.max(canvasW, winW)
      if (auto === 'X') canvasH = Math.max(canvasH, winH)
      extent()
    }
    const inset = P.enm(n, 'VerticalScrollBarInset', 'None')
    const dir = P.enm(n, 'ScrollingDirection', 'XY')
    const vScroll = canvasH > winH + 0.5 && dir !== 'X'
    if ((inset === 'Always' || (inset === 'ScrollBar' && vScroll)) && thickness > 0) {
      winW -= thickness
      if (auto === 'Y') canvasW = Math.max(cs.xs * winW + cs.xo, winW)
    }
    const cpRaw = P.vec2(n, 'CanvasPosition')
    const maxX = Math.max(0, canvasW - winW)
    const maxY = Math.max(0, canvasH - winH)
    const cx = Math.min(Math.max(cpRaw.x, 0), maxX)
    const cy = Math.min(Math.max(cpRaw.y, 0), maxY)
    if (Math.abs(cx - cpRaw.x) > 0.01 || Math.abs(cy - cpRaw.y) > 0.01) this.canvasFixes.push(['cp', n.id, cx, cy].join(SEP))
    ;(n as Node & { canvas?: unknown }).canvas = { w: canvasW * frame.k, h: canvasH * frame.k, winW: winW * frame.k, winH: winH * frame.k, x: cx, y: cy, maxX, maxY, vScroll }
    this.report(n, 'w', [fmt(canvasW * frame.k), fmt(canvasH * frame.k), fmt(winW * frame.k), fmt(winH * frame.k)].join(SEP))
    return { x: ox + pad.l - cx, y: oy + pad.t - cy, w: Math.max(0, canvasW - pad.l - pad.r), h: Math.max(0, canvasH - pad.t - pad.b) }
  }

  private layoutChildren(n: Node, content: { x: number; y: number; w: number; h: number }, frame: Frame, clip: RectVal | null, visible: boolean) {
    const kids = n.children.filter(isGuiObject)
    const list = this.scene.component(n, 'UIListLayout')
    const grid = this.scene.component(n, 'UIGridLayout')
    const placed = new Set<Node>()
    if (list) {
      const items = this.sortForLayout(kids.filter((c) => P.bool(c, 'Visible', true)), list)
      const vertical = P.enm(list, 'FillDirection', 'Vertical') === 'Vertical'
      const padU = P.udim(list, 'Padding')
      const gap = padU.s * (vertical ? content.h : content.w) + padU.o
      const sizes = items.map((c) => this.size(c, content.w, content.h))
      let total = 0
      let cross = 0
      sizes.forEach(([sw, sh], i) => {
        total += (vertical ? sh : sw) + (i > 0 ? gap : 0)
        cross = Math.max(cross, vertical ? sw : sh)
      })
      // optional flex fill along the main axis
      const flex = P.enm(list, vertical ? 'VerticalFlex' : 'HorizontalFlex', 'None')
      const free = (vertical ? content.h : content.w) - total
      let between = 0
      let startOffset = 0
      if (flex === 'Fill' && free > 0 && items.length) {
        const add = free / items.length
        sizes.forEach((sz) => {
          if (vertical) sz[1] += add
          else sz[0] += add
        })
        total += free
      } else if (flex === 'SpaceBetween' && free > 0 && items.length > 1) between = free / (items.length - 1)
      else if (flex === 'SpaceAround' && free > 0 && items.length) {
        between = free / items.length
        startOffset = between / 2
      } else if (flex === 'SpaceEvenly' && free > 0 && items.length) {
        between = free / (items.length + 1)
        startOffset = between
      }
      const ha = P.enm(list, 'HorizontalAlignment', 'Left')
      const va = P.enm(list, 'VerticalAlignment', 'Top')
      const mainAlign = vertical ? va : ha
      let cursor = startOffset
      if (flex === 'None' || free <= 0) {
        const extra = (vertical ? content.h : content.w) - total
        if (mainAlign === 'Center') cursor = extra / 2
        else if (mainAlign === 'Bottom' || mainAlign === 'Right') cursor = extra
      }
      items.forEach((c, i) => {
        const [sw, sh] = sizes[i]
        let x: number
        let y: number
        if (vertical) {
          y = content.y + cursor
          x = content.x + (ha === 'Center' ? (content.w - sw) / 2 : ha === 'Right' ? content.w - sw : 0)
          cursor += sh + gap + between
        } else {
          x = content.x + cursor
          y = content.y + (va === 'Center' ? (content.h - sh) / 2 : va === 'Bottom' ? content.h - sh : 0)
          cursor += sw + gap + between
        }
        this.place(c, x, y, sw, sh, frame, clip, visible)
        placed.add(c)
      })
      const contentW = vertical ? cross : total
      const contentH = vertical ? total : cross
      this.report(list, 'c', fmt(contentW * frame.k) + SEP + fmt(contentH * frame.k))
    } else if (grid) {
      const items = this.sortForLayout(kids.filter((c) => P.bool(c, 'Visible', true)), grid)
      const g = this.gridGeometry(grid, items.length, content.w, content.h)
      const ha = P.enm(grid, 'HorizontalAlignment', 'Left')
      const va = P.enm(grid, 'VerticalAlignment', 'Top')
      const offX = ha === 'Center' ? (content.w - g.contentW) / 2 : ha === 'Right' ? content.w - g.contentW : 0
      const offY = va === 'Center' ? (content.h - g.contentH) / 2 : va === 'Bottom' ? content.h - g.contentH : 0
      const corner = P.enm(grid, 'StartCorner', 'TopLeft')
      items.forEach((c, i) => {
        let col = g.horizontal ? i % g.perLine : Math.floor(i / g.perLine)
        let row = g.horizontal ? Math.floor(i / g.perLine) : i % g.perLine
        if (corner === 'TopRight' || corner === 'BottomRight') col = g.cols - 1 - col
        if (corner === 'BottomLeft' || corner === 'BottomRight') row = g.rows - 1 - row
        const x = content.x + offX + col * (g.cellW + g.padX)
        const y = content.y + offY + row * (g.cellH + g.padY)
        this.place(c, x, y, g.cellW, g.cellH, frame, clip, visible)
        placed.add(c)
      })
      this.report(grid, 'c', fmt(g.contentW * frame.k) + SEP + fmt(g.contentH * frame.k))
    }
    for (const c of kids) {
      if (placed.has(c)) continue
      const [sw, sh] = this.size(c, content.w, content.h)
      const pos = P.udim2(c, 'Position')
      const ap = P.vec2(c, 'AnchorPoint')
      const x = content.x + pos.xs * content.w + pos.xo - ap.x * sw
      const y = content.y + pos.ys * content.h + pos.yo - ap.y * sh
      this.place(c, x, y, sw, sh, frame, clip, visible && P.bool(c, 'Visible', true))
    }
  }
}

function fmt(n: number) {
  return Number.isInteger(n) ? String(n) : n.toFixed(3)
}
