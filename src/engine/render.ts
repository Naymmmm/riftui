// Draws the laid-out Instance tree as nested DOM, one element per GuiObject.
// Layout already resolved every box in screen pixels; each element is placed relative
// to its parent element so clipping and z-order nest the way Roblox's do.

import { cssFamily, escapeHtml, richToHtml } from './text'
import { isButton, isGuiObject, isImage, isText, P, type Color, type FontVal, type Keypoint, type Node, type NumKey, type Scene } from './scene'
import type { Layout } from './layout'
import type { Vfs } from './vfs'

interface Dom {
  el: HTMLDivElement
  bg: HTMLDivElement
  img?: HTMLDivElement
  tx?: HTMLDivElement
  kids: HTMLDivElement
  bar?: HTMLDivElement
  styleKey: Record<string, string>
}

const rgba = (c: Color, a = 1) => `rgba(${Math.round(c.r * 255)},${Math.round(c.g * 255)},${Math.round(c.b * 255)},${+a.toFixed(3)})`

function setStyle(d: Dom, el: HTMLElement, key: string, css: string) {
  if (d.styleKey[key] !== css) {
    d.styleKey[key] = css
    el.style.cssText = css
  }
}

function sampleNum(seq: NumKey[] | undefined, t: number): number {
  if (!seq || seq.length === 0) return 0
  if (t <= seq[0].t) return seq[0].v
  for (let i = 1; i < seq.length; i++) {
    if (t <= seq[i].t) {
      const a = seq[i - 1]
      const b = seq[i]
      const f = (t - a.t) / Math.max(b.t - a.t, 1e-6)
      return a.v + (b.v - a.v) * f
    }
  }
  return seq[seq.length - 1].v
}
function sampleColor(seq: Keypoint[] | undefined, t: number): Color {
  if (!seq || seq.length === 0) return { r: 1, g: 1, b: 1 }
  if (t <= seq[0].t) return seq[0]
  for (let i = 1; i < seq.length; i++) {
    if (t <= seq[i].t) {
      const a = seq[i - 1]
      const b = seq[i]
      const f = (t - a.t) / Math.max(b.t - a.t, 1e-6)
      return { r: a.r + (b.r - a.r) * f, g: a.g + (b.g - a.g) * f, b: a.b + (b.b - a.b) * f }
    }
  }
  return seq[seq.length - 1]
}

// UIGradient → CSS linear-gradient multiplied into a base colour and alpha.
function gradientCss(grad: Node, base: Color, baseAlpha: number): string {
  const cs = grad.props.Color as Keypoint[] | undefined
  const ns = grad.props.Transparency as NumKey[] | undefined
  const rot = P.num(grad, 'Rotation')
  const off = P.vec2(grad, 'Offset')
  const rad = (rot * Math.PI) / 180
  const shift = off.x * Math.cos(rad) + off.y * Math.sin(rad)
  const times = new Set<number>([0, 1])
  cs?.forEach((k) => times.add(k.t))
  ns?.forEach((k) => times.add(k.t))
  const stops = [...times]
    .sort((a, b) => a - b)
    .map((t) => {
      const c = sampleColor(cs, t)
      const a = baseAlpha * (1 - sampleNum(ns, t))
      return `${rgba({ r: c.r * base.r, g: c.g * base.g, b: c.b * base.b }, a)} ${((t + shift) * 100).toFixed(2)}%`
    })
  return `linear-gradient(${90 + rot}deg, ${stops.join(', ')})`
}

export class Renderer {
  private doms = new Map<number, Dom>()
  private guiEls = new Map<number, HTMLDivElement>()
  private warnedImages = new Set<string>()
  onImageWarning: (msg: string) => void = () => {}

  constructor(
    private root: HTMLElement,
    public scene: Scene,
    public layout: Layout,
    private vfs: Vfs,
  ) {}

  clear() {
    this.root.replaceChildren()
    this.doms.clear()
    this.guiEls.clear()
  }

