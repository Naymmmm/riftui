<img src="public/favicon.svg" width="56" height="56" alt="">

# RiftUI

A dock-style hub library for sUNC executors, written in Luau, plus **RiftSim**: a browser simulator that runs the *same* Luau source on an emulated Roblox client.

Tabs are tiles in a slim toolbar. Clicking a tile opens its panel in the middle of the screen; clicking anywhere else folds it back into the tile. Sections can be pinned to stay on screen while the toolbar is hidden.

## Use it in an executor

```lua
-- Optional: pin the library and its assets to an exact commit (full SHA recommended).
getgenv().riftcommit = "YOUR_COMMIT_SHA"
local Rift = loadstring(game:HttpGet("https://raw.githubusercontent.com/Naymmmm/riftui/main/public/Loader.luau"))()

xpcall(function()
	local Hub = Rift:CreateHub({ Name = "Rift Hub", Subtitle = "Baseplate", ToggleKey = Enum.KeyCode.RightShift })

	local Combat = Hub:Tab({ Name = "Combat", Icon = "crosshair", Description = "Aim assist" })
	local Aim = Combat:Section({ Name = "Aim Assist" })
	Aim:Toggle({ Name = "Enabled", Flag = "AimEnabled", Default = true, Callback = function(on) end })
	Aim:Slider({ Name = "Field of view", Flag = "AimFOV", Min = 10, Max = 400, Default = 248, Suffix = " px" })
end, Rift.HandleError)
```

Replace `YOUR_COMMIT_SHA` with a hexadecimal commit SHA (7–40 characters). The loader returns the library from `/<SHA>/public/RiftUI.luau`, sets `Rift.Commit`, and pins its asset URLs to the same revision. Pinned assets are cached separately under `RiftUI/assets/<SHA>/`. Invalid pins and download/compile errors stop with a readable error; there is no fallback to another revision. The selected commit must contain the bundled `public/RiftUI.luau` file.

Leave `getgenv().riftcommit` unset (or set it to `nil`) to use `main`. RiftSim serves `main` from the local project; pinned hashes are fetched from GitHub. The loader source is `lib/Loader.luau`, copied to `public/Loader.luau` by the bundle script.

### API

