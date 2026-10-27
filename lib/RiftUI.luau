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
	Version = "0.2.0",
	Flags = {},
	AssetBase = "https://raw.githubusercontent.com/YOUR_GITHUB/riftui/main/public/",
	Folder = "RiftUI",
	State = "Idle",
	StateHistory = {},
	Errors = {},
	Hubs = {},
	DeveloperMode = false,
}

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
	return Font.new(FONT_ID, weight or Enum.FontWeight.Regular)
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
	return result
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
	if string.find(name, "^rbxasset") then
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
		Theme = theme,
		ThemeName = themeName,
		ToggleKey = toggleKey,
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

	self:_bindInput()
	if options.Settings ~= false then
		self:_buildSettings()
	end
	table.insert(RiftUI.Hubs, self)
	registry[id] = self
	self:_registerSetupFlags()
	setState("Building", self.Name)
	task.defer(function()
		if self._destroyed then
			return
		end
		if options.Setup ~= false and not (saved and saved.Completed) and not self._replaying then
			task.delay(0.35, function()
				if not self._destroyed then
					self:OpenSetup()
				end
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
		self:_autoload()
		if RiftUI.State == "Building" or RiftUI.State == "Reinitializing" then
			setState("Ready", self.Name)
		end
	end)
	return self
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
		tween(self.PanelHolder, SETTLE, { Size = goalSize, Position = goalPos })
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
	tween(holder, RISE, { Position = goal })
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
	tween(holder, FOLD, { Position = holder.Position + UDim2.fromOffset(self:_tileOffset(tab) * 0.5, 14) })
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
	if self.Stealth and not options.Force then
		self._suppressed = (self._suppressed or 0) + 1
		return
	end
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
	if self.Stealth == on then
		return
	end
	self.Stealth = on
	if on then
		self._realNames = {}
		local function hide(inst)
			if self._realNames[inst] == nil then
				self._realNames[inst] = inst.Name
				inst.Name = randomName()
			end
		end
		hide(self.Gui)
		for _, d in self.Gui:GetDescendants() do
			hide(d)
		end
		self._stealthConn = self.Gui.DescendantAdded:Connect(hide)
		self:SetToolbarVisible(false, true)
	else
		if self._stealthConn then
			self._stealthConn:Disconnect()
			self._stealthConn = nil
		end
		for inst, name in self._realNames or {} do
			if inst.Parent or inst == self.Gui then
				inst.Name = name
			end
		end
		self._realNames = nil
	end
	if self._stealthControl then
		self._stealthControl:Set(on, true)
	end
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
	self.Badge.Visible = n > 0
	self.BadgeText.Text = tostring(n)
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
	local titleChip = create("Frame", {
		Name = "Title",
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		ZIndex = 2,
		Parent = head,
	}, { padding(0, 8, 0, 0), create("UISizeConstraint", { MaxSize = Vector2.new(180, 26) }) })
	text({
		Parent = titleChip,
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
	local rows = create("Frame", {
		Name = "Rows",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = frame,
	}, { list(Enum.FillDirection.Vertical, 0), padding(0, 1) })
	section.Frame = frame
	section.Head = head
	section.Rows = rows

	table.insert(self.Sections, section)
	hub:_record(self, "Section", options, section)
	return section
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
	}
	function control:OnChanged(fn)
		table.insert(self._changed, fn)
		return self
	end
	function control:SetVisible(v: boolean)
		self._hidden = not v
		self.Frame.Visible = v
	end
	function control:_emit(...)
		local args = table.pack(...)
		task.spawn(function()
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
			task.spawn(fn, ...)
		end
	end
	if control.Flag then
		RiftUI.Flags[control.Flag] = control
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
		c:_emit(true)
	end
	return c
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
	hub:_connect(btn.MouseButton1Click, function()
		c:_emit()
	end)
	function c:SetText(t: string)
		btn.Text = t
		self.Name = t
	end
	return c
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
	return c
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
	return c
end

---------------------------------------------------------------- Input
function Section:Input(options)
	local hub, theme = self.Hub, self.Hub.Theme
	local row = self:_row(58, "Input_" .. (options.Name or ""))
	local c = self:_control("Input", options, row)
	c.Value = options.Default or ""
	text({ Parent = row, Name = "Title", Text = c.Name, TextSize = 13, Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 16) })
	local box = create("TextBox", {
		Name = "Box",
		BackgroundColor3 = themeColor(theme, "Field"),
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 0, 26),
		FontFace = options.Numeric and MONO or inter(),
		TextSize = 13,
		TextColor3 = themeColor(theme, "Text"),
		PlaceholderText = options.Placeholder or "",
		PlaceholderColor3 = themeColor(theme, "Muted"),
		Text = c.Value,
		ClearTextOnFocus = options.ClearOnFocus == true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	}, { corner(6), padding(0, 8) })
	local boxStroke = stroke(themeColor(theme, "FieldStroke"))
	boxStroke.Parent = box
	function c:Set(value: string, silent: boolean?)
		value = tostring(value or "")
		if options.Numeric then
			value = string.gsub(value, "[^%d%.%-]", "")
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
	return c
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
	self:_labels(row, c.Name, options.Description, 90)
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
	end)
	hub:_connect(UserInputService.InputEnded, function(input)
		if c.Mode == "Hold" and c.State and matches(input) then
			c.State = false
			c:_emit(false)
		end
	end)
	return c
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
	return c
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
	return c
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
	local title = text({ Parent = holder, Text = options.Title or "", TextSize = 13, FontFace = inter(Enum.FontWeight.Medium), Size = UDim2.new(1, 0, 0, 16) })
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
		end
		if content then
			body.Text = content
		end
	end
	return c
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
	return c
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
	self.Rows.Parent = self.Frame
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
	elseif data.Value ~= nil and control.Set then
		control:Set(data.Value, silent)
	end