  render() {
    const seen = new Set<number>()
    const guis = this.layout.renderedGuis
    guis.forEach((gui, i) => {
      seen.add(gui.id)
      let el = this.guiEls.get(gui.id)
      if (!el) {
        el = document.createElement('div')
        el.className = 'rbx-gui'
        el.dataset.id = String(gui.id)
        this.guiEls.set(gui.id, el)
      }
      el.style.cssText = `position:absolute;left:0;top:0;width:100%;height:100%;pointer-events:none;z-index:${i + 1};display:${gui.rendered ? 'block' : 'none'}`
      if (el.parentElement !== this.root || this.root.children[i] !== el) this.root.insertBefore(el, this.root.children[i] ?? null)
      this.renderChildren(gui, el, gui.x, gui.y, seen)
    })
    for (const [id, el] of this.guiEls) if (!seen.has(id)) {
      el.remove()
      this.guiEls.delete(id)
    }
    for (const [id, d] of this.doms) if (!seen.has(id)) {
      d.el.remove()
      this.doms.delete(id)
    }
  }

  private renderChildren(parent: Node, container: HTMLElement, px: number, py: number, seen: Set<number>) {
    const kids = parent.children.filter(isGuiObject)
    // Sibling z-order: ZIndex, then child order
    kids.sort((a, b) => P.num(a, 'ZIndex', 1) - P.num(b, 'ZIndex', 1) || a.order - b.order)
    let i = 0
    for (const c of kids) {
      if (!c.rendered) continue
      const d = this.renderNode(c, px, py)
      seen.add(c.id)
      if (container.children[i] !== d.el) container.insertBefore(d.el, container.children[i] ?? null)
      i++
      this.renderChildren(c, d.kids, c.x, c.y, seen)
    }
    while (container.children.length > i) container.lastElementChild!.remove()
  }

  private dom(n: Node): Dom {
    let d = this.doms.get(n.id)
    if (!d) {
      const el = document.createElement('div')
      el.className = 'rbx'
      el.dataset.id = String(n.id)
      const bg = document.createElement('div')
      const kids = document.createElement('div')
      el.append(bg, kids)
      d = { el, bg, kids, styleKey: {} }
      this.doms.set(n.id, d)
    }
    return d
  }

