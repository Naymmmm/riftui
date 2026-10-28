// Browser coverage of the extended components, HUD, Players and translations.
// Uses the same Chromium fixture and Vite workflow as docs:images. Requires :5199.
import assert from 'node:assert/strict'
import { chromium } from 'playwright-core'
import { homedir } from 'node:os'
import { readdirSync, mkdirSync } from 'node:fs'
const base = homedir() + '/.cache/ms-playwright/'
const dir = readdirSync(base).find(d => d.startsWith('chromium-'))
const browser = await chromium.launch({ executablePath: base + dir + '/chrome-linux64/chrome', args: ['--enable-features=WebAssemblyJSPromiseIntegration'] })
const page = await browser.newPage({ viewport: { width: 1000, height: 800 } })
const errors = []
page.on('pageerror', e => errors.push(e.message))
const out = '.impeccable/review/components'
mkdirSync(out, { recursive: true })
async function open(demo) {
  await page.goto('http://localhost:5199/docs/preview.html?demo=' + demo)
  await page.waitForFunction(() => document.body.dataset.ready === 'true')
  assert.notEqual(await page.locator('#loading').getAttribute('data-error'), 'true', await page.locator('#loading').textContent())
}
async function point(name, text) {
  return page.evaluate(({name,text}) => {
    const matches = [...window.docsPreview.runtime.scene.nodes.values()].filter(n => n.rendered && (name ? n.props.Name === name : n.cls === 'TextButton' && n.props.Text === text))
    const n = matches.find(n => n.cls === 'TextButton') || matches[0]
    if (!n) throw Error('Missing ' + (name || text))
    return { x: n.x, y: n.y, w: n.w, h: n.h }
  }, {name,text})
}
async function click(name, text) { const p = await point(name,text); await page.mouse.click(p.x+p.w/2,p.y+p.h/2); await page.waitForTimeout(250) }
async function textExists(text) { return page.evaluate(text => [...window.docsPreview.runtime.scene.nodes.values()].some(n => n.rendered && n.props.Text === text), text) }
async function exec(source) {
  await page.evaluate(async source => {
    const rt = window.docsPreview.runtime
    while (rt.busy) await new Promise(r => setTimeout(r, 5))
    await rt.run(source,'components-probe.lua')
  }, source)
  await page.waitForTimeout(200)
}
try {
  await open('stepper')
  await click('Increase')
  assert.match(await page.locator('#result').textContent(), /Burst:.*2/)
  await click('Decrease')
  assert.match(await page.locator('#result').textContent(), /Burst:.*1/)
  await open('segmented')
  const build = await page.evaluate(() => { const n = [...window.docsPreview.runtime.scene.nodes.values()].find(n => n.props.Text === 'Build'); return {x:n.x+n.w/2,y:n.y+n.h/2} })
  await page.mouse.click(build.x,build.y)
  await page.waitForTimeout(200)
  assert.match(await page.locator('#result').textContent(), /Mode:.*Build/)
  await open('range-slider')
  const hit = await point('Hit')
  await page.mouse.move(hit.x+hit.w*0.24,hit.y+hit.h/2)
  await page.mouse.down()
  await page.mouse.move(hit.x+hit.w*0.7,hit.y+hit.h/2,{steps:6})
  await page.mouse.up()
  await page.waitForTimeout(200)
  assert.match(await page.locator('#result').textContent(), /Delay:/)
  await open('progress')
  await click(null,'Use ammo')
  assert.match(await page.locator('#result').textContent(), /Ammo:.*23/)
  await open('stat')
  await click(null,'Earn 100')
  assert(await textExists('12,600 $'))
  assert(await textExists('+100 $'))
  await open('sparkline')
  await click(null,'Add sample')
  assert.match(await page.locator('#result').textContent(), /Sample:/)
  await click(null,'Clear graph')
  assert(await textExists('—'))
  await open('console')
  await click(null,'Write entry')
  assert(await page.evaluate(() => [...window.docsPreview.runtime.scene.nodes.values()].some(n => n.props.Name === 'Line' && n.props.Text?.endsWith('  Action completed'))))
  await click('ClearLog')
  assert(await textExists('Nothing logged yet'))
  await open('dependent-controls')
  const before = await point('GroupClip')
  await click('Check')
  const folded = await point('GroupClip')
  assert(folded.h < 2 && before.h > 30, 'Dependent group did not fold')
  await click('GroupHead')
  assert((await point('GroupClip')).h > 30, 'Group cannot be reopened manually')
  await open('player-picker')
  await click('Chip')
  assert(await textExists('@builderman'))
  await exec('local players=game:GetService("Players") local p=players:FindFirstChild("builderman") p.Parent=nil p.Name="LiveJoin" p.DisplayName="Live Join" p.Parent=players getgenv().LiveJoin=p')
  assert(await textExists('@LiveJoin'), 'Open roster did not update on join')
  await click('Player_LiveJoin')
  assert.match(await page.locator('#result').textContent(), /Player:.*LiveJoin/)
  await exec('getgenv().LiveJoin:Destroy()')
  assert(await textExists('Left the game'), 'Departed player remained selected')
  await open('overlays')
  await page.locator('#viewport').focus()
  await page.keyboard.press('f')
  await page.waitForTimeout(200)
  assert(await textExists('On'), 'Keybind overlay failed to track toggle')
  await page.screenshot({path:out+'/hud-desktop.png'})
  await page.setViewportSize({width:390,height:844})
  await page.waitForTimeout(300)
  const hud = await point('Watermark')
  assert(hud.x >= 0 && hud.x+hud.w <= 390, 'Watermark overflows mobile: ' + JSON.stringify(hud))
  await page.screenshot({path:out+'/hud-mobile.png'})
  await page.setViewportSize({width:1000,height:800})
  await open('tooltips')
  const slider = await point('Slider_Smoothing')
  await page.mouse.move(slider.x+15,slider.y+10)
  await page.waitForTimeout(600)
  assert(await textExists('Higher values move more slowly. Hover this control for help.'), 'Hover tooltip did not appear')
  await open('translations')
  assert(await textExists('Tecla de la barra'))
  await click(null,'English')
  assert(await textExists('Toolbar key'))
  await click(null,'Español')
  assert(await textExists('Tecla de la barra'))
  await page.screenshot({path:out+'/translations.png'})
  assert.deepEqual(errors, [])
  console.log('New control interactions, dependent group, roster join/leave, HUD state, tooltip, translations and mobile HUD passed')
} finally { await browser.close() }
