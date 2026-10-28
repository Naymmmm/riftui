-- GUI and container classes with Roblox's current defaults for Instance.new.

local defineClass = E.defineClass
local V2, C3, U2, U = E.V2, E.C3, E.UDim2, E.UDim
local D, setProp, emit, fireIf = E.D, E.setProp, E.emit, E.fireIf
local enums = E.enums
local SEP = "\31"

local function white()
	return C3(1, 1, 1)
end

defineClass("DataModel", "Instance", { alsoIsA = { "ServiceProvider" } })
defineClass("Folder", "Instance", { creatable = true })
defineClass("Configuration", "Instance", { creatable = true })
defineClass("Model", "Instance", { creatable = true, alsoIsA = { "PVInstance" } })
defineClass("Camera", "Instance", {
	props = {
		{ "ViewportSize", "Vector2", V2(1280, 720), "r" },
		{ "FieldOfView", "number", 70 },
		{ "CameraType", "Enum:CameraType", enums.CameraType.Custom },
	},
	methods = {
		ViewportPointToRay = function()
			return nil
		end,
		WorldToViewportPoint = function(_, p)
			return E.V3(0, 0, 0), false
		end,
		WorldToScreenPoint = function(_, p)
			return E.V3(0, 0, 0), false
		end,
	},
})

-- Value objects
for _, spec in
	{
		{ "StringValue", "string", "" },
		{ "BoolValue", "bool", false },
		{ "NumberValue", "number", 0 },
		{ "IntValue", "int", 0 },
		{ "Color3Value", "Color3", C3(0, 0, 0) },
		{ "ObjectValue", "Instance", nil },
		{ "Vector3Value", "Vector3", E.V3(0, 0, 0) },
	}
do
	defineClass(spec[1], "Instance", {
		creatable = true,
		alsoIsA = { "ValueBase" },
		props = { { "Value", spec[2], spec[3] } },
		onSet = {
			Value = function(inst, d, v)
				task.defer(function()
					fireIf(d, "ValueChanged", v)
				end)
				return v
			end,
		},
		events = { "ValueChanged" },
	})
end

defineClass("BindableEvent", "Instance", {
	creatable = true,
	events = { "Event" },
	methods = {
		Fire = function(self, ...)
			fireIf(D[self], "Event", ...)
		end,
	},
})
defineClass("BindableFunction", "Instance", {
	creatable = true,
	props = { { "OnInvoke", "any", nil, "h" } },
	methods = {
		Invoke = function(self, ...)
			local f = D[self].props.OnInvoke
			if not f then
				error("BindableFunction has no OnInvoke callback", 2)
			end
			return f(...)
		end,
	},
})

---------------------------------------------------------------- GUI base
defineClass("GuiBase", "Instance", {})
defineClass("GuiBase2d", "GuiBase", {
	props = {
		{ "AbsolutePosition", "Vector2", V2(0, 0), "r" },
		{ "AbsoluteSize", "Vector2", V2(0, 0), "r" },
		{ "AbsoluteRotation", "number", 0, "r" },
		{ "AutoLocalize", "bool", true },
		{ "SelectionGroup", "bool", false },
	},
})
defineClass("LayerCollector", "GuiBase2d", {
	props = {
		{ "Enabled", "bool", true },
		{ "ResetOnSpawn", "bool", true },
		{ "ZIndexBehavior", "Enum:ZIndexBehavior", enums.ZIndexBehavior.Sibling },
	},
})
defineClass("ScreenGui", "LayerCollector", {
	creatable = true,
	props = {
		{ "DisplayOrder", "int", 0 },
		{ "IgnoreGuiInset", "bool", false },
		{ "ScreenInsets", "Enum:ScreenInsets", enums.ScreenInsets.CoreUISafeInsets },
		{ "ClipToDeviceSafeArea", "bool", true },
		{ "SafeAreaCompatibility", "Enum:SafeAreaCompatibility", enums.SafeAreaCompatibility.FullscreenExtension },
	},
})