  private renderNode(n: Node, px: number, py: number): Dom {
    const d = this.dom(n)
    const k = n.scale
    const rot = P.num(n, 'Rotation')
    const group = n.cls === 'CanvasGroup'
    const opacity = group ? 1 - P.num(n, 'GroupTransparency') : 1
    const cornerNode = this.scene.component(n, 'UICorner')
    let radius = 0
    if (cornerNode) {
      const cr = P.udim(cornerNode, 'CornerRadius')
      radius = Math.min(cr.s * Math.min(n.w, n.h) + cr.o * k, Math.min(n.w, n.h) / 2)
    }
    setStyle(
      d,
      d.el,
      'el',
      `position:absolute;left:${n.x - px}px;top:${n.y - py}px;width:${n.w}px;height:${n.h}px;` +
        (rot ? `transform:rotate(${rot}deg);` : '') +
        (opacity < 1 ? `opacity:${Math.max(0, opacity)};` : '') +
        `z-index:${P.num(n, 'ZIndex', 1)};`,
    )

    // background, border, stroke, gradient
    const bgT = P.num(n, 'BackgroundTransparency')
    const bgC = P.color(n, 'BackgroundColor3')
    const gradNode = this.scene.component(n, 'UIGradient')
    const grad = gradNode && P.bool(gradNode, 'Enabled', true) ? gradNode : undefined
    let bg = ''
    if (bgT < 1) bg = grad ? `background:${gradientCss(grad, bgC, 1 - bgT)};` : `background:${rgba(bgC, 1 - bgT)};`
    const shadows: string[] = []
    const bsp = P.num(n, 'BorderSizePixel')
    if (bsp > 0 && bgT < 1) shadows.push(`0 0 0 ${bsp * k}px ${rgba(P.color(n, 'BorderColor3'), 1 - bgT)}`)
    let textStroke = ''
    for (const s of n.children) {
      if (s.cls !== 'UIStroke' || !P.bool(s, 'Enabled', true)) continue
      const mode = P.enm(s, 'ApplyStrokeMode', 'Contextual')
      const t = P.num(s, 'Thickness', 1) * k
      const col = rgba(P.color(s, 'Color'), 1 - P.num(s, 'Transparency'))
      if (mode === 'Contextual' && isText(n)) textStroke = `-webkit-text-stroke:${t * 2}px ${col};paint-order:stroke fill;`
      else shadows.push(`0 0 0 ${t}px ${col}`)
    }
    const pressState = isButton(n) && P.bool(n, 'AutoButtonColor', true) ? P.str(n, 'GuiState', 'Idle') : 'Idle'
    const filter = pressState === 'Press' ? 'filter:brightness(0.7);' : pressState === 'Hover' ? 'filter:brightness(0.85);' : ''
    setStyle(
      d,
      d.bg,
      'bg',
      `position:absolute;inset:0;border-radius:${radius}px;${bg}${shadows.length ? `box-shadow:${shadows.join(',')};` : ''}${filter}`,
    )

    // children clip container (Roblox clips rectangularly, CanvasGroup clips with its corners)
    const clips = P.bool(n, 'ClipsDescendants') || n.cls === 'ScrollingFrame' || group
    setStyle(d, d.kids, 'kids', `position:absolute;left:0;top:0;width:${n.w}px;height:${n.h}px;${clips ? 'overflow:hidden;' : ''}${group && radius ? `border-radius:${radius}px;` : ''}`)

    if (isImage(n)) this.renderImage(n, d, radius)
    else if (d.img) {
      d.img.remove()
      d.img = undefined
    }
    if (isText(n)) this.renderText(n, d, textStroke, grad)
    else if (d.tx) {
      d.tx.remove()
      d.tx = undefined
    }
    if (n.cls === 'ScrollingFrame') this.renderScrollbar(n, d)
    return d
  }

  private renderScrollbar(n: Node, d: Dom) {
    const c = (n as Node & { canvas?: { h: number; winH: number; y: number; maxY: number; vScroll: boolean } }).canvas
    const t = P.num(n, 'ScrollBarThickness', 12) * n.scale
    if (!c || !c.vScroll || t <= 0) {
      d.bar?.remove()
      d.bar = undefined
      return
    }
    if (!d.bar) {
      d.bar = document.createElement('div')
      d.el.appendChild(d.bar)
    }
    const trackH = n.h
    const thumbH = Math.max(16, (c.winH / c.h) * trackH)
    const top = c.maxY > 0 ? (c.y / c.maxY) * (trackH - thumbH) : 0
    const col = rgba(P.color(n, 'ScrollBarImageColor3'), 1 - P.num(n, 'ScrollBarImageTransparency'))
    const left = P.enm(n, 'VerticalScrollBarPosition', 'Right') === 'Left'
    setStyle(d, d.bar, 'bar', `position:absolute;${left ? 'left' : 'right'}:0;top:${top}px;width:${t}px;height:${thumbH}px;background:${col};border-radius:${t / 2}px;z-index:100000;pointer-events:none`)
  }

  private resolveImage(id: string): string | null {
    if (!id) return null
    // Offline headshots for the simulator's sample roster; unknown avatars keep initials.
    const thumbnail = /^rbxthumb:\/\/type=AvatarHeadShot&id=(\d+)&/.exec(id)
    if (thumbnail) return new Set(['156', '261', '3', '31337', '48213', '77042']).has(thumbnail[1]) ? '/avatars/' + thumbnail[1] + '.png' : null
    const custom = /^rbxasset:\/\/riftsim\/(.+)$/.exec(id)
    if (custom) return this.vfs.assetUrl(custom[1])
    if (/^(https?:|data:|blob:)/.test(id)) return id
    if (!this.warnedImages.has(id)) {
      this.warnedImages.add(id)
      this.onImageWarning(`Image ${id} can't load in the simulator (only getcustomasset files and URLs can).`)
    }
    return null
  }

