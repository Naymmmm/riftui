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
local clipboardText
local authClipboard

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
			return files[path] and string.sub(files[path], 1, 11) == "iVBORw0KGgo" and ("rbxasset://riftsim/" .. path) or "ERR\31image-only executor: not a PNG " .. path
		end
		return ""
	end,
	http = function(method, url, headers)
		if url == "https://auth.test/v1/script" then
			if string.find(headers or "", "Bearer good-key", 1, true) then return "200\31" .. b64encode("return 'hub source'") .. "\31{}" end
			if string.find(headers or "", "Bearer busy-key", 1, true) then return "503\31\31{}" end
			return "401\31" .. b64encode('{"error":"Key expired"}') .. "\31{}"
		end
		if url == "https://image.test/empty.png" then return "200\31\31{}" end
		if url == "https://image.test/page.png" then return "200\31" .. b64encode("<!doctype html><html>Not an image</html>") .. "\31{}" end
		local rel = string.match(url, "/riftui/[^/]+/public/(.+)$")
		if rel and public[rel] then
			return "200\31" .. b64encode(public[rel]) .. "\31{}"
		end
		return "404\31\31{}"
	end,
	clipboard = function(value)
		clipboardText = value
		if value == "https://keys.test" then authClipboard = value end
	end,
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
check(R.tiles == 7, "dock has search + 5 hub tabs + Settings (got " .. tostring(R.tiles) .. ")")

