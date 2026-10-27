import { LuauState } from 'luau-web'
import { readFileSync, readdirSync } from 'node:fs'
const root = '/home/netcode/.t3/projects/riftui'
const files = readdirSync(root+'/engine').filter(f=>f.endsWith('.luau')).sort()
const src = files.map(f=>{const s=readFileSync(root+'/engine/'+f,'utf8'); return (f.startsWith('00-')||f.startsWith('99-'))? s : `do\n${s}\nend`}).join('\n')
let step, run, st
const opsLog=[]
const host = {
  sync: (p)=>{ opsLog.push(p.length); return '' },
  measure: (t,s)=> `${t.length*s*0.5}\x1f${s}`,
  print: (m)=>console.log('[print]', m),
  warn: (m)=>console.log('[warn]', m),
  error: (m,t)=>console.log('[error]', m, t),
  now: ()=>Date.now(),
  load: (s,n)=>{ const r = st.loadstring(s, n, false); return r },
  fs: (op,p,d)=> op==='isfile'||op==='isfolder' ? '0' : '',
  http: async (m,u)=> `404\x1f\x1f{}`,
  clipboard: ()=>{},
  register: (a,b)=>{ step=a; run=b },
}
st = await LuauState.createAsync({ __HOST: host })
const f = st.loadstring(src, '=engine', false)
if (typeof f === 'string') { console.log('COMPILE', f); process.exit(1) }
try { await f() } catch(e) { console.log('ENGINE ERR', e.message); process.exit(1) }
console.log('registered', typeof step, typeof run)
await run(`
local f = Instance.new("Frame")
f.Size = UDim2.new(0, 200, 0, 50)
f.Name = "Hi"
print(f, typeof(f), f.ClassName, f.Size, f:IsA("GuiObject"), typeof(UDim2.new()))
local sg = Instance.new("ScreenGui", gethui())
f.Parent = sg
print(f:GetFullName(), #sg:GetChildren())
local tl = Instance.new("TextLabel"); tl.Font = Enum.Font.GothamBold; print(tl.FontFace)
f.Changed:Connect(function(p) print("changed", p) end)
f.BackgroundColor3 = Color3.fromRGB(255,0,0)
local tw = game:GetService("TweenService"):Create(f, TweenInfo.new(0.1), {Size = UDim2.fromOffset(300, 60)})
tw.Completed:Connect(function(s) print("tween done", s, f.Size) end)
tw:Play()
task.wait(0.2)
print("after wait", f.Size)
local ok, e = pcall(function() f.Size = 5 end) print(ok, e)
local ok2, e2 = pcall(function() return f.Nope end) print(ok2, e2)
print(game:GetService("HttpService"):JSONEncode({a=1,b={1,2,3},c="x\\n"}))
print(game:GetService("HttpService"):JSONDecode('{"a":[1,2,{"b":true}],"c":null}').a[3].b)
print(crypt.base64decode(crypt.base64encode("hello\\0\\255world")) == "hello\\0\\255world")
local x: number = 1; x += 1; print(\`interp {x}\`)
print(Enum.KeyCode.RightShift, Enum.KeyCode.RightShift.Value, Color3.fromHex("#ff8800"):ToHex())
`, 'test')
for (let i=0;i<20;i++) await step(0.016, i==3 ? 'kd\x1fRightShift\x1f0' : '')
console.log('ops batches', opsLog.length, 'sizes', opsLog.slice(0,5))
