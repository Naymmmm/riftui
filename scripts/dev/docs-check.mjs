// Browser validation for the docs and live examples. Requires Vite on :5199.
import { chromium } from 'playwright-core'
import { readdirSync, mkdirSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
const base = homedir() + '/.cache/ms-playwright/'
const dir = readdirSync(base).find(d => d.startsWith('chromium-'))
const browser = await chromium.launch({ executablePath: base + dir + '/chrome-linux64/chrome', args: ['--enable-features=WebAssemblyJSPromiseIntegration'] })
const page = await browser.newPage({ viewport: { width: 1440, height: 1000 }, deviceScaleFactor: 1 })
await page.context().grantPermissions(['clipboard-read', 'clipboard-write'], { origin: 'http://localhost:5199' })
const errors = []
page.on('pageerror', e => errors.push(e.message))
mkdirSync('.impeccable/review/docs', { recursive: true })
const assert = (value, message) => { if (!value) throw new Error(message) }
const report = {}
try {
  await page.goto('http://localhost:5199/')
  await page.locator('h1').waitFor()
  await page.evaluate(() => document.fonts.ready)
  const routes = await page.locator('#navigation a').evaluateAll(as => as.map(a => a.getAttribute('href')))
  for (const route of routes) {
    await page.goto('http://localhost:5199/' + route)
    await page.locator('h1').waitFor()
    await page.waitForFunction(() => [...document.images].filter(i => i.loading !== 'lazy').every(i => i.complete))
    const bad = await page.locator('img').evaluateAll(images => images.filter(i => i.complete && !i.naturalWidth).map(i => i.src))
    assert(!bad.length, 'Broken images on ' + route + ': ' + bad.join(','))
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), 'Page overflow on ' + route)
  }
  report.routes = routes.length
  await page.goto('http://localhost:5199/#quick-start')
  await page.locator('.preview-image').waitFor()
  await page.evaluate(() => Promise.all([...document.images].map(i => i.decode().catch(() => {}))))
  await page.evaluate(() => { document.activeElement?.blur(); window.scrollTo(0, 0) })
  await page.waitForTimeout(250)
  await page.screenshot({ path: '.impeccable/review/docs/desktop.png', fullPage: true })
  await page.goto('http://localhost:5199/#themes')
  await page.locator('[data-theme="Ember"]').click()
  assert((await page.locator('.preview-image').getAttribute('src')).includes('theme-ember.webp'), 'Theme screenshot did not switch')
  await page.locator('[data-view="live"]').click()
  const liveFrame = page.frameLocator('#live-example')
  await liveFrame.locator('body[data-ready="true"]').waitFor({ timeout: 30000 })
  await page.locator('[data-theme="Slate"]').click()
  await liveFrame.locator('#result').filter({ hasText: 'Theme: Slate' }).waitFor()
  await page.evaluate(() => { document.activeElement?.blur(); window.scrollTo(0, 0) })
  await page.waitForTimeout(250)
  await page.screenshot({ path: '.impeccable/review/docs/themes.png', fullPage: true })
  report.themeSwitch = true
  await page.goto('http://localhost:5199/#button')
  await page.locator('[data-view="live"]').click()
  const frame = page.frames().find(f => f.url().includes('/docs/preview.html'))
  await page.frameLocator('#live-example').locator('body[data-ready="true"]').waitFor({ timeout: 30000 })
  const actualFrame = page.frames().find(f => f.url().includes('/docs/preview.html'))
  const point = await actualFrame.evaluate(() => {
    const n = [...window.docsPreview.runtime.scene.nodes.values()].find(n => n.cls === 'TextButton' && n.props.Text === 'Run action')
    return { x: n.x + n.w / 2, y: n.y + n.h / 2 }
  })
  const box = await page.locator('#live-example').boundingBox()
  await page.mouse.click(box.x + point.x, box.y + point.y)
  await page.frameLocator('#live-example').locator('#result').filter({ hasText: 'Button callback: 1' }).waitFor()
  report.buttonCallback = true
  await page.locator('[data-copy]').first().click()
  const copied = await page.evaluate(() => navigator.clipboard.readText())
  assert(copied.includes('Section:Button'), 'Copy button did not copy the displayed example')
  report.copy = true
  await page.locator('#search').fill('getcustomasset')
  assert(await page.locator('#navigation a[href="#compatibility"]').count() === 1, 'API text was not searchable')
  await page.locator('#search').fill('slider')
  assert(await page.locator('#navigation a').count() > 0, 'Search gave no slider result')
  assert(await page.locator('#navigation a').count() < routes.length, 'Search did not filter')
  await page.locator('#search').fill('zzzz-no-page')
  await page.locator('#clear-search').click()
  assert(await page.locator('#navigation a').count() === routes.length, 'Clear search did not restore navigation')
  report.search = true
  await page.setViewportSize({ width: 390, height: 844 })
  await page.goto('http://localhost:5199/#quick-start')
  await page.waitForTimeout(250)
  await page.evaluate(() => document.fonts.ready)
  await page.evaluate(() => Promise.all([...document.images].map(i => i.decode().catch(() => {}))))
  assert(await page.evaluate(() => document.documentElement.scrollWidth === innerWidth), 'Mobile page overflow')
  await page.evaluate(() => { document.activeElement?.blur(); window.scrollTo(0, 0) })
  await page.waitForTimeout(250)
  await page.screenshot({ path: '.impeccable/review/docs/mobile.png', fullPage: true })
  assert(await page.locator('#sidebar').evaluate(e => e.inert && e.getAttribute('aria-hidden') === 'true'), 'Closed mobile sidebar is not inert')
  await page.locator('#search').evaluate(e => e.focus())
  assert(await page.evaluate(() => document.activeElement?.id !== 'search'), 'Hidden mobile search received focus')
  await page.locator('#mobile-menu').click()
  assert(await page.locator('#sidebar').evaluate(e => !e.inert), 'Open mobile navigation remains inert')
  await page.locator('#navigation a[href="#themes"]').click()
  await page.waitForFunction(() => document.querySelector('h1')?.textContent === 'Themes')
  assert(await page.locator('#mobile-menu').getAttribute('aria-expanded') === 'false', 'Mobile menu did not close')
  report.mobileNavigation = true
  await page.locator('[data-view="live"]').click()
  await page.frameLocator('#live-example').locator('body[data-ready="true"]').waitFor({ timeout: 30000 })
  await page.locator('[data-theme="Ember"]').click()
  await page.frameLocator('#live-example').locator('#result').filter({ hasText: 'Theme: Ember' }).waitFor()
  report.mobileLive = true
  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.waitForFunction(() => !document.getElementById('sidebar').inert && document.getElementById('sidebar').getAttribute('aria-hidden') === 'false')
  await page.locator('#search').focus()
  assert(await page.evaluate(() => document.activeElement?.id === 'search'), 'Desktop search is not reachable')
  report.navigationFocus = true
  assert(!errors.length, 'Browser errors: ' + errors.join('\n'))
  report.consoleErrors = errors
  writeFileSync('.impeccable/review/docs/checks.json', JSON.stringify(report, null, 2) + '\n')
  console.log(JSON.stringify(report))
} finally { await browser.close() }
