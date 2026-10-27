import type { DemoName } from './demos'

export interface DocSection {
  id: string
  title: string
  text?: string[]
  code?: string
  columns?: string[]
  rows?: string[][]
  note?: string
}
export interface DocPage {
  slug: string
  title: string
  group: string
  summary: string
  demo?: DemoName
  hint?: string
  sections: DocSection[]
}
const loader = 'local Rift = loadstring(game:HttpGet(\n    "https://raw.githubusercontent.com/Naymmmm/riftui/main/public/Loader.luau"\n))()'
const optionColumns = ['Option', 'Type', 'Default', 'Description']
const control = (slug: string, title: string, summary: string, hint: string, code: string, rows: string[][], behavior: string[], methods: string): DocPage => ({
  slug, title, group: 'Components', summary, demo: slug as DemoName, hint,
  sections: [
    { id: 'usage', title: 'Usage', text: ['These examples assume you have a <code>Section</code>. Follow <a href="#first-hub">Your first hub</a> to create one.'], code },
    { id: 'behavior', title: 'What happens', text: behavior },
    { id: 'options', title: 'Options', columns: optionColumns, rows },
    { id: 'methods', title: 'Working with the control', code: methods, text: ['Use <code>:SetVisible(false)</code> to hide the row. Callbacks run asynchronously; errors are caught and reported by RiftUI.'] },
  ],
})
export const pages: DocPage[] = [
  {
    slug: 'quick-start', title: 'Quick start', group: 'Getting started',
    summary: 'Build a dock-style script hub in Luau. See what you’re making, try the controls, then copy the code.',
    demo: 'overview', hint: 'Try the toggle, drag the slider, or run the action. The output below the example shows the callback.',
    sections: [
      { id: 'load', title: 'Load the library', text: ['RiftUI runs in a sUNC-compatible executor. The loader returns the library; it does not create a hub until you call <code>:CreateHub()</code>.'], code: loader },
      { id: 'build', title: 'Create something useful', text: ['Start with a hub, give it a tab, then add a section and its controls. Clicking a toolbar tile opens its panel. Clicking outside closes it.'], code: `local Hub = Rift:CreateHub({
    Name = "My Hub",
    Id = "my-hub",
})
local Main = Hub:Tab({ Name = "Movement", Icon = "footprints" })
local Section = Main:Section({ Name = "Movement" })

Section:Toggle({
    Name = "Sprint",
    Flag = "Sprint",
    Default = true,
    Callback = function(enabled)
        print("Sprint:", enabled)
    end,
})` },
      { id: 'next', title: 'Where to go next', text: ['Explore <a href="#button">buttons</a>, <a href="#slider">sliders</a> and the rest of the components. Use <a href="#themes">themes</a> to change the look, or <a href="/simulator">open RiftSim</a> to write a complete script.'], note: 'Documentation demos change sample values only. They do not modify a Roblox game. Live demos run the actual Luau library in the browser simulator.' },
    ],
  },
  {
    slug: 'installation', title: 'Installation & loader', group: 'Getting started',
    summary: 'Load the current library, or keep a hub on one exact commit.',
    sections: [
      { id: 'loader', title: 'Use the loader', code: loader, text: ['No package installation is needed in an executor. Keep the returned <code>Rift</code> table for creating hubs and accessing flags.'] },
      { id: 'pin', title: 'Pin an exact revision', code: 'getgenv().riftcommit = "YOUR_COMMIT_SHA"\n' + loader, text: ['Replace the placeholder with a 7–40 character hexadecimal commit SHA. Prefer the full 40 characters. The selected commit must contain <code>public/RiftUI.luau</code>.', 'The library and asset URLs use the same revision. Pinned assets have a separate cache under <code>RiftUI/assets/&lt;SHA&gt;/</code>. The loader never falls back to a different revision if the pin fails.'], note: 'The loader URL above uses main; riftcommit pins the library it downloads. Pin the loader URL itself too if you need the bootstrap script to remain immutable.' },
      { id: 'latest', title: 'Return to main', code: 'getgenv().riftcommit = nil\n' + loader, text: ['<code>Rift.Commit</code> reports the revision selected by the loader. With no pin it returns <code>"main"</code>.'] },
      { id: 'local', title: 'Use the simulator locally', code: 'pnpm install\npnpm dev\n\n# Build the simulator and these docs\npnpm build', text: ['RiftSim is available at <code>/simulator</code>, and this documentation at <code>/</code>. Main-revision URLs resolve to the local project. Pinned commits are fetched from GitHub.'] },
    ],
  },
  {
    slug: 'first-hub', title: 'Your first hub', group: 'Getting started', demo: 'overview',
    summary: 'A hub owns the toolbar. Tabs own sections. Sections own controls.',
    sections: [
      { id: 'complete', title: 'A complete script', code: loader + `

xpcall(function()
    local Hub = Rift:CreateHub({
        Name = "My Hub",
        Id = "my-hub",
        Subtitle = "Movement",
        ToggleKey = Enum.KeyCode.RightShift,
    })
    local Tab = Hub:Tab({ Name = "Movement", Icon = "footprints" })
    local Section = Tab:Section({ Name = "Movement", Side = "Left" })
    Section:Button({
        Name = "Say hello",
        Callback = function()
            Hub:Notify({ Title = "Hello", Content = "Your hub is working." })
        end,
    })
end, Rift.HandleError)` },
      { id: 'structure', title: 'How it fits together', columns: ['Object', 'Created with', 'Responsible for'], rows: [['Library', 'Loader.luau', 'Hub creation, flags, themes and error reporting.'], ['Hub', 'Rift:CreateHub(options)', 'Toolbar, panels, setup, files and notifications.'], ['Tab', 'Hub:Tab(options)', 'A toolbar tile and its panel content.'], ['Section', 'Tab:Section(options)', 'A group of controls, optionally pinnable.'], ['Control', 'Section:Button(options), etc.', 'An input, its value and its callback.']] },
      { id: 'identity', title: 'Give your hub a stable ID', text: ['<code>Id</code> determines the hub’s folder and identifies an earlier running copy. Re-running a hub with the same ID replaces that copy. Keep the ID stable when changing its display name.'] },
      { id: 'open', title: 'Open and close panels', code: 'Hub:Open(Tab)\nHub:Close()\nHub:SetToolbarVisible(false)\nHub:SetToolbarVisible(true)', text: ['Right Shift toggles the toolbar by default. On touch devices a restore handle appears when the toolbar is hidden.'] },
    ],
  },
  control('button', 'Button', 'A single action, fired when the user clicks. Use a toggle when you need an on/off value.', 'Click Run action. Watch the label and callback output update.',
    `local Button = Section:Button({
    Name = "Run action",
    Callback = function()
        print("Your action ran")
    end,
})`,
    [['Name', 'string', '"Button"', 'Label shown on the button.'], ['Danger', 'boolean', 'false', 'Uses the danger text colour.'], ['Callback', 'function()', '—', 'Called once for each click.']],
    ['The button highlights on hover, compresses to 97% while pressed, then releases. A click calls <code>Callback()</code> with no arguments.', 'A button does not hold a boolean value. Its callback is where your action belongs.'],
    'Button:SetText("Run again")\nButton:SetVisible(false)\nButton:OnChanged(function()\n    print("Button was clicked")\nend)'),
  control('toggle', 'Toggle', 'A checkbox with a boolean value. Enabled toggles also contribute to the tab’s badge count.', 'Click either row. Its callback reports true or false.',
    `local Toggle = Section:Toggle({
    Name = "Sprint",
    Flag = "Sprint",
    Default = true,
    Callback = function(enabled)
        print("Sprint:", enabled)
    end,
})`,
    [['Name', 'string', '—', 'The row label.'], ['Description', 'string', '—', 'Supporting text below the label.'], ['Default', 'boolean', 'false', 'Initial checked state.'], ['Flag', 'string', '—', 'Registers the control in Rift.Flags.'], ['Callback', 'function(boolean)', '—', 'Receives the new state.']],
    ['Clicking changes the value and calls the callback. A toggle whose default is <code>true</code> also calls its callback during creation.', 'The checkmark and label update together. The tab badge counts enabled, non-internal toggles.'],
    'Toggle:Set(false)\nprint(Toggle:Get()) -- false\nToggle:Set(true, true) -- update silently\nprint(Rift.Flags.Sprint.Value)'),
  control('slider', 'Slider', 'A numeric value with a range and a step. Drag the notch or type an exact value.',
    'Drag a slider, or click its number and enter a value.',
    `local Speed = Section:Slider({
    Name = "Walk speed",
    Flag = "WalkSpeed",
    Min = 16,
    Max = 100,
    Step = 1,
    Default = 32,
    Suffix = " studs/s",
    Callback = function(value)
        print("Walk speed:", value)
    end,
})`,
    [['Min / Max', 'number', '0 / 100', 'Allowed numeric range.'], ['Step', 'number', '1', 'Rounding increment. Use a positive number.'], ['Default', 'number', 'Min', 'Starting value, clamped to the range.'], ['Suffix', 'string', '""', 'Displayed after the value.'], ['Callback', 'function(number)', '—', 'Receives the rounded, clamped value.']],
    ['The value rounds to <code>Step</code> and stays between <code>Min</code> and <code>Max</code>. Callbacks receive numbers, without the displayed suffix.', 'For decimal values, choose a decimal step such as <code>0.05</code>.'],
    'Speed:Set(48)\nprint(Speed:Get()) -- 48\nSpeed:Set(32, true) -- no callback'),
  control('dropdown', 'Dropdown', 'Choose one option, or select several with Multi enabled.', 'Open Mode or Targets. Single selection closes the popup; multi-selection stays open.',
    `local Mode = Section:Dropdown({
    Name = "Mode",
    Options = { "Explore", "Build", "Practice" },
    Default = "Explore",
    Callback = function(value)
        print("Mode:", value)
    end,
})`,
    [['Options', '{ any }', '{}', 'Choices displayed in the list.'], ['Default', 'option or array', 'First option / {}', 'Selected value, or selected options for Multi.'], ['Multi', 'boolean', 'false', 'Allows multiple selected options.'], ['Callback', 'function(value)', '—', 'A single value or a map of selected options.']],
    ['A single-select dropdown returns the selected option. A multi-select returns a map such as <code>{ Players = true, NPCs = true }</code>.', 'Lists with more than eight options include a search field. Click outside to dismiss the popup.'],
    `Mode:Set("Build")
Mode:SetOptions({ "Explore", "Build", "Practice", "Test" })

local Targets = Section:Dropdown({
    Name = "Targets",
    Options = { "Players", "NPCs", "Objects" },
    Multi = true,
    Default = { "Players" },
})
Targets:Set({ "Players", "NPCs" })
print(Targets:Get().NPCs) -- true`),
  control('input', 'Input', 'A text field with a placeholder and a configurable commit behavior.', 'Edit Profile name and press Enter. Live text reports changes while you type.',
    `local Name = Section:Input({
    Name = "Profile name",
    Placeholder = "Enter a name",
    Default = "My profile",
    Callback = function(text)
        print("Profile name:", text)
    end,
})`,
    [['Default', 'string', '""', 'Initial field value.'], ['Placeholder', 'string', '""', 'Shown when the field is empty.'], ['Finished', 'boolean', 'true behavior', 'Set false to emit while editing.'], ['Callback', 'function(string)', '—', 'Receives the field text.']],
    ['By default the field commits on focus loss when its text changed, or when Enter is pressed. Set <code>Finished = false</code> to also receive changes as the user types.'],
    'Name:Set("Another profile")\nprint(Name:Get())\nName:Set("Quiet update", true)'),
  control('keybind', 'Keybind', 'Bind a keyboard key or mouse button to a toggle, hold action or binding-only control.',
    'Click a chip to rebind it, then focus this example and press the key. Escape cancels rebinding.',
    `local Fly = Section:Keybind({
    Name = "Fly toggle",
    Default = Enum.KeyCode.F,
    Mode = "Toggle",
    Callback = function(enabled)
        print("Fly:", enabled)
    end,
})`,
    [['Default', 'EnumItem', 'nil', 'Initial keyboard key or input type.'], ['Mode', 'string', '"Toggle"', 'Toggle, Hold, Always, or None for binding only.'], ['Callback', 'function(boolean)', '—', 'Receives the action state.'], ['ChangedCallback', 'function(EnumItem?)', '—', 'Receives a newly assigned binding.']],
    ['<code>Toggle</code> flips state on each press. <code>Hold</code> emits true on press and false on release. <code>Always</code> starts active; matching input emits its active state.', 'Keybind shortcuts are ignored while a text box has focus. The browser may reserve some shortcuts.'],
    'Fly:Set(Enum.KeyCode.G)\nprint(Fly:Get()) -- the assigned binding\nprint(Fly.State) -- the action state'),
  control('color-picker', 'Color picker', 'Choose a Color3 value through hue, saturation and hexadecimal input.',
    'Click the colour swatch to open the picker.',
    `local Colour = Section:ColorPicker({
    Name = "Accent colour",
    Default = Color3.fromRGB(127, 178, 255),
    Callback = function(color)
        print("#" .. color:ToHex())
    end,
})`,
    [['Default', 'Color3', 'White', 'Initial selected colour.'], ['Flag', 'string', '—', 'Includes the value in flag-based configs.'], ['Callback', 'function(Color3)', '—', 'Receives the selected colour.']],
    ['Dragging inside the square changes saturation and value. The hue strip changes hue. Hexadecimal entry updates the same value.', 'Changing the hub’s theme does not change a user-selected colour value. A colour picker only changes the theme if your callback explicitly does so.'],
    'Colour:Set(Color3.fromHex("FF9A5A"))\nprint(Colour:Get():ToHex())'),
  {
    slug: 'content', title: 'Labels & paragraphs', group: 'Components', demo: 'content',
    summary: 'Explain a setting with a short label or a paragraph that grows with its content.',
    sections: [
      { id: 'label', title: 'Label', code: 'local Status = Section:Label("Waiting for an action.")\nStatus:Set("Action complete.")', text: ['A label is a short, wrapped text row. Keep it concise.'] },
      { id: 'paragraph', title: 'Paragraph', code: `local Help = Section:Paragraph({
    Title = "Before you begin",
    Content = "Choose a profile, then adjust the controls below.",
})
Help:Set("Ready", "Your profile is loaded.")`, text: ['Paragraphs have a title and body. They wrap and grow vertically. <code>RichText = true</code> enables supported Roblox rich text in the body.'] },
    ],
  },
  {
    slug: 'themes', title: 'Themes', group: 'Guides', demo: 'themes',
    summary: 'Four built-in palettes, your own colour overrides, and a smooth transition between them.',
    hint: 'Choose a preset below, or open the live example and click its preset buttons. Colours tween over 250ms.',
    sections: [
      { id: 'presets', title: 'Pick a starting palette', code: `local Hub = Rift:CreateHub({
    Name = "My Hub",
    ThemeName = "Slate",
})

-- Change existing colours in place
Hub:SetTheme("Ember")`, text: ['<code>Graphite</code> is neutral near-black with a white accent. <code>Ink</code> goes darker. <code>Slate</code> uses cool blue-grey surfaces and a blue accent. <code>Ember</code> uses warm surfaces and an orange accent.'] },
      { id: 'overrides', title: 'Override individual colours', code: `local Hub = Rift:CreateHub({
    Name = "My Hub",
    ThemeName = "Graphite",
    Theme = {
        Accent = Color3.fromRGB(127, 178, 255),
        AccentText = Color3.fromRGB(8, 14, 24),
        Panel = Color3.fromRGB(13, 17, 23),
    },
})`, text: ['RiftUI starts with its default tokens, applies the named preset, then applies your <code>Theme</code> overrides. Saved Theme Studio colours are applied when the hub is created.', 'Set <code>AccentText</code> with <code>Accent</code> so text and checkmarks stay legible on the accent colour.'] },
      { id: 'tokens', title: 'Colour roles', columns: ['Token', 'Used for'], rows: [['Panel / PanelStroke', 'Floating surfaces and their outlines.'], ['Tile / TileHover / TileActive', 'Buttons and toolbar tile states.'], ['Text / SubText / Muted', 'Primary labels, secondary labels and supporting text.'], ['Field / FieldStroke', 'Inputs, key chips and checkboxes.'], ['Accent / AccentText', 'Selected states and the foreground drawn on them.'], ['Track / Knob', 'Slider tracks and scrollbars.'], ['Divider / Highlight', 'Section rules and top-edge sheen.'], ['Danger / Success / Warning', 'Feedback and status messages.']] },
      { id: 'transition', title: 'How live changes work', text: ['Setup, Settings and Theme Studio update existing objects instead of rebuilding the hub. Backgrounds, labels, strokes and accents tween to the new palette over 250ms.', 'Choosing again interrupts from the current colours. Control values, pins and the current panel remain in place. Cancelling Theme Studio returns to the previous colour palette.'] },
      { id: 'studio', title: 'Theme Studio', code: 'Hub:OpenThemeStudio()', text: ['Open Settings → Interface → Theme studio to choose a base palette, adjust the accent and configure a background. Colour changes preview live; Save keeps the selection in the hub’s <code>setup.json</code>.'] },
      { id: 'share', title: 'Save and share a theme', code: `local Look = {
    Format = "riftui-theme",
    Version = 1,
    Name = "Ocean",
    Base = "Slate",
    Colors = { Accent = "7FB2FF", AccentText = "080E18" },
}
Hub:SaveTheme(Look)
local code = Hub:ExportTheme(Look)
local imported = Hub:ImportTheme(code)
print(imported.Name) -- Ocean`, text: ['Saved themes live in <code>RiftUI/themes/</code>. Export codes begin with <code>RIFT1:</code>. Importing does not download an attached image; <code>:FetchThemeImage()</code> does that explicitly.'] },
    ],
  },
  {
    slug: 'backgrounds', title: 'Background images', group: 'Guides',
    summary: 'Place an image behind a panel while keeping its controls readable.',
    sections: [
      { id: 'source', title: 'Choose an image source', code: `Hub:SetBackground({
    File = "RiftUI/my-hub/background.png",
    Opacity = 0.6,
    Dim = 0.55,
    Fit = "Fill",
})`, text: ['Use <code>File</code> for an image already in the executor workspace. Alternatively use <code>Url</code> to download an image, or <code>Base64</code> for image data. PNG, JPEG, WebP and GIF headers are recognized.', 'The image is displayed with <code>getcustomasset</code>. If file functions or custom assets are unavailable, the hub keeps its ordinary panel background.', 'In RiftSim, blocked public image GETs retry through the Vite dev/preview server. A static-only deployment needs a backend proxy or a CORS-enabled host. Empty responses and HTML pages are reported separately from unsupported image formats.'] },
      { id: 'placement', title: 'Adjust the placement', code: `Hub:PlaceBackground({
    Fit = "Free",
    Anchor = "BottomRight",
    Scale = 0.75,
    OffsetX = -12,
    OffsetY = -12,
    Rotation = 0,
    Dock = true,
})`, text: ['<code>Fill</code> crops to cover the panel; <code>Fit</code> contains the image; <code>Stretch</code> ignores its aspect ratio. <code>Free</code> exposes anchoring, scale, offsets and rotation.', 'Anchors include Center, TopLeft, Top, TopRight, Left, Right, BottomLeft, Bottom and BottomRight. The same placement controls are available in Theme Studio.'] },
      { id: 'remove', title: 'Remove the background', code: 'Hub:SetBackground(nil)' },
    ],
  },
  {
    slug: 'notifications', title: 'Notifications & prompts', group: 'Guides', demo: 'notifications',
    summary: 'Give feedback without replacing the panel, or ask for a decision with a prompt.',
    hint: 'Click Show notification. Hover the toast to pause its timer; click it to dismiss.',
    sections: [
      { id: 'notify', title: 'Show a notification', code: `Hub:Notify({
    Title = "Saved",
    Content = "Your profile is ready.",
    Icon = "check",
    Duration = 4,
})`, text: ['A notification opens from a narrow slit, stays for its duration, then folds away. <code>Tone</code> accepts a Color3; <code>Force = true</code> permits it during stealth mode.'] },
      { id: 'prompt', title: 'Ask for a decision', code: `Hub:Prompt({
    Title = "Reset this profile?",
    Content = "Your current values will be replaced.",
    Buttons = {
        { Text = "Cancel" },
        {
            Text = "Reset",
            Primary = true,
            Callback = function()
                print("Reset confirmed")
            end,
        },
    },
})`, text: ['Prompts interrupt the screen, so reserve them for a decision. Buttons close the prompt unless <code>KeepOpen = true</code> is set. <code>Danger = true</code> applies the danger colour.'] },
    ],
  },
  {
    slug: 'setup', title: 'First-run setup', group: 'Guides', demo: 'setup',
    summary: 'Ask for initial preferences and check executor compatibility before a hub is used.',
    hint: 'Walk through the real setup: toolbar key, theme, then compatibility checks.',
    sections: [
      { id: 'flow', title: 'What the user sees', text: ['On the first launch, setup asks for a toolbar key, a theme, your optional hub-specific choices, then runs compatibility checks. A completed setup is remembered per hub ID.', 'Theme choices tween immediately. The compatibility page reports both failed checks and the features affected. It allows the user to finish with reduced functionality.'] },
      { id: 'choices', title: 'Add your own choices', code: `local Hub = Rift:CreateHub({
    Name = "My Hub",
    Id = "my-hub",
    Setup = {
        Title = "How do you play?",
        Description = "Sets the starting values. Change them later.",
        Options = {
            {
                Type = "Dropdown",
                Name = "Play style",
                Flag = "PlayStyle",
                Options = { "Legit", "Balanced", "Blatant" },
                Default = "Legit",
            },
        },
    },
})
print(Rift.Flags.PlayStyle.Value)` },
      { id: 'control', title: 'Skip or reopen setup', code: '-- Disable first-run setup\nlocal Hub = Rift:CreateHub({ Name = "My Hub", Setup = false })\n\n-- Open it again later\nHub:OpenSetup()', text: ['Settings → RiftUI → Run setup again also opens the flow. Setup data lives at <code>RiftUI/&lt;Id&gt;/setup.json</code>.'] },
    ],
  },
  {
    slug: 'configs', title: 'Flags & configs', group: 'Guides', demo: 'configs',
    summary: 'Give controls stable flags, then save and restore a profile.',
    hint: 'Save the demo, change the values, then load it. Demo files stay in this preview’s memory.',
    sections: [
      { id: 'flags', title: 'Register a value', code: `local Sprint = Section:Toggle({
    Name = "Sprint",
    Flag = "Sprint",
    Default = false,
})
print(Rift.Flags.Sprint.Value)
Rift.Flags.Sprint:Set(true)`, text: ['Use unique flag names. <code>Rift.Flags</code> maps each name to its control object, not directly to the raw value. Read <code>.Value</code> or call <code>:Get()</code>.'] },
      { id: 'save', title: 'Save and load', code: `local ok, err = Hub:SaveConfig("default")
if not ok then warn(err) end

local loaded, loadError = Hub:LoadConfig("default")
if not loaded then warn(loadError) end

print(Hub:ListConfigs())
Hub:SetAutoload("default")`, text: ['Configs save flagged values plus the toolbar key, scale and pins. Files live under <code>RiftUI/&lt;Id&gt;/configs/</code>. File support is feature-detected; failed operations return a reason.'] },
      { id: 'manage', title: 'Manage profiles', code: 'Hub:DeleteConfig("default")\nHub:SetAutoload(nil) -- stop auto-loading', text: ['Themes and backgrounds are kept in setup data rather than individual flag-based configs.'] },
    ],
  },
  {
    slug: 'pins', title: 'Pinning sections', group: 'Guides', demo: 'pins',
    summary: 'Keep a small group of controls on screen while the toolbar is hidden.',
    hint: 'Pin the movement section, drag its header, then return it to the tab.',
    sections: [
      { id: 'pin', title: 'Pin and unpin', code: 'Section:Pin(Vector2.new(24, 90))\nSection:Unpin()', text: ['The section’s rows move into a floating card. Drag its header to reposition it. Unpinning returns the same controls to the original section.'] },
      { id: 'disable', title: 'Disable pinning for a section', code: 'local Section = Tab:Section({\n    Name = "About",\n    Pinnable = false,\n})', text: ['Users can also pin a section with its header pin icon. Saved configs can restore pinned sections and their positions.'] },
    ],
  },
  {
    slug: 'hub-api', title: 'Hub API', group: 'Reference',
    summary: 'The options and methods that manage a hub’s lifecycle and layout.',
    sections: [
      { id: 'options', title: 'CreateHub options', columns: optionColumns, rows: [['Name', 'string', '"Rift Hub"', 'Display name.'], ['Id', 'string', 'Derived from Name', 'Stable identity and per-hub folder.'], ['Subtitle', 'string', '""', 'Supporting hub text.'], ['ToggleKey', 'Enum.KeyCode', 'RightShift', 'Toolbar visibility shortcut.'], ['ThemeName', 'string', '"Graphite"', 'Built-in palette name.'], ['Theme', 'table', '{}', 'Colour overrides.'], ['Setup', 'boolean or table', 'Enabled', 'First-run flow and optional custom choices.'], ['Settings', 'boolean', 'true', 'Built-in Settings tab.'], ['Stealth', 'boolean', 'false', 'Random names, suppressed notifications, hidden toolbar.']] },
      { id: 'layout', title: 'Layout and visibility', columns: ['Method', 'Effect'], rows: [['Hub:Tab({ Name, Icon, Description })', 'Creates a toolbar tile and content page.'], ['Tab:Section({ Name, Side, Pinnable })', 'Creates a section; Side is Left or Right, otherwise balanced.'], ['Hub:Open(Tab) / Hub:Close()', 'Opens or closes the current panel.'], ['Hub:SetToolbarVisible(boolean)', 'Shows or hides the toolbar.'], ['Hub:SetScale(number)', 'Sets interface scale, clamped to 0.6–1.5.']] },
      { id: 'lifecycle', title: 'Lifecycle', code: 'Hub:Reinitialize() -- rebuild, preserve values and references\nHub:Destroy() -- remove the GUI and connections', text: ['<code>Reinitialize</code> replays the hub’s recorded calls and forwards old references to the new controls. Theme changes do not require a rebuild.'] },
      { id: 'errors', title: 'Handle loading errors', code: 'xpcall(function()\n    -- Create your hub and controls here\nend, Rift.HandleError)', text: ['<code>Rift.HandleError</code> records the error and shows a failure card. Control callbacks have their own error capture. Developer Mode exposes the state history and captured errors.'] },
    ],
  },
  {
    slug: 'compatibility', title: 'Executor compatibility', group: 'Reference',
    summary: 'RiftUI checks the functions it needs and keeps working with the features available.',
    sections: [
      { id: 'checks', title: 'Run the compatibility check', code: 'local results = Hub:RunCompatibilityCheck()\nfor _, result in results do\n    print(result.Name, result.Ok, result.Impact)\nend', text: ['Setup calls the same checks. Passing these library-specific checks does not mean an executor passes the entire sUNC test suite.'] },
      { id: 'fallbacks', title: 'What happens when something is missing', columns: ['Capability', 'Fallback or limitation'], rows: [['gethui', 'Falls back to CoreGui, then PlayerGui if needed.'], ['cloneref', 'Uses service references directly.'], ['File functions', 'Configs and setup cannot be saved.'], ['getcustomasset', 'Custom images and shadows are unavailable; icons use text fallbacks.'], ['listfiles', 'Saved config and theme lists may be unavailable.'], ['setclipboard', 'Copying to the clipboard is unavailable.'], ['game:HttpGet', 'Remote libraries and assets cannot be downloaded.']] },
      { id: 'simulator', title: 'Test weaker profiles', text: ['Open <a href="/simulator">RiftSim</a> and use its Executor picker. The profiles are simulated, invented executors that remove or break selected functions. They let you inspect fallbacks without launching a game.'], note: 'Browser previews approximate Roblox rendering. Roblox-only assets, browser-reserved keys and cross-origin requests have platform limits. Test your finished hub in its target executor too.' },
    ],
  },
]
export const groups = ['Getting started', 'Components', 'Guides', 'Reference']
export const getPage = (slug: string) => pages.find(p => p.slug === slug)
