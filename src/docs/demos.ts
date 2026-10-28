export const themes = ['Graphite', 'Ink', 'Slate', 'Ember'] as const
export type DemoName = 'overview' | 'button' | 'toggle' | 'slider' | 'dropdown' | 'input' | 'keybind' | 'color-picker' | 'content' | 'themes' | 'notifications' | 'setup' | 'configs' | 'pins' | 'command-palette' | 'range-slider' | 'progress' | 'stat' | 'sparkline' | 'segmented' | 'stepper' | 'console' | 'player-picker' | 'dependent-controls' | 'overlays' | 'tooltips' | 'translations' | 'encrypted-configs' | 'requirements' | 'stealth' | 'list' | 'loading' | 'auth' | 'social-button'
export const demoNames: DemoName[] = ['overview', 'button', 'toggle', 'slider', 'dropdown', 'input', 'keybind', 'color-picker', 'content', 'themes', 'notifications', 'setup', 'configs', 'pins', 'command-palette',"range-slider","progress","stat","sparkline","segmented","stepper","console","player-picker","dependent-controls","overlays","tooltips","translations","encrypted-configs","requirements","stealth","list","loading","auth","social-button"]
const examples: Record<DemoName, string> = {
  requirements: `S:Button({Name="Use feature",Requires="Feature",Callback=function() print("Feature action ran") end})
S:Slider({Name="Feature amount",Requires="Feature",Min=1,Max=10,Default=3})
local tests=Tab:Section({Name="Developer test",Side="Right"})
tests:Toggle({Name="Test result",Default=false,Callback=function(v) getgenv().featureReady=v Hub:RunRequirement("Feature") print(v and "Developer test passed" or "Developer test failed") end})
tests:Paragraph({Content="The hub developer supplies the test. Turn Test result on to unlock the feature."})`,
  stealth: `S:Button({Name="Local icons",Callback=function() Hub:Notify({Title="Local asset mode",Content="The toolbar and notifications remain available."}) end})
S:PlayerPicker({Name="Player"})
S:Paragraph({Title="Asset policy",Content="Built-in icons use local files. Raw Roblox image IDs are blocked; fonts use a built-in fallback. Avatar initials remain if a thumbnail cannot be cached."})`,
  'encrypted-configs': `assert(Hub:SetConfigEncryption({Key=crypt.generatekey()}))
S:Toggle({Name="Sprint",Flag="DocsEncryptedSprint",Default=true})
S:Slider({Name="Walk speed",Flag="DocsEncryptedSpeed",Min=16,Max=100,Default=32})
S:Button({Name="Save encrypted",Callback=function() local ok,err=Hub:SaveConfig("demo") print(ok and "Encrypted config saved" or err) end})
S:Button({Name="Load encrypted",Callback=function() local ok,err=Hub:LoadConfig("demo") print(ok and "Encrypted config restored" or err) end})
S:Paragraph({Title="Demo key",Content="This preview generates a temporary key. Save, change a value, then load to restore it. Replaying creates a new key."})`,
  "range-slider": `local delay=S:RangeSlider({Name="Delay",Min=0,Max=500,Step=10,Default={40,120},Suffix=" ms",Callback=function(lo,hi) print("Delay:",lo,hi) end})
S:Button({Name="Reset range",Callback=function() delay:Set({40,120}) end})`,
  "progress": `local health=S:Progress({Name="Health",Max=100,Default=82})
local ammo=S:Progress({Name="Ammo",Max=30,Default=24,Segments=6})
S:Button({Name="Use ammo",Callback=function() ammo:Set(math.max(0,ammo.Value-1)) health:Set(math.max(0,health.Value-7)) print("Ammo:",ammo.Value) end})`,
  "stat": `local money=S:Stat({Name="Money",Default=12500,Delta=true,Suffix=" $"})
S:Button({Name="Earn 100",Callback=function() money:Update(money.Value+100) print("Money:",money.Value) end})
S:Button({Name="Spend 50",Callback=function() money:Update(money.Value-50) end})`,
  "sparkline": `local graph=S:Sparkline({Name="Frame rate",Points=16,Min=0,Max=100,Suffix=" fps"})
for _,v in {58,60,59,55,54,58,60,62,57,59,60,56,61,60,59,60} do graph:Push(v) end
S:Button({Name="Add sample",Callback=function() local v=math.random(35,70) graph:Push(v) print("Sample:",v) end})
S:Button({Name="Clear graph",Callback=function() graph:Clear() end})`,
  "segmented": `S:Segmented({Name="Mode",Options={"Explore","Build","Practice"},Default="Explore",Callback=function(v) print("Mode:",v) end})`,
  "stepper": `S:Stepper({Name="Burst",Min=1,Max=5,Default=1,Callback=function(v) print("Burst:",v) end})`,
  "console": `local log=S:Console({Name="Events",Height=120,MaxLines=20})
log:Log("Ready") log:Log("Waiting for your input", "warn")
S:Button({Name="Write entry",Callback=function() log:Log("Action completed") print("Entry added") end})`,
  "player-picker": `S:PlayerPicker({Name="Player",Callback=function(p) print("Player:",p and p.Name or "None") end})`,
  "dependent-controls": `local enabled=S:Toggle({Name="Enabled",Default=true})
local group=S:Group({Name="Tuning",DependsOn=enabled})
group:Slider({Name="Field of view",Min=10,Max=400,Default=120})
group:Toggle({Name="Team check",Default=true})`,
  "overlays": `S:Keybind({Name="Sprint",Default=Enum.KeyCode.F,Mode="Toggle",Callback=function(on) print("Sprint:",on) end})
S:Keybind({Name="Focus",Default=Enum.KeyCode.Q,Mode="Hold"})
S:Toggle({Name="Watermark",Default=true,Callback=function(on) Hub:SetWatermark(on) end})
S:Toggle({Name="Keybind list",Default=true,Callback=function(on) Hub:SetKeybindList(on) end})
Hub:SetWatermark(true) Hub:SetKeybindList(true)`,
  "tooltips": `S:Slider({Name="Smoothing",Min=0,Max=1,Step=0.05,Default=0.3,Description="Higher values move more slowly. Hover this control for help."})
S:Button({Name="Run action",Description="Runs your callback once.",Callback=function() print("Action fired") end})`,
  "translations": `local function language(code) Hub:SetLanguage(code) print("Language:",code) end
S:Button({Name="Español",Callback=function() language("es") end})
S:Button({Name="English",Callback=function() language("en") end})
S:Toggle({Name="Watermark",Default=false,Callback=function(on) Hub:SetWatermark(on) end})
S:Keybind({Name="Toolbar key",Default=Enum.KeyCode.RightShift,Mode="None"})
Hub:SetLanguage("es")`,

  'command-palette': `S:Toggle({Name="Sprint",Default=true})
S:Slider({Name="Walk speed",Min=16,Max=100,Default=32})
S:Button({Name="Run action",Callback=function() print("Action callback ran") end})
local settings=Hub:Tab({Name="Appearance",Icon="palette"})
settings:Section({Name="Theme"}):Dropdown({Name="Base theme",Options={"Graphite","Ink","Slate","Ember"},Default="Graphite",Callback=function(v) Hub:SetTheme(v) end})
task.defer(function() Hub:OpenCommandPalette() end)`,
  overview: `local movement = Tab:Section({Name="Movement", Side="Left"})
movement:Toggle({Name="Sprint", Default=true, Callback=function(v) print("Sprint:",v) end})
movement:Slider({Name="Walk speed", Min=16, Max=100, Default=32, Suffix=" studs/s", Callback=function(v) print("Walk speed:",v) end})
movement:Keybind({Name="Fly toggle",Default=Enum.KeyCode.F,Callback=function(v) print("Fly:",v) end})
local actions=Tab:Section({Name="Actions",Side="Right"})
actions:Dropdown({Name="Mode",Options={"Explore","Build","Practice"},Default="Explore",Callback=function(v) print("Mode:",v) end})
actions:Button({Name="Run action",Callback=function() print("Callback fired: Run action") Hub:Notify({Title="Action complete",Content="Your callback ran.",Duration=3}) end})
actions:Paragraph({Title="Your hub, your logic",Content="These controls only change demo values. Add your own callbacks."})`,
  button: `local clicks=0
local status=S:Label("Callback has not run yet.")
S:Button({Name="Run action",Callback=function() clicks+=1 status:Set("Callback ran "..clicks..(clicks==1 and " time." or " times.")) print("Button callback:",clicks) end})
S:Button({Name="Danger action",Danger=true,Callback=function() print("Danger button callback fired") end})
local notes=Tab:Section({Name="Interaction",Side="Right"})
notes:Paragraph({Title="Click to call",Content="Press the button. The label updates when its callback runs."})`,
  toggle: `S:Toggle({Name="Sprint",Flag="DocsSprint",Default=true,Callback=function(v) print("Sprint:",v) end})
S:Toggle({Name="Team check",Default=false,Description="A second, independent value",Callback=function(v) print("Team check:",v) end})
local notes=Tab:Section({Name="State",Side="Right"})
notes:Paragraph({Title="A value that stays",Content="Checked means true. The toolbar badge counts active toggles."})`,
  slider: `S:Slider({Name="Walk speed",Min=16,Max=100,Step=1,Default=32,Suffix=" studs/s",Callback=function(v) print("Walk speed:",v) end})
S:Slider({Name="Smoothing",Min=0,Max=1,Step=0.05,Default=0.35,Callback=function(v) print("Smoothing:",v) end})
local notes=Tab:Section({Name="Interaction",Side="Right"})
notes:Paragraph({Title="Drag or type",Content="Drag the notch, or click the number and enter an exact value."})`,
  dropdown: `S:Dropdown({Name="Mode",Options={"Explore","Build","Practice"},Default="Explore",Callback=function(v) print("Mode:",v) end})
S:Dropdown({Name="Targets",Options={"Players","NPCs","Objects"},Multi=true,Default={"Players"},Callback=function(v) local a={} for k,on in v do if on then table.insert(a,k) end end print("Selected:",table.concat(a,", ")) end})`,
  input: `S:Input({Name="Profile name",Placeholder="Enter a name",Default="My profile",Callback=function(v) print("Profile name:",v) end})
S:Input({Name="Live text",Placeholder="Type here",Finished=false,Callback=function(v) print("Live text:",v) end})
local more=Tab:Section({Name="Multiline",Side="Right"})
more:Input({Name="Script",MultiLine=true,Lines=5,Code=true,Placeholder="-- paste a script",Default='print("Hello")\\nfor i = 1, 3 do\\n    print(i)\\nend',Callback=function(v) print("Script lines:",#string.split(v,"\\n")) end})`,
  list: `local wp=S:List({Name="Waypoints",Columns={"Name","Position"},Widths={2,3},Items={{"Spawn","0, 5, 0"},{"Shop","42, 3, -18"},{"Arena","-120, 8, 64"}},Removable=true,Placeholder="No waypoints saved",
  Callback=function(item,i) print("Selected:",item[1],"at row",i) end,OnRemove=function(item) print("Removed:",item[1]) end})
local tools=Tab:Section({Name="Actions",Side="Right"})
tools:Button({Name="Add waypoint",Callback=function() local n=#wp.Items+1 wp:Add({"Point "..n,math.random(-99,99)..", 4, "..math.random(-99,99)}) print("Added Point",n) end})
tools:Button({Name="Clear list",Callback=function() wp:Clear() print("List cleared") end})`,
  auth: '', // built by authDemo
  'social-button': `local win=Hub:Window({Title="About",Description="Community and support",Icon="info",Width=480,Height=300})
win:SocialButton({Discord="https://discord.gg/your-invite",Callback=function(url) print("Copied:",url) end})
win:Section({Name="Community"}):Paragraph({Title="Join the server",Content="The Discord button copies the invite. Narrow windows keep only the logo."})
S:Button({Name="Open About",Window=win})
S:Paragraph({Title="Collapsible sections",Content="Click a section header, such as CONTROLS, to fold it."})
task.defer(function() task.wait(0.3) win:Open() end)`,
  loading: `S:Paragraph({Title="Loaded",Content="The card held the screen while the script fetched data, then handed over to the toolbar."})
S:Button({Name="Run action",Callback=function() print("Hub is ready") end})
task.spawn(function()
  for i,step in {"Fetching game data","Building interface","Loading config"} do Hub:SetLoading(step,i/4) task.wait(0.7) end
  Hub:FinishLoading()
end)`,
  keybind: `S:Keybind({Name="Fly toggle",Default=Enum.KeyCode.F,Mode="Toggle",Callback=function(v) print("Fly:",v) end})
S:Keybind({Name="Hold action",Default=Enum.KeyCode.Q,Mode="Hold",Callback=function(v) print("Holding:",v) end})
local notes=Tab:Section({Name="Interaction",Side="Right"})
notes:Paragraph({Title="Click, then press",Content="Click a key chip to rebind it. Focus this preview before using the shortcut."})`,
  'color-picker': `S:ColorPicker({Name="Accent colour",Default=Color3.fromRGB(127,178,255),Callback=function(c) print("Colour: #"..c:ToHex()) end})
local notes=Tab:Section({Name="Interaction",Side="Right"})
notes:Paragraph({Title="Open the swatch",Content="Adjust hue and saturation, or enter a hexadecimal colour."})`,
  content: `S:Label("A short line of supporting text.")
S:Paragraph({Title="A little more context",Content="Paragraphs wrap to the available width and grow with their content."})`,
  themes: `S:Toggle({Name="Sprint",Default=true})
S:Slider({Name="Walk speed",Min=16,Max=100,Default=32})
S:Button({Name="Run action",Callback=function() print("Theme demo action fired") end})
local presets=Tab:Section({Name="Presets",Side="Right"})
for _,name in {"Graphite","Ink","Slate","Ember"} do presets:Button({Name=name,Callback=function() Hub:SetTheme(name) print("Theme:",name) end}) end`,
  notifications: `S:Button({Name="Show notification",Callback=function() Hub:Notify({Title="Saved",Content="Your profile is ready.",Icon="check",Duration=4}) print("Notification shown for 4 seconds") end})
S:Paragraph({Title="Try the notification",Content="Click the button. Hover the toast to pause its timer, or click to dismiss."})`,
  setup: `Hub:OpenSetup()`,
  configs: `S:Toggle({Name="Sprint",Flag="DocsSprint",Default=true})
S:Slider({Name="Walk speed",Flag="DocsSpeed",Min=16,Max=100,Default=32})
local profiles=Tab:Section({Name="Profiles",Side="Right"})
profiles:Button({Name="Save demo",Callback=function() local ok,err=Hub:SaveConfig("demo") print(ok and "Saved demo config" or err) end})
profiles:Button({Name="Load demo",Callback=function() local ok,err=Hub:LoadConfig("demo") print(ok and "Restored demo values" or err) end})`,
  pins: `S:Toggle({Name="Sprint",Default=true})
S:Slider({Name="Walk speed",Min=16,Max=100,Default=32})
local actions=Tab:Section({Name="Pinning",Side="Right"})
actions:Button({Name="Pin movement",Callback=function() S:Pin(Vector2.new(24,90)) print("Section pinned. Drag its header to move it.") end})
actions:Button({Name="Unpin movement",Callback=function() S:Unpin() print("Section returned to its tab.") end})`,
}
// The auth gate runs before any hub exists, so its example replaces the shared hub scaffold.
// Request stands in for the key server: it accepts RIFT-DEMO and answers with a hub script.
const authDemo = (theme: string) => `local Rift=loadstring(game:HttpGet("https://raw.githubusercontent.com/Naymmmm/riftui/main/public/Loader.luau"))()
getgenv().DocsRift=Rift
local hub=[==[
local Rift=getgenv().DocsRift
local Hub=Rift:CreateHub({Name="RiftUI example",Id="docs-example",HubIcon="rocket",ThemeName=${JSON.stringify(theme)},Setup=false,Settings=false,Loading={MinDuration=0.6}})
local Tab=Hub:Tab({Name="Example",Icon="sliders-horizontal"})
local S=Tab:Section({Name="Controls",Side="Left"})
S:Paragraph({Title="Unlocked",Content="The server accepted the key and sent this hub, which the script then ran with loadstring."})
S:Button({Name="Run action",Callback=function() print("Hub is ready") end})
Hub:Open(Tab)
]==]
task.spawn(function()
  local source=Rift:CreateAuth({Name="RiftUI example",Id="docs-auth",HubIcon="rocket",ThemeName=${JSON.stringify(theme)},Remember=false,
    Note="Use the demo key RIFT-DEMO. A real gate sends the key to your server.",
    GetKeyUrl="https://riftui.naymmm.lol/#auth",Discord="https://discord.gg/your-invite",
    Request=function(key) task.wait(0.6) if key=="RIFT-DEMO" then return true,hub end return false,"Invalid key. Try RIFT-DEMO." end})
  if not source then print("Auth closed") return end
  print("Key accepted, loading the hub")
  loadstring(source)()
end)`
export function demoSource(name: DemoName, theme = 'Graphite'): string {
  if (!themes.includes(theme as typeof themes[number])) theme = 'Graphite'
  if (name === 'auth') return authDemo(theme)
  return [
    'local Rift=loadstring(game:HttpGet("https://raw.githubusercontent.com/Naymmmm/riftui/main/public/Loader.luau"))()',
    name === 'requirements' ? 'getgenv().featureReady=false' : '',
    'local Hub=Rift:CreateHub({Name="RiftUI example",Id="docs-example",ThemeName=' + JSON.stringify(theme) + ',Setup=false,Settings=false' + (name === 'loading' ? ',HubIcon="rocket",Loading={Manual=true,Subtitle="Fetching game data"}' : '') + (name === 'requirements' ? ',Requirements={Feature={Name="Feature API",Test=function() return getgenv().featureReady==true,"Enable the developer test to use this feature" end}}' : '') + (name === 'stealth' ? ',Stealth=true' : '') + '})',
    'local Tab=Hub:Tab({Name="' + (name === 'overview' ? 'Movement' : name === 'themes' ? 'Appearance' : 'Example') + '",Icon="' + (name === 'themes' ? 'palette' : 'sliders-horizontal') + '"})',
    name === 'overview' ? '' : 'local S=Tab:Section({Name="' + (name === 'pins' ? 'Movement' : 'Controls') + '",Side="Left"})',
    examples[name],
    name === 'setup' ? '' : 'task.defer(function() Hub:Open(Tab) end)',
  ].join('\n')
}