local function fontSync()
	return {
		Font = function(inst, d, item)
			local f = E.fontFromEnum(item)
			if d.props.FontFace ~= f then
				d.props.FontFace = f
				emit("p" .. SEP .. d.id .. SEP .. "FontFace" .. SEP .. E.encode(f))
				E.propChanged(d, "FontFace")
			end
			return item
		end,
		FontFace = function(inst, d, f)
			local item = E.enumFromFont(f)
			if d.props.Font ~= item then
				d.props.Font = item
				emit("p" .. SEP .. d.id .. SEP .. "Font" .. SEP .. E.encode(item))
				E.propChanged(d, "Font")
			end
			return f
		end,
		Text = function(inst, d, t)
			return t
		end,
	}
end

local guiEvents = {
	"InputBegan",
	"InputChanged",
	"InputEnded",
	"MouseEnter",
	"MouseLeave",
	"MouseMoved",
	"MouseWheelForward",
	"MouseWheelBackward",
	"SelectionGained",
	"SelectionLost",
	"TouchTap",
	"TouchLongPress",
	"TouchPan",
	"TouchPinch",
	"TouchRotate",
	"TouchSwipe",
}

local function legacyTween(prop)
	return function(self, goal, dir, style, time, override, callback)
		local info = TweenInfo.new(time or 1, style or enums.EasingStyle.Quad, dir or enums.EasingDirection.Out)
		local goals = {}
		if prop == "Both" then
			goals.Size = goal
			goals.Position = dir
			info = TweenInfo.new(callback == nil and (override or 1) or override, time or enums.EasingStyle.Quad, style or enums.EasingDirection.Out)
		else
			goals[prop] = goal
		end
		local tw = E.TweenService:Create(self, info, goals)
		if callback then
			tw.Completed:Connect(function(state)
				callback(state)
			end)
		end
		tw:Play()
		return true
	end
end

defineClass("GuiObject", "GuiBase2d", {
	props = {
		{ "Active", "bool", false },
		{ "AnchorPoint", "Vector2", V2(0, 0) },
		{ "AutomaticSize", "Enum:AutomaticSize", enums.AutomaticSize.None },
		{ "BackgroundColor3", "Color3", white },
		{ "BackgroundTransparency", "number", 0 },
		{ "BorderColor3", "Color3", function()
			return C3(27 / 255, 42 / 255, 53 / 255)
		end },
		{ "BorderMode", "Enum:BorderMode", enums.BorderMode.Outline },
		{ "BorderSizePixel", "int", 0 },
		{ "ClipsDescendants", "bool", false },
		{ "Interactable", "bool", true },
		{ "LayoutOrder", "int", 0 },
		{ "Position", "UDim2", function()
			return U2(0, 0, 0, 0)
		end },
		{ "Rotation", "number", 0 },
		{ "Selectable", "bool", false },
		{ "SelectionOrder", "int", 0 },
		{ "Size", "UDim2", function()
			return U2(0, 100, 0, 100)
		end },
		{ "SizeConstraint", "Enum:SizeConstraint", enums.SizeConstraint.RelativeXY },
		{ "Transparency", "number", 0, "h" },
		{ "Visible", "bool", true },
		{ "ZIndex", "int", 1 },
		{ "GuiState", "string", "Idle", "r" },
	},
	events = guiEvents,
	onSet = {
		Transparency = function(inst, d, v)
			setProp(inst, "BackgroundTransparency", v, true)
			return v
		end,
	},
	methods = {
		TweenPosition = legacyTween("Position"),
		TweenSize = legacyTween("Size"),
		TweenSizeAndPosition = legacyTween("Both"),
	},
})

defineClass("Frame", "GuiObject", {
	creatable = true,
	props = { { "Style", "Enum:FrameStyle", enums.FrameStyle.Custom } },
})
defineClass("CanvasGroup", "GuiObject", {
	creatable = true,
	props = {
		{ "GroupTransparency", "number", 0 },
		{ "GroupColor3", "Color3", white },
	},
})

