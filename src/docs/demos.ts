export const themes = ['Graphite', 'Ink', 'Slate', 'Ember'] as const
export type DemoName = 'overview' | 'button' | 'toggle' | 'slider' | 'dropdown' | 'input' | 'keybind' | 'color-picker' | 'content' | 'themes' | 'notifications' | 'setup' | 'configs' | 'pins' | 'command-palette'
export const demoNames: DemoName[] = ['overview', 'button', 'toggle', 'slider', 'dropdown', 'input', 'keybind', 'color-picker', 'content', 'themes', 'notifications', 'setup', 'configs', 'pins', 'command-palette']
const examples: Record<DemoName, string> = {
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
S:Input({Name="Live text",Placeholder="Type here",Finished=false,Callback=function(v) print("Live text:",v) end})`,
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
export function demoSource(name: DemoName, theme = 'Graphite'): string {
  if (!themes.includes(theme as typeof themes[number])) theme = 'Graphite'
  return [
    'local Rift=loadstring(game:HttpGet("https://raw.githubusercontent.com/Naymmmm/riftui/main/public/Loader.luau"))()',
    'local Hub=Rift:CreateHub({Name="RiftUI example",Id="docs-example",ThemeName=' + JSON.stringify(theme) + ',Setup=false,Settings=false})',
    'local Tab=Hub:Tab({Name="' + (name === 'overview' ? 'Movement' : name === 'themes' ? 'Appearance' : 'Example') + '",Icon="' + (name === 'themes' ? 'palette' : 'sliders-horizontal') + '"})',
    name === 'overview' ? '' : 'local S=Tab:Section({Name="' + (name === 'pins' ? 'Movement' : 'Controls') + '",Side="Left"})',
    examples[name],
    name === 'setup' ? '' : 'task.defer(function() Hub:Open(Tab) end)',
  ].join('\n')
}