host.run([[
	local Rift = loadstring(game:HttpGet("https://raw.githubusercontent.com/x/riftui/main/public/RiftUI.luau"))()
	local R = getgenv().__probe
	local flags = Rift.Flags
	-- the example's library instance is a different module copy; use a fresh hub for API checks
	local Hub = Rift:CreateHub({ Name = "Test Hub", Id = "test-hub", Setup = false })
	R.hubId = Hub.Id
	local compat = Hub:RunCompatibilityCheck()
	R.customAssetProbeRemoved = not isfile("RiftUI/test-hub/.rift-probe.png")
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
	R.badgeHidden = not Tab.Badge.Visible
	Tab:SetBadge("New")
	R.badge = Tab.Badge.Visible and Tab.BadgeText.Text
	Tab:SetBadge(nil)
	R.badgeCleared = not Tab.Badge.Visible
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
	-- A saved autoload starts the toggle on. Its constructor must not call a nil picker.
	makefolder("RiftUI/autoload-startup")
	makefolder("RiftUI/autoload-startup/configs")
	writefile("RiftUI/autoload-startup/configs/start.json", game:GetService("HttpService"):JSONEncode({ Flags = {} }))
	writefile("RiftUI/autoload-startup/configs/autoload.txt", "start")
	local errorsBeforeStartup = #Rift.Errors
	-- auth gate: rejects, remembers, retries and returns the server's script
	Rift:ClearAuthKey("auth-hub")
	local authResult = {}
	task.spawn(function()
		authResult.source, authResult.key = Rift:CreateAuth({ Name = "Auth Hub", Id = "auth-hub", Url = "https://auth.test/v1/script", GetKeyUrl = "https://keys.test" })
	end)
	task.wait(0.1)
	local authGui = gethui():FindFirstChild("RiftAuth")
	local keyBox = authGui and authGui:FindFirstChild("KeyBox", true)
	local authStatus = authGui and authGui:FindFirstChild("Status", true)
	firesignal(authGui:FindFirstChild("Get key", true).MouseButton1Click)
	R.authCopy = authStatus.Text == "Key link copied. Open it in your browser."
	keyBox.Text = "bad-key"
	firesignal(keyBox.FocusLost, true)
	task.wait(0.2)
	R.authRejected = authStatus.Text == "Key expired" and authResult.source == nil and authGui.Parent ~= nil
	keyBox.Text = "  good-key  "
	firesignal(authGui:FindFirstChild("Continue", true).MouseButton1Click)
	task.wait(1)
	R.authAccepted = authResult.source == "return 'hub source'" and authResult.key == "good-key" and gethui():FindFirstChild("RiftAuth") == nil
	R.authSaved = isfile("RiftUI/auth-hub/auth.key") and readfile("RiftUI/auth-hub/auth.key") == "good-key"
	-- a saved key is checked on launch without input
	local again = {}
	task.spawn(function() again.source = Rift:CreateAuth({ Name = "Auth Hub", Id = "auth-hub", Url = "https://auth.test/v1/script" }) end)
	task.wait(1)
	R.authRemembered = again.source == "return 'hub source'"
	-- server errors keep the saved key; rejections forget it
	writefile("RiftUI/auth-hub/auth.key", "busy-key")
	local busy = {}
	task.spawn(function() busy.source, busy.reason = Rift:CreateAuth({ Name = "Auth Hub", Id = "auth-hub", Url = "https://auth.test/v1/script" }) end)
	task.wait(0.3)
	local busyGui = gethui():FindFirstChild("RiftAuth")
	R.authRetryKeeps = isfile("RiftUI/auth-hub/auth.key") and busyGui:FindFirstChild("Status", true).Text == "The server returned HTTP 503."
	firesignal(busyGui:FindFirstChild("Close", true).MouseButton1Click)
	task.wait(0.5)
	R.authClosed = busy.source == nil and busy.reason == "closed" and gethui():FindFirstChild("RiftAuth") == nil
	writefile("RiftUI/auth-hub/auth.key", "bad-key")
	task.spawn(function() Rift:CreateAuth({ Name = "Auth Hub", Id = "auth-hub", Url = "https://auth.test/v1/script" }) end)
	task.wait(0.3)
	R.authForgets = not isfile("RiftUI/auth-hub/auth.key")
	firesignal(gethui():FindFirstChild("RiftAuth"):FindFirstChild("Close", true).MouseButton1Click)
	-- a custom Request replaces HTTP
	local custom = {}
	task.spawn(function()
		custom.source = Rift:CreateAuth({ Name = "Custom", Remember = false, Request = function(key) return key == "ok", key == "ok" and "custom source" or "Nope" end })
	end)
	task.wait(0.6)
	local customGui = gethui():FindFirstChild("RiftAuth")
	customGui:FindFirstChild("KeyBox", true).Text = "ok"
	firesignal(customGui:FindFirstChild("KeyBox", true).FocusLost, true)
	task.wait(1)
	R.authCustom = custom.source == "custom source"
	R.authHttpsOnly = not pcall(function() Rift:CreateAuth({ Url = "http://auth.test/v1/script" }) end)
	-- loading screen holds the dock and Open until it finishes
	local loader = Rift:CreateHub({ Name = "Loader", Id = "loading-hub", Setup = false, Settings = false, Loading = { Manual = true, MinDuration = 0 } })
	local lt = loader:Tab({ Name = "Main" })
	lt:Section({ Name = "S" }):Button({ Name = "Go" })
	loader:Open(lt)
	task.wait(0.1)
	R.loadingCard = loader.Gui:FindFirstChild("Loading") ~= nil and loader:IsLoading() and not loader.DockHolder.Visible and loader._open == nil
	loader:SetLoading("Fetching", 0.5)
	loader:SetLoading(nil, 0.2)
	R.loadingProgress = loader._loading.Progress == 0.5 and loader._loading.Status.Text == "Fetching"
	loader:FinishLoading()
	task.wait(0.8)
	R.loadingDone = not loader:IsLoading() and loader.Gui:FindFirstChild("Loading") == nil and loader.DockHolder.Visible and loader._open == lt
	loader:Destroy()
	-- HubIcon: a Lucide name, an asset number, or a fallback to the initial
	local function chipOf(h)
		return h.Gui:FindFirstChild("Loading") and h.Gui.Loading:FindFirstChild("Chip", true)
	end
	local lucideHub = Rift:CreateHub({ Name = "Icon hub", Id = "icon-hub", Setup = false, Settings = false, HubIcon = "rocket", Loading = { Manual = true } })
	lucideHub:SetWatermark(true, true)
	local lucideChip = chipOf(lucideHub)
	local wmIcon = lucideHub.Gui:FindFirstChild("Watermark"):FindFirstChild("Icon")
	R.hubIconLucide = lucideHub.Icon == "rocket" and lucideChip:FindFirstChild("Icon") ~= nil and lucideChip.Icon.ImageRectSize.X > 0
		and wmIcon ~= nil and lucideHub.Gui.Watermark:FindFirstChild("Mark") == nil
	lucideHub:Destroy()
	local imageHub = Rift:CreateHub({ Name = "Image hub", Id = "image-hub", Setup = false, Settings = false, HubIcon = 1234567, Loading = { Manual = true } })
	local imageIcon = chipOf(imageHub):FindFirstChild("Icon")
	R.hubIconImage = imageIcon ~= nil and imageIcon.Image == "rbxassetid://1234567" and imageIcon.ImageRectSize.X == 0
	imageHub:Destroy()
	local plainHub = Rift:CreateHub({ Name = "Plain hub", Id = "plain-hub", Setup = false, Settings = false, HubIcon = "not-a-real-icon", Loading = { Manual = true } })
	local plainChip = chipOf(plainHub)
	R.hubIconFallback = plainChip:FindFirstChild("Icon") == nil and plainChip:FindFirstChildOfClass("TextLabel").Text == "P"
	plainHub:Destroy()
	R.hubIconRejects = not pcall(function() Rift:CreateHub({ Name = "Bad", Id = "bad-icon", HubIcon = true }) end)
	local auto = Rift:CreateHub({ Name = "Auto loader", Id = "auto-loading-hub", Setup = false, Settings = false, Loading = { MinDuration = 0 } })
	task.wait(0.8)
	R.loadingAuto = not auto:IsLoading() and auto.DockHolder.Visible
	auto:Destroy()
	local startup = Rift:CreateHub({ Name = "Autoload startup", Id = "autoload-startup", Setup = false })
	task.wait(0.15)
	local startupToggle, startupPick
	for _, section in startup.SettingsTab.Sections do
		for _, control in section.Controls do
			if control.Name == "Autoload a config" then startupToggle = control end
			if control.Name == "Autoload config" then startupPick = control end
		end
	end
	R.autoloadStartup = #Rift.Errors == errorsBeforeStartup and startupToggle.Value and startupPick.Frame.Visible and startupPick.Value == "start"
	startupToggle:Set(false)
	task.wait(0.03)
	R.autoloadDisable = startup:GetAutoload() == nil and not startupPick.Frame.Visible
	startupToggle:Set(true)
	task.wait(0.03)
	R.autoloadEnable = startup:GetAutoload() == "start" and startupPick.Frame.Visible
	startup:Destroy()
	-- per-config autoload, rename, share codes
	Hub:SetAutoload("unit")
	R.autoload = Hub:GetAutoload() == "unit"
	local code = Hub:ExportConfig("unit")
	R.exported = type(code) == "string" and string.sub(code, 1, 9) == "RIFTCFG1:"
	local imported, importedName = Hub:ImportConfig(code, "copy")
	R.imported = imported and importedName == "copy" and table.find(Hub:ListConfigs(), "copy") ~= nil
	R.foreignRefused = not Hub:ImportConfig("RIFTCFG1:" .. "e30=")
	R.renamed = Hub:RenameConfig("unit", "main") and Hub:GetAutoload() == "main" and not table.find(Hub:ListConfigs(), "unit")
	local info = Hub:ConfigInfo("main")
	R.info = info and info.Autoload and info.Settings and info.Settings > 0 and type(info.SavedAt) == "number"
	R.deleted = Hub:DeleteConfig("main") and Hub:GetAutoload() == nil
	Hub:RenameConfig("copy", "unit")
	-- child windows with tabs
	local Win = Hub:Window({ Title = "Extra", Icon = "app-window" })
	local WA = Win:Tab({ Name = "One" })
	local WB = Win:Tab({ Name = "Two" })
	local wt = WA:Section({ Name = "WS" }):Toggle({ Name = "Window toggle", Flag = "WinToggle" })
	WB:Section({ Name = "WS2" }):Slider({ Name = "Window slider", Min = 0, Max = 10 })
	local opener = S:Button({ Name = "Open extra", Window = Win })
	R.windowClosed = not Win.IsOpen and not Win.Layer.Visible
	Win:Open()
	Win:SelectTab("Two")
	R.windowOpen = Win.IsOpen and Win.Layer.Visible and Win.Selected == WB and WB.Page.Visible and not WA.Page.Visible and Win.Strip.Visible
	R.windowFlag = flags.WinToggle == wt and wt.Section.Hub == Hub
	-- social button: invite normalization, brand colour, mark, title room, replacement
	local social = Win:SocialButton({ Discord = "https://discord.com/invite/Rift-UI" })
	task.wait(0.05)
	local socialButton = Win.Body:FindFirstChild("Social_Discord")
	R.socialUrl = social.Url == "https://discord.gg/Rift-UI" and Win:SocialButton({ Discord = "abc123" }).Url == "https://discord.gg/abc123"
	socialButton = Win.Body:FindFirstChild("Social_Discord")
	local count = 0
	for _, c in Win.Body:GetChildren() do if c.Name == "Social_Discord" then count += 1 end end
	R.socialBrand = count == 1 and socialButton.BackgroundColor3 == Color3.fromRGB(88, 101, 242) and socialButton:FindFirstChild("Mark") ~= nil
	R.socialTitle = Win._titleLabel.Size.X.Offset < -120
	R.socialRejects = not pcall(function() Win:SocialButton({ Discord = "https://evil.test/discord.gg/x" }) end) and not pcall(function() Win:SocialButton({}) end)
	Win:Close()
	task.wait(0.3)
	R.windowHidden = not Win.IsOpen and not Win.Layer.Visible and opener.Window == Win
	-- new controls
	local parentToggle = S:Toggle({ Name = "Parent feature" })
	local G = S:Group({ Name = "Parent options", DependsOn = parentToggle })
	local inner = G:Slider({ Name = "Inner slider", Flag = "GroupInner", Min = 0, Max = 5, Default = 2 })
	task.wait(0.05)
	R.groupClosed = not G:IsOpen()
	parentToggle:Set(true)
	task.wait(0.05)
	R.groupOpens = G:IsOpen() and inner.Section == G and table.find(S.Controls, inner) ~= nil
	parentToggle:Set(false, true)
	task.wait(0.05)
	R.groupFollowsSilent = not G:IsOpen()
	G:SetOpen(true)
	R.groupManual = G:IsOpen()
	local range = S:RangeSlider({ Name = "Range", Flag = "RangeFlag", Min = 0, Max = 100, Default = { 20, 80 } })
	range:Set({ 90, 10 })
	R.range = range.Value.Min == 10 and range.Value.Max == 90
	local prog = S:Progress({ Name = "Health", Max = 200, Default = 50, Segments = 4 })
	prog:Set(250)
	R.progress = prog.Value == 200
	local stat = S:Stat({ Name = "Money", Default = 1000, Delta = true })
	stat:Update(12345)
	R.stat = stat.Value == 12345 and stat.Frame:FindFirstChild("Value", true).Text == "12,345"
	local spark = S:Sparkline({ Name = "FPS", Points = 8 })
	for i = 1, 12 do spark:Push(i) end
	R.spark = #spark.Values == 8 and spark:Get() == 12
	local seg = S:Segmented({ Name = "Mode", Flag = "SegFlag", Options = { "Legit", "Rage" } })
	seg:Set("Rage")
	seg:Set("Nope")
	R.segmented = seg.Value == "Rage"
	local stepper = S:Stepper({ Name = "Count", Flag = "StepFlag", Min = 1, Max = 5, Default = 3 })
	stepper:Set(9)
	R.stepper = stepper.Value == 5
	local log = S:Console({ Name = "Log", MaxLines = 3 })
	for i = 1, 5 do log:Log("line " .. i, i == 5 and "error" or nil) end
	R.console = #log.Lines == 3 and string.find(log:Get(), "line 5") ~= nil
	log:Clear()
	R.consoleClear = #log.Lines == 0
	local pick = S:PlayerPicker({ Name = "Target", Flag = "PickFlag" })
	local P = game:GetService("Players")
	-- Players can't be created by scripts; use one from the simulated server
	local guest = P:FindFirstChild("BaconHair")
	pick:Set("BaconHair")
	R.picker = pick.Value == guest
	local okSave = Hub:SaveConfig("controls")
	range:Set({ 0, 1 })
	seg:Set("Legit")
	stepper:Set(1)
	Hub:LoadConfig("controls")
	R.newControlsSave = okSave and range.Value.Min == 10 and seg.Value == "Rage" and stepper.Value == 5 and pick.Value == guest
	guest.Parent = nil
	task.wait(0.05)
	R.pickerLeft = pick.Value == nil
	guest.Parent = P
	-- multiline input and list
	local notes = S:Input({ Name = "Notes", Flag = "NotesFlag", MultiLine = true, Lines = 5, Code = true, Default = "a\nb" })
	local box = notes.Frame:FindFirstChild("Box")
	R.multiline = box.MultiLine == true and box.TextWrapped == true and box.Size.Y.Offset > 26 and notes.Value == "a\nb"
	local single = S:Input({ Name = "Single", MaxLength = 4 })
	single:Set("line\nbreak")
	R.singleLine = single.Value == "line"
	local picked = {}
	local waypoints = S:List({ Name = "Waypoints", Columns = { "Name", "Position" }, Items = { { "Spawn", "0, 5, 0" }, "Lone" }, Removable = true, Callback = function(item, i) picked = { item, i } end })
	R.listInit = #waypoints.Items == 2 and waypoints.Items[2][1] == "Lone" and waypoints.Items[2][2] == ""
	R.listAdd = waypoints:Add({ "Shop", "10, 2, -4" }) == 3 and waypoints:Add({ "First", "0, 0, 0" }, 1) == 1 and waypoints:Get()[1][1] == "First"
	waypoints:Select(3)
	task.wait(0.05)
	local item, index = waypoints:GetSelected()
	R.listSelect = item[1] == "Lone" and index == 3 and picked[2] == 3 and picked[1][1] == "Lone"
	waypoints:Remove(1)
	local _, shifted = waypoints:GetSelected()
	R.listRemove = #waypoints.Items == 3 and shifted == 2
	waypoints:Remove(2)
	R.listDeselect = waypoints:GetSelected() == nil
	local rowsShown = 0
	for _, d in waypoints.Frame:GetDescendants() do if d.Name == "Item" then rowsShown += 1 end end
	R.listRows = rowsShown == 2
	local plain = S:List({ Name = "Plain", Items = { "a", "b", "c" }, MaxItems = 3 })
	plain:Add("d")
	R.listPlain = table.concat(plain:Get(), "") == "bcd"
	plain:Clear()
	R.listClear = #plain.Items == 0 and plain.Frame:FindFirstChild("Empty", true).Visible == true
	local tipped = S:Slider({ Name = "Tipped", Description = "Shown on hover" })
	R.tooltip = tipped.Tooltip == "Shown on hover"
	-- HUD and language
	R.assetBase = Rift.AssetBase == "https://raw.githubusercontent.com/Naymmmm/riftui/main/public/"
	for _, section in Hub.SettingsTab.Sections do
		if section.Name == "About" then
			R.powered = true
			for _, node in section.Frame:GetDescendants() do
				if node:IsA("TextLabel") and node.Text == "This script is powered by RiftUI. Licensed under MPL-2.0" then R.licenseCredit = true end
			end
			for _, control in section.Controls do
				if control.Name == "Copy GitHub link" then control:_emit() end
			end
		end
	end
	Hub:SetWatermark(true, true)
	Hub:SetKeybindList(true, true)
	task.wait(0.1)
	R.hud = Hub._watermark ~= nil and Hub._keylist ~= nil and Hub.Gui:FindFirstChild("Watermark") ~= nil
	Hub:SetWatermark(false, true)
	Hub:SetKeybindList(false, true)
	R.hudOff = Hub._watermark == nil and Hub._keylist == nil
	Hub:SetLanguage("es", true)
	task.wait()
	R.translated = Hub:T("Settings") == "Ajustes" and Hub:T("12 results") == "12 resultados" and Hub:T("INTERFACE") == "INTERFAZ"
	local found = false
	for _, d in Hub.Gui:GetDescendants() do
		if d:IsA("TextLabel") and d.Text == "Tecla de la barra" then found = true break end
	end
	R.translatedGui = found
	Hub:SetLanguage("en", true)
	local back = true
	for _, d in Hub.Gui:GetDescendants() do
		if d:IsA("TextLabel") and d.Text == "Tecla de la barra" then back = false break end
	end
	R.untranslated = back
	S:Pin()
	R.pinned = S.Pinned and Hub.PinLayer:FindFirstChild("Pin_S") ~= nil
	S:Unpin()
	-- collapsing folds rows to the header, remembers the choice, and search peeks inside
	local CS = Tab:Section({ Name = "Fold" })
	CS:Toggle({ Name = "Folded toggle" })
	CS:Toggle({ Name = "Other toggle" })
	Hub:Open(Tab)
	task.wait(0.1)
	local clip = CS._rowsClip
	-- headless runs have no layout pass, so check how the clip is sized; RiftSim checks heights
	local function shut(c) return c.AutomaticSize == Enum.AutomaticSize.None and c.Size.Y.Offset == 0 end
	local function grows(c) return c.AutomaticSize == Enum.AutomaticSize.Y end
	R.collapseStartsOpen = grows(clip)
	firesignal(CS.Head:FindFirstChild("Collapse").MouseButton1Click)
	task.wait(0.5)
	R.collapsed = CS:IsCollapsed() and shut(clip) and Hub.SetupData.Collapsed["T/Fold"] == true
	Hub:_applySearch("folded")
	R.collapsePeek = grows(clip) and CS:IsCollapsed()
	Hub:_applySearch("")
	R.collapsePeekEnds = shut(clip)
	CS:SetCollapsed(false, true)
	R.expanded = grows(clip) and Hub.SetupData.Collapsed["T/Fold"] == nil
	local fixed = Tab:Section({ Name = "Fixed", Collapsible = false })
	fixed:SetCollapsed(true)
	R.notCollapsible = not fixed:IsCollapsed() and fixed.Head:FindFirstChild("Collapse") == nil
	local starts = Tab:Section({ Name = "Starts shut", Collapsed = true })
	starts:Label("hidden")
	R.startsCollapsed = shut(starts._rowsClip)
	R.unpinned = not S.Pinned and S.Rows.Parent == S._rowsClip and S._rowsClip.Parent == S.Frame
	-- reinitialize keeps values and keeps the old references working
	t:Set(true)
	Hub:Reinitialize()
	task.wait(0.2)
	R.reinitValue = flags.TA.Value
	t:Set(false)
	R.forwarded = flags.TA.Value == false
	Hub:SetStealth(true)
	R.stealthName = Hub.Stealth and Hub.Gui.Name == "RiftUI" and Hub.DockHolder.Visible
	Hub:SetStealth(false)
	R.stealthRestored = not Hub.Stealth and Hub.Gui.Name == "RiftUI"
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
	R.setupOptions = option ~= nil and option.Parent.Parent.Parent.Parent.Parent.Parent.ClassName == "Frame"
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
frames(900)
check(R.hubId == "test-hub", "hubs keep their Id")
check(R.compatCount and R.compatCount >= 8 and #R.compatFailed == 0, "compatibility check passes on a full sUNC host (" .. table.concat(R.compatFailed or {}, "; ") .. ")")
check(R.customAssetProbeRemoved, "custom asset check uses a real PNG and cleans up on an image-only executor")
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
check(R.badgeHidden == true, "tiles show no toggle-count badge unless ToggleBadges is set")
check(R.badge == "New" and R.badgeCleared == true, "Tab:SetBadge shows and clears a badge")
check(R.autoloadStartup and R.autoloadDisable and R.autoloadEnable, "saved autoload initializes without callback errors and its independent selector follows the toggle")
check(R.autoload == true, "SetAutoload / GetAutoload round-trip")
check(R.exported == true and R.imported == true, "ExportConfig code imports under a new name")
check(R.foreignRefused == true, "ImportConfig refuses a code for another hub")
check(R.renamed == true, "RenameConfig moves the file and keeps autoload")
check(R.info == true, "ConfigInfo reads count, time and autoload")
check(R.deleted == true, "DeleteConfig clears autoload for that config")
check(R.windowClosed == true and R.windowOpen == true and R.windowHidden == true, "Window opens, switches tabs and closes")
check(R.socialUrl == true, "SocialButton normalizes Discord invite links and codes")
check(R.socialBrand == true, "SocialButton replaces itself and uses Blurple with the Discord mark")
check(R.socialTitle == true, "SocialButton takes room from the window title")
check(R.socialRejects == true, "SocialButton refuses non-invite links and missing platforms")
check(R.windowFlag == true, "window controls register flags like panel controls")
check(R.groupClosed and R.groupOpens and R.groupFollowsSilent and R.groupManual, "Group folds with its parent toggle and opens by hand")
check(R.range == true, "RangeSlider orders and clamps its two values")
check(R.progress == true, "Progress clamps to its maximum")
check(R.stat == true, "Stat formats thousands")
check(R.spark == true, "Sparkline keeps a rolling window")
check(R.segmented == true, "Segmented ignores unknown options")
check(R.stepper == true, "Stepper clamps")
check(R.console and R.consoleClear, "Console caps lines and clears")
check(R.picker and R.pickerLeft, "PlayerPicker picks by name and clears when the player leaves")
check(R.newControlsSave == true, "range, segmented, stepper and player picker save in configs")
check(R.multiline == true, "MultiLine Input is a tall wrapped box that keeps newlines")
check(R.singleLine == true, "single-line Input flattens newlines and respects MaxLength")
check(R.listInit and R.listAdd, "List normalizes items and inserts at an index")
check(R.listSelect == true, "List selection reports the item and index")
check(R.listRemove and R.listDeselect, "List removal shifts and clears the selection")
check(R.listRows == true, "List renders one row per item")
check(R.listPlain and R.listClear, "single-column List caps MaxItems and clears to its placeholder")
check(R.authCopy == true and authClipboard == "https://keys.test", "auth Get key copies the key link")
check(R.authRejected == true, "auth shows the server's rejection reason and stays open")
check(R.authAccepted and R.authSaved, "auth returns the server script and trimmed key, closes and remembers the key")
check(R.authRemembered == true, "auth checks a saved key on launch")
check(R.authRetryKeeps and R.authForgets, "auth keeps a saved key on server errors and forgets a rejected one")
check(R.authClosed == true, "closing auth returns nil, \"closed\"")
check(R.authCustom == true, "auth Request replaces the HTTP check")
check(R.authHttpsOnly == true, "auth refuses non-HTTPS URLs")
check(R.loadingCard and R.loadingProgress, "Loading card holds the dock and Open, and its progress never moves back")
check(R.hubIconLucide == true, "HubIcon shows a Lucide icon on the loading card and replaces the watermark bar")
check(R.hubIconImage == true, "HubIcon accepts an image asset number")
check(R.hubIconFallback and R.hubIconRejects, "an unknown HubIcon falls back to the initial; a non-string is refused")
check(R.loadingDone == true, "FinishLoading removes the card, raises the dock and runs the queued Open")
check(R.loadingAuto == true, "automatic loading finishes once the hub has built")
check(R.tooltip == true, "Description becomes a hover tooltip on controls that don't print it")
check(R.assetBase and R.powered and R.licenseCredit and clipboardText == "https://github.com/Naymmmm/riftui", "real AssetBase and About license credit with working GitHub copy")
check(R.hud and R.hudOff, "watermark and keybind list turn on and off")
check(R.translated == true, "translations cover exact, patterned and uppercase text")
check(R.translatedGui and R.untranslated, "SetLanguage relabels the GUI and switches back")
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
check(R.collapseStartsOpen and R.collapsed, "clicking a section header collapses it and remembers the choice")
check(R.collapsePeek and R.collapsePeekEnds, "search shows matches in a collapsed section, then folds it again")
check(R.expanded == true, "SetCollapsed(false) restores the full height and clears the saved choice")
check(R.notCollapsible and R.startsCollapsed, "Collapsible = false and Collapsed = true are honoured")
check(R.unpinned == true, "Section:Unpin returns rows to the panel")
check(R.reinitValue == true, "Reinitialize keeps flag values")
check(R.forwarded == true, "old control references forward to the rebuilt hub")
check(R.stealthName == true, "stealth asset policy leaves the toolbar usable")
check(R.stealthRestored == true, "stealth asset policy can be turned off")
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
