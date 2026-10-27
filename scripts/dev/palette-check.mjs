// Real Luau command-palette regressions. Requires Vite at localhost:5199.
import assert from 'node:assert/strict'
import { chromium } from 'playwright-core'
import { homedir } from 'node:os'
import { readdirSync, mkdirSync } from 'node:fs'
const base = homedir() + '/.cache/ms-playwright/'
const dir = readdirSync(base).find(d => d.startsWith('chromium-'))
const browser = await chromium.launch({ executablePath: base + dir + '/chrome-linux64/chrome', args: ['--enable-features=WebAssemblyJSPromiseIntegration'] })
const page = await browser.newPage({ viewport: { width: 1000, height: 760 } })
const errors = []
page.on('pageerror', e => errors.push(e.message))
async function nodePoint(name) {
  return page.evaluate(name => {
    const n = [...window.docsPreview.runtime.scene.nodes.values()].find(n => n.rendered && n.props.Name === name)
    if (!n) throw Error('Missing visible node ' + name)
    return { x: n.x + n.w / 2, y: n.y + n.h / 2, w: n.w, h: n.h }
  }, name)
}
async function click(name) { const p = await nodePoint(name); await page.mouse.click(p.x, p.y); await page.waitForTimeout(150) }
async function search(query) { await page.locator('.rbx-editor').fill(query); await page.waitForTimeout(180) }
async function results() {
  return page.evaluate(() => [...window.docsPreview.runtime.scene.nodes.values()].filter(n => n.props.Name === 'CommandResult').map(n => {
    return [...n.children].map(n => n.props.Text).filter(Boolean)
  }))
}
try {
  await page.goto('http://localhost:5199/docs/preview.html?demo=overview')
  await page.waitForFunction(() => document.body.dataset.ready === 'true')
  await page.evaluate(async () => {
    window.paletteLogs = []
    const rt = window.docsPreview.runtime
    rt.onLog = e => window.paletteLogs.push(e)
    await rt.start(`local Rift=loadstring(game:HttpGet("https://raw.githubusercontent.com/Naymmmm/riftui/main/public/Loader.luau"))()
local Hub=Rift:CreateHub({Name="Palette test",Id="palette-check",Setup=false})
local Tab=Hub:Tab({Name="Movement",Icon="footprints"})
local S=Tab:Section({Name="Movement",Side="Left"})
S:Toggle({Name="Sprint",Default=false,Callback=function() error("Palette changed a value") end})
S:Button({Name="Run action",Callback=function() error("Palette executed a callback") end})
local hidden=S:Button({Name="Secret control"}) hidden:SetVisible(false)
for i=1,30 do S:Slider({Name="Walk speed "..i,Min=1,Max=100,Default=20}) end
local Tools=Hub:Tab({Name="Tools",Icon="wrench"}) Tools:Section({Name="Tools"}):Button({Name="Run tool"})
Hub:Open(Tools)
getgenv().PaletteTest=Hub`, 'palette-check.lua')
  })
  await page.waitForTimeout(450)
  await click('OpenCommands')
  await page.waitForSelector('.rbx-editor')
  await search('sPrInT movement')
  assert.equal((await results()).length, 1, 'Case-insensitive multiword search failed')
  await search('Secret control')
  assert.equal((await results()).length, 0, 'Hidden control leaked into search')
  await search('no such control')
  assert(await page.evaluate(() => [...window.docsPreview.runtime.scene.nodes.values()].some(n => n.props.Text?.startsWith('No matches.'))), 'Missing empty state')
  await search('Walk speed 30')
  await page.keyboard.press('Enter')
  await page.waitForTimeout(500)
  assert(await page.evaluate(() => {
    const ns = [...window.docsPreview.runtime.scene.nodes.values()]
    const label = ns.find(n => n.props.Text === 'Walk speed 30' && n.rendered)
    const page = ns.find(n => n.props.Name === 'Page_Movement')
    const scroll = ns.find(n => n.parent === page && n.props.Name === 'Scroll')
    return label && label.y > scroll.y && label.y + label.h < scroll.y + scroll.h
  }), 'Selecting an off-screen control did not reveal it')
  await page.keyboard.press('F2')
  await page.waitForSelector('.rbx-editor')
  await search('Run action')
  await page.keyboard.press('Enter')
  await page.waitForTimeout(300)
  assert.equal((await page.locator('.rbx-editor').count()), 0, 'Palette stayed open after navigation')
  await page.keyboard.press('F2')
  await page.waitForSelector('.rbx-editor')
  await search('Run')
  await page.keyboard.press('ArrowDown')
  await page.keyboard.press('Enter')
  await page.waitForTimeout(300)
  assert(await page.evaluate(() => [...window.docsPreview.runtime.scene.nodes.values()].some(n => n.props.Name === 'Page_Tools' && n.props.Visible)), 'Arrow selection did not navigate to second result')
  await page.keyboard.press('F2')
  await page.waitForSelector('.rbx-editor')
  await page.keyboard.press('Escape')
  await page.waitForTimeout(100)
  assert.equal(await page.locator('.rbx-editor').count(), 0, 'Escape did not dismiss')
  // Scaling an already-open window must recenter it immediately.
  for (const scale of [0.8, 1.25, 1]) {
    await page.evaluate(scale => window.docsPreview.runtime.run('getgenv().PaletteTest:SetScale(' + scale + ')', 'scale-check.lua'), scale)
    await page.waitForTimeout(350)
    const centered = await page.evaluate(() => {
      const rt = window.docsPreview.runtime
      const p = [...rt.scene.nodes.values()].find(n => n.props.Name === 'PanelHolder')
      return { x: p.x + p.w / 2, y: p.y + p.h / 2, w: rt.layout.W, h: rt.layout.H }
    })
    assert(Math.abs(centered.x - centered.w / 2) < 2 && Math.abs(centered.y - centered.h / 2) < 2, 'Open window drifted after scaling: ' + JSON.stringify(centered))
  }
  // Rebind and persist through configs; the old shortcut must stop working.
  await page.evaluate(async () => {
    const rt = window.docsPreview.runtime
    await rt.run('local h=getgenv().PaletteTest h:SetCommandKey(Enum.KeyCode.F3) assert(h.CommandKey==Enum.KeyCode.F3) assert(h:SaveConfig("palette")) h:SetCommandKey(Enum.KeyCode.F4) assert(h:LoadConfig("palette")) assert(h.CommandKey==Enum.KeyCode.F3)', 'palette-rebind.lua')
  })
  await page.keyboard.press('F2')
  await page.waitForTimeout(100)
  assert.equal(await page.locator('.rbx-editor').count(), 0, 'Old shortcut remains active')
  await page.keyboard.press('F3')
  await page.waitForSelector('.rbx-editor')
  await search('Movement')
  mkdirSync('.impeccable/review/palette', { recursive: true })
  await page.screenshot({ path: '.impeccable/review/palette/desktop.png' })
  await page.keyboard.press('Escape')
  await page.setViewportSize({ width: 390, height: 844 })
  await page.waitForTimeout(200)
  await page.evaluate(() => { const rt = window.docsPreview.runtime; rt.setViewport(rt.layout.W, rt.layout.H, true) })
  await page.waitForTimeout(200)
  await click('OpenCommands')
  await page.waitForSelector('.rbx-editor')
  await search('Sprint')
  const windowBounds = await nodePoint('CommandWindow')
  assert(windowBounds.x - windowBounds.w / 2 >= 0 && windowBounds.x + windowBounds.w / 2 <= 390, 'Palette overflows mobile viewport')
  const row = await nodePoint('CommandResult')
  assert(row.h >= 44, 'Result tap target is too small')
  await page.screenshot({ path: '.impeccable/review/palette/mobile.png' })
  await click('CommandResult')
  await page.waitForTimeout(300)
  assert.equal(await page.locator('.rbx-editor').count(), 0, 'Touch result failed to dismiss')
  const logErrors = await page.evaluate(() => window.paletteLogs.filter(e => e.level === 'error'))
  assert.deepEqual(logErrors, [], 'Palette caused Luau errors or fired control callbacks')
  assert.deepEqual(errors, [])
  console.log('Palette search, hidden controls, scroll-to-control, callbacks unchanged, keyboard navigation, rebinding/configs and mobile selection passed')
} finally { await browser.close() }
