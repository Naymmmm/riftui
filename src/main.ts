import './style.css'
import exampleHub from '../examples/hub.luau?raw'
import { Runtime, type LogEntry } from './engine/runtime'
import { clearMeasureCache } from './engine/text'
import { Vfs } from './engine/vfs'
import { EXECUTORS, profileSpec } from './engine/executors'
import { createEditor } from './ui/editor'
import { drawBackdrop, type BackdropName } from './ui/backdrop'
import { icon } from './ui/icons'
import { Inspector, renderFiles } from './ui/inspector'

const MINIMAL = `-- The smallest RiftUI hub: one tab, one section, one toggle.
local Rift = loadstring(game:HttpGet("https://raw.githubusercontent.com/Naymmmm/riftui/main/public/Loader.luau"))()

local Hub = Rift:CreateHub({ Name = "My Hub" })
local Main = Hub:Tab({ Name = "Main", Icon = "house" })
local Section = Main:Section({ Name = "Hello" })
Section:Toggle({ Name = "Say hi", Callback = function(on)
	print("hi?", on)
end })
`

const EXAMPLES: Record<string, string> = { 'Example hub': exampleHub, 'Minimal hub': MINIMAL }
const VIEWPORTS: Record<string, [number, number, boolean]> = {
  'Responsive': [390, 600, true],
  '1920 × 1080': [1920, 1080, false],
  '1366 × 768': [1366, 768, false],
  '1280 × 720': [1280, 720, false],
  'Phone 390 × 844': [390, 844, true],
  'Phone 844 × 390': [844, 390, true],
}
const STORE = 'riftsim:script'
const initialScreen = matchMedia('(max-width: 720px)').matches ? 'Responsive' : '1280 × 720'

const app = document.getElementById('app')!
app.innerHTML = `
<header class="topbar">
  <div class="brand"><span class="mark"><i></i><i></i></span>RiftSim <small>RiftUI simulator</small></div>
  <a class="docs-link" href="/">Docs</a>
  <span class="sep"></span>
  <button class="btn primary" id="run" title="Run (Ctrl+Enter)">${icon('play')}Run<kbd>Ctrl ↵</kbd></button>
  <button class="btn icon" id="stop" title="Stop" aria-label="Stop">${icon('stop')}</button>
  <label class="field">Example<select id="example">${Object.keys(EXAMPLES).map((k) => `<option>${k}</option>`).join('')}</select></label>
  <span class="spacer"></span>
  <span class="stat" id="stat"><i class="status-dot"></i>stopped</span>
  <label class="field" title="Pretend to be a weaker executor; the next run uses it">Executor<select id="executor">${EXECUTORS.map((e) => `<option value="${e.id}">${e.label}</option>`).join('')}</select></label>
  <label class="field">Screen<select id="screen">${Object.keys(VIEWPORTS).map((k) => `<option ${k === initialScreen ? 'selected' : ''}>${k}</option>`).join('')}</select></label>
  <label class="field">Scene<select id="scene-select"><option value="day">Baseplate</option><option value="night">Night</option><option value="snow">Snow</option></select></label>
</header>
<main class="main">
  <section class="col left">
    <div class="pane-head"><span class="title">hub.lua</span><span class="spacer"></span><button class="tool" id="reset-script" title="Restore the selected example" aria-label="Restore example">${icon('reset')}</button></div>
    <div class="editor" id="editor"></div>
  </section>
  <section class="col center">
    <div class="vp-shell">
    <div class="viewport" id="viewport" tabindex="0" aria-label="Game viewport">
      <div class="stage-wrap" id="wrap">
      <div class="stage-frame" id="frame">
        <div class="stage" id="stage">
          <canvas class="backdrop" id="backdrop"></canvas>
          <div class="topbar-mock" aria-hidden="true"><span>${icon('menu')}</span><span>${icon('chat')}</span></div>
          <div class="rbx-root"></div>
          <div class="highlight hover" id="hl-hover"><span class="tag"></span></div>
          <div class="highlight" id="hl-sel"><span class="tag"></span></div>
          <div class="empty-stage" id="empty">Press Run to start the game</div>

        </div>
      </div>
      </div>
    </div>
    <div class="zoombar" role="group" aria-label="Zoom">
      <button class="zb" id="zoom-out" title="Zoom out (Ctrl −)" aria-label="Zoom out">${icon('zoomOut')}</button>
      <button class="zb pct" id="zoom-pct" title="Actual size (Ctrl 0)">100%</button>
      <button class="zb" id="zoom-in" title="Zoom in (Ctrl +)" aria-label="Zoom in">${icon('zoomIn')}</button>
      <span class="zsep"></span>
      <button class="zb fit" id="zoom-fit" title="Fit to window">Fit</button>
    </div>
        <div class="script-error" id="script-error" role="alert" hidden>
          <span class="se-icon">${icon('alert')}</span>
          <div class="se-body"><b id="se-title">Script error</b><code id="se-msg"></code><small>This happened outside <code>xpcall(…, Rift.HandleError)</code>, so RiftUI couldn't catch it.</small></div>
          <button class="btn" id="se-goto">Show line</button>
          <button class="se-x" id="se-close" aria-label="Dismiss">${icon('x')}</button>
        </div>
    </div>
    <div class="output">
      <div class="pane-head"><span class="title">Output</span><span class="count" id="c-warn" hidden></span><span class="count" id="c-err" hidden></span><span class="spacer"></span><button class="tool" id="clear-log" title="Clear output" aria-label="Clear output">${icon('eraser')}</button></div>
      <div class="log" id="log"></div>
    </div>
  </section>
  <section class="col inspector">
    <div class="pane-head"><div class="tabs" role="tablist"><button class="tab" role="tab" aria-selected="true" data-tab="explorer">Explorer</button><button class="tab" role="tab" aria-selected="false" data-tab="files">Workspace files</button></div><span class="spacer"></span><button class="tool" id="reset-files" title="Delete all workspace files" aria-label="Delete workspace files" hidden>${icon('trash')}</button></div>
    <div class="explorer" id="tree"></div>
    <div class="files" id="files" hidden></div>
    <div class="pane-head" id="props-head"><span class="title">Properties</span></div>
    <div class="props" id="props"></div>
  </section>
</main>`

