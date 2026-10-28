// Local custom font loading and unsupported-executor fallback.
// Requires Vite on :5199. All remote thumbnail responses are deterministic fixtures.
import assert from 'node:assert/strict'
import { chromium } from 'playwright-core'
import { homedir } from 'node:os'
import { readdirSync, mkdirSync } from 'node:fs'
const base=homedir()+'/.cache/ms-playwright/'
const dir=readdirSync(base).find(d=>d.startsWith('chromium-'))
const browser=await chromium.launch({executablePath:base+dir+'/chrome-linux64/chrome',args:['--enable-features=WebAssemblyJSPromiseIntegration']})
const page=await browser.newPage({viewport:{width:1000,height:800}})
const errors=[];page.on('pageerror',e=>errors.push(e.message))

try {
  await page.goto('http://localhost:5199/docs/preview.html?demo=button')
  await page.waitForFunction(()=>document.body.dataset.ready==='true')
  async function start(fail=false) {
    await page.evaluate(async(fail)=>{
      const rt=window.docsPreview.runtime
      window.fontLogs=[];rt.onLog=e=>window.fontLogs.push(e)
      await rt.start(`local Rift=loadstring(game:HttpGet("https://raw.githubusercontent.com/Naymmmm/riftui/main/public/Loader.luau"))()
${fail ? 'local original=getcustomasset getcustomasset=function(path) if string.match(path,"%.font$") then error("font unsupported") end return original(path) end' : ''}
local h=Rift:CreateHub({Name="Local font",Id="font-check",Stealth=true,Setup=false})
local t=h:Tab({Name="Main",Icon="eye"}) local s=t:Section({Name="Typography"})
s:Button({Name="Inter is loaded locally",Callback=function()end})
getgenv().FontTest={Rift=Rift,Hub=h}
task.defer(function() h:Open(t) end)
task.spawn(function()
 while Rift:GetSecureFontStatus()=="idle" or Rift:GetSecureFontStatus()=="loading" do task.wait(0.1) end
 local status,family=Rift:GetSecureFontStatus()
 assert(status=="${fail ? 'failed' : 'ready'}",status)
 local count=0
 for _,n in h.Gui:GetDescendants() do
  if n:IsA("TextLabel") or n:IsA("TextButton") or n:IsA("TextBox") then
   assert(not string.match(n.FontFace.Family,"^rbxassetid://"))
   if n.FontFace.Family==family then count+=1 end
  end
 end
 ${fail ? 'assert(family==nil)' : 'assert(count>10,"existing text was not updated")'}
 print("FONT_CHECK_PASSED")
end)`, 'font-check.lua')
    },fail)
    await page.waitForFunction(()=>window.fontLogs.some(e=>e.text==='FONT_CHECK_PASSED'||e.level==='error'),null,{timeout:30000})
    assert.deepEqual(await page.evaluate(()=>window.fontLogs.filter(e=>e.level==='error')),[])
  }
  await start()
  const info=await page.evaluate(()=>{
    const rt=window.docsPreview.runtime
    const file=[...rt.vfs.files.keys()].find(p=>p.endsWith('.font'))
    const family=JSON.parse(new TextDecoder().decode(rt.vfs.read(file)))
    return {family,loaded:[...document.fonts].filter(f=>f.family.startsWith('RiftLocal_')).map(f=>({status:f.status,weight:f.weight})),mapped:[...rt.scene.nodes.values()].filter(n=>n.props.FontFace?.family?.includes('/Inter-')).length}
  })
  assert.equal(info.family.faces.length,4)
  assert(info.family.faces.every(f=>f.assetId.startsWith('rbxasset://riftsim/')))
  assert.deepEqual(info.loaded.map(f=>f.weight).sort(),['400','500','600','700'])
  assert(info.loaded.every(f=>f.status==='loaded'))
  mkdirSync('.impeccable/review/fonts',{recursive:true})
  await page.screenshot({path:'.impeccable/review/fonts/local-inter.png'})
  await start(true)
  assert.equal(await page.evaluate(()=>[...document.fonts].filter(f=>f.family.startsWith('RiftLocal_')).length),0)
  await start() // Warm TTF cache still builds and validates a fresh family.
  assert.equal(await page.evaluate(()=>[...document.fonts].filter(f=>f.family.startsWith('RiftLocal_')).length),4)
  const corrupt=await page.evaluate(async()=>{
    const {LocalFonts}=await import('/src/engine/fonts.ts')
    const {Vfs}=await import('/src/engine/vfs.ts')
    const v=new Vfs()
    v.write('bad.ttf',new Uint8Array(2048))
    v.write('bad.font',new TextEncoder().encode(JSON.stringify({name:'Bad',faces:[{name:'Regular',weight:400,style:'normal',assetId:'rbxasset://riftsim/bad.ttf'}]})))
    const registry=new LocalFonts(v,()=>{})
    try {await registry.load('rbxasset://riftsim/bad.font');return false} catch {return true} finally {registry.clear()}
  })
  assert(corrupt,'invalid TTF was accepted')
  assert.deepEqual(errors,[])
  console.log('Local Inter TTFs, four registered weights, existing text migration, cleanup and unsupported-executor fallback passed')
} finally { await browser.close() }