| Call | Notes |
|---|---|
| `Rift:CreateHub{ Name, Id, Subtitle, ToggleKey, ThemeName, Theme, Setup, Stealth, Settings }` | `Id` names the hub's folder, `RiftUI/<Id>/` (`setup.json`, `configs/`). Running a hub again with the same `Id` replaces the old copy. `ThemeName` is one of `Graphite`, `Ink`, `Slate`, `Ember`, and `Theme` overrides individual colours. `Settings = false` removes the built-in Settings tab (the only way to remove it). |
| `Hub:Tab{ Name, Icon, Description }` | `Icon` is any [Lucide](https://lucide.dev/icons) name or an `rbxassetid://`. |
| `Tab:Section{ Name, Side = "Left"\|"Right", Pinnable }` | `Section:Pin(pos?)`, `Section:Unpin()` |
| `Toggle`, `Slider`, `Dropdown{ Multi }`, `Input`, `Keybind{ Mode = "Toggle"\|"Hold"\|"Always" }`, `ColorPicker`, `Button`, `Label`, `Paragraph` | Every control has `.Value`, `:Set(v, silent?)`, `:Get()`, `:OnChanged(fn)`, `:SetVisible(b)`. `Flag` registers it in `Rift.Flags`. |
| `Hub:Notify{ Title, Content, Icon, Duration, Tone }` | Slit notifications: the card opens out of a thin slit that drains as the timer. Hover pauses, click dismisses. |
| `Hub:Prompt{ Icon, Title, Content, Buttons }` | Centred dialog. |
| `Hub:SaveConfig(name)`, `:LoadConfig(name)`, `:ListConfigs()`, `:SetAutoload(name)` | JSON under `RiftUI/<ConfigFolder>/`. |
| `Hub:SetBackground{ Url \| Base64 \| File, Opacity, Dim, Fit = "Crop"\|"Fit"\|"Stretch", Dock }` | A background image behind the panel (and optionally the toolbar). Base64 may be raw or a `data:` URI, and a URL that returns base64 text is decoded too. The image is checked to be PNG/JPEG/WebP/GIF, saved to `RiftUI/<Id>/background.<ext>` and shown through `getcustomasset`. `SetBackground(nil)` removes it. |
| `Hub:PlaceBackground{ Preset, Fit, Anchor, Scale, OffsetX, OffsetY, Rotation, Opacity, Dim, Dock }` | Move the current image without reloading it. `Fit`: `Fill`, `Fit`, `Stretch` or `Free`. With `Free`, the image is anchored to one of 9 points (`TopLeft` … `BottomRight`), sized by `Scale` (image height ÷ panel height), nudged by the offsets and rotated by any angle; rotated images keep hugging their corner. Presets: `Full`, `Corner`, `Body pillow`, `Body pillow (lying down)`. The same fields work in `SetBackground`. |
| `Hub:SaveTheme(look)`, `Hub:LoadTheme(name)`, `Hub:DeleteTheme(name)`, `Rift:ListThemes()` | Custom themes: `{ Name, Base, Colors, Background }`, saved to `RiftUI/themes/<name>.json` and shared by every hub. |
| `Hub:ExportTheme(look, embedImage?)`, `Hub:ImportTheme(code)`, `Hub:FetchThemeImage(look)` | Share codes are `RIFT1:` + base64-encoded JSON. A URL background travels as its URL; a local image is embedded only if you choose to (up to 4 MB). Importing never downloads or writes the image by itself; `FetchThemeImage` does that, and the studio asks first. |
| `Hub:OpenThemeStudio()` | The Theme Studio: base theme, accent colour, and background image (source, opacity, dim, fit, toolbar), with a live preview. Also under Settings › Interface. Saved in `setup.json`. |
| `Hub:SetStealth(on)` | Random instance names, no notifications, toolbar starts hidden. |
| `Hub:SetToolbarVisible(b)`, `:SetScale(n)`, `:Open(tab)`, `:Close()`, `:Reinitialize()`, `:Destroy()` | |
| `Rift.HandleError` | Pass to `xpcall`. Shows the "Hub failed to load" card and records the error. Errors in control callbacks are caught separately and shown as a red-slit notification. |
| `Rift.State`, `Rift.StateHistory`, `Rift.Errors`, `Rift:OnStateChanged(fn)` | The state machine: `Booting → Building → Ready`, `Failed`, `Reinitializing`, `Unloaded`. |

**Setup window:** on a hub's first launch (no `RiftUI/<Id>/setup.json` yet), a setup window walks through:

1. The toolbar key.
2. A theme.
3. The hub's own options (`Setup = { Title, Description, Options = { { Type = "Toggle" | "Dropdown" | "Slider" | ..., Name, Flag, Default } } }`). Their values land in `Rift.Flags` on every later launch too.
4. A compatibility check that calls each sUNC function RiftUI relies on: `gethui`, `cloneref`, file read/write, `listfiles`, `getcustomasset`, `delfile`, `HttpGet`, `setclipboard` and `request`. Anything that fails gets a warning that says what won't work, and a notification follows after Finish.

`Setup = false` skips the window. Settings › RiftUI › *Run setup again* reopens it, and `Hub:RunCompatibilityCheck()` returns the same results as a table.

**Developer Mode:** tap the version number in Settings › RiftUI six times (it counts down after the third tap). It adds a Developer tab with the state machine, captured errors, diagnostics (instances, connections, missing sUNC functions) and Reinitialize. Reinitialize rebuilds the hub from the calls that created it and keeps every value, pin and reference.

## Visual documentation

Open `/` for the documentation and `/simulator` for RiftSim. The docs match RiftUI's graphite theme and cover installation, each control, theming, setup, notifications, configs, pinning, backgrounds and the hub API.

Examples include real screenshots and an opt-in **Try it live** view using the actual Luau library. The button page shows its after-click state; the themes guide compares Graphite, Ink, Slate and Ember and lets readers tween between them. Live examples use an isolated, in-memory filesystem.

```sh
pnpm dev          # documentation at /; simulator at /simulator
pnpm docs:images  # regenerate 19 screenshots; requires the dev server
pnpm docs:check   # check routes, search, copy, callbacks and mobile behavior
pnpm build        # builds simulator + docs + live preview entry points
```

Screenshot generation uses the repository's Playwright Chromium and ImageMagick. The source scenes are in `src/docs/demos.ts`; image provenance is recorded beside each screenshot and in `public/docs/images/provenance.json`.

## RiftSim

```sh
pnpm install
pnpm dev        # http://localhost:5199
pnpm test       # loader and library checks (66 checks)
pnpm icons      # rebuild Lucide sheets + shadow
```

- **Real Luau.** The engine (`engine/*.luau`) emulates the Roblox client in Luau: Instances, datatypes, Enums, signals, `task`, TweenService, UserInputService, RunService, HttpService, TextService and the sUNC surface (`gethui`, `cloneref`, `getcustomasset`, file functions, `request`, `loadstring`). It runs in the browser on the Luau VM compiled to WASM (`luau-web`), and under Lune for tests.
- **JS does only what a renderer does.** It covers ScreenGui layout (UDim2, AnchorPoint, AutomaticSize, UIListLayout, UIGridLayout, UIPadding, UIScale, constraints, ScrollingFrame canvases, TextScaled/TextBounds), DOM rendering (UICorner, UIStroke, UIGradient, 9-slice, image rects with ImageColor3 tint, rich text), input hit-testing and real text editing.
- **Workspace.** `writefile` data persists in IndexedDB like an executor's workspace folder; see *Workspace files*.
- **Executor profiles.** The topbar *Executor* picker makes the simulator pretend to be a weaker executor. There are four profiles: RiftSim (100%), MidExec (82%, no `getconnections`/`protectgui`, broken `listfiles`), FreeExec (~36%, no `gethui`/`cloneref`/`getcustomasset`, stubbed `request`/`setclipboard`), and PotatoExec (2%, `loadstring` and `HttpGet` only). The executor names are made up. Use them to see what the compatibility check and the hub's fallbacks do.
- **Uncaught errors.** Syntax errors and anything thrown outside `xpcall` (which RiftUI can't see) show a banner over the game and mark the line in the editor.
- **Zoom.** Ctrl/⌘ + scroll zooms at the cursor, `+`/`−`/`Fit`/`100%` sit bottom-right, and Space-drag or middle-drag pans. Alt-click any element to select it in the Explorer.

Known gaps: `rbxassetid://` images can't load in a browser (only `getcustomasset` files and URLs). Builder Sans and Gotham are shown with open stand-ins (Inter, Montserrat), and the Properties panel says so.

Theme choices in setup, Settings and Theme Studio now tween existing colours over 250ms without rebuilding the hub. A new choice interrupts from the current colours; cancelling Theme Studio returns to the previous palette. Setup choices and the compatibility list remain visible in bounded pages, with scrolling where needed.

On small browser windows the simulator starts with a Responsive screen that follows the available preview area. Fixed portrait and landscape phone presets are also available. Panels and setup/studio windows fit the simulated viewport, and touch swipes scroll ScrollingFrames.

### Remote images in RiftSim

Public image GETs are tried directly first. If a browser blocks the request, the Vite development/preview server retries it through the same-origin image proxy. Run `pnpm dev`, or `pnpm build` followed by `pnpm preview`; a static-only deployment needs an equivalent backend proxy or CORS-enabled image hosts. The proxy accepts public HTTP(S) GET URLs, follows validated redirects, and limits responses to 16 MB.

Large HTTP responses and file reads cross the Luau/WASM bridge in 32 KiB chunks so ordinary image downloads do not overflow its string-marshalling stack. Empty downloads and HTML pages have distinct background-image errors.

`pnpm test:browser` checks a 3 MiB binary HTTP/file round trip, simulated CORS failure/retry, and background loading against the running dev server. Pass `--live-image=<url>` directly to `node scripts/dev/binary-check.mjs` to additionally exercise a real image URL.

### Cloudflare deployment

`wrangler.toml` deploys the Vite `dist/` assets to Cloudflare Workers. It runs `pnpm build` before deployment. Documentation is served at `/`, RiftSim at `/simulator`, and live documentation examples remain at `/docs/preview.html`.

```sh
pnpm dlx wrangler deploy
```

The config uses clean URLs without trailing slashes and ordinary 404s for missing files. This is a static-assets deployment; the Node-based image proxy remains available through `pnpm dev` / `pnpm preview`, not the Cloudflare static host.
