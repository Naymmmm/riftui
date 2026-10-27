// Offline browser regressions for large binary HTTP/FS and CORS fallback.
// Vite must be running. Optional: --live-image=https://... reproduces a real URL.
import assert from 'node:assert/strict'
import { chromium } from 'playwright-core'
import { readdirSync } from 'node:fs'
import { homedir } from 'node:os'
const base=homedir()+'/.cache/ms-playwright/'
const dir=readdirSync(base).find(d=>d.startsWith('chromium-'))
const browser=await chromium.launch({executablePath:base+dir+'/chrome-linux64/chrome',args:['--enable-features=WebAssemblyJSPromiseIntegration']})
const pixel=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==','base64')
const large=Buffer.alloc(3*1024*1024)
for(let i=0;i<large.length;i++)large[i]=i%256
const page=await browser.newPage({viewport:{width:900,height:700}})
const errors=[]
page.on('pageerror',e=>errors.push(e.message))
await page.route('https://binary.invalid/large',r=>r.fulfill({status:200,headers:{'access-control-allow-origin':'*'},body:large}))
await page.route('https://cors.invalid/image',r=>r.abort('blockedbyclient'))
await page.route('**/__rift_http?url=**',r=>{
  if(new URL(r.request().url()).searchParams.get('url')==='https://cors.invalid/image')return r.fulfill({status:200,headers:{'X-Rift-Proxy':'1','Content-Type':'image/png'},body:pixel})
  return r.continue()
})
try {
  await page.goto('http://localhost:5199/docs/preview.html?demo=button')
  await page.waitForFunction(()=>document.body.dataset.ready==='true')
  const live=process.argv.find(a=>a.startsWith('--live-image='))?.slice('--live-image='.length)
  const source=[
    'local r=request({Url="https://binary.invalid/large"})',
    'assert(#r.Body==3145728,"large HTTP body length")',
    'assert(string.byte(r.Body,1)==0 and string.byte(r.Body,-1)==255,"binary sentinels")',
    'writefile("binary-probe.bin",r.Body)',
    'assert(readfile("binary-probe.bin")==r.Body,"large file round trip")',
    'local Rift=loadstring(game:HttpGet("https://raw.githubusercontent.com/Naymmmm/riftui/main/public/Loader.luau"))()',
    'local Hub=Rift:CreateHub({Name="Image regression",Id="image-regression",Setup=false,Settings=false})',
    'Hub:SetBackground({Url="https://cors.invalid/image"})',
    'assert(Hub.Panel:FindFirstChild("Backdrop"),"proxied background is layered")',
    live?'Hub:SetBackground({Url='+JSON.stringify(live)+'}) print("LIVE_IMAGE_BYTES",#readfile(Hub.Background.File))':'',
    'print("BINARY_CHECK_PASSED")',
  ].join('\n')
  await page.evaluate(source=>window.docsPreview.runtime.start(source,'binary-check.lua'),source)
  await page.waitForFunction(()=>document.getElementById('result').textContent.includes('BINARY_CHECK_PASSED'),null,{timeout:30000})
  assert.equal(errors.length,0,errors.join('\n'))
  const bytes=await page.evaluate(()=>Array.from(window.docsPreview.runtime.vfs.read('binary-probe.bin')))
  assert.deepEqual(Buffer.from(bytes),large)
  console.log('3 MiB HTTP + filesystem round trip, CORS fallback and background loading passed' + (live?' (including live image URL)':''))
} finally {await browser.close()}
