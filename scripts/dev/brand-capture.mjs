// Deterministic export of the HTML/CSS banner. Requires pnpm dev at :5199.
import { chromium } from 'playwright-core'
import { homedir } from 'node:os'
import { readdirSync, mkdirSync } from 'node:fs'
import { execFileSync } from 'node:child_process'
const base = homedir() + '/.cache/ms-playwright/'
const dir = readdirSync(base).find(d => d.startsWith('chromium-'))
const browser = await chromium.launch({ executablePath: base + dir + '/chrome-linux64/chrome' })
try {
  const page = await browser.newPage({ viewport: { width: 1280, height: 640 }, deviceScaleFactor: 1 })
  await page.goto('http://localhost:5199/docs/banner.html')
  await page.evaluate(() => document.fonts.ready)
  mkdirSync('public/brand', { recursive: true })
  await page.screenshot({ path: 'public/brand/riftui-banner.png' })
  execFileSync('magick', ['public/brand/riftui-banner.png', '-quality', '92', 'public/brand/riftui-banner.webp'])
  console.log('Exported HTML/CSS banner to public/brand/riftui-banner.{png,webp}')
} finally { await browser.close() }