local textProps = {
	{ "Font", "Enum:Font", enums.Font.BuilderSans },
	{ "FontFace", "Font", function()
		return E.fontFromEnum(enums.Font.BuilderSans)
	end },
	{ "LineHeight", "number", 1 },
	{ "MaxVisibleGraphemes", "int", -1 },
	{ "RichText", "bool", false },
	{ "Text", "string", "Label" },
	{ "TextBounds", "Vector2", V2(0, 0), "r" },
	{ "TextColor3", "Color3", function()
		return C3(0, 0, 0)
	end },
	{ "TextDirection", "Enum:TextDirection", enums.TextDirection.Auto },
	{ "TextFits", "bool", true, "r" },
	{ "TextScaled", "bool", false },
	{ "TextSize", "number", 14 },
	{ "TextStrokeColor3", "Color3", function()
		return C3(0, 0, 0)
	end },
	{ "TextStrokeTransparency", "number", 1 },
	{ "TextTransparency", "number", 0 },
	{ "TextTruncate", "Enum:TextTruncate", enums.TextTruncate.None },
	{ "TextWrapped", "bool", false },
	{ "TextXAlignment", "Enum:TextXAlignment", enums.TextXAlignment.Center },
	{ "TextYAlignment", "Enum:TextYAlignment", enums.TextYAlignment.Center },
	{ "ContentText", "string", "Label", "r" },
}

local function textOnSet()
	local s = fontSync()
	s.Text = function(inst, d, t)
		if d.props.ContentText ~= t then
			local content = d.props.RichText and string.gsub(t, "<[^>]->", "") or t
			d.props.ContentText = content
		end
		return t
	end
	return s
end

defineClass("TextLabel", "GuiObject", { creatable = true, props = textProps, onSet = textOnSet() })

defineClass("GuiButton", "GuiObject", {
	props = {
		{ "AutoButtonColor", "bool", true },
		{ "Modal", "bool", false },
		{ "Selected", "bool", false },
		{ "Style", "Enum:ButtonStyle", enums.ButtonStyle.Custom },
		{ "Active", "bool", true },
		{ "Selectable", "bool", true },
	},
	events = {
		"Activated",
		"MouseButton1Click",
		"MouseButton1Down",
		"MouseButton1Up",
		"MouseButton2Click",
		"MouseButton2Down",
		"MouseButton2Up",
	},
})
defineClass("TextButton", "GuiButton", {
	creatable = true,
	props = (function()
		local p = table.clone(textProps)
		for i, v in p do
			if v[1] == "Text" then
				p[i] = { "Text", "string", "Button" }
			elseif v[1] == "ContentText" then
				p[i] = { "ContentText", "string", "Button", "r" }
			end
		end
		return p
	end)(),
	onSet = textOnSet(),
})

local imageProps = {
	{ "Image", "Content", "" },
	{ "ImageColor3", "Color3", white },
	{ "ImageRectOffset", "Vector2", V2(0, 0) },
	{ "ImageRectSize", "Vector2", V2(0, 0) },
	{ "ImageTransparency", "number", 0 },
	{ "IsLoaded", "bool", true, "r" },
	{ "ResampleMode", "Enum:ResamplerMode", enums.ResamplerMode.Default },
	{ "ScaleType", "Enum:ScaleType", enums.ScaleType.Stretch },
	{ "SliceCenter", "Rect", function()
		return E.Rect(0, 0, 0, 0)
	end },
	{ "SliceScale", "number", 1 },
	{ "TileSize", "UDim2", function()
		return U2(1, 0, 1, 0)
	end },
}
defineClass("ImageLabel", "GuiObject", { creatable = true, props = imageProps })
defineClass("ImageButton", "GuiButton", {
	creatable = true,
	props = (function()
		local p = table.clone(imageProps)
		table.insert(p, { "HoverImage", "Content", "" })
		table.insert(p, { "PressedImage", "Content", "" })
		return p
	end)(),
})