end

local SAVABLE = { Toggle = true, Slider = true, Dropdown = true, Input = true, Keybind = true, ColorPicker = true }

function Hub:_dir(): string
	return RiftUI.Folder .. "/" .. self.Id
end

function Hub:_configDir(): string
	return self:_dir() .. "/configs"
end

function Hub:_flagValues()
	local out = {}
	for flag, control in RiftUI.Flags do
		if control.Section and control.Section.Hub == self and SAVABLE[control.Type] and not control._internal then
			out[flag] = encodeValue(control)
		end
	end
	return out
end

function Hub:SaveConfig(name: string): (boolean, string?)
	if not hasFS then
		return false, "this executor has no file functions"
	end
	name = tostring(name or "default")
	if not string.match(name, "^[%w%s%-_]+$") then
		return false, "use letters, numbers, spaces, - or _"
	end
	local data = { Flags = self:_flagValues(), Pins = {}, ToggleKey = self.ToggleKey.Name, Scale = self._scale }
	for id, pos in self.Pins do
		data.Pins[id] = { pos.X, pos.Y }
	end
	ensureFolder(RiftUI.Folder)
	ensureFolder(self:_dir())
	ensureFolder(self:_configDir())
	writefile(self:_configDir() .. "/" .. name .. ".json", HttpService:JSONEncode(data))
	return true
end