const $ = <T extends HTMLElement>(id: string) => document.getElementById(id) as T
const viewportEl = $('viewport')
const frameEl = $('frame')
const stage = $('stage')
const backdrop = $<HTMLCanvasElement>('backdrop')
const logEl = $('log')

let [vw, vh, touch] = VIEWPORTS[initialScreen]
let scale = 1
let backdropName: BackdropName = 'day'

const vfs = new Vfs()
const runtime = new Runtime(stage, viewportEl, vfs, () => scale)
const EXEC_STORE = 'riftsim:executor'
function setExecutor(id: string) {
  const p = EXECUTORS.find((e) => e.id === id) ?? EXECUTORS[0]
  runtime.profile = profileSpec(p)
  localStorage.setItem(EXEC_STORE, p.id)
  $<HTMLSelectElement>('executor').value = p.id
  return p
}
setExecutor(localStorage.getItem(EXEC_STORE) ?? 'full')

// zoom: 'fit' follows the pane; a number is a fixed scale you can pan around
let zoom: 'fit' | number = 'fit'
const ZOOM_STEPS = [0.25, 0.33, 0.5, 0.67, 0.75, 0.9, 1, 1.25, 1.5, 2, 2.5, 3, 4]
function fitScale() {
  const pad = $<HTMLSelectElement>('screen').value === 'Responsive' ? 12 : 24
  const r = viewportEl.getBoundingClientRect()
  return Math.max(0.1, Math.min((r.width - pad * 2) / vw, (r.height - pad * 2) / vh, 1.5))
}
function fit() {
  if ($<HTMLSelectElement>('screen').value === 'Responsive') {
    const r = viewportEl.getBoundingClientRect()
    const w = Math.max(280, Math.floor(r.width - 24))
    const h = Math.max(240, Math.floor(r.height - 24))
    if (w !== vw || h !== vh) {
      vw = w; vh = h
      runtime.setViewport(vw, vh, touch)
      drawBackdrop(backdrop, vw, vh, backdropName)
    }
  }
  scale = zoom === 'fit' ? fitScale() : zoom
  frameEl.style.width = vw * scale + 'px'
  frameEl.style.height = vh * scale + 'px'
  stage.style.width = vw + 'px'
  stage.style.height = vh + 'px'
  stage.style.transform = `scale(${scale})`
  $('zoom-pct').textContent = Math.round(scale * 100) + '%'
  $('zoom-fit').classList.toggle('on', zoom === 'fit')
  viewportEl.classList.toggle('zoomed', zoom !== 'fit')
}
// zoom keeping the point under (clientX, clientY) fixed
function setZoom(next: 'fit' | number, clientX?: number, clientY?: number) {
  const r = stage.getBoundingClientRect()
  const vr = viewportEl.getBoundingClientRect()
  const cx = clientX ?? vr.left + vr.width / 2
  const cy = clientY ?? vr.top + vr.height / 2
  const simX = (cx - r.left) / scale
  const simY = (cy - r.top) / scale
  zoom = next === 'fit' ? 'fit' : Math.min(4, Math.max(0.25, next))
  fit()
  const r2 = stage.getBoundingClientRect()
  viewportEl.scrollLeft += r2.left + simX * scale - cx
  viewportEl.scrollTop += r2.top + simY * scale - cy
}
function stepZoom(dir: 1 | -1, cx?: number, cy?: number) {
  const cur = scale
  const next = dir > 0 ? ZOOM_STEPS.find((z) => z > cur + 0.001) ?? 4 : [...ZOOM_STEPS].reverse().find((z) => z < cur - 0.001) ?? 0.25
  setZoom(next, cx, cy)
}
new ResizeObserver(() => fit()).observe(viewportEl)