defineClass("TextBox", "GuiObject", {
	creatable = true,
	props = (function()
		local p = table.clone(textProps)
		for i, v in p do
			if v[1] == "Text" then
				p[i] = { "Text", "string", "TextBox" }
			elseif v[1] == "ContentText" then
				p[i] = { "ContentText", "string", "TextBox", "r" }
			end
		end
		table.insert(p, { "ClearTextOnFocus", "bool", true })
		table.insert(p, { "CursorPosition", "int", 1 })
		table.insert(p, { "MultiLine", "bool", false })
		table.insert(p, { "PlaceholderColor3", "Color3", function()
			return C3(178 / 255, 178 / 255, 178 / 255)
		end })
		table.insert(p, { "PlaceholderText", "string", "" })
		table.insert(p, { "SelectionStart", "int", -1 })
		table.insert(p, { "ShowNativeInput", "bool", true })
		table.insert(p, { "TextEditable", "bool", true })
		table.insert(p, { "TextInputType", "Enum:TextInputType", enums.TextInputType.Default })
		table.insert(p, { "Active", "bool", true })
		table.insert(p, { "Selectable", "bool", true })
		return p
	end)(),
	onSet = textOnSet(),
	events = { "FocusLost", "Focused", "ReturnPressedFromOnScreenKeyboard" },
	methods = {
		CaptureFocus = function(self)
			emit("f" .. SEP .. D[self].id .. SEP .. "1")
		end,
		ReleaseFocus = function(self, submitted)
			emit("f" .. SEP .. D[self].id .. SEP .. (submitted and "2" or "0"))
		end,
		IsFocused = function(self)
			return E.focusedTextBox == self
		end,
	},
})

defineClass("ScrollingFrame", "GuiObject", {
	creatable = true,
	props = {
		{ "AbsoluteCanvasSize", "Vector2", V2(0, 0), "r" },
		{ "AbsoluteWindowSize", "Vector2", V2(0, 0), "r" },
		{ "AutomaticCanvasSize", "Enum:AutomaticSize", enums.AutomaticSize.None },
		{ "BottomImage", "Content", "rbxasset://textures/ui/Scroll/scroll-bottom.png" },
		{ "CanvasPosition", "Vector2", V2(0, 0) },
		{ "CanvasSize", "UDim2", function()
			return U2(0, 0, 2, 0)
		end },
		{ "ElasticBehavior", "Enum:ElasticBehavior", enums.ElasticBehavior.WhenScrollable },
		{ "HorizontalScrollBarInset", "Enum:ScrollBarInset", enums.ScrollBarInset.None },
		{ "MidImage", "Content", "rbxasset://textures/ui/Scroll/scroll-middle.png" },
		{ "ScrollBarImageColor3", "Color3", function()
			return C3(0, 0, 0)
		end },
		{ "ScrollBarImageTransparency", "number", 0 },
		{ "ScrollBarThickness", "int", 12 },
		{ "ScrollingDirection", "Enum:ScrollingDirection", enums.ScrollingDirection.XY },
		{ "ScrollingEnabled", "bool", true },
		{ "TopImage", "Content", "rbxasset://textures/ui/Scroll/scroll-top.png" },
		{ "VerticalScrollBarInset", "Enum:ScrollBarInset", enums.ScrollBarInset.None },
		{ "VerticalScrollBarPosition", "Enum:VerticalScrollBarPosition", enums.VerticalScrollBarPosition.Right },
		{ "Active", "bool", true },
		{ "ClipsDescendants", "bool", true },
		{ "Selectable", "bool", true },
	},
})

