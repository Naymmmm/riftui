// Font mapping and text measurement. Roblox font families resolve to web faces; where
// Roblox's face isn't freely available the closest open face stands in, and fontNote()
// says so in the Properties panel.

import type { FontVal } from './scene'

const EXACT: Record<string, string> = {
  'rbxassetid://12187365364': 'Inter',
  SourceSansPro: '"Source Sans 3"',
  RobotoMono: '"Roboto Mono"',
  Roboto: 'Roboto',
  RobotoCondensed: '"Roboto Condensed"',
  Ubuntu: 'Ubuntu',
  Montserrat: 'Montserrat',
  Inconsolata: 'Inconsolata',
  Arimo: 'Arimo',
  Nunito: 'Nunito',
  Oswald: 'Oswald',
  Michroma: 'Michroma',
  Jura: 'Jura',
  TitilliumWeb: '"Titillium Web"',
  PressStart2P: '"Press Start 2P"',
  FredokaOne: '"Fredoka"',
  Merriweather: 'Merriweather',
}
const SUBSTITUTE: Record<string, [string, string]> = {
  BuilderSans: ['Inter', 'Builder Sans is shown as Inter'],
  GothamSSm: ['Montserrat', 'Gotham is shown as Montserrat'],
  LegacyArial: ['Arimo', 'Arial is shown as Arimo'],
  Arial: ['Arimo', 'Arial is shown as Arimo'],
}

function familyKey(family: string): string {
  const m = /families\/(.+?)\.json$/.exec(family)
  return m ? m[1] : family
}

export function cssFamily(font: FontVal | undefined): string {
  if (!font) return 'Inter'
  const key = familyKey(font.family)
  return (EXACT[key] ?? SUBSTITUTE[key]?.[0] ?? 'Inter') + ', Inter, system-ui, sans-serif'
}

export function fontNote(font: FontVal | undefined): string | null {
  if (!font) return null
  const key = familyKey(font.family)
  if (EXACT[key]) return null
  if (SUBSTITUTE[key]) return SUBSTITUTE[key][1]
  if (font.family.startsWith('rbxassetid://')) return `Store font ${font.family} isn't available in the simulator; shown as Inter`
  return `${key} isn't bundled; shown as Inter`
}

// Roblox rich text → HTML. Supports b, i, u, s, br, font(color,size,face,weight,transparency), stroke ignored.
const ESC: Record<string, string> = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }
export function escapeHtml(s: string) {
  return s.replace(/[&<>"]/g, (c) => ESC[c])
}
export function richToHtml(src: string): string {
  let out = ''
  const re = /<(\/?)(\w+)([^>]*)>|([^<]+)|(<)/g
  const stack: string[] = []
  let m: RegExpExecArray | null
  while ((m = re.exec(src))) {
    if (m[4] !== undefined || m[5] !== undefined) {
      const raw = m[4] ?? m[5]
      out += escapeHtml(raw.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&amp;/g, '&'))
      continue
    }
    const closing = m[1] === '/'
    const tag = m[2].toLowerCase()
    const attrs = m[3]
    if (tag === 'br') {
      out += '<br>'
      continue
    }
    if (closing) {
      const i = stack.lastIndexOf(tag)
      if (i >= 0) {
        while (stack.length > i) {
          stack.pop()
          out += '</span>'
        }
      }
      continue
    }
    const style: string[] = []
    if (tag === 'b') style.push('font-weight:700')
    else if (tag === 'i') style.push('font-style:italic')
    else if (tag === 'u') style.push('text-decoration:underline')
    else if (tag === 's') style.push('text-decoration:line-through')
    else if (tag === 'uc' || tag === 'uppercase') style.push('text-transform:uppercase')
    else if (tag === 'sc' || tag === 'smallcaps') style.push('font-variant:small-caps')
    else if (tag === 'font') {
      const attr = (name: string) => new RegExp(`${name}\\s*=\\s*["']([^"']*)["']`, 'i').exec(attrs)?.[1]
      const color = attr('color')
      if (color) {
        const rgb = /rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)/i.exec(color)
        style.push('color:' + (rgb ? `rgb(${rgb[1]},${rgb[2]},${rgb[3]})` : color))
      }
      const size = attr('size')
      if (size) style.push(`font-size:${parseFloat(size)}px`)
      const weight = attr('weight')
      if (weight) {
        const map: Record<string, number> = { thin: 100, extralight: 200, light: 300, regular: 400, medium: 500, semibold: 600, bold: 700, extrabold: 800, heavy: 900 }
        style.push(`font-weight:${map[weight.toLowerCase()] ?? parseInt(weight)}`)
      }
      const tr = attr('transparency')
      if (tr) style.push(`opacity:${1 - parseFloat(tr)}`)
    } else if (tag === 'stroke' || tag === 'mark') {
      // accepted, not drawn
    } else {
      out += escapeHtml(m[0])
      continue
    }
    stack.push(tag)
    out += `<span style="${style.join(';')}">`
  }
  while (stack.pop()) out += '</span>'
  return out
}

