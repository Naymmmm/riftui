// Browser regressions for overlapping VM starts/stops and wrapped notification text.
// Requires the Vite dev server at :5199.
import assert from 'node:assert/strict'
import { chromium } from 'playwright-core'
import { homedir } from 'node:os'
import { readdirSync, mkdirSync } from 'node:fs'
const base = homedir() + '/.cache/ms-playwright/'
const dir = readdirSync(base).find(d => d.startsWith('chromium-'))
const browser = await chromium.launch({ executablePath: base + dir + '/chrome-linux64/chrome', args: ['--enable-features=WebAssemblyJSPromiseIntegration'] })
const page = await browser.newPage({ viewport: { width: 1100, height: 800 } })
const errors = []
page.on('pageerror', e => errors.push(e.message))
let entered
let requested = new Promise(resolve => { entered = resolve })
await page.route('https://slow.invalid/response', async route => {
  entered()
  await new Promise(resolve => setTimeout(resolve, 250))
  await route.fulfill({ status: 200, headers: { 'access-control-allow-origin': '*' }, body: 'ok' })
})
try {
  await page.goto('http://localhost:5199/docs/preview.html?demo=button')
  await page.waitForFunction(() => document.body.dataset.ready === 'true')
  await page.evaluate(() => {
    window.runtimeLogs = []
    const rt = window.docsPreview.runtime
    rt.onLog = e => window.runtimeLogs.push(e)
    window.firstStart = rt.start('local body=game:HttpGet("https://slow.invalid/response") print("OLD_RUN",body)', 'old-run.lua').then(() => null, e => String(e))
  })
  await requested
  const results = await page.evaluate(async () => {
    const second = window.docsPreview.runtime.start('print("LATEST_RUN")', 'latest-run.lua').then(() => null, e => String(e))
    return Promise.all([window.firstStart, second])
  })
  assert.deepEqual(results, [null, null], 'Starting again while HTTP is pending must not destroy an active VM')
  assert(await page.evaluate(() => window.runtimeLogs.some(e => e.text === 'LATEST_RUN')), 'Latest run did not execute')
  requested = new Promise(resolve => { entered = resolve })
  await page.evaluate(() => {
    window.firstStart = window.docsPreview.runtime.start('game:HttpGet("https://slow.invalid/response")', 'stop-pending.lua').then(() => null, e => String(e))
  })
  await requested
  const stopped = await page.evaluate(async () => {
    const stop = window.docsPreview.runtime.stop().then(() => null, e => String(e))
    return Promise.all([window.firstStart, stop])
  })
  assert.deepEqual(stopped, [null, null], 'Stopping during startup must not destroy an active VM')
  assert(await page.evaluate(() => !window.docsPreview.runtime.running), 'Stop did not stop the VM')
  const source = [
    'local Rift=loadstring(game:HttpGet("https://raw.githubusercontent.com/Naymmmm/riftui/main/public/Loader.luau"))()',
    'local Hub=Rift:CreateHub({Name="Toast check",Id="toast-check",Setup=false,Settings=false})',
    'task.spawn(function() Hub:Notify({Title="Some features will not work",Content="1 compatibility check failed. Settings > Run setup again shows which. This text must remain fully visible after wrapping.",Icon="triangle-alert",Duration=30}) end)',
    'task.delay(0.8,function() Hub:SetScale(1.25) end)',
  ].join('\n')
  await page.evaluate(source => window.docsPreview.runtime.start(source, 'notification-check.lua'), source)
  await page.waitForTimeout(1700)
  const bounds = await page.evaluate(() => {
    const rt = window.docsPreview.runtime
    const body = [...rt.scene.nodes.values()].find(n => n.props.Text?.startsWith('1 compatibility check failed.'))
    const card = body?.parent
    const clip = card?.parent
    const holder = clip?.parent
    return {
      body: body && { y: body.y, h: body.h },
      clip: clip && { y: clip.y, h: clip.h },
      holder: holder && { y: holder.y, h: holder.h },
      logs: window.runtimeLogs.filter(e => e.level === 'error').map(e => e.text),
    }
  })
  assert(bounds.body && bounds.clip && bounds.holder, 'Missing toast nodes')
  assert(bounds.body.y + bounds.body.h <= bounds.clip.y + bounds.clip.h - 5, 'Notification body clips after wrapping or scaling: ' + JSON.stringify(bounds))
  assert.equal(bounds.logs.length, 0, bounds.logs.join('\n'))
  assert.equal(errors.length, 0, errors.join('\n'))
  mkdirSync('.impeccable/review/notifications', { recursive: true })
  await page.screenshot({ path: '.impeccable/review/notifications/wrapped.png' })
  await page.setViewportSize({ width: 390, height: 844 })
  await page.waitForTimeout(600)
  const mobile = await page.evaluate(() => {
    const body = [...window.docsPreview.runtime.scene.nodes.values()].find(n => n.props.Text?.startsWith('1 compatibility check failed.'))
    const clip = body.parent.parent
    return { left: body.x, right: body.x + body.w, bottom: body.y + body.h, clipBottom: clip.y + clip.h, width: innerWidth }
  })
  assert(mobile.left >= 0 && mobile.right <= mobile.width - 5, 'Toast overflows a narrow viewport: ' + JSON.stringify(mobile))
  assert(mobile.bottom <= mobile.clipBottom - 5, 'Narrow toast body clips: ' + JSON.stringify(mobile))
  await page.screenshot({ path: '.impeccable/review/notifications/mobile.png' })
  await page.evaluate(() => {
    const rt = window.docsPreview.runtime
    rt.setViewport(rt.layout.W, rt.layout.H, true)
  })
  await page.waitForTimeout(350)
  async function toolbarState() {
    return page.evaluate(() => {
      const nodes = [...window.docsPreview.runtime.scene.nodes.values()]
      const button = nodes.find(n => n.props.Name === 'ToggleToolbar')
      const dock = nodes.find(n => n.props.Name === 'DockHolder')
      return { text: button.props.Text, visible: button.props.Visible, x: button.x, y: button.y, w: button.w, h: button.h, dockVisible: dock.props.Visible, dockBottom: dock.y + dock.h }
    })
  }
  let toggle = await toolbarState()
  assert(toggle.visible && toggle.text === 'Hide toolbar', 'Touch toggle must be available while the toolbar is visible')
  assert(toggle.w >= 44 && toggle.h >= 44, 'Touch toggle needs a usable tap target')
  assert(toggle.dockBottom < toggle.y, 'Toolbar overlaps its touch toggle')
  await page.mouse.click(toggle.x + toggle.w / 2, toggle.y + toggle.h / 2)
  await page.waitForTimeout(400)
  toggle = await toolbarState()
  assert(toggle.visible && toggle.text === 'Show toolbar' && !toggle.dockVisible, 'Touch button did not hide the toolbar')
  await page.mouse.click(toggle.x + toggle.w / 2, toggle.y + toggle.h / 2)
  await page.waitForTimeout(400)
  toggle = await toolbarState()
  assert(toggle.visible && toggle.text === 'Hide toolbar' && toggle.dockVisible, 'Touch button did not restore the toolbar')
  await page.screenshot({ path: '.impeccable/review/notifications/mobile-toggle.png' })
  await page.evaluate(() => {
    const rt = window.docsPreview.runtime
    rt.setViewport(rt.layout.W, rt.layout.H, false)
  })
  await page.waitForTimeout(100)
  assert(!(await toolbarState()).visible, 'Touch button should stay hidden on desktop')
  console.log('Overlapping start/stop, wrapped toast, responsive layout and mobile toolbar toggle passed')
} finally { await browser.close() }