function setViewport(key: string) {
  ;[vw, vh, touch] = VIEWPORTS[key]
  fit()
  drawBackdrop(backdrop, vw, vh, backdropName)
  runtime.setViewport(vw, vh, touch)
}

// ---- output -------------------------------------------------------------
let warnCount = 0
let errCount = 0
const t0 = performance.now()
// Errors RiftUI never sees (syntax errors, code outside xpcall, crashed threads) get a banner
// over the game and a marked line in the editor.
let errorLineNo: number | null = null
function showScriptError(text: string) {
  const m = /(?:^|\s)[\w.-]+\.lua:(\d+):\s*(.*)$/s.exec(text)
  errorLineNo = m ? +m[1] : null
  const compile = /^(?:Expected|Incomplete|Malformed|Unexpected|Cannot)|expected/.test(m ? m[2] : text)
  $('se-title').textContent = (compile ? "Script didn't compile" : 'Script error') + (errorLineNo ? ` · line ${errorLineNo}` : '')
  $('se-msg').textContent = (m ? m[2] : text).replace(/^runtime error: /, '').split('\n')[0]
  $('se-goto').hidden = errorLineNo == null
  $('script-error').hidden = false
  editor.markError(errorLineNo)
}
function hideScriptError() {
  $('script-error').hidden = true
  editor.markError(null)
}
function addLog(e: LogEntry) {
  if (e.level === 'error' && !/^host sync|^input dispatch/.test(e.text)) showScriptError(e.text)
  if (logEl.querySelector('.none')) logEl.innerHTML = ''
  const stick = logEl.scrollTop + logEl.clientHeight >= logEl.scrollHeight - 4
  const row = document.createElement('div')
  row.className = 'row ' + e.level
  const secs = ((e.time - t0) / 1000).toFixed(2).padStart(7, ' ')
  const t = document.createElement('span')
  t.className = 't'
  t.textContent = secs
  const m = document.createElement('span')
  m.className = 'm'
  if (e.trace) {
    const d = document.createElement('details')
    const s = document.createElement('summary')
    s.textContent = e.text
    const pre = document.createElement('pre')
    pre.textContent = e.trace
    d.append(s, pre)
    m.append(d)
  } else m.textContent = e.text
  row.append(t, m)
  logEl.append(row)
  while (logEl.childElementCount > 1000) logEl.firstElementChild?.remove()
  if (stick) logEl.scrollTop = logEl.scrollHeight
  if (e.level === 'warn') warnCount++
  if (e.level === 'error') errCount++
  const cw = $('c-warn')
  const ce = $('c-err')
  cw.hidden = warnCount === 0
  ce.hidden = errCount === 0
  cw.className = 'count warn'
  ce.className = 'count error'
  cw.textContent = `${warnCount} warning${warnCount === 1 ? '' : 's'}`
  ce.textContent = `${errCount} error${errCount === 1 ? '' : 's'}`
}
function clearLog() {
  warnCount = errCount = 0
  logEl.innerHTML = '<div class="none">Output from print, warn and errors appears here.</div>'
  $('c-warn').hidden = true
  $('c-err').hidden = true
}
clearLog()
runtime.onLog = addLog
$('se-close').onclick = hideScriptError
$('se-goto').onclick = () => {
  editor.markError(errorLineNo)
  editor.view.focus()
}
$('clear-log').onclick = clearLog

// ---- inspector & highlight -------------------------------------------------
const inspector = new Inspector($('tree'), $('props'), runtime.scene)
inspector.onEdit = (id, prop, enc) => runtime.editProperty(id, prop, enc)
let hoverId: number | null = null
inspector.onHover = (id) => {
  hoverId = id
  drawHighlights()
}
inspector.onSelect = () => drawHighlights()