  private renderImage(n: Node, d: Dom, radius: number) {
    if (!d.img) {
      d.img = document.createElement('div')
      d.el.insertBefore(d.img, d.kids)
    }
    const url = this.resolveImage(P.str(n, 'Image'))
    const t = P.num(n, 'ImageTransparency')
    if (!url || t >= 1) {
      setStyle(d, d.img, 'img', 'display:none')
      return
    }
    const info = this.vfs.imageSize(url)
    const tint = P.color(n, 'ImageColor3')
    const tinted = tint.r < 0.999 || tint.g < 0.999 || tint.b < 0.999
    const scaleType = P.enm(n, 'ScaleType', 'Stretch')
    const rectOff = P.vec2(n, 'ImageRectOffset')
    const rectSize = P.vec2(n, 'ImageRectSize')
    let css = `position:absolute;inset:0;border-radius:${radius}px;opacity:${1 - t};`
    let bgImage = `url("${url}")`
    let layer = ''
    if (scaleType === 'Slice') {
      const sc = (n.props.SliceCenter as { x0: number; y0: number; x1: number; y1: number } | undefined) ?? { x0: 0, y0: 0, x1: 0, y1: 0 }
      const ss = P.num(n, 'SliceScale', 1) * n.scale
      const iw = info?.w ?? 0
      const ih = info?.h ?? 0
      const top = sc.y0
      const left = sc.x0
      const right = Math.max(0, iw - sc.x1)
      const bottom = Math.max(0, ih - sc.y1)
      css += `border-style:solid;border-color:transparent;border-image-source:${bgImage};border-image-slice:${top} ${right} ${bottom} ${left} fill;border-image-width:${top * ss}px ${right * ss}px ${bottom * ss}px ${left * ss}px;border-image-repeat:stretch;border-radius:0;`
      if (tinted) css += `filter:${tintFilter(tint)};`
      setStyle(d, d.img, 'img', css)
      return
    }
    if (rectSize.x > 0 && rectSize.y > 0 && info) {
      const sx = n.w / rectSize.x
      const sy = n.h / rectSize.y
      layer = `background-size:${info.w * sx}px ${info.h * sy}px;background-position:${-rectOff.x * sx}px ${-rectOff.y * sy}px;background-repeat:no-repeat;`
    } else if (scaleType === 'Fit') layer = 'background-size:contain;background-position:center;background-repeat:no-repeat;'
    else if (scaleType === 'Crop') layer = 'background-size:cover;background-position:center;background-repeat:no-repeat;'
    else if (scaleType === 'Tile') {
      const ts = P.udim2(n, 'TileSize')
      layer = `background-size:${ts.xs * n.w + ts.xo * n.scale}px ${ts.ys * n.h + ts.yo * n.scale}px;background-repeat:repeat;`
    } else layer = 'background-size:100% 100%;background-repeat:no-repeat;'
    if (P.enm(n, 'ResampleMode', 'Default') === 'Pixelated') css += 'image-rendering:pixelated;'
    if (tinted) {
      // multiply by ImageColor3 and keep the image's own alpha through a matching mask
      css += `background-image:${bgImage};background-color:${rgba(tint)};background-blend-mode:multiply;${layer}`
      css += `-webkit-mask-image:${bgImage};mask-image:${bgImage};` + layer.replace(/background-/g, '-webkit-mask-') + layer.replace(/background-/g, 'mask-')
    } else css += `background-image:${bgImage};${layer}`
    setStyle(d, d.img, 'img', css)
  }

