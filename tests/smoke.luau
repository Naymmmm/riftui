--!nocheck
-- Headless smoke test: runs the emulated engine, RiftUI and the example hub under Lune,
-- then drives the API (flags, Set, configs, pins, unload) and checks the instance tree.
-- Run with `pnpm test` (bundles first) or `lune run tests/smoke`.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local files: { [string]: string } = {}
-- Lune's fs yields; the engine resumes its own coroutines, so read everything up front
local public: { [string]: string } = {}
local function preload(dir: string)
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			preload(path)
		else
			public[string.sub(path, #"public/" + 1)] = fs.readFile(path)
		end
	end
end
preload("public")
local hubSource = fs.readFile("examples/hub.luau")
local folders: { [string]: boolean } = {}
local errors = {}
local env

local ALPHA = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function b64encode(data: string): string
	local n = #data
	local src = buffer.fromstring(data)
	local out = buffer.create(math.ceil(n / 3) * 4)
	local o = 0
	for i = 0, n - 1, 3 do
		local a = buffer.readu8(src, i)
		local b = i + 1 < n and buffer.readu8(src, i + 1) or 0
		local c = i + 2 < n and buffer.readu8(src, i + 2) or 0
		local v = a * 65536 + b * 256 + c
		buffer.writeu8(out, o, string.byte(ALPHA, bit32.extract(v, 18, 6) + 1))
		buffer.writeu8(out, o + 1, string.byte(ALPHA, bit32.extract(v, 12, 6) + 1))
		buffer.writeu8(out, o + 2, i + 1 < n and string.byte(ALPHA, bit32.extract(v, 6, 6) + 1) or 61)
		buffer.writeu8(out, o + 3, i + 2 < n and string.byte(ALPHA, bit32.extract(v, 0, 6) + 1) or 61)
		o += 4
	end
	return buffer.tostring(out)
end

local host = {
	sync = function()
		return ""
	end,
	measure = function(text, size)
		return tostring(#text * size * 0.5) .. "\31" .. tostring(size)
	end,
	print = function(m)
		print("[print] " .. m)
	end,
	warn = function(m)
		print("[warn] " .. m)
	end,
	error = function(m, trace)
		table.insert(errors, m)
		print("[error] " .. m .. "\n" .. (trace or ""))
	end,
	now = function()
		return os.time() * 1000
	end,
	load = function(src, name)
		local ok, fn = pcall(luau.load, src, { debugName = name, environment = env })
		if ok then
			return fn
		end
		return tostring(fn)
	end,
	fs = function(op, path, data)
		if op == "write" then
			files[path] = data
			return ""
		elseif op == "read" then
			return files[path] or ("ERR\31no file " .. path)
		elseif op == "isfile" then
			return files[path] and "1" or "0"
		elseif op == "isfolder" then
			return folders[path] and "1" or "0"
		elseif op == "mkdir" then
			folders[path] = true
			return ""
		elseif op == "delfile" then
			files[path] = nil
			return ""
		elseif op == "list" then
			local out = {}
			for k in files do
				if string.sub(k, 1, #path + 1) == path .. "/" then
					table.insert(out, k)
				end
			end
			return table.concat(out, "\31")
		elseif op == "asset" then
			return files[path] and ("rbxasset://riftsim/" .. path) or "ERR\31missing " .. path
		end
		return ""
	end,
	http = function(method, url)
		if url == "https://image.test/empty.png" then return "200\31\31{}" end
		if url == "https://image.test/page.png" then return "200\31" .. b64encode("<!doctype html><html>Not an image</html>") .. "\31{}" end
		local rel = string.match(url, "/riftui/[^/]+/public/(.+)$")
		if rel and public[rel] then
			return "200\31" .. b64encode(public[rel]) .. "\31{}"
		end
		return "404\31\31{}"
	end,
	clipboard = function() end,
}
host.register = function(step, run)
	host.step = step
	host.run = run
end

local sink = {}
env = setmetatable({
	__HOST = host,
	__sink = function(t)
		sink.R = t
	end,
}, { __index = _G })
local engine = luau.load(public["engine.luau"], { debugName = "engine", environment = env })
engine()
assert(host.step and host.run, "engine registered step and run")

local function frames(n)
	for _ = 1, n do
		host.step(1 / 60, "")
	end
end

local checks = 0
local function check(cond, label)
	checks += 1
	if not cond then
		table.insert(errors, "check failed: " .. label)
		print("FAIL " .. label)
	else
		print("ok   " .. label)
	end
end

host.run(hubSource, "hub.lua")
frames(30)

local probe = [[
	local R = {}
	local gui = gethui():FindFirstChild("RiftUI")
	R.gui = gui ~= nil
	local tiles = 0
	for _, c in gui.DockHolder.Dock:GetChildren() do
		if c:IsA("TextButton") then tiles += 1 end
	end
	R.tiles = tiles
	local Rift = nil
	getgenv().__probe = R
	__sink(R)
]]
host.run(probe, "probe")
frames(2)
local R = sink.R
check(R.gui, "RiftUI ScreenGui exists under gethui()")
check(R.tiles == 6, "dock has search + 4 hub tabs + Settings (got " .. tostring(R.tiles) .. ")")

host.run([[
	local Rift = loadstring(game:HttpGet("https://raw.githubusercontent.com/x/riftui/main/public/RiftUI.luau"))()
	local R = getgenv().__probe
	local flags = Rift.Flags
	-- the example's library instance is a different module copy; use a fresh hub for API checks
	local Hub = Rift:CreateHub({ Name = "Test Hub", Id = "test-hub", Setup = false })
	R.hubId = Hub.Id
	local compat = Hub:RunCompatibilityCheck()
	R.compatCount = #compat
	R.compatFailed = {}
	for _, r in compat do
		if not r.Ok then table.insert(R.compatFailed, r.Name .. ": " .. tostring(r.Error)) end
	end
	local emptyOk, emptyError = pcall(Hub.SetBackground, Hub, { Url = "https://image.test/empty.png" })
	R.bgEmpty = not emptyOk and string.find(tostring(emptyError), "empty response", 1, true) ~= nil
	local htmlOk, htmlError = pcall(Hub.SetBackground, Hub, { Url = "https://image.test/page.png" })
	R.bgHTML = not htmlOk and string.find(tostring(htmlError), "HTML page", 1, true) ~= nil
	-- background images: base64 PNG (data URI too), a URL, and junk that must be refused
	local okBg = pcall(function()
		Hub:SetBackground({ Base64 = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==", Opacity = 0.5 })
	end)
	R.bgBase64 = okBg and Hub.Background and Hub.Background.File == "RiftUI/test-hub/background.png"
	R.bgLayer = okBg and Hub.Panel:FindFirstChild("Backdrop") ~= nil
	local okUrl = pcall(function()
		Hub:SetBackground({ Url = "https://raw.githubusercontent.com/x/riftui/main/public/assets/shadow.png", Dock = true })
	end)
	R.bgUrl = okUrl and Hub.DockHolder:FindFirstChild("Backdrop") ~= nil
	local okJunk, junkErr = pcall(function()
		Hub:SetBackground({ Base64 = "aGVsbG8gd29ybGQ=" })
	end)
	R.bgJunk = not okJunk and string.find(tostring(junkErr), "isn't a PNG") ~= nil
	-- free placement: rotated image in a corner
	Hub:PlaceBackground({ Preset = "Body pillow (lying down)" })
	local placed = Hub.Panel:FindFirstChild("Backdrop") and Hub.Panel.Backdrop:FindFirstChild("Placement")
	R.placed = placed ~= nil and placed.Image.Rotation == 90 and placed.AnchorPoint == Vector2.new(0.5, 1)
	-- custom themes: save, list, share with a URL image, share with an embedded image, import
	local look = { Format = "riftui-theme", Name = "Midnight Sakura", Base = "Slate", Colors = { Accent = "FF8FC8" }, Background = Hub.Background }
	Hub:SaveTheme(look)
	R.themeListed = table.find(Rift:ListThemes(), "Midnight Sakura") ~= nil
	local urlCode = Hub:ExportTheme(look, false)
	local imported = Hub:ImportTheme(urlCode)
	R.urlRoundTrip = string.sub(urlCode, 1, 6) == "RIFT1:" and imported.Base == "Slate" and imported.Colors.Accent == "FF8FC8"
		and imported.Background and imported.Background.Image and imported.Background.Image.Url ~= nil and imported.Background.File == nil
		and imported.Background.Rotation == 90
	Hub:SetBackground({ Base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==" })
	local local_ = { Format = "riftui-theme", Name = "Embedded", Base = "Ink", Colors = {}, Background = Hub.Background }
	local embedCode = Hub:ExportTheme(local_, true)
	local emb = Hub:ImportTheme(embedCode)
	R.embedded = emb.Background and emb.Background.Image and emb.Background.Image.Data ~= nil
	local okFetch, path = pcall(Hub.FetchThemeImage, Hub, emb)
	R.fetched = okFetch and path == "RiftUI/test-hub/background.png" and emb.Background.Aspect == 1
	local noEmbed = Hub:ImportTheme(Hub:ExportTheme(local_, false))
	R.leftOut = noEmbed.Background == nil
	local okBad, badErr = pcall(Hub.ImportTheme, Hub, "RIFT1:bm90IGpzb24=")
	R.badCode = not okBad and string.find(tostring(badErr), "damaged") ~= nil
	Hub:DeleteTheme("Midnight Sakura")
	R.themeDeleted = table.find(Rift:ListThemes(), "Midnight Sakura") == nil
	Hub:SetBackground(nil)
	R.bgCleared = Hub.Panel:FindFirstChild("Backdrop") == nil
	-- running the same hub again replaces the earlier copy
	local Dup = Rift:CreateHub({ Name = "Dup", Id = "dup", Setup = false })
	local Dup2 = Rift:CreateHub({ Name = "Dup", Id = "dup", Setup = false })
	R.replaced = Dup._destroyed == true and Dup2.Gui.Parent ~= nil
	Dup2:Destroy()
	local Tab = Hub:Tab({ Name = "T", Icon = "box" })
	local S = Tab:Section({ Name = "S" })
	local toggled = nil
	local t = S:Toggle({ Name = "A", Flag = "TA", Callback = function(v) toggled = v end })
	local sl = S:Slider({ Name = "B", Flag = "TB", Min = 0, Max = 10, Step = 0.5, Default = 3 })
	local dd = S:Dropdown({ Name = "C", Flag = "TC", Options = { "x", "y" }, Default = "x" })
	local kb = S:Keybind({ Name = "D", Flag = "TD", Default = Enum.KeyCode.Q })
	local cp = S:ColorPicker({ Name = "E", Flag = "TE", Default = Color3.fromRGB(10, 20, 30) })
	t:Set(true)
	sl:Set(7.3)
	dd:Set("y")
	task.wait()
	R.toggled = toggled
	R.badge = Tab.Badge.Visible and Tab.BadgeText.Text
	R.slider = sl.Value
	local gui, palette, control = Hub.Gui, Hub.Theme, flags.TA
	local swatchBefore = cp.Value
	Hub:SetTheme("Slate")
	local oldPanel = Hub.Panel.BackgroundColor3
	task.wait(0.08)
	R.themeIntermediate = Hub.Panel.BackgroundColor3 ~= oldPanel and Hub.Panel.BackgroundColor3 ~= Hub.Theme.Panel
	task.wait(0.3)
	R.liveTheme = Hub.Gui == gui and Hub.Theme == palette and flags.TA == control and t.Value == true
	R.themeColours = Hub.Panel.BackgroundColor3 == Hub.Theme.Panel and Hub.Dock.BackgroundColor3 == Hub.Theme.Panel
	Hub:SetTheme("Ink")
	task.wait(0.05)
	Hub:SetTheme("Graphite")
	task.wait(0.3)
	R.retargetTheme = Hub.Panel.BackgroundColor3 == Hub.Theme.Panel and Hub.ThemeName == "Graphite"
	R.customColour = cp.Value == swatchBefore
	local ok, err = Hub:SaveConfig("unit")
	R.saved = ok
	t:Set(false)
	sl:Set(1)
	dd:Set("x")
	kb:Set(Enum.KeyCode.Z)
	R.loaded = Hub:LoadConfig("unit")
	R.after = { flags.TA.Value, flags.TB.Value, flags.TC.Value, flags.TD.Value and flags.TD.Value.Name }
	R.configs = Hub:ListConfigs()
	S:Pin()
	R.pinned = S.Pinned and Hub.PinLayer:FindFirstChild("Pin_S") ~= nil
	S:Unpin()
	R.unpinned = not S.Pinned and S.Rows.Parent == S.Frame
	-- reinitialize keeps values and keeps the old references working
	t:Set(true)
	Hub:Reinitialize()
	task.wait(0.2)
	R.reinitValue = flags.TA.Value
	t:Set(false)
	R.forwarded = flags.TA.Value == false
	Hub:SetStealth(true)
	R.stealthName = Hub.Gui.Name ~= "RiftUI"
	Hub:SetStealth(false)
	R.stealthRestored = Hub.Gui.Name == "RiftUI"
	local setupGui = Hub.Gui
	Hub.Options.Setup = { Title = "How do you play?", Options = {
		{ Type = "Dropdown", Name = "Play style", Options = { "Legit", "Balanced" }, Default = "Legit" },
	} }
	Hub:OpenSetup()
	local setup = Hub.Gui:FindFirstChild("Setup")
	local nextButton = setup:FindFirstChild("Continue", true)
	firesignal(nextButton.MouseButton1Click)
	task.wait(0.3)
	firesignal(setup:FindFirstChild("Theme_Slate", true).MouseButton1Click)
	task.wait(0.3)
	R.setupLiveTheme = Hub.Theme.Panel == Color3.fromRGB(13, 17, 23) and Hub.Gui == setupGui
	firesignal(nextButton.MouseButton1Click)
	task.wait(0.3)
	local option = setup:FindFirstChild("Dropdown_Play style", true)
	R.setupOptions = option ~= nil and option.Parent.Parent.Parent.Parent.Parent.ClassName == "Frame"
	firesignal(nextButton.MouseButton1Click)
	task.wait(1.6)
	local summary = setup:FindFirstChild("Summary", true)
	R.setupCompat = summary.Visible and summary.Parent.ClassName == "Frame"
	firesignal(nextButton.MouseButton1Click)
	task.wait(0.3)
	R.setupKeptGui = Hub.Gui == setupGui and not Hub._setupOpen
	xpcall(function()
		error("boom")
	end, Rift.HandleError)
	task.wait(0.1)
	R.failed = Rift.State == "Failed" and #Rift.Errors > 0
	Hub:Destroy()
	R.destroyed = Hub.Gui.Parent == nil
	R.unloaded = Rift.State == "Unloaded"
]], "api")
frames(300)
check(R.hubId == "test-hub", "hubs keep their Id")
check(R.compatCount and R.compatCount >= 8 and #R.compatFailed == 0, "compatibility check passes on a full sUNC host (" .. table.concat(R.compatFailed or {}, "; ") .. ")")
check(R.bgEmpty == true, "empty image downloads have a specific error")
check(R.bgHTML == true, "HTML responses explain that a direct image URL is needed")
check(R.bgBase64 == true, "SetBackground decodes a base64 PNG data URI into RiftUI/<Id>/background.png")
check(R.bgLayer == true, "the background image is layered into the panel")
check(R.bgUrl == true, "SetBackground downloads from a URL and can sit behind the toolbar")
check(R.bgJunk == true, "non-image data is refused with a readable error")
check(R.placed == true, "free placement anchors and rotates the image (lying-down body pillow)")
check(R.themeListed == true, "SaveTheme writes RiftUI/themes/<name>.json and ListThemes finds it")
check(R.urlRoundTrip == true, "share code round-trips base, colours, placement and the image URL")
check(R.embedded == true, "a local image can be embedded in the share code")
check(R.fetched == true, "FetchThemeImage writes the embedded image and reads its size")
check(R.leftOut == true, "a local image left out of the code drops the background")
check(R.badCode == true, "a damaged share code is refused with a readable error")
check(R.themeDeleted == true, "DeleteTheme removes it")
check(R.bgCleared == true, "SetBackground(nil) removes the image")
check(R.replaced == true, "re-running a hub with the same Id replaces the old one")
check(files["RiftUI/test-hub/configs/unit.json"] ~= nil, "configs live under RiftUI/<Id>/configs")
check(R.toggled == true, "Toggle callback fires with the new value")
check(R.badge == "1", "tile badge counts enabled toggles")
check(R.themeIntermediate == true, "theme colours interpolate before reaching their destination")
check(R.liveTheme == true, "theme changes preserve the GUI, palette, controls and values")
check(R.themeColours == true, "existing panel and dock receive the new palette")
check(R.retargetTheme == true, "rapid theme changes settle on the latest palette")
check(R.customColour == true, "theme changes preserve custom colour values")
check(R.slider == 7.5, "Slider rounds to Step (7.3 -> 7.5, got " .. tostring(R.slider) .. ")")
check(R.saved == true, "SaveConfig writes a file")
check(R.loaded == true, "LoadConfig reads it back")
check(R.after and R.after[1] == true and R.after[2] == 7.5 and R.after[3] == "y" and R.after[4] == "Q", "config restores toggle, slider, dropdown and keybind")
check(R.configs and table.find(R.configs, "unit") ~= nil, "ListConfigs lists the saved config")
check(R.pinned == true, "Section:Pin moves rows into a floating card")
check(R.unpinned == true, "Section:Unpin returns rows to the panel")
check(R.reinitValue == true, "Reinitialize keeps flag values")
check(R.forwarded == true, "old control references forward to the rebuilt hub")
check(R.stealthName == true, "stealth mode randomises instance names")
check(R.stealthRestored == true, "turning stealth off restores names")
check(R.setupLiveTheme == true, "setup theme choices recolour the existing hub")
check(R.setupOptions == true, "setup option controls have a frame viewport rather than a zero-height canvas")
check(R.setupCompat == true, "compatibility summary is visible inside a frame viewport")
check(R.setupKeptGui == true, "finishing setup preserves the GUI")
check(R.failed == true, "Rift.HandleError records the error and enters Failed")
check(R.destroyed == true, "Hub:Destroy removes the ScreenGui")
check(R.unloaded == true, "state machine ends in Unloaded")
check(files["RiftUI/assets/shadow-3.png"] ~= nil, "shadow asset cached through writefile")

print(string.format("\n%d checks, %d problems", checks, #errors))
if #errors > 0 then
	process.exit(1)
end
