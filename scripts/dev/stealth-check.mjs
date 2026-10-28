// Asset-only stealth policy: local icons/avatars, built-in fonts, quiet library output.
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
const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==','base64')
await page.route('https://thumbnails.roblox.com/**',r=>r.fulfill({status:200,headers:{'Access-Control-Allow-Origin':'*'},body:JSON.stringify({data:[{state:'Completed',imageUrl:'https://cdn.invalid/avatar.png'}]})}))
await page.route('https://cdn.invalid/avatar.png',r=>r.fulfill({status:200,headers:{'Access-Control-Allow-Origin':'*'},body:png}))
try{
  await page.goto('http://localhost:5199/docs/preview.html?demo=button')
  await page.waitForFunction(()=>document.body.dataset.ready==='true')
  await page.evaluate(async()=>{
    const rt=window.docsPreview.runtime
    window.stealthLogs=[];rt.onLog=e=>window.stealthLogs.push(e)
    await rt.start(`getgenv().RIFTUI_SECURE=true
local Rift=loadstring(game:HttpGet("https://raw.githubusercontent.com/Naymmmm/riftui/main/public/Loader.luau"))()
local h=Rift:CreateHub({Name="Local asset mode",Id="stealth-check",Setup=false})
assert(h.Stealth and h.DockHolder.Visible and h.Gui.Name=="RiftUI")
assert(Rift:GetIcon("rbxassetid://123456")==nil)
assert(Rift:GetIcon("rbxthumb://type=AvatarHeadShot&id=156&w=150&h=150")==nil)
local t=h:Tab({Name="Main",Icon="eye"}) local s=t:Section({Name="Controls"})
s:Button({Name="Local icons stay visible",Callback=function() end})
s:Button({Name="Raw ID stays blank",Window=h:Window({Title="Details",Icon="rbxassetid://123456"})})
s:PlayerPicker({Name="Player",Default="builderman"})
Rift:GetIcon("not-a-lucide-icon") -- library warning must be suppressed
warn("USER_SCRIPT_STILL_LOGS")
local external=Instance.new("ImageButton") external.BackgroundTransparency=1 external.Name="ExternalImage" external.Image="rbxassetid://987654" external.HoverImage="rbxassetid://123" external.PressedImage="rbxassetid://456" external.Parent=h.Gui
getgenv().StealthTest={Hub=h,Rift=Rift,External=external}
task.defer(function() h:Open(t) end)
task.spawn(function() h:Notify({Title="Stealth is ready",Content="The toolbar and notifications stay usable."}) end)
task.delay(0.6,function()
 assert(external.Image=="" and external.HoverImage=="" and external.PressedImage=="")
 local localIcons=0
 for _,n in h.Gui:GetDescendants() do
  if n:IsA("ImageLabel") or n:IsA("ImageButton") then
   assert(not string.match(n.Image,"^rbxassetid://") and not string.match(n.Image,"^rbxthumb://") and not string.match(n.Image,"^https?://"),"remote image survived")
   if string.match(n.Image,"^rbxasset://") then localIcons+=1 end
  elseif n:IsA("TextLabel") or n:IsA("TextButton") or n:IsA("TextBox") then
   assert(not string.match(n.FontFace.Family,"^rbxassetid://"),"remote font survived")
  end
 end
 assert(localIcons>0 and h.DockHolder.Visible)
 assert(h._stealthLocked and h._stealthStatus and h._stealthControl==nil)
 print("STEALTH_POLICY_PASSED")
end)`,'stealth-check.lua')
  })
  await page.waitForFunction(()=>window.stealthLogs.some(e=>e.text==='STEALTH_POLICY_PASSED'||e.level==='error'),null,{timeout:15000})
  assert.deepEqual(await page.evaluate(()=>window.stealthLogs.filter(e=>e.level==='error')),[])
  assert.deepEqual(await page.evaluate(()=>window.stealthLogs.filter(e=>e.level==='warn').map(e=>e.text)),['USER_SCRIPT_STILL_LOGS'])
  mkdirSync('.impeccable/review/stealth',{recursive:true})
  await page.screenshot({path:'.impeccable/review/stealth/desktop.png'})
  // Cached thumbnails must be local files, with no rbxthumb content IDs rendered.
  await page.evaluate(async()=>{
    const rt=window.docsPreview.runtime
    while(rt.busy)await new Promise(r=>setTimeout(r,5))
    await rt.run('local r=getgenv().StealthTest local id=r.Hub.Gui:FindFirstChild("PlayerPicker_Player",true) local click=id:FindFirstChild("Chip") firesignal(click.MouseButton1Click)','avatar-ui.lua')
  })
  await page.waitForTimeout(600)
  assert(await page.evaluate(()=>[...window.docsPreview.runtime.vfs.files.keys()].some(p=>/avatar-\d+\.png$/.test(p))))
  assert(await page.evaluate(()=>[...window.docsPreview.runtime.scene.nodes.values()].some(n=>n.props.Image?.startsWith('rbxasset://riftsim/')&&n.props.Image.includes('avatar-'))))
  await page.screenshot({path:'.impeccable/review/stealth/avatars.png'})
  await page.evaluate(async()=>{
    const rt=window.docsPreview.runtime
    while(rt.busy)await new Promise(r=>setTimeout(r,5))
    await rt.run(`local r=getgenv().StealthTest r.Hub:SetStealth(false)
assert(not r.Hub.Stealth and r.Hub.DockHolder.Visible)
assert(r.Rift:GetIcon("rbxassetid://123456").Image=="rbxassetid://123456")
local off=r.Rift:CreateHub({Name="Author disabled",Id="author-disabled",Setup=false,Stealth=false})
getgenv().RIFTUI_SECURE=false
local another=loadstring(game:HttpGet("https://raw.githubusercontent.com/Naymmmm/riftui/main/public/Loader.luau"))()
local optional=another:CreateHub({Name="User choice",Id="user-choice",Setup=false})
task.delay(0.3,function()
 assert(off._stealthLocked and not off.Stealth and off._stealthStatus and off._stealthControl==nil)
 assert(not optional._stealthLocked and optional._stealthControl)
 print("STEALTH_SETTINGS_LOCK_PASSED")
end)`, 'stealth-off.lua')
  })
  await page.waitForFunction(()=>window.stealthLogs.some(e=>e.text==='STEALTH_SETTINGS_LOCK_PASSED'||e.level==='error'))
  assert.deepEqual(await page.evaluate(()=>window.stealthLogs.filter(e=>e.level==='error')),[])
  assert.deepEqual(errors,[])
  console.log('Startup stealth blocks remote image IDs/fonts, keeps local icons/avatars and toolbar/notifications, silences library warnings only, and switches off passed')
}finally{await browser.close()}