function Hub:LoadConfig(name: string): (boolean, string?)
	if not hasFS then
		return false, "this executor has no file functions"
	end
	local path = self:_configDir() .. "/" .. tostring(name) .. ".json"
	if not isfile(path) then
		return false, "no config named " .. tostring(name)
	end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(readfile(path))
	end)
	if not ok or type(data) ~= "table" then
		return false, "config file is damaged"
	end
	for flag, saved in data.Flags or {} do
		local control = RiftUI.Flags[flag]
		if control and control.Section and control.Section.Hub == self then
			pcall(decodeValue, control, saved)
		end
	end
	if data.ToggleKey then
		local okKey, key = pcall(function()
			return Enum.KeyCode[data.ToggleKey]
		end)
		if okKey and key then
			self.ToggleKey = key
			if self._toggleKeyControl then
				self._toggleKeyControl:Set(key, true)
			end
		end
	end
	if type(data.Scale) == "number" then
		self:SetScale(data.Scale)
		if self._scaleControl then
			self._scaleControl:Set(math.floor(data.Scale * 100 + 0.5), true)
		end
	end
	for _, tab in self.Tabs do
		for _, section in tab.Sections do
			local p = data.Pins and data.Pins[section.Id]
			if p then
				section:Unpin()
				section:Pin(Vector2.new(p[1], p[2]))
			elseif section.Pinned then
				section:Unpin()
			end
		end
	end
	return true
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

function Hub:DeleteConfig(name: string)
	local path = self:_configDir() .. "/" .. tostring(name) .. ".json"
	if hasFS and typeof(delfile) == "function" and isfile(path) then
		delfile(path)
	end
end

function Hub:SetAutoload(name: string?)
	if not hasFS then
		return
	end
	ensureFolder(RiftUI.Folder)
	ensureFolder(self:_dir())
	ensureFolder(self:_configDir())
	writefile(self:_configDir() .. "/autoload.txt", name or "")
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
	return {
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
			needs("getcustomasset")
			local id = getcustomasset(probe)
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
	layer.Destroying:Connect(function() conn:Disconnect() end)
	fit()
end

function Hub:OpenSetup()
	if self._setupOpen then
		return
	end
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
		local data = { Version = RiftUI.Version, Completed = true, Skipped = skipped or nil, Theme = choice.Theme, ToggleKey = choice.ToggleKey.Name, Options = {}, Time = os.time(), Studio = (self.SetupData or {}).Studio }
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
		self._stealthControl = ui:Toggle({
			Name = "Stealth mode",
			Description = "Random instance names, no notifications, toolbar starts hidden",
			Default = self.Stealth,
			Callback = function(on)
				self:SetStealth(on)
			end,
		})

		local cfg = tab:Section({ Name = "Config", Side = "Right" })
		local nameBox = cfg:Input({ Name = "Config name", Placeholder = "e.g. legit", Default = "default" })
		local pick = cfg:Dropdown({ Name = "Saved", Options = self:ListConfigs(), Default = nil })
		local function refresh()
			pick:SetOptions(self:ListConfigs())
		end
		cfg:Button({
			Name = "Save",
			Callback = function()
				local ok, err = self:SaveConfig(nameBox.Value)
				refresh()
				self:Notify(ok and { Title = "Config saved", Content = nameBox.Value, Duration = 3 } or { Title = "Couldn't save", Content = err, Tone = self.Theme.Danger })
			end,
		})
		cfg:Button({
			Name = "Load selected",
			Callback = function()
				local name = pick.Value or nameBox.Value
				local ok, err = self:LoadConfig(name)
				self:Notify(ok and { Title = "Config loaded", Content = tostring(name), Duration = 3 } or { Title = "Couldn't load", Content = err, Tone = self.Theme.Danger })
			end,
		})
		cfg:Button({
			Name = "Load on start",
			Callback = function()
				local name = pick.Value or nameBox.Value
				self:SetAutoload(name)
				self:Notify({ Title = "Autoload set", Content = tostring(name) .. " loads when the hub starts.", Duration = 3 })
			end,
		})

		local about = tab:Section({ Name = "RiftUI", Side = "Left" })
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
	local wasOpen = self._open and self._open.Name
	self:_teardown()
	if failureGui then
		failureGui:Destroy()
		failureGui = nil
	end
	local ok, err = xpcall(function()
		local fresh = RiftUI:CreateHub(self.Options)
		fresh._replaying = true
		fresh.ToggleKey = toggleKey
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
				pcall(decodeValue, control, saved, true)
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
