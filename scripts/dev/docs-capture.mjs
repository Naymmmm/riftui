// Generate real library screenshots and check all documentation examples.
// Run with Vite on :5199: node scripts/dev/docs-capture.mjs
import { chromium } from 'playwright-core'
import { readdirSync, readFileSync, mkdirSync, writeFileSync, rmSync } from 'node:fs'
import { homedir } from 'node:os'
import { execFileSync } from 'node:child_process'

const base = homedir() + '/.cache/ms-playwright/'
const dir = readdirSync(base).find(d => d.startsWith('chromium-'))
if (!dir) throw new Error('Install the repository’s Playwright Chromium before capturing docs.')
const browser = await chromium.launch({ executablePath: base + dir + '/chrome-linux64/chrome', args: ['--enable-features=WebAssemblyJSPromiseIntegration'] })
const page = await browser.newPage({ viewport: { width: 660, height: 500 }, deviceScaleFactor: 2 })
const out = 'public/docs/images'
mkdirSync(out, { recursive: true })
const errors = []
const only = process.argv.find(a => a.startsWith('--only='))?.slice(7)
const provenance = only ? JSON.parse(readFileSync(out + '/provenance.json', 'utf8')).images.filter(i => i.file !== only + '.webp' && !(only === 'button' && i.file === 'button-clicked.webp')) : []
page.on('pageerror', e => errors.push(e.message))
async function open(demo, theme = 'Graphite') {
  await page.goto('http://localhost:5199/docs/preview.html?demo=' + demo + '&theme=' + theme)
  await page.waitForFunction(() => document.body.dataset.ready === 'true', null, { timeout: 30000 })
  await page.waitForTimeout(150)
  const failure = await page.locator('#loading').getAttribute('data-error')
  if (failure === 'true') throw new Error(demo + ': ' + await page.locator('#loading').innerText())
}
async function clickNode({ text, name }) {
  const point = await page.evaluate(({ text, name }) => {
    const rt = window.docsPreview.runtime
    const n = [...rt.scene.nodes.values()].find(n => n.rendered && (text ? n.cls === 'TextButton' && n.props.Text === text : n.props.Name === name && n.cls === 'TextButton'))
    if (!n) throw new Error('Missing demo control: ' + (text || name))
    return { x: n.x + n.w / 2, y: n.y + n.h / 2 }
  }, { text, name })
  await page.mouse.click(point.x, point.y, { delay: 80 })
  await page.waitForTimeout(700)
}
async function shot(file, demo, state = 'initial', theme = 'Graphite') {
  const png = out + '/' + file + '.png'
  const webp = out + '/' + file + '.webp'
  await page.screenshot({ path: png })
  const origin = 'Screenshot of actual RiftUI Luau rendered by RiftSim. Source: src/docs/demos.ts; demo=' + demo + '; state=' + state + '; theme=' + theme + '; route=/docs/preview.html. Captured using scripts/dev/docs-capture.mjs.'
  execFileSync('magick', [png, '-set', 'comment', origin, '-quality', '92', webp])
  rmSync(png)
  writeFileSync(webp + '.json', JSON.stringify({ prompt: origin, source: 'Actual RiftUI screenshot; see provenance.json' }, null, 2) + '\n')
  provenance.push({ file: file + '.webp', origin, cssWidth: 660, cssHeight: 500, pixelRatio: 2 })
}
try {
  for (const demo of ['overview', 'button', 'toggle', 'slider', 'dropdown', 'input', 'keybind', 'color-picker', 'content', 'themes', 'notifications', 'setup', 'configs', 'pins', 'command-palette',"range-slider","progress","stat","sparkline","segmented","stepper","console","player-picker","dependent-controls","overlays","tooltips","translations","encrypted-configs","requirements","stealth"]) {
    if (only && only !== demo) continue
    await open(demo)
    if (demo === 'dropdown') await clickNode({ name: 'Chip' })
    if (demo === 'color-picker') await clickNode({ name: 'Swatch' })
    if (demo === 'notifications') await clickNode({ text: 'Show notification' })
    if (demo === 'pins') await clickNode({ text: 'Pin movement' })
    if (demo === 'player-picker') await clickNode({ name: 'Chip' })
    if (demo === 'stat') await clickNode({ text: 'Earn 100' })
    if (demo === 'tooltips') {
      const p = await page.evaluate(() => { const n = [...window.docsPreview.runtime.scene.nodes.values()].find(n => n.props.Name === 'Slider_Smoothing'); return {x:n.x+12,y:n.y+10} })
      await page.mouse.move(p.x,p.y)
      await page.waitForTimeout(600)
    }
    await shot(demo, demo, ['dropdown', 'color-picker', 'notifications', 'pins'].includes(demo) ? 'opened' : 'initial')
    if (demo === 'button') {
      await clickNode({ text: 'Run action' })
      const result = await page.locator('#result').innerText()
      if (!/Button callback:\s*1/.test(result)) throw new Error('Button callback did not fire once: ' + result)
      await shot('button-clicked', demo, 'one click')
    }
  }
  for (const theme of ['Graphite', 'Ink', 'Slate', 'Ember']) {
    if (only && only !== 'themes') continue
    await open('themes', theme)
    await shot('theme-' + theme.toLowerCase(), 'themes', 'initial', theme)
  }
  if (errors.length) throw new Error(errors.join('\n'))
  writeFileSync(out + '/provenance.json', JSON.stringify({ source: 'Actual library screenshots, not generated mockups', images: provenance }, null, 2) + '\n')
  console.log('Captured ' + provenance.length + ' images; requested examples loaded; button callback verified when captured.')
} finally {
  await browser.close()
}
