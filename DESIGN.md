# Design

RiftUI is near-black graphite. There's no accent hue by default, and white is the only "on" colour. Floating surfaces (dock, panel, popups, toasts, pins) get a 1px stroke, a 1px top sheen and a soft 9-slice shadow. Inside a panel nothing is a card: sections are flat groups whose uppercase title sits notched into a hairline, imgui-groupbox style.

## Tokens (DefaultTheme)

| Token | Value | Use |
|---|---|---|
| Panel | `#0F0F11` | dock, panel, popups, toasts, dialogs; also masks the group-title notch |
| PanelStroke | `#2A2A30` | 1px outline on floating surfaces |
| Highlight | `#FFFFFF` at 93% transparency | 1px top sheen on the dock and panel |
| Tile / TileHover / TileActive | `#17171A` / `#1E1E22` / `#26262B` | dock tiles are transparent until hovered; header icon chip; buttons |
| Divider | `#1D1D21` | group hairlines, header rule |
| Text / SubText / Muted | `#EDEDEF` / `#8E8E96` / `#5F5F67` | an unchecked toggle's label drops to SubText |
| Field / FieldStroke | `#0A0A0C` / `#2A2A30` | inputs, checkboxes, chips |
| Track / Knob | `#2A2A30` / `#6E6E76` | 2px slider track |
| Accent / AccentText | `#F2F2F3` / `#0F0F11` | checked boxes, slider fill and notch, badges, the notification slit |
| Danger / Success / Warning | `#FF7070` / `#78DC96` / `#F2C24F` | errors, state history |

## Controls

- **Toggle:** a 16px square checkbox, radius 4. It fills white with a dark check and pops from 0.8 with Back Out.
- **Slider:** a 2px hairline track with a 4×14 white notch. The value is quiet mono text that becomes a field when clicked.
- **Dropdown / keybind:** field chips.
- **Buttons:** Tile fill, 1px stroke, radius 6.

## Type

Inter (`rbxassetid://12187365364`): 15 SemiBold panel titles, 13 Regular row labels, 12 Medium section heads, 11 descriptions. Roboto Mono Medium 11–12 for values, keys and errors.

## Shape & space

- **Radii:** dock 12, tiles 9, panel/dialog 14, popups 10, fields 5–8, checkboxes 4, toasts 4.
- **Dock:** 40px tiles, 4px gap, 5px padding (50px tall), 40px above the screen edge.
- **Panel:** 470px wide, centred on screen and kept clear of the topbar and the dock.
- **Rows:** 34px, or 52px for sliders.

## Motion

- **Rise:** a panel rises out of its tile toward the centre (0.34s Quint Out on position and scale from 0.92, a 0.2s fade) and folds back toward the tile (0.16s Quad In).
- **Tab switch:** the content slides 18px in from the side of the tile you came from.
- **Notifications:** the slit draws (0.22s), the card opens out of it (0.34s), the slit drains as the timer, then the card closes back into the slit and the stack folds up.
- **Press:** tiles and buttons press to 0.92–0.97 and release with Back Out.

## Simulator shell

Near-black panels (`#111`, `#171717`, borders `#262626`), Inter 13, Roboto Mono for code and numbers, `#3D7BFD` only for Explorer selection and the viewport highlight.
