// Developer-test requirements: real Luau, gates, async races, timeouts and pointer/keyboard input.
// Requires the documented Vite dev server at :5199.
import assert from 'node:assert/strict'
import { chromium } from 'playwright-core'
import { readdirSync, mkdirSync } from 'node:fs'
import { homedir } from 'node:os'
const base=homedir()+'/.cache/ms-playwright/'
const dir=readdirSync(base).find(d=>d.startsWith('chromium-'))
const browser=await chromium.launch({executablePath:base+dir+'/chrome-linux64/chrome',args:['--enable-features=WebAssemblyJSPromiseIntegration']})
const page=await browser.newPage({viewport:{width:1000,height:800}})
const errors=[];page.on('pageerror',e=>errors.push(e.message))
async function execute(source){
  await page.evaluate(async source=>{
    const rt=window.docsPreview.runtime
    while(rt.busy)await new Promise(r=>setTimeout(r,5))
    await rt.run(source,'requirements-probe.lua')
  },source)
  await page.waitForTimeout(180)
  assert.deepEqual(await page.evaluate(()=>window.requirementLogs.filter(e=>e.level==='error')),[])
}
async function clickGate(){
  const p=await page.evaluate(()=>{
    const n=[...window.docsPreview.runtime.scene.nodes.values()].find(n=>n.rendered&&n.props.Name==='RequirementGate'&&n.props.Visible)
    return {x:n.x+n.w/2,y:n.y+n.h/2}
  })
  await page.mouse.click(p.x,p.y)
  await page.waitForTimeout(150)
}
try{
  await page.goto('http://localhost:5199/docs/preview.html?demo=button')
  await page.waitForFunction(()=>document.body.dataset.ready==='true')
  await page.evaluate(async()=>{
    const rt=window.docsPreview.runtime
    window.requirementLogs=[];rt.onLog=e=>window.requirementLogs.push(e)
    await rt.start(`local Rift=loadstring(game:HttpGet("https://raw.githubusercontent.com/Naymmmm/riftui/main/public/Loader.luau"))()
local ready=false local mode="normal" local calls=0 local executions=0 local defaults=0 local changes=0
local h=Rift:CreateHub({Name="Developer requirements",Id="requirements-test",Setup=false,Requirements={
 Ready={Name="Developer feature",Message="Not available here",Test=function() calls+=1 if mode=="old" then task.wait(0.3) return true end return ready,"The developer test did not pass" end},
 Throws={Test=function() error("developer error detail") end},
 Slow={Timeout=0.1,Test=function() task.wait(1) return true end},
}})
h:OnRequirementsChanged(function() changes+=1 end)
local t=h:Tab({Name="Features",Icon="lock"}) local s=t:Section({Name="Tools",Requires="Ready"})
local button=s:Button({Name="Use feature",Callback=function() executions+=1 end})
local toggle=s:Toggle({Name="Default enabled",Default=true,Flag="Gated",Callback=function() defaults+=1 end})
local slider=s:Slider({Name="Amount",Min=0,Max=10,Default=3,Flag="Amount"})
local key=s:Keybind({Name="Run with F",Default=Enum.KeyCode.F,Callback=function() executions+=1 end})
local unknown=t:Section({Name="Unknown"}):Button({Name="Undefined requirement",Requires="Missing",Callback=function() error("undefined requirement bypassed") end})
assert(not h:CanUse("Ready")) assert(slider:Set(8)==false and slider.Value==3)
local guarded=h:Guard("Ready",function(a) executions+=1 return a, "kept" end)
assert(guarded(123)==false)
getgenv().ReqTest={Hub=h,Button=button,Toggle=toggle,Slider=slider,Key=key,Guarded=guarded,SetReady=function(v) ready=v end,SetMode=function(v) mode=v end,Stats=function() return calls,executions,defaults,changes end}
task.defer(function() h:Open(t) end)`,'requirements-test.lua')
  })
  await page.waitForTimeout(600)
  await execute(`local r=getgenv().ReqTest local h=r.Hub
assert(h:GetRequirement("Ready").Status=="failed")
assert(h:GetRequirement("Throws").Error and h:GetRequirement("Throws").Status=="failed")
assert(h:GetRequirement("Slow").Status=="timeout")
assert(not h:CanUse("Missing"))
assert(not r.Button:IsAvailable()) assert(r.Slider:Set(8)==false and r.Slider.Value==3)
local calls,n,d,changes=r.Stats() assert(calls==1 and n==0 and d==0 and changes>0)
local copy=h:GetRequirement("Ready") copy.Passed=true assert(not h:CanUse("Ready"))`)
  await clickGate()
  await page.locator('#viewport').focus()
  await page.keyboard.press('f')
  await page.waitForTimeout(150)
  await execute('local r=getgenv().ReqTest local _,n,d=r.Stats() assert(n==0 and d==0 and r.Key.State==false)')
  mkdirSync('.impeccable/review/requirements',{recursive:true})
  await page.screenshot({path:'.impeccable/review/requirements/locked.png'})
  await execute('local r=getgenv().ReqTest r.SetReady(true) task.spawn(function() r.Hub:RunRequirements() end)')
  await page.waitForTimeout(400)
  await execute(`local r=getgenv().ReqTest assert(r.Hub:CanUse("Ready")) assert(not r.Hub:CanUse({"Ready","Missing"}))
local _,n,d=r.Stats() assert(d==1)
local a,b=r.Guarded(123) assert(a==123 and b=="kept")
r.Slider:Set(8,true) assert(r.Slider.Value==8)`)
  await page.locator('#viewport').focus()
  await page.keyboard.press('f')
  await page.waitForTimeout(150)
  await execute('local r=getgenv().ReqTest local _,n=r.Stats() assert(n==2 and r.Key.State==true)')
  await page.screenshot({path:'.impeccable/review/requirements/unlocked.png'})
  // An older yielding test must never overwrite a newer failed result.
  await execute('local r=getgenv().ReqTest r.SetMode("old") task.spawn(function() r.Hub:RunRequirement("Ready") end)')
  await execute('local r=getgenv().ReqTest r.SetMode("normal") r.SetReady(false) task.spawn(function() r.Hub:RunRequirement("Ready") end)')
  await page.waitForTimeout(450)
  await execute('local r=getgenv().ReqTest assert(not r.Hub:CanUse("Ready")) assert(r.Slider:Set(9)==false and r.Slider.Value==8)')
  await page.setViewportSize({width:390,height:844})
  await page.waitForTimeout(350)
  await clickGate()
  await page.screenshot({path:'.impeccable/review/requirements/mobile.png'})
  assert.deepEqual(errors,[])
  console.log('Developer-only tests, inherited gates, pending/failed/unknown states, callbacks/Set/keybind guards, defaults, timeout/error capture, stale results, desktop/mobile passed')
}finally{await browser.close()}