function placeHighlight(el: HTMLElement, id: number | null) {
  const n = id != null ? runtime.scene.get(id) : undefined
  if (!n || !n.rendered || n.w <= 0) {
    el.style.display = 'none'
    return
  }
  el.style.display = 'block'
  el.style.left = n.x + 'px'
  el.style.top = n.y + 'px'
  el.style.width = n.w + 'px'
  el.style.height = n.h + 'px'
  const tag = el.querySelector('.tag') as HTMLElement
  tag.textContent = `${n.props.Name ?? n.cls} · ${Math.round(n.w)}×${Math.round(n.h)}`
  tag.style.top = n.y < 20 ? '100%' : ''
  tag.style.bottom = n.y < 20 ? 'auto' : ''
  tag.style.marginTop = n.y < 20 ? '3px' : ''
}
function drawHighlights() {
  placeHighlight($('hl-sel'), inspector.selected)
  placeHighlight($('hl-hover'), hoverId !== inspector.selected ? hoverId : null)
}
// Alt-click in the viewport selects the topmost GuiObject under the cursor
viewportEl.addEventListener(
  'pointerdown',
  (e) => {
    if (!e.altKey) return
    e.stopImmediatePropagation()
    e.preventDefault()
    const r = stage.getBoundingClientRect()
    const hit = runtime.input.stackAt((e.clientX - r.left) / scale, (e.clientY - r.top) / scale)[0]
    if (hit) inspector.select(hit.id, true)
  },
  { capture: true },
)

// zoom controls: Ctrl/⌘ + wheel at the cursor, buttons, Ctrl +/−/0; Space- or middle-drag pans
viewportEl.addEventListener(
  'wheel',
  (e) => {
    if (!(e.ctrlKey || e.metaKey)) return
    e.preventDefault()
    e.stopImmediatePropagation()
    setZoom(scale * Math.exp(-e.deltaY * 0.0022), e.clientX, e.clientY)
  },
  { capture: true, passive: false },
)
$('zoom-in').onclick = () => stepZoom(1)
$('zoom-out').onclick = () => stepZoom(-1)
$('zoom-pct').onclick = () => setZoom(1)
$('zoom-fit').onclick = () => setZoom('fit')
let spaceHeld = false
let pan: { x: number; y: number; sl: number; st: number } | null = null
viewportEl.addEventListener(
  'keydown',
  (e) => {
    if ((e.ctrlKey || e.metaKey) && (e.key === '=' || e.key === '+')) stepZoom(1)
    else if ((e.ctrlKey || e.metaKey) && e.key === '-') stepZoom(-1)
    else if ((e.ctrlKey || e.metaKey) && e.key === '0') setZoom('fit')
    else if (e.code === 'Space' && zoom !== 'fit') {
      spaceHeld = true
      viewportEl.classList.add('panning')
    } else return
    e.preventDefault()
    e.stopImmediatePropagation()
  },
  { capture: true },
)
viewportEl.addEventListener('keyup', (e) => {
  if (e.code === 'Space') {
    spaceHeld = false
    viewportEl.classList.remove('panning')
  }
}, { capture: true })
viewportEl.addEventListener(
  'pointerdown',
  (e) => {
    if (zoom === 'fit' || !(e.button === 1 || (spaceHeld && e.button === 0))) return
    e.preventDefault()
    e.stopImmediatePropagation()
    pan = { x: e.clientX, y: e.clientY, sl: viewportEl.scrollLeft, st: viewportEl.scrollTop }
    viewportEl.setPointerCapture(e.pointerId)
    viewportEl.classList.add('grabbing')
  },
  { capture: true },
)
viewportEl.addEventListener(
  'pointermove',
  (e) => {
    if (!pan) return
    e.stopImmediatePropagation()
    viewportEl.scrollLeft = pan.sl - (e.clientX - pan.x)
    viewportEl.scrollTop = pan.st - (e.clientY - pan.y)
  },
  { capture: true },
)
viewportEl.addEventListener(
  'pointerup',
  (e) => {
    if (!pan) return
    e.stopImmediatePropagation()
    pan = null
    viewportEl.classList.remove('grabbing')
  },
  { capture: true },
)

