import { Runtime } from '../engine/runtime'
import { Vfs } from '../engine/vfs'
import { clearMeasureCache } from '../engine/text'
import { demoNames, demoSource, type DemoName } from './demos'
import './preview.css'

const viewport = document.getElementById('viewport')!
const stage = document.getElementById('stage')!
const result = document.getElementById('result')!
const loading = document.getElementById('loading')!
const params = new URLSearchParams(location.search)
const candidate = params.get('demo') as DemoName
const demo = demoNames.includes(candidate) ? candidate : 'overview'
const runtime = new Runtime(stage, viewport, new Vfs(), () => 1)
let booted = false
let starting = false
runtime.onLog = (e) => {
  if (e.level === 'info') return
  result.textContent = e.text
  result.dataset.level = e.level
  if (e.level === 'error') { loading.textContent = e.text; loading.dataset.error = 'true' }
  parent.postMessage({ type: 'rift-docs-output', demo, level: e.level, text: e.text }, location.origin)
}
function resize() {
  const width = Math.max(280, viewport.clientWidth)
  const height = Math.max(300, viewport.clientHeight)
  stage.style.width = width + 'px'
  stage.style.height = height + 'px'
  runtime.setViewport(width, height, matchMedia('(pointer: coarse)').matches)
}
new ResizeObserver(resize).observe(viewport)
async function start() {
  if (starting) return
  starting = true
  booted = false
  delete document.body.dataset.ready
  loading.hidden = false
  delete loading.dataset.error
  loading.textContent = 'Loading the Luau example…'
  try {
    await Promise.all([document.fonts.load('400 13px Inter'), document.fonts.load('700 9px Inter'), document.fonts.load('500 12px "Roboto Mono"')])
    clearMeasureCache()
    resize()
    await runtime.start(demoSource(demo, params.get('theme') || 'Graphite'), 'docs-' + demo + '.lua')
    await new Promise(r => setTimeout(r, 450))
    if (loading.dataset.error !== 'true') loading.hidden = true
    booted = true
    document.body.dataset.ready = 'true'
  } catch (error) {
    loading.textContent = 'Example failed to load: ' + String(error)
    loading.dataset.error = 'true'
  } finally { starting = false }
}
window.addEventListener('message', (e) => {
  if (e.origin !== location.origin || e.source !== parent) return
  if (e.data?.type === 'rift-docs-replay') void start()
  if (e.data?.type === 'rift-docs-theme' && booted && demo === 'themes') {
    const button = [...runtime.scene.nodes.values()].find(n => n.cls === 'TextButton' && n.props.Text === e.data.theme)
    if (button) { params.set('theme', e.data.theme); runtime.input.push('gb', button.id, 'MouseButton1Click') }
  }
})
window.addEventListener('pagehide', () => { void runtime.stop() })
;(window as unknown as { docsPreview: unknown }).docsPreview = { runtime, demo }
void start()
