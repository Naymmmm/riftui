// Explorer tree, Properties panel and the executor workspace file list.

import { icon, type IconName } from './icons'
import { fontNote } from '../engine/text'
import { encode, isGuiObject, type Color, type EnumVal, type FontVal, type Kind, type Node, type Scene, type UDim, type UDim2, type Value, type Vec2 } from '../engine/scene'
import type { Vfs } from '../engine/vfs'

const CLASS_ICON: Record<string, IconName> = {
  DataModel: 'game',
  Frame: 'frame',
  CanvasGroup: 'group',
  TextLabel: 'text',
  TextButton: 'button',
  TextBox: 'input',
  ImageLabel: 'image',
  ImageButton: 'image',
  ScrollingFrame: 'scroll',
  UIListLayout: 'list',
  UIGridLayout: 'grid',
  UICorner: 'corner',
  UIStroke: 'stroke',
  UIPadding: 'padding',
  UIGradient: 'gradient',
  UIScale: 'scale',
  UISizeConstraint: 'constraint',
  UIAspectRatioConstraint: 'constraint',
  UITextSizeConstraint: 'constraint',
  ScreenGui: 'screen',
  Folder: 'folder',
  Player: 'player',
  Camera: 'camera',
  BindableEvent: 'event',
  Model: 'model',
}
const SERVICE_ORDER = ['Workspace', 'Players', 'Lighting', 'ReplicatedStorage', 'StarterGui', 'CoreGui']
const HIDDEN_SERVICES = new Set(['TweenService', 'UserInputService', 'RunService', 'HttpService', 'TextService', 'ContentProvider', 'GuiService', 'SoundService', 'Teams', 'Chat', 'TextChatService'])

const esc = (s: string) => s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]!)

function fmtNum(n: number) {
  if (!Number.isFinite(n)) return n > 0 ? 'inf' : n < 0 ? '-inf' : 'nan'
  return Number.isInteger(n) ? String(n) : String(+n.toFixed(3))
}

export function formatValue(kind: Kind, v: Value): string {
  switch (kind) {
    case 'b':
      return v ? 'true' : 'false'
    case 'n':
      return fmtNum(v as number)
    case 's':
      return String(v)
    case 'U2': {
      const u = v as UDim2
      return `{${fmtNum(u.xs)}, ${fmtNum(u.xo)}}, {${fmtNum(u.ys)}, ${fmtNum(u.yo)}}`
    }
    case 'U': {
      const u = v as UDim
      return `${fmtNum(u.s)}, ${fmtNum(u.o)}`
    }
    case 'V2': {
      const u = v as Vec2
      return `${fmtNum(u.x)}, ${fmtNum(u.y)}`
    }
    case 'C3': {
      const c = v as Color
      return [c.r, c.g, c.b].map((x) => Math.round(x * 255)).join(', ')
    }
    case 'E':
      return (v as EnumVal).name
    case 'F': {
      const f = v as FontVal
      const fam = /families\/(.+?)\.json$/.exec(f.family)?.[1] ?? f.family
      return `${fam} · ${f.weight}${f.style ? ' italic' : ''}`
    }
    case 'I':
      return v ? `#${(v as { ref: number }).ref}` : 'nil'
    case 'CS':
    case 'NS':
      return `${(v as unknown[]).length} keypoints`
    case 'x':
      return 'nil'
    default:
      return JSON.stringify(v)
  }
}

const GROUPS: Array<[string, RegExp]> = [
  ['Data', /^(Name|ClassName|Parent|Archivable|LayoutOrder|ZIndex|Enabled|DisplayOrder|Value|Active|Interactable|Selectable|Selected|Modal|GuiState)$/],
  ['Transform', /^(Position|Size|AnchorPoint|Rotation|SizeConstraint|AutomaticSize|Absolute.*)$/],
  ['Appearance', /^(Background.*|Border.*|Visible|ClipsDescendants|Group.*|Transparency|AutoButtonColor|Style)$/],
  ['Text', /^(Text.*|Font.*|RichText|LineHeight|MaxVisibleGraphemes|Placeholder.*|ClearTextOnFocus|MultiLine|ContentText|CursorPosition|SelectionStart|ShowNativeInput)$/],
  ['Image', /^(Image.*|ScaleType|Slice.*|TileSize|ResampleMode|IsLoaded|HoverImage|PressedImage)$/],
  ['Scrolling', /^(Canvas.*|ScrollBar.*|Scrolling.*|ElasticBehavior|.*ScrollBar.*|AutomaticCanvasSize|.*Image)$/],
]