// inspector tabs
let filesTab = false
for (const tab of document.querySelectorAll<HTMLButtonElement>('.inspector .tab')) {
  tab.onclick = () => {
    filesTab = tab.dataset.tab === 'files'
    for (const t of document.querySelectorAll('.inspector .tab')) t.setAttribute('aria-selected', String(t === tab))
    $('tree').hidden = filesTab
    $('files').hidden = !filesTab
    $('reset-files').hidden = !filesTab
    if (filesTab) renderFiles($('files'), vfs)
  }
}
vfs.onChange = () => {
  if (filesTab) renderFiles($('files'), vfs)
}
$('reset-files').onclick = async () => {
  await vfs.reset()
  addLog({ level: 'info', text: 'Workspace cleared. The next run downloads RiftUI assets again.', time: performance.now() })
}

// ---- frame stats ----------------------------------------------------------
let frames = 0
let lastStat = performance.now()
runtime.onFrame = () => {
  frames++
  inspector.scene = runtime.scene
  inspector.refresh()
  drawHighlights()
  const now = performance.now()
  if (now - lastStat > 500) {
    const fps = Math.round((frames * 1000) / (now - lastStat))
    frames = 0
    lastStat = now
    $('stat').innerHTML = `<i class="status-dot on"></i>${fps} fps · step ${runtime.frameTime.toFixed(1)} ms · ${runtime.scene.nodes.size} instances`
  }
}

// ---- editor & run -----------------------------------------------------------
const saved = localStorage.getItem(STORE)
const editor = createEditor($('editor'), saved ?? exampleHub, () => run(), (s) => localStorage.setItem(STORE, s))

let runRequest = 0
async function run() {
  const request = ++runRequest
  $('empty').hidden = true
  hideScriptError()
  const exec = EXECUTORS.find((e) => e.id === localStorage.getItem(EXEC_STORE)) ?? EXECUTORS[0]
  clearLog()
  if (exec.id !== 'full') addLog({ level: 'info', text: `Pretending to be ${exec.label}: ${exec.off.length + exec.broken.length} executor globals are missing or broken this run.`, time: performance.now() })
  inspector.reset(runtime.scene)
  try {
    await runtime.start(editor.get(), 'hub.lua')
  } catch (error) {
    if (request === runRequest) addLog({ level: 'error', text: 'Run failed: ' + String(error), trace: error instanceof Error ? error.stack : undefined, time: performance.now() })
    return
  }
  if (request !== runRequest) return
  inspector.reset(runtime.scene)
  viewportEl.focus({ preventScroll: true })
}
async function stop() {
  const request = ++runRequest
  await runtime.stop()
  if (request !== runRequest) return
  $('empty').hidden = false
  $('stat').innerHTML = '<i class="status-dot"></i>stopped'
  inspector.reset(runtime.scene)
  inspector.refresh()
}
$('run').onclick = () => run()
$('stop').onclick = () => stop()
$('reset-script').onclick = () => editor.set(EXAMPLES[$<HTMLSelectElement>('example').value])
$<HTMLSelectElement>('example').onchange = (e) => {
  editor.set(EXAMPLES[(e.target as HTMLSelectElement).value])
  run()
}
$<HTMLSelectElement>('executor').onchange = (e) => {
  const p = setExecutor((e.target as HTMLSelectElement).value)
  void p
  run()
}
$<HTMLSelectElement>('screen').onchange = (e) => setViewport((e.target as HTMLSelectElement).value)
$<HTMLSelectElement>('scene-select').onchange = (e) => {
  backdropName = (e.target as HTMLSelectElement).value as BackdropName
  drawBackdrop(backdrop, vw, vh, backdropName)
}
window.addEventListener('keydown', (e) => {
  if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
    e.preventDefault()
    run()
  }
})

// ---- boot -------------------------------------------------------------------
;(async () => {
  try {
    await boot()
  } catch (e) {
    addLog({ level: 'error', text: 'Simulator failed to start: ' + String(e), trace: e instanceof Error ? e.stack : undefined, time: performance.now() })
  }
})()

async function boot() {
  fit()
  drawBackdrop(backdrop, vw, vh, backdropName)
  runtime.setViewport(vw, vh, touch)
  const settle = (p: Promise<unknown>) => Promise.race([p, new Promise((r) => setTimeout(r, 2500))])
  await Promise.all([settle(vfs.load()), settle(document.fonts.load('400 13px Inter')), settle(document.fonts.load('600 13px Inter')), settle(document.fonts.load('500 12px "Roboto Mono"'))])
  clearMeasureCache()
  document.fonts.addEventListener('loadingdone', () => {
    clearMeasureCache()
    runtime.forceRender()
  })
  inspector.refresh()
  await run()
}

// handy for poking at the simulator from devtools
;(window as unknown as { riftsim: unknown }).riftsim = { runtime, run, stop, vfs }
