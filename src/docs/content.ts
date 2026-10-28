import type { DemoName } from './demos'
import showcase from '../../examples/showcase.luau?raw'

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
  navTitle?: string
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
    slug: 'introduction', navTitle: 'Introduction', title: 'RiftUI library for Roblox', group: 'Overview',
    summary: 'A dock-style UI library for Roblox script hubs. Floating panels, a command palette, live theming, and a browser simulator to build it all without launching a game.',
    sections: [
      { id: 'loader', title: 'Load RiftUI', text: ['Load the library, create a hub, then add tabs, sections and controls. The official loader fetches RiftUI and its assets from this repository.'], code: loader },
      { id: 'included', title: 'What’s included', text: ['A compact toolbar opens floating panels. Pin sections, search controls with the <a href="#command-palette">command palette</a>, or move detailed settings into <a href="#hub-api">child windows</a>.', 'Build with buttons, toggles, sliders, player pickers, logs and live meters. <a href="#themes">Themes</a>, <a href="#translations">translations</a> and <a href="#configs">saved configs</a> are built in.'] },
      { id: 'start', title: 'Get started', text: ['Follow the <a href="#quick-start">quick start</a> to build your first hub, or try the <a href="#showcase">feature tour</a>, a demo hub that uses every feature. Each component page includes code, a screenshot and a live example.'] },
      { id: 'simulator', title: 'Preview in the docs', text: ['<a href="/simulator">RiftSim</a> is an optional browser workspace for trying your hub without launching Roblox. It runs the same Luau library with a simulated ScreenGui and sample game data. Your finished hub runs independently of the simulator.'] },
      { id: 'source', title: 'Source & license', text: ['RiftUI is open source under the <a href="https://github.com/Naymmmm/riftui/blob/main/LICENSE">Mozilla Public License 2.0</a>. Report issues or contribute on <a href="https://github.com/Naymmmm/riftui">GitHub</a>.'] },
    ],
  },
  {
    slug: 'quick-start', title: 'Quick start', group: 'Getting started',
    summary: 'Build a dock-style script hub in Luau. See what you’re making, try the controls, then copy the code.',
    demo: 'overview', hint: 'Try the toggle, drag the slider, or run the action. The output below the example shows the callback.',
    sections: [
      { id: 'load', title: 'Load the library', text: ['RiftUI runs in a sUNC-compatible executor. The loader returns the library; it does not create a hub until you call <code>:CreateHub()</code>.'], code: loader },
      { id: 'build', title: 'Add controls', text: ['Start with a hub, give it a tab, then add a section and its controls. Click a tab in the toolbar to open its panel. Clicking outside closes it.'], code: `local Hub = Rift:CreateHub({
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
      { id: 'structure', title: 'How it fits together', columns: ['Object', 'Created with', 'Responsible for'], rows: [['Library', 'Loader.luau', 'Hub creation, flags, themes and error reporting.'], ['Hub', 'Rift:CreateHub(options)', 'Toolbar, panels, setup, files and notifications.'], ['Tab', 'Hub:Tab(options)', 'A toolbar tab and its panel content.'], ['Section', 'Tab:Section(options)', 'A group of controls, optionally pinnable.'], ['Control', 'Section:Button(options), etc.', 'An input, its value and its callback.']] },
      { id: 'identity', title: 'Give your hub a stable ID', text: ['<code>Id</code> determines the hub’s folder and identifies an earlier running copy. Re-running a hub with the same ID replaces that copy. Keep the ID stable when changing its display name.'] },
      { id: 'open', title: 'Open and close panels', code: 'Hub:Open(Tab)\nHub:Close()\nHub:SetToolbarVisible(false)\nHub:SetToolbarVisible(true)', text: ['Right Shift toggles the toolbar by default. On touch devices, the button below the toolbar switches between Hide toolbar and Show toolbar. It stays available in both states.'] },
    ],
  },
  {
    slug: 'showcase', navTitle: 'Feature tour', title: 'Feature tour', group: 'Getting started', demo: 'showcase',
    summary: 'One demo hub that uses every RiftUI feature. It runs on sample data and never touches the game.',
    hint: 'Switch to Try it live, enter the key DEMO, then finish or skip setup. Open each toolbar tab to explore.',
    sections: [
      { id: 'run', title: 'Run the tour', text: ['Paste the script below into your executor or <a href="/simulator">RiftSim</a>. It starts with a key gate; the demo key is <kbd>DEMO</kbd>. A loading card stays up while the tabs are built, then first-run setup appears.', 'The source is <a href="https://github.com/Naymmmm/riftui/blob/main/examples/showcase.luau">examples/showcase.luau</a>. Copy any section of it into your own hub.'] },
      { id: 'contents', title: 'What each tab shows', columns: ['Tab', 'Features'], rows: [
        ['Key gate', 'CreateAuth with a stand-in Request, a remembered key, Get key and Discord links, and HubIcon.'],
        ['Startup', 'A manual loading screen, first-run setup, requirements, translations, the watermark and the keybind list.'],
        ['Controls', 'Buttons, toggles, a dependent group, sliders, dropdowns, segmented choices, a stepper, a range slider, keybinds, a colour picker and a section that starts collapsed.'],
        ['Text & data', 'A multiline code input, a paragraph, an editable list and a console.'],
        ['Live', 'Stats, progress bars and sparklines fed by a demo data loop.'],
        ['People', 'A tab badge and a player picker in a section gated by a requirement.'],
        ['Hub', 'A child window with two tabs and a Discord button, notifications and prompts, the command palette, themes and Theme Studio, scale, language, configs and pins.'],
      ] },
      { id: 'source', title: 'Full script', code: showcase },
    ],
  },
  {
    slug: 'command-palette', title: 'Command palette', group: 'Guides', demo: 'command-palette',
    summary: 'Find a tab, setting or control without hunting through panels.',
    hint: 'Type Walk speed, then select the result. Reopen with the toolbar search button or F2 after focusing the preview.',
    sections: [
      { id: 'open', title: 'Open from anywhere', text: ['Click the search icon at the start of the toolbar, or press <kbd>F2</kbd>. On phones, tap the same search button. If the toolbar is hidden, use Show toolbar first. Shortcuts stay inactive while you type in another text field or bind a key.'], code: 'Hub:OpenCommandPalette()\nHub:CloseCommandPalette()' },
      { id: 'search', title: 'Search and jump', text: ['With nothing typed, the palette lists your recent jumps, then tabs, windows and actions. Typing searches tab, section and control names, ignoring letter case, and groups results under their tab or window. Every word must match, or type initials: <kbd>fov</kbd> finds Field of view. Exact names appear first. The box shrinks to fit its results. Hidden controls and supporting labels are omitted. Up and Down select a result, Enter opens it, and Escape or the close button dismisses the palette.', 'Selecting a control opens its tab, scrolls it into view and briefly highlights its row. Pinned controls stay pinned. Values and control callbacks stay unchanged. Built-in action results, such as Hide toolbar and Run setup again, perform their named action. Results show up to 40 matches; keep typing to narrow a longer list.'] },
      { id: 'shortcut', title: 'Choose a shortcut', text: ['Use CommandKey when creating the hub, call SetCommandKey later, or change Command palette key under Settings → Interface. The changed shortcut is saved per hub and included in saved configs. Use a different key from your toolbar shortcut and control keybinds.'], code: 'local Hub = Rift:CreateHub({\n    Name = "My Hub",\n    CommandKey = Enum.KeyCode.F2,\n})\n\nHub:SetCommandKey(Enum.KeyCode.F3)' },
    ],
  },
  {
  "slug": "range-slider",
  "title": "Range slider",
  "group": "Components",
  "summary": "Drag two handles to choose a minimum and maximum.",
  "demo": "range-slider",
  "sections": [
    {
      "id": "usage",
      "title": "Usage",
      "code": "local Range = Section:RangeSlider({\n    Name = \"Delay\", Min = 0, Max = 500, Step = 10,\n    Default = {40, 120}, Suffix = \" ms\", Flag = \"Delay\",\n    Callback = function(low, high) print(low, high) end,\n})"
    },
    {
      "id": "behavior",
      "title": "Behavior",
      "text": [
        "Value is {Min, Max}. Handles stop against each other. Set accepts {low, high} or {Min = low, Max = high}, sorts and clamps both values. Pass true as the second argument to Set to suppress callbacks."
      ]
    },
    {
      "id": "methods",
      "title": "Methods",
      "code": "Range:Set({60, 180})\nlocal low, high = Range:Get()"
    }
  ]
},
  {
  "slug": "progress",
  "title": "Progress / meter",
  "group": "Components",
  "summary": "A read-only meter for values supplied by your script.",
  "demo": "progress",
  "sections": [
    {
      "id": "usage",
      "title": "Usage",
      "code": "local Meter = Section:Progress({\n    Name = \"Health\", Min = 0, Max = 100, Default = 82,\n    Segments = 6, -- omit for a continuous bar\n})"
    },
    {
      "id": "behavior",
      "title": "Behavior",
      "text": [
        "Set and Update clamp to Min and Max. Supply Color for a fixed fill colour, or Format(value, min, max) for custom readout text. Values animate; this control has no input callback."
      ]
    },
    {
      "id": "methods",
      "title": "Methods",
      "code": "Meter:Set(65)\nMeter:Update(72)\nlocal value = Meter:Get()"
    }
  ]
},
  {
  "slug": "stat",
  "title": "Stat row",
  "group": "Components",
  "summary": "A live monospace value with optional change indicators.",
  "demo": "stat",
  "sections": [
    {
      "id": "usage",
      "title": "Usage",
      "code": "local Stat = Section:Stat({\n    Name = \"Money\", Default = 12500, Suffix = \" $\",\n    Delta = true, HigherIsBetter = true,\n})"
    },
    {
      "id": "behavior",
      "title": "Behavior",
      "text": [
        "The label updates only when formatted text changes. Delta shows gains or losses briefly in green or red. Set HigherIsBetter = false for metrics where a decrease is good. Format(value) replaces the default number formatter."
      ]
    },
    {
      "id": "methods",
      "title": "Methods",
      "code": "Stat:Update(12600)\nlocal value = Stat:Get()"
    }
  ]
},
  {
  "slug": "sparkline",
  "title": "Sparkline",
  "group": "Components",
  "summary": "A small rolling graph for a stream of numeric samples.",
  "demo": "sparkline",
  "sections": [
    {
      "id": "usage",
      "title": "Usage",
      "code": "local Graph = Section:Sparkline({\n    Name = \"Frame rate\", Points = 40, Suffix = \" fps\",\n    Min = 0, Max = 120, -- omit to fit the observed range\n})"
    },
    {
      "id": "behavior",
      "title": "Behavior",
      "text": [
        "Points is clamped to 4–120. Push appends a sample and drops the oldest once full. Provide samples from your own timer; the graph does not poll FPS or other data automatically. Color, Step and Format customise the line and readout."
      ]
    },
    {
      "id": "methods",
      "title": "Methods",
      "code": "Graph:Push(60)\nGraph:Update(58) -- alias for Push\nGraph:Clear()\nlocal newest = Graph:Get()"
    }
  ]
},
  {
  "slug": "segmented",
  "title": "Segmented control",
  "group": "Components",
  "summary": "Keep a short choice visible instead of opening a dropdown.",
  "demo": "segmented",
  "sections": [
    {
      "id": "usage",
      "title": "Usage",
      "code": "local Mode = Section:Segmented({\n    Name = \"Mode\", Options = {\"Explore\", \"Build\", \"Practice\"},\n    Default = \"Explore\", Flag = \"Mode\",\n    Callback = function(value) print(value) end,\n})"
    },
    {
      "id": "behavior",
      "title": "Behavior",
      "text": [
        "Use two to four short options. The active segment moves to the selected option. Unknown values are ignored. Set(value, true) changes the choice silently."
      ]
    },
    {
      "id": "methods",
      "title": "Methods",
      "code": "Mode:Set(\"Build\")\nlocal value = Mode:Get()"
    }
  ]
},
  {
  "slug": "stepper",
  "title": "Number stepper",
  "group": "Components",
  "summary": "Increase or decrease a small numeric value.",
  "demo": "stepper",
  "sections": [
    {
      "id": "usage",
      "title": "Usage",
      "code": "local Burst = Section:Stepper({\n    Name = \"Burst\", Min = 1, Max = 5, Step = 1, Default = 1,\n    Flag = \"Burst\", Callback = function(value) print(value) end,\n})"
    },
    {
      "id": "behavior",
      "title": "Behavior",
      "text": [
        "Press plus or minus once to step, or hold to repeat faster. Values round to Step and stay within Min and Max. Set(value, true) suppresses callbacks. Description and Suffix are optional."
      ]
    },
    {
      "id": "methods",
      "title": "Methods",
      "code": "Burst:Set(3)\nlocal value = Burst:Get()"
    }
  ]
},
  {
  "slug": "console",
  "title": "Log / console",
  "group": "Components",
  "summary": "A bounded, scrollable log with copy and clear actions.",
  "demo": "console",
  "sections": [
    {
      "id": "usage",
      "title": "Usage",
      "code": "local Log = Section:Console({\n    Name = \"Events\", Height = 150, MaxLines = 200,\n    Placeholder = \"Nothing logged yet\",\n})"
    },
    {
      "id": "behavior",
      "title": "Behavior",
      "text": [
        "The copy button uses the executor clipboard function. New entries follow the end only while the reader is already there. MaxLines caps retained entries. Print is an alias for Log; this is your script’s log, not an automatic capture of every print."
      ]
    },
    {
      "id": "methods",
      "title": "Methods",
      "code": "Log:Log(\"Ready\")\nLog:Log(\"Retrying\", \"warn\")\nLog:Log(\"Failed\", \"error\")\nlocal text = Log:Get()\nLog:Clear()"
    }
  ]
},
  {
  "slug": "list",
  "title": "List / table",
  "group": "Components",
  "summary": "Rows of data your script owns, with optional columns, selection and remove buttons.",
  "demo": "list",
  "hint": "Click a row to select it, hover a row and press × to remove it, or add a waypoint.",
  "sections": [
    {
      "id": "usage",
      "title": "Usage",
      "code": "local Waypoints = Section:List({\n    Name = \"Waypoints\",\n    Columns = { \"Name\", \"Position\" },\n    Items = {\n        { \"Spawn\", \"0, 5, 0\" },\n        { \"Shop\", \"42, 3, -18\" },\n    },\n    Removable = true,\n    Callback = function(item, index)\n        print(\"Selected\", item[1])\n    end,\n    OnRemove = function(item, index)\n        print(\"Removed\", item[1])\n    end,\n})"
    },
    {
      "id": "behavior",
      "title": "Behavior",
      "text": [
        "An item is a string or an array of cell values; each value is shown with tostring. Without Columns the list has one column and Get returns plain strings. With Columns, a header is added and each row is split into cells. Later columns use a monospace font unless Monospace is false.",
        "Clicking a row selects it and calls Callback with a copy of the item and its index. The remove button drops the row first, then calls OnRemove. Lists hold data, not settings, so they are not saved in configs."
      ]
    },
    {
      "id": "options",
      "title": "Options",
      "columns": ["Option", "Type", "Default", "Description"],
      "rows": [
        ["Items", "{ string | { string } }", "{}", "Initial rows."],
        ["Columns", "{ string }", "—", "Header labels. Omit for a single-column list."],
        ["Widths", "{ number }", "equal", "Relative column widths, such as { 2, 1 }."],
        ["Height", "number", "156", "Height of the scrolling area in pixels."],
        ["Selectable", "boolean", "true", "Set false for a read-only list."],
        ["Removable", "boolean", "false", "Adds a remove button to each row. Implied by OnRemove."],
        ["MaxItems", "number", "—", "Drops the oldest rows past this count."],
        ["Placeholder", "string", "\"Nothing here yet\"", "Shown when the list is empty."],
        ["Callback", "function(item, index)", "—", "Runs when the user selects a row."],
        ["OnRemove", "function(item, index)", "—", "Runs after the user removes a row."]
      ]
    },
    {
      "id": "methods",
      "title": "Methods",
      "code": "local index = Waypoints:Add({ \"Arena\", \"-120, 8, 64\" })\nWaypoints:Add({ \"Top\", \"0, 0, 0\" }, 1) -- insert at a position\nWaypoints:Update(index, { \"Arena\", \"-118, 8, 60\" })\nWaypoints:Remove(1)\nWaypoints:Select(2, true) -- silent\nlocal item, at = Waypoints:GetSelected()\nlocal all = Waypoints:Get()\nWaypoints:Set({ \"Only row\" })\nWaypoints:Clear()"
    }
  ]
},
  {
  "slug": "player-picker",
  "title": "Player picker",
  "group": "Components",
  "summary": "Choose a player from the live server roster.",
  "demo": "player-picker",
  "sections": [
    {
      "id": "usage",
      "title": "Usage",
      "code": "local Picker = Section:PlayerPicker({\n    Name = \"Player\", Flag = \"TargetPlayer\", IncludeSelf = false,\n    Callback = function(player)\n        print(player and player.Name or \"None\")\n    end,\n})"
    },
    {
      "id": "behavior",
      "title": "Behavior",
      "text": [
        "Rows show an avatar, display name and @username. Join and leave events refresh an open list. The selected value is a Player instance or nil; configs store the username. A selected player leaving clears the value. Set also accepts a Player instance; true as its second argument suppresses callbacks. The simulator supplies a sample roster."
      ]
    },
    {
      "id": "methods",
      "title": "Methods",
      "code": "Picker:Set(\"builderman\")\nlocal player = Picker:Get()\nPicker:Set(nil)"
    }
  ]
},
  {
  "slug": "dependent-controls",
  "title": "Dependent controls",
  "group": "Guides",
  "summary": "Fold related settings when their parent option is off.",
  "demo": "dependent-controls",
  "sections": [
    {
      "id": "usage",
      "title": "Create a group",
      "code": "local Enabled = Section:Toggle({Name = \"Enabled\", Default = true})\nlocal Tuning = Section:Group({Name = \"Tuning\", DependsOn = Enabled})\nTuning:Slider({Name = \"Field of view\", Min = 10, Max = 400, Default = 120})"
    },
    {
      "id": "behavior",
      "title": "Keep settings available",
      "text": [
        "The group follows the parent toggle, including silent Set calls. Its header can reopen it while the parent is off, so users can prepare settings first. Folding preserves values; it does not disable your script’s logic. Groups accept the same controls as sections. Without DependsOn, use Open = true for an initially open group."
      ],
      "code": "Tuning:SetOpen(true)\nlocal open = Tuning:IsOpen()"
    }
  ]
},
  {
  "slug": "overlays",
  "title": "Watermark & keybinds",
  "group": "Guides",
  "summary": "Optional HUD elements that stay visible alongside the hub.",
  "demo": "overlays",
  "sections": [
    {
      "id": "watermark",
      "title": "Watermark",
      "code": "local Hub = Rift:CreateHub({Name = \"My Hub\", Watermark = true})\nHub:SetWatermark(false)",
      "text": [
        "The strip shows the hub name, FPS, ping and local time. Ping comes from LocalPlayer:GetNetworkPing when available. It can be dragged; its position and enabled state save per hub. It starts off by default."
      ]
    },
    {
      "id": "keybinds",
      "title": "Keybind list",
      "code": "local Hub = Rift:CreateHub({Name = \"My Hub\", KeybindList = true})\nHub:SetKeybindList(false)",
      "text": [
        "The floating list shows non-internal bound controls, their keys and their toggle, hold or always state. Rebinding and changing state refresh the list. Drag the header to move it. Both overlays can be toggled under Settings → Interface; saved preferences take precedence over CreateHub defaults. Stealth asset mode keeps both overlays usable."
      ]
    }
  ]
},
  {
  "slug": "tooltips",
  "title": "Control tooltips",
  "group": "Guides",
  "summary": "Add short hover help through Description.",
  "demo": "tooltips",
  "sections": [
    {
      "id": "usage",
      "title": "Describe a control",
      "code": "Section:Slider({\n    Name = \"Smoothing\", Min = 0, Max = 1, Step = 0.05,\n    Description = \"Higher values move more slowly.\",\n})",
      "text": [
        "Controls that do not print Description inline show it as hover help. Move the pointer away to dismiss it. Keep instructions needed on a touch device visible in a label or paragraph, since hover help needs a pointer."
      ]
    }
  ]
},
  {
  "slug": "translations",
  "title": "Translations",
  "group": "Guides",
  "summary": "Change interface language in place and supply translations for your own labels.",
  "demo": "translations",
  "sections": [
    {
      "id": "language",
      "title": "Choose a language",
      "code": "Hub:SetLanguage(\"es\")\nHub:SetLanguage(\"en\")\nlocal translated = Hub:T(\"Settings\")\nlocal languages = Hub:Languages()",
      "text": [
        "Built-in dictionaries cover common interface strings in English, Spanish, Portuguese, German and French. Untranslated text falls back to the English source. Language is selectable in Settings and saved per hub. CreateHub accepts Language; otherwise a supported Roblox locale supplies the initial choice."
      ]
    },
    {
      "id": "custom",
      "title": "Translate your labels",
      "code": "local Hub = Rift:CreateHub({\n    Name = \"My Hub\", Language = \"es\",\n    Translations = {\n        es = {\n            [\"Aim Assist\"] = \"Asistencia de puntería\",\n            [\"{n} targets\"] = \"{n} objetivos\",\n        },\n    },\n})",
      "text": [
        "Keys are the original English labels. Custom entries override built-in entries and may add another language code. Named placeholders match changing pieces of text. Existing labels and new controls update in place, and switching back restores source strings. Text-box values are left alone; placeholders translate. These dictionaries cover interface copy, not arbitrary player names or script data."
      ]
    }
  ]
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
  control('toggle', 'Toggle', 'A checkbox with a boolean value.', 'Click either row. Its callback reports true or false.',
    `local Toggle = Section:Toggle({
    Name = "Sprint",
    Flag = "Sprint",
    Default = true,
    Callback = function(enabled)
        print("Sprint:", enabled)
    end,
})`,
    [['Name', 'string', '—', 'The row label.'], ['Description', 'string', '—', 'Supporting text below the label.'], ['Default', 'boolean', 'false', 'Initial checked state.'], ['Flag', 'string', '—', 'Registers the control in Rift.Flags.'], ['Callback', 'function(boolean)', '—', 'Receives the new state.']],
    ['Clicking changes the value and calls the callback. A toggle whose default is <code>true</code> also calls its callback during creation.', 'The checkmark and label update together.'],
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
    [['Default', 'string', '""', 'Initial field value.'], ['Placeholder', 'string', '""', 'Shown when the field is empty.'], ['Finished', 'boolean', 'true behavior', 'Set false to emit while editing.'], ['MultiLine', 'boolean', 'false', 'A taller, wrapping field where Enter starts a new line.'], ['Lines', 'number', '4', 'Visible rows for a multiline field, 2–20.'], ['Code', 'boolean', 'false', 'Monospace text, for scripts and pasted codes.'], ['MaxLength', 'number', '—', 'Trims longer values, counted in characters.'], ['Callback', 'function(string)', '—', 'Receives the field text.']],
    ['By default the field commits on focus loss when its text changed, or when Enter is pressed. Set <code>Finished = false</code> to also receive changes as the user types.', 'With <code>MultiLine = true</code>, Enter adds a line break and the value commits when the field loses focus. Single-line fields replace line breaks in <code>:Set()</code> values with spaces.', 'Multiline example: <code>Section:Input({ Name = "Script", MultiLine = true, Lines = 6, Code = true })</code>'],
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
      { id: 'tokens', title: 'Colour roles', columns: ['Token', 'Used for'], rows: [['Panel / PanelStroke', 'Floating surfaces and their outlines.'], ['Tile / TileHover / TileActive', 'Buttons and toolbar tab states.'], ['Text / SubText / Muted', 'Primary labels, secondary labels and supporting text.'], ['Field / FieldStroke', 'Inputs, key chips and checkboxes.'], ['Accent / AccentText', 'Selected states and the foreground drawn on them.'], ['Track / Knob', 'Slider tracks and scrollbars.'], ['Divider / Highlight', 'Section rules and top-edge sheen.'], ['Danger / Success / Warning', 'Feedback and status messages.']] },
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
    slug: 'social-button', title: 'Social button', group: 'Guides', demo: 'social-button',
    summary: 'Link your community from a window header, using the platform’s own colours and logo.',
    hint: 'Click the Discord button to copy the invite. Close the window and click a section header to fold it.',
    sections: [
      { id: 'usage', title: 'Add a Discord button', code: `local About = Hub:Window({ Title = "About", Icon = "info" })
About:SocialButton({
    Discord = "https://discord.gg/your-invite", -- or just "your-invite"
    Callback = function(url) end,               -- optional, after copying
})`, text: ['The button sits in the window header, left of the close button. Clicking it copies the invite and shows a notification. If the executor has no clipboard function, the notification shows the link instead. The window title gives up the room the button needs. Windows narrower than 420 pixels show the logo only.', 'Accepted links: <code>discord.gg/…</code>, <code>discord.com/invite/…</code> or a bare invite code. Anything else raises an error, so a typo is caught when the hub loads. Each window has one social button; calling it again replaces the button.'] },
      { id: 'brand', title: 'Brand colours', text: ['Brand buttons keep their platform’s colours in every theme. Discord uses Blurple (<code>#5865F2</code>) with the official white logo, following the <a href="https://discord.com/branding">Discord brand guidelines</a>. The logo is never recoloured or redrawn. If the logo can’t load, the button still shows its label.'], columns: ['Option', 'Type', 'Description'], rows: [['Discord', 'string', 'Invite link or code. Also selects the platform.'], ['Label', 'string', 'Button text. Defaults to the platform name.'], ['Callback', 'function(url)', 'Runs after the invite is copied.']] },
      { id: 'methods', title: 'Working with the button', code: 'local Social = About:SocialButton({ Discord = "your-invite" })\nprint(Social.Url) -- https://discord.gg/your-invite\nSocial:SetVisible(false)\nSocial:Destroy()' },
    ],
  },
  {
    slug: 'auth', title: 'Key gate', group: 'Guides', demo: 'auth',
    summary: 'Ask for a key before your hub loads. Your server checks it and sends the hub script back.',
    hint: 'Enter RIFT-DEMO and press Continue. Any other key shows the server’s refusal.',
    sections: [
      { id: 'flow', title: 'How the gate works', code: loader + `

local source, key = Rift:CreateAuth({
    Name = "My Hub",
    Id = "my-hub",
    Url = "https://auth.example.com/v1/script",
    GetKeyUrl = "https://example.com/get-key",
    Discord = "https://discord.gg/your-invite",
    Note = "Keys last 24 hours.",
})
if not source then return end -- the user closed the gate

loadstring(source)()`, text: ['<code>CreateAuth</code> shows a key prompt and waits. The key is sent to <code>Url</code> as <code>Authorization: Bearer &lt;key&gt;</code>. A 2xx response body is your hub script: CreateAuth returns it with the accepted key, and your loader runs it. If the user closes the gate, it returns <code>nil, "closed"</code>.', 'Load the hub after the gate. Use the same <code>Id</code> for the gate and the hub so the gate picks up the user’s saved theme.'] },
      { id: 'security', title: 'What it protects', text: ['Code that is already on the user’s machine can always be edited, including any check in it. The gate is only secure because the server keeps the hub script until a valid key arrives. Keep the hub on your server, and do key checks, expiry and HWID binding there, not in the client script.'] },
      { id: 'options', title: 'Options', columns: ['Option', 'Type', 'Default', 'Description'], rows: [
        ['Url', 'string', '—', 'HTTPS endpoint that checks the key. Required unless you pass Request.'],
        ['Request', 'function(key)', '—', 'Replaces the HTTP call. Return <code>true, source</code> to accept, <code>false, reason</code> to reject, or <code>nil, reason</code> for a temporary failure.'],
        ['Name / Id', 'string', '"Rift Hub"', 'Card title and the folder that holds the saved key.'],
        ['Title / Subtitle', 'string', 'Name / prompt', 'Card head.'], ['HubIcon', 'string or number', 'initial', 'Same as CreateHub: a Lucide name or an image asset ID. Pass the value your hub uses so both cards match.'],
        ['Note', 'string', '—', 'A line under the head, such as where keys come from.'],
        ['GetKeyUrl / Discord', 'string', '—', 'Adds a button that copies the link.'],
        ['Placeholder', 'string', '"Paste your key"', 'Empty-field hint.'],
        ['Remember', 'boolean', 'true', 'Saves an accepted key to <code>RiftUI/&lt;Id&gt;/auth.key</code> and checks it again on the next launch.'],
        ['SendHwid', 'boolean', 'false', 'Sends <code>X-Rift-Hwid</code> from <code>gethwid()</code> or the Roblox client ID, so the server can lock a key to one device.'],
        ['ThemeName / Theme', 'string / table', 'Graphite', 'Colours, the same as CreateHub.'],
      ] },
      { id: 'responses', title: 'Server responses', columns: ['Status', 'Gate shows', 'Saved key'], rows: [
        ['2xx with a body', 'Key accepted, then closes', 'Saved'],
        ['401 / 403', '<code>error</code> or <code>message</code> from a JSON body, plain text, or “Invalid key.”', 'Forgotten'],
        ['429', 'Too many attempts', 'Kept'],
        ['5xx / no connection', 'The status, or a connection message', 'Kept'],
      ], text: ['A saved key is only forgotten when the server rejects it. A server or network failure keeps it for the next launch. Scripts larger than 16 MiB are refused.'] },
      { id: 'logout', title: 'Forget a saved key', code: 'Rift:ClearAuthKey("my-hub")' },
      { id: 'server', title: 'Reference server', code: 'import { authServer } from "./scripts/auth/server.mjs"\n\nauthServer({\n    // true to accept, false or a reason string to refuse\n    authorize: async (key, hwid) => (await lookUp(key, hwid)) ? true : "Key expired",\n    script: async (key, hwid) => readFile("hub.luau", "utf8"),\n}).listen(8789, "127.0.0.1")', text: ['<code>scripts/auth/server.mjs</code> answers <code>GET /v1/script</code>. It returns the script as text, refusals as <code>{ "error": "…" }</code>, and limits each client to 10 attempts per minute. It has no key store, payments or obfuscation: plug yours into <code>authorize</code> and <code>script</code>.', 'To try it with fixed keys, run <code>RIFT_AUTH_KEYS="key-one,key-two" RIFT_AUTH_SCRIPT=hub.luau node scripts/auth/server.mjs</code>. Run it behind an HTTPS reverse proxy, and set <code>RIFT_AUTH_TRUST_PROXY=1</code> so the limit counts the forwarded client address.'] },
    ],
  },
  {
    slug: 'loading', title: 'Loading screen', group: 'Guides', demo: 'loading',
    summary: 'Show a branded card while your hub builds, then bring up the toolbar.',
    hint: 'Replay the example to watch the card step through its stages.',
    sections: [
      { id: 'enable', title: 'Turn it on', code: 'local Hub = Rift:CreateHub({\n    Name = "My Hub",\n    Loading = true,\n})', text: ['The card shows the hub name and subtitle while the hub builds, applies preferences, checks requirements and loads the autoload config. The toolbar stays hidden, and <code>Hub:Open()</code> and first-run setup wait until the card has gone.'] },
      { id: 'customize', title: 'Customize the card', code: 'Loading = {\n    Title = "My Hub",\n    Subtitle = "Fetching game data",\n    Icon = "rocket",\n    MinDuration = 1.5,\n}', columns: ['Option', 'Type', 'Default', 'Description'], rows: [['Title', 'string', 'hub Name', 'Large text on the card.'], ['Subtitle', 'string', 'hub Subtitle', 'Second line under the title.'], ['Icon', 'string', 'HubIcon', 'Overrides the hub’s <code>HubIcon</code> for this card. Without either, the chip shows the title’s first letter.'], ['MinDuration', 'number', '1', 'Seconds the card stays, so a fast build doesn’t flash.'], ['Manual', 'boolean', 'false', 'Keep the card until you call <code>Hub:FinishLoading()</code>.']] },
      { id: 'manual', title: 'Drive it from your script', code: 'local Hub = Rift:CreateHub({ Name = "My Hub", Loading = { Manual = true } })\n\nHub:SetLoading("Fetching game data", 0.3)\nlocal data = fetchData()\nHub:SetLoading("Building interface", 0.7)\nbuildTabs(Hub, data)\nHub:FinishLoading()', text: ['Use Manual when your script yields before it builds, for example to download data. <code>SetLoading(status, progress)</code> changes the status line and moves the bar. Progress runs from 0 to 1 and never moves backwards. Omit either argument to leave that part unchanged. <code>Hub:IsLoading()</code> reports whether the card is still up.'] },
    ],
  },
  {
    slug: 'requirements', title: 'Developer requirements', group: 'Guides', demo: 'requirements',
    summary: 'Supply your own function tests and gate features on their results.',
    hint: 'Enable Test result to unlock the feature. The test function belongs to the hub author.',
    sections: [
      { id: 'define', title: 'Bring your own test', code: 'local Hub = Rift:CreateHub({\n    Name = "My Hub",\n    Requirements = {\n        DrawingFeature = {\n            Name = "Drawing feature",\n            Test = function(hub)\n                return myDrawingTest(), "Drawing is unavailable here"\n            end,\n            Timeout = 5,\n        },\n    },\n})', text: ['You implement myDrawingTest. RiftUI calls only the Test function you supply for a declared requirement. It does not look up a matching global function, invoke a named API, or add a built-in test for your feature. Each Test must explicitly return true to pass; false, nil, an error or a timeout keeps the feature locked.', 'Requirements run automatically for each new hub and again when the developer or user requests a recheck. A definition may also be a function directly: Requirements = {Feature = function(hub) return myTest() end}. Optional Name and Message provide user-facing text. Timeout defaults to five seconds and accepts 0.1–30 seconds; yielding tests are cancelled on timeout. A test that never yields cannot be preempted, so keep tests bounded and side effects under your control.'] },
      { id: 'gate', title: 'Gate controls and groups', code: 'Section:Toggle({\n    Name = "ESP", Requires = "DrawingFeature",\n    Callback = function(on) -- your feature logic\n    end,\n})\n\nSection:Button({\n    Name = "Advanced action",\n    Requires = {"DrawingFeature", "OtherFeature"},\n    Callback = runAction,\n})', text: ['Every listed requirement must pass. Missing IDs fail closed. While checking or unavailable, interactive controls display a lock and reason; hover or tap for the full explanation. Requires also works on Tab, Section and Group options, and child controls inherit those requirements in addition to their own. Help text and read-only data remain readable.', 'Pointer input, keybind activation, callbacks and Set calls are gated, including values restored from configs. A default-on toggle waits until its requirements pass before its initial callback runs. Rechecking immediately locks affected controls until the new result is known. Reinitialize rechecks requirements; it does not trust saved results.'] },
      { id: 'manual', title: 'Gate code outside the UI', code: 'local allowed, reason = Hub:CanUse("DrawingFeature")\nlocal run = Hub:Guard("DrawingFeature", function(value)\n    return useFeature(value)\nend)\nlocal result, reason = run(123)\n\nlocal result = Hub:GetRequirement("DrawingFeature")\nHub:RunRequirement("DrawingFeature")\nHub:RunRequirements()', text: ['Guard returns false and a reason when blocked; otherwise it forwards the callback’s return values. GetRequirement returns a copy with Id, Name, Passed, Status and Message, plus Error for a thrown test error. Status is pending, passed, failed or timeout. Late results from superseded tests are ignored.'] },
      { id: 'changes', title: 'React when availability changes', code: 'local connection = Hub:OnRequirementsChanged(function(results)\n    if not results.DrawingFeature.Passed then\n        stopMyAlreadyRunningFeature()\n    end\nend)\n\nconnection:Disconnect()', text: ['Gates stop new interactions; they do not undo work an earlier callback already started. The developer owns cleanup of running features. Requirement changes are observable so your code can stop them safely. Subscriptions end when the hub is destroyed.', 'Settings shows Feature requirements and a recheck button. The setup compatibility page labels your checks as developer tests; RiftUI’s own core-library checks remain separate. Tests and cached results are never serialized into configs.'] },
    ],
  },
  {
    slug: 'stealth', title: 'Stealth asset mode', group: 'Guides', demo: 'stealth',
    summary: 'Use cached local images and fonts while keeping the hub usable.',
    sections: [
      { id: 'startup', title: 'Set the policy at creation', code: 'local Hub = Rift:CreateHub({\n    Name = "My Hub",\n    Stealth = true,\n})', text: ['An explicit Stealth = true or Stealth = false is controlled by the script. Settings displays its status as read-only. Omit Stealth to leave a user-facing toggle in Settings. Developers can still call Hub:SetStealth(true or false).', 'For policy coverage before any library-created widget, set getgenv().RIFTUI_SECURE = true before loading RiftUI. This also makes the mode script-controlled. Enable it before asset loading; switching modes later cannot undo content already fetched.'] },
      { id: 'assets', title: 'What it changes', text: ['Built-in Lucide sheets and shadows continue to use cached getcustomasset files. Raw rbxassetid://, rbxthumb:// and direct HTTP image references are blocked from rendered image properties. Pass a local getcustomasset result for your own icons. Inter is cached as four TTF files, registered with getcustomasset and loaded through a generated local .font family. BuilderSans stays visible until registration succeeds, and remains the fallback if the executor cannot load custom fonts. Built-in mono fonts remain available. Rift:GetSecureFontStatus() returns idle, loading, ready or failed; Rift:LoadSecureFont() retries a failed load.', 'Player headshots try the thumbnail API, cache PNG bytes and render a local content ID. If caching is unavailable, the initials fallback stays visible. Library warnings are quiet while enabled; diagnostic records remain available to the developer. Your own print and warn functions are not patched.', 'The toolbar, notifications, watermark and keybind list continue to work. Names are not randomized. Asset policy is shared across hubs from one loaded RiftUI instance while any hub enables it. Disabling permits future remote references; it does not reconstruct images already omitted while the policy was enabled.'], note: 'This is an asset-loading policy, not a guarantee of invisibility or anti-cheat bypass. RiftSim verifies the policy’s GUI behavior; test Roblox-specific asset handling in the target environment.' },
    ],
  },
  {
    slug: 'encrypted-configs', title: 'Encrypted & remote configs', group: 'Guides', demo: 'encrypted-configs',
    summary: 'Optional authenticated encryption for saved configs, share codes and server-delivered presets.',
    sections: [
      { id: 'enable', title: 'Enable encryption', code: 'local Hub = Rift:CreateHub({\n    Name = "My Hub", Id = "my-hub",\n    ConfigEncryption = {\n        Key = function() return session.configKey end,\n    },\n})\n\nHub:SaveConfig("private")\nHub:LoadConfig("private")\nHub:SaveConfig("plain", {Encrypt = false})', text: ['Your script supplies <code>session.configKey</code>: a random 32-byte key encoded as Base64, not a password. It may be a string or a function that returns one. Keys and bearer tokens are never written into config files or preferences.', 'ConfigEncryption enables encrypted saves by default. Set Enabled = false to supply a decryption key while keeping new saves plain. The config manager exposes Encrypt saved configs when a key provider is configured. Existing plain configs remain compatible.'], note: 'Encryption is optional and needs a compatible AES-CBC/SHA-256 provider. sUNC does not guarantee the old crypt library. RiftUI accepts ConfigEncryption.Crypto or Rift.ConfigCrypto; otherwise it detects crypt. Unsupported providers fail clearly and never silently save an encrypted request as plaintext.' },
      { id: 'sharing', title: 'Share encrypted configs', code: 'local code, err = Hub:ExportConfig("private") -- RIFTCFG2:...\nlocal ok, name = Hub:ImportConfig(code, "imported")\n\n-- Encrypt a plain config on export, without changing the source file.\nlocal code = Hub:ExportConfig("plain", {Encrypt = true})', text: ['An already encrypted config exports as encrypted by default. Import verifies its authentication and hub identity before saving; it stays encrypted. Existing RIFTCFG1 plain codes still work. For one-off keys, pass {Key = key} to SaveConfig, LoadConfig, ExportConfig or as the third argument of ImportConfig. Explicit {Encrypt = false} on export decrypts an encrypted file using its key.'] },
      { id: 'remote', title: 'Fetch from a config server', code: 'local ok, err = Hub:SetConfigServer({\n    Url = "https://configs.example.com/v1",\n    Token = function(configId) return session.accessToken end,\n    RequireEncrypted = true,\n})\n\nlocal ok, err = Hub:LoadRemoteConfig("premium-legit")\n-- Optional: keep an encrypted local copy for later or autoload.\nHub:LoadRemoteConfig("premium-legit", {SaveAs = "premium"})', text: ['Your script obtains the authenticated session and config key from your own service. GET /v1/configs/:id returns an encrypted envelope as JSON, or a plain {Hub, Name, Data} payload if your policy allows it. A token adds Authorization: Bearer ...; omit Token for public endpoints. HTTPS is required. Authentication errors, wrong keys, altered ciphertext, oversized bodies and configs for another hub are rejected before applying values.', 'Remote configs stay in memory by default. SaveAs explicitly caches the original encrypted envelope; the key is still required later. Saving an offline copy permits offline reuse. The config manager adds a Remote tab when ConfigServer is configured.'], note: 'Purchase checks, account access, revocation and key distribution belong to your server. A client that receives a decryption key can read or copy the resulting values; this feature is not DRM. In the simulator your server must allow the docs origin and Authorization header through CORS. Authenticated requests never retry through the public image proxy.' },
      { id: 'server', title: 'Reference server', code: 'node scripts/config/pack.mjs --generate-key\n# Put that key in RIFT_CONFIG_KEY using your environment/secret manager.\nnode scripts/config/pack.mjs plain.json private-configs/premium-legit.json my-hub premium\n\n# Set RIFT_CONFIG_TOKEN and optionally RIFT_CONFIG_ORIGIN first.\nnode scripts/config/server.mjs', text: ['The Node reference tools use only built-in crypto. pack.mjs encrypts a saved config JSON file; its hub ID must match your script. Create private-configs first. The server listens on loopback port 8788; expose it through an HTTPS reverse proxy. Private data and .env files are gitignored. It sends Cache-Control: no-store and requires a token.', 'The example token grants access to all files in that directory. For a paid service, use the exported configServer({directory, authorize, origin}) and replace authorize(token, configId) with your entitlement lookup. No payment or account service is provisioned. See <a href="https://github.com/Naymmmm/riftui/tree/main/scripts/config">scripts/config</a> for the complete server and packer.'] },
      { id: 'format', title: 'Encryption format & providers', text: ['Version 1 uses AES-256-CBC with PKCS#7 padding and encrypt-then-MAC HMAC-SHA256. Each message has a random 16-byte IV. Independent encryption and MAC keys derive from the random master key using HMAC-SHA256 with the domain strings RiftUI config encryption v1 and RiftUI config authentication v1. The tag authenticates the format/version/algorithm, IV and ciphertext before decryption. The encrypted payload contains {Hub, Name, Data}.', 'A provider exposes encrypt(raw, base64Key, base64IV, "CBC") → base64Ciphertext, decrypt(base64Ciphertext, base64Key, base64IV, "CBC") → raw, hash(raw, "sha256") → 64 hexadecimal characters, generatebytes(n) → secure random bytes in Base64, base64encode(raw), and base64decode(encoded). The simulator implements this with Web Crypto. See the <a href="https://github.com/sUNC-Utilities/docs/tree/main/docs/Encoding">sUNC encoding documentation</a> for the distinction between encoding and optional crypto.', 'The exact interoperable JSON envelope and authenticated byte sequence are implemented in scripts/config/crypto.mjs and tested against the Luau client. Configs remain data: they are never passed to loadstring or executed.'] },
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
      { id: 'manage', title: 'Manage profiles', code: 'Hub:RenameConfig("default", "legit")\nHub:DeleteConfig("legit") -- also clears autoload if it pointed here\nprint(Hub:GetAutoload())\nprint(Hub:ConfigInfo("rage")) -- { Name, Settings, SavedAt, Autoload }\nHub:SetAutoload(nil) -- stop auto-loading', text: ['Settings → Config has an <strong>Autoload a config</strong> checkbox with its own picker, so browsing the Saved list never changes what loads on start. <strong>Manage configs</strong> opens a window that lists every config with its size and save time, and loads, overwrites, renames, deletes or sets autoload for the selected one.', 'Themes and backgrounds are kept in setup data rather than individual flag-based configs.'] },
      { id: 'share', title: 'Share a config', code: 'local code = Hub:ExportConfig("legit") -- "RIFTCFG1:..."\nlocal ok, nameOrError = Hub:ImportConfig(code, "from-friend")', text: ['Codes carry control values, pins, keys and scale, and only import into a hub with the same Id. The Share tab in Manage configs copies and imports them.'] },
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
      { id: 'options', title: 'CreateHub options', columns: optionColumns, rows: [['Name', 'string', '"Rift Hub"', 'Display name.'], ['Id', 'string', 'Derived from Name', 'Stable identity and per-hub folder.'], ['Subtitle', 'string', '""', 'Supporting hub text.'], ['HubIcon', 'string or number', 'initial', 'The hub’s mark on the loading card, key gate and watermark: a Lucide icon name such as <code>"rocket"</code>, or an image as <code>"rbxassetid://123"</code> or <code>123</code>. Images keep their colours. Stealth mode blocks remote images, so the name’s first letter is shown instead.'], ['ToggleKey', 'Enum.KeyCode', 'RightShift', 'Toolbar visibility shortcut.'], ['CommandKey', 'Enum.KeyCode', 'F2', 'Command palette shortcut.'], ['ThemeName', 'string', '"Graphite"', 'Built-in palette name.'], ['Theme', 'table', '{}', 'Colour overrides.'], ['Setup', 'boolean or table', 'Enabled', 'First-run flow and optional custom choices.'], ['Settings', 'boolean', 'true', 'Built-in Settings tab, including About, the RiftUI license credit and GitHub link.'], ['Watermark', 'boolean', 'false', 'Optional name, FPS, ping and time strip.'], ['KeybindList', 'boolean', 'false', 'Optional bound-key overlay.'], ['Language', 'string', 'Supported Roblox locale or en', 'Initial interface language.'], ['Translations', 'table', '{}', 'Per-language dictionaries for your own labels.'], ['Stealth', 'boolean', 'false', 'Local images and Inter font files, built-in font fallback and quiet library warnings. An explicit value is read-only in Settings.']] },
      { id: 'layout', title: 'Layout and visibility', columns: ['Method', 'Effect'], rows: [['Hub:Tab({ Name, Icon, Description })', 'Creates a toolbar tab and content page.'], ['Tab:Section({ Name, Side, Pinnable })', 'Creates a section; Side is Left or Right, otherwise balanced.'], ['Tab:Section({ Collapsed, Collapsible })', 'Clicking a section header folds it to the header. The user’s choice is saved per hub. <code>Collapsed = true</code> starts it folded; <code>Collapsible = false</code> keeps it open.'], ['Section:SetCollapsed(boolean) / Section:IsCollapsed()', 'Folds or opens a section from code. Search and the command palette open folded sections to show matches.'], ['Window:SocialButton({ Discord = invite })', 'Adds a Discord button to a window header, in Blurple with the official logo. It copies the invite and takes a full link or a bare invite code.'], ['Hub:Open(Tab) / Hub:Close()', 'Opens or closes the current panel.'], ['Hub:SetToolbarVisible(boolean)', 'Shows or hides the toolbar.'], ['Hub:SetScale(number)', 'Sets interface scale, clamped to 0.6–1.5, and recenters the open panel.'], ['Hub:OpenCommandPalette() / Hub:CloseCommandPalette()', 'Opens or dismisses hub-wide search.'], ['Hub:SetCommandKey(Enum.KeyCode)', 'Changes and saves the palette shortcut.'], ['Tab:SetBadge(number | string | nil)', 'Shows a small badge on the toolbar tab; nil or 0 hides it. CreateHub{ ToggleBadges = true } restores counting enabled toggles.'], ['Hub:Window({ Title, Description, Icon, Width, Height })', 'Creates a child window. Add Window:Tab({ Name, Icon }) for tabs, or Window:Section() for a single page.'], ['Window:Open() / Close() / Toggle() / SelectTab(tab)', 'Opens it over the panel with Escape and click-outside to close. Section:Button({ Name, Window = W }) opens it from a button.']] },
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
export const groups = ['Overview', 'Getting started', 'Components', 'Guides', 'Reference']
export const getPage = (slug: string) => pages.find(p => p.slug === slug)