export class Inspector {
  selected: number | null = null
  private open = new Set<number>()
  private lastStructure = -1
  private lastProps = -1
  private propsFor: number | null = null
  onSelect: (id: number | null) => void = () => {}
  onHover: (id: number | null) => void = () => {}
  onEdit: (id: number, prop: string, encoded: string) => void = () => {}

  constructor(
    private tree: HTMLElement,
    private props: HTMLElement,
    public scene: Scene,
  ) {
    tree.addEventListener('click', (e) => {
      const row = (e.target as HTMLElement).closest<HTMLElement>('.tree-row')
      if (!row) return
      const id = +row.dataset.id!
      if ((e.target as HTMLElement).closest('.tw')) {
        if (this.open.has(id)) this.open.delete(id)
        else this.open.add(id)
        this.lastStructure = -1
        this.refresh()
        return
      }
      this.select(id)
    })
    tree.addEventListener('mouseover', (e) => {
      const row = (e.target as HTMLElement).closest<HTMLElement>('.tree-row')
      this.onHover(row ? +row.dataset.id! : null)
    })
    tree.addEventListener('mouseleave', () => this.onHover(null))
  }

  reset(scene: Scene) {
    this.scene = scene
    this.selected = null
    this.open.clear()
    this.lastStructure = -1
    this.lastProps = -1
    this.propsFor = null
  }

  select(id: number | null, reveal = false) {
    this.selected = id
    if (reveal && id != null) {
      let p = this.scene.get(id)?.parent
      while (p) {
        this.open.add(p.id)
        p = p.parent
      }
    }
    this.lastStructure = -1
    this.lastProps = -1
    this.onSelect(id)
    this.refresh()
    if (reveal) this.tree.querySelector('.tree-row.sel')?.scrollIntoView({ block: 'nearest' })
  }

  refresh() {
    const s = this.scene
    if (s.structureVersion !== this.lastStructure) {
      this.lastStructure = s.structureVersion
      this.renderTree()
    }
    if (s.propVersion !== this.lastProps || this.propsFor !== this.selected) {
      this.lastProps = s.propVersion
      this.renderProps()
    }
  }

  private renderTree() {
    const root = this.scene.root()
    if (!root) {
      this.tree.innerHTML = '<div class="props empty" style="border:0">Run a script to see its instances.</div>'
      return
    }
    if (this.open.size === 0) {
      // first view: open the path down to the hub's ScreenGui
      this.open.add(root.id)
      for (const svc of root.children) if (svc.cls === 'CoreGui') {
        this.open.add(svc.id)
        for (const c of svc.children) this.open.add(c.id)
      }
    }
    const rows: string[] = []
    const visit = (n: Node, depth: number) => {
      const kids = depth === 0 ? this.sortedServices(n) : n.children
      const hasKids = kids.length > 0
      const isOpen = this.open.has(n.id)
      const hidden = isGuiObject(n) && n.props.Visible === false
      rows.push(
        `<div class="tree-row${this.selected === n.id ? ' sel' : ''}${hidden ? ' hidden' : ''}" data-id="${n.id}" style="padding-left:${6 + depth * 14}px">` +
          (hasKids ? `<button class="tw${isOpen ? ' open' : ''}" aria-label="${isOpen ? 'Collapse' : 'Expand'}">${icon('chevron')}</button>` : '<span class="tw"></span>') +
          `<span class="ci">${icon(CLASS_ICON[n.cls] ?? (n.cls.endsWith('Service') || depth === 1 ? 'service' : 'value'))}</span>` +
          `<span class="nm">${esc(String(n.props.Name ?? n.cls))}</span>` +
          (String(n.props.Name) !== n.cls ? `<span class="cls">${n.cls}</span>` : '') +
          '</div>',
      )
      if (hasKids && isOpen) for (const c of kids) visit(c, depth + 1)
    }
    visit(root, 0)
    this.tree.innerHTML = rows.join('')
  }