export function stripRich(src: string) {
  return src.replace(/<br\s*\/?>/gi, '\n').replace(/<[^>]+>/g, '').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&')
}

// --- measurement ---------------------------------------------------------
let probe: HTMLDivElement | null = null
const cache = new Map<string, [number, number]>()

function getProbe() {
  if (!probe) {
    probe = document.createElement('div')
    probe.style.cssText = 'position:absolute;left:-10000px;top:0;visibility:hidden;white-space:pre;contain:layout style'
    document.body.appendChild(probe)
  }
  return probe
}

export function clearMeasureCache() {
  cache.clear()
}

export interface MeasureOpts {
  text: string
  size: number
  font: FontVal | undefined
  width: number // 0 = no wrapping
  rich: boolean
  lineHeight: number
}

export function measure(o: MeasureOpts): [number, number] {
  const key = `${o.size}|${o.font?.family}|${o.font?.weight}|${o.font?.style}|${o.width}|${o.rich ? 1 : 0}|${o.lineHeight}|${o.text}`
  const hit = cache.get(key)
  if (hit) return hit
  const el = getProbe()
  el.style.fontFamily = cssFamily(o.font)
  el.style.fontWeight = String(o.font?.weight ?? 400)
  el.style.fontStyle = o.font?.style ? 'italic' : 'normal'
  el.style.fontSize = o.size + 'px'
  el.style.lineHeight = o.size * Math.max(1.2, o.lineHeight) + 'px'
  if (o.width > 0) {
    el.style.whiteSpace = 'pre-wrap'
    el.style.overflowWrap = 'break-word'
    el.style.width = o.width + 'px'
    el.style.display = 'block'
  } else {
    el.style.whiteSpace = 'pre'
    el.style.width = 'auto'
    el.style.display = 'inline-block'
  }
  if (o.rich) el.innerHTML = richToHtml(o.text)
  else el.textContent = o.text
  let w: number
  let h: number
  if (o.text === '') {
    w = 0
    h = o.size * Math.max(1.2, o.lineHeight)
  } else if (o.width > 0) {
    // shrink-wrap: width of the longest rendered line
    const range = document.createRange()
    range.selectNodeContents(el)
    const rects = range.getClientRects()
    let maxRight = 0
    const left = el.getBoundingClientRect().left
    for (const r of rects) maxRight = Math.max(maxRight, r.right - left)
    w = Math.min(o.width, Math.ceil(maxRight))
    h = el.getBoundingClientRect().height
  } else {
    const r = el.getBoundingClientRect()
    w = Math.ceil(r.width)
    h = r.height
  }
  const res: [number, number] = [w, Math.round(h)]
  if (cache.size > 5000) cache.clear()
  cache.set(key, res)
  return res
}