  private renderText(n: Node, d: Dom, textStroke: string, grad: Node | undefined) {
    if (!d.tx) {
      d.tx = document.createElement('div')
      d.el.insertBefore(d.tx, d.kids)
    }
    const font = n.props.FontFace as FontVal | undefined
    let text = P.str(n, 'Text')
    let color = P.color(n, 'TextColor3')
    let alpha = 1 - P.num(n, 'TextTransparency')
    if (n.cls === 'TextBox' && text === '') {
      text = P.str(n, 'PlaceholderText')
      color = P.color(n, 'PlaceholderColor3')
    }
    if (n.dataset_editing) alpha = 0
    const pad = this.scene.component(n, 'UIPadding')
    let padCss = ''
    if (pad) {
      const s = n.scale
      const pv = (k: string, base: number) => {
        const v = P.udim(pad, k)
        return v.s * base + v.o * s
      }
      padCss = `padding:${pv('PaddingTop', n.h)}px ${pv('PaddingRight', n.w)}px ${pv('PaddingBottom', n.h)}px ${pv('PaddingLeft', n.w)}px;`
    }
    const xa = P.enm(n, 'TextXAlignment', 'Center')
    const ya = P.enm(n, 'TextYAlignment', 'Center')
    const wrapped = P.bool(n, 'TextWrapped') || P.bool(n, 'TextScaled')
    const truncate = P.enm(n, 'TextTruncate', 'None') !== 'None'
    const size = n.textSize || P.num(n, 'TextSize', 14) * n.scale
    const lh = size * Math.max(1.2, P.num(n, 'LineHeight', 1))
    const strokeT = P.num(n, 'TextStrokeTransparency', 1)
    let stroke = textStroke
    if (!stroke && strokeT < 1) stroke = `-webkit-text-stroke:2px ${rgba(P.color(n, 'TextStrokeColor3'), 1 - strokeT)};paint-order:stroke fill;`
    const justify = xa === 'Left' ? 'flex-start' : xa === 'Right' ? 'flex-end' : 'center'
    const align = ya === 'Top' ? 'flex-start' : ya === 'Bottom' ? 'flex-end' : 'center'
    let colorCss = `color:${rgba(color, alpha)};`
    if (grad) colorCss = `background:${gradientCss(grad, color, alpha)};-webkit-background-clip:text;background-clip:text;color:transparent;`
    const css =
      `position:absolute;inset:0;box-sizing:border-box;display:flex;justify-content:${justify};align-items:${align};${padCss}` +
      `font-family:${cssFamily(font)};font-weight:${font?.weight ?? 400};font-style:${font?.style ? 'italic' : 'normal'};font-size:${size}px;line-height:${lh}px;${colorCss}${stroke}` +
      `text-align:${xa === 'Left' ? 'left' : xa === 'Right' ? 'right' : 'center'};pointer-events:none;`
    setStyle(d, d.tx, 'tx', css)
    const inner =
      `<span style="display:block;max-width:100%;${wrapped ? 'white-space:pre-wrap;overflow-wrap:break-word;' : 'white-space:pre;'}${truncate ? 'overflow:hidden;text-overflow:ellipsis;white-space:pre;' : ''}">` +
      (P.bool(n, 'RichText') && !(n.cls === 'TextBox' && P.str(n, 'Text') === '') ? richToHtml(clip(text, n)) : escapeHtml(clip(text, n))) +
      '</span>'
    if (d.styleKey.txHtml !== inner) {
      d.styleKey.txHtml = inner
      d.tx.innerHTML = inner
    }
  }
}

function clip(text: string, n: Node) {
  const max = P.num(n, 'MaxVisibleGraphemes', -1)
  if (max < 0) return text
  return [...text].slice(0, max).join('')
}

// approximate multiply-by-colour for 9-slice images (border-image can't be masked)
function tintFilter(c: Color) {
  const l = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
  return `brightness(${l.toFixed(3)})`
}

declare module './scene' {
  interface Node {
    dataset_editing?: boolean
  }
}
