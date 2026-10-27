// Captures the simulator at a given size: node scripts/dev/capture.mjs out.png [width] [height] [actions-json]
import { chromium } from 'playwright-core'
import { readdirSync } from 'node:fs'
import { homedir } from 'node:os'
const [out = '/tmp/cap.png', w = '1440', h = '900', actions = '[]'] = process.argv.slice(2)
const base = homedir() + '/.cache/ms-playwright/'
const dir = readdirSync(base).find((d) => d.startsWith('chromium-'))
const browser = await chromium.launch({ executablePath: `${base}${dir}/chrome-linux64/chrome`, args: ['--enable-features=WebAssemblyJSPromiseIntegration'] })
const page = await browser.newPage({ viewport: { width: +w, height: +h }, deviceScaleFactor: 2 })
page.on('console', (m) => { if (m.type() === 'error') console.log('console:', m.text()) })
page.on('pageerror', (e) => console.log('pageerror:', e.message))
await page.goto('http://localhost:5199/simulator/')
await page.waitForFunction(() => window.riftsim?.runtime.running && document.querySelectorAll('.rbx').length > 20, null, { timeout: 30000 })
await page.waitForTimeout(1200)
for (const a of JSON.parse(actions)) {
  if (a.click || a.clickText) {
    const box = await page.evaluate(([sel, txt]) => { const n = window.riftsim.runtime.scene; let best = null; for (const node of n.nodes.values()) if (node.rendered && (sel ? node.props.Name === sel : node.props.Text === txt)) best = { x: node.x, y: node.y, w: node.w, h: node.h }; return best }, [a.click, a.clickText])
    const st = await page.evaluate(() => { const r = document.getElementById('stage').getBoundingClientRect(); return { x: r.left, y: r.top, s: r.width / window.riftsim.runtime.layout.W } })
    if (box) await page.mouse.click(st.x + (box.x + box.w / 2) * st.s, st.y + (box.y + box.h / 2) * st.s)
    else console.log('no node', a.click || a.clickText)
  }
  if (a.key) await page.keyboard.press(a.key)
  if (a.run) await page.evaluate(async (src) => { const ed = document.querySelector('.cm-content'); window.riftsim.runtime.run && await window.riftsim.runtime.start(src, 'probe.lua') }, a.run)
  if (a.select) await page.selectOption(a.select[0], a.select[1])
  if (a.wait) await page.waitForTimeout(a.wait)
  if (a.eval) console.log(await page.evaluate(a.eval))
}
await page.waitForTimeout(600)
if (process.env.STAGE) {
  const el = await page.$('#frame')
  await el.screenshot({ path: out })
} else await page.screenshot({ path: out })
console.log('saved', out)
await browser.close()
