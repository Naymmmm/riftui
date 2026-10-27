# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Stack

- **Library:** RiftUI itself is written in Luau, distributed as a single `loadstring`-ready source file for sUNC-compatible executors.
- **Simulator:** Vite + vanilla TypeScript, no UI framework. The simulator runs the *same* Luau source through the real Luau VM compiled to WASM (`luau-web`) against a JS emulation of the Roblox Instance tree (ScreenGui, Frame, TextLabel, TextButton, TextBox, ImageLabel, ScrollingFrame, UIListLayout, UICorner, UIStroke, UIPadding, UIGradient…), UDim2/Color3/Vector2 datatypes, TweenService, UserInputService and RBXScriptSignal. It renders that tree to the DOM the way Roblox lays out GuiObjects.
- **Headless tests:** Lune runs smoke tests of the library against a small Luau Instance stub.

## Users

Script hub authors: developers building multi-tab script utilities (toggles, sliders, keybinds, dropdowns, inputs) for Roblox executors, who want a polished, consistent window with a few lines of Lua and need to preview and iterate on it without launching the game.

## Product Purpose

RiftUI gives hub authors a complete window/tab/section/control API that looks good by default and behaves correctly (dragging, minimize, keybind toggle, notifications, config flags). The simulator lets them write against the real API and see the result in a browser, so iteration does not require an executor or a game session. Success: an author can paste their hub script into the simulator, see it render faithfully, and ship the same script unchanged.

## Positioning

The preview is not a mockup: it executes the real Luau library on an emulated ScreenGui, so what renders in the browser is the same code path that runs in-game.

## Operating Context

- Authors write Lua in an editor, run it in an executor, and inspect the result in-game; the simulator replaces that loop during development.
- Executors expose sUNC functions (`gethui`, `cloneref`, `protectgui`, `getgenv`, file functions for configs). RiftUI must feature-detect these and degrade cleanly when absent (falls back to `CoreGui` / `PlayerGui`).
- In-game, the UI floats over arbitrary 3D scenes and must stay legible on any background.

## Capabilities and Constraints

- Components: Window, Tab, Section, Button, Toggle, Slider, Dropdown (single/multi), Input, Keybind, ColorPicker, Label/Paragraph, Notification.
- Global `Flags` table for values; window toggle keybind; draggable window.
- Simulator must only use APIs the emulated Roblox layer actually implements; the library must not call browser APIs.
- Open: config save/load file format; theming API surface.

## Brand Commitments

Name: RiftUI. Existing placeholder icon at `assets/icon.svg` (not binding).

- Standing visual preference (chosen 2026-10-27): the category-standard dark script-hub window, executed at full craft, not an exotic world. It must still read as distinct from Rayfield/Orion clones.
- Quality references: Obsidian (clean but plain) and LinoriaLib (older dense imgui/CS-style). Match or beat their density and crispness.

## Evidence on Hand

None. No users, testimonials, benchmarks, or adoption numbers exist; do not fabricate any.

## Product Principles

1. The simulator never lies: anything shown is produced by the real library code.
2. Short path to a good-looking hub; depth available without ceremony.
3. Legible over any game scene.
4. Executor-agnostic: depend only on sUNC, feature-detect everything.
