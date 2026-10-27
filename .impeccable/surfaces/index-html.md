---
version: 1
slug: "index-html"
primary_target: "simulator/index.html"
related_targets: ["lib/RiftUI.luau"]
---

# Surface: RiftUI window + simulator

Mode: Operate. Audience: script hub authors previewing hubs before shipping. Task: write a hub script, run it, inspect the emulated ScreenGui, iterate. Constraints: library is pure Luau using only Roblox + sUNC APIs; simulator runs that same Luau in WASM.

## Direction contract

THESIS: A hub is a dock, not a window. Tabs live as icon tiles in a bottom hotbar; a tab's panel rises above the dock on click and folds away on click-off; sections can be pinned to stay on screen. Refuses the category's always-open sidebar window (Rayfield/Orion/Obsidian).

OWN-WORLD: Neutral graphite (#1f1f1f panels, #2a2a2a tiles, #4a4a4a 1px strokes, 14px/10px radii), white as the only "on" colour, Inter (rbxassetid 12187365364) throughout, Lucide icons at 1.9 stroke via getcustomasset sprite sheets, tabular mono for values. No accent hue by default; theme can set one.

STORY: The author sees their hub exactly as players will: a quiet dock over the game, a live count of what is on per tab, a panel that opens on demand, pins for what matters mid-game.

FIRST VIEWPORT: Simulator shell: top bar (run, viewport size, backdrop), Lua editor left, game viewport centre with dock bottom-centre and Combat panel open above it, Explorer + Properties right, Output bottom.

FORM: canon chosen by user, reshaped by the user's Figma dock sketch; position: user-authored. seed: none (unavailable)

Signature interaction: panel rises from its tile (scale/position tween from the tile, 180ms quint-out), click-off folds it back; hover pill names the tile.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