---------------------------------------------------------------- UI components
defineClass("UIBase", "Instance", {})
defineClass("UIComponent", "UIBase", {})
defineClass("UICorner", "UIComponent", {
	creatable = true,
	props = { { "CornerRadius", "UDim", function()
		return U(0, 8)
	end } },
})
defineClass("UIStroke", "UIComponent", {
	creatable = true,
	props = {
		{ "ApplyStrokeMode", "Enum:ApplyStrokeMode", enums.ApplyStrokeMode.Contextual },
		{ "Color", "Color3", function()
			return C3(0, 0, 0)
		end },
		{ "Enabled", "bool", true },
		{ "LineJoinMode", "Enum:LineJoinMode", enums.LineJoinMode.Round },
		{ "Thickness", "number", 1 },
		{ "Transparency", "number", 0 },
	},
})
defineClass("UIPadding", "UIComponent", {
	creatable = true,
	props = {
		{ "PaddingBottom", "UDim", function()
			return U(0, 0)
		end },
		{ "PaddingLeft", "UDim", function()
			return U(0, 0)
		end },
		{ "PaddingRight", "UDim", function()
			return U(0, 0)
		end },
		{ "PaddingTop", "UDim", function()
			return U(0, 0)
		end },
	},
})
defineClass("UIGradient", "UIComponent", {
	creatable = true,
	props = {
		{ "Color", "ColorSequence", function()
			return ColorSequence.new(C3(1, 1, 1))
		end },
		{ "Enabled", "bool", true },
		{ "Offset", "Vector2", V2(0, 0) },
		{ "Rotation", "number", 0 },
		{ "Transparency", "NumberSequence", function()
			return NumberSequence.new(0)
		end },
	},
})
defineClass("UIScale", "UIComponent", { creatable = true, props = { { "Scale", "number", 1 } } })
defineClass("UIConstraint", "UIComponent", {})
defineClass("UISizeConstraint", "UIConstraint", {
	creatable = true,
	props = {
		{ "MaxSize", "Vector2", V2(math.huge, math.huge) },
		{ "MinSize", "Vector2", V2(0, 0) },
	},
})
defineClass("UITextSizeConstraint", "UIConstraint", {
	creatable = true,
	props = {
		{ "MaxTextSize", "int", 100 },
		{ "MinTextSize", "int", 1 },
	},
})
defineClass("UIAspectRatioConstraint", "UIConstraint", {
	creatable = true,
	props = {
		{ "AspectRatio", "number", 1 },
		{ "AspectType", "Enum:AspectType", enums.AspectType.FitWithinMaxSize },
		{ "DominantAxis", "Enum:DominantAxis", enums.DominantAxis.Width },
	},
})
defineClass("UIFlexItem", "UIComponent", {
	creatable = true,
	props = {
		{ "FlexMode", "Enum:UIFlexMode", enums.UIFlexMode.None },
		{ "GrowRatio", "number", 0 },
		{ "ShrinkRatio", "number", 0 },
		{ "ItemLineAlignment", "Enum:ItemLineAlignment", enums.ItemLineAlignment.Automatic },
	},
})
defineClass("UILayout", "UIComponent", {})
defineClass("UIGridStyleLayout", "UILayout", {
	props = {
		{ "AbsoluteContentSize", "Vector2", V2(0, 0), "r" },
		{ "FillDirection", "Enum:FillDirection", enums.FillDirection.Horizontal },
		{ "HorizontalAlignment", "Enum:HorizontalAlignment", enums.HorizontalAlignment.Left },
		{ "SortOrder", "Enum:SortOrder", enums.SortOrder.LayoutOrder },
		{ "VerticalAlignment", "Enum:VerticalAlignment", enums.VerticalAlignment.Top },
	},
	methods = {
		ApplyLayout = function() end,
	},
})
defineClass("UIListLayout", "UIGridStyleLayout", {
	creatable = true,
	props = {
		{ "FillDirection", "Enum:FillDirection", enums.FillDirection.Vertical },
		{ "HorizontalFlex", "Enum:UIFlexAlignment", enums.UIFlexAlignment.None },
		{ "ItemLineAlignment", "Enum:ItemLineAlignment", enums.ItemLineAlignment.Automatic },
		{ "Padding", "UDim", function()
			return U(0, 0)
		end },
		{ "VerticalFlex", "Enum:UIFlexAlignment", enums.UIFlexAlignment.None },
		{ "Wraps", "bool", false },
	},
})
defineClass("UIGridLayout", "UIGridStyleLayout", {
	creatable = true,
	props = {
		{ "AbsoluteCellCount", "Vector2", V2(0, 0), "r" },
		{ "AbsoluteCellSize", "Vector2", V2(0, 0), "r" },
		{ "CellPadding", "UDim2", function()
			return U2(0, 5, 0, 5)
		end },
		{ "CellSize", "UDim2", function()
			return U2(0, 100, 0, 100)
		end },
		{ "FillDirectionMaxCells", "int", 0 },
		{ "StartCorner", "Enum:StartCorner", enums.StartCorner.TopLeft },
	},
})