  private sortedServices(root: Node) {
    return root.children
      .filter((c) => !HIDDEN_SERVICES.has(c.cls))
      .sort((a, b) => {
        const ia = SERVICE_ORDER.indexOf(a.cls)
        const ib = SERVICE_ORDER.indexOf(b.cls)
        return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib)
      })
  }

  private renderProps() {
    this.propsFor = this.selected
    const n = this.selected != null ? this.scene.get(this.selected) : undefined
    if (!n) {
      this.props.innerHTML = '<div class="empty">Select an instance in the Explorer, or Alt-click it in the viewport.</div>'
      return
    }
    const focusedProp = (document.activeElement as HTMLElement | null)?.dataset?.prop
    if (focusedProp && this.props.contains(document.activeElement)) return
    const keys = Object.keys(n.props).sort()
    const grouped = new Map<string, string[]>()
    for (const k of keys) {
      const g = GROUPS.find(([, re]) => re.test(k))?.[0] ?? 'Behavior'
      if (!grouped.has(g)) grouped.set(g, [])
      grouped.get(g)!.push(k)
    }
    const order = ['Data', 'Transform', 'Appearance', 'Text', 'Image', 'Scrolling', 'Behavior']
    const html: string[] = []
    const note = fontNote(n.props.FontFace as FontVal | undefined)
    if (note) html.push(`<div class="note">${esc(note)}</div>`)
    for (const g of order) {
      const list = grouped.get(g)
      if (!list) continue
      html.push(`<div class="group">${g}</div>`)
      for (const k of list) html.push(this.propRow(n, k))
    }
    this.props.innerHTML = html.join('')
    for (const el of this.props.querySelectorAll<HTMLInputElement>('input[data-prop]')) {
      const prop = el.dataset.prop!
      const kind = n.kinds[prop]
      const commit = () => {
        let value: Value | null = null
        if (kind === 'b') value = el.checked
        else if (kind === 'n') value = parseFloat(el.value)
        else if (kind === 's') value = el.value
        else if (kind === 'C3') {
          const hex = el.value.replace('#', '')
          value = { r: parseInt(hex.slice(0, 2), 16) / 255, g: parseInt(hex.slice(2, 4), 16) / 255, b: parseInt(hex.slice(4, 6), 16) / 255 }
        } else if (kind === 'U2') {
          const nums = el.value.match(/-?\d*\.?\d+/g)?.map(Number)
          if (nums && nums.length === 4) value = { xs: nums[0], xo: nums[1], ys: nums[2], yo: nums[3] }
        } else if (kind === 'V2') {
          const nums = el.value.match(/-?\d*\.?\d+/g)?.map(Number)
          if (nums && nums.length === 2) value = { x: nums[0], y: nums[1] }
        }
        if (value === null || (typeof value === 'number' && Number.isNaN(value))) return
        this.onEdit(n.id, prop, encode(kind, value))
      }
      el.addEventListener(el.type === 'checkbox' || el.type === 'color' ? 'input' : 'change', commit)
      el.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') el.blur()
        e.stopPropagation()
      })
    }
  }

  private propRow(n: Node, k: string) {
    const kind = n.kinds[k] ?? 'x'
    const v = n.props[k]
    const ro = /^(ClassName|Absolute.*|TextBounds|TextFits|ContentText|GuiState|IsLoaded)$/.test(k)
    let control: string
    if (ro) control = `<span class="ro">${esc(formatValue(kind, v))}</span>`
    else if (kind === 'b') control = `<input type="checkbox" data-prop="${k}" ${v ? 'checked' : ''} aria-label="${k}">`
    else if (kind === 'n' || kind === 's' || kind === 'U2' || kind === 'V2')
      control = `<input type="text" data-prop="${k}" value="${esc(formatValue(kind, v))}" aria-label="${k}" spellcheck="false">`
    else if (kind === 'C3') {
      const c = v as Color
      const hex = '#' + [c.r, c.g, c.b].map((x) => Math.round(x * 255).toString(16).padStart(2, '0')).join('')
      control = `<input type="color" data-prop="${k}" value="${hex}" aria-label="${k}"><span>${formatValue(kind, v)}</span>`
    } else control = `<span>${esc(formatValue(kind, v))}</span>`
    return `<div class="prop"><span class="k" title="${k}">${k}</span><span class="v">${control}</span></div>`
  }
}

export function renderFiles(el: HTMLElement, vfs: Vfs) {
  const files = [...vfs.files.entries()].sort(([a], [b]) => a.localeCompare(b))
  if (files.length === 0) {
    el.innerHTML = '<div class="props empty" style="border:0">The executor workspace is empty. Files written with writefile appear here.</div>'
    return
  }
  const size = (b: number) => (b > 1024 * 1024 ? (b / 1024 / 1024).toFixed(1) + ' MB' : b > 1024 ? (b / 1024).toFixed(1) + ' KB' : b + ' B')
  el.innerHTML = files
    .map(([path, bytes]) => {
      const ic = /\.(png|jpe?g|webp)$/.test(path) ? icon('fileImage') : /\.(json|lua|luau|txt)$/.test(path) ? icon('fileCode') : icon('file')
      return `<div class="f" title="${esc(path)}">${ic}<span>${esc(path)}</span><span class="sz">${size(bytes.length)}</span></div>`
    })
    .join('')
}
