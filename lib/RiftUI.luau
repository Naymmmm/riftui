-- SPDX-License-Identifier: MPL-2.0
-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, obtain one at https://mozilla.org/MPL/2.0/.
--[[
	RiftUI: a dock-style hub library for sUNC executors.

	local Rift = loadstring(game:HttpGet("https://raw.githubusercontent.com/Naymmmm/riftui/main/public/Loader.luau"))()

	xpcall(function()
		local Hub = Rift:CreateHub({ Name = "Rift Hub", Subtitle = "Baseplate" })
		local Combat = Hub:Tab({ Name = "Combat", Icon = "crosshair" })
		local Aim = Combat:Section({ Name = "Aim Assist" })
		Aim:Toggle({ Name = "Enabled", Flag = "AimEnabled", Default = true, Callback = function(on) end })
	end, Rift.HandleError)

	Tabs are tiles in a slim toolbar at the bottom of the screen. Clicking a tile opens its
	panel in the middle of the screen; clicking anywhere else folds it back into the tile.
	Sections can be pinned to stay on screen while the toolbar is hidden.
]]

--@@ICONS@@

local RiftUI = {
	Version = "dev", --@@VERSION@@
	Flags = {},
	AssetBase = "https://raw.githubusercontent.com/Naymmmm/riftui/main/public/",
	Folder = "RiftUI",
	State = "Idle",
	StateHistory = {},
	Errors = {},
	Hubs = {},
	DeveloperMode = false,
}

-- Secure asset policy is shared by hubs created from this library instance.
local initialStealth = false
pcall(function()
	local env = typeof(getgenv) == "function" and getgenv() or _G
	initialStealth = env.RIFTUI_SECURE == true
end)
local bootStealth = initialStealth
local secureHubs = setmetatable({}, { __mode = "k" })
local localAssetIds = {}
local secureFontFamily = nil
local secureFontState = "idle"
local watchedAssets = setmetatable({}, { __mode = "k" })
local function secureAssets()
	return bootStealth or next(secureHubs) ~= nil
end
local nativeWarn = warn
local function warn(...)
	if not secureAssets() then nativeWarn(...) end
end
local function localImage(value)
	return value == "" or (type(value) == "string" and (localAssetIds[value] or string.match(value, "^rbxasset://") or string.match(value, "^rbxtemp://")))
end
local function secureProperty(prop, value)
	if not secureAssets() then return value end
	if (prop == "Image" or prop == "HoverImage" or prop == "PressedImage") and not localImage(value) then return "" end
	if prop == "FontFace" and typeof(value) == "Font" then
		local family = value.Family
		if type(family) == "string" and not localAssetIds[family] and (string.match(family, "^rbxassetid://") or string.match(family, "^https?://") or (secureFontFamily and family == Font.fromEnum(Enum.Font.BuilderSans).Family)) then
			local fallback = Font.fromEnum(Enum.Font.BuilderSans)
			return Font.new(secureFontFamily or fallback.Family, value.Weight, value.Style)
		end
	end
	return value
end
local function watchAsset(inst)
	if watchedAssets[inst] then return end
	local props = {}
	if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then table.insert(props, "Image") end
	if inst:IsA("ImageButton") then table.insert(props, "HoverImage") table.insert(props, "PressedImage") end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then table.insert(props, "FontFace") end
	if #props == 0 then return end
	watchedAssets[inst] = true
	for _, prop in props do
		local function apply()
			local old = inst[prop]
			local value = secureProperty(prop, old)
			if value ~= old then inst[prop] = value end
		end
		inst:GetPropertyChangedSignal(prop):Connect(apply)
		apply()
	end
end

---------------------------------------------------------------- services
local function service(name)
	local s = game:GetService(name)
	if cloneref then
		s = cloneref(s)
	end
	return s
end
local Players = service("Players")
local TweenService = service("TweenService")
local UserInputService = service("UserInputService")
local HttpService = service("HttpService")
local RunService = service("RunService")
local CoreGui = service("CoreGui")
local GuiService = service("GuiService")

local hasFS = typeof(writefile) == "function" and typeof(readfile) == "function" and typeof(isfile) == "function"
local hasAssets = hasFS and typeof(getcustomasset) == "function"
local clock = os.clock()

local function topInset(): number
	local ok, inset = pcall(function()
		return GuiService:GetGuiInset()
	end)
	return ok and inset and inset.Y or 58
end

local function viewport(): Vector2
	local cam = workspace.CurrentCamera
	return cam and cam.ViewportSize or Vector2.new(1280, 720)
end

---------------------------------------------------------------- state machine & error log
local listeners = {}

local function notifyListeners()
	for _, fn in listeners do
		task.spawn(fn)
	end
end

local function setState(state: string, detail: string?)
	if RiftUI.State == state and detail == nil then
		return
	end
	RiftUI.State = state
	table.insert(RiftUI.StateHistory, { State = state, Detail = detail, Time = os.clock() - clock })
	if #RiftUI.StateHistory > 30 then
		table.remove(RiftUI.StateHistory, 1)
	end
	notifyListeners()
end

local function recordError(message: string, trace: string?, source: string?)
	table.insert(RiftUI.Errors, { Message = message, Trace = trace, Source = source or "hub", Time = os.clock() - clock })
	if #RiftUI.Errors > 50 then
		table.remove(RiftUI.Errors, 1)
	end
	notifyListeners()
end

function RiftUI:OnStateChanged(fn)
	table.insert(listeners, fn)
	return {
		Disconnect = function()
			local i = table.find(listeners, fn)
			if i then
				table.remove(listeners, i)
			end
		end,
	}
end

---------------------------------------------------------------- theme
local rgb = Color3.fromRGB
local DefaultTheme = {
	Panel = rgb(15, 15, 17),
	PanelStroke = rgb(42, 42, 48),
	Highlight = rgb(255, 255, 255), -- 1px top sheen on floating surfaces
	Tile = rgb(23, 23, 26),
	TileHover = rgb(30, 30, 34),
	TileActive = rgb(38, 38, 43),
	TileStroke = rgb(34, 34, 39),
	TileActiveStroke = rgb(52, 52, 59),
	Section = rgb(20, 20, 23),
	SectionStroke = rgb(34, 34, 39),
	Divider = rgb(29, 29, 33),
	Text = rgb(237, 237, 239),
	SubText = rgb(142, 142, 150),
	Muted = rgb(95, 95, 103),
	Field = rgb(10, 10, 12),
	FieldStroke = rgb(42, 42, 48),
	Track = rgb(42, 42, 48),
	Knob = rgb(110, 110, 118),
	Accent = rgb(242, 242, 243),
	AccentText = rgb(15, 15, 17),
	Danger = rgb(255, 112, 112),
	Success = rgb(120, 220, 150),
	Warning = rgb(242, 194, 79),
	Scrim = rgb(0, 0, 0),
}

local FONT_ID = "rbxassetid://12187365364" -- Inter
local function inter(weight)
	local family = secureAssets() and (secureFontFamily or Font.fromEnum(Enum.Font.BuilderSans).Family) or FONT_ID
	return Font.new(family, weight or Enum.FontWeight.Regular)
end
local MONO = Font.fromName("RobotoMono", Enum.FontWeight.Medium)

local FAST = TweenInfo.new(0.14, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local SOFT = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RISE = TweenInfo.new(0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local FOLD = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local THEME_FADE = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SETTLE = TweenInfo.new(0.26, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

---------------------------------------------------------------- helpers
local themeBindings = setmetatable({}, { __mode = "k" })
local function themeColor(theme, key)
	return { _theme = theme, _key = key }
end
local function setThemed(inst, prop, value)
	value = secureProperty(prop, value)
	if type(value) == "table" and rawget(value, "_theme") then
		local bindings = themeBindings[inst] or {}
		themeBindings[inst] = bindings
		bindings[prop] = value
		inst[prop] = value._theme[value._key]
	else
		inst[prop] = value
	end
end

local function create(className: string, props: { [string]: any }?, children: { Instance }?)
	local inst = Instance.new(className)
	local parent
	for k, v in props or {} do
		if k == "Parent" then
			parent = v
		else
			setThemed(inst, k, v)
		end
	end
	for _, c in children or {} do
		c.Parent = inst
	end
	watchAsset(inst)
	if parent then
		inst.Parent = parent
	end
	return inst
end

-- a hairline of light along the top edge, inset from the corners, so dark surfaces read as objects
local function sheen(parent: Instance, inset: number, theme, zIndex: number?)
	return create("Frame", {
		Name = "Sheen",
		BackgroundColor3 = themeColor(theme, "Highlight"),
		BackgroundTransparency = 0.93,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(inset, 0),
		Size = UDim2.new(1, -inset * 2, 0, 1),
		ZIndex = zIndex or 1,
		Parent = parent,
	})
end

local function corner(r: number)
	return create("UICorner", { CornerRadius = UDim.new(0, r) })
end

local function stroke(color, thickness: number?, transparency: number?)
	return create("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function padding(t: number, r: number?, b: number?, l: number?)
	return create("UIPadding", {
		PaddingTop = UDim.new(0, t),
		PaddingRight = UDim.new(0, r or t),
		PaddingBottom = UDim.new(0, b or t),
		PaddingLeft = UDim.new(0, l or r or t),
	})
end

local function list(dir, pad: number, halign, valign)
	return create("UIListLayout", {
		FillDirection = dir or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, pad or 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = halign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = valign or Enum.VerticalAlignment.Top,
	})
end

local function text(props)
	local t = create("TextLabel", {
		BackgroundTransparency = 1,
		FontFace = props.FontFace or inter(),
		TextSize = props.TextSize or 13,
		TextColor3 = props.TextColor3 or DefaultTheme.Text,
		TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left,
		TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Center,
		Text = props.Text or "",
		Size = props.Size or UDim2.new(1, 0, 0, 16),
		AutomaticSize = props.AutomaticSize or Enum.AutomaticSize.None,
		TextWrapped = props.TextWrapped or false,
		LineHeight = props.LineHeight or (props.TextWrapped and 1.2 or 1),
		TextTruncate = props.TextTruncate or Enum.TextTruncate.None,
		RichText = props.RichText or false,
		LayoutOrder = props.LayoutOrder or 0,
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		TextTransparency = props.TextTransparency or 0,
		ZIndex = props.ZIndex or 1,
		Name = props.Name or "Label",
	})
	if props.Parent then
		t.Parent = props.Parent
	end
	return t
end

local function tween(inst, info, goals)
	local resolved = {}
	for prop, value in goals do
		if type(value) == "table" and rawget(value, "_theme") then
			local bindings = themeBindings[inst] or {}
			themeBindings[inst] = bindings
			bindings[prop] = value
			resolved[prop] = value._theme[value._key]
		else
			resolved[prop] = value
		end
	end
	local tw = TweenService:Create(inst, info, resolved)
	tw:Play()
	return tw
end

local function within(inst: GuiObject?, pos: Vector2): boolean
	if not inst or not inst.Parent or not inst.Visible then
		return false
	end
	local p, s = inst.AbsolutePosition, inst.AbsoluteSize
	return pos.X >= p.X and pos.X <= p.X + s.X and pos.Y >= p.Y and pos.Y <= p.Y + s.Y
end

local function isPointer(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function isMove(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch
end

local function round(n: number, step: number): number
	local r = math.floor(n / step + 0.5) * step
	return tonumber(string.format("%.6f", r)) :: number
end

local function formatNumber(n: number, step: number): string
	if step >= 1 then
		return string.format("%d", math.floor(n + 0.5))
	end
	local decimals = math.clamp(math.ceil(-math.log10(step)), 1, 4)
	return string.format("%." .. decimals .. "f", n)
end

local function randomName(): string
	return string.format("%08x", math.random(0, 0x7fffffff))
end

local KEY_NAMES = {
	RightShift = "RShift",
	LeftShift = "LShift",
	RightControl = "RCtrl",
	LeftControl = "LCtrl",
	RightAlt = "RAlt",
	LeftAlt = "LAlt",
	Return = "Enter",
	Backspace = "Bksp",
	Escape = "Esc",
	PageUp = "PgUp",
	PageDown = "PgDn",
	Insert = "Ins",
	Delete = "Del",
	CapsLock = "Caps",
	Backquote = "`",
	Zero = "0",
	One = "1",
	Two = "2",
	Three = "3",
	Four = "4",
	Five = "5",
	Six = "6",
	Seven = "7",
	Eight = "8",
	Nine = "9",
	MouseButton1 = "MB1",
	MouseButton2 = "MB2",
	MouseButton3 = "MB3",
}
local function keyName(key): string
	if key == nil then
		return "None"
	end
	return KEY_NAMES[key.Name] or key.Name
end

---------------------------------------------------------------- assets (icons, shadow)
---------------------------------------------------------------- theme presets
-- Each preset overrides DefaultTheme; a hub's own Theme table overrides the preset.
local THEMES = {
	{ Name = "Graphite", Description = "Neutral near-black", Colors = {} },
	{
		Name = "Ink",
		Description = "True black, highest contrast",
		Colors = {
			Panel = rgb(6, 6, 7),
			PanelStroke = rgb(36, 36, 40),
			Tile = rgb(16, 16, 18),
			TileHover = rgb(23, 23, 26),
			TileActive = rgb(31, 31, 35),
			TileStroke = rgb(27, 27, 31),
			TileActiveStroke = rgb(46, 46, 52),
			Divider = rgb(23, 23, 26),
			Field = rgb(0, 0, 0),
			FieldStroke = rgb(36, 36, 40),
			Track = rgb(36, 36, 40),
			AccentText = rgb(6, 6, 7),
		},
	},
	{
		Name = "Slate",
		Description = "Cool blue-grey, blue accent",
		Colors = {
			Panel = rgb(13, 17, 23),
			PanelStroke = rgb(40, 48, 60),
			Tile = rgb(22, 27, 34),
			TileHover = rgb(28, 34, 43),
			TileActive = rgb(36, 44, 56),
			TileStroke = rgb(33, 40, 50),
			TileActiveStroke = rgb(52, 62, 78),
			Divider = rgb(30, 36, 46),
			Text = rgb(230, 237, 243),
			SubText = rgb(139, 148, 158),
			Muted = rgb(98, 108, 120),
			Field = rgb(8, 11, 15),
			FieldStroke = rgb(40, 48, 60),
			Track = rgb(40, 48, 60),
			Knob = rgb(110, 120, 135),
			Accent = rgb(127, 178, 255),
			AccentText = rgb(8, 14, 24),
		},
	},
	{
		Name = "Ember",
		Description = "Warm charcoal, orange accent",
		Colors = {
			Panel = rgb(17, 15, 14),
			PanelStroke = rgb(50, 43, 39),
			Tile = rgb(27, 24, 22),
			TileHover = rgb(35, 31, 28),
			TileActive = rgb(44, 39, 35),
			TileStroke = rgb(40, 35, 32),
			TileActiveStroke = rgb(62, 54, 48),
			Divider = rgb(34, 30, 27),
			Text = rgb(240, 235, 230),
			SubText = rgb(160, 150, 140),
			Muted = rgb(110, 101, 94),
			Field = rgb(11, 10, 9),
			FieldStroke = rgb(50, 43, 39),
			Track = rgb(50, 43, 39),
			Knob = rgb(125, 115, 106),
			Accent = rgb(255, 154, 90),
			AccentText = rgb(28, 16, 8),
		},
	},
}
RiftUI.Themes = THEMES

local function buildTheme(name: string?, overrides)
	local theme = table.clone(DefaultTheme)
	for _, preset in THEMES do
		if preset.Name == name then
			for k, v in preset.Colors do
				theme[k] = v
			end
		end
	end
	for k, v in overrides or {} do
		theme[k] = v
	end
	return theme
end

---------------------------------------------------------------- per-hub files: RiftUI/<Id>/...
local function hubId(options): string
	local raw = options.Id or options.Name or "RiftHub"
	local id = string.lower((string.gsub(string.gsub(raw, "%s+", "-"), "[^%w%-_]", "")))
	return id ~= "" and id or "hub"
end

local function readSetup(id: string)
	if not hasFS then
		return nil
	end
	local ok, data = pcall(function()
		local path = RiftUI.Folder .. "/" .. id .. "/setup.json"
		if not isfile(path) then
			return nil
		end
		return HttpService:JSONDecode(readfile(path))
	end)
	return ok and type(data) == "table" and data or nil
end

local Assets = { sheets = {}, failed = false, names = nil, shadow = nil }

local function ensureFolder(path: string)
	if typeof(isfolder) == "function" and typeof(makefolder) == "function" and not isfolder(path) then
		makefolder(path)
	end
end

-- Download a file into the executor workspace once, then hand back its content id.
local function customAsset(fileName: string, remote: string): string?
	if not hasAssets or Assets.failed then
		return nil
	end
	local folder = RiftUI.AssetCacheFolder or (RiftUI.Folder .. "/assets")
	local path = folder .. "/" .. fileName
	local ok, result = pcall(function()
		if not isfile(path) then
			ensureFolder(RiftUI.Folder)
			ensureFolder(RiftUI.Folder .. "/assets")
			ensureFolder(folder)
			local body = game:HttpGet(RiftUI.AssetBase .. remote)
			if #body < 64 then
				error("asset download returned " .. #body .. " bytes")
			end
			writefile(path, body)
		end
		return getcustomasset(path)
	end)
	if not ok then
		Assets.failed = true
		recordError("couldn't load " .. remote .. ": " .. tostring(result), nil, "assets")
		warn("[RiftUI] couldn't load " .. remote .. ": " .. tostring(result) .. " (falling back to text icons)")
		return nil
	end
	if type(result) == "string" then localAssetIds[result] = true end
	return result
end

-- Family JSON is rebuilt from this session's content IDs; cached IDs may expire.
function RiftUI:GetSecureFontStatus()
	return secureFontState, secureFontFamily
end

function RiftUI:LoadSecureFont()
	if secureFontState == "loading" or secureFontState == "ready" then return secureFontState == "ready" end
	secureFontState = "loading"
	local ok, result = pcall(function()
		assert(hasAssets, "local assets unavailable")
		local folder = (self.AssetCacheFolder or (self.Folder .. "/assets")) .. "/fonts/inter-4.1"
		local prefix = ""
		for part in string.gmatch(folder, "[^/]+") do
			prefix = prefix == "" and part or prefix .. "/" .. part
			ensureFolder(prefix)
		end
		local faces = {}
		for _, face in { { "Regular", 400 }, { "Medium", 500 }, { "SemiBold", 600 }, { "Bold", 700 } } do
			local file = "Inter-" .. face[1] .. ".ttf"
			local path = folder .. "/" .. file
			local function valid(bytes)
				return type(bytes) == "string" and #bytes > 1024 and #bytes < 2097152 and (string.sub(bytes, 1, 4) == "\0\1\0\0" or string.sub(bytes, 1, 4) == "OTTO")
			end
			local bytes = isfile(path) and readfile(path) or nil
			if not valid(bytes) then
				bytes = game:HttpGet(self.AssetBase .. "assets/fonts/inter-4.1/" .. file)
				assert(valid(bytes), "invalid font download")
				writefile(path, bytes)
			end
			local asset = getcustomasset(path)
			assert(type(asset) == "string" and asset ~= "", "font asset registration failed")
			table.insert(faces, { name = face[1], weight = face[2], style = "normal", assetId = asset })
		end
		local json = HttpService:JSONEncode({ name = "Inter", faces = faces })
		local hash = 5381
		for i = 1, #json do hash = (hash * 33 + string.byte(json, i)) % 4294967296 end
		local path = folder .. "/Inter-" .. string.format("%08x", hash) .. ".font"
		writefile(path, json)
		local family = getcustomasset(path)
		assert(type(family) == "string" and family ~= "", "font family registration failed")
		local info = service("TextService"):GetFamilyInfoAsync(family)
		assert(type(info) == "table" and type(info.Faces) == "table" and #info.Faces >= 4, "font family could not be loaded")
		Font.new(family, Enum.FontWeight.Regular)
		return family
	end)
	if not ok then
		secureFontState = "failed"
		recordError("local Inter font unavailable: " .. tostring(result), nil, "fonts")
		return false
	end
	secureFontFamily = result
	localAssetIds[result] = true
	secureFontState = "ready"
	if secureAssets() then
		local fallback = Font.fromEnum(Enum.Font.BuilderSans).Family
		for _, hub in self.Hubs do
			if not hub._destroyed then
				for _, inst in hub.Gui:GetDescendants() do
					if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
						local font = inst.FontFace
						if font.Family == fallback or font.Family == FONT_ID then inst.FontFace = Font.new(result, font.Weight, font.Style) end
					end
				end
			end
		end
	end
	return true
end

local function queueSecureFont()
	if secureAssets() and secureFontState == "idle" then task.defer(function() RiftUI:LoadSecureFont() end) end
end

local function iconIndex(name: string): number?
	if not Assets.names then
		Assets.names = {}
		local i = 0
		for n in string.gmatch(ICON_INDEX.Names, "[^,]+") do
			Assets.names[n] = i
			i += 1
		end
	end
	return Assets.names[name]
end

-- Returns { Image, ImageRectOffset, ImageRectSize } for a Lucide icon name, or nil.
function RiftUI:GetIcon(name: string?)
	if type(name) ~= "string" then
		return nil
	end
	if string.find(name, "^rbxasset") or string.find(name, "^rbxtemp://") then
		if secureAssets() and not localImage(name) then return nil end
		return { Image = name, ImageRectOffset = Vector2.zero, ImageRectSize = Vector2.zero }
	end
	local idx = iconIndex(name)
	if not idx then
		warn("[RiftUI] unknown Lucide icon '" .. name .. "'")
		return nil
	end
	local sheet = idx // ICON_INDEX.PerSheet
	local image = Assets.sheets[sheet]
	if not image then
		image = customAsset(string.format("lucide-%s-%d.png", ICON_INDEX.Version, sheet), "assets/lucide/sheet-" .. sheet .. ".png")
		if not image then
			return nil
		end
		Assets.sheets[sheet] = image
	end
	local cell = idx % ICON_INDEX.PerSheet
	local c, inset = ICON_INDEX.Cell, ICON_INDEX.Inset
	return {
		Image = image,
		ImageRectOffset = Vector2.new((cell % ICON_INDEX.PerRow) * c + inset, (cell // ICON_INDEX.PerRow) * c + inset),
		ImageRectSize = Vector2.new(c - inset * 2, c - inset * 2),
	}
end

local function iconLabel(name: string?, size: number, color: Color3, props)
	local data = RiftUI:GetIcon(name)
	if not data then
		return nil
	end
	local img = create("ImageLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		Image = data.Image,
		ImageRectOffset = data.ImageRectOffset,
		ImageRectSize = data.ImageRectSize,
		ImageColor3 = color,
	})
	for k, v in props or {} do
		img[k] = v
	end
	return img
end

-- A hub's own mark: a Lucide icon name, or an image (rbxassetid://…, an asset number, or a
-- getcustomasset id). Images keep their colours and draw a little larger than line icons.
-- Nil when there's nothing to draw, so callers fall back to the name's initial.
local function hubMark(icon, size: number, theme, props)
	if type(icon) == "string" and icon ~= "" then
		local lucide = iconLabel(icon, size, theme.Text, props)
		if lucide then return lucide end
	end
	local image
	if type(icon) == "number" or (type(icon) == "string" and string.match(icon, "^%d+$")) then
		image = "rbxassetid://" .. tostring(math.floor(tonumber(icon) or 0))
	elseif type(icon) == "string" and (string.match(icon, "^rbxassetid://%d+$") or string.match(icon, "^rbxasset://") or localAssetIds[icon]) then
		image = icon
	end
	-- stealth mode refuses remote images, so the initial stands in
	if not image or (secureAssets() and not localImage(image)) then return nil end
	local s = math.floor(size * 1.375 + 0.5)
	local img = create("ImageLabel", { Name = "Icon", BackgroundTransparency = 1, Image = image, ScaleType = Enum.ScaleType.Fit, Size = UDim2.fromOffset(s, s) }, { corner(math.floor(s / 4)) })
	for k, v in props or {} do
		img[k] = v
	end
	return img
end

-- 9-slice soft shadow sized to its parent plus `spread` on every side
local function shadow(parent: Instance, spread: number?, zIndex: number?, offsetY: number?)
	if Assets.shadow == nil then
		Assets.shadow = customAsset("shadow-3.png", "assets/shadow.png") or false
	end
	if not Assets.shadow then
		return nil
	end
	spread = spread or 20
	return create("ImageLabel", {
		Name = "Shadow",
		BackgroundTransparency = 1,
		Image = Assets.shadow,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(39, 39, 41, 41),
		SliceScale = spread / 20,
		ImageTransparency = 0.1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, offsetY or 4),
		Size = UDim2.new(1, spread * 2, 1, spread * 2),
		ZIndex = zIndex or 0,
		Parent = parent,
	})
end

local function guiParent()
	if typeof(gethui) == "function" then
		local ok, hui = pcall(gethui)
		if ok and hui then
			return hui
		end
	end
	local ok = pcall(function()
		return CoreGui:GetChildren()
	end)
	if ok then
		return CoreGui
	end
	return Players.LocalPlayer:WaitForChild("PlayerGui")
end

---------------------------------------------------------------- dialogs (prompts, the failure card)
-- A centred card over a scrim. Buttons: { Text, Primary?, Danger?, Callback?, KeepOpen? }
local function dialog(gui: Instance, theme, o)
	local layer = create("Frame", {
		Name = "Dialog",
		BackgroundColor3 = themeColor(theme, "Scrim"),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Active = true,
		ZIndex = 100,
		Parent = gui,
	})
	local holder = create("Frame", {
		Name = "Holder",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 12),
		Size = UDim2.new(1, -24, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 61,
		Parent = layer,
	})
	create("UISizeConstraint", { MaxSize = Vector2.new(o.Width or 360, 100000), Parent = holder })
	shadow(holder, 30, 61, 8)
	local card = create("CanvasGroup", {
		Name = "Card",
		BackgroundColor3 = themeColor(theme, "Panel"),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		GroupTransparency = 1,
		ZIndex = 62,
		Parent = holder,
	}, { corner(14), padding(18, 18, 16, 18), list(Enum.FillDirection.Vertical, 10) })
	local outline = create("Frame", { Name = "Outline", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 63, Parent = holder }, {
		corner(14),
		stroke(themeColor(theme, "PanelStroke")),
	})
	local head = create("Frame", { Name = "Head", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), ZIndex = 62, Parent = card }, {
		list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
	})
	local icon = iconLabel(o.Icon, 18, o.Tone or theme.Text, { ZIndex = 63 })
	if icon then
		icon.Parent = head
	end
	text({ Parent = head, Text = o.Title or "", FontFace = inter(Enum.FontWeight.SemiBold), TextSize = 16, Size = UDim2.new(1, -30, 0, 22), LayoutOrder = 2, ZIndex = 63 })
	if o.Content and o.Content ~= "" then
		text({
			Parent = card,
			Text = o.Content,
			TextSize = 13,
			TextColor3 = themeColor(theme, "SubText"),
			TextWrapped = true,
			LineHeight = 1.3,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 2,
			ZIndex = 63,
		})
	end
	local body = create("Frame", { Name = "Body", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, ZIndex = 62, Parent = card }, {
		list(Enum.FillDirection.Vertical, 8),
	})
	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		tween(layer, FOLD, { BackgroundTransparency = 1 })
		tween(holder, FOLD, { Position = UDim2.new(0.5, 0, 0.5, 8) })
		outline.Visible = false
		local tw = tween(card, FOLD, { GroupTransparency = 1 })
		tw.Completed:Connect(function()
			layer:Destroy()
		end)
	end
	local row = create("Frame", { Name = "Buttons", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 32), LayoutOrder = 4, ZIndex = 62, Parent = card }, {
		list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center),
	})
	for i, b in o.Buttons or { { Text = "OK", Primary = true } } do
		local btn = create("TextButton", {
			Name = "Button",
			BackgroundColor3 = b.Primary and themeColor(theme, "Accent") or themeColor(theme, "Tile"),
			Size = UDim2.fromOffset(0, 32),
			AutomaticSize = Enum.AutomaticSize.X,
			Text = b.Text,
			FontFace = inter(Enum.FontWeight.Medium),
			TextSize = 13,
			TextColor3 = b.Primary and themeColor(theme, "AccentText") or (b.Danger and themeColor(theme, "Danger") or themeColor(theme, "Text")),
			AutoButtonColor = false,
			LayoutOrder = i,
			ZIndex = 63,
			Parent = row,
		}, { corner(8), padding(0, 14) })
		if not b.Primary then
			stroke(themeColor(theme, "FieldStroke")).Parent = btn
		end
		btn.MouseEnter:Connect(function()
			tween(btn, FAST, { BackgroundColor3 = b.Primary and rgb(255, 255, 255) or theme.TileHover })
		end)
		btn.MouseLeave:Connect(function()
			tween(btn, FAST, { BackgroundColor3 = b.Primary and themeColor(theme, "Accent") or themeColor(theme, "Tile") })
		end)
		btn.MouseButton1Click:Connect(function()
			if not b.KeepOpen then
				close()
			end
			if b.Callback then
				task.spawn(b.Callback, btn)
			end
		end)
	end
	tween(layer, SOFT, { BackgroundTransparency = 0.55 })
	-- Keep the modal anchored to its available viewport.
	tween(card, SOFT, { GroupTransparency = 0 })
	return { Layer = layer, Body = body, Close = close }
end

---------------------------------------------------------------- the error handler
local failureGui

local function showFailure(message: string, trace: string?)
	local hub = RiftUI.Hubs[#RiftUI.Hubs]
	local gui = hub and hub.Gui
	if not gui or not gui.Parent then
		if failureGui and failureGui.Parent then
			failureGui:Destroy()
		end
		failureGui = create("ScreenGui", {
			Name = "RiftUI_Failure",
			IgnoreGuiInset = true,
			ResetOnSpawn = false,
			DisplayOrder = 200,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			Parent = guiParent(),
		})
		gui = failureGui
	end
	local theme = hub and hub.Theme or DefaultTheme
	local short = string.gsub(message, "^%[string \"(.-)\"%]", "%1")
	local buttons = {
		{
			Text = "Copy error",
			KeepOpen = true,
			Callback = function(btn)
				if typeof(setclipboard) == "function" then
					setclipboard(message .. "\n" .. (trace or ""))
					btn.Text = "Copied"
				else
					btn.Text = "No clipboard"
				end
			end,
		},
	}
	if hub and #hub._recipe > 0 then
		table.insert(buttons, {
			Text = "Reinitialize",
			Callback = function()
				hub:Reinitialize()
			end,
		})
	end
	table.insert(buttons, {
		Text = "Dismiss",
		Primary = true,
		Callback = function()
			task.delay(0.3, function()
				if failureGui then
					failureGui:Destroy()
					failureGui = nil
				end
			end)
		end,
	})
	local d = dialog(gui, theme, {
		Icon = "triangle-alert",
		Tone = theme.Danger,
		Title = "Hub failed to load",
		Content = hub and "Part of the hub was built before the error; what loaded still works." or "The script stopped before the hub was created.",
		Width = 420,
		Buttons = buttons,
	})
	local box = create("Frame", {
		Name = "Error",
		BackgroundColor3 = themeColor(theme, "Field"),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ClipsDescendants = true,
		ZIndex = 63,
		Parent = d.Body,
	}, { corner(8), stroke(themeColor(theme, "FieldStroke")), padding(10, 12), create("UISizeConstraint", { MaxSize = Vector2.new(math.huge, 160) }) })
	text({
		Parent = box,
		Text = (RiftUI.DeveloperMode and trace) and (short .. "\n" .. trace) or short,
		FontFace = MONO,
		TextSize = 12,
		TextColor3 = themeColor(theme, "Text"),
		TextWrapped = true,
		LineHeight = 1.25,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 64,
	})
	text({
		Parent = d.Body,
		Text = RiftUI.DeveloperMode and "Developer Mode keeps every error under Developer › Errors." or ("RiftUI " .. RiftUI.Version),
		TextSize = 11,
		TextColor3 = themeColor(theme, "Muted"),
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 14),
		ZIndex = 63,
	})
end

-- Pass to xpcall: xpcall(function() ... end, Rift.HandleError)
function RiftUI.HandleError(err: any): string
	local message = tostring(err)
	local trace = debug.traceback("", 2)
	recordError(message, trace, "load")
	setState("Failed", message)
	warn("[RiftUI] hub failed to load: " .. message)
	-- the handler runs on the failing stack; build the card once it has unwound
	task.defer(showFailure, message, trace)
	return message
end

---------------------------------------------------------------- Hub
local Hub = {}
Hub.__index = Hub

local function devFile()
	return RiftUI.Folder .. "/developer.txt"
end
if hasFS then
	local ok, on = pcall(function()
		return isfile(devFile()) and readfile(devFile()) == "1"
	end)
	RiftUI.DeveloperMode = ok and on or false
end

function RiftUI:CreateHub(options)
	options = options or {}
	setState("Booting", options.Name)
	local id = hubId(options)
	-- running the script again replaces the previous copy of this hub instead of stacking a second one
	local registry = {}
	pcall(function()
		local genv = typeof(getgenv) == "function" and getgenv() or _G
		genv.__RiftUIHubs = genv.__RiftUIHubs or {}
		registry = genv.__RiftUIHubs
	end)
	local previous = registry[id]
	if previous and previous.Destroy and not previous._destroyed then
		pcall(previous.Destroy, previous)
	end
	local saved = readSetup(id)
	local themeName = (saved and saved.Theme) or options.ThemeName or "Graphite"
	local overrides = table.clone(options.Theme or {})
	if saved and type(saved.Studio) == "table" then
		for k, hex in saved.Studio.Colors or {} do
			local ok, col = pcall(Color3.fromHex, hex)
			if ok then
				overrides[k] = col
			end
		end
	end
	local theme = buildTheme(themeName, overrides)
	local toggleKey = options.ToggleKey or Enum.KeyCode.RightShift
	if saved and saved.ToggleKey then
		local ok, key = pcall(function()
			return Enum.KeyCode[saved.ToggleKey]
		end)
		if ok and key then
			toggleKey = key
		end
	end
	local self = setmetatable({
		Options = options,
		Id = id,
		Name = options.Name or "Rift Hub",
		Subtitle = options.Subtitle or "",
		Icon = options.HubIcon,
		Theme = theme,
		ThemeName = themeName,
		ToggleKey = toggleKey,
		CommandKey = (saved and saved.CommandKey and Enum.KeyCode[saved.CommandKey]) or options.CommandKey or Enum.KeyCode.F2,
		SetupData = saved,
		Flags = RiftUI.Flags,
		Tabs = {},
		Pins = {},
		Stealth = false,
		_conns = {},
		_recipe = {},
		_popup = nil,
		_open = nil,
		_visible = true,
		_scale = 1,
	}, Hub)

	assert(options.Stealth == nil or type(options.Stealth) == "boolean", "Stealth must be a boolean")
	assert(options.HubIcon == nil or type(options.HubIcon) == "string" or type(options.HubIcon) == "number", "HubIcon must be a Lucide icon name or an image asset ID")
	local stealth = options.Stealth
	if stealth == nil then stealth = initialStealth end
	self._stealthLocked = options.Stealth ~= nil or initialStealth
	self.Stealth = stealth == true
	if self.Stealth then secureHubs[self] = true end
	bootStealth = false
	self:_initRequirements(options.Requirements)
	local gui = create("ScreenGui", {
		Name = "RiftUI",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 100,
	})
	if typeof(protectgui) == "function" then
		pcall(protectgui, gui)
	end
	gui.Parent = guiParent()
	self.Gui = gui
	self:_connect(gui.DescendantAdded, watchAsset)
	self.UIScale = create("UIScale", { Scale = 1, Parent = gui })
	self:_connect(gui:GetPropertyChangedSignal("AbsoluteSize"), function()
		if self._open then self:_fitPanel(self._open, false) end
	end)

	-- Dock: a slim strip of 40px tiles
	self.DockHolder = create("Frame", {
		Name = "DockHolder",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -self:_dockBottom()),
		Size = UDim2.fromOffset(0, 50),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = gui,
	})
	shadow(self.DockHolder, 18, 0, 5)
	self.Dock = create("Frame", {
		Name = "Dock",
		BackgroundColor3 = themeColor(theme, "Panel"),
		Size = UDim2.fromOffset(0, 50),
		AutomaticSize = Enum.AutomaticSize.X,
		ZIndex = 2,
		Parent = self.DockHolder,
	}, {
		corner(12),
		stroke(themeColor(theme, "PanelStroke")),
		padding(5),
		list(Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
	})
	sheen(self.DockHolder, 12, theme, 3)

	-- Tooltip pill under the dock
	self.Tooltip = create("Frame", {
		Name = "Tooltip",
		BackgroundColor3 = themeColor(theme, "Panel"),
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	}, { corner(8), stroke(themeColor(theme, "PanelStroke")), padding(0, 10) })
	self.TooltipText = text({
		Parent = self.Tooltip,
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		TextSize = 12,
		FontFace = inter(Enum.FontWeight.Medium),
		TextColor3 = themeColor(theme, "Text"),
		ZIndex = 21,
	})

	-- Panel: a CanvasGroup so the whole sheet fades as one
	self.PanelHolder = create("Frame", {
		Name = "PanelHolder",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(470, 300),
		Visible = false,
		ZIndex = 5,
		Parent = gui,
	})
	self.PanelShadow = shadow(self.PanelHolder, 34, 4, 10)
	self.Panel = create("CanvasGroup", {
		Name = "Panel",
		BackgroundColor3 = themeColor(theme, "Panel"),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		Parent = self.PanelHolder,
	}, { corner(14) })
	self.PanelRise = create("UIScale", { Name = "Rise", Scale = 1, Parent = self.Panel })
	self.PanelOutline = create("Frame", {
		Name = "Outline",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 6,
		Parent = self.PanelHolder,
	}, { corner(14) })
	self.PanelOutlineStroke = stroke(themeColor(theme, "PanelStroke"), 1, 1)
	self.PanelOutlineStroke.Parent = self.PanelOutline
	sheen(self.Panel, 16, theme, 7)
	self:_buildHeader()
	self.Pages = create("Frame", {
		Name = "Pages",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 57),
		Size = UDim2.new(1, 0, 1, -57),
		ClipsDescendants = true,
		Parent = self.Panel,
	})

	-- Floating layers
	self.PinLayer = create("Frame", { Name = "Pins", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 8, Parent = gui })
	self.Toasts = create("Frame", {
		Name = "Notifications",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, topInset() + 6),
		Size = UDim2.new(0, 300, 1, -topInset() - 20),
		ZIndex = 30,
		Parent = gui,
	}, { list(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Right) })
	self.Overlay = create("Frame", { Name = "Overlay", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 90, Parent = gui })

	-- A persistent touch control can hide the toolbar and bring it back.
	self.Restore = create("TextButton", {
		Name = "ToggleToolbar",
		BackgroundColor3 = themeColor(theme, "Panel"),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(128, 44),
		Text = "Hide toolbar",
		TextSize = 13,
		FontFace = inter(Enum.FontWeight.Medium),
		TextColor3 = themeColor(theme, "Text"),
		AutoButtonColor = false,
		Visible = UserInputService.TouchEnabled,
		ZIndex = 35,
		Parent = gui,
	}, { corner(10), stroke(themeColor(theme, "PanelStroke")) })
	self:_connect(self.Restore.MouseButton1Click, function()
		self:ToggleToolbar()
	end)

	self:_connect(UserInputService:GetPropertyChangedSignal("TouchEnabled"), function()
		self.Restore.Visible = UserInputService.TouchEnabled
		if self._visible then self.DockHolder.Position = UDim2.new(0.5, 0, 1, -self:_dockBottom()) end
		if self._open then self:_fitPanel(self._open, false) end
	end)

	if options.Loading then
		self:_buildLoading(options.Loading)
	end

	self.CommandButton = create("TextButton", {
		Name = "OpenCommands", BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
		Size = UDim2.fromOffset(40, 40), LayoutOrder = -100, Parent = self.Dock,
	}, { corner(9) })
	iconLabel("search", 19, theme.SubText, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Parent = self.CommandButton })
	self:_connect(self.CommandButton.MouseButton1Click, function() self:OpenCommandPalette() end)
	self:_bindInput()
	if options.ConfigEncryption then
		local ok, err = self:SetConfigEncryption(options.ConfigEncryption)
		if not ok then self:_teardown() error("[RiftUI] " .. err, 2) end
		if saved and saved.EncryptConfigs ~= nil then self._encryptConfigs = saved.EncryptConfigs == true end
	end
	if options.ConfigServer then
		local ok, err = self:SetConfigServer(options.ConfigServer)
		if not ok then self:_teardown() error("[RiftUI] " .. err, 2) end
	end
	if options.Settings ~= false then
		self:_buildSettings()
	end
	table.insert(RiftUI.Hubs, self)
	queueSecureFont()
	registry[id] = self
	self:_registerSetupFlags()
	setState("Building", self.Name)
	task.defer(function()
		if self._destroyed then
			return
		end
		self:_loadingStep("Applying preferences", 0.45)
		if options.Setup ~= false and not (saved and saved.Completed) and not self._replaying then
			self:_afterLoading(function()
				task.delay(0.35, function()
					if not self._destroyed then
						self:OpenSetup()
					end
				end)
			end)
		end
		if options.Stealth then
			self:SetStealth(true)
		end
		if saved and type(saved.Studio) == "table" and saved.Studio.Background then
			self.Background = saved.Studio.Background
			self:_applyBackground()
		end
		if RiftUI.DeveloperMode and options.Settings ~= false then
			self:_buildDeveloper()
		end
		-- HUD pieces and language: the saved choice wins over the CreateHub default
		local prefs = self.SetupData or {}
		local function pref(key, default)
			if prefs[key] ~= nil then return prefs[key] end
			return default
		end
		-- HUD pieces come up with the toolbar, not over the loading card
		self:_afterLoading(function()
			if self._destroyed then return end
			if pref("Watermark", options.Watermark) and not self._watermark then self:SetWatermark(true, true) end
			if pref("KeybindList", options.KeybindList) then self:SetKeybindList(true, true) end
		end)
		local language = pref("Language", options.Language)
		if not language then
			pcall(function()
				local locale = string.lower(string.sub(game:GetService("LocalizationService").RobloxLocaleId, 1, 2))
				if RiftUI.Translations[locale] or (options.Translations or {})[locale] then language = locale end
			end)
		end
		if language and language ~= "en" then self:SetLanguage(language, true) end
		if next(self._requirements) then
			self:_loadingStep("Checking requirements", 0.65)
			self:RunRequirements()
		end
		self:_loadingStep("Loading config", 0.85)
		self:_autoload()
		if RiftUI.State == "Building" or RiftUI.State == "Reinitializing" then
			setState("Ready", self.Name)
		end
		if self._loading and not self._loading.Manual then
			self:FinishLoading()
		end
	end)
	return self
end

---------------------------------------------------------------- loading screen
--[[
	A small card that holds the screen while the hub builds. The dock stays down until it
	leaves, and anything that would open over it (setup, Hub:Open) waits its turn.
	Loading = true, or { Title, Subtitle, Icon, MinDuration, Manual }. With Manual = true the
	card stays until Hub:FinishLoading(); Hub:SetLoading(status, progress) drives it.
]]
-- The floating card the loading screen and the auth gate share: shadow, fading body,
-- outline and sheen, with a chip/title/subtitle head.
local function floatingCard(parent: Instance, theme, width: number, z: number)
	local holder = create("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 10),
		Size = UDim2.new(1, -24, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = z,
		Parent = parent,
	})
	create("UISizeConstraint", { MaxSize = Vector2.new(width, 100000), Parent = holder })
	shadow(holder, 30, z, 8)
	local card = create("CanvasGroup", {
		Name = "Card",
		BackgroundColor3 = themeColor(theme, "Panel"),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		GroupTransparency = 1,
		ZIndex = z + 1,
		Parent = holder,
	}, { corner(14), padding(16, 16, 16, 16), list(Enum.FillDirection.Vertical, 14) })
	local outline = create("Frame", { Name = "Outline", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = z + 2, Parent = holder }, {
		corner(14),
		stroke(themeColor(theme, "PanelStroke"), 1, 1),
	})
	sheen(holder, 16, theme, z + 2)
	return holder, card, outline
end

local function cardHead(card: Instance, theme, title: string, subtitle: string?, icon: string?, z: number, rightInset: number?)
	local head = create("Frame", { Name = "Head", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 32), ZIndex = z, Parent = card })
	local chip = create("Frame", {
		Name = "Chip",
		BackgroundColor3 = themeColor(theme, "Tile"),
		Size = UDim2.fromOffset(32, 32),
		ZIndex = z,
		Parent = head,
	}, { corner(8), stroke(themeColor(theme, "TileStroke")) })
	if not hubMark(icon, 16, theme, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = z + 1, Parent = chip }) then
		text({ Parent = chip, Text = string.upper(string.sub(title, 1, 1)), FontFace = inter(Enum.FontWeight.SemiBold), Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = z + 1 })
	end
	local hasSub = type(subtitle) == "string" and subtitle ~= ""
	local inset = 44 + (rightInset or 0)
	text({ Parent = head, Name = "Title", Text = title, FontFace = inter(Enum.FontWeight.SemiBold), TextSize = 14, Position = UDim2.fromOffset(44, hasSub and 0 or 8), Size = UDim2.new(1, -inset, 0, 17), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = z + 1 })
	if hasSub then
		text({ Parent = head, Name = "Subtitle", Text = subtitle, TextSize = 12, TextColor3 = themeColor(theme, "SubText"), Position = UDim2.fromOffset(44, 17), Size = UDim2.new(1, -inset, 0, 15), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = z + 1 })
	end
	return head
end

local function showCard(holder, card, outline)
	tween(holder, RISE, { Position = UDim2.fromScale(0.5, 0.5) })
	tween(card, RISE, { GroupTransparency = 0 })
	tween(outline:FindFirstChildOfClass("UIStroke"), RISE, { Transparency = 0 })
end

local function hideCard(holder, card, outline)
	tween(holder, FOLD, { Position = UDim2.new(0.5, 0, 0.5, -6) })
	tween(outline:FindFirstChildOfClass("UIStroke"), FOLD, { Transparency = 1 })
	local shade = holder:FindFirstChild("Shadow")
	if shade then tween(shade, FOLD, { ImageTransparency = 1 }) end
	return tween(card, FOLD, { GroupTransparency = 1 })
end

function Hub:_buildLoading(o)
	o = type(o) == "table" and o or {}
	assert(o.MinDuration == nil or type(o.MinDuration) == "number", "Loading.MinDuration must be a number")
	local theme = self.Theme
	local state = { Manual = o.Manual == true, MinDuration = o.MinDuration or 1, Started = os.clock(), Progress = 0, Queue = {} }
	self._loading = state
	self.DockHolder.Visible = false
	self.Restore.Visible = false
	local holder, card, outline = floatingCard(self.Gui, theme, 300, 95)
	holder.Name = "Loading"
	cardHead(card, theme, o.Title or self.Name, o.Subtitle or self.Subtitle, o.Icon or self.Icon, 96)
	local foot = create("Frame", { Name = "Status", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 2, ZIndex = 96, Parent = card })
	state.Status = text({ Parent = foot, Name = "Label", Text = self:T("Building interface"), TextSize = 11, TextColor3 = themeColor(theme, "SubText"), Size = UDim2.new(1, -44, 0, 14), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 97 })
	state.Percent = text({ Parent = foot, Name = "Percent", Text = "0%", FontFace = MONO, TextSize = 11, TextColor3 = themeColor(theme, "Muted"), TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(44, 14), ZIndex = 97 })
	local track = create("Frame", { Name = "Track", BackgroundColor3 = themeColor(theme, "Track"), BorderSizePixel = 0, Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 3), ZIndex = 97, Parent = foot }, { corner(2) })
	state.Fill = create("Frame", { Name = "Fill", BackgroundColor3 = themeColor(theme, "Accent"), BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), ZIndex = 98, Parent = track }, { corner(2) })
	state.Holder, state.Card, state.Outline = holder, card, outline
	showCard(holder, card, outline)
	self:_loadingStep("Building interface", 0.2)
end

function Hub:_loadingStep(status: string, progress: number)
	local state = self._loading
	if state and not state.Manual then self:SetLoading(status, progress) end
end

-- Update the loading card. Progress is 0–1 and never moves backwards; omit it to keep the bar.
function Hub:SetLoading(status: string?, progress: number?)
	local state = self._loading
	if not state or state.Finishing then return end
	if type(status) == "string" then state.Status.Text = self:T(status) end
	if type(progress) == "number" then
		state.Progress = math.max(state.Progress, math.clamp(progress, 0, 1))
		state.Percent.Text = math.floor(state.Progress * 100 + 0.5) .. "%"
		tween(state.Fill, SETTLE, { Size = UDim2.fromScale(state.Progress, 1) })
	end
end

function Hub:IsLoading(): boolean
	return self._loading ~= nil
end

-- Run fn once the loading card has gone, or now if there isn't one.
function Hub:_afterLoading(fn)
	if self._loading then table.insert(self._loading.Queue, fn) else fn() end
end

function Hub:FinishLoading()
	local state = self._loading
	if not state or state.Finishing then return end
	state.Finishing = true
	state.Status.Text = self:T("Ready")
	state.Percent.Text = "100%"
	tween(state.Fill, SETTLE, { Size = UDim2.fromScale(1, 1) })
	task.spawn(function()
		-- a card that flashes for a frame reads as a glitch, so it stays at least MinDuration
		local wait = state.MinDuration - (os.clock() - state.Started)
		task.wait(math.max(0.25, wait))
		if self._destroyed then return end
		hideCard(state.Holder, state.Card, state.Outline).Completed:Wait()
		if self._destroyed then return end
		state.Holder:Destroy()
		self._loading = nil
		self.Restore.Visible = UserInputService.TouchEnabled
		if self._visible then
			local holder, bottom = self.DockHolder, self:_dockBottom()
			holder.Position = UDim2.new(0.5, 0, 1, -bottom + 12)
			holder.Visible = true
			tween(holder, RISE, { Position = UDim2.new(0.5, 0, 1, -bottom) })
		end
		for _, fn in state.Queue do task.spawn(fn) end
	end)
end

---------------------------------------------------------------- auth gate
--[[
	Rift:CreateAuth asks for a key before any hub exists. The key goes to the author's server
	as a bearer token; a 2xx answer carries the hub script, which CreateAuth returns for the
	caller to loadstring. Anything already on the client can be edited, so the gate only
	protects what the server holds back: keep the hub itself on the server.

		local source, key = Rift:CreateAuth({ Name = "My Hub", Url = "https://auth.example.com/v1/script" })
		if not source then return end
		loadstring(source)()
]]
local AUTH_SCRIPT_LIMIT = 16 * 1024 * 1024

local function authHwid(): string?
	if typeof(gethwid) == "function" then
		local ok, id = pcall(gethwid)
		if ok and type(id) == "string" and id ~= "" then return id end
	end
	local ok, id = pcall(function() return game:GetService("RbxAnalyticsService"):GetClientId() end)
	return ok and type(id) == "string" and id ~= "" and id or nil
end

-- A short, single-line reason from an error body: JSON { error } / { message }, or plain text.
local function authReason(body): string?
	if type(body) ~= "string" or body == "" or #body > 4096 then return nil end
	local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
	local reason
	if ok and type(data) == "table" then
		reason = data.error or data.message
	elseif not ok and not string.find(body, "<", 1, true) then
		reason = body
	end
	if type(reason) ~= "string" then return nil end
	reason = string.gsub(string.gsub(reason, "%c", " "), "^%s*(.-)%s*$", "%1")
	if reason == "" then return nil end
	return #reason > 140 and (string.sub(reason, 1, 140) .. "…") or reason
end

-- ok, scriptOrReason, retryable. Retryable failures (network, 429, 5xx) keep a saved key.
local function authCheck(o, key: string)
	if o.Request then
		local ok, passed, result = pcall(o.Request, key)
		if not ok then
			recordError(tostring(passed), nil, "auth")
			return false, "The key check failed. Try again.", true
		end
		if passed == true and type(result) == "string" and result ~= "" then return true, result end
		return false, type(result) == "string" and result ~= "" and result or "Invalid key.", passed == nil
	end
	local httpRequest = (typeof(request) == "function" and request) or (typeof(http_request) == "function" and http_request)
	if not httpRequest then return false, "This executor can't make HTTP requests.", false end
	local headers = { Authorization = "Bearer " .. key, Accept = "text/plain, application/json" }
	if o.SendHwid then headers["X-Rift-Hwid"] = authHwid() end
	local ok, response = pcall(httpRequest, { Url = o.Url, Method = "GET", Headers = headers, Timeout = 20 })
	local status = ok and type(response) == "table" and tonumber(response.StatusCode) or 0
	if status == 0 then return false, "Couldn't reach the server. Check your connection and try again.", true end
	if status >= 200 and status < 300 then
		local body = response.Body
		if type(body) ~= "string" or body == "" then return false, "The server sent an empty script.", true end
		if #body > AUTH_SCRIPT_LIMIT then return false, "The server sent an oversized script.", false end
		return true, body
	end
	local retry = status == 429 or status >= 500
	local fallback = (status == 401 or status == 403) and "Invalid key."
		or status == 429 and "Too many attempts. Wait a moment, then try again."
		or ("The server returned HTTP " .. status .. ".")
	return false, (not retry and authReason(response.Body)) or fallback, retry
end

function RiftUI:CreateAuth(options)
	options = options or {}
	assert(type(options) == "table", "CreateAuth expects an options table")
	assert(options.Request == nil or type(options.Request) == "function", "Request must be a function")
	if not options.Request then
		local authority = type(options.Url) == "string" and string.match(options.Url, "^https://([^/%s?#]+)")
		assert(authority and not string.find(authority, "@", 1, true) and not string.find(options.Url, "[%s#]"), "CreateAuth needs an HTTPS Url without credentials, or a Request function")
	end
	local id = hubId(options)
	local name = options.Name or "Rift Hub"
	local saved = readSetup(id)
	local theme = buildTheme((saved and saved.Theme) or options.ThemeName or "Graphite", options.Theme)
	local remember = options.Remember ~= false and hasFS
	local keyPath = RiftUI.Folder .. "/" .. id .. "/auth.key"

	local gui = create("ScreenGui", { Name = "RiftAuth", IgnoreGuiInset = true, ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 110 })
	if typeof(protectgui) == "function" then pcall(protectgui, gui) end
	gui.Parent = guiParent()
	local holder, card, outline = floatingCard(gui, theme, 340, 10)
	holder.Name = "Auth"
	local head = cardHead(card, theme, options.Title or name, options.Subtitle or "Enter your key to continue", options.Icon or options.HubIcon, 11, 32)
	local close = create("TextButton", {
		Name = "Close", BackgroundColor3 = themeColor(theme, "Tile"), BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 4, 0.5, 0), Size = UDim2.fromOffset(28, 28), ZIndex = 12, Parent = head,
	}, { corner(7) })
	if not iconLabel("x", 15, theme.SubText, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 13, Parent = close }) then
		text({ Parent = close, Text = "×", TextColor3 = themeColor(theme, "SubText"), TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 13 })
	end
	close.MouseEnter:Connect(function() tween(close, FAST, { BackgroundTransparency = 0 }) end)
	close.MouseLeave:Connect(function() tween(close, FAST, { BackgroundTransparency = 1 }) end)
	if type(options.Note) == "string" and options.Note ~= "" then
		text({ Parent = card, Name = "Note", Text = options.Note, TextSize = 12, TextColor3 = themeColor(theme, "SubText"), TextWrapped = true, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, ZIndex = 12 })
	end
	local field = create("Frame", { Name = "Field", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 52), LayoutOrder = 3, ZIndex = 11, Parent = card })
	local box = create("TextBox", {
		Name = "KeyBox", BackgroundColor3 = themeColor(theme, "Field"), Size = UDim2.new(1, 0, 0, 34),
		FontFace = MONO, TextSize = 12, TextColor3 = themeColor(theme, "Text"), Text = "",
		PlaceholderText = options.Placeholder or "Paste your key", PlaceholderColor3 = themeColor(theme, "Muted"),
		ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 12, Parent = field,
	}, { corner(7), padding(0, 10) })
	local boxStroke = stroke(themeColor(theme, "FieldStroke"))
	boxStroke.Parent = box
	local status = text({ Parent = field, Name = "Status", Text = "", TextSize = 11, TextColor3 = themeColor(theme, "Muted"), Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 0, 14), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 12 })
	local buttons = create("Frame", { Name = "Buttons", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 32), LayoutOrder = 4, ZIndex = 11, Parent = card })
	local links = create("Frame", { Name = "Links", BackgroundTransparency = 1, Size = UDim2.new(1, -110, 1, 0), ZIndex = 11, Parent = buttons }, {
		list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
	})
	local function button(label: string, primary: boolean, parent: Instance, order: number?)
		local b = create("TextButton", {
			Name = label, BackgroundColor3 = themeColor(theme, primary and "Accent" or "Tile"), Text = label,
			FontFace = inter(Enum.FontWeight.Medium), TextSize = 13, TextColor3 = themeColor(theme, primary and "AccentText" or "Text"),
			AutoButtonColor = false, Size = UDim2.fromOffset(0, 32), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = order or 0, ZIndex = 12, Parent = parent,
		}, { corner(8), padding(0, 12) })
		if not primary then
			stroke(themeColor(theme, "TileStroke")).Parent = b
			b.MouseEnter:Connect(function() tween(b, FAST, { BackgroundColor3 = themeColor(theme, "TileHover") }) end)
			b.MouseLeave:Connect(function() tween(b, FAST, { BackgroundColor3 = themeColor(theme, "Tile") }) end)
		end
		return b
	end
	local submit = button("Continue", true, buttons)
	submit.AnchorPoint = Vector2.new(1, 0)
	submit.Position = UDim2.fromScale(1, 0)
	submit.Size = UDim2.fromOffset(100, 32)
	submit.AutomaticSize = Enum.AutomaticSize.None

	local function say(message: string, tone: string?)
		status.Text = message
		setThemed(status, "TextColor3", themeColor(theme, tone or "Muted"))
	end
	local function copyLink(url: string, what: string)
		if typeof(setclipboard) == "function" and pcall(setclipboard, url) then
			say(what .. " link copied. Open it in your browser.", "Success")
		else
			say(url, "SubText")
		end
	end
	if type(options.GetKeyUrl) == "string" and options.GetKeyUrl ~= "" then
		button("Get key", false, links, 1).MouseButton1Click:Connect(function() copyLink(options.GetKeyUrl, "Key") end)
	end
	if type(options.Discord) == "string" and options.Discord ~= "" then
		button("Discord", false, links, 2).MouseButton1Click:Connect(function() copyLink(options.Discord, "Discord") end)
	end

	local finished, result, acceptedKey, reason = false, nil, nil, nil
	local busy = false
	local function shake()
		local x = { 7, -6, 4, -2, 0 }
		task.spawn(function()
			for _, dx in x do
				holder.Position = UDim2.new(0.5, dx, 0.5, 0)
				task.wait(0.035)
			end
		end)
		tween(boxStroke, FAST, { Color = themeColor(theme, "Danger") })
	end
	local function attempt(key: string, fromFile: boolean)
		if busy or finished then return end
		key = string.gsub(key or "", "^%s*(.-)%s*$", "%1")
		if key == "" then say("Enter your key.", "Danger") shake() return end
		if #key > 512 or string.find(key, "%c") then say("That key isn't valid.", "Danger") shake() return end
		busy = true
		box.TextEditable = false
		submit.Text = "Checking…"
		say(fromFile and "Checking your saved key…" or "Checking key…")
		tween(boxStroke, FAST, { Color = themeColor(theme, "FieldStroke") })
		local ok, value, retry = authCheck(options, key)
		busy = false
		if finished or not gui.Parent then return end
		box.TextEditable = true
		submit.Text = "Continue"
		if ok then
			say("Key accepted. Loading " .. name .. "…", "Success")
			tween(boxStroke, FAST, { Color = themeColor(theme, "Success") })
			if remember then
				pcall(function()
					ensureFolder(RiftUI.Folder) ensureFolder(RiftUI.Folder .. "/" .. id)
					writefile(keyPath, key)
				end)
			end
			result, acceptedKey = value, key
			task.wait(0.35)
			finished = true
		else
			-- a rejected saved key is forgotten; one that only hit a network error is kept
			if fromFile and not retry and typeof(delfile) == "function" then pcall(delfile, keyPath) end
			say(value, "Danger")
			shake()
		end
	end
	submit.MouseButton1Click:Connect(function() task.spawn(attempt, box.Text, false) end)
	box.FocusLost:Connect(function(enter) if enter then task.spawn(attempt, box.Text, false) end end)
	box.Focused:Connect(function() if not busy then tween(boxStroke, FAST, { Color = themeColor(theme, "SubText") }) end end)
	close.MouseButton1Click:Connect(function()
		if finished then return end
		reason, finished = "closed", true
	end)

	showCard(holder, card, outline)
	if remember then
		local ok, stored = pcall(function() return isfile(keyPath) and readfile(keyPath) or nil end)
		if ok and type(stored) == "string" and stored ~= "" then
			box.Text = stored
			task.spawn(attempt, stored, true)
		end
	end
	while not finished and gui.Parent do task.wait() end
	if not finished then reason = "closed" end
	if gui.Parent then
		hideCard(holder, card, outline).Completed:Wait()
		gui:Destroy()
	end
	if result then return result, acceptedKey end
	return nil, reason or "closed"
end

-- Forget the key CreateAuth saved for a hub, e.g. from a "Log out" button.
function RiftUI:ClearAuthKey(options)
	local id = hubId(type(options) == "string" and { Id = options } or options or {})
	if hasFS and typeof(delfile) == "function" then
		pcall(delfile, RiftUI.Folder .. "/" .. id .. "/auth.key")
	end
end

---------------------------------------------------------------- developer-defined requirements
local function requirementIds(required)
	if required == nil then return {} end
	if type(required) == "string" then return { required } end
	assert(type(required) == "table", "Requires must be a requirement ID or a list of IDs")
	local ids, seen = {}, {}
	for _, id in required do
		assert(type(id) == "string" and id ~= "", "Requires must contain requirement IDs")
		if not seen[id] then seen[id] = true table.insert(ids, id) end
	end
	return ids
end

local function mergedRequirements(parent, own)
	local out, seen = {}, {}
	for _, list in { requirementIds(parent), requirementIds(own) } do
		for _, id in list do if not seen[id] then seen[id] = true table.insert(out, id) end end
	end
	return out
end

function Hub:_initRequirements(definitions)
	self._requirements, self._requirementResults, self._requirementRuns = {}, {}, {}
	self._requiredControls, self._requirementWatchers, self._requirementThreads = {}, {}, {}
	assert(definitions == nil or type(definitions) == "table", "Requirements must be a table of developer tests")
	for id, spec in definitions or {} do
		assert(type(id) == "string" and id ~= "", "Requirements must use named IDs")
		if type(spec) == "function" then spec = { Test = spec } end
		assert(type(spec) == "table" and type(spec.Test) == "function", "Requirement " .. id .. " needs a developer-defined Test function")
		assert(spec.Name == nil or type(spec.Name) == "string", "Requirement Name must be a string")
		assert(spec.Message == nil or type(spec.Message) == "string", "Requirement Message must be a string")
		local timeout = spec.Timeout or 5
		assert(type(timeout) == "number" and timeout >= 0.1 and timeout <= 30, "Requirement Timeout must be 0.1–30 seconds")
		self._requirements[id] = { Test = spec.Test, Name = spec.Name or id, Message = spec.Message, Timeout = timeout }
		self._requirementResults[id] = { Id = id, Name = spec.Name or id, Status = "pending", Passed = false, Message = "Not checked yet" }
	end
end

function Hub:CanUse(required)
	for _, id in requirementIds(required) do
		local result = self._requirementResults[id]
		if not result then return false, "Unknown requirement: " .. id end
		if not result.Passed then
			if result.Status == "pending" then return false, "Checking " .. result.Name .. "…" end
			return false, result.Message or (result.Name .. " is unavailable")
		end
	end
	return true
end

function Hub:GetRequirement(id)
	local result = self._requirementResults[id]
	return result and table.clone(result) or nil
end

function Hub:OnRequirementsChanged(callback)
	assert(type(callback) == "function", "callback must be a function")
	local watcher = { Callback = callback, Connected = true }
	table.insert(self._requirementWatchers, watcher)
	return { Disconnect = function() watcher.Connected = false end }
end

function Hub:_requirementsChanged()
	if self._destroyed then return end
	for _, control in self._requiredControls do
		if control.Frame.Parent then
			local allowed, reason = self:CanUse(control.Requires)
			control.Available, control.RequirementMessage = allowed, reason
			if control._requirementOverlay then
				control._requirementOverlay.Visible = not allowed
				control._requirementReason.Text = reason or ""
			end
			if not allowed then
				-- A popup opened before a test changed must not bypass the new gate.
				if self._popup then
					local anchor = self._popup.Anchor
					if anchor and anchor:IsDescendantOf(control.Frame) then self:_closePopup() end
				end
			else
				if control._requirementRestore then self:_restoreRequiredControl(control) end
				if control._pendingRequirementDefault then
					control._pendingRequirementDefault = nil
					if control.Type == "Toggle" and control.Value then control:_emit(true) end
				end
			end
		end
	end
	self:_keybindsChanged()
	for _, watcher in self._requirementWatchers do
		if watcher.Connected then
			local snapshot = {}
			for id, result in self._requirementResults do snapshot[id] = table.clone(result) end
			task.spawn(function()
				local ok, err = pcall(watcher.Callback, snapshot)
				if not ok then recordError(tostring(err), nil, "requirements changed") end
			end)
		end
	end
end

function Hub:RunRequirement(id)
	local spec = self._requirements[id]
	if not spec then return { Id = id, Name = id, Passed = false, Status = "failed", Message = "Unknown requirement: " .. tostring(id) } end
	if self._requirementThreads[id] then pcall(task.cancel, self._requirementThreads[id]) end
	local run = (self._requirementRuns[id] or 0) + 1
	self._requirementRuns[id] = run
	self._requirementResults[id] = { Id = id, Name = spec.Name, Passed = false, Status = "pending", Message = "Checking…" }
	self:_requirementsChanged()
	local finished, success, passed, message = false, false, false, nil
	local thread = task.spawn(function()
		success, passed, message = pcall(spec.Test, self)
		finished = true
	end)
	self._requirementThreads[id] = thread
	local started = os.clock()
	while not finished and not self._destroyed and self._requirementRuns[id] == run and os.clock() - started < spec.Timeout do task.wait() end
	if self._destroyed or self._requirementRuns[id] ~= run then pcall(task.cancel, thread) return self:GetRequirement(id) end
	if not finished then pcall(task.cancel, thread) end
	self._requirementThreads[id] = nil
	local result = { Id = id, Name = spec.Name, Passed = finished and success and passed == true, Status = "failed" }
	if not finished then
		result.Status, result.Message = "timeout", spec.Name .. " test timed out"
	elseif not success then
		result.Message = spec.Message or (spec.Name .. " test raised an error")
		-- Test errors belong to the developer. Keep them in the result, not a generic VM failure.
		result.Error = tostring(passed)
	elseif passed ~= true then
		result.Message = type(message) == "string" and message or spec.Message or (spec.Name .. " is unavailable")
	else
		result.Status, result.Message = "passed", type(message) == "string" and message or "Available"
	end
	self._requirementResults[id] = result
	self:_requirementsChanged()
	return table.clone(result)
end

function Hub:RunRequirements()
	self._requirementBatch = (self._requirementBatch or 0) + 1
	local batch = self._requirementBatch
	local ids = {}
	for id in self._requirements do table.insert(ids, id) end
	table.sort(ids)
	-- Mark the whole set pending so a recheck cannot use stale passing results.
	for _, id in ids do
		self._requirementRuns[id] = (self._requirementRuns[id] or 0) + 1
		self._requirementResults[id] = { Id = id, Name = self._requirements[id].Name, Passed = false, Status = "pending", Message = "Checking…" }
	end
	self:_requirementsChanged()
	local results = {}
	for _, id in ids do
		if self._destroyed or batch ~= self._requirementBatch then break end
		results[id] = self:RunRequirement(id)
	end
	return results
end

function Hub:Guard(required, callback)
	local ids = requirementIds(required)
	assert(type(callback) == "function", "Guard needs a callback")
	return function(...)
		local allowed, reason = self:CanUse(ids)
		if not allowed then return false, reason end
		return callback(...)
	end
end

function Hub:_finishRequiredControl(control)
	if #control.Requires == 0 or ({ Label = true, Paragraph = true, Info = true, Progress = true, Stat = true, Sparkline = true, Console = true })[control.Type] then return control end
	local theme, row = self.Theme, control.Frame
	local overlay = create("TextButton", {
		Name = "RequirementGate", BackgroundColor3 = themeColor(theme, "Panel"), BackgroundTransparency = 0,
		Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1), ZIndex = 10, Parent = row,
	})
	text({ Parent = overlay, Text = control.Name, TextColor3 = themeColor(theme, "SubText"), TextSize = 13,
		Position = UDim2.fromOffset(0, 1), Size = UDim2.new(1, -28, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 11 })
	local reason = text({ Parent = overlay, Text = "", TextColor3 = themeColor(theme, "SubText"), TextSize = 11,
		Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, -28, 0, 14), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 11 })
	iconLabel("lock", 14, theme.SubText, { Parent = overlay, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -4, 0.5, 0), ZIndex = 11 })
	control._requirementOverlay, control._requirementReason = overlay, reason
	self:_connect(overlay.MouseButton1Click, function()
		self:Notify({ Title = control.Name .. " unavailable", Content = control.RequirementMessage or "Requirements are still being checked.", Icon = "lock", Duration = 4 })
	end)
	self:_connect(overlay.MouseEnter, function() self:_showTip(overlay, control.RequirementMessage or "Checking requirements…") end)
	self:_connect(overlay.MouseLeave, function() if self._tipFor == overlay then self:_hideTip() end end)
	local originalSet = control.Set
	if originalSet then
		control.Set = function(c, ...)
			local allowed, why = c:IsAvailable()
			if not allowed then return false, why end
			return originalSet(c, ...)
		end
	end
	table.insert(self._requiredControls, control)
	self:_requirementsChanged()
	return control
end

function Hub:_connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(self._conns, c)
	return c
end

function Hub:_record(target, method: string, args, result)
	if target._internal or result._internal or self._replaying then
		return
	end
	table.insert(self._recipe, { Target = target, Method = method, Args = args, Result = result })
end

function Hub:_buildHeader()
	local theme = self.Theme
	local header = create("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 56),
		Parent = self.Panel,
	}, { padding(0, 10, 0, 16) })
	self.HeaderChip = create("Frame", {
		Name = "Chip",
		BackgroundColor3 = themeColor(theme, "Tile"),
		Position = UDim2.fromOffset(0, 12),
		Size = UDim2.fromOffset(32, 32),
		Parent = header,
	}, { corner(8), stroke(themeColor(theme, "TileStroke")) })
	self.HeaderTitle = text({
		Parent = header,
		Name = "Title",
		FontFace = inter(Enum.FontWeight.SemiBold),
		TextSize = 14,
		Position = UDim2.fromOffset(44, 12),
		Size = UDim2.new(1, -150, 0, 17),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	self.HeaderSub = text({
		Parent = header,
		Name = "Description",
		TextSize = 12,
		TextColor3 = themeColor(theme, "SubText"),
		Position = UDim2.fromOffset(44, 30),
		Size = UDim2.new(1, -150, 0, 14),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	create("Frame", {
		Name = "Rule",
		BackgroundColor3 = themeColor(theme, "Divider"),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, -16, 1, 0),
		Size = UDim2.new(1, 26, 0, 1),
		Parent = header,
	})
	self.Search = create("TextBox", {
		Name = "Search",
		BackgroundColor3 = themeColor(theme, "Field"),
		Position = UDim2.fromOffset(0, 12),
		Size = UDim2.new(1, -78, 0, 32),
		FontFace = inter(),
		TextSize = 13,
		TextColor3 = themeColor(theme, "Text"),
		PlaceholderText = "Search this tab",
		PlaceholderColor3 = themeColor(theme, "Muted"),
		Text = "",
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
		Parent = header,
	}, { corner(8), stroke(themeColor(theme, "FieldStroke")), padding(0, 10) })
	local actions = create("Frame", {
		Name = "Actions",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 14),
		Size = UDim2.fromOffset(64, 28),
		Parent = header,
	}, { list(Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Right) })
	local function action(icon: string, fallback: string, order: number, fn)
		local b = create("TextButton", {
			Name = icon,
			BackgroundColor3 = themeColor(theme, "Tile"),
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(28, 28),
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = order,
			Parent = actions,
		}, { corner(7) })
		local img = iconLabel(icon, 16, theme.SubText, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
		if img then
			img.Parent = b
		else
			text({ Parent = b, Text = fallback, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = themeColor(theme, "SubText") })
		end
		self:_connect(b.MouseEnter, function()
			tween(b, FAST, { BackgroundTransparency = 0 })
			if img then
				setThemed(img, "ImageColor3", themeColor(theme, "Text"))
			end
		end)
		self:_connect(b.MouseLeave, function()
			tween(b, FAST, { BackgroundTransparency = 1 })
			if img then
				setThemed(img, "ImageColor3", themeColor(theme, "SubText"))
			end
		end)
		self:_connect(b.MouseButton1Click, fn)
		return b
	end
	action("search", "?", 1, function()
		self:_toggleSearch()
	end)
	action("x", "x", 2, function()
		self:Close()
	end)
	self:_connect(self.Search:GetPropertyChangedSignal("Text"), function()
		self:_applySearch(self.Search.Text)
	end)
	self:_connect(self.Search.FocusLost, function()
		if self.Search.Text == "" then
			self:_toggleSearch(false)
		end
	end)
end

function Hub:_toggleSearch(force: boolean?)
	local on = if force ~= nil then force else not self.Search.Visible
	self.Search.Visible = on
	self.HeaderTitle.Visible = not on
	self.HeaderChip.Visible = not on
	self.HeaderSub.Visible = not on and self._open ~= nil and (self._open.Description or "") ~= ""
	if on then
		self.Search:CaptureFocus()
	else
		self.Search.Text = ""
		self:_applySearch("")
	end
end

function Hub:_applySearch(query: string)
	local tab = self._open
	if not tab then
		return
	end
	query = string.lower(query)
	for _, section in tab.Sections do
		local any = false
		for _, control in section.Controls do
			local match = query == "" or string.find(string.lower(control.Name or ""), query, 1, true) ~= nil
			control.Frame.Visible = match and not control._hidden
			any = any or match
		end
		section.Frame.Visible = (any or query == "") and not section.Pinned
		local peek = query ~= "" and any
		if section._peek ~= peek then
			section._peek = peek
			section:_applyCollapse(false)
		end
	end
	task.defer(function()
		self:_fitPanel(tab, true)
	end)
end

---------------------------------------------------------------- input: click-off, toggle key
function Hub:_bindInput()
	self:_connect(UserInputService.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.Keyboard then
			if UserInputService:GetFocusedTextBox() then
				return
			end
			local top = self._windows and self._windows[#self._windows]
			if input.KeyCode == Enum.KeyCode.Escape and top and not self._palette and not self._listening then
				top:Close()
				return
			end
			if input.KeyCode == self.CommandKey and not self._listening then
				self:OpenCommandPalette()
				return
			end
			if input.KeyCode == self.ToggleKey and not self._listening then
				self:SetToolbarVisible(not self._visible)
			end
			return
		end
		if not isPointer(input) then
			return
		end
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		if self._popup and not within(self._popup.Frame, pos) and not within(self._popup.Anchor, pos) then
			self:_closePopup()
		end
		-- a child window sits over the panel; clicks on it or its scrim never fold the panel
		if self._windows and #self._windows > 0 then
			return
		end
		if self._open and not within(self.PanelHolder, pos) and not within(self.Dock, pos) and not self._popupJustClosed then
			if not (self._popup and within(self._popup.Frame, pos)) then
				self:Close()
			end
		end
	end)
end

function Hub:_dockBottom()
	return UserInputService.TouchEnabled and 68 or 40
end

function Hub:SetToolbarVisible(visible: boolean, quiet: boolean?)
	if self._visible == visible then
		return
	end
	if self._loading then
		-- the dock comes up when loading ends; until then only remember the choice
		self._visible = visible
		self.Restore.Text = visible and "Hide toolbar" or "Show toolbar"
		return
	end
	self._visible = visible
	self.Restore.Text = visible and "Hide toolbar" or "Show toolbar"
	self.Restore.Visible = UserInputService.TouchEnabled
	local holder = self.DockHolder
	if visible then
		holder.Visible = true
		local bottom = self:_dockBottom()
		holder.Position = UDim2.new(0.5, 0, 1, -bottom + 12)
		tween(holder, RISE, { Position = UDim2.new(0.5, 0, 1, -bottom) })
	else
		self:Close()
		self:_closePopup()
		self.Tooltip.Visible = false
		local tw = tween(holder, FOLD, { Position = UDim2.new(0.5, 0, 1, 70) })
		tw.Completed:Connect(function()
			if not self._visible then
				holder.Visible = false
			end
		end)
		if not UserInputService.TouchEnabled and not quiet then
			self:Notify({
				Title = "Toolbar hidden",
				Content = "Press " .. keyName(self.ToggleKey) .. " to bring it back.",
				Duration = 3,
			})
		end
	end
end

function Hub:ToggleToolbar()
	self:SetToolbarVisible(not self._visible)
end

---------------------------------------------------------------- open / close
-- Panel height for a tab and its centred position, kept clear of the dock and the topbar.
function Hub:_panelGeometry(tab)
	local s = self._scale
	local vp = viewport() / s
	local top = topInset() / s + 12
	local bottom = vp.Y - self:_dockBottom() - 50 - 16
	local h = 58 + tab.Columns.Frame.AbsoluteSize.Y / s
	h = math.clamp(h, 120, math.max(bottom - top, 160))
	local cy = math.clamp(vp.Y / 2, top + h / 2, math.max(top + h / 2, bottom - h / 2))
	return h, cy
end

function Hub:_fitPanel(tab, animate: boolean)
	if self._panelFitTween then self._panelFitTween:Cancel() end
	if self._panelMoveTween then self._panelMoveTween:Cancel() end
	local narrow = viewport().X / self._scale < 460
	for side = 1, 2 do
		local col = tab.Columns[side]
		col.Visible = not narrow or side == 1
		col.Size = narrow and UDim2.new(1, 0, 0, 0) or UDim2.new(0.5, -9, 0, 0)
	end
	for i, section in tab.Sections do
		if not section.Pinned then
			section.Frame.Parent = tab.Columns[narrow and 1 or section.Side + 1]
			section.Frame.LayoutOrder = i
		end
	end
	local h, cy = self:_panelGeometry(tab)
	local goalSize = UDim2.fromOffset(math.min(470, viewport().X / self._scale - 24), h)
	local goalPos = UDim2.new(0.5, 0, 0, cy)
	if animate then
		self._panelFitTween = tween(self.PanelHolder, SETTLE, { Size = goalSize, Position = goalPos })
	else
		self.PanelHolder.Size = goalSize
		self.PanelHolder.Position = goalPos
	end
end

-- horizontal pull toward the tile that owns the panel, for the rise and fold motion
function Hub:_tileOffset(tab): number
	local s = self._scale
	local tp, ts = tab.Tile.AbsolutePosition, tab.Tile.AbsoluteSize
	return ((tp.X + ts.X / 2) - viewport().X / 2) / s * 0.22
end

function Hub:Open(tab)
	if type(tab) == "string" then
		for _, t in self.Tabs do
			if t.Name == tab then
				tab = t
				break
			end
		end
	end
	if type(tab) ~= "table" or self._open == tab then
		return
	end
	if self._loading then
		self:_afterLoading(function() if not self._destroyed then self:Open(tab) end end)
		return
	end
	local previous = self._open
	if previous then
		previous.Page.Visible = false
		previous:_setActive(false)
	end
	self._open = tab
	tab:_setActive(true)
	if self.Search.Visible then
		self:_toggleSearch(false)
	end
	self.HeaderTitle.Text = tab.Name
	self.HeaderSub.Text = tab.Description or ""
	self.HeaderSub.Visible = (tab.Description or "") ~= ""
	self.HeaderTitle.Position = UDim2.fromOffset(44, self.HeaderSub.Visible and 12 or 20)
	self.HeaderChip:ClearAllChildren()
	corner(8).Parent = self.HeaderChip
	stroke(self.Theme.TileStroke).Parent = self.HeaderChip
	if not iconLabel(tab.Icon, 16, self.Theme.Text, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Parent = self.HeaderChip }) then
		text({ Parent = self.HeaderChip, Text = string.upper(string.sub(tab.Name, 1, 1)), FontFace = inter(Enum.FontWeight.SemiBold), Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	end
	tab.Page.Visible = true
	tab.Scroll.CanvasPosition = Vector2.zero
	self.Tooltip.Visible = false

	if previous then
		-- switching tabs: content slides in from the side of the tile you came from
		local dir = (table.find(self.Tabs, tab) or 0) > (table.find(self.Tabs, previous) or 0) and 1 or -1
		self:_fitPanel(tab, true)
		tab.Scroll.Position = UDim2.fromOffset(18 * dir, 0)
		tween(tab.Scroll, SETTLE, { Position = UDim2.fromOffset(0, 0) })
		return
	end
	local holder = self.PanelHolder
	holder.Visible = true
	self:_fitPanel(tab, false)
	-- the signature move: the sheet rises out of its tile toward the centre
	local goal = holder.Position
	holder.Position = goal + UDim2.fromOffset(self:_tileOffset(tab), 26)
	self.Panel.GroupTransparency = 1
	self.PanelRise.Scale = 0.92
	self.PanelOutlineStroke.Transparency = 1
	if self.PanelShadow then
		self.PanelShadow.ImageTransparency = 1
		tween(self.PanelShadow, RISE, { ImageTransparency = 0.1 })
	end
	self._panelMoveTween = tween(holder, RISE, { Position = goal })
	tween(self.Panel, SOFT, { GroupTransparency = 0 })
	tween(self.PanelRise, RISE, { Scale = 1 })
	tween(self.PanelOutlineStroke, RISE, { Transparency = 0 })
end

function Hub:Close()
	local tab = self._open
	if not tab then
		return
	end
	self._open = nil
	tab:_setActive(false)
	self:_closePopup()
	if self.Search.Visible then
		self:_toggleSearch(false)
	end
	local holder = self.PanelHolder
	if self.PanelShadow then
		tween(self.PanelShadow, FOLD, { ImageTransparency = 1 })
	end
	tween(self.PanelOutlineStroke, FOLD, { Transparency = 1 })
	tween(self.PanelRise, FOLD, { Scale = 0.95 })
	self._panelMoveTween = tween(holder, FOLD, { Position = holder.Position + UDim2.fromOffset(self:_tileOffset(tab) * 0.5, 14) })
	local tw = tween(self.Panel, FOLD, { GroupTransparency = 1 })
	tw.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed and self._open == nil then
			holder.Visible = false
			tab.Page.Visible = false
		end
	end)
end

---------------------------------------------------------------- popups (dropdown lists, color picker)
function Hub:_openPopup(anchor: GuiObject, frame: GuiObject, onClose)
	self:_closePopup()
	local holder = create("Frame", {
		Name = "Popup",
		BackgroundTransparency = 1,
		Size = frame.Size,
		Parent = self.Overlay,
	})
	shadow(holder, 20, 40, 6)
	frame.Position = UDim2.new()
	frame.Parent = holder
	self._popup = { Anchor = anchor, Frame = frame, Holder = holder, OnClose = onClose }
	local s = self._scale
	local ap, as = anchor.AbsolutePosition / s, anchor.AbsoluteSize / s
	local fs = frame.AbsoluteSize / s
	local vp = viewport() / s
	local floor = vp.Y - 8
	if self._visible and self.DockHolder.Visible then
		floor = math.min(floor, self.Dock.AbsolutePosition.Y / s - 8)
	end
	local x = math.clamp(ap.X + as.X - fs.X, 8, math.max(8, vp.X - fs.X - 8))
	local y = ap.Y + as.Y + 6
	local below = true
	if y + fs.Y > floor then
		y = math.max(8, ap.Y - 6 - fs.Y)
		below = false
	end
	holder.Position = UDim2.fromOffset(x, y + (below and -6 or 6))
	tween(holder, SETTLE, { Position = UDim2.fromOffset(x, y) })
end

function Hub:_closePopup()
	local p = self._popup
	if not p then
		return
	end
	self._popup = nil
	self._popupJustClosed = true
	task.defer(function()
		self._popupJustClosed = false
	end)
	if p.OnClose then
		p.OnClose()
	end
	p.Holder:Destroy()
end

function Hub:Prompt(o)
	return dialog(self.Gui, self.Theme, o)
end

---------------------------------------------------------------- notifications: a slit that opens
--[[
	A notification starts as a thin vertical slit at the screen edge. The card opens out of
	it, the slit drains as the timer, and when it is empty the card closes back into the slit
	and the stack folds up. Hovering pauses the timer; clicking dismisses.
]]
function Hub:Notify(options)
	options = type(options) == "table" and options or { Title = tostring(options) }
	local theme = self.Theme
	local duration = options.Duration or 4
	local width = math.min(300, math.max(160, viewport().X / self._scale - 28))
	self._toastOrder = (self._toastOrder or 0) - 1
	local holder = create("Frame", {
		Name = "Toast",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(width, 0),
		LayoutOrder = self._toastOrder,
		Parent = self.Toasts,
	})
	local clip = create("Frame", {
		Name = "Clip",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 0),
		Size = UDim2.new(0, 0, 1, 0),
		ClipsDescendants = true,
		Parent = holder,
	})
	local card = create("TextButton", {
		Name = "Card",
		BackgroundColor3 = themeColor(theme, "Panel"),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -1, 0, 1),
		Size = UDim2.new(0, width - 8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = "",
		AutoButtonColor = false,
		Parent = clip,
	}, { corner(4), stroke(themeColor(theme, "PanelStroke")), padding(9, 14, 10, 12), list(Enum.FillDirection.Vertical, 3) })
	local titleRow = create("Frame", { Name = "Title", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16), Parent = card }, {
		list(Enum.FillDirection.Horizontal, 7, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
	})
	local icon = options.Icon and iconLabel(options.Icon, 14, theme.Text)
	if icon then
		icon.Parent = titleRow
	end
	text({ Parent = titleRow, Text = options.Title or self.Name, FontFace = inter(Enum.FontWeight.SemiBold), TextSize = 13, Size = UDim2.new(1, icon and -21 or 0, 0, 16), LayoutOrder = 2, TextTruncate = Enum.TextTruncate.AtEnd })
	if options.Content and options.Content ~= "" then
		text({
			Parent = card,
			Text = options.Content,
			TextSize = 12,
			TextColor3 = themeColor(theme, "SubText"),
			TextWrapped = true,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 2,
		})
	end
	local slit = create("Frame", {
		Name = "Slit",
		BackgroundColor3 = options.Tone or themeColor(theme, "Accent"),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 2, 0, 0),
		BorderSizePixel = 0,
		Parent = holder,
	}, { corner(1) })

	local closing = false
	local targetHeight, targetWidth = 0, 0
	local function fitToast()
		if self._destroyed or not holder.Parent or closing then return end
		local nextWidth = math.min(300, math.max(160, viewport().X / self._scale - 28))
		if nextWidth ~= width then
			width = nextWidth
			card.Size = UDim2.new(0, width - 8, 0, 0)
		end
		local h = math.max(37, math.ceil(card.AbsoluteSize.Y / self._scale) + 2)
		if h == targetHeight and width == targetWidth then return end
		targetHeight, targetWidth = h, width
		tween(holder, SETTLE, { Size = UDim2.fromOffset(width, h) })
	end
	-- Wrapped text and late font/layout updates can change AutomaticSize after creation.
	local sizeConn = card:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitToast)
	local viewportConn = self.Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitToast)
	local scaleConn = self.UIScale:GetPropertyChangedSignal("Scale"):Connect(fitToast)
	holder.Destroying:Connect(function()
		sizeConn:Disconnect()
		viewportConn:Disconnect()
		scaleConn:Disconnect()
	end)
	-- 1) the stack makes room, 2) the slit draws, 3) the card opens out of it
	fitToast()
	local draw = tween(slit, TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Size = UDim2.new(0, 2, 1, -6) })
	draw.Completed:Wait()
	if not holder.Parent then
		return
	end
	tween(clip, RISE, { Size = UDim2.new(1, -6, 1, 0) })

	local function close()
		if closing then
			return
		end
		closing = true
		tween(clip, FOLD, { Size = UDim2.new(0, 0, 1, 0) }).Completed:Wait()
		tween(slit, FOLD, { Size = UDim2.new(0, 2, 0, 0) }).Completed:Wait()
		tween(holder, FOLD, { Size = UDim2.fromOffset(width, 0) }).Completed:Wait()
		holder:Destroy()
	end
	-- the slit is the timer
	local timer = TweenService:Create(slit, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 2, 0, 0) })
	timer.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed then
			task.spawn(close)
		end
	end)
	task.delay(0.3, function()
		if not closing then
			timer:Play()
		end
	end)
	card.MouseEnter:Connect(function()
		if not closing then
			timer:Pause()
		end
	end)
	card.MouseLeave:Connect(function()
		if not closing then
			timer:Play()
		end
	end)
	card.MouseButton1Click:Connect(function()
		timer:Pause()
		task.spawn(close)
	end)
end

---------------------------------------------------------------- stealth
function Hub:SetStealth(on: boolean)
	on = on == true
	self.Stealth = on
	secureHubs[self] = on and true or nil
	queueSecureFont()
	if on then
		-- Inspect live instances too; startup mode is needed to avoid earlier loads.
		for _, hub in RiftUI.Hubs do
			for _, inst in hub.Gui:GetDescendants() do
				watchAsset(inst)
				if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then inst.Image = secureProperty("Image", inst.Image) end
				if inst:IsA("ImageButton") then inst.HoverImage = secureProperty("HoverImage", inst.HoverImage) inst.PressedImage = secureProperty("PressedImage", inst.PressedImage) end
				if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then inst.FontFace = secureProperty("FontFace", inst.FontFace) end
			end
		end
	end
	if self._stealthControl then self._stealthControl:Set(on, true) end
	if self._stealthStatus then self._stealthStatus:Set(on and "Script: On" or "Script: Off") end
end

---------------------------------------------------------------- tabs
local Tab = {}
Tab.__index = Tab

function Hub:Tab(options)
	options = type(options) == "table" and options or { Name = tostring(options) }
	local theme = self.Theme
	local tab = setmetatable({
		Hub = self,
		Name = options.Name or "Tab",
		Description = options.Description,
		Icon = options.Icon,
		Sections = {},
		Requires = requirementIds(options.Requires),
		_internal = options._internal,
		_count = 0,
	}, Tab)
	local order = options._order or (#self.Tabs + 1)

	local tile = create("TextButton", {
		Name = "Tile_" .. tab.Name,
		BackgroundColor3 = themeColor(theme, "TileActive"),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(40, 40),
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = order,
		Parent = self.Dock,
	}, { corner(9) })
	local tileStroke = stroke(themeColor(theme, "TileActiveStroke"), 1, 1)
	tileStroke.Parent = tile
	local press = create("UIScale", { Name = "Press", Scale = 1, Parent = tile })
	tab.Tile = tile
	tab.TileStroke = tileStroke
	local icon = iconLabel(tab.Icon, 19, theme.SubText, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Parent = tile,
	})
	tab.TileIcon = icon
	if not icon then
		text({
			Parent = tile,
			Text = string.upper(string.sub(tab.Name, 1, 1)),
			TextSize = 16,
			FontFace = inter(Enum.FontWeight.SemiBold),
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
	end
	tab.Indicator = create("Frame", {
		Name = "Active",
		BackgroundColor3 = themeColor(theme, "Text"),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 2),
		Size = UDim2.fromOffset(0, 2),
		BackgroundTransparency = 1,
		Parent = tile,
	}, { corner(1) })
	tab.Badge = create("Frame", {
		Name = "Badge",
		BackgroundColor3 = themeColor(theme, "Accent"),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 1, 0, -1),
		Size = UDim2.fromOffset(13, 13),
		Visible = false,
		ZIndex = 3,
		Parent = tile,
	}, { corner(7), stroke(themeColor(theme, "Panel"), 2) })
	tab.BadgeText = text({
		Parent = tab.Badge,
		AnchorPoint = Vector2.new(0.5, 0.5),
		-- At 9px Inter's digit ink sits slightly above/left of its line box centre.
		Position = UDim2.new(0.5, 0.5, 0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		TextSize = 9,
		FontFace = inter(Enum.FontWeight.Bold),
		TextColor3 = themeColor(theme, "AccentText"),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 4,
	})

	self:_connect(tab.BadgeText:GetPropertyChangedSignal("TextBounds"), function()
		tab.Badge.Size = UDim2.fromOffset(math.max(13, math.ceil(tab.BadgeText.TextBounds.X / self._scale) + 6), 13)
	end)

	self:_connect(tile.MouseEnter, function()
		if self._open ~= tab then
			tween(tile, FAST, { BackgroundColor3 = themeColor(theme, "TileHover"), BackgroundTransparency = 0 })
			if icon then
				tween(icon, FAST, { ImageColor3 = themeColor(theme, "Text") })
			end
		end
		self.TooltipText.Text = tab.Name
		local s = self._scale
		local tp, ts = tile.AbsolutePosition, tile.AbsoluteSize
		local dock = self.Dock
		self.Tooltip.Position = UDim2.fromOffset((tp.X + ts.X / 2) / s, (dock.AbsolutePosition.Y + dock.AbsoluteSize.Y + 6) / s)
		self.Tooltip.Visible = self._visible
	end)
	self:_connect(tile.MouseLeave, function()
		if self._open ~= tab then
			tween(tile, FAST, { BackgroundTransparency = 1 })
			if icon then
				tween(icon, FAST, { ImageColor3 = themeColor(theme, "SubText") })
			end
		end
		if self.TooltipText.Text == tab.Name then
			self.Tooltip.Visible = false
		end
		tween(press, FAST, { Scale = 1 })
	end)
	self:_connect(tile.MouseButton1Down, function()
		tween(press, FAST, { Scale = 0.92 })
	end)
	self:_connect(tile.MouseButton1Up, function()
		tween(press, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
	end)
	self:_connect(tile.MouseButton1Click, function()
		if self._open == tab then
			self:Close()
		else
			self:Open(tab)
		end
	end)

	local page = create("Frame", {
		Name = "Page_" .. tab.Name,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = self.Pages,
	})
	local scroll = create("ScrollingFrame", {
		Name = "Scroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = themeColor(theme, "Knob"),
		ScrollBarImageTransparency = 0.4,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = page,
	})
	local columns = create("Frame", {
		Name = "Columns",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = scroll,
	}, { padding(10, 16, 12, 16) })
	local function column(side: number)
		return create("Frame", {
			Name = side == 0 and "Left" or "Right",
			BackgroundTransparency = 1,
			Position = UDim2.new(side * 0.5, side == 0 and 0 or 9, 0, 0),
			Size = UDim2.new(0.5, -9, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = columns,
		}, { list(Enum.FillDirection.Vertical, 10) })
	end
	tab.Page = page
	tab.Scroll = scroll
	tab.Columns = { column(0), column(1), Frame = columns }
	self:_connect(columns:GetPropertyChangedSignal("AbsoluteSize"), function()
		if self._open == tab then self:_fitPanel(tab, false) end
	end)

	table.insert(self.Tabs, tab)
	self:_record(self, "Tab", options, tab)
	return tab
end

function Tab:_setActive(active: boolean)
	local theme = self.Hub.Theme
	tween(self.Tile, FAST, { BackgroundColor3 = themeColor(theme, "TileActive"), BackgroundTransparency = active and 0 or 1 })
	tween(self.TileStroke, FAST, { Transparency = active and 0 or 1 })
	if self.TileIcon then
		tween(self.TileIcon, FAST, { ImageColor3 = active and themeColor(theme, "Text") or themeColor(theme, "SubText") })
	end
	tween(self.Indicator, SETTLE, {
		Size = UDim2.fromOffset(active and 12 or 0, 2),
		BackgroundTransparency = active and 0 or 1,
	})
end

function Tab:_recount()
	local n = 0
	for _, s in self.Sections do
		for _, c in s.Controls do
			if c.Type == "Toggle" and c.Value == true and not c._internal then
				n += 1
			end
		end
	end
	self._count = n
	-- Counting enabled toggles is opt-in (CreateHub{ ToggleBadges = true }); unexplained
	-- numbers on the toolbar read as notifications.
	if self._badge == nil and self.Hub.Options.ToggleBadges then
		self.Badge.Visible = n > 0
		self.BadgeText.Text = tostring(n)
	end
end

-- Shows a small count or word on the toolbar tile, e.g. Tab:SetBadge(3) or Tab:SetBadge("New").
-- nil or 0 hides it.
function Tab:SetBadge(value)
	if value == 0 or value == "" then
		value = nil
	end
	self._badge = value
	self.Badge.Visible = value ~= nil
	self.BadgeText.Text = value ~= nil and tostring(value) or ""
	if value == nil then
		self:_recount()
	end
end

---------------------------------------------------------------- sections
local Section = {}
Section.__index = Section

function Tab:Section(options)
	options = type(options) == "table" and options or { Name = tostring(options) }
	local hub = self.Hub
	local theme = hub.Theme
	local side = options.Side
	if side == "Right" then
		side = 1
	elseif side == "Left" then
		side = 0
	else
		local left, right = 0, 0
		for _, s in self.Sections do
			if s.Side == 0 then
				left += 1
			else
				right += 1
			end
		end
		side = left <= right and 0 or 1
	end
	local section = setmetatable({
		Tab = self,
		Hub = hub,
		Name = options.Name or "Section",
		Side = side,
		Controls = {},
		Requires = mergedRequirements(self.Requires, options.Requires),
		Pinned = false,
		_internal = self._internal,
		_order = 0,
	}, Section)
	section.Id = self.Name .. "/" .. section.Name

	local frame = create("Frame", {
		Name = "Section_" .. section.Name,
		BackgroundColor3 = themeColor(theme, "Section"),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = #self.Sections + 1,
		Parent = self.Columns[side + 1],
	}, { padding(0, 2, 6, 2), list(Enum.FillDirection.Vertical, 0) })
	frame.BackgroundTransparency = 1
	local head = create("Frame", { Name = "Head", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), Parent = frame })
	-- the group title sits on a hairline that runs from the title to the pin, like an imgui groupbox
	local pinRoom = options.Pinnable == false and 0 or 24
	local rule = create("Frame", {
		Name = "Rule",
		BackgroundColor3 = themeColor(theme, "Divider"),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, -pinRoom, 0, 1),
		Parent = head,
	})
	-- Collapsible by default; the user's choice per section outlives the session.
	local collapsible = options.Collapsible ~= false
	local remembered = hub.SetupData and type(hub.SetupData.Collapsed) == "table" and hub.SetupData.Collapsed[section.Id]
	section._collapsible = collapsible
	section._collapsed = collapsible and (remembered == true or (remembered == nil and options.Collapsed == true))
	local titleChip = create("Frame", {
		Name = "Title",
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		ZIndex = 2,
		Parent = head,
	}, {
		padding(0, 8, 0, 0),
		create("UISizeConstraint", { MaxSize = Vector2.new(196, 26) }),
		list(Enum.FillDirection.Horizontal, 3, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
	})
	if collapsible then
		section._chevron = iconLabel("chevron-down", 12, theme.Muted, { Rotation = section._collapsed and -90 or 0, ZIndex = 3, Parent = titleChip })
	end
	section._titleLabel = text({
		Parent = titleChip,
		LayoutOrder = 1,
		Text = string.upper(section.Name),
		TextSize = 11,
		FontFace = inter(Enum.FontWeight.SemiBold),
		TextColor3 = themeColor(theme, "SubText"),
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
	})
	local function placeRule()
		local w = titleChip.AbsoluteSize.X / hub._scale
		rule.Position = UDim2.new(0, w, 0.5, 0)
		rule.Size = UDim2.new(1, -w - pinRoom, 0, 1)
	end
	hub:_connect(titleChip:GetPropertyChangedSignal("AbsoluteSize"), placeRule)
	placeRule()
	if collapsible then
		local toggle = create("TextButton", { Name = "Collapse", BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Size = UDim2.new(1, -pinRoom, 1, 0), ZIndex = 4, Parent = head })
		hub:_connect(toggle.MouseButton1Click, function() section:SetCollapsed(not section._collapsed) end)
		hub:_connect(toggle.MouseEnter, function()
			setThemed(section._titleLabel, "TextColor3", themeColor(theme, "Text"))
			if section._chevron then setThemed(section._chevron, "ImageColor3", themeColor(theme, "SubText")) end
		end)
		hub:_connect(toggle.MouseLeave, function()
			setThemed(section._titleLabel, "TextColor3", themeColor(theme, "SubText"))
			if section._chevron then setThemed(section._chevron, "ImageColor3", themeColor(theme, "Muted")) end
		end)
	end
	if options.Pinnable ~= false then
		local pin = create("TextButton", {
			Name = "Pin",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 4, 0.5, 0),
			Size = UDim2.fromOffset(22, 22),
			Text = "",
			AutoButtonColor = false,
			Parent = head,
		})
		local pinIcon = iconLabel("pin", 13, theme.Muted, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Parent = pin })
		if not pinIcon then
			text({ Parent = pin, Text = "Pin", TextSize = 10, TextColor3 = themeColor(theme, "Muted"), Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
		end
		hub:_connect(pin.MouseEnter, function()
			if pinIcon then
				setThemed(pinIcon, "ImageColor3", themeColor(theme, "Text"))
			end
		end)
		hub:_connect(pin.MouseLeave, function()
			if pinIcon then
				setThemed(pinIcon, "ImageColor3", themeColor(theme, "Muted"))
			end
		end)
		hub:_connect(pin.MouseButton1Click, function()
			section:Pin()
		end)
	end
	-- Rows sit in a clip that folds to the header when the section collapses.
	local clip = create("Frame", {
		Name = "RowsClip",
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = section._collapsed and Enum.AutomaticSize.None or Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = frame,
	})
	local rows = create("Frame", {
		Name = "Rows",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = clip,
	}, { list(Enum.FillDirection.Vertical, 0), padding(0, 1) })
	section._rowsClip = clip
	section.Frame = frame
	section.Head = head
	section.Rows = rows

	table.insert(self.Sections, section)
	hub:_record(self, "Section", options, section)
	return section
end

-- Fold the rows to the header, or open them. Search results peek inside collapsed sections
-- without changing the saved choice.
function Section:_applyCollapse(animate: boolean)
	local clip = self._rowsClip
	if not clip then return end
	local shut = self._collapsed and not self._peek
	if self._chevron then tween(self._chevron, FAST, { Rotation = shut and -90 or 0 }) end
	if self._clipTween then self._clipTween:Cancel() self._clipTween = nil end
	local function settle()
		clip.AutomaticSize = shut and Enum.AutomaticSize.None or Enum.AutomaticSize.Y
		clip.Size = UDim2.new(1, 0, 0, 0)
	end
	if not animate then settle() return end
	local scale = self.Hub._scale
	clip.AutomaticSize = Enum.AutomaticSize.None
	clip.Size = UDim2.new(1, 0, 0, clip.AbsoluteSize.Y / scale)
	local tw = tween(clip, SETTLE, { Size = UDim2.new(1, 0, 0, shut and 0 or self.Rows.AbsoluteSize.Y / scale) })
	self._clipTween = tw
	tw.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed and self._clipTween == tw then
			self._clipTween = nil
			settle()
		end
	end)
end

function Section:SetCollapsed(collapsed: boolean, instant: boolean?)
	if not self._collapsible or self._isGroup then return end
	collapsed = collapsed == true
	if self._collapsed == collapsed then return end
	self._collapsed = collapsed
	local hub = self.Hub
	local map = table.clone(hub.SetupData and type(hub.SetupData.Collapsed) == "table" and hub.SetupData.Collapsed or {})
	map[self.Id] = collapsed or nil
	hub:_savePref("Collapsed", map)
	self:_applyCollapse(not instant)
end

function Section:IsCollapsed(): boolean
	return self._collapsed == true
end

function Section:_row(height: number?, name: string?)
	local theme = self.Hub.Theme
	self._order += 1
	local first = #self.Controls == 0
	local row = create("Frame", {
		Name = name or "Row",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, height or 34),
		LayoutOrder = self._order,
		Parent = self.Rows,
	})
	create("Frame", {
		Name = "Divider",
		BackgroundColor3 = themeColor(theme, "Divider"),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 1),
		Visible = false,
		Parent = row,
	})
	local _ = first
	return row
end

-- Shared plumbing for every control: registry, flag, recipe, visibility, safe callbacks.
function Section:_control(kind: string, options, row: Frame, rawArgs)
	local control = {
		Type = kind,
		Name = options.Name or kind,
		Flag = options.Flag,
		Frame = row,
		Section = self,
		Callback = options.Callback or function() end,
		_internal = self._internal,
		_changed = {},
		Requires = mergedRequirements(self.Requires, options.Requires),
	}
	function control:IsAvailable() return self.Section.Hub:CanUse(self.Requires) end
	function control:OnChanged(fn)
		table.insert(self._changed, fn)
		return self
	end
	function control:SetVisible(v: boolean)
		self._hidden = not v
		self.Frame.Visible = v
	end
	function control:_emit(...)
		if not self:IsAvailable() then return false, select(2, self:IsAvailable()) end
		local args = table.pack(...)
		task.spawn(function()
			if not self:IsAvailable() then return end
			local ok, err = xpcall(self.Callback, debug.traceback, table.unpack(args, 1, args.n))
			if not ok then
				local message = string.match(tostring(err), "^[^\n]*")
				recordError(message, tostring(err), self.Name)
				warn("[RiftUI] " .. self.Name .. " callback error: " .. message)
				local hub = self.Section.Hub
				local now = os.clock()
				if not self._lastErrorToast or now - self._lastErrorToast > 4 then
					self._lastErrorToast = now
					hub:Notify({
						Title = self.Name .. " callback failed",
						Content = message,
						Tone = hub.Theme.Danger,
						Icon = "triangle-alert",
						Duration = 6,
					})
				end
			end
		end)
		for _, fn in self._changed do
			task.spawn(function() if self:IsAvailable() then fn(table.unpack(args, 1, args.n)) end end)
		end
	end
	if control.Flag then
		RiftUI.Flags[control.Flag] = control
	end
	-- these print Description under their name already; everything else shows it on hover
	local inline = { Toggle = true, Keybind = true, Dropdown = true, ColorPicker = true, Stepper = true, PlayerPicker = true }
	local tip = options.Tooltip or (not inline[kind] and options.Description)
	if type(tip) == "string" and tip ~= "" then
		control.Tooltip = tip
		self.Hub:_attachTip(row, tip)
	end
	table.insert(self.Controls, control)
	self.Hub:_record(self, kind, rawArgs or options, control)
	return control
end

function Section:_labels(row: Frame, name: string, description: string?, rightWidth: number)
	local theme = self.Hub.Theme
	local holder = create("Frame", {
		Name = "Labels",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -rightWidth - 8, 1, 0),
		Parent = row,
	}, { list(Enum.FillDirection.Vertical, 1, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
	local title = text({ Parent = holder, Name = "Title", Text = name, TextSize = 13, TextColor3 = themeColor(theme, "Text"), Size = UDim2.new(1, 0, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd })
	if description and description ~= "" then
		text({
			Parent = holder,
			Name = "Description",
			Text = description,
			TextSize = 11,
			TextColor3 = themeColor(theme, "Muted"),
			TextWrapped = true,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 2,
		})
		row.AutomaticSize = Enum.AutomaticSize.Y
		create("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), Parent = holder })
		holder.Size = UDim2.new(1, -rightWidth - 8, 0, 0)
		holder.AutomaticSize = Enum.AutomaticSize.Y
	end
	return title
end

---------------------------------------------------------------- Toggle
function Section:Toggle(options)
	local hub, theme = self.Hub, self.Hub.Theme
	local row = self:_row(34, "Toggle_" .. (options.Name or ""))
	local c = self:_control("Toggle", options, row)
	c.Value = options.Default == true
	local titleLabel = self:_labels(row, c.Name, options.Description, 24)
	local box = create("Frame", {
		Name = "Check",
		BackgroundColor3 = themeColor(theme, "Field"),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(16, 16),
		Parent = row,
	}, { corner(4) })
	local boxStroke = stroke(themeColor(theme, "FieldStroke"))
	boxStroke.Parent = box
	local pop = create("UIScale", { Name = "Pop", Parent = box })
	local mark = iconLabel("check", 12, theme.AccentText, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ImageTransparency = 1,
		Parent = box,
	})
	local hit = create("TextButton", { Name = "Hit", BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = row })

	local function render(animate: boolean)
		local on = c.Value
		local goals = { BackgroundColor3 = on and themeColor(theme, "Accent") or themeColor(theme, "Field") }
		if animate then
			tween(box, FAST, goals)
			tween(boxStroke, FAST, { Color = on and themeColor(theme, "Accent") or themeColor(theme, "FieldStroke") })
			if mark then
				tween(mark, FAST, { ImageTransparency = on and 0 or 1 })
			end
			if on then
				pop.Scale = 0.8
				tween(pop, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			end
		else
			setThemed(box, "BackgroundColor3", goals.BackgroundColor3)
			setThemed(boxStroke, "Color", on and themeColor(theme, "Accent") or themeColor(theme, "FieldStroke"))
			if mark then
				mark.ImageTransparency = on and 0 or 1
			end
		end
		if titleLabel then
			setThemed(titleLabel, "TextColor3", on and themeColor(theme, "Text") or themeColor(theme, "SubText"))
		end
	end
	hub:_connect(hit.MouseEnter, function()
		if not c.Value then
			tween(boxStroke, FAST, { Color = themeColor(theme, "Knob") })
		end
	end)
	hub:_connect(hit.MouseLeave, function()
		if not c.Value then
			tween(boxStroke, FAST, { Color = themeColor(theme, "FieldStroke") })
		end
	end)
	function c:Set(value: boolean, silent: boolean?)
		value = value == true
		if self.Value == value then
			return
		end
		self.Value = value
		render(true)
		self.Section.Tab:_recount()
		for _, fn in self._dependents or {} do
			task.spawn(fn, value)
		end
		if not silent then
			self:_emit(value)
		end
	end
	function c:Get()
		return self.Value
	end
	render(false)
	hub:_connect(hit.MouseButton1Click, function()
		c:Set(not c.Value)
	end)
	self.Tab:_recount()
	if c.Value and not hub._replaying then
		if #c.Requires > 0 and not c:IsAvailable() then c._pendingRequirementDefault = true else c:_emit(true) end
	end
	return self.Hub:_finishRequiredControl(c)
end

---------------------------------------------------------------- Button
function Section:Button(options)
	options = type(options) == "table" and options or { Name = tostring(options) }
	local hub, theme = self.Hub, self.Hub.Theme
	local row = self:_row(36, "Button_" .. (options.Name or ""))
	local c = self:_control("Button", options, row)
	local base = options.Danger and theme.Field or theme.Tile
	local btn = create("TextButton", {
		Name = "Button",
		BackgroundColor3 = base,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 28),
		Text = c.Name,
		FontFace = inter(Enum.FontWeight.Medium),
		TextSize = 13,
		TextColor3 = options.Danger and themeColor(theme, "Danger") or themeColor(theme, "Text"),
		AutoButtonColor = false,
		Parent = row,
	}, { corner(6), stroke(themeColor(theme, "TileStroke")) })
	local press = create("UIScale", { Name = "Press", Parent = btn })
	hub:_connect(btn.MouseEnter, function()
		tween(btn, FAST, { BackgroundColor3 = themeColor(theme, "TileHover") })
	end)
	hub:_connect(btn.MouseLeave, function()
		tween(btn, FAST, { BackgroundColor3 = base })
		tween(press, FAST, { Scale = 1 })
	end)
	hub:_connect(btn.MouseButton1Down, function()
		tween(press, FAST, { Scale = 0.97 })
	end)
	hub:_connect(btn.MouseButton1Up, function()
		tween(press, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
	end)
	if options.Window then
		c.Window = options.Window
		btn.TextXAlignment = Enum.TextXAlignment.Left
		padding(0, 30, 0, 10).Parent = btn
		iconLabel("chevron-right", 14, theme.SubText, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 20, 0.5, 0), Parent = btn })
	end
	hub:_connect(btn.MouseButton1Click, function()
		if not c:IsAvailable() then return end
		if c.Window then c.Window:Open() end
		c:_emit()
	end)
	function c:SetText(t: string)
		btn.Text = t
		self.Name = t
	end
	return self.Hub:_finishRequiredControl(c)
end

---------------------------------------------------------------- Slider
function Section:Slider(options)
	local hub, theme = self.Hub, self.Hub.Theme
	local min, max = options.Min or 0, options.Max or 100
	local step = options.Step or options.Increment or 1
	local suffix = options.Suffix or ""
	local row = self:_row(46, "Slider_" .. (options.Name or ""))
	local c = self:_control("Slider", options, row)
	c.Min, c.Max, c.Step = min, max, step
	c.Value = math.clamp(round(options.Default or min, step), min, max)

	text({ Parent = row, Name = "Title", Text = c.Name, TextSize = 13, Position = UDim2.fromOffset(0, 7), Size = UDim2.new(1, -80, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd })
	local box = create("TextBox", {
		Name = "Value",
		BackgroundColor3 = themeColor(theme, "Field"),
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 4),
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		FontFace = MONO,
		TextSize = 12,
		TextColor3 = themeColor(theme, "SubText"),
		TextXAlignment = Enum.TextXAlignment.Right,
		ClearTextOnFocus = false,
		Text = "",
		Parent = row,
	}, { corner(5), padding(0, 6), create("UISizeConstraint", { MinSize = Vector2.new(30, 22) }) })
	local track = create("Frame", {
		Name = "Track",
		BackgroundColor3 = themeColor(theme, "Track"),
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 34),
		Size = UDim2.new(1, 0, 0, 2),
		Parent = row,
	}, { corner(1) })
	local fill = create("Frame", { Name = "Fill", BackgroundColor3 = themeColor(theme, "Accent"), BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = track }, { corner(1) })
	local knob = create("Frame", {
		Name = "Notch",
		BackgroundColor3 = themeColor(theme, "Accent"),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(4, 14),
		ZIndex = 2,
		Parent = track,
	}, { corner(2) })
	local grow = create("UIScale", { Name = "Grow", Parent = knob })
	local hit = create("TextButton", {
		Name = "Hit",
		BackgroundTransparency = 1,
		Text = "",
		Position = UDim2.fromOffset(-6, 24),
		Size = UDim2.new(1, 12, 0, 22),
		ZIndex = 3,
		Parent = row,
	})

	local function render()
		local a = (max > min) and (c.Value - min) / (max - min) or 0
		fill.Size = UDim2.fromScale(a, 1)
		knob.Position = UDim2.fromScale(a, 0.5)
		if not box:IsFocused() then
			box.Text = formatNumber(c.Value, step) .. suffix
		end
	end
	function c:Set(value: number, silent: boolean?)
		value = math.clamp(round(tonumber(value) or min, step), min, max)
		if self.Value == value then
			render()
			return
		end
		self.Value = value
		render()
		if not silent then
			self:_emit(value)
		end
	end
	function c:Get()
		return self.Value
	end
	render()

	local dragging = false
	local function fromX(x: number)
		local p, s = track.AbsolutePosition, track.AbsoluteSize
		if s.X <= 0 then
			return
		end
		c:Set(min + (max - min) * math.clamp((x - p.X) / s.X, 0, 1))
	end
	hub:_connect(hit.InputBegan, function(input)
		if isPointer(input) then
			dragging = true
			tween(grow, SETTLE, { Scale = 1.25 })
			fromX(input.Position.X)
		end
	end)
	hub:_connect(UserInputService.InputChanged, function(input)
		if dragging and isMove(input) then
			fromX(input.Position.X)
		end
	end)
	hub:_connect(UserInputService.InputEnded, function(input)
		if dragging and isPointer(input) then
			dragging = false
			tween(grow, SETTLE, { Scale = 1 })
		end
	end)
	hub:_connect(box.Focused, function()
		box.Text = formatNumber(c.Value, step)
		box.BackgroundTransparency = 0
		setThemed(box, "TextColor3", themeColor(theme, "Text"))
	end)
	hub:_connect(box.FocusLost, function()
		box.BackgroundTransparency = 1
		setThemed(box, "TextColor3", themeColor(theme, "SubText"))
		local n = tonumber((string.gsub(box.Text, "[^%d%.%-]", "")))
		if n then
			c:Set(n)
		end
		render()
	end)
	return self.Hub:_finishRequiredControl(c)
end

---------------------------------------------------------------- Dropdown
function Section:Dropdown(options)
	local hub, theme = self.Hub, self.Hub.Theme
	local multi = options.Multi == true
	local row = self:_row(34, "Dropdown_" .. (options.Name or ""))
	local c = self:_control("Dropdown", options, row)
	c.Options = table.clone(options.Options or options.Values or {})
	c.Multi = multi
	if multi then
		c.Value = {}
		for _, v in (type(options.Default) == "table" and options.Default or {}) do
			c.Value[v] = true
		end
	else
		c.Value = options.Default or c.Options[1]
	end
	self:_labels(row, c.Name, options.Description, 96)
	local chip = create("TextButton", {
		Name = "Chip",
		BackgroundColor3 = themeColor(theme, "Field"),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "",
		AutoButtonColor = false,
		Parent = row,
	}, {
		corner(6),
		stroke(themeColor(theme, "FieldStroke")),
		padding(0, 6, 0, 8),
		list(Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
		create("UISizeConstraint", { MaxSize = Vector2.new(120, 24) }),
	})
	local label = text({
		Parent = chip,
		Name = "Value",
		TextSize = 12,
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	create("UISizeConstraint", { MaxSize = Vector2.new(90, 24), Parent = label })
	if not iconLabel("chevron-down", 14, theme.SubText, { LayoutOrder = 2, Parent = chip }) then
		text({ Parent = chip, Text = "v", TextSize = 11, TextColor3 = themeColor(theme, "SubText"), Size = UDim2.fromOffset(10, 24), LayoutOrder = 2 })
	end

	local function display(): string
		if multi then
			local picked = {}
			for _, o in c.Options do
				if c.Value[o] then
					table.insert(picked, tostring(o))
				end
			end
			if #picked == 0 then
				return "None"
			elseif #picked > 2 then
				return #picked .. " selected"
			end
			return table.concat(picked, ", ")
		end
		return c.Value ~= nil and tostring(c.Value) or "None"
	end
	local function render()
		label.Text = display()
	end
	function c:Set(value, silent: boolean?)
		if multi then
			local set = {}
			if type(value) == "table" then
				for k, v in value do
					if type(k) == "number" then
						set[v] = true
					elseif v then
						set[k] = true
					end
				end
			end
			self.Value = set
		else
			self.Value = value
		end
		render()
		if not silent then
			self:_emit(self.Value)
		end
	end
	function c:Get()
		return self.Value
	end
	function c:SetOptions(newOptions: { any })
		self.Options = table.clone(newOptions)
		render()
	end
	render()

	hub:_connect(chip.MouseButton1Click, function()
		if hub._popup and hub._popup.Anchor == chip then
			hub:_closePopup()
			return
		end
		local count = #c.Options
		local searchable = count > 8
		local itemH = 28
		local h = math.max(1, math.min(count, 7)) * itemH + 8 + (searchable and 34 or 0)
		local frame = create("Frame", {
			Name = "DropdownList",
			BackgroundColor3 = themeColor(theme, "Panel"),
			Size = UDim2.fromOffset(190, h),
			ZIndex = 41,
		}, { corner(10), stroke(themeColor(theme, "PanelStroke")), padding(4) })
		local search
		if searchable then
			search = create("TextBox", {
				Name = "Filter",
				BackgroundColor3 = themeColor(theme, "Field"),
				Size = UDim2.new(1, 0, 0, 28),
				PlaceholderText = "Filter",
				PlaceholderColor3 = themeColor(theme, "Muted"),
				Text = "",
				FontFace = inter(),
				TextSize = 12,
				TextColor3 = themeColor(theme, "Text"),
				TextXAlignment = Enum.TextXAlignment.Left,
				ClearTextOnFocus = false,
				ZIndex = 42,
				Parent = frame,
			}, { corner(6), padding(0, 8) })
		end
		local scroll = create("ScrollingFrame", {
			Name = "Items",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, searchable and 34 or 0),
			Size = UDim2.new(1, 0, 1, searchable and -34 or 0),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 2,
			ScrollBarImageColor3 = themeColor(theme, "Knob"),
			ZIndex = 42,
			Parent = frame,
		}, { list(Enum.FillDirection.Vertical, 0) })
		if count == 0 then
			text({ Parent = scroll, Text = "No options", TextColor3 = themeColor(theme, "Muted"), Size = UDim2.new(1, 0, 0, itemH), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 43 })
		end
		local items = {}
		for i, opt in c.Options do
			local selected = if multi then c.Value[opt] == true else c.Value == opt
			local item = create("TextButton", {
				Name = "Item",
				BackgroundColor3 = themeColor(theme, "Tile"),
				BackgroundTransparency = selected and 0 or 1,
				Size = UDim2.new(1, 0, 0, itemH),
				Text = "",
				AutoButtonColor = false,
				LayoutOrder = i,
				ZIndex = 43,
				Parent = scroll,
			}, { corner(6), padding(0, 8) })
			text({ Parent = item, Text = tostring(opt), TextSize = 13, Size = UDim2.new(1, -20, 1, 0), ZIndex = 44, TextTruncate = Enum.TextTruncate.AtEnd })
			local check = iconLabel("check", 14, theme.Text, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.fromScale(1, 0.5),
				Visible = selected,
				ZIndex = 44,
				Parent = item,
			})
			items[opt] = item
			item.MouseEnter:Connect(function()
				tween(item, FAST, { BackgroundTransparency = 0 })
			end)
			item.MouseLeave:Connect(function()
				local on = if multi then c.Value[opt] == true else c.Value == opt
				tween(item, FAST, { BackgroundTransparency = on and 0 or 1 })
			end)
			item.MouseButton1Click:Connect(function()
				if multi then
					local v = table.clone(c.Value)
					v[opt] = not v[opt] or nil
					c:Set(v)
					if check then
						check.Visible = v[opt] == true
					end
				else
					c:Set(opt)
					hub:_closePopup()
				end
			end)
		end
		if search then
			search:GetPropertyChangedSignal("Text"):Connect(function()
				local q = string.lower(search.Text)
				for opt, item in items do
					item.Visible = q == "" or string.find(string.lower(tostring(opt)), q, 1, true) ~= nil
				end
			end)
		end
		hub:_openPopup(chip, frame)
	end)
	return self.Hub:_finishRequiredControl(c)
end

---------------------------------------------------------------- Input
function Section:Input(options)
	local hub, theme = self.Hub, self.Hub.Theme
	-- MultiLine grows the field to Lines rows of wrapped text; Enter then starts a new line
	-- and the value commits when focus leaves.
	local multi = options.MultiLine == true
	local mono = options.Numeric or options.Code
	local textSize = options.Code and 12 or 13
	local boxHeight = multi and (math.clamp(math.floor(options.Lines or 4), 2, 20) * math.ceil(textSize * 1.25) + 12) or 26
	local row = self:_row(boxHeight + 32, "Input_" .. (options.Name or ""))
	local c = self:_control("Input", options, row)
	c.Value = options.Default or ""
	c.MultiLine = multi
	text({ Parent = row, Name = "Title", Text = c.Name, TextSize = 13, Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 16) })
	local box = create("TextBox", {
		Name = "Box",
		BackgroundColor3 = themeColor(theme, "Field"),
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 0, boxHeight),
		FontFace = mono and MONO or inter(),
		TextSize = textSize,
		TextColor3 = themeColor(theme, "Text"),
		PlaceholderText = options.Placeholder or "",
		PlaceholderColor3 = themeColor(theme, "Muted"),
		Text = c.Value,
		ClearTextOnFocus = options.ClearOnFocus == true,
		MultiLine = multi,
		TextWrapped = multi,
		ClipsDescendants = multi,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = multi and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
		Parent = row,
	}, { corner(6), multi and padding(6, 8) or padding(0, 8) })
	local boxStroke = stroke(themeColor(theme, "FieldStroke"))
	boxStroke.Parent = box
	function c:Set(value: string, silent: boolean?)
		value = tostring(value or "")
		if options.Numeric then
			value = string.gsub(value, "[^%d%.%-]", "")
		elseif not multi then
			value = string.gsub(value, "[\r\n]+", " ")
		end
		if type(options.MaxLength) == "number" and utf8.len(value) and utf8.len(value) > options.MaxLength then
			value = string.sub(value, 1, (utf8.offset(value, options.MaxLength + 1) or (#value + 1)) - 1)
		end
		self.Value = value
		box.Text = value
		if not silent then
			self:_emit(value)
		end
	end
	function c:Get()
		return self.Value
	end
	hub:_connect(box.Focused, function()
		tween(boxStroke, FAST, { Color = themeColor(theme, "SubText") })
	end)
	hub:_connect(box.FocusLost, function(enter)
		tween(boxStroke, FAST, { Color = themeColor(theme, "FieldStroke") })
		if options.Finished == false or enter or box.Text ~= c.Value then
			c:Set(box.Text)
		end
	end)
	if options.Finished == false then
		hub:_connect(box:GetPropertyChangedSignal("Text"), function()
			if box:IsFocused() then
				c:Set(box.Text)
			end
		end)
	end
	return self.Hub:_finishRequiredControl(c)
end

---------------------------------------------------------------- Keybind
function Section:Keybind(options)
	local hub, theme = self.Hub, self.Hub.Theme
	local row = self:_row(34, "Keybind_" .. (options.Name or ""))
	local c = self:_control("Keybind", options, row)
	c.Value = options.Default
	c.Mode = options.Mode or "Toggle" -- Toggle, Hold, Always
	c.State = c.Mode == "Always"
	c.ChangedCallback = options.ChangedCallback
	local labels = self:_labels(row, c.Name, options.Description, 90).Parent
	local chip = create("TextButton", {
		Name = "Key",
		BackgroundColor3 = themeColor(theme, "Field"),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		FontFace = MONO,
		TextSize = 11,
		TextColor3 = themeColor(theme, "Text"),
		Text = "",
		AutoButtonColor = false,
		Parent = row,
	}, { corner(6), stroke(themeColor(theme, "FieldStroke")), padding(0, 8), create("UISizeConstraint", { MinSize = Vector2.new(40, 24) }) })
	-- The label gets whatever the key chip leaves, so short keys don't truncate long names.
	local function fitLabels()
		local w = chip.AbsoluteSize.X / hub._scale
		labels.Size = UDim2.new(1, -math.ceil(w) - 10, labels.Size.Y.Scale, labels.Size.Y.Offset)
	end
	hub:_connect(chip:GetPropertyChangedSignal("AbsoluteSize"), fitLabels)
	local listening = false
	local function render()
		if listening then
			chip.Text = "Press a key…"
			setThemed(chip, "BackgroundColor3", themeColor(theme, "Accent"))
			setThemed(chip, "TextColor3", themeColor(theme, "AccentText"))
		else
			chip.Text = keyName(c.Value)
			setThemed(chip, "BackgroundColor3", themeColor(theme, "Field"))
			setThemed(chip, "TextColor3", themeColor(theme, "Text"))
		end
	end
	function c:Set(key, silent: boolean?)
		if type(key) == "string" then
			local ok, item = pcall(function()
				return Enum.KeyCode[key]
			end)
			if not ok then
				ok, item = pcall(function()
					return Enum.UserInputType[key]
				end)
			end
			key = ok and item or nil
		end
		self.Value = key
		render()
		hub:_keybindsChanged()
		if not silent and self.ChangedCallback then
			task.spawn(self.ChangedCallback, key)
		end
	end
	function c:Get()
		return self.Value
	end
	render()

	hub:_connect(chip.MouseButton1Click, function()
		listening = true
		hub._listening = true
		render()
	end)
	local function matches(input: InputObject): boolean
		local v = c.Value
		if v == nil then
			return false
		end
		if v.EnumType == Enum.KeyCode then
			return input.KeyCode == v
		end
		return input.UserInputType == v
	end
	hub:_connect(UserInputService.InputBegan, function(input)
		if not c:IsAvailable() then
			if listening then listening = false hub._listening = false render() end
			return
		end
		if listening then
			local key
			if input.UserInputType == Enum.UserInputType.Keyboard then
				key = input.KeyCode
				if key == Enum.KeyCode.Escape or key == Enum.KeyCode.Backspace then
					key = nil
				end
			elseif input.UserInputType == Enum.UserInputType.MouseButton2 or input.UserInputType == Enum.UserInputType.MouseButton3 then
				key = input.UserInputType
			else
				return
			end
			listening = false
			task.defer(function()
				hub._listening = false
			end)
			c:Set(key)
			return
		end
		if UserInputService:GetFocusedTextBox() or not matches(input) then
			return
		end
		if c.Mode == "Toggle" then
			c.State = not c.State
			c:_emit(c.State)
		elseif c.Mode == "Hold" then
			c.State = true
			c:_emit(true)
		elseif c.Mode == "Always" then
			c:_emit(true)
		end
		hub:_keybindsChanged()
	end)
	hub:_connect(UserInputService.InputEnded, function(input)
		if c.Mode == "Hold" and c.State and matches(input) then
			c.State = false
			c:_emit(false)
			hub:_keybindsChanged()
		end
	end)
	return self.Hub:_finishRequiredControl(c)
end

---------------------------------------------------------------- ColorPicker
function Section:ColorPicker(options)
	local hub, theme = self.Hub, self.Hub.Theme
	local row = self:_row(34, "Color_" .. (options.Name or ""))
	local c = self:_control("ColorPicker", options, row)
	c.Value = options.Default or rgb(255, 255, 255)
	self:_labels(row, c.Name, options.Description, 44)
	local swatch = create("TextButton", {
		Name = "Swatch",
		BackgroundColor3 = c.Value,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(36, 20),
		Text = "",
		AutoButtonColor = false,
		Parent = row,
	}, { corner(6), stroke(themeColor(theme, "FieldStroke")) })
	swatch:SetAttribute("ThemeSwatch", true)
	local h, s, v = c.Value:ToHSV()
	local update
	function c:Set(color: Color3, silent: boolean?)
		self.Value = color
		setThemed(swatch, "BackgroundColor3", color)
		if update then
			update()
		end
		if not silent then
			self:_emit(color)
		end
	end
	function c:Get()
		return self.Value
	end

	hub:_connect(swatch.MouseButton1Click, function()
		if hub._popup and hub._popup.Anchor == swatch then
			hub:_closePopup()
			return
		end
		h, s, v = c.Value:ToHSV()
		local frame = create("Frame", {
			Name = "ColorPicker",
			BackgroundColor3 = themeColor(theme, "Panel"),
			Size = UDim2.fromOffset(212, 214),
			ZIndex = 41,
		}, { corner(12), stroke(themeColor(theme, "PanelStroke")), padding(10) })
		local sv = create("TextButton", {
			Name = "SaturationValue",
			BackgroundColor3 = Color3.fromHSV(h, 1, 1),
			Size = UDim2.new(1, 0, 0, 140),
			Text = "",
			AutoButtonColor = false,
			ZIndex = 42,
			Parent = frame,
		}, { corner(8) })
		create("Frame", { Name = "White", BackgroundColor3 = rgb(255, 255, 255), Size = UDim2.fromScale(1, 1), ZIndex = 43, Parent = sv }, {
			corner(8),
			create("UIGradient", { Transparency = NumberSequence.new(0, 1) }),
		})
		create("Frame", { Name = "Black", BackgroundColor3 = rgb(0, 0, 0), Size = UDim2.fromScale(1, 1), ZIndex = 44, Parent = sv }, {
			corner(8),
			create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0) }),
		})
		local svKnob = create("Frame", {
			Name = "Knob",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(12, 12),
			ZIndex = 45,
			Parent = sv,
		}, { corner(6), create("UIStroke", { Color = rgb(255, 255, 255), Thickness = 2 }) })
		local hue = create("TextButton", {
			Name = "Hue",
			BackgroundColor3 = rgb(255, 255, 255),
			Position = UDim2.fromOffset(0, 150),
			Size = UDim2.new(1, 0, 0, 12),
			Text = "",
			AutoButtonColor = false,
			ZIndex = 42,
			Parent = frame,
		}, {
			corner(6),
			create("UIGradient", {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, rgb(255, 0, 0)),
					ColorSequenceKeypoint.new(1 / 6, rgb(255, 255, 0)),
					ColorSequenceKeypoint.new(2 / 6, rgb(0, 255, 0)),
					ColorSequenceKeypoint.new(3 / 6, rgb(0, 255, 255)),
					ColorSequenceKeypoint.new(4 / 6, rgb(0, 0, 255)),
					ColorSequenceKeypoint.new(5 / 6, rgb(255, 0, 255)),
					ColorSequenceKeypoint.new(1, rgb(255, 0, 0)),
				}),
			}),
		})
		local hueKnob = create("Frame", {
			Name = "Knob",
			BackgroundColor3 = rgb(255, 255, 255),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(6, 16),
			ZIndex = 43,
			Parent = hue,
		}, { corner(3) })
		local hex = create("TextBox", {
			Name = "Hex",
			BackgroundColor3 = themeColor(theme, "Field"),
			Position = UDim2.fromOffset(0, 172),
			Size = UDim2.new(1, -42, 0, 26),
			FontFace = MONO,
			TextSize = 12,
			TextColor3 = themeColor(theme, "Text"),
			Text = "",
			ClearTextOnFocus = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 42,
			Parent = frame,
		}, { corner(6), stroke(themeColor(theme, "FieldStroke")), padding(0, 8) })
		local preview = create("Frame", {
			Name = "Preview",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 172),
			Size = UDim2.fromOffset(34, 26),
			ZIndex = 42,
			Parent = frame,
		}, { corner(6), stroke(themeColor(theme, "FieldStroke")) })

		update = function()
			local col = c.Value
			setThemed(sv, "BackgroundColor3", Color3.fromHSV(h, 1, 1))
			svKnob.Position = UDim2.fromScale(s, 1 - v)
			hueKnob.Position = UDim2.fromScale(h, 0.5)
			setThemed(preview, "BackgroundColor3", col)
			if not hex:IsFocused() then
				hex.Text = "#" .. col:ToHex()
			end
		end
		local drag = nil
		local function apply(pos: Vector2)
			if drag == "sv" then
				local p, sz = sv.AbsolutePosition, sv.AbsoluteSize
				s = math.clamp((pos.X - p.X) / sz.X, 0, 1)
				v = 1 - math.clamp((pos.Y - p.Y) / sz.Y, 0, 1)
			elseif drag == "hue" then
				local p, sz = hue.AbsolutePosition, hue.AbsoluteSize
				h = math.clamp((pos.X - p.X) / sz.X, 0, 0.999)
			end
			c:Set(Color3.fromHSV(h, s, v))
		end
		local conns = {
			sv.InputBegan:Connect(function(input)
				if isPointer(input) then
					drag = "sv"
					apply(Vector2.new(input.Position.X, input.Position.Y))
				end
			end),
			hue.InputBegan:Connect(function(input)
				if isPointer(input) then
					drag = "hue"
					apply(Vector2.new(input.Position.X, input.Position.Y))
				end
			end),
			UserInputService.InputChanged:Connect(function(input)
				if drag and isMove(input) then
					apply(Vector2.new(input.Position.X, input.Position.Y))
				end
			end),
			UserInputService.InputEnded:Connect(function(input)
				if isPointer(input) then
					drag = nil
				end
			end),
			hex.FocusLost:Connect(function()
				local ok, col = pcall(Color3.fromHex, hex.Text)
				if ok then
					h, s, v = col:ToHSV()
					c:Set(col)
				end
				update()
			end),
		}
		update()
		swatch:SetAttribute("ThemeSwatch", true)
		hub:_openPopup(swatch, frame, function()
			update = nil
			for _, conn in conns do
				conn:Disconnect()
			end
		end)
	end)
	return self.Hub:_finishRequiredControl(c)
end

---------------------------------------------------------------- Label / Paragraph / info rows
function Section:Label(textValue: string)
	local theme = self.Hub.Theme
	local row = self:_row(30, "Label")
	local c = self:_control("Label", { Name = textValue }, row, textValue)
	local label = text({ Parent = row, Text = textValue, TextSize = 13, TextColor3 = themeColor(theme, "SubText"), Size = UDim2.fromScale(1, 1), TextWrapped = true })
	function c:Set(t: string)
		label.Text = t
		self.Name = t
	end
	return self.Hub:_finishRequiredControl(c)
end

function Section:Paragraph(options)
	local theme = self.Hub.Theme
	local row = self:_row(0, "Paragraph")
	row.AutomaticSize = Enum.AutomaticSize.Y
	local c = self:_control("Paragraph", { Name = options.Title }, row, options)
	local holder = create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = row }, {
		list(Enum.FillDirection.Vertical, 3),
		create("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 9) }),
	})
	local title = text({ Parent = holder, Text = options.Title or "", Visible = options.Title ~= nil and options.Title ~= "", TextSize = 13, FontFace = inter(Enum.FontWeight.Medium), Size = UDim2.new(1, 0, 0, 16) })
	local body = text({
		Parent = holder,
		Text = options.Content or "",
		TextSize = 12,
		TextColor3 = themeColor(theme, "SubText"),
		TextWrapped = true,
		RichText = options.RichText == true,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
	})
	function c:Set(newTitle: string?, content: string?)
		if newTitle then
			title.Text = newTitle
			title.Visible = newTitle ~= ""
		end
		if content then
			body.Text = content
		end
	end
	return self.Hub:_finishRequiredControl(c)
end

-- A label with a quiet value on the right. With onClick the value is a button that still
-- reads as plain text (the version line in Settings › RiftUI).
function Section:_info(name: string, value: string, onClick)
	local theme = self.Hub.Theme
	local row = self:_row(30, "Info_" .. name)
	local c = self:_control("Info", { Name = name }, row)
	text({ Parent = row, Text = name, TextSize = 13, Size = UDim2.new(0.5, 0, 1, 0) })
	local valueLabel = create(onClick and "TextButton" or "TextLabel", {
		Name = "Value",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.5, 0, 1, 0),
		Text = value,
		FontFace = MONO,
		TextSize = 12,
		TextColor3 = themeColor(theme, "SubText"),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
	if onClick then
		valueLabel.AutoButtonColor = false
		self.Hub:_connect(valueLabel.MouseButton1Click, onClick)
	end
	function c:Set(v: string)
		valueLabel.Text = v
	end
	return self.Hub:_finishRequiredControl(c)
end

---------------------------------------------------------------- Group (dependent controls)
--[[
	A group indents a few controls under a parent toggle. It folds shut when the parent turns
	off and opens when it turns on; its header still opens it by hand so the settings can be
	prepared before switching the feature on.
]]
function Section:Group(options)
	options = type(options) == "table" and options or { Name = tostring(options) }
	local hub, theme = self.Hub, self.Hub.Theme
	local parent = options.DependsOn
	local row = self:_row(0, "Group_" .. (options.Name or ""))
	row.AutomaticSize = Enum.AutomaticSize.Y
	local head = create("TextButton", { Name = "GroupHead", BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Size = UDim2.new(1, 0, 0, 26), Parent = row })
	local chevron = iconLabel("chevron-right", 13, theme.SubText, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Parent = head })
	local title = text({ Parent = head, Text = options.Name or "Options", TextSize = 12, FontFace = inter(Enum.FontWeight.Medium), TextColor3 = themeColor(theme, "SubText"), Position = UDim2.fromOffset(18, 0), Size = UDim2.new(1, -18, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd })
	local clip = create("Frame", { Name = "GroupClip", BackgroundTransparency = 1, ClipsDescendants = true, Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 0), Parent = row })
	local body = create("Frame", { Name = "GroupBody", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = clip }, {
		padding(0, 0, 4, 14), list(Enum.FillDirection.Vertical, 0),
	})
	create("Frame", { Name = "Guide", BackgroundColor3 = themeColor(theme, "Divider"), BorderSizePixel = 0, Position = UDim2.fromOffset(6, 0), Size = UDim2.new(0, 1, 1, -6), Parent = clip })
	-- Pad the row so the clip's height counts toward the section.
	local spacer = create("Frame", { Name = "GroupSpace", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 0), Parent = row })

	local group = setmetatable({
		Hub = hub, Tab = self.Tab, Name = options.Name or "Options", Parent = self,
		Controls = self.Controls, Rows = body, Frame = self.Frame, Pinned = false,
		Requires = mergedRequirements(self.Requires, options.Requires),
		_internal = self._internal, _order = 0, _isGroup = true,
	}, Section)
	group.Id = self.Id .. "/" .. group.Name
	local open = false
	local function setHeight(h, animate)
		if animate then
			tween(clip, SETTLE, { Size = UDim2.new(1, 0, 0, h) })
			tween(spacer, SETTLE, { Size = UDim2.new(1, 0, 0, h) })
		else
			clip.Size = UDim2.new(1, 0, 0, h)
			spacer.Size = UDim2.new(1, 0, 0, h)
		end
	end
	local function contentHeight()
		return body.AbsoluteSize.Y / hub._scale
	end
	function group:SetOpen(on: boolean, instant: boolean?)
		open = on == true
		if chevron then tween(chevron, FAST, { Rotation = open and 90 or 0 }) end
		setThemed(title, "TextColor3", themeColor(theme, open and "Text" or "SubText"))
		setHeight(open and contentHeight() or 0, not instant)
	end
	function group:IsOpen()
		return open
	end
	hub:_connect(body:GetPropertyChangedSignal("AbsoluteSize"), function()
		if open then setHeight(contentHeight(), false) end
	end)
	hub:_connect(head.MouseButton1Click, function() group:SetOpen(not open) end)
	hub:_connect(head.MouseEnter, function() if not open then setThemed(title, "TextColor3", themeColor(theme, "Text")) end end)
	hub:_connect(head.MouseLeave, function() if not open then setThemed(title, "TextColor3", themeColor(theme, "SubText")) end end)
	if parent and parent.Value ~= nil then
		parent._dependents = parent._dependents or {}
		table.insert(parent._dependents, function(v) group:SetOpen(v == true) end)
		open = parent.Value == true
	else
		open = options.Open == true
	end
	task.defer(function() group:SetOpen(open, true) end)
	hub:_record(self, "Group", options, group)
	return group
end

---------------------------------------------------------------- RangeSlider
function Section:RangeSlider(options)
	local hub, theme = self.Hub, self.Hub.Theme
	local min, max = options.Min or 0, options.Max or 100
	local step = options.Step or 1
	local suffix = options.Suffix or ""
	local row = self:_row(46, "Range_" .. (options.Name or ""))
	local c = self:_control("RangeSlider", options, row)
	c.Min, c.Max, c.Step = min, max, step
	local d = options.Default or { min, max }
	local function clean(lo, hi)
		lo = math.clamp(round(tonumber(lo) or min, step), min, max)
		hi = math.clamp(round(tonumber(hi) or max, step), min, max)
		if lo > hi then lo, hi = hi, lo end
		return lo, hi
	end
	local lo0, hi0 = clean(d[1] or d.Min, d[2] or d.Max)
	c.Value = { Min = lo0, Max = hi0 }
	text({ Parent = row, Name = "Title", Text = c.Name, TextSize = 13, Position = UDim2.fromOffset(0, 7), Size = UDim2.new(1, -110, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd })
	local readout = text({ Parent = row, Name = "Value", Text = "", FontFace = MONO, TextSize = 12, TextColor3 = themeColor(theme, "SubText"), TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 7), Size = UDim2.fromOffset(110, 16) })
	local track = create("Frame", { Name = "Track", BackgroundColor3 = themeColor(theme, "Track"), BorderSizePixel = 0, Position = UDim2.new(0, 0, 0, 34), Size = UDim2.new(1, 0, 0, 2), Parent = row }, { corner(1) })
	local fill = create("Frame", { Name = "Fill", BackgroundColor3 = themeColor(theme, "Accent"), BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = track }, { corner(1) })
	local function notch(name)
		local k = create("Frame", { Name = name, BackgroundColor3 = themeColor(theme, "Accent"), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(4, 14), ZIndex = 2, Parent = track }, { corner(2) })
		return k, create("UIScale", { Parent = k })
	end
	local lowKnob, lowGrow = notch("Low")
	local highKnob, highGrow = notch("High")
	local hit = create("TextButton", { Name = "Hit", BackgroundTransparency = 1, Text = "", Position = UDim2.fromOffset(-6, 24), Size = UDim2.new(1, 12, 0, 22), ZIndex = 3, Parent = row })
	local function frac(v) return (max > min) and (v - min) / (max - min) or 0 end
	local function render()
		local a, b = frac(c.Value.Min), frac(c.Value.Max)
		fill.Position = UDim2.fromScale(a, 0)
		fill.Size = UDim2.fromScale(b - a, 1)
		lowKnob.Position = UDim2.fromScale(a, 0.5)
		highKnob.Position = UDim2.fromScale(b, 0.5)
		readout.Text = formatNumber(c.Value.Min, step) .. " – " .. formatNumber(c.Value.Max, step) .. suffix
	end
	function c:Set(value, silent: boolean?)
		local lo, hi
		if type(value) == "table" then
			lo, hi = clean(value[1] or value.Min, value[2] or value.Max)
		else
			lo, hi = self.Value.Min, self.Value.Max
		end
		if lo == self.Value.Min and hi == self.Value.Max then render() return end
		self.Value = { Min = lo, Max = hi }
		render()
		if not silent then self:_emit(lo, hi) end
	end
	function c:Get() return self.Value.Min, self.Value.Max end
	render()
	local dragging
	local function valueAt(x)
		local p, s = track.AbsolutePosition, track.AbsoluteSize
		if s.X <= 0 then return nil end
		return min + (max - min) * math.clamp((x - p.X) / s.X, 0, 1)
	end
	local function move(x)
		local v = valueAt(x)
		if not v then return end
		v = math.clamp(round(v, step), min, max)
		-- a knob can't pass the other one; it stops against it
		if dragging == "Min" then
			c:Set({ math.min(v, c.Value.Max), c.Value.Max })
		else
			c:Set({ c.Value.Min, math.max(v, c.Value.Min) })
		end
	end
	hub:_connect(hit.InputBegan, function(input)
		if not isPointer(input) then return end
		local v = valueAt(input.Position.X)
		if not v then return end
		local dLo, dHi = math.abs(v - c.Value.Min), math.abs(v - c.Value.Max)
		dragging = (dLo < dHi or (dLo == dHi and v < c.Value.Min)) and "Min" or "Max"
		tween(dragging == "Min" and lowGrow or highGrow, SETTLE, { Scale = 1.25 })
		move(input.Position.X)
	end)
	hub:_connect(UserInputService.InputChanged, function(input)
		if dragging and isMove(input) then move(input.Position.X) end
	end)
	hub:_connect(UserInputService.InputEnded, function(input)
		if dragging and isPointer(input) then
			tween(dragging == "Min" and lowGrow or highGrow, SETTLE, { Scale = 1 })
			dragging = nil
		end
	end)
	return self.Hub:_finishRequiredControl(c)
end

---------------------------------------------------------------- Progress / meter
function Section:Progress(options)
	local hub, theme = self.Hub, self.Hub.Theme
	local min, max = options.Min or 0, options.Max or 100
	local segments = options.Segments
	local row = self:_row(options.Name and 42 or 22, "Progress_" .. (options.Name or ""))
	local c = self:_control("Progress", options, row)
	c.Value = math.clamp(options.Default or options.Value or min, min, max)
	local top = 0
	local readout
	if options.Name then
		top = 26
		text({ Parent = row, Name = "Title", Text = c.Name, TextSize = 13, Position = UDim2.fromOffset(0, 5), Size = UDim2.new(1, -90, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd })
		readout = text({ Parent = row, Name = "Value", Text = "", FontFace = MONO, TextSize = 12, TextColor3 = themeColor(theme, "SubText"), TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 5), Size = UDim2.fromOffset(90, 16) })
	end
	local bar = create("Frame", { Name = "Bar", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, top + 4), Size = UDim2.new(1, 0, 0, 6), Parent = row })
	local color = options.Color
	local fills = {}
	if segments and segments > 1 then
		create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, Parent = bar })
		for i = 1, segments do
			local seg = create("Frame", { Name = "Segment", BackgroundColor3 = themeColor(theme, "Track"), BorderSizePixel = 0, Size = UDim2.new(1 / segments, -3 + 3 / segments, 1, 0), LayoutOrder = i, Parent = bar }, { corner(2) })
			table.insert(fills, create("Frame", { Name = "Fill", BackgroundColor3 = color or themeColor(theme, "Accent"), BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = seg }, { corner(2) }))
		end
	else
		local back = create("Frame", { Name = "Track", BackgroundColor3 = themeColor(theme, "Track"), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = bar }, { corner(3) })
		table.insert(fills, create("Frame", { Name = "Fill", BackgroundColor3 = color or themeColor(theme, "Accent"), BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = back }, { corner(3) }))
	end
	local format = options.Format
	local function render(animate)
		local a = (max > min) and (c.Value - min) / (max - min) or 0
		local n = #fills
		for i, f in fills do
			-- each segment fills its own share of the bar
			local share = math.clamp(a * n - (i - 1), 0, 1)
			local goal = { Size = UDim2.fromScale(share, 1) }
			if animate then tween(f, SOFT, goal) else f.Size = goal.Size end
		end
		if readout then
			readout.Text = format and format(c.Value, min, max) or (math.floor(a * 100 + 0.5) .. "%")
		end
	end
	function c:Set(value: number)
		value = math.clamp(tonumber(value) or min, min, max)
		if value == self.Value then return end
		self.Value = value
		render(true)
	end
	c.Update = c.Set
	function c:SetColor(col: Color3)
		for _, f in fills do setThemed(f, "BackgroundColor3", col) end
	end
	function c:Get() return self.Value end
	render(false)
	return self.Hub:_finishRequiredControl(c)
end

---------------------------------------------------------------- Stat
function Section:Stat(options)
	local hub, theme = self.Hub, self.Hub.Theme
	local row = self:_row(30, "Stat_" .. (options.Name or ""))
	local c = self:_control("Stat", options, row)
	c.Value = options.Default or options.Value
	local format = options.Format
	local deltas = options.Delta
	text({ Parent = row, Name = "Title", Text = c.Name, TextSize = 13, Size = UDim2.new(0.5, 0, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd })
	local holder = create("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.5, 0, 1, 0), Parent = row }, {
		list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center),
	})
	local delta = text({ Parent = holder, Name = "Delta", Text = "", FontFace = MONO, TextSize = 11, Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X, TextTransparency = 1, LayoutOrder = 1 })
	local value = text({ Parent = holder, Name = "Value", Text = "", FontFace = MONO, TextSize = 12, TextColor3 = themeColor(theme, "Text"), Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2 })
	local function show(v)
		if format then return format(v) end
		if type(v) == "number" then
			local s = (v == math.floor(v)) and string.format("%d", v) or string.format("%.2f", v)
			-- group thousands so long numbers stay readable
			local int, rest = string.match(s, "^(-?%d+)(.*)$")
			if int and #string.gsub(int, "^-", "") >= 4 then
				int = string.reverse((string.gsub(string.reverse(int), "(%d%d%d)", "%1,")))
				int = string.gsub(int, "^(-?),", "%1")
			end
			return (int or s) .. (rest or "") .. (options.Suffix or "")
		end
		return tostring(v == nil and "—" or v) .. (options.Suffix or "")
	end
	local fadeToken = 0
	function c:Update(v)
		local old = self.Value
		self.Value = v
		local s = show(v)
		-- only touch the label when the text changes, so it never flickers
		if value.Text ~= s then value.Text = s end
		if deltas and type(v) == "number" and type(old) == "number" and v ~= old then
			local up = v > old
			local good = (options.HigherIsBetter == false) ~= up
			local col = themeColor(theme, good and "Success" or "Danger")
			setThemed(delta, "TextColor3", col)
			setThemed(value, "TextColor3", col)
			delta.Text = (up and "+" or "") .. show(v - old)
			delta.TextTransparency = 0
			fadeToken += 1
			local token = fadeToken
			task.delay(1.4, function()
				if token ~= fadeToken then return end
				tween(delta, SOFT, { TextTransparency = 1 })
				tween(value, SOFT, { TextColor3 = themeColor(theme, "Text") })
			end)
		end
	end
	c.Set = c.Update
	function c:Get() return self.Value end
	value.Text = show(c.Value)
	return self.Hub:_finishRequiredControl(c)
end

---------------------------------------------------------------- Sparkline
function Section:Sparkline(options)
	local hub, theme = self.Hub, self.Hub.Theme
	local count = math.clamp(options.Points or 40, 4, 120)
	local row = self:_row(64, "Spark_" .. (options.Name or ""))
	local c = self:_control("Sparkline", options, row)
	c.Values = {}
	text({ Parent = row, Name = "Title", Text = c.Name, TextSize = 13, Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, -90, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd })
	local readout = text({ Parent = row, Name = "Value", Text = "—", FontFace = MONO, TextSize = 12, TextColor3 = themeColor(theme, "SubText"), TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 4), Size = UDim2.fromOffset(90, 16) })
	local plot = create("Frame", { Name = "Plot", BackgroundColor3 = themeColor(theme, "Field"), Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 34), ClipsDescendants = true, Parent = row }, { corner(6), stroke(themeColor(theme, "FieldStroke")) })
	local area = create("Frame", { Name = "Area", BackgroundTransparency = 1, Position = UDim2.fromOffset(4, 5), Size = UDim2.new(1, -8, 1, -10), Parent = plot })
	local color = options.Color
	local segs = {}
	for i = 1, count - 1 do
		segs[i] = create("Frame", { Name = "Seg", BackgroundColor3 = color or themeColor(theme, "Accent"), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(0, 1.5), Visible = false, Parent = area })
	end
	local dot = create("Frame", { Name = "Head", BackgroundColor3 = color or themeColor(theme, "Accent"), AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(4, 4), Visible = false, ZIndex = 2, Parent = area }, { corner(2) })
	local function draw()
		local vals = c.Values
		local n = #vals
		local w, h = area.AbsoluteSize.X / hub._scale, area.AbsoluteSize.Y / hub._scale
		if n < 2 or w <= 0 then
			for _, s in segs do s.Visible = false end
			dot.Visible = false
			return
		end
		local lo, hi = options.Min, options.Max
		if lo == nil or hi == nil then
			local a, b = math.huge, -math.huge
			for _, v in vals do a = math.min(a, v) b = math.max(b, v) end
			if a == b then a, b = a - 1, b + 1 end
			lo, hi = lo or a, hi or b
		end
		local dx = w / (count - 1)
		-- newest point sits on the right edge; older ones scroll left
		local x0 = w - (n - 1) * dx
		local function pt(i)
			local t = math.clamp((vals[i] - lo) / (hi - lo), 0, 1)
			return x0 + (i - 1) * dx, h - t * h
		end
		for i, s in segs do
			if i < n then
				local ax, ay = pt(i)
				local bx, by = pt(i + 1)
				local len = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
				s.Position = UDim2.fromOffset((ax + bx) / 2, (ay + by) / 2)
				s.Size = UDim2.fromOffset(len + 0.6, 1.5)
				s.Rotation = math.deg(math.atan2(by - ay, bx - ax))
				s.Visible = true
			else
				s.Visible = false
			end
		end
		local hx, hy = pt(n)
		dot.Position = UDim2.fromOffset(hx, hy)
		dot.Visible = true
	end
	function c:Push(v: number)
		v = tonumber(v)
		if not v then return end
		table.insert(self.Values, v)
		while #self.Values > count do table.remove(self.Values, 1) end
		local s = options.Format and options.Format(v) or (formatNumber(v, options.Step or 1) .. (options.Suffix or ""))
		if readout.Text ~= s then readout.Text = s end
		draw()
	end
	c.Update = c.Push
	function c:Clear()
		table.clear(self.Values)
		readout.Text = "—"
		draw()
	end
	function c:Get() return self.Values[#self.Values] end
	hub:_connect(area:GetPropertyChangedSignal("AbsoluteSize"), draw)
	return self.Hub:_finishRequiredControl(c)
end

---------------------------------------------------------------- Segmented
function Section:Segmented(options)
	local hub, theme = self.Hub, self.Hub.Theme
	local opts = options.Options or {}
	local row = self:_row(options.Name and 58 or 34, "Segmented_" .. (options.Name or ""))
	local c = self:_control("Segmented", options, row)
	c.Options = table.clone(opts)
	c.Value = options.Default or opts[1]
	local top = 0
	if options.Name then
		text({ Parent = row, Name = "Title", Text = c.Name, TextSize = 13, Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd })
		top = 26
	end
	local track = create("Frame", { Name = "Track", BackgroundColor3 = themeColor(theme, "Field"), Position = UDim2.fromOffset(0, top + 2), Size = UDim2.new(1, 0, 0, 28), Parent = row }, { corner(7), stroke(themeColor(theme, "FieldStroke")) })
	local n = math.max(1, #opts)
	local pill = create("Frame", { Name = "Pill", BackgroundColor3 = themeColor(theme, "TileActive"), Position = UDim2.new(0, 2, 0, 2), Size = UDim2.new(1 / n, -4, 1, -4), Parent = track }, { corner(5), stroke(themeColor(theme, "TileActiveStroke")) })
	local labels = {}
	for i, o in opts do
		local b = create("TextButton", { Name = "Segment", BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Position = UDim2.fromScale((i - 1) / n, 0), Size = UDim2.fromScale(1 / n, 1), ZIndex = 2, Parent = track })
		labels[i] = text({ Parent = b, Text = tostring(o), TextSize = 12, FontFace = inter(Enum.FontWeight.Medium), TextColor3 = themeColor(theme, "SubText"), TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3 })
		hub:_connect(b.MouseButton1Click, function() c:Set(o) end)
		hub:_connect(b.MouseEnter, function() if c.Value ~= o then setThemed(labels[i], "TextColor3", themeColor(theme, "Text")) end end)
		hub:_connect(b.MouseLeave, function() if c.Value ~= o then setThemed(labels[i], "TextColor3", themeColor(theme, "SubText")) end end)
	end
	local function render(animate)
		local i = table.find(opts, c.Value) or 1
		local goal = { Position = UDim2.new((i - 1) / n, 2, 0, 2) }
		if animate then tween(pill, SETTLE, goal) else pill.Position = goal.Position end
		for j, l in labels do
			setThemed(l, "TextColor3", themeColor(theme, j == i and "Text" or "SubText"))
		end
	end
	function c:Set(v, silent: boolean?)
		if not table.find(opts, v) or v == self.Value then return end
		self.Value = v
		render(true)
		if not silent then self:_emit(v) end
	end
	function c:Get() return self.Value end
	render(false)
	return self.Hub:_finishRequiredControl(c)
end

---------------------------------------------------------------- Stepper
function Section:Stepper(options)
	local hub, theme = self.Hub, self.Hub.Theme
	local min, max, step = options.Min or 0, options.Max or 10, options.Step or 1
	local row = self:_row(34, "Stepper_" .. (options.Name or ""))
	local c = self:_control("Stepper", options, row)
	c.Value = math.clamp(round(options.Default or min, step), min, max)
	self:_labels(row, c.Name, options.Description, 96)
	local box = create("Frame", { Name = "Stepper", BackgroundColor3 = themeColor(theme, "Field"), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromOffset(92, 24), Parent = row }, { corner(6), stroke(themeColor(theme, "FieldStroke")) })
	local function button(name, icon, x, anchor)
		local b = create("TextButton", { Name = name, BackgroundColor3 = themeColor(theme, "Tile"), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(anchor, 0), Position = UDim2.fromScale(x, 0), Size = UDim2.new(0, 26, 1, 0), Parent = box }, { corner(6) })
		local ic = iconLabel(icon, 13, theme.SubText, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Parent = b })
		if not ic then text({ Parent = b, Text = icon == "minus" and "–" or "+", TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1) }) end
		return b, ic
	end
	local minus, minusIcon = button("Decrease", "minus", 0, 0)
	local plus, plusIcon = button("Increase", "plus", 1, 1)
	local value = text({ Parent = box, Name = "Value", Text = "", FontFace = MONO, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(26, 0), Size = UDim2.new(1, -52, 1, 0) })
	local function render()
		value.Text = formatNumber(c.Value, step) .. (options.Suffix or "")
		if minusIcon then setThemed(minusIcon, "ImageColor3", themeColor(theme, c.Value <= min and "Muted" or "SubText")) end
		if plusIcon then setThemed(plusIcon, "ImageColor3", themeColor(theme, c.Value >= max and "Muted" or "SubText")) end
	end
	function c:Set(v, silent: boolean?)
		v = math.clamp(round(tonumber(v) or min, step), min, max)
		if v == self.Value then return end
		self.Value = v
		render()
		if not silent then self:_emit(v) end
	end
	function c:Get() return self.Value end
	render()
	-- Holding a button repeats, faster the longer it's held.
	local function hold(b, dir)
		local token = 0
		hub:_connect(b.MouseEnter, function() tween(b, FAST, { BackgroundTransparency = 0 }) end)
		hub:_connect(b.MouseLeave, function() token += 1 tween(b, FAST, { BackgroundTransparency = 1 }) end)
		hub:_connect(b.MouseButton1Down, function()
			token += 1
			local mine = token
			c:Set(c.Value + dir * step)
			task.delay(0.4, function()
				local wait = 0.12
				while token == mine and not hub._destroyed do
					c:Set(c.Value + dir * step)
					task.wait(wait)
					wait = math.max(0.03, wait * 0.85)
				end
			end)
		end)
		hub:_connect(b.MouseButton1Up, function() token += 1 end)
	end
	hold(minus, -1)
	hold(plus, 1)
	return self.Hub:_finishRequiredControl(c)
end

---------------------------------------------------------------- Console
function Section:Console(options)
	options = type(options) == "table" and options or { Name = tostring(options) }
	local hub, theme = self.Hub, self.Hub.Theme
	local maxLines = options.MaxLines or 200
	local height = options.Height or 150
	local row = self:_row(height + 30, "Console_" .. (options.Name or ""))
	local c = self:_control("Console", options, row)
	c.Lines = {}
	text({ Parent = row, Name = "Title", Text = c.Name, TextSize = 13, Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, -70, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd })
	local function tool(name, icon, x)
		local b = create("TextButton", { Name = name, BackgroundColor3 = themeColor(theme, "Tile"), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, x, 0, 0), Size = UDim2.fromOffset(26, 24), Parent = row }, { corner(6) })
		local ic = iconLabel(icon, 14, theme.SubText, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Parent = b })
		hub:_connect(b.MouseEnter, function() tween(b, FAST, { BackgroundTransparency = 0 }) end)
		hub:_connect(b.MouseLeave, function() tween(b, FAST, { BackgroundTransparency = 1 }) end)
		return b, ic
	end
	local copy, copyIcon = tool("CopyLog", "copy", -30)
	local clear = tool("ClearLog", "trash-2", 0)
	local scroll = create("ScrollingFrame", {
		Name = "Log", BackgroundColor3 = themeColor(theme, "Field"), BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 0, height),
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3, ScrollBarImageColor3 = themeColor(theme, "Knob"), ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = row,
	}, { corner(6), stroke(themeColor(theme, "FieldStroke")), padding(6, 8), list(Enum.FillDirection.Vertical, 2) })
	local empty = text({ Parent = scroll, Name = "Empty", Text = options.Placeholder or "Nothing logged yet", FontFace = MONO, TextSize = 11, TextColor3 = themeColor(theme, "Muted"), Size = UDim2.new(1, 0, 0, 14) })
	local labels = {}
	local order = 0
	local KIND = { warn = "Warning", warning = "Warning", error = "Danger", success = "Success", info = "Text" }
	local function stamp() return os.date("%H:%M:%S") end
	function c:Log(message, kind: string?)
		message = tostring(message)
		local h = scroll.AbsoluteSize.Y / hub._scale
		local atBottom = scroll.CanvasPosition.Y + h >= scroll.AbsoluteCanvasSize.Y / hub._scale - 24
		order += 1
		local line = options.Timestamps == false and message or (stamp() .. "  " .. message)
		table.insert(self.Lines, line)
		local label = text({ Parent = scroll, Name = "Line", Text = line, FontFace = MONO, TextSize = 11, TextWrapped = true, TextColor3 = themeColor(theme, KIND[string.lower(kind or "info")] or "Text"), Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order })
		table.insert(labels, label)
		empty.Visible = false
		while #labels > maxLines do
			table.remove(labels, 1):Destroy()
			table.remove(self.Lines, 1)
		end
		-- follow new lines only if the reader was already at the bottom
		if atBottom then
			task.defer(function()
				scroll.CanvasPosition = Vector2.new(0, math.max(0, scroll.AbsoluteCanvasSize.Y / hub._scale - scroll.AbsoluteSize.Y / hub._scale))
			end)
		end
	end
	c.Print = c.Log
	function c:Clear()
		for _, l in labels do l:Destroy() end
		table.clear(labels)
		table.clear(self.Lines)
		empty.Visible = true
	end
	function c:Get() return table.concat(self.Lines, "\n") end
	hub:_connect(clear.MouseButton1Click, function() c:Clear() end)
	hub:_connect(copy.MouseButton1Click, function()
		if typeof(setclipboard) == "function" then
			setclipboard(c:Get())
			if copyIcon then
				setThemed(copyIcon, "ImageColor3", themeColor(theme, "Success"))
				task.delay(0.9, function() setThemed(copyIcon, "ImageColor3", themeColor(theme, "SubText")) end)
			end
		else
			hub:Notify({ Title = "No clipboard", Content = "This executor can't copy text.", Tone = hub.Theme.Warning })
		end
	end)
	return self.Hub:_finishRequiredControl(c)
end

---------------------------------------------------------------- List
--[[
	Rows of data the script owns: waypoints, saved positions, logs of players. An item is a
	string or an array of cell strings; Columns adds a header and splits each row into cells.
	Clicking a row selects it (Callback(item, index)); Removable adds a remove button that
	calls OnRemove(item, index) and drops the row. Items are data, not settings, so lists
	are left out of configs.
]]
function Section:List(options)
	options = type(options) == "table" and options or { Name = tostring(options) }
	local hub, theme = self.Hub, self.Hub.Theme
	local columns = type(options.Columns) == "table" and #options.Columns > 0 and options.Columns or nil
	local ncols = columns and #columns or 1
	local widths = {}
	do
		local given, total = options.Widths, 0
		for i = 1, ncols do
			widths[i] = type(given) == "table" and tonumber(given[i]) or 1
			total += widths[i]
		end
		for i = 1, ncols do widths[i] /= total end
	end
	local removable = options.Removable == true or options.OnRemove ~= nil
	local selectable = options.Selectable ~= false
	local height = math.max(60, options.Height or 156)
	local headH = columns and 24 or 0
	local top = options.Name and 26 or 0
	local row = self:_row(top + headH + height + 4, "List_" .. (options.Name or ""))
	local c = self:_control("List", options, row)
	c.Items = {}
	c.Selected = nil
	local count
	if options.Name then
		text({ Parent = row, Name = "Title", Text = c.Name, TextSize = 13, Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, -80, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd })
		count = text({ Parent = row, Name = "Count", Text = "", FontFace = MONO, TextSize = 11, TextColor3 = themeColor(theme, "Muted"), TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 4), Size = UDim2.fromOffset(80, 18) })
	end
	local frame = create("Frame", {
		Name = "Box", BackgroundColor3 = themeColor(theme, "Field"), Position = UDim2.fromOffset(0, top),
		Size = UDim2.new(1, 0, 0, headH + height), ClipsDescendants = true, Parent = row,
	}, { corner(6), stroke(themeColor(theme, "FieldStroke")) })
	local rightPad = removable and 30 or 0
	local function cells(parent, values, header: boolean, selected: boolean)
		local x = 0
		for i = 1, ncols do
			local w = widths[i]
			text({
				Parent = parent, Name = header and "Column" or "Cell", Text = values[i] or "",
				FontFace = header and inter(Enum.FontWeight.Medium) or ((i > 1 and options.Monospace ~= false) and MONO or inter()),
				TextSize = header and 11 or 12,
				TextColor3 = themeColor(theme, header and "Muted" or ((i == 1 or selected) and "Text" or "SubText")),
				Position = UDim2.new(x, i == 1 and 0 or 8, 0, 0),
				Size = UDim2.new(w, (i == 1 and 0 or -8) - (i == ncols and rightPad or 0), 1, 0),
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
			x += w
		end
	end
	if columns then
		local head = create("Frame", { Name = "Header", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, headH), Parent = frame }, { padding(0, 10) })
		local names = {}
		for i, col in columns do names[i] = hub:T(tostring(col)) end
		cells(head, names, true, false)
		create("Frame", { Name = "Divider", BackgroundColor3 = themeColor(theme, "Divider"), BorderSizePixel = 0, Position = UDim2.fromOffset(0, headH - 1), Size = UDim2.new(1, 0, 0, 1), Parent = frame })
	end
	local scroll = create("ScrollingFrame", {
		Name = "Rows", BackgroundTransparency = 1, BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, headH), Size = UDim2.new(1, 0, 0, height),
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3, ScrollBarImageColor3 = themeColor(theme, "Knob"), ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = frame,
	}, { padding(4, 4), list(Enum.FillDirection.Vertical, 1) })
	local empty = text({ Parent = frame, Name = "Empty", Text = options.Placeholder or "Nothing here yet", TextSize = 12, TextColor3 = themeColor(theme, "Muted"), TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, headH), Size = UDim2.new(1, 0, 0, height) })
	local rows = {}
	local function normalize(item)
		if type(item) ~= "table" then item = { item } end
		local out = {}
		for i = 1, ncols do out[i] = item[i] ~= nil and tostring(item[i]) or "" end
		return out
	end
	local function public(item)
		return ncols == 1 and item[1] or table.clone(item)
	end
	local function paint(i)
		local r = rows[i]
		if not r then return end
		local on = c.Selected == i
		local goal = { BackgroundTransparency = (on or r.Hover) and 0 or 1 }
		setThemed(r.Button, "BackgroundColor3", themeColor(theme, on and "TileActive" or "TileHover"))
		tween(r.Button, FAST, goal)
	end
	-- rows are rebuilt on every change; their connections die with the buttons
	local function render()
		for _, r in rows do r.Button:Destroy() end
		table.clear(rows)
		for i, item in c.Items do
			local b = create("TextButton", {
				Name = "Item", BackgroundColor3 = themeColor(theme, "TileHover"), BackgroundTransparency = 1,
				Text = "", AutoButtonColor = false, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = i, Parent = scroll,
			}, { corner(5), padding(0, 6, 0, 6) })
			local r = { Button = b, Hover = false }
			rows[i] = r
			cells(b, item, false, c.Selected == i)
			if removable then
				local x = create("TextButton", {
					Name = "Remove", BackgroundColor3 = themeColor(theme, "Tile"), BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
					AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 2, 0.5, 0), Size = UDim2.fromOffset(22, 22), ZIndex = 2, Parent = b,
				}, { corner(5) })
				local ic = iconLabel("x", 13, theme.Muted, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 3, Parent = x })
				if not ic then text({ Parent = x, Text = "×", TextColor3 = themeColor(theme, "Muted"), TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 3 }) end
				x.MouseEnter:Connect(function()
					if ic then setThemed(ic, "ImageColor3", themeColor(theme, "Danger")) end
				end)
				x.MouseLeave:Connect(function()
					if ic then setThemed(ic, "ImageColor3", themeColor(theme, "Muted")) end
				end)
				x.MouseButton1Click:Connect(function()
					local index = table.find(c.Items, item)
					if not index or not c:IsAvailable() then return end
					c:Remove(index)
					if options.OnRemove then
						task.spawn(function()
							local ok, err = pcall(options.OnRemove, public(item), index)
							if not ok then recordError(tostring(err), nil, c.Name) warn("[RiftUI] " .. c.Name .. " OnRemove error: " .. tostring(err)) end
						end)
					end
				end)
			end
			b.MouseEnter:Connect(function() r.Hover = true paint(i) end)
			b.MouseLeave:Connect(function() r.Hover = false paint(i) end)
			if selectable then
				b.MouseButton1Click:Connect(function() c:Select(i) end)
			end
			paint(i)
		end
		empty.Visible = #c.Items == 0
		if count then
			local n = #c.Items
			count.Text = n == 0 and "" or (n .. (n == 1 and " item" or " items"))
		end
	end
	function c:Select(index: number?, silent: boolean?)
		if index ~= nil and not self.Items[index] then return end
		self.Selected = index
		render()
		if not silent and index then self:_emit(public(self.Items[index]), index) end
	end
	function c:Add(item, index: number?)
		local entry = normalize(item)
		index = index and math.clamp(math.floor(index), 1, #self.Items + 1) or (#self.Items + 1)
		table.insert(self.Items, index, entry)
		if self.Selected and self.Selected >= index then self.Selected += 1 end
		local max = options.MaxItems
		while type(max) == "number" and #self.Items > max do
			table.remove(self.Items, 1)
			if self.Selected then self.Selected = self.Selected > 1 and self.Selected - 1 or nil end
			index -= 1
		end
		render()
		return math.max(index, 1)
	end
	function c:Remove(index: number)
		if not self.Items[index] then return nil end
		local item = table.remove(self.Items, index)
		if self.Selected == index then
			self.Selected = nil
		elseif self.Selected and self.Selected > index then
			self.Selected -= 1
		end
		render()
		return item
	end
	function c:Update(index: number, item)
		if not self.Items[index] then return end
		self.Items[index] = normalize(item)
		render()
	end
	function c:Set(items)
		table.clear(self.Items)
		for _, item in type(items) == "table" and items or {} do table.insert(self.Items, normalize(item)) end
		self.Selected = nil
		render()
	end
	function c:Clear() self:Set({}) end
	function c:Get()
		local out = {}
		for i, item in self.Items do out[i] = public(item) end
		return out
	end
	function c:GetSelected()
		local item = self.Selected and self.Items[self.Selected]
		if not item then return nil, nil end
		return public(item), self.Selected
	end
	c:Set(options.Items)
	return self.Hub:_finishRequiredControl(c)
end

---------------------------------------------------------------- PlayerPicker
local function initials(name: string): string
	local a, b = string.match(name, "^%W*(%w)%w*%W+(%w)")
	return string.upper(a and (a .. b) or string.sub(string.gsub(name, "%W", ""), 1, 2))
end

local function cachedHeadshot(player)
	if not hasAssets then return nil end
	local id = tonumber(player.UserId)
	if not id or id < 1 or id % 1 ~= 0 then return nil end
	local folder = RiftUI.AssetCacheFolder or (RiftUI.Folder .. "/assets")
	local path = folder .. "/avatar-" .. tostring(id) .. ".png"
	local ok, result = pcall(function()
		if not isfile(path) then
			local url = "https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds=" .. tostring(id) .. "&size=150x150&format=Png&isCircular=false"
			local response = HttpService:JSONDecode(game:HttpGet(url))
			local item = response.data and response.data[1]
			assert(item and item.state == "Completed" and type(item.imageUrl) == "string" and string.match(item.imageUrl, "^https://"), "thumbnail unavailable")
			local bytes = game:HttpGet(item.imageUrl)
			assert(type(bytes) == "string" and #bytes <= 1024 * 1024 and string.sub(bytes, 1, 8) == "\137PNG\r\n\26\n", "invalid thumbnail")
			ensureFolder(RiftUI.Folder) ensureFolder(RiftUI.Folder .. "/assets") ensureFolder(folder)
			writefile(path, bytes)
		end
		return getcustomasset(path)
	end)
	if ok and type(result) == "string" then localAssetIds[result] = true return result end
	return nil
end

local function avatar(player, size: number, theme, props)
	local face = create("Frame", { Name = "Avatar", BackgroundColor3 = themeColor(theme, "TileActive"), Size = UDim2.fromOffset(size, size) }, { corner(size / 2) })
	-- initials sit underneath, so a thumbnail that never loads still leaves a face
	text({ Parent = face, Name = "Initials", Text = player and initials(player.DisplayName) or "?", TextSize = math.floor(size * 0.4), FontFace = inter(Enum.FontWeight.SemiBold), TextColor3 = themeColor(theme, "SubText"), TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1) })
	if player then
		local img = create("ImageLabel", { Name = "Thumb", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = face }, { corner(size / 2) })
		task.spawn(function()
			local ok, url = pcall(function()
				if secureAssets() then return cachedHeadshot(player) end
				return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
			end)
			if ok and url and img.Parent then img.Image = secureProperty("Image", url) end
		end)
	end
	for k, v in props or {} do face[k] = v end
	return face
end

function Section:PlayerPicker(options)
	local hub, theme = self.Hub, self.Hub.Theme
	local row = self:_row(34, "PlayerPicker_" .. (options.Name or ""))
	local c = self:_control("PlayerPicker", options, row)
	c.Value = nil
	local includeSelf = options.IncludeSelf == true
	self:_labels(row, c.Name, options.Description, 150)
	local chip = create("TextButton", {
		Name = "Chip", BackgroundColor3 = themeColor(theme, "Field"), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, Text = "", AutoButtonColor = false, Parent = row,
	}, { corner(6), stroke(themeColor(theme, "FieldStroke")), padding(0, 6, 0, 4), list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center), create("UISizeConstraint", { MaxSize = Vector2.new(150, 26) }) })
	local face
	local label = text({ Parent = chip, Name = "Value", TextSize = 12, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 2 })
	create("UISizeConstraint", { MaxSize = Vector2.new(96, 26), Parent = label })
	iconLabel("chevron-down", 14, theme.SubText, { LayoutOrder = 3, Parent = chip })
	local function players()
		local out = {}
		for _, p in Players:GetPlayers() do
			if includeSelf or p ~= Players.LocalPlayer then table.insert(out, p) end
		end
		table.sort(out, function(a, b) return string.lower(a.DisplayName) < string.lower(b.DisplayName) end)
		return out
	end
	local left = false
	local function render()
		if face then face:Destroy() end
		face = avatar(c.Value, 18, theme, { LayoutOrder = 1, Parent = chip })
		label.Text = c.Value and c.Value.DisplayName or (left and "Left the game" or "None")
		setThemed(label, "TextColor3", themeColor(theme, c.Value and "Text" or "SubText"))
	end
	function c:Set(player, silent: boolean?)
		if type(player) == "string" then
			local name = player
			player = nil
			for _, p in Players:GetPlayers() do
				if p.Name == name or p.DisplayName == name then player = p break end
			end
		end
		if typeof(player) ~= "Instance" then player = nil end
		left = false
		if player == self.Value then render() return end
		self.Value = player
		render()
		if not silent then self:_emit(player) end
	end
	function c:Get() return self.Value end
	if options.Default then c:Set(options.Default, true) else render() end

	local refreshList
	hub:_connect(Players.PlayerAdded, function()
		if refreshList then refreshList() end
	end)
	hub:_connect(Players.PlayerRemoving, function(p)
		if p == c.Value then
			c.Value = nil
			left = true
			render()
			c:_emit(nil)
		end
		task.defer(function() if refreshList then refreshList() end end)
	end)
	hub:_connect(chip.MouseButton1Click, function()
		if hub._popup and hub._popup.Anchor == chip then hub:_closePopup() return end
		local itemH = 40
		local frame = create("Frame", { Name = "PlayerList", BackgroundColor3 = themeColor(theme, "Panel"), Size = UDim2.fromOffset(240, 8), ZIndex = 41 }, { corner(10), stroke(themeColor(theme, "PanelStroke")), padding(4) })
		local search = create("TextBox", {
			Name = "Filter", BackgroundColor3 = themeColor(theme, "Field"), Size = UDim2.new(1, 0, 0, 28),
			PlaceholderText = "Search players", PlaceholderColor3 = themeColor(theme, "Muted"), Text = "", FontFace = inter(), TextSize = 12,
			TextColor3 = themeColor(theme, "Text"), TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false, ZIndex = 42, Parent = frame,
		}, { corner(6), padding(0, 8) })
		local scroll = create("ScrollingFrame", {
			Name = "Items", BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 1, -32),
			CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 2, ScrollBarImageColor3 = themeColor(theme, "Knob"), ZIndex = 42, Parent = frame,
		}, { list(Enum.FillDirection.Vertical, 0) })
		local count = create("TextLabel", { Name = "Count", BackgroundTransparency = 1, Text = "", FontFace = MONO, TextSize = 10, TextColor3 = themeColor(theme, "Muted"), TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 0), Size = UDim2.fromOffset(40, 28), ZIndex = 43, Parent = frame })
		local function build()
			for _, ch in scroll:GetChildren() do if ch:IsA("GuiObject") then ch:Destroy() end end
			local q = string.lower(search.Text)
			local all = players()
			local shown = 0
			for i, p in all do
				if q == "" or string.find(string.lower(p.DisplayName), q, 1, true) or string.find(string.lower(p.Name), q, 1, true) then
					shown += 1
					local on = p == c.Value
					local item = create("TextButton", { Name = "Player_" .. p.Name, BackgroundColor3 = themeColor(theme, "Tile"), BackgroundTransparency = on and 0 or 1, Size = UDim2.new(1, 0, 0, itemH), Text = "", AutoButtonColor = false, LayoutOrder = i, ZIndex = 43, Parent = scroll }, { corner(6) })
					avatar(p, 26, theme, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0), ZIndex = 44, Parent = item })
					text({ Parent = item, Text = p.DisplayName, TextSize = 13, FontFace = inter(Enum.FontWeight.Medium), Position = UDim2.fromOffset(42, 4), Size = UDim2.new(1, -66, 0, 17), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 44 })
					text({ Parent = item, Text = "@" .. p.Name, TextSize = 11, TextColor3 = themeColor(theme, "SubText"), Position = UDim2.fromOffset(42, 20), Size = UDim2.new(1, -66, 0, 15), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 44 })
					iconLabel("check", 14, theme.Text, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Visible = on, ZIndex = 44, Parent = item })
					item.MouseEnter:Connect(function() tween(item, FAST, { BackgroundTransparency = 0 }) end)
					item.MouseLeave:Connect(function() tween(item, FAST, { BackgroundTransparency = p == c.Value and 0 or 1 }) end)
					item.MouseButton1Click:Connect(function()
						c:Set(p)
						hub:_closePopup()
					end)
				end
			end
			if shown == 0 then
				text({ Parent = scroll, Text = #all == 0 and "Nobody else is here" or "No match", TextColor3 = themeColor(theme, "Muted"), Size = UDim2.new(1, 0, 0, itemH), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 43 })
			end
			count.Text = tostring(#all)
			frame.Size = UDim2.fromOffset(240, 8 + 32 + math.max(1, math.min(shown, 6)) * itemH)
			if frame.Parent then frame.Parent.Size = frame.Size end
		end
		build()
		search:GetPropertyChangedSignal("Text"):Connect(build)
		refreshList = build
		hub:_openPopup(chip, frame, function() refreshList = nil end)
	end)
	return self.Hub:_finishRequiredControl(c)
end

---------------------------------------------------------------- pinning
function Section:Pin(position: Vector2?)
	if self.Pinned then
		return
	end
	local hub, theme = self.Hub, self.Hub.Theme
	self.Pinned = true
	self.Frame.Visible = false
	local card = create("Frame", {
		Name = "Pin_" .. self.Name,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(220, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = hub.PinLayer,
	})
	shadow(card, 18, 0, 5)
	local body = create("Frame", {
		Name = "Card",
		BackgroundColor3 = themeColor(theme, "Panel"),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 2,
		Parent = card,
	}, { corner(12), stroke(themeColor(theme, "PanelStroke")), padding(36, 12, 4, 12) })
	local head = create("TextButton", {
		Name = "Drag",
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Position = UDim2.fromOffset(-12, -36),
		Size = UDim2.new(1, 24, 0, 34),
		ZIndex = 3,
		Parent = body,
	}, { padding(0, 8, 0, 12) })
	text({ Parent = head, Text = self.Name, FontFace = inter(Enum.FontWeight.SemiBold), TextSize = 13, Size = UDim2.new(1, -28, 1, 0), ZIndex = 4, TextTruncate = Enum.TextTruncate.AtEnd })
	local unpin = create("TextButton", {
		Name = "Unpin",
		BackgroundColor3 = themeColor(theme, "Tile"),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(24, 24),
		Text = "",
		AutoButtonColor = false,
		ZIndex = 4,
		Parent = head,
	}, { corner(6) })
	if not iconLabel("pin-off", 13, theme.Text, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 5, Parent = unpin }) then
		text({ Parent = unpin, Text = "x", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 })
	end
	self.Rows.Parent = body
	self.Card = card

	local start = position or hub.Pins[self.Id]
	if not start then
		local n = 0
		for _ in hub.Pins do
			n += 1
		end
		start = Vector2.new(16, topInset() + 8 + n * 150)
	end
	card.Position = UDim2.fromOffset(start.X, start.Y + 8)
	tween(card, SETTLE, { Position = UDim2.fromOffset(start.X, start.Y) })
	hub.Pins[self.Id] = start

	local dragging, origin, from
	self._pinConns = {
		head.InputBegan:Connect(function(input)
			if isPointer(input) then
				dragging = true
				origin = Vector2.new(input.Position.X, input.Position.Y)
				from = Vector2.new(card.Position.X.Offset, card.Position.Y.Offset)
			end
		end),
		UserInputService.InputChanged:Connect(function(input)
			if dragging and isMove(input) then
				local s = hub._scale
				local d = (Vector2.new(input.Position.X, input.Position.Y) - origin) / s
				local vp = viewport() / s
				local x = math.clamp(from.X + d.X, 0, math.max(0, vp.X - card.AbsoluteSize.X / s))
				local y = math.clamp(from.Y + d.Y, 0, math.max(0, vp.Y - card.AbsoluteSize.Y / s))
				card.Position = UDim2.fromOffset(x, y)
				hub.Pins[self.Id] = Vector2.new(x, y)
			end
		end),
		UserInputService.InputEnded:Connect(function(input)
			if isPointer(input) then
				dragging = false
			end
		end),
		unpin.MouseButton1Click:Connect(function()
			self:Unpin()
		end),
	}
	if hub._open == self.Tab then
		task.defer(function()
			hub:_fitPanel(self.Tab, true)
		end)
	end
end

function Section:Unpin()
	if not self.Pinned then
		return
	end
	local hub = self.Hub
	self.Pinned = false
	hub.Pins[self.Id] = nil
	for _, c in self._pinConns or {} do
		c:Disconnect()
	end
	self.Rows.Parent = self._rowsClip or self.Frame
	self.Frame.Visible = true
	if self.Card then
		self.Card:Destroy()
		self.Card = nil
	end
	if hub._open == self.Tab then
		task.defer(function()
			hub:_fitPanel(self.Tab, true)
		end)
	end
end

---------------------------------------------------------------- configs
local function encodeValue(control)
	local v = control.Value
	if control.Type == "ColorPicker" then
		return { Color = v:ToHex() }
	elseif control.Type == "Keybind" then
		return { Key = v and v.Name or "None", Mode = control.Mode }
	elseif control.Type == "PlayerPicker" then
		return { Player = v and v.Name or nil }
	elseif control.Type == "RangeSlider" then
		return { Range = { v.Min, v.Max } }
	elseif control.Type == "Dropdown" and control.Multi then
		local picked = {}
		for k, on in v do
			if on then
				table.insert(picked, k)
			end
		end
		return { Multi = picked }
	end
	return { Value = v }
end

local function decodeValue(control, data, silent: boolean?)
	if control.Type == "ColorPicker" and data.Color then
		local ok, col = pcall(Color3.fromHex, data.Color)
		if ok then
			control:Set(col, silent)
		end
	elseif control.Type == "Keybind" and data.Key then
		control:Set(data.Key ~= "None" and data.Key or nil, silent)
	elseif control.Type == "Dropdown" and data.Multi then
		control:Set(data.Multi, silent)
	elseif control.Type == "RangeSlider" and data.Range then
		control:Set(data.Range, silent)
	elseif control.Type == "PlayerPicker" then
		control:Set(data.Player, silent)
	elseif data.Value ~= nil and control.Set then
		control:Set(data.Value, silent)
	end
end

function Hub:_restoreRequiredControl(control)
	local value = control._requirementRestore
	control._requirementRestore = nil
	if value then pcall(decodeValue, control, value, true) end
end

local SAVABLE = { Toggle = true, Slider = true, Dropdown = true, Input = true, Keybind = true, ColorPicker = true, RangeSlider = true, Segmented = true, Stepper = true, PlayerPicker = true }

function Hub:_dir(): string
	return RiftUI.Folder .. "/" .. self.Id
end

function Hub:_configDir(): string
	return self:_dir() .. "/configs"
end

function Hub:_flagValues()
	local out = {}
	for flag, control in RiftUI.Flags do
		if control.Section and (control.Section.Hub == self or control.Section.Hub.Gui == self.Gui) and SAVABLE[control.Type] and not control._internal then
			out[flag] = encodeValue(control)
		end
	end
	return out
end

-- Optional authenticated config encryption. AES itself stays in the crypto provider.
local CONFIG_LIMIT = 256 * 1024
local CONFIG_ENCRYPTED = "riftui-encrypted-config"
local CONFIG_CIPHER = "AES-256-CBC-HMAC-SHA256"
local CONFIG_ENCRYPTED_PREFIX = "RIFTCFG2:"
local function configName(name)
	return type(name) == "string" and #name > 0 and #name <= 80 and string.match(name, "^[%w%s%-_]+$") ~= nil
end
local function hashBytes(provider, value)
	local hex = provider.hash(value, "sha256")
	assert(type(hex) == "string" and #hex == 64 and string.match(hex, "^%x+$"), "SHA-256 provider required")
	return (string.gsub(hex, "%x%x", function(pair) return string.char(tonumber(pair, 16)) end))
end
local function hmac(provider, key, value)
	if #key > 64 then key = hashBytes(provider, key) end
	key ..= string.rep("\0", 64 - #key)
	local inner, outer = {}, {}
	for i = 1, 64 do
		local b = string.byte(key, i)
		inner[i], outer[i] = string.char(bit32.bxor(b, 0x36)), string.char(bit32.bxor(b, 0x5c))
	end
	return hashBytes(provider, table.concat(outer) .. hashBytes(provider, table.concat(inner) .. value))
end
local function hexBytes(value)
	return (string.gsub(value, ".", function(c) return string.format("%02x", string.byte(c)) end))
end
local function sameTag(a, b)
	if type(a) ~= "string" or #a ~= #b then return false end
	local diff = 0
	for i = 1, #b do diff = bit32.bor(diff, bit32.bxor(string.byte(a, i), string.byte(b, i))) end
	return diff == 0
end
local function authenticatedText(envelope)
	return CONFIG_ENCRYPTED .. "\0" .. "1\0" .. CONFIG_CIPHER .. "\0" .. envelope.IV .. "\0" .. envelope.Ciphertext
end

function Hub:SetConfigEncryption(options)
	if options == nil or options == false then
		self._configEncryption, self._encryptConfigs = nil, false
		return true
	end
	if type(options) ~= "table" or (type(options.Key) ~= "string" and type(options.Key) ~= "function") then
		return false, "ConfigEncryption needs a 32-byte Base64 key or key provider"
	end
	local provider = options.Crypto or RiftUI.ConfigCrypto or (typeof(crypt) == "table" and crypt)
	for _, method in { "encrypt", "decrypt", "hash", "generatebytes", "base64encode", "base64decode" } do
		if type(provider) ~= "table" or type(provider[method]) ~= "function" then
			return false, "encrypted configs require an AES-CBC/SHA-256 crypto provider"
		end
	end
	self._configEncryption = { Key = options.Key, Crypto = provider }
	self._encryptConfigs = options.Enabled ~= false
	return true
end

function Hub:_configKeys(options)
	local configured = self._configEncryption
	local provider = (options and options.Crypto) or (configured and configured.Crypto) or RiftUI.ConfigCrypto or (typeof(crypt) == "table" and crypt)
	assert(type(provider) == "table", "crypto provider unavailable")
	local key = (options and options.Key) or (configured and configured.Key)
	if type(key) == "function" then key = key() end
	assert(type(key) == "string" and #key == 44 and string.match(key, "^[%w+/]+=$"), "a 32-byte Base64 key is required")
	local raw = provider.base64decode(key)
	assert(#raw == 32 and provider.base64encode(raw) == key, "a 32-byte Base64 key is required")
	-- Independent encryption and authentication keys derived from a random master key.
	return provider, provider.base64encode(hmac(provider, raw, "RiftUI config encryption v1")), hmac(provider, raw, "RiftUI config authentication v1")
end

function Hub:_encryptConfig(payload, options)
	local ok, envelope = pcall(function()
		local provider, aesKey, macKey = self:_configKeys(options)
		local json = HttpService:JSONEncode(payload)
		assert(#json <= CONFIG_LIMIT, "config too large")
		local iv = provider.generatebytes(16)
		assert(type(iv) == "string" and #provider.base64decode(iv) == 16, "invalid IV")
		local ciphertext = provider.encrypt(json, aesKey, iv, "CBC")
		assert(type(ciphertext) == "string" and #ciphertext <= CONFIG_LIMIT * 2, "invalid ciphertext")
		local bytes = provider.base64decode(ciphertext)
		assert(#bytes > 0 and #bytes % 16 == 0 and provider.base64encode(bytes) == ciphertext, "Base64 ciphertext required")
		local out = { Format = CONFIG_ENCRYPTED, Version = 1, Algorithm = CONFIG_CIPHER, IV = iv, Ciphertext = ciphertext }
		out.Tag = hexBytes(hmac(provider, macKey, authenticatedText(out)))
		return out
	end)
	if not ok then return nil, "couldn't encrypt config; check the key and crypto provider" end
	return envelope
end

function Hub:_decodeConfig(value, options)
	local original
	local ok, payload = pcall(function()
		if type(value) == "string" then
			assert(#value <= CONFIG_LIMIT * 2, "config too large")
			value = HttpService:JSONDecode(value)
		end
		assert(type(value) == "table", "invalid config")
		if value.Format == CONFIG_ENCRYPTED then
			original = value
			assert(value.Version == 1 and value.Algorithm == CONFIG_CIPHER, "unsupported encrypted config")
			assert(type(value.IV) == "string" and #value.IV == 24 and type(value.Ciphertext) == "string" and #value.Ciphertext <= CONFIG_LIMIT * 2, "invalid ciphertext")
			local provider, aesKey, macKey = self:_configKeys(options)
			assert(sameTag(value.Tag, hexBytes(hmac(provider, macKey, authenticatedText(value)))), "authentication failed")
			-- Verify the MAC before the AES provider sees ciphertext.
			local plain = provider.decrypt(value.Ciphertext, aesKey, value.IV, "CBC")
			assert(type(plain) == "string" and #plain <= CONFIG_LIMIT, "invalid plaintext")
			value = HttpService:JSONDecode(plain)
		end
		-- Plain local configs predate the sharing envelope.
		if value.Flags then
			assert(not (options and options.Remote), "remote config must identify its hub")
			value = { Hub = self.Id, Data = value }
		end
		assert(type(value) == "table" and value.Hub == self.Id and type(value.Data) == "table" and type(value.Data.Flags) == "table", "wrong hub or invalid config")
		local data = value.Data
		assert(data.Scale == nil or (type(data.Scale) == "number" and data.Scale == data.Scale), "invalid scale")
		assert(data.Pins == nil or type(data.Pins) == "table", "invalid pins")
		return value
	end)
	if not ok then return nil, "config is invalid, belongs to another hub, or its key/authentication is incorrect" end
	return payload, nil, original
end

function Hub:_writeConfig(name, payload, envelope)
	if not configName(name) then return false, "use up to 80 letters, numbers, spaces, - or _" end
	if not hasFS then return false, "this executor has no file functions" end
	local ok = pcall(function()
		ensureFolder(RiftUI.Folder) ensureFolder(self:_dir()) ensureFolder(self:_configDir())
		writefile(self:_configDir() .. "/" .. name .. ".json", HttpService:JSONEncode(envelope or payload.Data))
	end)
	if not ok then return false, "couldn't write config" end
	self:_configsChanged()
	return true, name
end

function Hub:_applyConfig(data)
	for flag, saved in data.Flags do
		local control = RiftUI.Flags[flag]
		if control and control.Section and (control.Section.Hub == self or control.Section.Hub.Gui == self.Gui) and type(saved) == "table" then pcall(decodeValue, control, saved) end
	end
	if type(data.ToggleKey) == "string" then
		local ok, key = pcall(function() return Enum.KeyCode[data.ToggleKey] end)
		if ok and key then
			self.ToggleKey = key
			if self._toggleKeyControl then self._toggleKeyControl:Set(key, true) end
		end
	end
	if type(data.CommandKey) == "string" then
		local ok, key = pcall(function() return Enum.KeyCode[data.CommandKey] end)
		if ok and key then self:SetCommandKey(key) end
	end
	if data.Scale then self:SetScale(data.Scale) end
	for _, tab in self.Tabs do
		for _, section in tab.Sections do
			local p = data.Pins and data.Pins[section.Id]
			if type(p) == "table" and type(p[1]) == "number" and type(p[2]) == "number" then
				section:Unpin() section:Pin(Vector2.new(p[1], p[2]))
			elseif section.Pinned then section:Unpin() end
		end
	end
	return true
end

function Hub:SetConfigServer(options)
	if options == nil then self._configServer = nil return true end
	local authority = type(options) == "table" and type(options.Url) == "string" and string.match(options.Url, "^https://([^/%s?#]+)")
	if not authority or string.find(authority, "@", 1, true) or string.find(options.Url, "[%s?#]") then
		return false, "config server must use an HTTPS base URL without credentials or query parameters"
	end
	if options.Token ~= nil and type(options.Token) ~= "string" and type(options.Token) ~= "function" then return false, "invalid token provider" end
	self._configServer = { Url = string.gsub(options.Url, "/+$", ""), Token = options.Token, RequireEncrypted = options.RequireEncrypted == true }
	return true
end

function Hub:LoadRemoteConfig(id, options)
	options = options or {}
	local server = self._configServer
	if not server then return false, "no config server configured" end
	if type(id) ~= "string" or #id > 80 or not string.match(id, "^[%w_-]+$") then return false, "invalid remote config ID" end
	if options.SaveAs and not configName(options.SaveAs) then return false, "invalid local config name" end
	local httpRequest = (typeof(request) == "function" and request) or (typeof(http_request) == "function" and http_request)
	if not httpRequest then return false, "remote configs require the request function" end
	local ok, response = pcall(function()
		local token = server.Token
		if type(token) == "function" then token = token(id) end
		local headers = { Accept = "application/json" }
		if token ~= nil then
			assert(type(token) == "string" and not string.find(token, "[\r\n]"), "invalid token")
			headers.Authorization = "Bearer " .. token
		end
		return httpRequest({ Url = server.Url .. "/configs/" .. id, Method = "GET", Headers = headers, Timeout = 15 })
	end)
	if not ok or type(response) ~= "table" then return false, "config server request failed; check connectivity and CORS in the simulator" end
	local status = tonumber(response.StatusCode) or 0
	if status < 200 or status >= 300 then return false, "config server returned HTTP " .. status end
	if type(response.Body) ~= "string" or #response.Body > CONFIG_LIMIT * 2 then return false, "config server returned an invalid or oversized body" end
	local decodeOptions = table.clone(options)
	decodeOptions.Remote = true
	local payload, err, envelope = self:_decodeConfig(response.Body, decodeOptions)
	if not payload then return false, err end
	if (server.RequireEncrypted or options.RequireEncrypted) and not envelope then return false, "this server requires encrypted configs" end
	-- Remote configs stay in memory unless the caller explicitly asks to cache one.
	if options.SaveAs then
		if not envelope and self._encryptConfigs then
			envelope, err = self:_encryptConfig(payload, options)
			if not envelope then return false, err end
		end
		local saved, saveError = self:_writeConfig(options.SaveAs, payload, envelope)
		if not saved then return false, saveError end
	end
	return self:_applyConfig(payload.Data)
end

function Hub:SaveConfig(name: string, options)
	name = tostring(name or "default")
	options = options or {}
	if not configName(name) then return false, "invalid config name" end
	local data = { Flags = self:_flagValues(), Pins = {}, ToggleKey = self.ToggleKey.Name, Scale = self._scale, CommandKey = self.CommandKey.Name, SavedAt = os.time() }
	for id, pos in self.Pins do data.Pins[id] = { pos.X, pos.Y } end
	local payload = { Hub = self.Id, Name = name, Data = data }
	local encrypted = options.Encrypt
	if encrypted == nil then encrypted = self._encryptConfigs end
	local envelope, err
	if encrypted then
		envelope, err = self:_encryptConfig(payload, options)
		if not envelope then return false, err end
	end
	return self:_writeConfig(name, payload, envelope)
end

-- Settings dropdowns and the config manager rebuild their lists through this.
function Hub:_configsChanged()
	for _, fn in self._configWatchers or {} do
		task.spawn(fn)
	end
end

function Hub:_watchConfigs(fn)
	self._configWatchers = self._configWatchers or {}
	table.insert(self._configWatchers, fn)
end

function Hub:LoadConfig(name: string, options)
	if not configName(name) then return false, "invalid config name" end
	if not hasFS then return false, "this executor has no file functions" end
	local path = self:_configDir() .. "/" .. name .. ".json"
	if not isfile(path) then return false, "no config named " .. name end
	local read, body = pcall(readfile, path)
	if not read then return false, "couldn't read config" end
	local payload, err = self:_decodeConfig(body, options)
	if not payload then return false, err end
	return self:_applyConfig(payload.Data)
end

function Hub:ListConfigs(): { string }
	local out = {}
	if not hasFS or typeof(listfiles) ~= "function" or not isfolder(self:_configDir()) then
		return out
	end
	for _, path in listfiles(self:_configDir()) do
		local name = string.match(path, "([^/\\]+)%.json$")
		if name then
			table.insert(out, name)
		end
	end
	table.sort(out)
	return out
end

function Hub:DeleteConfig(name: string): (boolean, string?)
	local path = self:_configDir() .. "/" .. tostring(name) .. ".json"
	if not (hasFS and typeof(delfile) == "function") then
		return false, "this executor can't delete files"
	end
	if not isfile(path) then
		return false, "no config named " .. tostring(name)
	end
	delfile(path)
	if self:GetAutoload() == name then
		self:SetAutoload(nil)
	end
	self:_configsChanged()
	return true
end

function Hub:RenameConfig(name: string, newName: string): (boolean, string?)
	newName = tostring(newName or "")
	if not string.match(newName, "^[%w%s%-_]+$") then
		return false, "use letters, numbers, spaces, - or _"
	end
	if not hasFS then
		return false, "this executor has no file functions"
	end
	local dir = self:_configDir()
	local from, to = dir .. "/" .. tostring(name) .. ".json", dir .. "/" .. newName .. ".json"
	if not isfile(from) then
		return false, "no config named " .. tostring(name)
	end
	if isfile(to) then
		return false, newName .. " already exists"
	end
	writefile(to, readfile(from))
	if typeof(delfile) == "function" then
		delfile(from)
	end
	if self:GetAutoload() == name then
		self:SetAutoload(newName)
	end
	self:_configsChanged()
	return true
end

-- Name, settings count and save time, read from the file without applying it.
function Hub:ConfigInfo(name: string)
	local path = self:_configDir() .. "/" .. tostring(name) .. ".json"
	if not hasFS or not isfile(path) then
		return nil
	end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(readfile(path))
	end)
	if not ok or type(data) ~= "table" then
		return { Name = name, Damaged = true }
	end
	if data.Format == CONFIG_ENCRYPTED then
		-- Listing files never invokes key providers or decrypts each stored preset.
		return { Name = name, Encrypted = true, Locked = self._configEncryption == nil, Autoload = self:GetAutoload() == name }
	end
	local count = 0
	for _ in data.Flags or {} do
		count += 1
	end
	return { Name = name, Settings = count, SavedAt = data.SavedAt, Autoload = self:GetAutoload() == name }
end

function Hub:GetAutoload(): string?
	local path = self:_configDir() .. "/autoload.txt"
	if not hasFS or not isfile(path) then
		return nil
	end
	local name = readfile(path)
	return name ~= "" and name or nil
end

function Hub:SetAutoload(name: string?)
	if not hasFS then
		return
	end
	ensureFolder(RiftUI.Folder)
	ensureFolder(self:_dir())
	ensureFolder(self:_configDir())
	writefile(self:_configDir() .. "/autoload.txt", name or "")
	self:_configsChanged()
end

function Hub:_autoload()
	if not hasFS or self._replaying then
		return
	end
	local path = self:_configDir() .. "/autoload.txt"
	if isfile(path) then
		local name = readfile(path)
		if name ~= "" then
			local ok, err = self:LoadConfig(name)
			if ok then
				self:Notify({ Title = "Config loaded", Content = name, Duration = 3 })
			else
				recordError("autoload failed: " .. tostring(err), nil, "config")
			end
		end
	end
end

function Hub:SetScale(scale: number)
	scale = math.clamp(scale, 0.6, 1.5)
	self._scale = scale
	self.UIScale.Scale = scale
	if self._scaleControl then self._scaleControl:Set(math.floor(scale * 100 + 0.5), true) end
	if self._open then self:_fitPanel(self._open, false) end
	task.defer(function()
		if not self._destroyed and self._open then self:_fitPanel(self._open, false) end
	end)
end

---------------------------------------------------------------- developer mode
function RiftUI:SetDeveloperMode(on: boolean)
	RiftUI.DeveloperMode = on == true
	if hasFS then
		pcall(function()
			ensureFolder(RiftUI.Folder)
			writefile(devFile(), on and "1" or "0")
		end)
	end
	for _, hub in RiftUI.Hubs do
		if on then
			hub:_buildDeveloper()
		elseif hub.DeveloperTab then
			hub:_removeTab(hub.DeveloperTab)
			hub.DeveloperTab = nil
		end
	end
	notifyListeners()
end

function Hub:_removeTab(tab)
	if self._open == tab then
		self:Close()
	end
	for _, section in tab.Sections do
		section:Unpin()
		for _, c in section.Controls do
			if c.Flag and RiftUI.Flags[c.Flag] == c then
				RiftUI.Flags[c.Flag] = nil
			end
		end
	end
	tab.Tile:Destroy()
	task.delay(0.3, function()
		tab.Page:Destroy()
	end)
	local i = table.find(self.Tabs, tab)
	if i then
		table.remove(self.Tabs, i)
	end
	if tab._stateConn then
		tab._stateConn:Disconnect()
	end
end

local function countConnections(hub): number
	local n = 0
	for _, c in hub._conns do
		if c.Connected then
			n += 1
		end
	end
	return n
end

local SUNC = { "gethui", "cloneref", "getcustomasset", "writefile", "readfile", "isfile", "makefolder", "listfiles", "setclipboard", "request", "identifyexecutor" }
local function missingFunctions(): string
	local env = getfenv(1)
	local missing = {}
	for _, name in SUNC do
		if typeof(env[name]) ~= "function" then
			table.insert(missing, name)
		end
	end
	return #missing == 0 and "None. Every function RiftUI uses is available." or table.concat(missing, ", ")
end

function Hub:_buildDeveloper()
	if self.DeveloperTab or self.Options.Settings == false then
		return
	end
	local tab = self:Tab({ Name = "Developer", Icon = "bug", Description = "State machine, errors and tools", _internal = true, _order = 950 })
	self.DeveloperTab = tab
	local state = tab:Section({ Name = "State machine", Side = "Left" })
	local current = state:_info("Current", RiftUI.State)
	local history = state:Paragraph({ Title = "Transitions", Content = "", RichText = true })
	local diag = tab:Section({ Name = "Diagnostics", Side = "Left" })
	local inst = diag:_info("Instances", "0")
	local conns = diag:_info("Connections", "0")
	local flags = diag:_info("Flags", "0")
	local sheets = diag:_info("Icon sheets", "0")
	local missing = diag:Paragraph({ Title = "Missing sUNC functions", Content = missingFunctions() })

	local errs = tab:Section({ Name = "Errors", Side = "Right" })
	local errList = errs:Paragraph({ Title = "Captured errors", Content = "" })
	errs:Button({
		Name = "Copy errors",
		Callback = function()
			local lines = {}
			for _, e in RiftUI.Errors do
				table.insert(lines, string.format("[%.2fs] (%s) %s", e.Time, e.Source, e.Message))
				if e.Trace then
					table.insert(lines, e.Trace)
				end
			end
			if typeof(setclipboard) == "function" then
				setclipboard(table.concat(lines, "\n"))
				self:Notify({ Title = "Errors copied", Content = #RiftUI.Errors .. " entries", Duration = 2 })
			end
		end,
	})
	errs:Button({
		Name = "Clear errors",
		Callback = function()
			table.clear(RiftUI.Errors)
			notifyListeners()
		end,
	})
	local actions = tab:Section({ Name = "Actions", Side = "Right" })
	actions:Button({
		Name = "Reinitialize hub",
		Callback = function()
			self:Reinitialize()
		end,
	})
	actions:Button({
		Name = "Clear cached assets",
		Callback = function()
			if typeof(delfolder) == "function" and typeof(isfolder) == "function" and isfolder(RiftUI.Folder .. "/assets") then
				delfolder(RiftUI.Folder .. "/assets")
			end
			table.clear(Assets.sheets)
			Assets.shadow = nil
			Assets.failed = false
			self:Notify({ Title = "Assets cleared", Content = "They download again on the next Reinitialize.", Duration = 3 })
		end,
	})
	actions:Button({
		Name = "Throw a test error",
		Callback = function()
			xpcall(function()
				error("test error from Developer Mode")
			end, RiftUI.HandleError)
		end,
	})
	actions:Button({
		Name = "Disable Developer Mode",
		Danger = true,
		Callback = function()
			RiftUI:SetDeveloperMode(false)
		end,
	})

	local TONE = { Ready = "rgb(120,220,150)", Failed = "rgb(255,120,120)", Unloaded = "rgb(128,128,128)" }
	local function refresh()
		if not tab.Tile.Parent then
			return
		end
		current:Set(RiftUI.State)
		local lines = {}
		for i = #RiftUI.StateHistory, math.max(1, #RiftUI.StateHistory - 7), -1 do
			local e = RiftUI.StateHistory[i]
			local detail = e.Detail and ("  " .. string.sub(tostring(e.Detail), 1, 36)) or ""
			detail = string.gsub(string.gsub(detail, "<", "&lt;"), ">", "&gt;")
			table.insert(lines, string.format('<font color="%s">%s</font>  %.2fs%s', TONE[e.State] or "rgb(200,200,200)", e.State, e.Time, detail))
		end
		history:Set(nil, table.concat(lines, "\n"))
		local n = #RiftUI.Errors
		if n == 0 then
			errList:Set("Captured errors", "No errors recorded.")
		else
			local e = {}
			for i = n, math.max(1, n - 4), -1 do
				table.insert(e, string.format("%.2fs · %s · %s", RiftUI.Errors[i].Time, RiftUI.Errors[i].Source, string.sub(RiftUI.Errors[i].Message, 1, 120)))
			end
			errList:Set(string.format("Captured errors (%d)", n), table.concat(e, "\n"))
		end
		inst:Set(tostring(#self.Gui:GetDescendants()))
		conns:Set(tostring(countConnections(self)))
		local f = 0
		for _ in RiftUI.Flags do
			f += 1
		end
		flags:Set(tostring(f))
		local sh = 0
		for _ in Assets.sheets do
			sh += 1
		end
		sheets:Set(sh .. " / " .. ICON_INDEX.Sheets)
		missing:Set(nil, missingFunctions())
	end
	tab._stateConn = RiftUI:OnStateChanged(refresh)
	refresh()
	task.spawn(function()
		while tab.Tile.Parent do
			task.wait(1)
			if self._open == tab then
				refresh()
			end
		end
	end)
end

---------------------------------------------------------------- setup: first launch
--[[
	CreateHub({ Id = "rift-hub", Setup = { Options = { { Type = "Toggle", Name = "...", Flag = "...", Default = true } } } })

	The first time a hub runs (no RiftUI/<Id>/setup.json yet) it opens a setup window:
	toolbar key, theme, the hub's own setup options, then a compatibility check that calls
	each sUNC function RiftUI relies on and warns about anything that failed.
	Setup = false turns it off.
]]

function Hub:_setupOptions()
	local setup = self.Options.Setup
	return type(setup) == "table" and setup.Options or {}
end

-- Setup options exist as flags from the start, holding the saved (or default) value.
function Hub:_registerSetupFlags()
	local savedValues = self.SetupData and self.SetupData.Options or {}
	for _, opt in self:_setupOptions() do
		if opt.Flag and not RiftUI.Flags[opt.Flag] then
			local c = { Type = opt.Type, Name = opt.Name, Flag = opt.Flag, Value = opt.Default, _internal = true, _setup = true }
			if opt.Type == "Dropdown" and opt.Multi then
				c.Value = {}
				for _, v in opt.Default or {} do
					c.Value[v] = true
				end
				c.Multi = true
			end
			function c:Set(v)
				self.Value = v
			end
			function c:Get()
				return self.Value
			end
			RiftUI.Flags[opt.Flag] = c
			local data = savedValues[opt.Flag]
			if data then
				pcall(function()
					if data.Color then
						c.Value = Color3.fromHex(data.Color)
					elseif data.Key then
						c.Value = data.Key ~= "None" and Enum.KeyCode[data.Key] or nil
					elseif data.Multi then
						c.Value = {}
						for _, v in data.Multi do
							c.Value[v] = true
						end
					else
						c.Value = data.Value
					end
				end)
			end
		end
	end
end

local function needs(...)
	for _, name in { ... } do
		if typeof(getfenv(1)[name]) ~= "function" then
			error(name .. " isn't available", 0)
		end
	end
end

-- Each check calls the real function; Severity says how bad a failure is.
function Hub:_compatChecks()
	local dir = self:_dir()
	local probe = dir .. "/.rift-probe"
	local checks = {
		{ Name = "Hidden UI container", Detail = "gethui", Severity = "warn", Impact = "The hub falls back to CoreGui, where some games can find it.", Run = function()
			needs("gethui")
			assert(typeof(gethui()) == "Instance", "gethui didn't return an Instance")
		end },
		{ Name = "Safe references", Detail = "cloneref", Severity = "warn", Impact = "Services are used directly instead of through clones.", Run = function()
			needs("cloneref")
			assert(cloneref(game:GetService("Players")).Name == "Players", "cloneref returned a broken reference")
		end },
		{ Name = "Write and read files", Detail = "writefile · readfile", Severity = "fail", Impact = "Configs, setup and cached assets can't be saved.", Run = function()
			needs("writefile", "readfile", "isfile", "makefolder", "isfolder")
			ensureFolder(RiftUI.Folder)
			ensureFolder(dir)
			writefile(probe, "rift")
			assert(readfile(probe) == "rift", "readfile returned something else")
		end },
		{ Name = "List folders", Detail = "listfiles", Severity = "warn", Impact = "Saved configs won't appear in the Saved list.", Run = function()
			needs("listfiles")
			for _, path in listfiles(dir) do
				if string.find(path, "rift%-probe") then
					return
				end
			end
			error("listfiles didn't return the file it just wrote", 0)
		end },
		{ Name = "Custom assets", Detail = "getcustomasset", Severity = "fail", Impact = "Icons show as letters and shadows are missing.", Run = function()
			needs("getcustomasset", "writefile")
			ensureFolder(RiftUI.Folder) ensureFolder(dir)
			local imageProbe = probe .. ".png"
			-- Use a real PNG: image-only executors correctly reject the text file probe.
			writefile(imageProbe, "\137\080\078\071\013\010\026\010\000\000\000\013\073\072\068\082\000\000\000\001\000\000\000\001\008\006\000\000\000\031\021\196\137\000\000\000\013\073\068\065\084\120\218\099\100\096\248\095\015\000\002\135\001\128\235\071\186\146\000\000\000\000\073\069\078\068\174\066\096\130")
			local ok, id = pcall(getcustomasset, imageProbe)
			if typeof(delfile) == "function" then pcall(delfile, imageProbe) end
			assert(ok, tostring(id))
			assert(type(id) == "string" and #id > 0, "getcustomasset returned no content id")
		end },
		{ Name = "Delete files", Detail = "delfile", Severity = "warn", Impact = "Deleted configs stay in the workspace.", Run = function()
			needs("delfile")
			delfile(probe)
			assert(not isfile(probe), "the file is still there")
		end },
		{ Name = "Download assets", Detail = "game:HttpGet", Severity = "fail", Impact = "Icons and the shadow can't be downloaded.", Run = function()
			local body = game:HttpGet(RiftUI.AssetBase .. "assets/shadow.png")
			assert(type(body) == "string" and #body > 64, "the download came back empty")
		end },
		{ Name = "Clipboard", Detail = "setclipboard", Severity = "warn", Impact = "Copy buttons won't do anything.", Run = function()
			needs("setclipboard")
		end },
		{ Name = "Web requests", Detail = "request", Severity = "warn", Impact = "Hub features that call web APIs may not work.", Run = function()
			if typeof(request) ~= "function" and typeof(http_request) ~= "function" then
				error("request isn't available", 0)
			end
		end },
	}
	local ids = {}
	for id in self._requirements do table.insert(ids, id) end
	table.sort(ids)
	for _, id in ids do
		local spec = self._requirements[id]
		table.insert(checks, { Name = spec.Name, Detail = "developer test", Severity = "warn", Impact = "Features requiring " .. id .. " stay locked.", Run = function()
			local result = self:RunRequirement(id)
			assert(result and result.Passed, result and result.Message or "test cancelled")
		end })
	end
	return checks
end

function Hub:RunCompatibilityCheck()
	local results = {}
	for _, check in self:_compatChecks() do
		local ok, err = pcall(check.Run)
		table.insert(results, { Name = check.Name, Detail = check.Detail, Ok = ok, Severity = check.Severity, Error = not ok and tostring(err) or nil, Impact = check.Impact })
	end
	RiftUI.Compatibility = results
	return results
end

-- Recolour existing objects, retaining controls, focus, pins and captured theme references.
local THEME_PROPERTIES = { "BackgroundColor3", "TextColor3", "PlaceholderColor3", "ImageColor3", "ScrollBarImageColor3", "Color" }
local THEME_TOKENS = { "Text", "SubText", "Muted", "Accent", "AccentText", "Panel", "PanelStroke", "Tile", "TileHover", "TileActive", "TileStroke", "TileActiveStroke", "Section", "SectionStroke", "Divider", "Field", "FieldStroke", "Track", "Knob", "Highlight", "Danger", "Success", "Warning", "Scrim" }

function Hub:_transitionTheme(name, overrides)
	local nextTheme = buildTheme(name, overrides or self.Options.Theme)
	local old = table.clone(self.Theme)
	self._themeBindings = self._themeBindings or setmetatable({}, { __mode = "k" })
	for _, tw in self._themeTweens or {} do
		tw:Cancel()
	end
	self._themeTweens = {}
	for _, inst in self.Gui:GetDescendants() do
		local skip = false
		local ancestor = inst
		while ancestor and ancestor ~= self.Gui do
			if ancestor:GetAttribute("ThemeSwatch") then skip = true break end
			ancestor = ancestor.Parent
		end
		if skip then continue end
		local bindings = self._themeBindings[inst] or {}
		self._themeBindings[inst] = bindings
		local goals = {}
		for _, prop in THEME_PROPERTIES do
			local ok, value = pcall(function() return inst[prop] end)
			if not ok or typeof(value) ~= "Color3" then continue end
			local explicit = themeBindings[inst] and themeBindings[inst][prop]
			local token = explicit and explicit._theme == self.Theme and explicit._key or nil
			-- Identity distinguishes equal-valued palette entries in the simulator;
			-- the stable token order also works with Roblox's value-type Color3.
			if not token then
				for _, key in THEME_TOKENS do
					if rawequal(value, old[key]) then token = key break end
				end
			end
			if not token then
				for _, key in THEME_TOKENS do
					if value == old[key] then token = key break end
				end
			end
			token = token or bindings[prop]
			if token then
				bindings[prop] = token
				goals[prop] = nextTheme[token]
			end
		end
		if next(goals) then
			table.insert(self._themeTweens, tween(inst, THEME_FADE, goals))
		end
	end
	-- Update in place: existing event handlers read the new palette too.
	for key, value in nextTheme do self.Theme[key] = value end
end

function Hub:SetTheme(name: string)
	self:_transitionTheme(name)
	self.ThemeName = name
	self.Options.ThemeName = name
	if self._themeControl then self._themeControl:Set(name, true) end
	local data = self.SetupData or {}
	data.Theme = name
	self.SetupData = data
	if hasFS then
		pcall(function()
			ensureFolder(RiftUI.Folder)
			ensureFolder(self:_dir())
			writefile(self:_dir() .. "/setup.json", HttpService:JSONEncode(data))
		end)
	end
end

local function fitModal(hub, layer, holder, width, height, onResize)
	local function fit()
		local vp = viewport() / hub._scale
		local top = topInset() / hub._scale + 8
		local w, h = math.min(width, vp.X - 24), math.min(height, vp.Y - top - 16)
		holder.Size = UDim2.fromOffset(math.max(260, w), math.max(240, h))
		holder.Position = UDim2.fromOffset(vp.X / 2, top + h / 2)
		if onResize then onResize(w, h) end
	end
	local conn = layer:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	local scaleConn = hub.UIScale:GetPropertyChangedSignal("Scale"):Connect(fit)
	layer.Destroying:Connect(function() conn:Disconnect() scaleConn:Disconnect() end)
	fit()
end

---------------------------------------------------------------- preferences
-- Small per-hub choices (watermark, keybind list, language) live in setup.json.
function Hub:_savePref(key: string, value)
	self.SetupData = self.SetupData or {}
	self.SetupData[key] = value
	if hasFS then
		pcall(function()
			ensureFolder(RiftUI.Folder)
			ensureFolder(self:_dir())
			writefile(self:_dir() .. "/setup.json", HttpService:JSONEncode(self.SetupData))
		end)
	end
end

local function dragBy(hub, handle: GuiObject, target: GuiObject, onDrop)
	local start, origin
	hub:_connect(handle.InputBegan, function(input)
		if isPointer(input) then
			start = Vector2.new(input.Position.X, input.Position.Y)
			origin = target.Position
		end
	end)
	hub:_connect(UserInputService.InputChanged, function(input)
		if start and isMove(input) then
			local d = (Vector2.new(input.Position.X, input.Position.Y) - start) / hub._scale
			target.Position = UDim2.new(origin.X.Scale, origin.X.Offset + d.X, origin.Y.Scale, origin.Y.Offset + d.Y)
		end
	end)
	hub:_connect(UserInputService.InputEnded, function(input)
		if start and isPointer(input) then
			start = nil
			if onDrop then onDrop(target.Position) end
		end
	end)
end

---------------------------------------------------------------- tooltips
-- Hovering a control for a moment shows its help text. Description fills in for controls
-- that don't print it under their name; Tooltip overrides it for any control.
function Hub:_attachTip(target: GuiObject, message: string)
	local token = 0
	self:_connect(target.MouseEnter, function()
		token += 1
		local mine = token
		task.delay(0.45, function()
			if mine ~= token or self._destroyed or self._popup then return end
			self:_showTip(target, message)
		end)
	end)
	self:_connect(target.MouseLeave, function()
		token += 1
		if self._tipFor == target then self:_hideTip() end
	end)
	self:_connect(target.InputBegan, function(input)
		if isPointer(input) then
			token += 1
			if self._tipFor == target then self:_hideTip() end
		end
	end)
end

function Hub:_showTip(target: GuiObject, message: string)
	local theme = self.Theme
	if not self._tip then
		self._tip = create("Frame", {
			Name = "ControlTip", BackgroundColor3 = themeColor(theme, "Panel"), Size = UDim2.fromOffset(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY, Visible = false, ZIndex = 95, Parent = self.Overlay,
		}, { corner(8), stroke(themeColor(theme, "PanelStroke")), padding(7, 10) })
		self._tipText = text({ Parent = self._tip, Name = "Text", TextSize = 12, TextWrapped = true, LineHeight = 1.2, TextColor3 = themeColor(theme, "Text"), Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, ZIndex = 96 })
		create("UISizeConstraint", { MaxSize = Vector2.new(260, 400), Parent = self._tipText })
		self._tipScale = create("UIScale", { Parent = self._tip })
	end
	self._tipFor = target
	self._tipText.Text = message
	local s = self._scale
	local pos, size = target.AbsolutePosition / s, target.AbsoluteSize / s
	local vp = viewport() / s
	self._tip.Visible = true
	task.defer(function()
		if self._tipFor ~= target or not self._tip then return end
		local ts = self._tip.AbsoluteSize / s
		local x = math.clamp(pos.X, 8, math.max(8, vp.X - ts.X - 8))
		local y = pos.Y + size.Y + 4
		if y + ts.Y > vp.Y - 8 then y = pos.Y - ts.Y - 4 end
		self._tip.Position = UDim2.fromOffset(x, y)
		self._tipScale.Scale = 0.96
		tween(self._tipScale, FAST, { Scale = 1 })
	end)
end

function Hub:_hideTip()
	self._tipFor = nil
	if self._tip then self._tip.Visible = false end
end

---------------------------------------------------------------- watermark
--[[
	A thin strip in the corner: hub name, frame rate, ping and local time. It is drawn from
	the theme, never steals input except for dragging, and hides in stealth mode.
]]
function Hub:SetWatermark(on, quiet: boolean?)
	on = on ~= false and on ~= nil
	if self._watermarkControl then self._watermarkControl:Set(on, true) end
	if not quiet then self:_savePref("Watermark", on) end
	if not on then
		if self._watermark then
			local wm = self._watermark
			self._watermark = nil
			tween(wm.Scale, FOLD, { Scale = 0.96 })
			tween(wm.Frame, FOLD, { BackgroundTransparency = 1 }).Completed:Connect(function() wm.Frame:Destroy() end)
			for _, conn in wm.Conns do conn:Disconnect() end
		end
		return
	end
	if self._watermark then return end
	local theme = self.Theme
	local saved = self.SetupData and self.SetupData.WatermarkPos
	local frame = create("Frame", {
		Name = "Watermark", BackgroundColor3 = themeColor(theme, "Panel"), BackgroundTransparency = 1,
		Position = saved and UDim2.fromOffset(saved[1], saved[2]) or UDim2.fromOffset(12, topInset() / self._scale + 10),
		Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, Active = true, ZIndex = 9, Parent = self.Gui,
	}, { corner(7), stroke(themeColor(theme, "PanelStroke")), padding(0, 10, 0, 8), list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
	local scale = create("UIScale", { Scale = 0.96, Parent = frame })
	if not hubMark(self.Icon, 14, theme, { LayoutOrder = 1, ZIndex = 10, Parent = frame }) then
		create("Frame", { Name = "Mark", BackgroundColor3 = themeColor(theme, "Accent"), BorderSizePixel = 0, Size = UDim2.fromOffset(2, 12), LayoutOrder = 1, ZIndex = 10, Parent = frame }, { corner(1) })
	end
	text({ Parent = frame, Name = "HubName", Text = self.Name, TextSize = 12, FontFace = inter(Enum.FontWeight.SemiBold), Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, ZIndex = 10 })
	local order = 2
	local function field(name)
		order += 1
		text({ Parent = frame, Text = "·", TextSize = 12, TextColor3 = themeColor(theme, "Muted"), Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = order, ZIndex = 10 })
		order += 1
		return text({ Parent = frame, Name = name, Text = "", FontFace = MONO, TextSize = 11, TextColor3 = themeColor(theme, "SubText"), Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = order, ZIndex = 10 })
	end
	local fps, ping, clock = field("Fps"), field("Ping"), field("Time")
	local conns = {}
	local frames, elapsed = 0, 0
	local function update()
		local p
		pcall(function() p = Players.LocalPlayer:GetNetworkPing() end)
		local pingText = p and (math.floor(p * 2000 + 0.5) .. " ms") or "— ms"
		if ping.Text ~= pingText then ping.Text = pingText end
		local now = os.date("%H:%M")
		if clock.Text ~= now then clock.Text = now end
	end
	table.insert(conns, RunService.RenderStepped:Connect(function(dt)
		frames += 1
		elapsed += dt
		if elapsed >= 0.5 then
			local f = tostring(math.floor(frames / elapsed + 0.5)) .. " fps"
			if fps.Text ~= f then fps.Text = f end
			frames, elapsed = 0, 0
			update()
		end
	end))
	fps.Text = "— fps"
	update()
	self._watermark = { Frame = frame, Scale = scale, Conns = conns }
	dragBy(self, frame, frame, function(pos) self:_savePref("WatermarkPos", { pos.X.Offset, pos.Y.Offset }) end)
	frame.Visible = true
	tween(frame, SOFT, { BackgroundTransparency = 0.04 })
	tween(scale, RISE, { Scale = 1 })
end

---------------------------------------------------------------- keybind list
function Hub:_keybindControls()
	local out = {}
	local function scan(sections)
		for _, section in sections do
			for _, c in section.Controls do
				if c.Type == "Keybind" and not c._internal and c.Value ~= nil and not table.find(out, c) then
					table.insert(out, c)
				end
			end
		end
	end
	for _, tab in self.Tabs do scan(tab.Sections) end
	for _, win in self.Windows or {} do
		for _, tab in win.Tabs do scan(tab.Sections) end
	end
	return out
end

function Hub:_keybindsChanged()
	if not self._keylist or self._keylistQueued then return end
	self._keylistQueued = true
	task.defer(function()
		self._keylistQueued = false
		if self._keylist then self._keylist.Render() end
	end)
end

function Hub:SetKeybindList(on, quiet: boolean?)
	on = on ~= false and on ~= nil
	if self._keylistControl then self._keylistControl:Set(on, true) end
	if not quiet then self:_savePref("KeybindList", on) end
	if not on then
		if self._keylist then
			local kl = self._keylist
			self._keylist = nil
			tween(kl.Scale, FOLD, { Scale = 0.96 })
			tween(kl.Frame, FOLD, { BackgroundTransparency = 1 }).Completed:Connect(function() kl.Frame:Destroy() end)
		end
		return
	end
	if self._keylist then return end
	local theme = self.Theme
	local saved = self.SetupData and self.SetupData.KeybindListPos
	local frame = create("Frame", {
		Name = "KeybindList", BackgroundColor3 = themeColor(theme, "Panel"), BackgroundTransparency = 1,
		Position = saved and UDim2.fromOffset(saved[1], saved[2]) or UDim2.fromOffset(12, topInset() / self._scale + 46),
		Size = UDim2.fromOffset(210, 0), AutomaticSize = Enum.AutomaticSize.Y, Active = true, ZIndex = 9, Parent = self.Gui,
	}, { corner(9), stroke(themeColor(theme, "PanelStroke")), padding(0, 10, 6, 10), list(Enum.FillDirection.Vertical, 0) })
	local scale = create("UIScale", { Scale = 0.96, Parent = frame })
	local head = create("Frame", { Name = "Head", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 0, ZIndex = 10, Parent = frame })
	iconLabel("keyboard", 13, theme.SubText, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), ZIndex = 11, Parent = head })
	text({ Parent = head, Text = "Keybinds", TextSize = 11, FontFace = inter(Enum.FontWeight.SemiBold), TextColor3 = themeColor(theme, "SubText"), Position = UDim2.fromOffset(20, 0), Size = UDim2.new(1, -20, 1, 0), ZIndex = 11 })
	create("Frame", { BackgroundColor3 = themeColor(theme, "Divider"), BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1), ZIndex = 11, Parent = head })
	local rows = {}
	local function render()
		for _, r in rows do r:Destroy() end
		table.clear(rows)
		local binds = self:_keybindControls()
		if #binds == 0 then
			table.insert(rows, text({ Parent = frame, Text = "No keybinds set", TextSize = 12, TextColor3 = themeColor(theme, "Muted"), Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 1, ZIndex = 10 }))
		end
		for i, c in binds do
			local available = c:IsAvailable()
			local active = available and (c.State == true or c.Mode == "Always")
			local r = create("Frame", { Name = "Bind", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = i, ZIndex = 10, Parent = frame })
			text({ Parent = r, Text = c.Name, TextSize = 12, TextColor3 = themeColor(theme, active and "Text" or "SubText"), Size = UDim2.new(1, -96, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 11 })
			create("TextLabel", {
				BackgroundColor3 = themeColor(theme, "Field"), Text = keyName(c.Value), FontFace = MONO, TextSize = 10, TextColor3 = themeColor(theme, "SubText"),
				AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -44, 0.5, 0), Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 11, Parent = r,
			}, { corner(4), stroke(themeColor(theme, "FieldStroke")), padding(0, 5), create("UISizeConstraint", { MaxSize = Vector2.new(70, 18) }) })
			local state = not available and "Locked" or c.Mode == "Always" and "Always" or (c.Mode == "Hold" and (active and "Held" or "Hold") or (active and "On" or "Off"))
			text({ Parent = r, Text = state, FontFace = inter(Enum.FontWeight.Medium), TextSize = 11, TextColor3 = themeColor(theme, active and "Accent" or "Muted"), TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 40, 1, 0), ZIndex = 11 })
			table.insert(rows, r)
		end
	end
	self._keylist = { Frame = frame, Scale = scale, Render = render }
	render()
	dragBy(self, head, frame, function(pos) self:_savePref("KeybindListPos", { pos.X.Offset, pos.Y.Offset }) end)
	frame.Visible = true
	tween(frame, SOFT, { BackgroundTransparency = 0.04 })
	tween(scale, RISE, { Scale = 1 })
end

---------------------------------------------------------------- translations
--[[
	Every label the hub draws passes through the active language. Keys are the English text;
	"{n}"-style keys match text with a changing part, so "{n} results" covers "12 results".
	Hubs add their own strings with CreateHub{ Translations = { es = { ["Aim Assist"] = "…" } } }.
]]
RiftUI.LanguageNames = { en = "English", es = "Español", pt = "Português", de = "Deutsch", fr = "Français" }
RiftUI.Translations = {
	es = {
		["Settings"] = "Ajustes", ["Toolbar, configs and about"] = "Barra, configuraciones e información", ["Interface"] = "Interfaz", ["Config"] = "Configuración",
		["Toolbar key"] = "Tecla de la barra", ["Command palette key"] = "Tecla de búsqueda", ["Interface scale"] = "Escala de interfaz", ["Theme"] = "Tema",
		["Open theme studio"] = "Abrir estudio de temas", ["Stealth mode"] = "Modo sigilo", ["Local assets only, built-in font fallback, quiet library output"] = "Solo recursos locales, fuente integrada y biblioteca silenciosa",
		["Watermark"] = "Marca de agua", ["Hub name, FPS, ping and time"] = "Nombre, FPS, ping y hora", ["Keybind list"] = "Lista de teclas", ["Bound keys and their state"] = "Teclas asignadas y su estado", ["Language"] = "Idioma",
		["Config name"] = "Nombre", ["Save"] = "Guardar", ["Saved"] = "Guardadas", ["Load selected"] = "Cargar selección", ["Autoload a config"] = "Cargar al iniciar",
		["Loads on start, before the toolbar shows"] = "Se aplica al iniciar, antes de mostrar la barra", ["Autoload config"] = "Configuración inicial", ["Manage configs"] = "Gestionar configuraciones",
		["Version"] = "Versión", ["Executor"] = "Ejecutor", ["Hub ID"] = "ID del hub", ["Run setup again"] = "Repetir configuración inicial", ["Unload hub"] = "Descargar hub", ["None"] = "Ninguna",
		["Search tabs, settings and controls"] = "Buscar pestañas, ajustes y controles", ["Recent"] = "Recientes", ["Jump to"] = "Ir a", ["Windows"] = "Ventanas", ["Actions"] = "Acciones",
		["Move"] = "Mover", ["Open"] = "Abrir", ["Close"] = "Cerrar", ["Type to search every control"] = "Escribe para buscar cualquier control", ["Tap a result to jump to it"] = "Toca un resultado para ir a él",
		["No results"] = "Sin resultados", ["{n} results"] = "{n} resultados", ["1 result"] = "1 resultado", ["Hide toolbar"] = "Ocultar barra", ["Show toolbar"] = "Mostrar barra", ["Close panel"] = "Cerrar panel",
		["Configs"] = "Configuraciones", ["Save, load and share setups for {hub}"] = "Guarda, carga y comparte ajustes de {hub}", ["Share"] = "Compartir", ["Saved configs"] = "Guardadas", ["Selected"] = "Seleccionada",
		["Load"] = "Cargar", ["Save current settings here"] = "Sobrescribir con los ajustes actuales", ["Load on start"] = "Cargar al iniciar", ["Applied when the hub starts"] = "Se aplica al iniciar el hub",
		["Rename to"] = "Renombrar a", ["New name"] = "Nuevo nombre", ["Rename"] = "Renombrar", ["Delete"] = "Eliminar", ["New config"] = "Nueva configuración", ["Name"] = "Nombre",
		["Save current settings"] = "Guardar ajustes actuales", ["Export"] = "Exportar", ["Copy share code"] = "Copiar código", ["Import"] = "Importar", ["Share code"] = "Código", ["Save as"] = "Guardar como",
		["Keep original name"] = "Mantener el nombre", ["No configs yet. Save one under New config."] = "Aún no hay configuraciones. Guarda una en Nueva configuración.",
		["Keybinds"] = "Teclas", ["On"] = "Activo", ["Off"] = "Inactivo", ["Held"] = "Pulsada", ["Hold"] = "Mantener", ["Always"] = "Siempre", ["No keybinds set"] = "No hay teclas asignadas",
		["Config saved"] = "Configuración guardada", ["Config loaded"] = "Configuración cargada", ["Autoload set"] = "Carga automática lista", ["Cancel"] = "Cancelar", ["OK"] = "Aceptar",
		["Nothing logged yet"] = "Sin registros", ["Search players"] = "Buscar jugadores", ["Left the game"] = "Salió del juego", ["Nobody else is here"] = "No hay nadie más", ["No match"] = "Sin coincidencias",
		["{n} settings · {when}"] = "{n} ajustes · {when}", ["saved just now"] = "guardada ahora", ["saved {n} min ago"] = "guardada hace {n} min", ["saved {n} h ago"] = "guardada hace {n} h", ["saved {n} d ago"] = "guardada hace {n} d", ["{when} · loads on start"] = "{when} · se carga al iniciar",
	},
	pt = {
		["Settings"] = "Configurações", ["Toolbar, configs and about"] = "Barra, perfis e sobre", ["Interface"] = "Interface", ["Config"] = "Perfil",
		["Toolbar key"] = "Tecla da barra", ["Command palette key"] = "Tecla de busca", ["Interface scale"] = "Escala da interface", ["Theme"] = "Tema",
		["Open theme studio"] = "Abrir estúdio de temas", ["Stealth mode"] = "Modo furtivo", ["Local assets only, built-in font fallback, quiet library output"] = "Apenas recursos locais, fonte interna e biblioteca silenciosa",
		["Watermark"] = "Marca d'água", ["Hub name, FPS, ping and time"] = "Nome, FPS, ping e hora", ["Keybind list"] = "Lista de teclas", ["Bound keys and their state"] = "Teclas definidas e seu estado", ["Language"] = "Idioma",
		["Config name"] = "Nome", ["Save"] = "Salvar", ["Saved"] = "Salvos", ["Load selected"] = "Carregar selecionado", ["Autoload a config"] = "Carregar ao iniciar",
		["Loads on start, before the toolbar shows"] = "Aplicado ao iniciar, antes da barra aparecer", ["Autoload config"] = "Perfil inicial", ["Manage configs"] = "Gerenciar perfis",
		["Version"] = "Versão", ["Executor"] = "Executor", ["Hub ID"] = "ID do hub", ["Run setup again"] = "Refazer configuração inicial", ["Unload hub"] = "Descarregar hub", ["None"] = "Nenhum",
		["Search tabs, settings and controls"] = "Buscar abas, configurações e controles", ["Recent"] = "Recentes", ["Jump to"] = "Ir para", ["Windows"] = "Janelas", ["Actions"] = "Ações",
		["Move"] = "Mover", ["Open"] = "Abrir", ["Close"] = "Fechar", ["Type to search every control"] = "Digite para buscar qualquer controle", ["Tap a result to jump to it"] = "Toque em um resultado para ir até ele",
		["No results"] = "Nenhum resultado", ["{n} results"] = "{n} resultados", ["1 result"] = "1 resultado", ["Hide toolbar"] = "Ocultar barra", ["Show toolbar"] = "Mostrar barra", ["Close panel"] = "Fechar painel",
		["Configs"] = "Perfis", ["Save, load and share setups for {hub}"] = "Salve, carregue e compartilhe perfis de {hub}", ["Share"] = "Compartilhar", ["Saved configs"] = "Perfis salvos", ["Selected"] = "Selecionado",
		["Load"] = "Carregar", ["Save current settings here"] = "Sobrescrever com as configurações atuais", ["Load on start"] = "Carregar ao iniciar", ["Applied when the hub starts"] = "Aplicado quando o hub inicia",
		["Rename to"] = "Renomear para", ["New name"] = "Novo nome", ["Rename"] = "Renomear", ["Delete"] = "Excluir", ["New config"] = "Novo perfil", ["Name"] = "Nome",
		["Save current settings"] = "Salvar configurações atuais", ["Export"] = "Exportar", ["Copy share code"] = "Copiar código", ["Import"] = "Importar", ["Share code"] = "Código", ["Save as"] = "Salvar como",
		["Keep original name"] = "Manter o nome", ["No configs yet. Save one under New config."] = "Nenhum perfil ainda. Salve um em Novo perfil.",
		["Keybinds"] = "Teclas", ["On"] = "Ligado", ["Off"] = "Desligado", ["Held"] = "Segurando", ["Hold"] = "Segurar", ["Always"] = "Sempre", ["No keybinds set"] = "Nenhuma tecla definida",
		["Config saved"] = "Perfil salvo", ["Config loaded"] = "Perfil carregado", ["Autoload set"] = "Carregamento automático definido", ["Cancel"] = "Cancelar", ["OK"] = "OK",
		["Nothing logged yet"] = "Nada registrado", ["Search players"] = "Buscar jogadores", ["Left the game"] = "Saiu do jogo", ["Nobody else is here"] = "Ninguém mais aqui", ["No match"] = "Nada encontrado",
		["{n} settings · {when}"] = "{n} ajustes · {when}", ["saved just now"] = "salvo agora", ["saved {n} min ago"] = "salvo há {n} min", ["saved {n} h ago"] = "salvo há {n} h", ["saved {n} d ago"] = "salvo há {n} d", ["{when} · loads on start"] = "{when} · carrega ao iniciar",
	},
	de = {
		["Settings"] = "Einstellungen", ["Toolbar, configs and about"] = "Leiste, Profile und Info", ["Interface"] = "Oberfläche", ["Config"] = "Profil",
		["Toolbar key"] = "Leistentaste", ["Command palette key"] = "Suchtaste", ["Interface scale"] = "Skalierung", ["Theme"] = "Design",
		["Open theme studio"] = "Design-Studio öffnen", ["Stealth mode"] = "Tarnmodus", ["Local assets only, built-in font fallback, quiet library output"] = "Nur lokale Assets, integrierte Schrift und stille Bibliothek",
		["Watermark"] = "Wasserzeichen", ["Hub name, FPS, ping and time"] = "Name, FPS, Ping und Uhrzeit", ["Keybind list"] = "Tastenliste", ["Bound keys and their state"] = "Belegte Tasten und ihr Zustand", ["Language"] = "Sprache",
		["Config name"] = "Name", ["Save"] = "Speichern", ["Saved"] = "Gespeichert", ["Load selected"] = "Auswahl laden", ["Autoload a config"] = "Beim Start laden",
		["Loads on start, before the toolbar shows"] = "Wird beim Start geladen, bevor die Leiste erscheint", ["Autoload config"] = "Startprofil", ["Manage configs"] = "Profile verwalten",
		["Version"] = "Version", ["Executor"] = "Executor", ["Hub ID"] = "Hub-ID", ["Run setup again"] = "Einrichtung wiederholen", ["Unload hub"] = "Hub entladen", ["None"] = "Keins",
		["Search tabs, settings and controls"] = "Tabs, Einstellungen und Regler suchen", ["Recent"] = "Zuletzt", ["Jump to"] = "Springen zu", ["Windows"] = "Fenster", ["Actions"] = "Aktionen",
		["Move"] = "Bewegen", ["Open"] = "Öffnen", ["Close"] = "Schließen", ["Type to search every control"] = "Tippen, um alles zu durchsuchen", ["Tap a result to jump to it"] = "Ergebnis antippen, um hinzuspringen",
		["No results"] = "Keine Treffer", ["{n} results"] = "{n} Treffer", ["1 result"] = "1 Treffer", ["Hide toolbar"] = "Leiste ausblenden", ["Show toolbar"] = "Leiste einblenden", ["Close panel"] = "Panel schließen",
		["Configs"] = "Profile", ["Save, load and share setups for {hub}"] = "Profile für {hub} speichern, laden und teilen", ["Share"] = "Teilen", ["Saved configs"] = "Gespeicherte Profile", ["Selected"] = "Ausgewählt",
		["Load"] = "Laden", ["Save current settings here"] = "Mit aktuellen Werten überschreiben", ["Load on start"] = "Beim Start laden", ["Applied when the hub starts"] = "Wird beim Start des Hubs angewendet",
		["Rename to"] = "Umbenennen in", ["New name"] = "Neuer Name", ["Rename"] = "Umbenennen", ["Delete"] = "Löschen", ["New config"] = "Neues Profil", ["Name"] = "Name",
		["Save current settings"] = "Aktuelle Werte speichern", ["Export"] = "Exportieren", ["Copy share code"] = "Code kopieren", ["Import"] = "Importieren", ["Share code"] = "Code", ["Save as"] = "Speichern als",
		["Keep original name"] = "Namen beibehalten", ["No configs yet. Save one under New config."] = "Noch keine Profile. Speichere eins unter Neues Profil.",
		["Keybinds"] = "Tasten", ["On"] = "An", ["Off"] = "Aus", ["Held"] = "Gehalten", ["Hold"] = "Halten", ["Always"] = "Immer", ["No keybinds set"] = "Keine Tasten belegt",
		["Config saved"] = "Profil gespeichert", ["Config loaded"] = "Profil geladen", ["Autoload set"] = "Startprofil gesetzt", ["Cancel"] = "Abbrechen", ["OK"] = "OK",
		["Nothing logged yet"] = "Noch keine Einträge", ["Search players"] = "Spieler suchen", ["Left the game"] = "Hat das Spiel verlassen", ["Nobody else is here"] = "Sonst ist niemand hier", ["No match"] = "Kein Treffer",
		["{n} settings · {when}"] = "{n} Werte · {when}", ["saved just now"] = "gerade gespeichert", ["saved {n} min ago"] = "vor {n} Min. gespeichert", ["saved {n} h ago"] = "vor {n} Std. gespeichert", ["saved {n} d ago"] = "vor {n} T. gespeichert", ["{when} · loads on start"] = "{when} · lädt beim Start",
	},
	fr = {
		["Settings"] = "Réglages", ["Toolbar, configs and about"] = "Barre, profils et infos", ["Interface"] = "Interface", ["Config"] = "Profil",
		["Toolbar key"] = "Touche de la barre", ["Command palette key"] = "Touche de recherche", ["Interface scale"] = "Échelle", ["Theme"] = "Thème",
		["Open theme studio"] = "Ouvrir le studio de thèmes", ["Stealth mode"] = "Mode discret", ["Local assets only, built-in font fallback, quiet library output"] = "Ressources locales, police intégrée et bibliothèque silencieuse",
		["Watermark"] = "Filigrane", ["Hub name, FPS, ping and time"] = "Nom, FPS, ping et heure", ["Keybind list"] = "Liste des touches", ["Bound keys and their state"] = "Touches assignées et leur état", ["Language"] = "Langue",
		["Config name"] = "Nom", ["Save"] = "Enregistrer", ["Saved"] = "Enregistrés", ["Load selected"] = "Charger la sélection", ["Autoload a config"] = "Charger au lancement",
		["Loads on start, before the toolbar shows"] = "Appliqué au lancement, avant l'affichage de la barre", ["Autoload config"] = "Profil de départ", ["Manage configs"] = "Gérer les profils",
		["Version"] = "Version", ["Executor"] = "Exécuteur", ["Hub ID"] = "ID du hub", ["Run setup again"] = "Relancer la configuration", ["Unload hub"] = "Décharger le hub", ["None"] = "Aucun",
		["Search tabs, settings and controls"] = "Rechercher onglets, réglages et contrôles", ["Recent"] = "Récents", ["Jump to"] = "Aller à", ["Windows"] = "Fenêtres", ["Actions"] = "Actions",
		["Move"] = "Naviguer", ["Open"] = "Ouvrir", ["Close"] = "Fermer", ["Type to search every control"] = "Tapez pour chercher un contrôle", ["Tap a result to jump to it"] = "Touchez un résultat pour y aller",
		["No results"] = "Aucun résultat", ["{n} results"] = "{n} résultats", ["1 result"] = "1 résultat", ["Hide toolbar"] = "Masquer la barre", ["Show toolbar"] = "Afficher la barre", ["Close panel"] = "Fermer le panneau",
		["Configs"] = "Profils", ["Save, load and share setups for {hub}"] = "Enregistrez, chargez et partagez les profils de {hub}", ["Share"] = "Partager", ["Saved configs"] = "Profils enregistrés", ["Selected"] = "Sélection",
		["Load"] = "Charger", ["Save current settings here"] = "Écraser avec les réglages actuels", ["Load on start"] = "Charger au lancement", ["Applied when the hub starts"] = "Appliqué au lancement du hub",
		["Rename to"] = "Renommer en", ["New name"] = "Nouveau nom", ["Rename"] = "Renommer", ["Delete"] = "Supprimer", ["New config"] = "Nouveau profil", ["Name"] = "Nom",
		["Save current settings"] = "Enregistrer les réglages actuels", ["Export"] = "Exporter", ["Copy share code"] = "Copier le code", ["Import"] = "Importer", ["Share code"] = "Code", ["Save as"] = "Enregistrer sous",
		["Keep original name"] = "Garder le nom", ["No configs yet. Save one under New config."] = "Aucun profil. Enregistrez-en un dans Nouveau profil.",
		["Keybinds"] = "Touches", ["On"] = "Actif", ["Off"] = "Inactif", ["Held"] = "Maintenue", ["Hold"] = "Maintenir", ["Always"] = "Toujours", ["No keybinds set"] = "Aucune touche assignée",
		["Config saved"] = "Profil enregistré", ["Config loaded"] = "Profil chargé", ["Autoload set"] = "Chargement auto défini", ["Cancel"] = "Annuler", ["OK"] = "OK",
		["Nothing logged yet"] = "Rien pour l'instant", ["Search players"] = "Rechercher des joueurs", ["Left the game"] = "A quitté la partie", ["Nobody else is here"] = "Personne d'autre ici", ["No match"] = "Aucun résultat",
		["{n} settings · {when}"] = "{n} réglages · {when}", ["saved just now"] = "enregistré à l'instant", ["saved {n} min ago"] = "enregistré il y a {n} min", ["saved {n} h ago"] = "enregistré il y a {n} h", ["saved {n} d ago"] = "enregistré il y a {n} j", ["{when} · loads on start"] = "{when} · chargé au lancement",
	},
}

local function compileDictionary(dict)
	local exact, patterns, upper = {}, {}, {}
	for key, value in dict do
		if string.find(key, "{%w+}") then
			local names = {}
			local pat = string.gsub(key, "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
			pat = string.gsub(pat, "{(%w+)}", function(name)
				table.insert(names, name)
				return "(.-)"
			end)
			table.insert(patterns, { Pattern = "^" .. pat .. "$", Names = names, Value = value })
		else
			exact[key] = value
			upper[string.upper(key)] = string.upper(value)
		end
	end
	return { Exact = exact, Patterns = patterns, Upper = upper }
end

function Hub:T(source: string): string
	local dict = self._dictionary
	if not dict or type(source) ~= "string" or source == "" then return source end
	local hit = dict.Exact[source] or dict.Upper[source]
	if hit then return hit end
	for _, p in dict.Patterns do
		local caps = { string.match(source, p.Pattern) }
		if #caps > 0 then
			local out = p.Value
			for i, name in p.Names do
				-- captured parts may themselves be translatable ("{when}")
				out = string.gsub(out, "{" .. name .. "}", function() return self:T(caps[i]) end)
			end
			return out
		end
	end
	return source
end

function Hub:Languages(): { string }
	local seen, out = { en = true }, { "en" }
	for code in RiftUI.Translations do
		if not seen[code] then seen[code] = true table.insert(out, code) end
	end
	for code in self.Options.Translations or {} do
		if not seen[code] then seen[code] = true table.insert(out, code) end
	end
	table.sort(out, function(a, b) return a == "en" or (b ~= "en" and a < b) end)
	return out
end

function Hub:SetLanguage(code: string?, quiet: boolean?)
	code = code or "en"
	self.Language = code
	if not quiet then self:_savePref("Language", code) end
	if code == "en" then
		self._dictionary = nil
	else
		local merged = {}
		for k, v in RiftUI.Translations[code] or {} do merged[k] = v end
		for k, v in (self.Options.Translations or {})[code] or {} do merged[k] = v end
		self._dictionary = compileDictionary(merged)
	end
	if self._languageControl then
		self._languageControl:Set(RiftUI.LanguageNames[code] or code, true)
	end
	self:_translateAll()
end

-- Watches every text instance once; the English source is remembered so switching
-- languages back and forth never translates a translation.
function Hub:_watchText(inst: Instance)
	if not (inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox")) then return end
	local state = self._textSources[inst]
	if state then return end
	state = {}
	self._textSources[inst] = state
	local function apply(prop)
		local current = inst[prop]
		if current ~= state[prop .. "Out"] then
			state[prop] = current
		end
		local out = self:T(state[prop])
		state[prop .. "Out"] = out
		if inst[prop] ~= out then inst[prop] = out end
	end
	state.Apply = function()
		if not inst:IsA("TextBox") then apply("Text") end
		if inst:IsA("TextBox") then apply("PlaceholderText") end
	end
	if not inst:IsA("TextBox") then
		inst:GetPropertyChangedSignal("Text"):Connect(function()
			if self._dictionary or state.TextOut then apply("Text") end
		end)
	else
		inst:GetPropertyChangedSignal("PlaceholderText"):Connect(function()
			if self._dictionary or state.PlaceholderTextOut then apply("PlaceholderText") end
		end)
	end
	state.Apply()
end

function Hub:_translateAll()
	if not self._textSources then
		self._textSources = setmetatable({}, { __mode = "k" })
		self:_connect(self.Gui.DescendantAdded, function(inst)
			if self._dictionary then self:_watchText(inst) end
		end)
	end
	if not self._dictionary and not next(self._textSources) then return end
	for _, inst in self.Gui:GetDescendants() do
		local state = self._textSources[inst]
		if state then state.Apply() elseif self._dictionary then self:_watchText(inst) end
	end
end

---------------------------------------------------------------- child windows
--[[
	A window opens over the hub from a button, a palette entry or code. It holds its own tabs
	and sections, built from the same controls as the panel, so a long feature can move its
	detail out of the main page: Section:Button({ Name = "ESP colours", Window = EspWindow }).
]]
local Window = {}
Window.__index = Window

local WindowTab = setmetatable({}, { __index = Tab })
WindowTab.__index = WindowTab

function WindowTab:Section(options)
	options = type(options) == "table" and table.clone(options) or { Name = tostring(options) }
	-- Windows are modal; pinning a section out of one would strand it on screen.
	options.Pinnable = false
	return Tab.Section(self, options)
end

function Hub:Window(options)
	options = type(options) == "table" and options or { Title = tostring(options) }
	local theme = self.Theme
	local width, height = options.Width or 560, options.Height or 440
	local win = setmetatable({
		Hub = self,
		Title = options.Title or options.Name or "Window",
		Description = options.Description,
		Icon = options.Icon,
		Tabs = {},
		IsOpen = false,
		_internal = options._internal,
	}, Window)
	win.Name = win.Title

	local layer = create("TextButton", {
		Name = "Window_" .. win.Title, Text = "", AutoButtonColor = false,
		BackgroundColor3 = themeColor(theme, "Scrim"), BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 70, Parent = self.Gui,
	})
	local holder = create("Frame", {
		Name = "Holder", BackgroundTransparency = 1, Active = true,
		AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(width, height), ZIndex = 71, Parent = layer,
	})
	local grow = create("UIScale", { Scale = 0.96, Parent = holder })
	shadow(holder, 34, 71, 10)
	local body = create("CanvasGroup", {
		Name = "Body", BackgroundColor3 = themeColor(theme, "Panel"),
		Size = UDim2.fromScale(1, 1), GroupTransparency = 1, ZIndex = 72, Parent = holder,
	}, { corner(14) })
	local outline = stroke(themeColor(theme, "PanelStroke"))
	outline.Transparency = 1
	create("Frame", { Name = "Outline", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 80, Parent = holder }, { corner(14), outline })
	sheen(body, 16, theme, 79)

	-- header: icon chip, title, description, close
	local chip = create("Frame", { Name = "Chip", BackgroundColor3 = themeColor(theme, "Tile"), Position = UDim2.fromOffset(16, 14), Size = UDim2.fromOffset(32, 32), ZIndex = 73, Parent = body }, { corner(8), stroke(themeColor(theme, "TileStroke")) })
	if not iconLabel(win.Icon, 16, theme.Text, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 74, Parent = chip }) then
		text({ Parent = chip, Text = string.upper(string.sub(win.Title, 1, 1)), FontFace = inter(Enum.FontWeight.SemiBold), Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 74 })
	end
	local hasSub = (win.Description or "") ~= ""
	win._titleLabel = text({ Parent = body, Name = "Title", Text = win.Title, FontFace = inter(Enum.FontWeight.SemiBold), TextSize = 15, Position = UDim2.fromOffset(60, hasSub and 13 or 21), Size = UDim2.new(1, -120, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 73 })
	if hasSub then
		win._descriptionLabel = text({ Parent = body, Name = "Description", Text = win.Description, TextSize = 12, TextColor3 = themeColor(theme, "SubText"), Position = UDim2.fromOffset(60, 31), Size = UDim2.new(1, -120, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 73 })
	end
	local close = create("TextButton", { Name = "CloseWindow", BackgroundTransparency = 1, Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), Size = UDim2.fromOffset(44, 44), ZIndex = 74, Parent = body })
	local closeIcon = iconLabel("x", 16, theme.SubText, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 75, Parent = close })
	self:_connect(close.MouseEnter, function() if closeIcon then setThemed(closeIcon, "ImageColor3", themeColor(theme, "Text")) end end)
	self:_connect(close.MouseLeave, function() if closeIcon then setThemed(closeIcon, "ImageColor3", themeColor(theme, "SubText")) end end)

	-- tab strip, shown once there are two tabs
	local strip = create("Frame", { Name = "TabStrip", BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 58), Size = UDim2.new(1, -32, 0, 30), Visible = false, ZIndex = 73, Parent = body }, {
		list(Enum.FillDirection.Horizontal, 2, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
	})
	local marker = create("Frame", { Name = "TabMarker", BackgroundColor3 = themeColor(theme, "Accent"), BorderSizePixel = 0, Position = UDim2.fromOffset(16, 89), Size = UDim2.fromOffset(0, 2), ZIndex = 75, Parent = body }, { corner(1) })
	local rule = create("Frame", { Name = "Rule", BackgroundColor3 = themeColor(theme, "Divider"), BorderSizePixel = 0, Position = UDim2.fromOffset(0, 60), Size = UDim2.new(1, 0, 0, 1), ZIndex = 73, Parent = body })
	local pages = create("Frame", { Name = "Pages", BackgroundTransparency = 1, ClipsDescendants = true, Position = UDim2.fromOffset(0, 61), Size = UDim2.new(1, 0, 1, -61), ZIndex = 73, Parent = body })

	win.Layer, win.Holder, win.Body, win.Pages, win.Strip = layer, holder, body, pages, strip
	win._grow, win._outline, win._marker, win._rule = grow, outline, marker, rule
	win._narrow = false
	fitModal(self, layer, holder, width, height, function(w)
		local narrow = w < 500
		if narrow == win._narrow then return end
		win._narrow = narrow
		for _, tab in win.Tabs do tab:_arrange(narrow) end
	end)
	win._narrow = (holder.AbsoluteSize.X / self._scale) < 500
	self:_connect(close.MouseButton1Click, function() win:Close() end)
	self:_connect(layer.MouseButton1Click, function() win:Close() end)
	self.Windows = self.Windows or {}
	table.insert(self.Windows, win)
	self:_record(self, "Window", options, win)
	return win
end

---------------------------------------------------------------- social buttons
-- Brand colours and marks are the platforms' own; they don't follow the theme.
local SOCIALS = {
	Discord = {
		Label = "Discord",
		Color = Color3.fromRGB(88, 101, 242), -- Blurple, #5865F2
		Hover = Color3.fromRGB(71, 82, 196),
		Asset = "discord-1.png",
		Remote = "assets/brand/discord.png",
		Url = function(value: string): string?
			value = string.gsub(value, "^%s*(.-)%s*$", "%1")
			if string.match(value, "^[%w%-]+$") then return "https://discord.gg/" .. value end
			local code = string.match(value, "^https://discord%.gg/([%w%-]+)/?$")
				or string.match(value, "^https://discord%.com/invite/([%w%-]+)/?$")
				or string.match(value, "^https://discordapp%.com/invite/([%w%-]+)/?$")
			return code and ("https://discord.gg/" .. code) or nil
		end,
	},
}

local function brandMark(platform: string)
	local spec = SOCIALS[platform]
	Assets.brands = Assets.brands or {}
	if Assets.brands[platform] == nil then
		-- a missing brand mark leaves the label alone; it must not switch off every icon
		local failed = Assets.failed
		Assets.brands[platform] = customAsset(spec.Asset, spec.Remote) or false
		Assets.failed = failed
	end
	return Assets.brands[platform] or nil
end

--[[
	A brand-coloured button in the window header that copies an invite link.
		Window:SocialButton({ Discord = "https://discord.gg/your-invite" })
	A bare invite code works too. Narrow windows drop the label and keep the mark.
]]
function Window:SocialButton(options)
	assert(type(options) == "table", "SocialButton expects an options table")
	local platform, raw
	for name in SOCIALS do
		if options[name] ~= nil then
			assert(platform == nil, "SocialButton takes one platform per button")
			platform, raw = name, options[name]
		end
	end
	assert(platform, "SocialButton needs a platform, such as Discord = \"https://discord.gg/...\"")
	local spec = SOCIALS[platform]
	local url = type(raw) == "string" and spec.Url(raw)
	assert(url, platform .. " needs an invite link, such as https://discord.gg/your-invite")
	local hub = self.Hub
	if self._social then self._social:Destroy() end
	local button = create("TextButton", {
		Name = "Social_" .. platform, BackgroundColor3 = spec.Color, Text = "", AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -54, 0, 30), Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X, ZIndex = 74, Parent = self.Body,
	}, { corner(8), padding(0, 10), list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	local mark = brandMark(platform)
	if mark then
		create("ImageLabel", { Name = "Mark", BackgroundTransparency = 1, Image = mark, ImageColor3 = Color3.new(1, 1, 1), ScaleType = Enum.ScaleType.Fit, Size = UDim2.fromOffset(18, 18), ZIndex = 75, Parent = button })
	end
	local label = text({ Parent = button, Name = "Label", Text = hub:T(options.Label or spec.Label), FontFace = inter(Enum.FontWeight.SemiBold), TextSize = 13, TextColor3 = Color3.new(1, 1, 1), Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, ZIndex = 75 })
	create("UISizeConstraint", { MinSize = Vector2.new(34, 30), Parent = button })
	local function fit()
		-- the title gives up the room the button takes; a narrow window keeps only the mark
		label.Visible = not mark or (self.Holder.AbsoluteSize.X / hub._scale) >= 420
		local w = button.AbsoluteSize.X / hub._scale
		for _, l in { self._titleLabel, self._descriptionLabel } do
			if l then l.Size = UDim2.new(1, -120 - math.ceil(w) - 6, l.Size.Y.Scale, l.Size.Y.Offset) end
		end
	end
	local conns = {
		button:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit),
		self.Holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit),
		button.MouseEnter:Connect(function() tween(button, FAST, { BackgroundColor3 = spec.Hover }) hub:_showTip(button, url) end),
		button.MouseLeave:Connect(function() tween(button, FAST, { BackgroundColor3 = spec.Color }) if hub._tipFor == button then hub:_hideTip() end end),
		button.MouseButton1Click:Connect(function()
			if typeof(setclipboard) == "function" and pcall(setclipboard, url) then
				hub:Notify({ Title = platform .. " invite copied", Content = "Paste it into your browser or " .. platform .. ".", Icon = "check", Duration = 3 })
			else
				hub:Notify({ Title = platform .. " invite", Content = url, Duration = 8 })
			end
			if type(options.Callback) == "function" then task.spawn(options.Callback, url) end
		end),
	}
	fit()
	local social = { Platform = platform, Url = url, Frame = button, _internal = self._internal }
	function social:SetVisible(v: boolean)
		button.Visible = v
	end
	local window = self
	function social:Destroy()
		for _, c in conns do c:Disconnect() end
		button:Destroy()
		if window._social == social then
			window._social = nil
			for _, l in { window._titleLabel, window._descriptionLabel } do
				if l then l.Size = UDim2.new(1, -120, l.Size.Y.Scale, l.Size.Y.Offset) end
			end
		end
	end
	self._social = social
	hub:_record(self, "SocialButton", options, social)
	return social
end

function Window:_layoutStrip()
	local multi = #self.Tabs > 1
	self.Strip.Visible = multi
	self._marker.Visible = multi
	local top = multi and 92 or 61
	self._rule.Position = UDim2.fromOffset(0, top - 1)
	self.Pages.Position = UDim2.fromOffset(0, top)
	self.Pages.Size = UDim2.new(1, 0, 1, -top)
end

function Window:Tab(options)
	options = type(options) == "table" and options or { Name = tostring(options) }
	local hub, theme = self.Hub, self.Hub.Theme
	local tab = setmetatable({
		Hub = hub,
		Window = self,
		Name = options.Name or "Tab",
		Icon = options.Icon,
		Sections = {},
		_internal = self._internal,
		_recount = function() end,
	}, WindowTab)
	local button = create("TextButton", {
		Name = "WindowTab_" .. tab.Name, BackgroundTransparency = 1, AutoButtonColor = false,
		Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, Text = "",
		LayoutOrder = #self.Tabs + 1, ZIndex = 74, Parent = self.Strip,
	}, { padding(0, 10), list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
	local icon = iconLabel(tab.Icon, 14, theme.SubText, { ZIndex = 75, Parent = button })
	local label = text({ Parent = button, Text = tab.Name, TextSize = 13, FontFace = inter(Enum.FontWeight.Medium), TextColor3 = themeColor(theme, "SubText"), Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, ZIndex = 75 })
	tab.Button, tab._label, tab._icon = button, label, icon

	local page = create("Frame", { Name = "WindowPage_" .. tab.Name, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 73, Parent = self.Pages })
	local scroll = create("ScrollingFrame", {
		Name = "Scroll", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3, ScrollBarImageColor3 = themeColor(theme, "Knob"), ScrollBarImageTransparency = 0.4,
		ScrollingDirection = Enum.ScrollingDirection.Y, ZIndex = 73, Parent = page,
	})
	local columns = create("Frame", { Name = "Columns", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 73, Parent = scroll }, {
		padding(10, 16, 14, 16),
	})
	local flow = list(Enum.FillDirection.Horizontal, 18)
	flow.Parent = columns
	local function column(side)
		return create("Frame", {
			Name = side == 0 and "Left" or "Right", BackgroundTransparency = 1,
			Size = UDim2.new(0.5, -9, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = side, ZIndex = 73, Parent = columns,
		}, { list(Enum.FillDirection.Vertical, 10) })
	end
	tab.Page, tab.Scroll = page, scroll
	tab.Columns = { column(0), column(1), Frame = columns }
	-- Narrow windows stack the right column under the left one.
	function tab:_arrange(narrow)
		flow.FillDirection = narrow and Enum.FillDirection.Vertical or Enum.FillDirection.Horizontal
		flow.Padding = UDim.new(0, narrow and 10 or 18)
		for i = 1, 2 do
			self.Columns[i].Size = narrow and UDim2.new(1, 0, 0, 0) or UDim2.new(0.5, -9, 0, 0)
		end
	end
	tab:_arrange(self._narrow)

	hub:_connect(button.MouseButton1Click, function() self:SelectTab(tab) end)
	hub:_connect(button.MouseEnter, function()
		if self.Selected ~= tab then setThemed(label, "TextColor3", themeColor(theme, "Text")) end
	end)
	hub:_connect(button.MouseLeave, function()
		if self.Selected ~= tab then setThemed(label, "TextColor3", themeColor(theme, "SubText")) end
	end)
	hub:_connect(button:GetPropertyChangedSignal("AbsoluteSize"), function()
		if self.Selected == tab then self:_moveMarker(false) end
	end)
	table.insert(self.Tabs, tab)
	self:_layoutStrip()
	if not self.Selected then self:SelectTab(tab, true) end
	hub:_record(self, "Tab", options, tab)
	return tab
end

function Window:Section(options)
	if not self._defaultTab then
		self._defaultTab = self:Tab({ Name = "Main" })
	end
	return self._defaultTab:Section(options)
end

function Window:_moveMarker(animate: boolean)
	local tab = self.Selected
	if not tab then return end
	local scale = self.Hub._scale
	local x = (tab.Button.AbsolutePosition.X - self.Body.AbsolutePosition.X) / scale + 10
	local w = math.max(0, tab.Button.AbsoluteSize.X / scale - 20)
	local goal = { Position = UDim2.fromOffset(x, 89), Size = UDim2.fromOffset(w, 2) }
	if animate then
		tween(self._marker, SETTLE, goal)
	else
		self._marker.Position, self._marker.Size = goal.Position, goal.Size
	end
end

function Window:SelectTab(tab, instant: boolean?)
	if type(tab) == "string" then
		for _, t in self.Tabs do
			if t.Name == tab then tab = t break end
		end
	end
	if type(tab) ~= "table" or tab.Window ~= self then return end
	local previous = self.Selected
	if previous == tab then return end
	local theme = self.Hub.Theme
	self.Selected = tab
	local order = table.find(self.Tabs, tab) or 0
	local fromOrder = previous and table.find(self.Tabs, previous) or order
	for _, t in self.Tabs do
		local on = t == tab
		t.Page.Visible = on
		setThemed(t._label, "TextColor3", themeColor(theme, on and "Text" or "SubText"))
		if t._icon then setThemed(t._icon, "ImageColor3", themeColor(theme, on and "Text" or "SubText")) end
	end
	if not instant and self.IsOpen then
		-- the page slides in from the side of the tab it came from
		local dir = order >= fromOrder and 1 or -1
		tab.Page.Position = UDim2.fromOffset(14 * dir, 0)
		tween(tab.Page, SETTLE, { Position = UDim2.new() })
	else
		tab.Page.Position = UDim2.new()
	end
	task.defer(function() self:_moveMarker(not instant and previous ~= nil) end)
end

function Window:Open()
	local hub = self.Hub
	if self.IsOpen or hub._destroyed then return end
	self.IsOpen = true
	hub:_closePopup()
	hub.Tooltip.Visible = false
	hub._windows = hub._windows or {}
	table.insert(hub._windows, self)
	self.Layer.Visible = true
	self.Layer.Active = true
	-- reopen on top of anything opened since
	hub._windowZ = (hub._windowZ or 70) + 1
	self.Layer.ZIndex = math.min(hub._windowZ, 79)
	self._grow.Scale = 0.96
	tween(self.Layer, SOFT, { BackgroundTransparency = 0.45 })
	tween(self.Body, SOFT, { GroupTransparency = 0 })
	tween(self._outline, SOFT, { Transparency = 0 })
	tween(self._grow, RISE, { Scale = 1 })
	task.defer(function() self:_moveMarker(false) end)
end

function Window:Close()
	local hub = self.Hub
	if not self.IsOpen then return end
	self.IsOpen = false
	hub:_closePopup()
	local i = hub._windows and table.find(hub._windows, self)
	if i then table.remove(hub._windows, i) end
	if #(hub._windows or {}) == 0 then hub._windowZ = 70 end
	self.Layer.Active = false
	tween(self.Layer, FOLD, { BackgroundTransparency = 1 })
	tween(self._outline, FOLD, { Transparency = 1 })
	tween(self._grow, FOLD, { Scale = 0.97 })
	tween(self.Body, FOLD, { GroupTransparency = 1 }).Completed:Connect(function()
		if not self.IsOpen then self.Layer.Visible = false end
	end)
end

function Window:Toggle()
	if self.IsOpen then self:Close() else self:Open() end
end

function Window:Destroy()
	local hub = self.Hub
	self:Close()
	local i = hub.Windows and table.find(hub.Windows, self)
	if i then table.remove(hub.Windows, i) end
	self.Layer:Destroy()
end

---------------------------------------------------------------- command palette
function Hub:SetCommandKey(key)
	if typeof(key) ~= "EnumItem" or key.EnumType ~= Enum.KeyCode or key == Enum.KeyCode.Unknown then return end
	self.CommandKey = key
	if self._commandKeyControl then self._commandKeyControl:Set(key, true) end
	self.SetupData = self.SetupData or {}
	self.SetupData.CommandKey = key.Name
	if hasFS then
		pcall(function()
			ensureFolder(RiftUI.Folder)
			ensureFolder(self:_dir())
			writefile(self:_dir() .. "/setup.json", HttpService:JSONEncode(self.SetupData))
		end)
	end
end

function Hub:CloseCommandPalette(instant)
	local palette = self._palette
	if not palette then return end
	self._palette = nil
	palette.Input:ReleaseFocus()
	for _, conn in palette.Connections do conn:Disconnect() end
	if instant or self._destroyed then
		palette.Layer:Destroy()
		return
	end
	-- Fold back toward the search field, faster than it opened.
	palette.Layer.Active = false
	tween(palette.Layer, FOLD, { BackgroundTransparency = 1 })
	tween(palette.Outline, FOLD, { Transparency = 1 })
	tween(palette.Scale, FOLD, { Scale = 0.97 })
	tween(palette.Card, FOLD, { GroupTransparency = 1 }).Completed:Connect(function()
		palette.Layer:Destroy()
	end)
end

local CONTROL_ICONS = {
	Toggle = "square-check", Slider = "sliders-horizontal", Dropdown = "list", Input = "text-cursor-input",
	Keybind = "keyboard", ColorPicker = "palette", Button = "mouse-pointer-click", Info = "info",
}

function Hub:_commandEntries()
	local entries = {}
	local function addControls(group, tab, sections, extra)
		for _, section in sections do
			for _, control in section.Controls do
				if not control._hidden and control.Type ~= "Label" and control.Type ~= "Paragraph" then
					local entry = { Name = control.Name, Group = group, Detail = section.Name, Icon = CONTROL_ICONS[control.Type] or "dot", Tab = tab, Control = control, Key = group .. "/" .. section.Name .. "/" .. control.Name }
					for k, v in extra or {} do entry[k] = v end
					table.insert(entries, entry)
				end
			end
		end
	end
	for _, tab in self.Tabs do
		if tab.Tile.Visible then
			table.insert(entries, { Name = tab.Name, Group = "Tabs", Detail = tab.Description, Icon = tab.Icon or "layout-grid", Tab = tab, IsTab = true, Key = "tab/" .. tab.Name })
			addControls(tab.Name, tab, tab.Sections)
		end
	end
	for _, win in self.Windows or {} do
		if win.Layer.Parent then
			table.insert(entries, { Name = win.Title, Group = "Windows", Detail = win.Description, Icon = win.Icon or "app-window", Window = win, Key = "window/" .. win.Title })
			for _, tab in win.Tabs do
				addControls(win.Title, tab, tab.Sections, { Window = win })
			end
		end
	end
	local function action(name, icon, run)
		table.insert(entries, { Name = name, Group = "Actions", Icon = icon, Run = run, Key = "action/" .. name })
	end
	action(self._visible and "Hide toolbar" or "Show toolbar", "panel-bottom", function() self:ToggleToolbar() end)
	if self._open then action("Close panel", "x", function() self:Close() end) end
	action("Run setup again", "rotate-ccw", function() self:OpenSetup() end)
	return entries
end

function Hub:_rememberJump(key: string)
	local recent = self._recentJumps or {}
	local i = table.find(recent, key)
	if i then table.remove(recent, i) end
	table.insert(recent, 1, key)
	while #recent > 4 do table.remove(recent) end
	self._recentJumps = recent
end

local PALETTE_HEAD, PALETTE_TOP, PALETTE_FOOT = 26, 54, 38

function Hub:OpenCommandPalette()
	if self._destroyed or self._listening then return end
	if self._palette then self:CloseCommandPalette() return end
	self:_closePopup()
	self.Tooltip.Visible = false
	local theme = self.Theme
	local touch = UserInputService.TouchEnabled
	-- rows are finger-sized on touch screens
	local PALETTE_ROW = touch and 48 or 40
	local layer = create("TextButton", {
		Name = "CommandPalette", Text = "", AutoButtonColor = false,
		BackgroundColor3 = themeColor(theme, "Scrim"), BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1), ZIndex = 81, Parent = self.Gui,
	})
	local holder = create("Frame", {
		Name = "CommandWindow", BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(520, 200),
		Active = true, ZIndex = 82, Parent = layer,
	})
	-- Scale from the top edge so the window grows down out of the search field.
	local grow = create("UIScale", { Scale = 0.96, Parent = holder })
	shadow(holder, 30, 82, 8)
	local win = create("CanvasGroup", {
		Name = "Card", BackgroundColor3 = themeColor(theme, "Panel"),
		Size = UDim2.fromScale(1, 1), GroupTransparency = 1, ZIndex = 82, Parent = holder,
	}, { corner(14) })
	local outlineStroke = stroke(themeColor(theme, "PanelStroke"))
	outlineStroke.Transparency = 1
	create("Frame", { Name = "Outline", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 86, Parent = holder }, {
		corner(14), outlineStroke,
	})
	iconLabel("search", 16, theme.SubText, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromOffset(18, PALETTE_TOP / 2), ZIndex = 83, Parent = win })
	local box = create("TextBox", {
		Name = "CommandInput", BackgroundTransparency = 1,
		Position = UDim2.fromOffset(44, 3), Size = UDim2.new(1, -110, 0, PALETTE_TOP - 6),
		Text = "", PlaceholderText = "Search tabs, settings and controls", ClearTextOnFocus = false,
		TextSize = 14, FontFace = inter(Enum.FontWeight.Medium),
		TextColor3 = themeColor(theme, "Text"), PlaceholderColor3 = themeColor(theme, "Muted"),
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 83, Parent = win,
	})
	-- Esc on keyboards, an X on touch screens; both close.
	local close = create("TextButton", {
		Name = "CloseCommands", BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0, PALETTE_TOP / 2), Size = UDim2.fromOffset(touch and 44 or 40, 44),
		ZIndex = 83, Parent = win,
	})
	local function keycap(parent, label, props)
		local cap = create("TextLabel", {
			BackgroundColor3 = themeColor(theme, "Field"), Text = label, FontFace = inter(Enum.FontWeight.Medium), TextSize = 10,
			TextColor3 = themeColor(theme, "SubText"), Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 85, Parent = parent,
		}, { corner(4), stroke(themeColor(theme, "FieldStroke")), padding(0, 5) })
		for k, v in props or {} do cap[k] = v end
		return cap
	end
	if touch then
		iconLabel("x", 16, theme.SubText, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Parent = close, ZIndex = 84 })
	else
		keycap(close, "Esc", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
	end
	create("Frame", { BackgroundColor3 = themeColor(theme, "Divider"), BorderSizePixel = 0, Position = UDim2.fromOffset(0, PALETTE_TOP), Size = UDim2.new(1, 0, 0, 1), ZIndex = 83, Parent = win })
	local results = create("ScrollingFrame", {
		Name = "CommandResults", BackgroundTransparency = 1, BorderSizePixel = 0,
		Position = UDim2.fromOffset(8, PALETTE_TOP + 5), Size = UDim2.new(1, -16, 1, -(PALETTE_TOP + 5 + PALETTE_FOOT)),
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3, ScrollBarImageColor3 = themeColor(theme, "Knob"),
		ScrollingDirection = Enum.ScrollingDirection.Y, ZIndex = 83, Parent = win,
	}, { list(Enum.FillDirection.Vertical, 0) })
	local foot = create("Frame", { Name = "CommandFooter", BackgroundColor3 = themeColor(theme, "Section"), BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, PALETTE_FOOT), ZIndex = 83, Parent = win })
	create("Frame", { BackgroundColor3 = themeColor(theme, "Divider"), BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 1), ZIndex = 84, Parent = foot })
	local status = text({ Name = "CommandStatus", Text = "", TextSize = 11, TextColor3 = themeColor(theme, "SubText"), Position = UDim2.fromOffset(16, 1), Size = UDim2.new(1, -32, 1, -1), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 84, Parent = foot })
	if not touch then
		local hints = create("Frame", { Name = "KeyHints", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 1), Size = UDim2.new(0, 0, 1, -1), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 84, Parent = foot }, {
			list(Enum.FillDirection.Horizontal, 5, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center),
		})
		local order = 0
		local function hint(keys, label)
			for _, k in keys do
				order += 1
				keycap(hints, k, { LayoutOrder = order })
			end
			order += 1
			text({ Parent = hints, Text = label, TextSize = 11, TextColor3 = themeColor(theme, "SubText"), Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = order, ZIndex = 85 })
			order += 1
			create("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(6, 1), LayoutOrder = order, Parent = hints })
		end
		hint({ "↑", "↓" }, "Move")
		hint({ "↵" }, "Open")
		hint({ "Esc" }, "Close")
	end

	local connections = {}
	local palette = { Layer = layer, Input = box, Card = win, Outline = outlineStroke, Scale = grow, Connections = connections, Selected = 1, Matches = {}, Rows = {} }
	self._palette = palette
	local function connect(signal, fn) table.insert(connections, signal:Connect(fn)) end
	layer.Destroying:Connect(function()
		for _, conn in connections do conn:Disconnect() end
		if self._palette == palette then self._palette = nil end
	end)
	local contentHeight = 0
	local sized = false
	local function fit(animate)
		local vp = viewport() / self._scale
		local top = topInset() / self._scale + 12
		local maxH = math.min(440, vp.Y - top - 16)
		local h = math.min(maxH, PALETTE_TOP + 5 + contentHeight + 6 + PALETTE_FOOT)
		holder.Position = UDim2.new(0.5, 0, 0, top)
		local size = UDim2.fromOffset(math.min(520, vp.X - 24), h)
		-- the card follows its results: fewer matches, shorter box
		if animate and sized then
			tween(holder, SETTLE, { Size = size })
		else
			holder.Size = size
		end
		sized = true
	end
	connect(layer:GetPropertyChangedSignal("AbsoluteSize"), function() fit(false) end)
	connect(self.UIScale:GetPropertyChangedSignal("Scale"), function() fit(false) end)
	local function select(index)
		palette.Selected = math.clamp(index, 1, math.max(1, #palette.Matches))
		for i, row in palette.Rows do
			local goal = i == palette.Selected and 0 or 1
			if row.BackgroundTransparency ~= goal then tween(row, FAST, { BackgroundTransparency = goal }) end
		end
		local row = palette.Rows[palette.Selected]
		if row then
			local y = (row.AbsolutePosition.Y - results.AbsolutePosition.Y) / self._scale + results.CanvasPosition.Y
			local height = results.AbsoluteSize.Y / self._scale
			-- keep a group header in view above the first row of its group
			local above = (palette.HeadAbove[palette.Selected] and PALETTE_HEAD or 0)
			if y - above < results.CanvasPosition.Y then results.CanvasPosition = Vector2.new(0, math.max(0, y - above))
			elseif y + PALETTE_ROW > results.CanvasPosition.Y + height then results.CanvasPosition = Vector2.new(0, y + PALETTE_ROW - height) end
		end
	end
	local function flash(control)
		local mark = stroke(themeColor(self.Theme, "Accent"), 1, 0)
		mark.Parent = control.Frame
		tween(mark, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1 })
		task.delay(1.3, function() mark:Destroy() end)
	end
	local function reveal(scroll, control)
		if control.Section.Pinned then return end
		local y = (control.Frame.AbsolutePosition.Y - scroll.AbsolutePosition.Y) / self._scale + scroll.CanvasPosition.Y
		scroll.CanvasPosition = Vector2.new(0, math.max(0, y - 12))
	end
	local function activate(entry)
		if self._palette ~= palette or not entry then return end
		self:_rememberJump(entry.Key)
		self:CloseCommandPalette()
		if entry.Run then entry.Run() return end
		local control = entry.Control
		local group = control and control.Section
		while group and group._isGroup do
			group:SetOpen(true, true)
			group = group.Parent
		end
		if group and group.SetCollapsed then group:SetCollapsed(false, true) end
		if entry.Window then
			local win = entry.Window
			win:Open()
			if entry.Tab then win:SelectTab(entry.Tab, true) end
			if not control then return end
			task.defer(function()
				task.wait()
				if self._destroyed or not control.Frame.Parent then return end
				reveal(entry.Tab.Scroll, control)
				flash(control)
			end)
			return
		end
		self:SetToolbarVisible(true, true)
		self:_applySearch("")
		self.Search.Text = ""
		self:Open(entry.Tab)
		if not control then return end
		task.defer(function()
			if self._destroyed or not control.Frame.Parent then return end
			self:_fitPanel(entry.Tab, false)
			task.wait()
			if self._destroyed or not control.Frame.Parent then return end
			reveal(entry.Tab.Scroll, control)
			flash(control)
		end)
	end
	local function addHeader(label, order)
		create("TextLabel", {
			Name = "CommandGroup", BackgroundTransparency = 1, Text = string.upper(label), TextSize = 10,
			FontFace = inter(Enum.FontWeight.SemiBold), TextColor3 = themeColor(theme, "Muted"),
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Bottom,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Size = UDim2.new(1, -4, 0, PALETTE_HEAD), LayoutOrder = order, ZIndex = 84, Parent = results,
		}, { padding(0, 10, 6, 10) })
		contentHeight += PALETTE_HEAD
	end
	local function addRow(entry, order)
		table.insert(palette.Matches, entry)
		local row = create("TextButton", { Name = "CommandResult", Text = "", AutoButtonColor = false,
			BackgroundColor3 = themeColor(theme, "TileActive"), BackgroundTransparency = 1,
			Size = UDim2.new(1, -4, 0, PALETTE_ROW), LayoutOrder = order, ZIndex = 84, Parent = results,
		}, { corner(8) })
		local icon = iconLabel(entry.Icon, 15, theme.SubText, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), ZIndex = 85, Parent = row })
		local left = icon and 38 or 12
		text({ Text = entry.Name, FontFace = inter(Enum.FontWeight.Medium), TextSize = 13,
			TextColor3 = themeColor(theme, "Text"), Position = UDim2.fromOffset(left, 0), Size = UDim2.new(0.62, -left, 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 85, Parent = row })
		if entry.Detail and entry.Detail ~= "" then
			text({ Text = entry.Detail, TextSize = 11, TextColor3 = themeColor(theme, "SubText"), TextXAlignment = Enum.TextXAlignment.Right,
				AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 0), Size = UDim2.new(0.38, -12, 1, 0),
				TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 85, Parent = row })
		end
		local index = #palette.Matches
		row.MouseEnter:Connect(function() if not touch then select(index) end end)
		row.MouseButton1Click:Connect(function() activate(entry) end)
		table.insert(palette.Rows, row)
		contentHeight += PALETTE_ROW
	end
	local function refresh()
		for _, child in results:GetChildren() do
			if child:IsA("GuiObject") then child:Destroy() end
		end
		palette.Rows, palette.Matches, palette.HeadAbove = {}, {}, {}
		contentHeight = 0
		local query = string.lower(string.match(box.Text, "^%s*(.-)%s*$"))
		local entries = self:_commandEntries()
		local groups, order = {}, {}
		local function put(groupName, entry)
			if not groups[groupName] then
				groups[groupName] = {}
				table.insert(order, groupName)
			end
			table.insert(groups[groupName], entry)
		end
		local total = 0
		if query == "" then
			-- nothing typed: recent jumps, then the tabs and actions; controls wait for a query
			local byKey = {}
			for _, e in entries do byKey[e.Key] = e end
			for _, key in self._recentJumps or {} do
				if byKey[key] then put("Recent", byKey[key]) end
			end
			for _, e in entries do
				if (e.IsTab or e.Group == "Windows" or e.Group == "Actions") and not table.find(self._recentJumps or {}, e.Key) then
					put(e.IsTab and "Jump to" or e.Group, e)
				end
			end
		else
			local matches = {}
			for i, entry in entries do
				local name = string.lower(entry.Name)
				-- initials let "fov" find Field of view and "tc" find Team check
				local initials = string.gsub(name, "(%w)%w*%W*", "%1")
				local haystack = name .. " " .. string.lower(self:T(entry.Name)) .. " " .. string.lower(entry.Group) .. " " .. string.lower(entry.Detail or "")
				local matched = initials == query
				if not matched then
					matched = true
					for token in string.gmatch(query, "%S+") do
						if not string.find(haystack, token, 1, true) then matched = false break end
					end
				end
				if matched then
					entry.Score = name == query and 0 or ((string.sub(name, 1, #query) == query or initials == query) and 1 or (string.find(name, query, 1, true) and 2 or 3))
					entry.Order = i
					table.insert(matches, entry)
				end
			end
			-- the best match decides which group is listed first; rows keep their order inside a group
			table.sort(matches, function(a, b) return a.Score < b.Score or (a.Score == b.Score and a.Order < b.Order) end)
			total = #matches
			for i = 1, math.min(40, #matches) do
				put(matches[i].Group, matches[i])
			end
			for _, name in order do
				table.sort(groups[name], function(a, b) return a.Order < b.Order end)
			end
		end
		local n = 0
		for _, groupName in order do
			n += 1
			addHeader(groupName, n)
			palette.HeadAbove[#palette.Matches + 1] = true
			for _, entry in groups[groupName] do
				n += 1
				addRow(entry, n)
			end
		end
		if #palette.Matches == 0 then
			n += 1
			text({ Parent = results, Name = "CommandEmpty", Text = "Nothing matches “" .. box.Text .. "”.\nTry a tab, section or control name.", TextSize = 12, LineHeight = 1.25,
				TextColor3 = themeColor(theme, "SubText"), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.new(1, -4, 0, 64), LayoutOrder = n, ZIndex = 84 })
			contentHeight += 64
		end
		results.CanvasPosition = Vector2.zero
		if query == "" then
			status.Text = touch and "Tap a result to jump to it" or "Type to search every control"
		elseif total == 0 then
			status.Text = "No results"
		else
			status.Text = (total > 40 and "First 40 of " .. total or tostring(total)) .. (total == 1 and " result" or " results")
		end
		fit(true)
		select(1)
	end
	connect(box:GetPropertyChangedSignal("Text"), refresh)
	connect(box.FocusLost, function(enter) if enter then activate(palette.Matches[palette.Selected]) end end)
	connect(close.MouseButton1Click, function() self:CloseCommandPalette() end)
	connect(layer.MouseButton1Click, function() self:CloseCommandPalette() end)
	connect(UserInputService.InputBegan, function(input)
		if self._palette ~= palette or input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == self.CommandKey then self:CloseCommandPalette()
		elseif input.KeyCode == Enum.KeyCode.Down then select(palette.Selected + 1)
		elseif input.KeyCode == Enum.KeyCode.Up then select(palette.Selected - 1)
		elseif input.KeyCode == Enum.KeyCode.Return then activate(palette.Matches[palette.Selected]) end
	end)
	refresh()
	box:CaptureFocus()
	tween(layer, SOFT, { BackgroundTransparency = 0.5 })
	tween(win, SOFT, { GroupTransparency = 0 })
	tween(outlineStroke, SOFT, { Transparency = 0 })
	tween(grow, RISE, { Scale = 1 })
end

function Hub:OpenSetup()
	if self._setupOpen then
		return
	end
	self:CloseCommandPalette()
	self._setupOpen = true
	self._listening = true
	self:Close()
	local theme = self.Theme
	local saved = self.SetupData or {}
	local choice = { ToggleKey = self.ToggleKey, Theme = self.ThemeName }
	local devOptions = self:_setupOptions()

	local layer = create("Frame", {
		Name = "Setup",
		BackgroundColor3 = themeColor(theme, "Scrim"),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Active = true,
		ZIndex = 70,
		Parent = self.Gui,
	})
	local holder = create("Frame", {
		Name = "Window",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 16),
		Size = UDim2.fromOffset(500, 440),
		ZIndex = 71,
		Parent = layer,
	})
	shadow(holder, 34, 71, 10)
	task.defer(function() fitModal(self, layer, holder, 500, 440) end)
	local win = create("CanvasGroup", {
		Name = "Body",
		BackgroundColor3 = themeColor(theme, "Panel"),
		Size = UDim2.fromScale(1, 1),
		GroupTransparency = 1,
		ZIndex = 72,
		Parent = holder,
	}, { corner(14) })
	create("Frame", { Name = "Outline", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 80, Parent = holder }, { corner(14), stroke(themeColor(theme, "PanelStroke")) })
	sheen(win, 16, theme, 79)

	-- header: progress segments, step label, title, subtitle
	local steps = { "key", "theme" }
	if #devOptions > 0 then
		table.insert(steps, "options")
	end
	table.insert(steps, "compat")
	local progress = create("Frame", { Name = "Progress", BackgroundTransparency = 1, Position = UDim2.fromOffset(24, 22), Size = UDim2.new(1, -48, 0, 2), ZIndex = 73, Parent = win }, {
		list(Enum.FillDirection.Horizontal, 4),
	})
	local segments = {}
	for i = 1, #steps do
		local seg = create("Frame", {
			Name = "Segment",
			BackgroundColor3 = themeColor(theme, "Track"),
			BorderSizePixel = 0,
			Size = UDim2.new(1 / #steps, -4 * (#steps - 1) / #steps, 1, 0),
			LayoutOrder = i,
			ZIndex = 73,
			Parent = progress,
		}, { corner(1) })
		local fill = create("Frame", { Name = "Fill", BackgroundColor3 = themeColor(theme, "Accent"), BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), ZIndex = 74, Parent = seg }, { corner(1) })
		segments[i] = fill
	end
	local stepLabel = text({ Parent = win, Text = "", TextSize = 11, FontFace = inter(Enum.FontWeight.SemiBold), TextColor3 = themeColor(theme, "Muted"), Position = UDim2.fromOffset(24, 38), Size = UDim2.new(1, -48, 0, 14), ZIndex = 73 })
	local title = text({ Parent = win, Text = "", TextSize = 19, FontFace = inter(Enum.FontWeight.SemiBold), Position = UDim2.fromOffset(24, 58), Size = UDim2.new(1, -48, 0, 24), ZIndex = 73 })
	local subtitle = text({
		Parent = win,
		Text = "",
		TextSize = 13,
		TextColor3 = themeColor(theme, "SubText"),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(24, 88),
		Size = UDim2.new(1, -48, 0, 36),
		ZIndex = 73,
	})
	local stage = create("CanvasGroup", {
		Name = "Stage",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(24, 134),
		Size = UDim2.new(1, -48, 1, -134 - 64),
		ZIndex = 73,
		Parent = win,
	})
	create("Frame", { Name = "Rule", BackgroundColor3 = themeColor(theme, "Divider"), BorderSizePixel = 0, Position = UDim2.new(0, 0, 1, -64), Size = UDim2.new(1, 0, 0, 1), ZIndex = 73, Parent = win })
	local footer = create("Frame", { Name = "Footer", BackgroundTransparency = 1, Position = UDim2.new(0, 24, 1, -64), Size = UDim2.new(1, -48, 0, 64), ZIndex = 73, Parent = win })
	local skip = create("TextButton", {
		Name = "Skip",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0, 0.5),
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "Skip setup",
		FontFace = inter(Enum.FontWeight.Medium),
		TextSize = 13,
		TextColor3 = themeColor(theme, "Muted"),
		AutoButtonColor = false,
		ZIndex = 74,
		Parent = footer,
	})
	local buttons = create("Frame", { Name = "Buttons", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromOffset(260, 32), ZIndex = 74, Parent = footer }, {
		list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center),
	})
	local function footerButton(label: string, primary: boolean, order: number)
		local b = create("TextButton", {
			Name = label,
			BackgroundColor3 = primary and themeColor(theme, "Accent") or themeColor(theme, "Tile"),
			Size = UDim2.fromOffset(0, 32),
			AutomaticSize = Enum.AutomaticSize.X,
			Text = label,
			FontFace = inter(Enum.FontWeight.Medium),
			TextSize = 13,
			TextColor3 = primary and themeColor(theme, "AccentText") or themeColor(theme, "Text"),
			AutoButtonColor = false,
			LayoutOrder = order,
			ZIndex = 75,
			Parent = buttons,
		}, { corner(8), padding(0, 16) })
		if not primary then
			stroke(themeColor(theme, "TileStroke")).Parent = b
		end
		return b
	end
	local back = footerButton("Back", false, 1)
	local nextButton = footerButton("Continue", true, 2)
	local conns = {}
	local function on(signal, fn)
		table.insert(conns, signal:Connect(fn))
	end

	-- step bodies
	local step = 0
	local busy = false
	local compatDone = false
	local optionControls = {}
	local pages = {}

	local function page(scrollable)
		if scrollable then
			return create("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 3, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 73, Parent = stage })
		end
		return create("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 73, Parent = stage })
	end

	-- 1) toolbar key
	do
		local p = page()
		pages.key = { Frame = p, Title = "Toolbar key", Subtitle = "Shows and hides " .. self.Name .. "'s toolbar. You can change it later in Settings." }
		local keyChip = create("TextButton", {
			Name = "Key",
			BackgroundColor3 = themeColor(theme, "Field"),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 34),
			Size = UDim2.fromOffset(200, 64),
			Text = keyName(choice.ToggleKey),
			FontFace = MONO,
			TextSize = 22,
			TextColor3 = themeColor(theme, "Text"),
			AutoButtonColor = false,
			ZIndex = 74,
			Parent = p,
		}, { corner(12) })
		local keyStroke = stroke(themeColor(theme, "FieldStroke"))
		keyStroke.Parent = keyChip
		local hint = text({
			Parent = p,
			Text = "Click, then press a key",
			TextSize = 12,
			TextColor3 = themeColor(theme, "Muted"),
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 110),
			Size = UDim2.new(1, 0, 0, 16),
			ZIndex = 74,
		})
		local listening = false
		on(keyChip.MouseButton1Click, function()
			listening = true
			keyChip.Text = "Press a key…"
			keyChip.TextSize = 16
			tween(keyStroke, FAST, { Color = themeColor(theme, "Accent") })
			hint.Text = "Esc cancels"
		end)
		on(UserInputService.InputBegan, function(input)
			if not listening or input.UserInputType ~= Enum.UserInputType.Keyboard then
				return
			end
			listening = false
			if input.KeyCode ~= Enum.KeyCode.Escape then
				choice.ToggleKey = input.KeyCode
			end
			keyChip.Text = keyName(choice.ToggleKey)
			keyChip.TextSize = 22
			tween(keyStroke, FAST, { Color = themeColor(theme, "FieldStroke") })
			hint.Text = "Click, then press a key"
		end)
	end

	-- 2) theme cards, each a small picture of the toolbar in that theme
	do
		local p = page(true)
		pages.theme = { Frame = p, Title = "Theme", Subtitle = "Applies immediately. More options in Settings › Theme studio." }
		-- the stage clips (it fades as one), so leave room for the selected card's outline
		padding(3).Parent = p
		create("UIGridLayout", { CellSize = UDim2.new(0.5, -5, 0, 100), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = p })
		local cards = {}
		local function refreshCards()
			for name, c in cards do
				local sel = name == choice.Theme
				tween(c.Stroke, FAST, { Color = sel and c.Colors.Accent or themeColor(theme, "TileStroke"), Thickness = sel and 2 or 1 })
				c.Check.Visible = sel
			end
		end
		for i, preset in THEMES do
			local colors = buildTheme(preset.Name, nil)
			local card = create("TextButton", {
				Name = "Theme_" .. preset.Name,
				BackgroundColor3 = colors.Panel,
				Text = "",
				AutoButtonColor = false,
				LayoutOrder = i,
				ZIndex = 74,
				Parent = p,
			}, { corner(10) })
			card:SetAttribute("ThemeSwatch", true)
			local cardStroke = stroke(themeColor(theme, "TileStroke"))
			cardStroke.Parent = card
			-- mini toolbar: three tiles, the middle one active with the accent underline
			local mini = create("Frame", {
				Name = "Toolbar",
				BackgroundColor3 = colors.Panel,
				Position = UDim2.fromOffset(12, 12),
				Size = UDim2.fromOffset(86, 30),
				ZIndex = 75,
				Parent = card,
			}, { corner(7), stroke(colors.PanelStroke), padding(4), list(Enum.FillDirection.Horizontal, 3, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center) })
			for t = 1, 3 do
				create("Frame", {
					BackgroundColor3 = t == 2 and colors.TileActive or colors.Tile,
					Size = UDim2.fromOffset(24, 22),
					LayoutOrder = t,
					ZIndex = 76,
					Parent = mini,
				}, { corner(5) })
			end
			create("Frame", { Name = "Accent", BackgroundColor3 = colors.Accent, BorderSizePixel = 0, Position = UDim2.fromOffset(110, 20), Size = UDim2.fromOffset(28, 4), ZIndex = 75, Parent = card }, { corner(2) })
			create("Frame", { Name = "Line", BackgroundColor3 = colors.Divider, BorderSizePixel = 0, Position = UDim2.fromOffset(110, 30), Size = UDim2.new(1, -122, 0, 1), ZIndex = 75, Parent = card })
			text({ Parent = card, Text = preset.Name, FontFace = inter(Enum.FontWeight.SemiBold), TextSize = 14, TextColor3 = colors.Text, Position = UDim2.fromOffset(12, 56), Size = UDim2.new(1, -40, 0, 18), ZIndex = 75 })
			text({ Parent = card, Text = preset.Description, TextSize = 11, TextColor3 = colors.SubText, Position = UDim2.fromOffset(12, 76), Size = UDim2.new(1, -24, 0, 14), ZIndex = 75, TextTruncate = Enum.TextTruncate.AtEnd })
			local check = create("Frame", { Name = "Selected", BackgroundColor3 = colors.Accent, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.fromOffset(16, 16), Visible = false, ZIndex = 76, Parent = card }, { corner(8) })
			iconLabel("check", 11, colors.AccentText, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 77, Parent = check })
			cards[preset.Name] = { Stroke = cardStroke, Check = check, Colors = colors }
			on(card.MouseButton1Click, function()
				choice.Theme = preset.Name
				self:_transitionTheme(preset.Name)
				refreshCards()
			end)
		end
		refreshCards()
	end

	-- 3) the hub's own setup options, built with the regular controls
	if #devOptions > 0 then
		local p = page()
		local setupTitle = type(self.Options.Setup) == "table" and self.Options.Setup.Title
		pages.options = { Frame = p, Title = setupTitle or "Hub options", Subtitle = (type(self.Options.Setup) == "table" and self.Options.Setup.Description) or (self.Name .. " asks for a few choices before it starts.") }
		local scroll = create("ScrollingFrame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = themeColor(theme, "Knob"),
			ZIndex = 74,
			Parent = p,
		})
		local col = create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 74, Parent = scroll }, {
			list(Enum.FillDirection.Vertical, 6),
		})
		local fakeTab = setmetatable({
			Hub = self,
			Name = "Setup",
			Sections = {},
			Columns = { col, col, Frame = col },
			_internal = true,
			_recount = function() end,
		}, Tab)
		local section = fakeTab:Section({ Name = self.Name, Pinnable = false })
		for _, opt in devOptions do
			local args = table.clone(opt)
			args.Type = nil
			local current = opt.Flag and RiftUI.Flags[opt.Flag]
			if current and current.Value ~= nil then
				if opt.Type == "Dropdown" and opt.Multi then
					local picked = {}
					for k, v in current.Value do
						if v then
							table.insert(picked, k)
						end
					end
					args.Default = picked
				else
					args.Default = current.Value
				end
			end
			local method = section[opt.Type]
			if method then
				local control = method(section, args)
				control._setup = true
				table.insert(optionControls, control)
			end
		end
	end

	-- 4) compatibility check
	local compat = page()
	pages.compat = { Frame = compat, Title = "Compatibility check", Subtitle = "Calling each executor function RiftUI uses." }
	local compatList = create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -78),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = themeColor(theme, "Knob"),
		ZIndex = 74,
		Parent = compat,
	}, { list(Enum.FillDirection.Vertical, 0) })
	local summary = create("Frame", {
		Name = "Summary",
		BackgroundColor3 = themeColor(theme, "Field"),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 1, 1, -14),
		Size = UDim2.new(1, -2, 0, 52),
		Visible = false,
		ZIndex = 74,
		Parent = compat,
	}, { corner(8), padding(0, 12) })
	local summaryStroke = stroke(themeColor(theme, "FieldStroke"))
	summaryStroke.Parent = summary
	local summaryText = text({ Parent = summary, Text = "", TextSize = 12, TextWrapped = true, Size = UDim2.new(1, -28, 1, 0), Position = UDim2.fromOffset(24, 0), ZIndex = 75 })
	local summaryIcon = create("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(16, 16), ZIndex = 75, Parent = summary })

	local STATUS = {
		pass = { Icon = "check", Color = themeColor(theme, "Success") },
		warn = { Icon = "triangle-alert", Color = themeColor(theme, "Warning") },
		fail = { Icon = "circle-x", Color = themeColor(theme, "Danger") },
	}
	local function runCompat()
		compatDone = false
		nextButton.Text = "Checking…"
		compatList:ClearAllChildren()
		list(Enum.FillDirection.Vertical, 0).Parent = compatList
		summary.Visible = false
		local checks = self:_compatChecks()
		local rows = {}
		for i, check in checks do
			local row = create("Frame", { Name = "Check", BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 30), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = i, ZIndex = 74, Parent = compatList })
			local status = create("Frame", { Name = "Status", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 8), Size = UDim2.fromOffset(14, 14), ZIndex = 75, Parent = row })
			local dot = create("Frame", { BackgroundColor3 = themeColor(theme, "Muted"), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(5, 5), ZIndex = 76, Parent = status }, { corner(3) })
			local name = text({ Parent = row, Text = check.Name, TextSize = 13, TextColor3 = themeColor(theme, "SubText"), Position = UDim2.fromOffset(24, 7), Size = UDim2.new(1, -150, 0, 16), ZIndex = 75 })
			text({ Parent = row, Text = check.Detail, FontFace = MONO, TextSize = 11, TextColor3 = themeColor(theme, "Muted"), TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 7), Size = UDim2.fromOffset(140, 16), ZIndex = 75 })
			rows[i] = { Row = row, Status = status, Dot = dot, Name = name }
		end
		local results = {}
		local counts = { pass = 0, warn = 0, fail = 0 }
		for i, check in checks do
			local r = rows[i]
			-- the dot grows into a spinner-ish pulse while the check runs
			tween(r.Dot, FAST, { Size = UDim2.fromOffset(9, 9), BackgroundColor3 = themeColor(theme, "Text") })
			task.wait(0.12)
			local ok, err = pcall(check.Run)
			local level = ok and "pass" or check.Severity
			counts[level] += 1
			table.insert(results, { Name = check.Name, Detail = check.Detail, Ok = ok, Severity = check.Severity, Error = not ok and tostring(err) or nil, Impact = check.Impact })
			r.Dot:Destroy()
			local icon = iconLabel(STATUS[level].Icon, 14, STATUS[level].Color, { ZIndex = 76, Parent = r.Status })
			if not icon then
				create("Frame", { BackgroundColor3 = STATUS[level].Color, Size = UDim2.fromOffset(10, 10), Position = UDim2.fromOffset(2, 2), ZIndex = 76, Parent = r.Status }, { corner(5) })
			end
			setThemed(r.Name, "TextColor3", themeColor(theme, "Text"))
			if not ok then
				text({
					Parent = r.Row,
					Text = check.Impact .. "  (" .. string.gsub(tostring(err), "^.-:%d+: ", "") .. ")",
					TextSize = 11,
					TextColor3 = STATUS[level].Color,
					TextWrapped = true,
					Position = UDim2.fromOffset(24, 26),
					Size = UDim2.new(1, -24, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					ZIndex = 75,
				})
				create("UIPadding", { PaddingBottom = UDim.new(0, 8), Parent = r.Row })
			end
			if not layer.Parent then
				return
			end
		end
		RiftUI.Compatibility = results
		choice.Compat = results
		local level = counts.fail > 0 and "fail" or counts.warn > 0 and "warn" or "pass"
		summaryIcon:ClearAllChildren()
		iconLabel(STATUS[level].Icon, 16, STATUS[level].Color, { Parent = summaryIcon, ZIndex = 76 })
		setThemed(summaryStroke, "Color", level == "pass" and themeColor(theme, "FieldStroke") or STATUS[level].Color)
		setThemed(summaryText, "TextColor3", level == "pass" and themeColor(theme, "Text") or STATUS[level].Color)
		if level == "pass" then
			summaryText.Text = "All " .. #checks .. " checks passed. Everything RiftUI needs is available."
		else
			summaryText.Text = string.format("%d failed, %d with warnings. You can still finish; the parts listed above won't work in this executor.", counts.fail, counts.warn)
			if counts.fail > 0 then
				recordError(counts.fail .. " compatibility check(s) failed", nil, "setup")
			end
		end
		summary.Visible = true
		compatDone = true
		nextButton.Text = "Finish"
	end

	local function finish(skipped: boolean)
		self._setupOpen = false
		task.defer(function()
			self._listening = false
		end)
		for _, c in conns do
			c:Disconnect()
		end
		local data = { Version = RiftUI.Version, Completed = true, Skipped = skipped or nil, Theme = choice.Theme, ToggleKey = choice.ToggleKey.Name, CommandKey = self.CommandKey.Name, Options = {}, Time = os.time(), Studio = (self.SetupData or {}).Studio }
		for _, control in optionControls do
			if control.Flag then
				data.Options[control.Flag] = encodeValue(control)
			end
		end
		if choice.Compat then
			data.Compat = {}
			for _, r in choice.Compat do
				data.Compat[r.Name] = r.Ok and "pass" or r.Severity
			end
		end
		self.SetupData = data
		self.ToggleKey = choice.ToggleKey
		if self._toggleKeyControl then
			self._toggleKeyControl:Set(choice.ToggleKey, true)
		end
		if hasFS then
			pcall(function()
				ensureFolder(RiftUI.Folder)
				ensureFolder(self:_dir())
				writefile(self:_dir() .. "/setup.json", HttpService:JSONEncode(data))
			end)
		end
		tween(layer, FOLD, { BackgroundTransparency = 1 })
		-- Keep the responsive modal position during its fade.
		local tw = tween(win, FOLD, { GroupTransparency = 1 })
		tw.Completed:Wait()
		layer:Destroy()
		self.ThemeName = choice.Theme
		self.Options.ThemeName = choice.Theme
		if self._themeControl then self._themeControl:Set(choice.Theme, true) end
		local target = RiftUI.Hubs[#RiftUI.Hubs] or self
		if not skipped then
			target:Notify({ Title = "Setup complete", Content = UserInputService.TouchEnabled and "Tap Hide toolbar or Show toolbar at the bottom of the screen." or ("Press " .. keyName(choice.ToggleKey) .. " to show or hide the toolbar."), Icon = "circle-check", Duration = 4 })
		end
		local failed = 0
		for _, r in choice.Compat or {} do
			if not r.Ok and r.Severity == "fail" then
				failed += 1
			end
		end
		if failed > 0 then
			target:Notify({ Title = "Some features won't work", Content = failed .. " compatibility check(s) failed. Settings › Run setup again shows which.", Tone = theme.Warning, Icon = "triangle-alert", Duration = 7, Force = true })
		end
	end

	local function show(index: number, dir: number)
		step = index
		local key = steps[index]
		local info = pages[key]
		for i, fill in segments do
			tween(fill, SETTLE, { Size = UDim2.fromScale(i <= index and 1 or 0, 1) })
		end
		stepLabel.Text = string.upper(string.format("Setup · %d of %d", index, #steps))
		title.Text = info.Title
		subtitle.Text = info.Subtitle
		for k, pg in pages do
			pg.Frame.Visible = k == key
		end
		back.Visible = index > 1
		skip.Visible = key ~= "compat"
		nextButton.Text = key == "compat" and (compatDone and "Finish" or "Checking…") or "Continue"
		stage.GroupTransparency = 1
		stage.Position = UDim2.fromOffset(24 + 14 * dir, 134)
		tween(stage, SETTLE, { Position = UDim2.fromOffset(24, 134), GroupTransparency = 0 })
		if key == "compat" and not compatDone then
			task.spawn(runCompat)
		end
	end

	on(nextButton.MouseButton1Click, function()
		if busy then
			return
		end
		if steps[step] == "compat" then
			if compatDone then
				busy = true
				finish(false)
			end
			return
		end
		show(step + 1, 1)
	end)
	on(back.MouseButton1Click, function()
		if step > 1 then
			show(step - 1, -1)
		end
	end)
	on(skip.MouseButton1Click, function()
		if not busy then
			busy = true
			finish(true)
		end
	end)
	on(skip.MouseEnter, function()
		setThemed(skip, "TextColor3", themeColor(theme, "Text"))
	end)
	on(skip.MouseLeave, function()
		setThemed(skip, "TextColor3", themeColor(theme, "Muted"))
	end)
	on(nextButton.MouseEnter, function()
		tween(nextButton, FAST, { BackgroundColor3 = rgb(255, 255, 255):Lerp(theme.Accent, 0.6) })
	end)
	on(nextButton.MouseLeave, function()
		tween(nextButton, FAST, { BackgroundColor3 = themeColor(theme, "Accent") })
	end)

	tween(layer, SOFT, { BackgroundTransparency = 0.5 })
	-- Keep the modal anchored to its available viewport.
	tween(win, SOFT, { GroupTransparency = 0 })
	show(1, 0)
	local _ = saved
end

---------------------------------------------------------------- theme studio & background images
--[[
	Hub:SetBackground({ Url = "...", Base64 = "...", File = "path/in/workspace.png", Opacity = 0.6, Dim = 0.55, Fit = "Crop", Dock = false })
	Hub:SetBackground(nil) removes it.

	Images are saved into RiftUI/<Id>/ with writefile and shown through getcustomasset. Url
	downloads with HttpGet; a URL that returns base64 text (or a data: URI) is decoded too.
]]

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local accentTextFor
local function decodeBase64(data: string): string
	data = string.gsub(data, "^data:[^,]*,", "")
	data = string.gsub(data, "[^%w%+/=]", "")
	local decoder = (typeof(crypt) == "table" and crypt.base64decode) or (typeof(base64_decode) == "function" and base64_decode)
	if decoder then
		local ok, out = pcall(decoder, data)
		if ok and type(out) == "string" then
			return out
		end
	end
	local lookup = {}
	for i = 1, 64 do
		lookup[string.byte(B64, i)] = i - 1
	end
	local n = #data
	local out = buffer.create(n // 4 * 3)
	local o = 0
	for i = 1, n - 3, 4 do
		local a, b, c, d = string.byte(data, i, i + 3)
		local va, vb, vc, vd = lookup[a] or 0, lookup[b] or 0, lookup[c], lookup[d]
		local v = va * 262144 + vb * 4096 + (vc or 0) * 64 + (vd or 0)
		buffer.writeu8(out, o, bit32.extract(v, 16, 8))
		o += 1
		if vc then
			buffer.writeu8(out, o, bit32.extract(v, 8, 8))
			o += 1
		end
		if vd then
			buffer.writeu8(out, o, bit32.extract(v, 0, 8))
			o += 1
		end
	end
	return buffer.readstring(out, 0, o)
end

-- Returns the file extension for image bytes, or nil if they aren't an image.
local function imageKind(bytes: string): string?
	if string.sub(bytes, 1, 8) == "\137PNG\r\n\26\n" then
		return "png"
	elseif string.sub(bytes, 1, 3) == "\255\216\255" then
		return "jpg"
	elseif string.sub(bytes, 1, 4) == "RIFF" and string.sub(bytes, 9, 12) == "WEBP" then
		return "webp"
	elseif string.sub(bytes, 1, 4) == "GIF8" then
		return "gif"
	end
	return nil
end

-- Width and height straight from the file header (PNG, GIF, JPEG, WebP), or nil.
local function imageSize(bytes: string): (number?, number?)
	local function be(i, n)
		local v = 0
		for k = 0, n - 1 do
			v = v * 256 + string.byte(bytes, i + k)
		end
		return v
	end
	local function le(i, n)
		local v = 0
		for k = n - 1, 0, -1 do
			v = v * 256 + string.byte(bytes, i + k)
		end
		return v
	end
	local kind = imageKind(bytes)
	if kind == "png" and #bytes >= 24 then
		return be(17, 4), be(21, 4)
	elseif kind == "gif" and #bytes >= 10 then
		return le(7, 2), le(9, 2)
	elseif kind == "jpg" then
		local i = 3
		while i < #bytes - 9 do
			if string.byte(bytes, i) ~= 0xFF then
				i += 1
				continue
			end
			local marker = string.byte(bytes, i + 1)
			-- SOF0..SOF15 except DHT (C4), JPG (C8) and DAC (CC) carry the frame size
			if marker >= 0xC0 and marker <= 0xCF and marker ~= 0xC4 and marker ~= 0xC8 and marker ~= 0xCC then
				return be(i + 7, 2), be(i + 5, 2)
			end
			i += 2 + be(i + 2, 2)
		end
	elseif kind == "webp" and #bytes >= 30 then
		local chunk = string.sub(bytes, 13, 16)
		if chunk == "VP8X" then
			return le(25, 3) + 1, le(28, 3) + 1
		elseif chunk == "VP8 " then
			return bit32.band(le(27, 2), 0x3FFF), bit32.band(le(29, 2), 0x3FFF)
		elseif chunk == "VP8L" then
			local b = le(22, 4)
			return bit32.band(b, 0x3FFF) + 1, bit32.band(bit32.rshift(b, 14), 0x3FFF) + 1
		end
	end
	return nil, nil
end

-- Resolve a background source to a workspace file path and the image's aspect ratio.
-- Errors carry a readable reason.
function Hub:_storeBackground(source): (string, number)
	if not hasFS then
		error("this executor can't write files, so it can't keep a background", 0)
	end
	if source.File and source.File ~= "" then
		if not isfile(source.File) then
			error("there's no file at " .. source.File, 0)
		end
		local w, h = imageSize(readfile(source.File))
		return source.File, (w and h and h > 0) and w / h or 1
	end
	local bytes
	if source.Base64 and source.Base64 ~= "" then
		bytes = decodeBase64(source.Base64)
	elseif source.Url and source.Url ~= "" then
		local ok, body = pcall(function()
			return game:HttpGet(source.Url)
		end)
		if not ok then
			error("download failed: " .. tostring(body), 0)
		end
		bytes = body
		if #bytes == 0 then
			error("the server returned an empty response; the image file may be empty or unavailable", 0)
		end
		if string.match(string.lower(string.sub(bytes, 1, 200)), "^%s*<") then
			error("the URL returned an HTML page instead of image bytes; use a direct image URL", 0)
		end
		if not imageKind(bytes) and string.match(string.sub(bytes, 1, 200), "^%s*[%w%+/=:;,%-]+") then
			bytes = decodeBase64(bytes)
		end
	else
		error("give a URL, base64 data or a file path", 0)
	end
	local kind = imageKind(bytes)
	if not kind then
		error("that isn't a PNG, JPEG, WebP or GIF image", 0)
	end
	ensureFolder(RiftUI.Folder)
	ensureFolder(self:_dir())
	local path = self:_dir() .. "/background." .. kind
	writefile(path, bytes)
	local w, h = imageSize(bytes)
	return path, (w and h and h > 0) and w / h or 1
end

local FITS = { Fill = Enum.ScaleType.Crop, Crop = Enum.ScaleType.Crop, Fit = Enum.ScaleType.Fit, Stretch = Enum.ScaleType.Stretch }
local ANCHORS = {
	TopLeft = Vector2.new(0, 0),
	Top = Vector2.new(0.5, 0),
	TopRight = Vector2.new(1, 0),
	Left = Vector2.new(0, 0.5),
	Center = Vector2.new(0.5, 0.5),
	Right = Vector2.new(1, 0.5),
	BottomLeft = Vector2.new(0, 1),
	Bottom = Vector2.new(0.5, 1),
	BottomRight = Vector2.new(1, 1),
}
local ANCHOR_NAMES = { "Top left", "Top", "Top right", "Left", "Center", "Right", "Bottom left", "Bottom", "Bottom right" }
local function anchorKey(name: string?): string
	local key = string.gsub(name or "Center", "%s", "")
	for k in ANCHORS do
		if string.lower(k) == string.lower(key) then
			return k
		end
	end
	return "Center"
end
local function anchorLabel(name: string?): string
	local key = anchorKey(name)
	for _, label in ANCHOR_NAMES do
		if string.gsub(label, "%s", "") == key then
			return label
		end
	end
	return "Center"
end

-- Placement presets for the studio and SetBackground({ Preset = ... })
local PLACEMENTS = {
	Full = { Fit = "Fill", Anchor = "Center", Scale = 1, OffsetX = 0, OffsetY = 0, Rotation = 0 },
	Corner = { Fit = "Free", Anchor = "BottomRight", Scale = 0.75, OffsetX = 0, OffsetY = 0, Rotation = 0 },
	["Body pillow"] = { Fit = "Free", Anchor = "Right", Scale = 1, OffsetX = 0, OffsetY = 0, Rotation = 0 },
	["Body pillow (lying down)"] = { Fit = "Free", Anchor = "Bottom", Scale = 1, OffsetX = 0, OffsetY = 0, Rotation = 90 },
}

--[[
	background = {
		File, Aspect (w/h), Opacity 0..1, Dim 0..1, Dock,
		Fit = "Fill" | "Fit" | "Stretch" | "Free",
		-- Free only:
		Anchor = "TopLeft" … "BottomRight", Scale (image height / panel height),
		OffsetX, OffsetY (px), Rotation (degrees)
	}
]]
local function backgroundLayer(parent: Instance, bg, theme, radius: number, z: number, solid: boolean?)
	-- a CanvasGroup clips the picture to the surface's rounded corners
	local holder = create("CanvasGroup", {
		Name = "Backdrop",
		BackgroundColor3 = themeColor(theme, "Panel"),
		BackgroundTransparency = solid and 0 or 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
		Parent = parent,
	}, { corner(radius) })
	local ok, id = pcall(getcustomasset, bg.File)
	if ok and id then
		local transparency = 1 - math.clamp(bg.Opacity or 0.6, 0, 1)
		local fit = bg.Fit == "Crop" and "Fill" or (bg.Fit or "Fill")
		if fit == "Free" then
			-- size the box to the rotated picture's bounds so anchoring a corner really hugs the corner
			local a = bg.Aspect or 1
			local rad = math.rad(bg.Rotation or 0)
			local c, s = math.abs(math.cos(rad)), math.abs(math.sin(rad))
			local W, H = a * c + s, a * s + c
			local anchor = ANCHORS[anchorKey(bg.Anchor)]
			local box = create("Frame", {
				Name = "Placement",
				BackgroundTransparency = 1,
				AnchorPoint = anchor,
				Position = UDim2.new(anchor.X, bg.OffsetX or 0, anchor.Y, bg.OffsetY or 0),
				Size = UDim2.fromScale(0, (bg.Scale or 1) * H),
				ZIndex = z,
				Parent = holder,
			}, {
				create("UIAspectRatioConstraint", {
					AspectRatio = W / H,
					AspectType = Enum.AspectType.ScaleWithParentSize,
					DominantAxis = Enum.DominantAxis.Height,
				}),
			})
			create("ImageLabel", {
				Name = "Image",
				BackgroundTransparency = 1,
				Image = id,
				ScaleType = Enum.ScaleType.Stretch,
				ImageTransparency = transparency,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(a / W, 1 / H),
				Rotation = bg.Rotation or 0,
				ZIndex = z,
				Parent = box,
			})
		else
			create("ImageLabel", {
				Name = "Image",
				BackgroundTransparency = 1,
				Image = id,
				ScaleType = FITS[fit] or Enum.ScaleType.Crop,
				ImageTransparency = transparency,
				Size = UDim2.fromScale(1, 1),
				ZIndex = z,
				Parent = holder,
			})
		end
	end
	-- a wash of the panel colour keeps text readable over any picture
	create("Frame", {
		Name = "Dim",
		BackgroundColor3 = themeColor(theme, "Panel"),
		BackgroundTransparency = 1 - math.clamp(bg.Dim or 0.55, 0, 1),
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
		Parent = holder,
	}, { corner(radius) })
	return holder
end

function Hub:_applyBackground()
	for _, layer in self._bgLayers or {} do
		layer:Destroy()
	end
	self._bgLayers = {}
	local bg = self.Background
	self.Dock.BackgroundTransparency = 0
	if not bg or not bg.File or not hasAssets then
		return
	end
	table.insert(self._bgLayers, backgroundLayer(self.Panel, bg, self.Theme, 14, 0))
	if bg.Dock then
		-- the dock lays its children out in a row, so the picture goes behind it in the holder
		self.Dock.BackgroundTransparency = 1
		table.insert(self._bgLayers, backgroundLayer(self.DockHolder, bg, self.Theme, 12, 1, true))
	end
end

function Hub:_saveStudio(colors)
	local data = self.SetupData or { Version = RiftUI.Version }
	data.Theme = self.ThemeName
	data.Studio = { Colors = colors, Background = self.Background }
	self.SetupData = data
	if hasFS then
		pcall(function()
			ensureFolder(RiftUI.Folder)
			ensureFolder(self:_dir())
			writefile(self:_dir() .. "/setup.json", HttpService:JSONEncode(data))
		end)
	end
end

local function placement(source, base)
	local preset = source.Preset and PLACEMENTS[source.Preset] or {}
	local function pick(key, default)
		if source[key] ~= nil then
			return source[key]
		elseif preset[key] ~= nil then
			return preset[key]
		elseif base and base[key] ~= nil then
			return base[key]
		end
		return default
	end
	return {
		Fit = pick("Fit", "Fill") == "Crop" and "Fill" or pick("Fit", "Fill"),
		Anchor = anchorKey(pick("Anchor", "Center")),
		Scale = pick("Scale", 1),
		OffsetX = pick("OffsetX", 0),
		OffsetY = pick("OffsetY", 0),
		Rotation = pick("Rotation", 0),
	}
end

function Hub:SetBackground(source)
	if source == nil then
		self.Background = nil
	else
		local path, aspect = self:_storeBackground(source)
		local bg = placement(source, nil)
		bg.File = path
		bg.Aspect = aspect
		bg.Url = source.Url
		bg.Opacity = source.Opacity or 0.6
		bg.Dim = source.Dim or 0.55
		bg.Dock = source.Dock == true
		self.Background = bg
	end
	self:_applyBackground()
	local studio = self.SetupData and self.SetupData.Studio
	self:_saveStudio(studio and studio.Colors or {})
end

---------------------------------------------------------------- custom themes & share codes
--[[
	A theme ("look") is { Format = "riftui-theme", Version = 1, Name, Base, Colors, Background }.
	Saved themes live in RiftUI/themes/<name>.json and are shared by every hub.
	Share codes are "RIFT1:" .. base64(JSON). A background travels as Image = { Url } or, when the
	author chose to embed it, Image = { Data = base64, Type }. Nothing is downloaded or written
	until the person importing agrees.
]]
local THEME_FORMAT = "riftui-theme"
local SHARE_PREFIX = "RIFT1:"
local MAX_EMBED = 4 * 1024 * 1024

accentTextFor = function(c: Color3): string
	-- dark text on light accents, light text on dark ones
	return (0.299 * c.R + 0.587 * c.G + 0.114 * c.B) > 0.55 and "0F0F11" or "F2F2F3"
end

local function encodeBase64(data: string): string
	local encoder = (typeof(crypt) == "table" and crypt.base64encode) or (typeof(base64_encode) == "function" and base64_encode)
	if encoder then
		local ok, out = pcall(encoder, data)
		if ok and type(out) == "string" then
			return out
		end
	end
	local n = #data
	local out = buffer.create(math.ceil(n / 3) * 4)
	local o = 0
	for i = 1, n, 3 do
		local a, b, c = string.byte(data, i, i + 2)
		local v = a * 65536 + (b or 0) * 256 + (c or 0)
		buffer.writeu8(out, o, string.byte(B64, bit32.extract(v, 18, 6) + 1))
		buffer.writeu8(out, o + 1, string.byte(B64, bit32.extract(v, 12, 6) + 1))
		buffer.writeu8(out, o + 2, b and string.byte(B64, bit32.extract(v, 6, 6) + 1) or 61)
		buffer.writeu8(out, o + 3, c and string.byte(B64, bit32.extract(v, 0, 6) + 1) or 61)
		o += 4
	end
	return buffer.tostring(out)
end

local function themesDir(): string
	return RiftUI.Folder .. "/themes"
end

local function themeFileName(name: string): string
	return (string.gsub(name, "[^%w%s%-_]", ""))
end

-- Checks and normalises a theme table from any source; errors carry a readable reason.
local function validateLook(data)
	if type(data) ~= "table" or data.Format ~= THEME_FORMAT then
		error("that isn't a RiftUI theme", 0)
	end
	local name = type(data.Name) == "string" and themeFileName(data.Name) or ""
	if name == "" then
		error("the theme has no usable name", 0)
	end
	local base = "Graphite"
	for _, t in THEMES do
		if t.Name == data.Base then
			base = t.Name
		end
	end
	local colors = {}
	for k, hex in type(data.Colors) == "table" and data.Colors or {} do
		if type(k) == "string" and DefaultTheme[k] and type(hex) == "string" and pcall(Color3.fromHex, hex) then
			colors[k] = hex
		end
	end
	local bg = nil
	if type(data.Background) == "table" then
		local src = data.Background
		local num = function(v, lo, hi, d)
			return type(v) == "number" and math.clamp(v, lo, hi) or d
		end
		bg = placement(src, nil)
		bg.Scale = num(bg.Scale, 0.05, 3, 1)
		bg.OffsetX = num(bg.OffsetX, -2000, 2000, 0)
		bg.OffsetY = num(bg.OffsetY, -2000, 2000, 0)
		bg.Rotation = num(bg.Rotation, -360, 360, 0)
		bg.Opacity = num(src.Opacity, 0, 1, 0.6)
		bg.Dim = num(src.Dim, 0, 1, 0.55)
		bg.Aspect = num(src.Aspect, 0.05, 20, 1)
		bg.Dock = src.Dock == true
		bg.File = type(src.File) == "string" and src.File or nil
		local image = src.Image
		if type(src.Url) == "string" and string.match(src.Url, "^https?://") then
			bg.Url = src.Url
			image = image or { Url = src.Url }
		end
		if type(image) == "table" then
			if type(image.Url) == "string" and string.match(image.Url, "^https?://") then
				bg.Image = { Url = image.Url }
			elseif type(image.Data) == "string" and #image.Data <= MAX_EMBED * 4 / 3 then
				bg.Image = { Data = image.Data, Type = image.Type }
			end
		end
		if not bg.Image and not bg.File then
			bg = nil
		end
	end
	return { Format = THEME_FORMAT, Version = 1, Name = name, Base = base, Colors = colors, Background = bg }
end

function RiftUI:ListThemes(): { string }
	local out = {}
	if not hasFS or typeof(listfiles) ~= "function" or not isfolder(themesDir()) then
		return out
	end
	for _, path in listfiles(themesDir()) do
		local name = string.match(path, "([^/\\]+)%.json$")
		if name then
			table.insert(out, name)
		end
	end
	table.sort(out)
	return out
end

function Hub:SaveTheme(lookData)
	if not hasFS then
		error("this executor can't write files", 0)
	end
	local data = validateLook(lookData)
	-- keep the local file path so applying it later needs no download
	if data.Background and lookData.Background then
		data.Background.File = lookData.Background.File
	end
	ensureFolder(RiftUI.Folder)
	ensureFolder(themesDir())
	writefile(themesDir() .. "/" .. data.Name .. ".json", HttpService:JSONEncode(data))
	return data
end

function Hub:LoadTheme(name: string)
	local path = themesDir() .. "/" .. themeFileName(name) .. ".json"
	if not hasFS or not isfile(path) then
		error("there's no saved theme called " .. tostring(name), 0)
	end
	local data = validateLook(HttpService:JSONDecode(readfile(path)))
	if data.Background and data.Background.File and not isfile(data.Background.File) then
		data.Background.File = nil
	end
	return data
end

function Hub:DeleteTheme(name: string)
	local path = themesDir() .. "/" .. themeFileName(name) .. ".json"
	if hasFS and typeof(delfile) == "function" and isfile(path) then
		delfile(path)
	end
end

-- A share code for a theme. With embedImage, a local background image travels inside it.
function Hub:ExportTheme(lookData, embedImage: boolean?): string
	local data = validateLook(lookData)
	local bg = data.Background
	if bg then
		local file = lookData.Background and lookData.Background.File
		if bg.Url then
			bg.Image = { Url = bg.Url }
		elseif embedImage and file and hasFS and isfile(file) then
			local bytes = readfile(file)
			if #bytes > MAX_EMBED then
				error("the image is too big to embed (over 4 MB); host it and use a URL instead", 0)
			end
			bg.Image = { Data = encodeBase64(bytes), Type = imageKind(bytes) }
		else
			bg.Image = nil
		end
		bg.File = nil
		if not bg.Image then
			data.Background = nil
		end
	end
	return SHARE_PREFIX .. encodeBase64(HttpService:JSONEncode(data))
end

-- Reads a share code (prefix optional). Doesn't download or write the image; see FetchThemeImage.
function Hub:ImportTheme(code: string)
	code = string.gsub(tostring(code or ""), "%s", "")
	if code == "" then
		error("paste a share code first", 0)
	end
	code = string.gsub(code, "^" .. SHARE_PREFIX, "")
	local ok, data = pcall(function()
		return HttpService:JSONDecode(decodeBase64(code))
	end)
	if not ok then
		error("that code is damaged or incomplete", 0)
	end
	local lookData = validateLook(data)
	if lookData.Background then
		lookData.Background.File = nil
	end
	return lookData
end

-- Downloads (Url) or writes (embedded Data) a theme's image into this hub's folder.
function Hub:FetchThemeImage(lookData): (string, number)
	local bg = lookData.Background
	local image = bg and bg.Image
	if not image then
		error("this theme has no image", 0)
	end
	local path, aspect = self:_storeBackground({ Url = image.Url, Base64 = image.Data })
	bg.File = path
	bg.Aspect = aspect
	bg.Url = image.Url
	return path, aspect
end

-- Move or restyle the current background without loading it again:
-- Hub:PlaceBackground({ Preset = "Body pillow" }) or { Anchor = "TopLeft", Rotation = 90, Scale = 0.6 }
function Hub:PlaceBackground(changes)
	local bg = self.Background
	if not bg then
		return
	end
	local p = placement(changes, bg)
	for k, v in p do
		bg[k] = v
	end
	for _, key in { "Opacity", "Dim", "Dock" } do
		if changes[key] ~= nil then
			bg[key] = changes[key]
		end
	end
	self:_applyBackground()
	local studio = self.SetupData and self.SetupData.Studio
	self:_saveStudio(studio and studio.Colors or {})
end

---------------------------------------------------------------- config sharing and manager
local CONFIG_PREFIX = "RIFTCFG1:"

function Hub:ExportConfig(name: string, options): (string?, string?)
	if not configName(name) then return nil, "invalid config name" end
	local path = self:_configDir() .. "/" .. name .. ".json"
	if not hasFS or not isfile(path) then return nil, "no config named " .. name end
	local ok, value = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
	if not ok or type(value) ~= "table" then return nil, "config file is damaged" end
	-- Preserve an already encrypted file when sharing, even without its key.
	if value.Format == CONFIG_ENCRYPTED and (not options or options.Encrypt ~= false) then
		return CONFIG_ENCRYPTED_PREFIX .. encodeBase64(HttpService:JSONEncode(value))
	end
	local payload, err = self:_decodeConfig(value, options)
	if not payload then return nil, err end
	payload.Name = name
	if options and options.Encrypt then
		local envelope
		envelope, err = self:_encryptConfig(payload, options)
		if not envelope then return nil, err end
		return CONFIG_ENCRYPTED_PREFIX .. encodeBase64(HttpService:JSONEncode(envelope))
	end
	return CONFIG_PREFIX .. encodeBase64(HttpService:JSONEncode(payload))
end

function Hub:ImportConfig(code: string, saveAs: string?, options): (boolean, string?)
	code = string.gsub(tostring(code or ""), "%s", "")
	if #code > CONFIG_LIMIT * 3 then return false, "config code is too large" end
	local prefix = string.sub(code, 1, #CONFIG_PREFIX)
	if prefix ~= CONFIG_PREFIX and prefix ~= CONFIG_ENCRYPTED_PREFIX then return false, "not a RiftUI config code" end
	local ok, value = pcall(function() return HttpService:JSONDecode(decodeBase64(string.sub(code, #CONFIG_PREFIX + 1))) end)
	if not ok then return false, "the code is cut off or damaged" end
	if prefix == CONFIG_ENCRYPTED_PREFIX and (type(value) ~= "table" or value.Format ~= CONFIG_ENCRYPTED) then return false, "invalid encrypted config code" end
	local payload, err, envelope = self:_decodeConfig(value, options)
	if not payload then return false, err end
	local name = saveAs and saveAs ~= "" and saveAs or payload.Name or "imported"
	if not envelope and self._encryptConfigs then
		envelope, err = self:_encryptConfig(payload, options)
		if not envelope then return false, err end
	end
	return self:_writeConfig(name, payload, envelope)
end

local function ago(t: number?): string
	if type(t) ~= "number" then
		return "saved earlier"
	end
	local d = math.max(0, os.time() - t)
	if d < 60 then
		return "saved just now"
	elseif d < 3600 then
		return "saved " .. math.floor(d / 60) .. " min ago"
	elseif d < 86400 then
		return "saved " .. math.floor(d / 3600) .. " h ago"
	end
	return "saved " .. math.floor(d / 86400) .. " d ago"
end

function Hub:_buildConfigManager()
	local theme = self.Theme
	local win = self:Window({ Title = "Configs", Description = "Save, load and share setups for " .. self.Name, Icon = "folder", Width = 620, Height = 470, _internal = true })
	local function toast(ok, title, detail, err)
		self:Notify(ok and { Title = title, Content = detail, Duration = 3 } or { Title = "Couldn't " .. string.lower(title), Content = err, Tone = self.Theme.Danger })
	end

	local saved = win:Tab({ Name = "Saved", Icon = "folder" })
	local listSection = saved:Section({ Name = "Saved configs", Side = "Left" })
	local holderRow = listSection:_row(0, "ConfigList")
	holderRow.AutomaticSize = Enum.AutomaticSize.Y
	local listFrame = create("Frame", { Name = "Rows", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = holderRow }, {
		list(Enum.FillDirection.Vertical, 4), padding(4, 0, 4, 0),
	})

	local selectedSection = saved:Section({ Name = "Selected", Side = "Right" })
	local selectedName = selectedSection:_info("Config", "None")
	local selected
	selectedSection:Button({ Name = "Load", Callback = function()
		if not selected then return end
		local ok, err = self:LoadConfig(selected)
		toast(ok, "Load", selected, err)
	end })
	selectedSection:Button({ Name = "Save current settings here", Callback = function()
		if not selected then return end
		local ok, err = self:SaveConfig(selected)
		toast(ok, "Save", selected, err)
	end })
	local autoToggle = selectedSection:Toggle({ Name = "Load on start", Description = "Applied when the hub starts", Callback = function(on)
		if not selected then return end
		self:SetAutoload(on and selected or nil)
	end })
	local renameBox = selectedSection:Input({ Name = "Rename to", Placeholder = "New name" })
	selectedSection:Button({ Name = "Rename", Callback = function()
		if not selected then return end
		local to = renameBox.Value
		local ok, err = self:RenameConfig(selected, to)
		if ok then selected = to renameBox:Set("", true) end
		toast(ok, "Rename", tostring(to), err)
	end })
	selectedSection:Button({ Name = "Delete", Danger = true, Callback = function()
		if not selected then return end
		local name = selected
		self:Prompt({
			Title = "Delete " .. name .. "?",
			Content = "The file is removed from RiftUI/" .. self.Id .. "/configs. This can't be undone.",
			Icon = "trash-2",
			Buttons = {
				{ Text = "Cancel" },
				{ Text = "Delete", Primary = true, Callback = function()
					local ok, err = self:DeleteConfig(name)
					if ok and selected == name then selected = nil end
					toast(ok, "Delete", name, err)
				end },
			},
		})
	end })

	local newSection = saved:Section({ Name = "New config", Side = "Right" })
	local newName = newSection:Input({ Name = "Name", Placeholder = "e.g. legit", Default = "" })
	newSection:Button({ Name = "Save current settings", Callback = function()
		local name = newName.Value ~= "" and newName.Value or "default"
		local ok, err = self:SaveConfig(name)
		if ok then selected = name newName:Set("", true) end
		toast(ok, "Save", name, err)
	end })

	if self._configEncryption then
		local storage = saved:Section({ Name = "Storage", Side = "Right" })
		storage:Toggle({ Name = "Encrypt saved configs", Default = self._encryptConfigs, Description = "Uses the key supplied by this hub", Callback = function(on)
			self._encryptConfigs = on
			self:_savePref("EncryptConfigs", on)
		end })
	end
	if self._configServer then
		local remote = win:Tab({ Name = "Remote", Icon = "cloud-download" })
		local source = remote:Section({ Name = "Config server", Side = "Left" })
		local id = source:Input({ Name = "Config ID", Placeholder = "e.g. premium-legit" })
		local cache = source:Toggle({ Name = "Save a local copy", Default = false })
		source:Button({ Name = "Load remote config", Callback = function()
			local ok, err = self:LoadRemoteConfig(id.Value, { SaveAs = cache.Value and id.Value or nil })
			toast(ok, "Load remote config", id.Value, err)
		end })
		source:Paragraph({ Content = "Access is checked by the config server. Remote configs stay in memory unless you save a local copy." })
	end

	local share = win:Tab({ Name = "Share", Icon = "share-2" })
	local export = share:Section({ Name = "Export", Side = "Left" })
	local exportPick = export:Dropdown({ Name = "Config", Options = self:ListConfigs() })
	export:Button({ Name = "Copy share code", Callback = function()
		local name = exportPick.Value
		if not name then
			toast(false, "Copy", nil, "pick a config first")
			return
		end
		local code, err = self:ExportConfig(name)
		if code and typeof(setclipboard) == "function" then
			setclipboard(code)
			toast(true, "Copied", name .. " share code is on your clipboard.")
		else
			toast(false, "Copy", nil, err or "this executor has no clipboard")
		end
	end })
	export:Paragraph({ Title = "What's in a code", Content = "Control values, pins, keys and scale. Codes only import into a hub with the ID " .. self.Id .. "." })
	local import = share:Section({ Name = "Import", Side = "Right" })
	local codeBox = import:Input({ Name = "Share code", Placeholder = CONFIG_PREFIX .. "…" })
	local asBox = import:Input({ Name = "Save as", Placeholder = "Keep original name" })
	import:Button({ Name = "Import", Callback = function()
		local ok, result = self:ImportConfig(codeBox.Value, asBox.Value)
		if ok then
			selected = result
			codeBox:Set("", true)
			asBox:Set("", true)
			win:SelectTab(saved)
		end
		toast(ok, "Import", ok and (result .. " saved. Load it from Saved.") or nil, result)
	end })

	local rows = {}
	local function refresh()
		local names = self:ListConfigs()
		if selected and not table.find(names, selected) then selected = nil end
		local autoload = self:GetAutoload()
		for _, r in rows do r:Destroy() end
		table.clear(rows)
		if #names == 0 then
			table.insert(rows, text({ Parent = listFrame, Text = "No configs yet. Save one under New config.", TextSize = 12, TextColor3 = themeColor(theme, "SubText"), TextWrapped = true, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y }))
		end
		for i, name in names do
			local info = self:ConfigInfo(name) or { Name = name }
			local on = name == selected
			local row = create("TextButton", {
				Name = "Config_" .. name, Text = "", AutoButtonColor = false,
				BackgroundColor3 = themeColor(theme, "TileActive"), BackgroundTransparency = on and 0 or 1,
				Size = UDim2.new(1, 0, 0, 44), LayoutOrder = i, Parent = listFrame,
			}, { corner(8) })
			if on then stroke(themeColor(theme, "TileActiveStroke")).Parent = row end
			iconLabel(name == autoload and "zap" or "file", 15, name == autoload and theme.Accent or theme.SubText, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Parent = row })
			text({ Parent = row, Text = name, FontFace = inter(Enum.FontWeight.Medium), TextSize = 13, Position = UDim2.fromOffset(34, 6), Size = UDim2.new(1, -44, 0, 17), TextTruncate = Enum.TextTruncate.AtEnd })
			local meta = info.Encrypted and (info.Locked and "encrypted · key required" or "encrypted") or (info.Damaged and "damaged file" or ((info.Settings or 0) .. " settings · " .. ago(info.SavedAt)))
			if name == autoload then meta ..= " · loads on start" end
			text({ Parent = row, Text = meta, TextSize = 11, TextColor3 = themeColor(theme, info.Damaged and "Danger" or "SubText"), Position = UDim2.fromOffset(34, 23), Size = UDim2.new(1, -44, 0, 15), TextTruncate = Enum.TextTruncate.AtEnd })
			row.MouseEnter:Connect(function() if selected ~= name then tween(row, FAST, { BackgroundTransparency = 0.5 }) end end)
			row.MouseLeave:Connect(function() if selected ~= name then tween(row, FAST, { BackgroundTransparency = 1 }) end end)
			row.MouseButton1Click:Connect(function()
				selected = name
				refresh()
			end)
			table.insert(rows, row)
		end
		selectedName:Set(selected or "None")
		selectedSection.Frame.Visible = selected ~= nil
		autoToggle:Set(selected ~= nil and selected == autoload, true)
		local current = selected or exportPick.Value
		exportPick:SetOptions(names)
		if current and table.find(names, current) then exportPick:Set(current, true) end
	end
	self:_watchConfigs(refresh)
	refresh()
	self.ConfigManager = win
	return win
end

function Hub:OpenThemeStudio()
	if self._studioOpen then
		return
	end
	self._studioOpen = true
	local originalTheme = table.clone(self.Theme)
	local originalName = self.ThemeName
	local theme = self.Theme
	local savedStudio = self.SetupData and self.SetupData.Studio or {}
	local draft = {
		ThemeName = self.ThemeName,
		Accent = theme.Accent,
		Background = self.Background and table.clone(self.Background) or nil,
		Source = "None",
		Opacity = self.Background and self.Background.Opacity or 0.6,
		Dim = self.Background and self.Background.Dim or 0.55,
		Dock = self.Background and self.Background.Dock or false,
	}
	for k, v in placement({}, self.Background) do
		draft[k] = v
	end
	local accentChanged = savedStudio.Colors and savedStudio.Colors.Accent ~= nil

	local layer = create("Frame", { Name = "ThemeStudio", BackgroundColor3 = themeColor(theme, "Scrim"), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Active = true, ZIndex = 70, Parent = self.Gui })
	local holder = create("Frame", { Name = "Window", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 16), Size = UDim2.fromOffset(660, 470), ZIndex = 71, Parent = layer })
	shadow(holder, 34, 71, 10)
	local win = create("CanvasGroup", { Name = "Body", BackgroundColor3 = themeColor(theme, "Panel"), Size = UDim2.fromScale(1, 1), GroupTransparency = 1, ZIndex = 72, Parent = holder }, { corner(14) })
	create("Frame", { Name = "Outline", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 80, Parent = holder }, { corner(14), stroke(themeColor(theme, "PanelStroke")) })
	sheen(win, 16, theme, 79)
	text({ Parent = win, Text = "Theme studio", TextSize = 19, FontFace = inter(Enum.FontWeight.SemiBold), Position = UDim2.fromOffset(24, 22), Size = UDim2.new(1, -48, 0, 24), ZIndex = 73 })
	text({ Parent = win, Text = "Colours and background for " .. self.Name .. ". Saved per hub.", TextSize = 13, TextColor3 = themeColor(theme, "SubText"), Position = UDim2.fromOffset(24, 48), Size = UDim2.new(1, -48, 0, 28), TextWrapped = true, ZIndex = 73 })
	create("Frame", { Name = "Rule", BackgroundColor3 = themeColor(theme, "Divider"), BorderSizePixel = 0, Position = UDim2.fromOffset(0, 80), Size = UDim2.new(1, 0, 0, 1), ZIndex = 73, Parent = win })

	-- left: controls
	local scroll = create("ScrollingFrame", {
		Name = "Controls",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(16, 88),
		Size = UDim2.new(0, 330, 1, -88 - 64),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = themeColor(theme, "Knob"),
		ZIndex = 73,
		Parent = win,
	})
	local col = create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -10, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 73, Parent = scroll }, {
		padding(0, 8, 8, 8),
		list(Enum.FillDirection.Vertical, 8),
	})
	local fakeTab = setmetatable({ Hub = self, Name = "Studio", Sections = {}, Columns = { col, col, Frame = col }, _internal = true, _recount = function() end }, Tab)

	-- right: a live miniature of a panel
	local previewHost = create("Frame", { Name = "Preview", BackgroundTransparency = 1, Position = UDim2.new(0, 358, 0, 96), Size = UDim2.new(1, -382, 1, -96 - 80), ZIndex = 73, Parent = win })
	text({ Parent = previewHost, Text = "PREVIEW", TextSize = 11, FontFace = inter(Enum.FontWeight.SemiBold), TextColor3 = themeColor(theme, "Muted"), Size = UDim2.new(1, 0, 0, 14), ZIndex = 74 })
	local status = text({ Parent = previewHost, Text = "", TextSize = 11, TextColor3 = themeColor(theme, "SubText"), TextWrapped = true, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 28), TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 74 })
	fitModal(self, layer, holder, 660, 470, function(w)
		local narrow = w < 580
		previewHost.Visible = not narrow
		scroll.Size = UDim2.new(narrow and 1 or 0, narrow and -32 or 324, 1, narrow and -200 or -168)
		status.Parent = narrow and win or previewHost
		status.Position = narrow and UDim2.new(0, 24, 1, -66) or UDim2.new(0, 0, 1, 0)
		status.Size = narrow and UDim2.new(1, -48, 0, 28) or UDim2.new(1, 0, 0, 28)
	end)
	local miniHolder
	local function drawPreview()
		self:_transitionTheme(draft.ThemeName, { Accent = draft.Accent, AccentText = Color3.fromHex(accentTextFor(draft.Accent)) })
		if miniHolder then
			miniHolder:Destroy()
		end
		local t = buildTheme(draft.ThemeName, { Accent = draft.Accent })
		miniHolder = create("Frame", { Name = "Mini", BackgroundColor3 = t.Panel, Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 1, -60), ZIndex = 74, Parent = previewHost }, { corner(12) })
		miniHolder:SetAttribute("ThemeSwatch", true)
		stroke(t.PanelStroke).Parent = miniHolder
		if draft.Background then
			backgroundLayer(miniHolder, {
				File = draft.Background.File,
				Aspect = draft.Background.Aspect,
				Opacity = draft.Opacity,
				Dim = draft.Dim,
				Fit = draft.Fit,
				Anchor = draft.Anchor,
				Scale = draft.Scale,
				-- the preview is about half size, so offsets shrink with it
				OffsetX = draft.OffsetX * 0.5,
				OffsetY = draft.OffsetY * 0.5,
				Rotation = draft.Rotation,
			}, t, 12, 74)
		end
		local content = create("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 75, Parent = miniHolder }, { padding(14) })
		local chip = create("Frame", { BackgroundColor3 = t.Tile, Size = UDim2.fromOffset(26, 26), ZIndex = 76, Parent = content }, { corner(7), stroke(t.TileStroke) })
		iconLabel("crosshair", 14, t.Text, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 77, Parent = chip })
		text({ Parent = content, Text = "Combat", FontFace = inter(Enum.FontWeight.SemiBold), TextSize = 13, TextColor3 = t.Text, Position = UDim2.fromOffset(36, 0), Size = UDim2.new(1, -36, 0, 15), ZIndex = 76 })
		text({ Parent = content, Text = "Aim assist", TextSize = 11, TextColor3 = t.SubText, Position = UDim2.fromOffset(36, 14), Size = UDim2.new(1, -36, 0, 13), ZIndex = 76 })
		text({ Parent = content, Text = "AIM ASSIST", TextSize = 10, FontFace = inter(Enum.FontWeight.SemiBold), TextColor3 = t.SubText, Position = UDim2.fromOffset(0, 44), Size = UDim2.fromOffset(70, 14), ZIndex = 76 })
		create("Frame", { BackgroundColor3 = t.Divider, BorderSizePixel = 0, Position = UDim2.new(0, 72, 0, 51), Size = UDim2.new(1, -72, 0, 1), ZIndex = 76, Parent = content })
		local rows = { { "Enabled", true }, { "Team check", false } }
		for i, r in rows do
			local y = 62 + (i - 1) * 26
			text({ Parent = content, Text = r[1], TextSize = 12, TextColor3 = r[2] and t.Text or t.SubText, Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, -24, 0, 18), ZIndex = 76 })
			local box = create("Frame", { BackgroundColor3 = r[2] and t.Accent or t.Field, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, y + 2), Size = UDim2.fromOffset(14, 14), ZIndex = 76, Parent = content }, { corner(4) })
			stroke(r[2] and t.Accent or t.FieldStroke).Parent = box
			if r[2] then
				iconLabel("check", 10, t.AccentText, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 77, Parent = box })
			end
		end
		text({ Parent = content, Text = "Field of view", TextSize = 12, TextColor3 = t.Text, Position = UDim2.fromOffset(0, 118), Size = UDim2.new(1, -40, 0, 18), ZIndex = 76 })
		text({ Parent = content, Text = "248", FontFace = MONO, TextSize = 11, TextColor3 = t.SubText, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 118), Size = UDim2.fromOffset(40, 18), ZIndex = 76 })
		local track = create("Frame", { BackgroundColor3 = t.Track, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 144), Size = UDim2.new(1, 0, 0, 2), ZIndex = 76, Parent = content })
		create("Frame", { BackgroundColor3 = t.Accent, BorderSizePixel = 0, Size = UDim2.fromScale(0.62, 1), ZIndex = 77, Parent = track })
		create("Frame", { BackgroundColor3 = t.Accent, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.62, 0.5), Size = UDim2.fromOffset(4, 12), ZIndex = 78, Parent = track }, { corner(2) })
	end

	-- controls
	local look = fakeTab:Section({ Name = "Look", Pinnable = false })
	local names = {}
	for _, t in THEMES do
		table.insert(names, t.Name)
	end
	local baseControl = look:Dropdown({
		Name = "Base theme",
		Options = names,
		Default = draft.ThemeName,
		Callback = function(v)
			draft.ThemeName = v
			if not accentChanged then
				draft.Accent = buildTheme(v, nil).Accent
			end
			drawPreview()
		end,
	})
	local accentPicker = look:ColorPicker({
		Name = "Accent",
		Default = draft.Accent,
		Callback = function(c)
			draft.Accent = c
			accentChanged = true
			drawPreview()
		end,
	})

	local bgSection = fakeTab:Section({ Name = "Background image", Pinnable = false })
	local sourceInputs = {}
	bgSection:Dropdown({
		Name = "Source",
		Options = { "None", "URL", "Base64", "Workspace file" },
		Default = draft.Background and "Workspace file" or "None",
		Callback = function(v)
			draft.Source = v
			for key, input in sourceInputs do
				input:SetVisible(key == v)
			end
			if v == "None" then
				draft.Background = nil
				status.Text = "No background image."
				drawPreview()
			end
		end,
	})
	sourceInputs.URL = bgSection:Input({ Name = "Image URL", Placeholder = "https://… (.png, .jpg, or base64 text)" })
	sourceInputs.Base64 = bgSection:Input({ Name = "Base64 data", Placeholder = "iVBORw0KGgo… or data:image/png;base64,…" })
	sourceInputs["Workspace file"] = bgSection:Input({ Name = "File path", Placeholder = "e.g. waifu.png", Default = draft.Background and draft.Background.File or "" })
	for key, input in sourceInputs do
		input:SetVisible(draft.Background ~= nil and key == "Workspace file")
	end
	bgSection:Button({
		Name = "Load image",
		Callback = function()
			local src = draft.Source == "None" and (draft.Background and "Workspace file") or draft.Source
			if not src or src == "None" then
				status.Text = "Pick a source first."
				setThemed(status, "TextColor3", themeColor(theme, "Warning"))
				return
			end
			local value = sourceInputs[src].Value
			status.Text = "Loading…"
			setThemed(status, "TextColor3", themeColor(theme, "SubText"))
			local ok, result = pcall(function()
				return self:_storeBackground({
					Url = src == "URL" and value or nil,
					Base64 = src == "Base64" and value or nil,
					File = src == "Workspace file" and value or nil,
				})
			end)
			if ok then
				local _, aspect = self:_storeBackground({ File = result })
				draft.Background = { File = result, Aspect = aspect, Url = src == "URL" and value or nil }
				status.Text = "Saved to " .. result
				setThemed(status, "TextColor3", themeColor(theme, "Success"))
			else
				status.Text = tostring(result)
				setThemed(status, "TextColor3", themeColor(theme, "Danger"))
				recordError("background: " .. tostring(result), nil, "theme studio")
			end
			drawPreview()
		end,
	})
	local opacityControl = bgSection:Slider({ Name = "Image opacity", Min = 0, Max = 100, Step = 5, Default = math.floor(draft.Opacity * 100 + 0.5), Suffix = "%", Callback = function(v)
		draft.Opacity = v / 100
		drawPreview()
	end })
	local dimControl = bgSection:Slider({ Name = "Dim", Min = 0, Max = 95, Step = 5, Default = math.floor(draft.Dim * 100 + 0.5), Suffix = "%", Callback = function(v)
		draft.Dim = v / 100
		drawPreview()
	end })
	-- placement
	local place = fakeTab:Section({ Name = "Placement", Pinnable = false })
	local freeControls = {}
	local function syncFree()
		for _, c in freeControls do
			c:SetVisible(draft.Fit == "Free")
		end
	end
	local presetNames = { "Full", "Corner", "Body pillow", "Body pillow (lying down)" }
	local fitControl, anchorControl, scaleControl, xControl, yControl, rotControl
	place:Dropdown({
		Name = "Preset",
		Options = presetNames,
		Default = nil,
		Callback = function(name)
			local p = PLACEMENTS[name]
			if not p then
				return
			end
			for k, v in p do
				draft[k] = v
			end
			fitControl:Set(draft.Fit, true)
			anchorControl:Set(anchorLabel(draft.Anchor), true)
			scaleControl:Set(math.floor(draft.Scale * 100 + 0.5), true)
			xControl:Set(draft.OffsetX, true)
			yControl:Set(draft.OffsetY, true)
			rotControl:Set(draft.Rotation, true)
			syncFree()
			drawPreview()
		end,
	})
	fitControl = place:Dropdown({
		Name = "Fit",
		Description = "Free lets you anchor, size and rotate it",
		Options = { "Fill", "Fit", "Stretch", "Free" },
		Default = draft.Fit,
		Callback = function(v)
			draft.Fit = v
			syncFree()
			drawPreview()
		end,
	})
	anchorControl = place:Dropdown({
		Name = "Anchor",
		Options = ANCHOR_NAMES,
		Default = anchorLabel(draft.Anchor),
		Callback = function(v)
			draft.Anchor = anchorKey(v)
			drawPreview()
		end,
	})
	scaleControl = place:Slider({ Name = "Size", Min = 10, Max = 200, Step = 5, Default = math.floor(draft.Scale * 100 + 0.5), Suffix = "%", Callback = function(v)
		draft.Scale = v / 100
		drawPreview()
	end })
	xControl = place:Slider({ Name = "Offset X", Min = -300, Max = 300, Step = 2, Default = draft.OffsetX, Suffix = " px", Callback = function(v)
		draft.OffsetX = v
		drawPreview()
	end })
	yControl = place:Slider({ Name = "Offset Y", Min = -300, Max = 300, Step = 2, Default = draft.OffsetY, Suffix = " px", Callback = function(v)
		draft.OffsetY = v
		drawPreview()
	end })
	rotControl = place:Slider({ Name = "Rotation", Min = -180, Max = 180, Step = 15, Default = draft.Rotation, Suffix = "°", Callback = function(v)
		draft.Rotation = v
		drawPreview()
	end })
	freeControls = { anchorControl, scaleControl, xControl, yControl, rotControl }
	syncFree()
	local dockControl = bgSection:Toggle({ Name = "Also behind the toolbar", Default = draft.Dock, Callback = function(v)
		draft.Dock = v
	end })
	if not hasAssets then
		bgSection:Paragraph({ Title = "Not available here", Content = "This executor is missing writefile or getcustomasset, so background images can't be shown." })
	end

	---------------------------------------------------------------- your themes: save, share, import
	local function lookFromDraft(name: string)
		local colors = {}
		if accentChanged then
			colors.Accent = draft.Accent:ToHex()
			colors.AccentText = accentTextFor(draft.Accent)
		end
		local bg
		if draft.Background then
			bg = {
				File = draft.Background.File,
				Aspect = draft.Background.Aspect,
				Url = draft.Background.Url,
				Opacity = draft.Opacity,
				Dim = draft.Dim,
				Fit = draft.Fit,
				Anchor = draft.Anchor,
				Scale = draft.Scale,
				OffsetX = draft.OffsetX,
				OffsetY = draft.OffsetY,
				Rotation = draft.Rotation,
				Dock = draft.Dock,
			}
		end
		return { Format = THEME_FORMAT, Version = 1, Name = name, Base = draft.ThemeName, Colors = colors, Background = bg }
	end
	local function applyLook(lookData)
		draft.ThemeName = lookData.Base
		baseControl:Set(lookData.Base, true)
		local accentHex = lookData.Colors and lookData.Colors.Accent
		if accentHex then
			draft.Accent = Color3.fromHex(accentHex)
			accentChanged = true
		else
			draft.Accent = buildTheme(lookData.Base, nil).Accent
			accentChanged = false
		end
		accentPicker:Set(draft.Accent, true)
		local bg = lookData.Background
		if bg then
			for k, v in placement(bg, nil) do
				draft[k] = v
			end
			draft.Opacity, draft.Dim, draft.Dock = bg.Opacity or 0.6, bg.Dim or 0.55, bg.Dock == true
			draft.Background = bg.File and { File = bg.File, Aspect = bg.Aspect, Url = bg.Url } or nil
		else
			draft.Background = nil
			for k, v in PLACEMENTS.Full do
				draft[k] = v
			end
		end
		fitControl:Set(draft.Fit, true)
		anchorControl:Set(anchorLabel(draft.Anchor), true)
		scaleControl:Set(math.floor(draft.Scale * 100 + 0.5), true)
		xControl:Set(draft.OffsetX, true)
		yControl:Set(draft.OffsetY, true)
		rotControl:Set(draft.Rotation, true)
		opacityControl:Set(math.floor(draft.Opacity * 100 + 0.5), true)
		dimControl:Set(math.floor(draft.Dim * 100 + 0.5), true)
		dockControl:Set(draft.Dock, true)
		syncFree()
		drawPreview()
	end
	local function say(msg: string, tone)
		status.Text = msg
		setThemed(status, "TextColor3", tone or themeColor(theme, "SubText"))
	end
	-- ask before downloading or writing an image that came with a theme, then apply it
	local function offerImage(lookData)
		local image = lookData.Background and lookData.Background.Image
		if not image or (lookData.Background.File and isfile(lookData.Background.File)) then
			applyLook(lookData)
			say("Applied " .. lookData.Name .. ". Save to keep it.", theme.Success)
			return
		end
		local isUrl = image.Url ~= nil
		local host = isUrl and (string.match(image.Url, "^https?://([^/]+)") or image.Url) or nil
		self:Prompt({
			Icon = "image-down",
			Title = isUrl and "Download this theme's image?" or "Save this theme's image?",
			Content = isUrl and ("“" .. lookData.Name .. "” uses a background image from " .. host .. ". RiftUI only downloads it if you say so.")
				or ("“" .. lookData.Name .. "” carries its own background image (" .. math.ceil(#image.Data * 3 / 4 / 1024) .. " KB). It gets written to your workspace."),
			Buttons = {
				{
					Text = "Without image",
					Callback = function()
						lookData.Background = nil
						applyLook(lookData)
						say("Applied " .. lookData.Name .. " without its image.", theme.SubText)
					end,
				},
				{
					Text = isUrl and "Download" or "Save image",
					Primary = true,
					Callback = function()
						say("Fetching image…")
						local ok, path, aspect = pcall(self.FetchThemeImage, self, lookData)
						if ok then
							applyLook(lookData)
							pcall(self.SaveTheme, self, lookData)
							say("Applied " .. lookData.Name .. " with its image (" .. path .. "). Save to keep it.", theme.Success)
						else
							say("Couldn't get the image: " .. tostring(path), theme.Danger)
							recordError("theme image: " .. tostring(path), nil, "theme studio")
						end
						local _ = aspect
					end,
				},
			},
		})
	end

	local mine = fakeTab:Section({ Name = "Your themes", Pinnable = false })
	local nameBox = mine:Input({ Name = "Theme name", Placeholder = "e.g. Midnight Sakura" })
	local savedPick
	local function refreshSaved()
		savedPick:SetOptions(RiftUI:ListThemes())
	end
	mine:Button({
		Name = "Save as theme",
		Callback = function()
			local name = nameBox.Value
			local ok, err = pcall(self.SaveTheme, self, lookFromDraft(name))
			if ok then
				refreshSaved()
				say("Saved “" .. name .. "” to " .. RiftUI.Folder .. "/themes.", theme.Success)
			else
				say(tostring(err), theme.Danger)
			end
		end,
	})
	savedPick = mine:Dropdown({
		Name = "Saved themes",
		Options = RiftUI:ListThemes(),
		Default = nil,
		Callback = function(name)
			local ok, data = pcall(self.LoadTheme, self, name)
			if ok then
				nameBox:Set(name, true)
				offerImage(data)
			else
				say(tostring(data), theme.Danger)
			end
		end,
	})
	mine:Button({
		Name = "Delete selected",
		Danger = true,
		Callback = function()
			if savedPick.Value then
				self:DeleteTheme(savedPick.Value)
				say("Deleted “" .. savedPick.Value .. "”.")
				savedPick:Set(nil, true)
				refreshSaved()
			end
		end,
	})

	local share = fakeTab:Section({ Name = "Share", Pinnable = false })
	local codeBox = share:Input({ Name = "Share code", Placeholder = "RIFT1:… paste a code here to import it" })
	local function export(embed: boolean)
		local name = nameBox.Value ~= "" and nameBox.Value or (draft.ThemeName .. " remix")
		local ok, code = pcall(self.ExportTheme, self, lookFromDraft(name), embed)
		if not ok then
			say(tostring(code), theme.Danger)
			return
		end
		codeBox:Set(code, true)
		local copied = typeof(setclipboard) == "function" and pcall(setclipboard, code)
		say(string.format("%s code for “%s” (%d characters).", copied and "Copied the" or "Here's the", name, #code), theme.Success)
	end
	share:Button({
		Name = "Copy share code",
		Callback = function()
			local bg = draft.Background
			if bg and not bg.Url then
				-- the image only exists in this workspace: embed it, or share the look without it
				local size = 0
				pcall(function()
					size = #readfile(bg.File)
				end)
				self:Prompt({
					Icon = "image",
					Title = "Include the background image?",
					Content = "This image isn't from a URL, so other people can only get it if it's embedded in the code (+" .. math.ceil(size * 4 / 3 / 1024) .. " KB of text).",
					Buttons = {
						{ Text = "Leave it out", Callback = function()
							export(false)
						end },
						{ Text = "Embed image", Primary = true, Callback = function()
							export(true)
						end },
					},
				})
			else
				export(false)
			end
		end,
	})
	share:Button({
		Name = "Import code",
		Callback = function()
			local ok, data = pcall(self.ImportTheme, self, codeBox.Value)
			if not ok then
				say(tostring(data), theme.Danger)
				return
			end
			pcall(self.SaveTheme, self, data)
			refreshSaved()
			nameBox:Set(data.Name, true)
			offerImage(data)
		end,
	})

	-- footer
	create("Frame", { Name = "Rule", BackgroundColor3 = themeColor(theme, "Divider"), BorderSizePixel = 0, Position = UDim2.new(0, 0, 1, -64), Size = UDim2.new(1, 0, 0, 1), ZIndex = 73, Parent = win })
	local footer = create("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0, 24, 1, -64), Size = UDim2.new(1, -48, 0, 64), ZIndex = 73, Parent = win }, {
		list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center),
	})
	local function close()
		self._studioOpen = false
		tween(layer, FOLD, { BackgroundTransparency = 1 })
		-- Keep the responsive modal position during its fade.
		tween(win, FOLD, { GroupTransparency = 1 }).Completed:Wait()
		layer:Destroy()
	end
	local function button(label: string, primary: boolean, order: number, fn)
		local b = create("TextButton", {
			BackgroundColor3 = primary and themeColor(theme, "Accent") or themeColor(theme, "Tile"),
			Size = UDim2.fromOffset(0, 32),
			AutomaticSize = Enum.AutomaticSize.X,
			Text = label,
			FontFace = inter(Enum.FontWeight.Medium),
			TextSize = 13,
			TextColor3 = primary and themeColor(theme, "AccentText") or themeColor(theme, "Text"),
			AutoButtonColor = false,
			LayoutOrder = order,
			ZIndex = 74,
			Parent = footer,
		}, { corner(8), padding(0, 16) })
		if not primary then
			stroke(themeColor(theme, "TileStroke")).Parent = b
		end
		b.MouseButton1Click:Connect(fn)
	end
	button("Reset", false, 1, function()
		draft.ThemeName = "Graphite"
		draft.Accent = DefaultTheme.Accent
		draft.Background = nil
		for k, v in PLACEMENTS.Full do
			draft[k] = v
		end
		fitControl:Set("Fill", true)
		syncFree()
		accentChanged = false
		accentPicker:Set(DefaultTheme.Accent, true)
		status.Text = "Reset to Graphite with no image. Save to keep it."
		setThemed(status, "TextColor3", themeColor(theme, "SubText"))
		drawPreview()
	end)
	button("Cancel", false, 2, function()
		self:_transitionTheme(originalName, originalTheme)
		close()
	end)
	button("Save", true, 3, function()
		local colors = {}
		if accentChanged then
			colors.Accent = draft.Accent:ToHex()
			colors.AccentText = accentTextFor(draft.Accent)
		end
		self.Background = draft.Background and {
			File = draft.Background.File,
			Aspect = draft.Background.Aspect or 1,
			Url = draft.Background.Url,
			Opacity = draft.Opacity,
			Dim = draft.Dim,
			Fit = draft.Fit,
			Anchor = draft.Anchor,
			Scale = draft.Scale,
			OffsetX = draft.OffsetX,
			OffsetY = draft.OffsetY,
			Rotation = draft.Rotation,
			Dock = draft.Dock,
		} or nil
		self.ThemeName = draft.ThemeName
		self.Options.ThemeName = draft.ThemeName
		if self._themeControl then self._themeControl:Set(draft.ThemeName, true) end
		self:_saveStudio(colors)
		self:_applyBackground()
		close()
		local hub = RiftUI.Hubs[#RiftUI.Hubs]
		if hub then
			hub:Notify({ Title = "Theme saved", Content = draft.ThemeName .. (draft.Background and " with a background image" or ""), Icon = "palette", Duration = 3 })
		end
	end)

	tween(layer, SOFT, { BackgroundTransparency = 0.5 })
	-- Keep the modal anchored to its available viewport.
	tween(win, SOFT, { GroupTransparency = 0 })
	status.Text = draft.Background and ("Current image: " .. draft.Background.File) or "No background image."
	drawPreview()
end

---------------------------------------------------------------- built-in settings tab
function Hub:_buildSettings()
	task.defer(function()
		if self._destroyed then
			return
		end
		local tab = self:Tab({ Name = "Settings", Icon = "settings", Description = "Toolbar, configs and about", _internal = true, _order = 1000 })
		self.SettingsTab = tab
		create("Frame", {
			Name = "Separator",
			BackgroundColor3 = self.Theme.TileStroke,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(1, 24),
			LayoutOrder = 900,
			Parent = self.Dock,
		})

		local ui = tab:Section({ Name = "Interface", Side = "Left" })
		local key = ui:Keybind({
			Name = "Toolbar key",
			Default = self.ToggleKey,
			Mode = "None", -- the hub itself listens for the toolbar key
			ChangedCallback = function(k)
				if k then
					self.ToggleKey = k
				end
			end,
		})
		self._toggleKeyControl = key
		self._commandKeyControl = ui:Keybind({
			Name = "Command palette key", Default = self.CommandKey, Mode = "None",
			ChangedCallback = function(k)
				if k then self:SetCommandKey(k) end
				self._commandKeyControl:Set(self.CommandKey, true)
			end,
		})
		self._scaleControl = ui:Slider({
			Name = "Interface scale",
			Min = 70,
			Max = 140,
			Step = 5,
			Default = math.floor(self._scale * 100 + 0.5),
			Suffix = "%",
			Callback = function(v)
				self:SetScale(v / 100)
			end,
		})
		local themeNames = {}
		for _, t in THEMES do
			table.insert(themeNames, t.Name)
		end
		self._themeControl = ui:Dropdown({
			Name = "Theme",
			Options = themeNames,
			Default = self.ThemeName,
			Callback = function(name)
				if name ~= self.ThemeName then
					self:SetTheme(name)
				end
			end,
		})
		ui:Button({
			Name = "Open theme studio",
			Callback = function()
				self:Close()
				self:OpenThemeStudio()
			end,
		})
		if self._stealthLocked then
			self._stealthStatus = ui:_info("Stealth mode", self.Stealth and "Script: On" or "Script: Off")
			ui:Paragraph({ Content = "Stealth mode is controlled by this script." })
		else
			self._stealthControl = ui:Toggle({
				Name = "Stealth mode",
				Description = "Local assets only, built-in font fallback, quiet library output",
				Default = self.Stealth,
				Callback = function(on) self:SetStealth(on) end,
			})
		end
		self._watermarkControl = ui:Toggle({
			Name = "Watermark",
			Description = "Hub name, FPS, ping and time",
			Default = self._watermark ~= nil,
			Callback = function(on) self:SetWatermark(on) end,
		})
		self._keylistControl = ui:Toggle({
			Name = "Keybind list",
			Description = "Bound keys and their state",
			Default = self._keylist ~= nil,
			Callback = function(on) self:SetKeybindList(on) end,
		})
		local languageNames, codeFor = {}, {}
		for _, code in self:Languages() do
			local label = RiftUI.LanguageNames[code] or code
			table.insert(languageNames, label)
			codeFor[label] = code
		end
		if #languageNames > 1 then
			self._languageControl = ui:Dropdown({
				Name = "Language",
				Options = languageNames,
				Default = RiftUI.LanguageNames[self.Language or "en"] or self.Language or "English",
				Callback = function(label) self:SetLanguage(codeFor[label] or "en") end,
			})
		end

		if next(self._requirements) then
			local section = tab:Section({ Name = "Feature requirements", Side = "Right" })
			local fields = {}
			local ids = {}
			for id in self._requirements do table.insert(ids, id) end
			table.sort(ids)
			for _, id in ids do fields[id] = section:_info(self._requirements[id].Name, "Checking…") end
			local function refresh(results)
				for id, field in fields do
					local result = results[id]
					field:Set(result.Passed and "Available" or result.Status == "pending" and "Checking…" or "Unavailable")
				end
			end
			self:OnRequirementsChanged(refresh)
			refresh(self._requirementResults)
			section:Button({ Name = "Recheck feature requirements", Callback = function() self:RunRequirements() end })
		end

		local cfg = tab:Section({ Name = "Config", Side = "Right" })
		local nameBox = cfg:Input({ Name = "Config name", Placeholder = "e.g. legit", Default = "default" })
		cfg:Button({
			Name = "Save",
			Callback = function()
				local ok, err = self:SaveConfig(nameBox.Value)
				self:Notify(ok and { Title = "Config saved", Content = nameBox.Value, Duration = 3 } or { Title = "Couldn't save", Content = err, Tone = self.Theme.Danger })
			end,
		})
		local pick = cfg:Dropdown({ Name = "Saved", Options = self:ListConfigs(), Default = nil })
		cfg:Button({
			Name = "Load selected",
			Callback = function()
				local name = pick.Value or nameBox.Value
				local ok, err = self:LoadConfig(name)
				self:Notify(ok and { Title = "Config loaded", Content = tostring(name), Duration = 3 } or { Title = "Couldn't load", Content = err, Tone = self.Theme.Danger })
			end,
		})
		-- autoload has its own picker, so browsing Saved never changes what loads on start
		local autoToggle = cfg:Toggle({
			Name = "Autoload a config",
			Description = "Loads on start, before the toolbar shows",
			Default = self:GetAutoload() ~= nil,
		})
		local autoPick = cfg:Dropdown({
			Name = "Autoload config",
			Options = self:ListConfigs(),
			Default = self:GetAutoload(),
		})
		-- Default-on controls can emit during construction. Bind cross-control callbacks
		-- only after both controls exist; their initial state is synchronized below.
		autoToggle.Callback = function(on)
			autoPick:SetVisible(on)
			if not on then
				self:SetAutoload(nil)
			elseif autoPick.Value then
				self:SetAutoload(autoPick.Value)
			end
		end
		autoPick.Callback = function(name)
			if autoToggle.Value and name then
				self:SetAutoload(name)
				self:Notify({ Title = "Autoload set", Content = tostring(name) .. " loads when the hub starts.", Duration = 3 })
			end
		end
		autoPick:SetVisible(autoToggle.Value)
		local manager = self:_buildConfigManager()
		cfg:Button({ Name = "Manage configs", Window = manager })
		self:_watchConfigs(function()
			local names = self:ListConfigs()
			local current = pick.Value
			pick:SetOptions(names)
			if current and table.find(names, current) then pick:Set(current, true) end
			local auto = self:GetAutoload()
			autoPick:SetOptions(names)
			if auto then autoPick:Set(auto, true) end
			-- an autoload cleared elsewhere (deleted config) turns the toggle off; picking one turns it on
			if (auto ~= nil) ~= autoToggle.Value and (auto ~= nil or autoPick.Value == nil or not table.find(names, autoPick.Value)) then
				autoToggle:Set(auto ~= nil, true)
				autoPick:SetVisible(auto ~= nil)
			end
		end)

		local about = tab:Section({ Name = "About", Side = "Left" })
		about:Paragraph({ Content = "This script is powered by RiftUI. Licensed under MPL-2.0" })
		about:Button({ Name = "Copy GitHub link", Description = "github.com/Naymmmm/riftui", Callback = function()
			if typeof(setclipboard) == "function" then
				setclipboard("https://github.com/Naymmmm/riftui")
				self:Notify({ Title = "Link copied", Content = "github.com/Naymmmm/riftui", Icon = "check", Duration = 2 })
			else
				self:Notify({ Title = "GitHub", Content = "https://github.com/Naymmmm/riftui", Duration = 6 })
			end
		end })
		-- Developer Mode hides behind six taps on the version, like Android's build number
		local taps, lastTap = 0, 0
		local versionRow
		versionRow = about:_info("Version", RiftUI.Version, function()
			if RiftUI.DeveloperMode then
				self:Notify({ Title = "Developer Mode is on", Content = "Find it in the Developer tab.", Icon = "bug", Duration = 2, Force = true })
				self:Open(self.DeveloperTab)
				return
			end
			local now = os.clock()
			taps = (now - lastTap < 1.5) and taps + 1 or 1
			lastTap = now
			if taps < 6 then
				if taps >= 3 then
					-- count down in place of the version, then quietly put it back
					local left = 6 - taps
					versionRow:Set(left .. (left == 1 and " tap left" or " taps left"))
					task.delay(1.5, function()
						if os.clock() - lastTap >= 1.45 then
							versionRow:Set(RiftUI.Version)
						end
					end)
				end
				return
			end
			taps = 0
			versionRow:Set(RiftUI.Version)
			self:Prompt({
				Icon = "bug",
				Title = "Enable Developer Mode?",
				Content = "Adds a Developer tab with the hub's state machine, every captured error and tools like Reinitialize. It's meant for hub authors and stays on until you turn it off.",
				Buttons = {
					{ Text = "Cancel" },
					{
						Text = "Enable",
						Primary = true,
						Callback = function()
							RiftUI:SetDeveloperMode(true)
							task.wait(0.15)
							self:Open(self.DeveloperTab)
						end,
					},
				},
			})
		end)
		local executor = typeof(identifyexecutor) == "function" and select(1, identifyexecutor()) or "Unknown"
		about:_info("Executor", tostring(executor))
		about:_info("Hub ID", self.Id)
		about:Button({
			Name = "Run setup again",
			Callback = function()
				self:Close()
				self:OpenSetup()
			end,
		})
		about:Button({
			Name = "Unload hub",
			Danger = true,
			Callback = function()
				self:Destroy()
			end,
		})
	end)
end

---------------------------------------------------------------- reinitialize & teardown
function Hub:_teardown()
	for _, tw in self._themeTweens or {} do tw:Cancel() end
	self._themeTweens = nil
	self._destroyed = true
	secureHubs[self] = nil
	for _, thread in self._requirementThreads or {} do pcall(task.cancel, thread) end
	self._requirementWatchers = {}
	if self._watermark then
		for _, conn in self._watermark.Conns do conn:Disconnect() end
	end
	self:CloseCommandPalette(true)
	self:_closePopup()
	for _, c in self._conns do
		c:Disconnect()
	end
	if self._stealthConn then
		self._stealthConn:Disconnect()
	end
	for _, tab in self.Tabs do
		if tab._stateConn then
			tab._stateConn:Disconnect()
		end
		for _, section in tab.Sections do
			for _, c in section._pinConns or {} do
				c:Disconnect()
			end
			for _, control in section.Controls do
				if control.Flag and RiftUI.Flags[control.Flag] == control then
					RiftUI.Flags[control.Flag] = nil
				end
			end
		end
	end
	self.Gui:Destroy()
	local i = table.find(RiftUI.Hubs, self)
	if i then
		table.remove(RiftUI.Hubs, i)
	end
end

--[[
	Rebuilds the hub from the calls that created it, keeps every flag's value and pin, and
	turns the old Hub/Tab/Section/control tables into forwarders so references the hub
	script still holds keep working.
]]
function Hub:Reinitialize()
	setState("Reinitializing", self.Name)
	local quiet = self._quietReinit
	self._quietReinit = nil
	local values = self:_flagValues()
	local pins = table.clone(self.Pins)
	local recipe = self._recipe
	local stealth = self.Stealth
	local scale = self._scale
	local toggleKey = self.ToggleKey
	local commandKey = self.CommandKey
	local configEncryption, encryptConfigs, configServer = self._configEncryption, self._encryptConfigs, self._configServer
	local wasOpen = self._open and self._open.Name
	self:_teardown()
	if failureGui then
		failureGui:Destroy()
		failureGui = nil
	end
	local ok, err = xpcall(function()
		local rebuildOptions = table.clone(self.Options)
		rebuildOptions.Stealth = stealth
		rebuildOptions.Loading = nil
		local fresh = RiftUI:CreateHub(rebuildOptions)
		fresh._stealthLocked = self._stealthLocked
		fresh._replaying = true
		fresh.ToggleKey = toggleKey
		fresh.CommandKey = commandKey
		fresh._configEncryption, fresh._encryptConfigs, fresh._configServer = configEncryption, encryptConfigs, configServer
		fresh:SetScale(scale)
		local map = { [self] = fresh }
		for _, step in recipe do
			local target = map[step.Target]
			if target then
				map[step.Result] = target[step.Method](target, step.Args)
			end
		end
		fresh._replaying = false
		local rebuilt = {}
		for _, step in recipe do
			table.insert(rebuilt, {
				Target = map[step.Target] or step.Target,
				Method = step.Method,
				Args = step.Args,
				Result = map[step.Result] or step.Result,
			})
		end
		fresh._recipe = rebuilt
		for flag, saved in values do
			local control = RiftUI.Flags[flag]
			if control then
				if #control.Requires > 0 and not control:IsAvailable() then
					control._requirementRestore = saved
				else pcall(decodeValue, control, saved, true) end
			end
		end
		for _, tab in fresh.Tabs do
			tab:_recount()
			for _, section in tab.Sections do
				if pins[section.Id] then
					section:Pin(pins[section.Id])
				end
			end
		end
		if stealth then
			fresh:SetStealth(true)
		end
		for old, new in map do
			if old ~= new then
				table.clear(old)
				setmetatable(old, { __index = new, __newindex = new })
			end
		end
		if not quiet then
			fresh:Notify({ Title = "Hub reinitialized", Content = #recipe .. " elements rebuilt, values kept.", Duration = 3 })
		end
		if wasOpen then
			task.wait(0.1)
			fresh:Open(wasOpen)
		end
	end, debug.traceback)
	if not ok then
		recordError(tostring(err), nil, "reinitialize")
		setState("Failed", "reinitialize")
		task.defer(showFailure, tostring(err), nil)
	end
end

function Hub:Destroy()
	self:_teardown()
	setState("Unloaded", self.Name)
end

return RiftUI