---------------------------------------------------------------- Services and players
defineClass("CoreGui", "Instance", { alsoIsA = { "BasePlayerGui" } })
defineClass("PlayerGui", "Instance", {
	alsoIsA = { "BasePlayerGui" },
	methods = {
		GetTopbarTransparency = function()
			return 0
		end,
	},
})
defineClass("StarterGui", "Instance", {
	alsoIsA = { "BasePlayerGui" },
	methods = {
		SetCore = function(_, name, value)
			if name == "SendNotification" and type(value) == "table" then
				E.host.print("[SetCore notification] " .. tostring(value.Title) .. ": " .. tostring(value.Text))
			end
		end,
		GetCore = function()
			return nil
		end,
		SetCoreGuiEnabled = function() end,
		GetCoreGuiEnabled = function()
			return true
		end,
	},
})
defineClass("Players", "Instance", {
	props = {
		{ "LocalPlayer", "Instance", nil, "r" },
		{ "MaxPlayers", "int", 12, "r" },
	},
	events = { "PlayerAdded", "PlayerRemoving" },
	methods = {
		GetPlayers = function(self)
			local list = {}
			for _, c in D[self].children do
				if D[c].cls.name == "Player" then
					table.insert(list, c)
				end
			end
			return list
		end,
		GetPlayerByUserId = function(self, id)
			for _, c in D[self].children do
				if D[c].cls.name == "Player" and D[c].props.UserId == id then
					return c
				end
			end
			return nil
		end,
		GetUserThumbnailAsync = function(_, id)
			return "rbxthumb://type=AvatarHeadShot&id=" .. tostring(id) .. "&w=150&h=150", true
		end,
	},
})
defineClass("Player", "Instance", {
	props = {
		{ "DisplayName", "string", "Player" },
		{ "UserId", "int", 0 },
		{ "AccountAge", "int", 0 },
		{ "Character", "Instance", nil },
		{ "Team", "Instance", nil },
		{ "MembershipType", "string", "None" },
	},
	events = { "CharacterAdded", "CharacterRemoving", "Chatted", "Idled" },
	methods = {
		GetMouse = function(self)
			return E.mouse
		end,
		GetNetworkPing = function()
			-- one-way latency in seconds, wandering like a real connection
			return 0.03 + 0.012 * math.sin(os.clock() * 0.7) + math.random() * 0.004
		end,
		Kick = function(_, msg)
			E.host.warn("Player:Kick called: " .. tostring(msg))
		end,
		IsFriendsWith = function()
			return false
		end,
	},
})
defineClass("Mouse", "Instance", {
	props = {
		{ "X", "number", 0, "r" },
		{ "Y", "number", 0, "r" },
		{ "Icon", "Content", "" },
		{ "ViewSizeX", "number", 0, "r" },
		{ "ViewSizeY", "number", 0, "r" },
		{ "Hit", "any", nil, "h" },
		{ "Target", "Instance", nil, "r" },
	},
	events = { "Button1Down", "Button1Up", "Button2Down", "Button2Up", "Move", "WheelForward", "WheelBackward", "Idle" },
})
defineClass("Workspace", "Instance", {
	props = { { "CurrentCamera", "Instance", nil }, { "Gravity", "number", 196.2 } },
	methods = {
		GetServerTimeNow = function()
			return E.host.now() / 1000
		end,
	},
})
defineClass("Lighting", "Instance", {
	props = { { "ClockTime", "number", 14 }, { "Brightness", "number", 2 } },
})
defineClass("ReplicatedStorage", "Instance", {})
defineClass("SoundService", "Instance", {})
defineClass("Teams", "Instance", {})
defineClass("Chat", "Instance", {})
defineClass("TextChatService", "Instance", {})
defineClass("ContentProvider", "Instance", {
	methods = {
		PreloadAsync = function(_, list, cb)
			if cb then
				for _, a in list do
					cb(a, enums.AssetFetchStatus and enums.AssetFetchStatus.Success or nil)
				end
			end
		end,
	},
})
defineClass("GuiService", "Instance", {
	props = {
		{ "SelectedObject", "Instance", nil },
		{ "AutoSelectGuiEnabled", "bool", true },
		{ "MenuIsOpen", "bool", false, "r" },
	},
	events = { "MenuOpened", "MenuClosed" },
	methods = {
		GetGuiInset = function()
			return V2(0, E.guiInset), V2(0, 0)
		end,
		IsTenFootInterface = function()
			return false
		end,
	},
})
