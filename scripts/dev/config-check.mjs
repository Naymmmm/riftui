// Cross-runtime tests: real Luau + browser Web Crypto against the Node server format.
// Requires pnpm dev on :5199.
import assert from 'node:assert/strict'
import { chromium } from 'playwright-core'
import { homedir } from 'node:os'
import { readdirSync, mkdirSync } from 'node:fs'
import { encryptConfig, decryptConfig } from '../config/crypto.mjs'
const key = Buffer.alloc(32, 7).toString('base64')
const wrong = Buffer.alloc(32, 8).toString('base64')
const payload = {Hub:'encrypted-test',Name:'premium',Data:{Flags:{SecretToggle:{Value:true},SecretNumber:{Value:88}}}}
const remote = encryptConfig(payload, key)
const tampered = structuredClone(remote); tampered.Tag = '0'.repeat(64)
const foreign = encryptConfig({...payload,Hub:'another-hub'},key)
const base = homedir()+'/.cache/ms-playwright/'
const dir = readdirSync(base).find(d=>d.startsWith('chromium-'))
const browser = await chromium.launch({executablePath:base+dir+'/chrome-linux64/chrome',args:['--enable-features=WebAssemblyJSPromiseIntegration']})
const page = await browser.newPage({viewport:{width:1000,height:800}})
const errors=[];page.on('pageerror',e=>errors.push(e.message))
await page.route('https://config.invalid/v1/configs/**', async route=>{
  const id = new URL(route.request().url()).pathname.split('/').pop()
  const allowed = route.request().headers().authorization === 'Bearer test-token'
  const headers = {'Access-Control-Allow-Origin':'*','Content-Type':'application/json'}
  if (!allowed || id==='unauthorized') return route.fulfill({status:401,headers,body:'{"error":"denied"}'})
  return route.fulfill({status:200,headers,body:JSON.stringify(id==='tampered'?tampered:id==='plain'?payload:id==='foreign'?foreign:remote)})
})
try {
  await page.goto('http://localhost:5199/docs/preview.html?demo=button')
  await page.waitForFunction(()=>document.body.dataset.ready==='true')
  await page.evaluate(async ({key,wrong})=>{
    const rt=window.docsPreview.runtime
    window.configLogs=[];rt.onLog=e=>window.configLogs.push(e)
    const source=`local Rift=loadstring(game:HttpGet("https://raw.githubusercontent.com/Naymmmm/riftui/main/public/Loader.luau"))()
local key=${JSON.stringify(key)} local wrong=${JSON.stringify(wrong)}
local h=Rift:CreateHub({Name="Encrypted config test",Id="encrypted-test",Setup=false,ConfigEncryption={Key=key},ConfigServer={Url="https://config.invalid/v1",Token=function() return "test-token" end,RequireEncrypted=true}})
local t=h:Tab({Name="Test",Icon="lock"}) local s=t:Section({Name="Controls"})
local toggle=s:Toggle({Name="Enabled",Flag="SecretToggle",Default=false})
local number=s:Slider({Name="Number",Flag="SecretNumber",Min=0,Max=100,Default=20})
local p,aes,mac=h:_configKeys() local iv=p.generatebytes(16) local ct=p.encrypt("probe",aes,iv,"CBC") assert(p.decrypt(ct,aes,iv,"CBC")=="probe")
assert(h:SaveConfig("secure"))
assert(h:ConfigInfo("secure").Encrypted)
assert(not h:SaveConfig("must-not-exist",{Key="not-a-key"})) assert(not isfile("RiftUI/encrypted-test/configs/must-not-exist.json"))
local raw=readfile("RiftUI/encrypted-test/configs/secure.json")
assert(not string.find(raw,"SecretToggle",1,true) and not string.find(raw,key,1,true))
number:Set(44,true) assert(h:LoadConfig("secure")) assert(number.Value==20)
assert(h:SaveConfig("plain",{Encrypt=false})) assert(string.find(readfile("RiftUI/encrypted-test/configs/plain.json"),"SecretToggle",1,true))
local code=assert(h:ExportConfig("secure")) assert(string.sub(code,1,9)=="RIFTCFG2:")
assert(h:ImportConfig(code,"imported"))
number:Set(31,true) assert(not h:LoadConfig("secure",{Key=wrong})) assert(number.Value==31)
assert(not h:LoadRemoteConfig("premium",{Key=wrong})) assert(number.Value==31)
assert(not h:LoadRemoteConfig("tampered")) assert(number.Value==31)
assert(not h:LoadRemoteConfig("foreign")) assert(number.Value==31)
assert(not h:LoadRemoteConfig("unauthorized")) assert(number.Value==31)
assert(not h:LoadRemoteConfig("plain")) assert(number.Value==31)
assert(not h:LoadRemoteConfig("../premium"))
assert(not h:ImportConfig("RIFTCFG2:"..crypt.base64encode(game:GetService("HttpService"):JSONEncode({Hub=h.Id,Data={Flags={}}})),"downgrade"))
assert(h:LoadRemoteConfig("premium")) assert(number.Value==88 and toggle.Value)
assert(not isfile("RiftUI/encrypted-test/configs/premium.json"))
assert(h:LoadRemoteConfig("premium",{SaveAs="cached"}))
assert(not string.find(readfile("RiftUI/encrypted-test/configs/cached.json"),"SecretToggle",1,true))
number:Set(12,true) assert(h:LoadConfig("cached")) assert(number.Value==88)
assert(not h:SetConfigServer({Url="http://config.invalid"}))
assert(not h:SetConfigServer({Url="https://user:password@config.invalid"}))
assert(h:SetConfigServer({Url="https://config.invalid/v1",Token="test-token"}))
assert(h:LoadRemoteConfig("plain",{SaveAs="plain-remote"}))
assert(not string.find(readfile("RiftUI/encrypted-test/configs/plain-remote.json"),"SecretToggle",1,true))
local savedProvider=crypt crypt=nil
local plain=Rift:CreateHub({Name="No crypto",Id="no-crypto",Setup=false,Settings=false})
assert(plain:SaveConfig("works")) assert(not plain:SaveConfig("encrypted",{Encrypt=true}))
assert(not isfile("RiftUI/no-crypto/configs/encrypted.json")) plain:Destroy() crypt=savedProvider
assert(h:SetConfigEncryption({Key=function() return key end}))
h._quietReinit=true h:Reinitialize()
number:Set(5,true) assert(h:LoadConfig("secure")) assert(number.Value==20) assert(h:LoadRemoteConfig("premium")) assert(number.Value==88) assert(h:SaveConfig("rebuilt"))
getgenv().ConfigTest=h
task.spawn(function() for i=1,100 do if h.ConfigManager then h.ConfigManager:Open() print("CONFIG_MANAGER_READY") return end task.wait(0.05) end error("config manager did not initialize") end)
print("CONFIG_ENCRYPTION_PASSED")`
    await rt.start(source,'encrypted-config-check.lua')
  },{key,wrong})
  await page.waitForFunction(()=>window.configLogs.some(e=>e.text==='CONFIG_MANAGER_READY' || e.level==='error'),null,{timeout:30000})
  assert.deepEqual(await page.evaluate(()=>window.configLogs.filter(e=>e.level==='error')),[])
  const encrypted = await page.evaluate(()=>new TextDecoder().decode(window.docsPreview.runtime.vfs.read('RiftUI/encrypted-test/configs/secure.json')))
  const decoded=decryptConfig(JSON.parse(encrypted),key)
  assert.equal(decoded.Hub,'encrypted-test')
  assert.equal(decoded.Data.Flags.SecretNumber.Value,20)
  assert(!encrypted.includes(key))
  const rebuilt=await page.evaluate(()=>new TextDecoder().decode(window.docsPreview.runtime.vfs.read('RiftUI/encrypted-test/configs/rebuilt.json')))
  assert.equal(decryptConfig(JSON.parse(rebuilt),key).Data.Flags.SecretNumber.Value,88)
  const logErrors=await page.evaluate(()=>window.configLogs.filter(e=>e.level==='error'))
  assert.deepEqual(logErrors,[])
  assert.deepEqual(errors,[])
  mkdirSync('.impeccable/review/config-encryption',{recursive:true})
  await page.waitForTimeout(450)
  await page.screenshot({path:'.impeccable/review/config-encryption/manager.png'})
  await page.evaluate(async()=>{
    const rt=window.docsPreview.runtime
    while(rt.busy) await new Promise(r=>setTimeout(r,5))
    await rt.run('local h=getgenv().ConfigTest for _,t in h.ConfigManager.Tabs do if t.Name=="Remote" then h.ConfigManager:SelectTab(t) end end','remote-ui.lua')
  })
  await page.waitForTimeout(350)
  await page.screenshot({path:'.impeccable/review/config-encryption/remote.png'})
  await page.setViewportSize({width:390,height:844})
  await page.waitForTimeout(350)
  await page.screenshot({path:'.impeccable/review/config-encryption/mobile.png'})
  assert.deepEqual(await page.evaluate(()=>window.configLogs.filter(e=>e.level==='error')),[])
  console.log('Luau ↔ Node encryption, opt-in/plain configs, wrong-key/tamper/wrong-hub/401 rejection without mutation, encrypted cache and remote loads passed')
} finally {await browser.close()}
