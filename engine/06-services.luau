-- DataModel, services, input dispatch and the per-frame step the host drives.

local host = E.host
local typeof = E.typeof
local defineClass, newInstance, setProp = E.defineClass, E.newInstance, E.setProp
local D, byId, fire, fireIf, signalOf = E.D, E.byId, E.fire, E.fireIf, E.signalOf
local V2, V3, C3 = E.V2, E.V3, E.C3
local enums = E.enums
local SEP = "\31"

E.guiInset = 58

---------------------------------------------------------------- TweenService
local EASE = {}
EASE.Linear = function(t)
	return t
end
EASE.Sine = function(t)
	return 1 - math.cos(t * math.pi / 2)
end
EASE.Quad = function(t)
	return t * t
end
EASE.Cubic = function(t)
	return t * t * t
end
EASE.Quart = function(t)
	return t * t * t * t
end
EASE.Quint = function(t)
	return t * t * t * t * t
end
EASE.Exponential = function(t)
	return t == 0 and 0 or 2 ^ (10 * t - 10)
end
EASE.Circular = function(t)
	return 1 - math.sqrt(1 - t * t)
end
EASE.Back = function(t)
	local s = 1.70158
	return t * t * ((s + 1) * t - s)
end
EASE.Elastic = function(t)
	if t == 0 or t == 1 then
		return t
	end
	return -(2 ^ (10 * t - 10)) * math.sin((t * 10 - 10.75) * (2 * math.pi / 3))
end
local function bounceOut(t)
	local n, d = 7.5625, 2.75
	if t < 1 / d then
		return n * t * t
	elseif t < 2 / d then
		t -= 1.5 / d
		return n * t * t + 0.75
	elseif t < 2.5 / d then
		t -= 2.25 / d
		return n * t * t + 0.9375
	end
	t -= 2.625 / d
	return n * t * t + 0.984375
end
EASE.Bounce = function(t)
	return 1 - bounceOut(1 - t)
end

local function ease(alpha, style, direction)
	alpha = math.clamp(alpha, 0, 1)
	local f = EASE[style.Name] or EASE.Quad
	if direction.Name == "In" then
		return f(alpha)
	elseif direction.Name == "Out" then
		return 1 - f(1 - alpha)
	end
	if alpha < 0.5 then
		return f(alpha * 2) / 2
	end
	return 1 - f(2 - alpha * 2) / 2
end

local function lerp(a, b, t)
	local ty = typeof(a)
	if ty == "number" then
		return a + (b - a) * t
	elseif ty == "boolean" or ty == "EnumItem" or ty == "string" then
		return t >= 1 and b or a
	elseif ty == "Rect" then
		return Rect.new(a.Min:Lerp(b.Min, t), a.Max:Lerp(b.Max, t))
	end
	return a:Lerp(b, t)
end

local TWEENABLE = {
	number = true,
	int = true,
	bool = true,
	UDim = true,
	UDim2 = true,
	Vector2 = true,
	Vector3 = true,
	Color3 = true,
	Rect = true,
	CFrame = true,
}

local activeTweens = {}

local function tweenData(self)
	return D[self].tw
end

local function setTweenState(self, d, state)
	if d.props.PlaybackState ~= state then
		setProp(self, "PlaybackState", state, true)
	end
end

local function cancelOverlapping(self, tw)
	for other in activeTweens do
		if other ~= self then
			local ot = tweenData(other)
			if ot.target == tw.target then
				for prop in tw.goals do
					if ot.goals[prop] ~= nil then
						activeTweens[other] = nil
						setTweenState(other, D[other], enums.PlaybackState.Cancelled)
						fireIf(D[other], "Completed", enums.PlaybackState.Cancelled)
						break
					end
				end
			end
		end
	end
end

defineClass("TweenBase", "Instance", {
	noHost = true,
	props = { { "PlaybackState", "Enum:PlaybackState", enums.PlaybackState.Begin, "r" } },
	events = { "Completed" },
})
defineClass("Tween", "TweenBase", {
	noHost = true,
	props = {
		{ "Instance", "Instance", nil, "r" },
		{ "TweenInfo", "any", nil, "r" },
	},
	methods = {
		Play = function(self)
			local d = D[self]
			local tw = d.tw
			if activeTweens[self] and d.props.PlaybackState ~= enums.PlaybackState.Paused then
				return
			end
			if d.props.PlaybackState ~= enums.PlaybackState.Paused then
				tw.elapsed = 0
				tw.from = nil
			end
			cancelOverlapping(self, tw)
			activeTweens[self] = true
			setTweenState(self, d, tw.info.DelayTime > 0 and enums.PlaybackState.Delayed or enums.PlaybackState.Playing)
		end,
		Pause = function(self)
			if activeTweens[self] then
				activeTweens[self] = nil
				setTweenState(self, D[self], enums.PlaybackState.Paused)
			end
		end,
		Cancel = function(self)
			local d = D[self]
			activeTweens[self] = nil
			d.tw.elapsed = 0
			d.tw.from = nil
			if d.props.PlaybackState ~= enums.PlaybackState.Cancelled then
				setTweenState(self, d, enums.PlaybackState.Cancelled)
				fireIf(d, "Completed", enums.PlaybackState.Cancelled)
			end
		end,
	},
})

local function stepTweens(dt)
	for self in activeTweens do
		local d = D[self]
		local tw = d.tw
		local td = D[tw.target]
		if td == nil or td.destroyed then
			activeTweens[self] = nil
			continue
		end
		tw.elapsed += dt
		local info = tw.info
		local t = tw.elapsed - info.DelayTime
		if t < 0 then
			continue
		end
		if not tw.from then
			tw.from = {}
			for prop in tw.goals do
				tw.from[prop] = td.props[prop]
			end
			setTweenState(self, d, enums.PlaybackState.Playing)
		end
		local cycle = info.Time * (info.Reverses and 2 or 1)
		local total = info.RepeatCount < 0 and math.huge or cycle * (info.RepeatCount + 1)
		local done = t >= total
		local local_t = done and cycle or (cycle > 0 and t % cycle or 0)
		if done and info.Reverses then
			local_t = cycle
		end
		local alpha
		if info.Time <= 0 then
			alpha = info.Reverses and 0 or 1
		elseif info.Reverses and local_t > info.Time then
			alpha = 1 - (local_t - info.Time) / info.Time
		else
			alpha = math.min(local_t / info.Time, 1)
		end
		if done then
			alpha = info.Reverses and 0 or 1
		end
		local eased = ease(alpha, info.EasingStyle, info.EasingDirection)
		for prop, goal in tw.goals do
			local from = tw.from[prop]
			local ok, err = pcall(setProp, tw.target, prop, alpha >= 1 and goal or lerp(from, goal, eased), true)
			if not ok then
				host.warn("Tween failed on " .. prop .. ": " .. tostring(err))
			end
		end
		if done then
			activeTweens[self] = nil
			setTweenState(self, d, enums.PlaybackState.Completed)
			fireIf(d, "Completed", enums.PlaybackState.Completed)
		end
	end
end

defineClass("TweenService", "Instance", {
	methods = {
		Create = function(_, inst, info, goals)
			if not E.isInstance(inst) then
				error("TweenService:Create no instance given", 2)
			end
			if typeof(info) ~= "TweenInfo" then
				error("TweenService:Create expects a TweenInfo as argument #2", 2)
			end
			if type(goals) ~= "table" then
				error("TweenService:Create expects a table of property goals as argument #3", 2)
			end
			local td = D[inst]
			local clean = {}
			for prop, goal in goals do
				local def = td.cls.props[prop]
				if not def then
					error(string.format("No property named '%s' for object '%s'", tostring(prop), td.props.Name), 2)
				end
				if not TWEENABLE[def.kind] then
					error(string.format("TweenService:Create property named '%s' cannot be tweened due to type mismatch (property is a '%s', but given type is '%s')", prop, def.kind, typeof(goal)), 2)
				end
				clean[prop] = goal
			end
			local tween = newInstance("Tween", true)
			local d = D[tween]
			d.props.Instance = inst
			d.props.TweenInfo = info
			d.tw = { target = inst, info = info, goals = clean, elapsed = 0 }
			return tween
		end,
		GetValue = function(_, alpha, style, direction)
			return ease(alpha, style, direction)
		end,
		SmoothDamp = function(_, current, target, velocity, smoothTime, maxSpeed, dt)
			return lerp(current, target, math.clamp((dt or 1 / 60) / math.max(smoothTime, 1e-4), 0, 1)), velocity
		end,
	},
})

---------------------------------------------------------------- RunService
local renderBindings = {}
defineClass("RunService", "Instance", {
	events = { "Heartbeat", "RenderStepped", "Stepped", "PreRender", "PreAnimation", "PreSimulation", "PostSimulation" },
	methods = {
		IsStudio = function()
			return false
		end,
		IsClient = function()
			return true
		end,
		IsServer = function()
			return false
		end,
		IsRunning = function()
			return true
		end,
		IsRunMode = function()
			return false
		end,
		IsEdit = function()
			return false
		end,
		BindToRenderStep = function(_, name, priority, fn)
			renderBindings[name] = { priority = priority, fn = fn }
		end,
		UnbindFromRenderStep = function(_, name)
			renderBindings[name] = nil
		end,
	},
})

---------------------------------------------------------------- HttpService (JSON lives here)
local function jsonEncode(v, seen)
	local t = type(v)
	if t == "nil" then
		return "null"
	elseif t == "boolean" then
		return v and "true" or "false"
	elseif t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			return "null"
		end
		if v == math.floor(v) and math.abs(v) < 1e15 then
			return string.format("%d", v)
		end
		return string.format("%.14g", v)
	elseif t == "string" then
		return '"'
			.. string.gsub(v, '[%c"\\]', function(c)
				local map = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t", ["\b"] = "\\b", ["\f"] = "\\f" }
				return map[c] or string.format("\\u%04x", string.byte(c))
			end)
			.. '"'
	elseif t == "table" then
		seen = seen or {}
		if seen[v] then
			error("Can't convert to JSON: cyclic table", 0)
		end
		seen[v] = true
		local n = #v
		local isArray = n > 0 or next(v) == nil
		if isArray then
			for k in v do
				if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then
					isArray = false
					break
				end
			end
		end
		local parts = {}
		if isArray then
			for i = 1, n do
				parts[i] = jsonEncode(v[i], seen)
			end
			seen[v] = nil
			return "[" .. table.concat(parts, ",") .. "]"
		end
		for k, val in v do
			if type(k) ~= "string" and type(k) ~= "number" then
				error("Can't convert to JSON: invalid key type " .. type(k), 0)
			end
			table.insert(parts, jsonEncode(tostring(k)) .. ":" .. jsonEncode(val, seen))
		end
		seen[v] = nil
		return "{" .. table.concat(parts, ",") .. "}"
	end
	error("Can't convert to JSON: unsupported type " .. typeof(v), 0)
end

local function jsonDecode(s: string)
	local pos = 1
	local function ws()
		pos = string.find(s, "[^ \t\r\n]", pos) or #s + 1
	end
	local function fail(msg)
		error("Can't parse JSON: " .. msg .. " at character " .. pos, 0)
	end
	local value
	local function str()
		pos += 1
		local out = {}
		while true do
			local c = string.sub(s, pos, pos)
			if c == "" then
				fail("unterminated string")
			elseif c == '"' then
				pos += 1
				break
			elseif c == "\\" then
				local e = string.sub(s, pos + 1, pos + 1)
				local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
				if e == "u" then
					local hex = string.sub(s, pos + 2, pos + 5)
					local cp = tonumber(hex, 16) or fail("bad unicode escape")
					pos += 6
					if cp >= 0xD800 and cp <= 0xDBFF and string.sub(s, pos, pos + 1) == "\\u" then
						local lo = tonumber(string.sub(s, pos + 2, pos + 5), 16)
						if lo and lo >= 0xDC00 and lo <= 0xDFFF then
							cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
							pos += 6
						end
					end
					table.insert(out, utf8.char(cp))
				else
					table.insert(out, map[e] or fail("bad escape"))
					pos += 2
				end
			else
				local nxt = string.find(s, '["\\]', pos) or #s + 1
				table.insert(out, string.sub(s, pos, nxt - 1))
				pos = nxt
			end
		end
		return table.concat(out)
	end
	value = function()
		ws()
		local c = string.sub(s, pos, pos)
		if c == "{" then
			pos += 1
			local obj = {}
			ws()
			if string.sub(s, pos, pos) == "}" then
				pos += 1
				return obj
			end
			while true do
				ws()
				if string.sub(s, pos, pos) ~= '"' then
					fail("expected key")
				end
				local k = str()
				ws()
				if string.sub(s, pos, pos) ~= ":" then
					fail("expected ':'")
				end
				pos += 1
				obj[k] = value()
				ws()
				local d = string.sub(s, pos, pos)
				pos += 1
				if d == "}" then
					return obj
				elseif d ~= "," then
					fail("expected ',' or '}'")
				end
			end
		elseif c == "[" then
			pos += 1
			local arr = {}
			ws()
			if string.sub(s, pos, pos) == "]" then
				pos += 1
				return arr
			end
			while true do
				table.insert(arr, value())
				ws()
				local d = string.sub(s, pos, pos)
				pos += 1
				if d == "]" then
					return arr
				elseif d ~= "," then
					fail("expected ',' or ']'")
				end
			end
		elseif c == '"' then
			return str()
		elseif string.sub(s, pos, pos + 3) == "true" then
			pos += 4
			return true
		elseif string.sub(s, pos, pos + 4) == "false" then
			pos += 5
			return false
		elseif string.sub(s, pos, pos + 3) == "null" then
			pos += 4
			return nil
		end
		local numStr = string.match(s, "^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
		if numStr and #numStr > 0 then
			pos += #numStr
			return tonumber(numStr)
		end
		fail("unexpected character '" .. c .. "'")
		return nil
	end
	local result = value()
	ws()
	if pos <= #s then
		fail("trailing characters")
	end
	return result
end
E.jsonEncode = jsonEncode
E.jsonDecode = jsonDecode

defineClass("HttpService", "Instance", {
	props = { { "HttpEnabled", "bool", false } },
	methods = {
		JSONEncode = function(_, v)
			return jsonEncode(v)
		end,
		JSONDecode = function(_, s)
			if type(s) ~= "string" then
				error("Can't parse JSON", 2)
			end
			return jsonDecode(s)
		end,
		GenerateGUID = function(_, wrap)
			local g = string.gsub("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx", "[xy]", function(c)
				local v = c == "x" and math.random(0, 15) or math.random(8, 11)
				return string.format("%X", v)
			end)
			return (wrap == false) and g or "{" .. g .. "}"
		end,
		UrlEncode = function(_, s)
			return (string.gsub(s, "[^%w%-_%.~]", function(c)
				return string.format("%%%02X", string.byte(c))
			end))
		end,
		GetAsync = function()
			error("Http requests can only be executed by game server", 2)
		end,
		PostAsync = function()
			error("Http requests can only be executed by game server", 2)
		end,
		RequestAsync = function()
			error("Http requests can only be executed by game server", 2)
		end,
	},
})

---------------------------------------------------------------- TextService
local function measure(text, size, font, width)
	local res = host.measure(text, size, font.Family, font.Weight.Value, font.Style.Value, width or 0)
	local w, h = string.match(res, "^([^\31]+)\31(.+)$")
	return V2(tonumber(w) or 0, tonumber(h) or 0)
end
defineClass("GetTextBoundsParams", "Instance", {
	creatable = true,
	noHost = true,
	props = {
		{ "Text", "string", "" },
		{ "Font", "Font", function()
			return E.fontFromEnum(enums.Font.BuilderSans)
		end },
		{ "Size", "number", 14 },
		{ "Width", "number", 0 },
		{ "RichText", "bool", false },
	},
})
defineClass("TextService", "Instance", {
	methods = {
		GetTextSize = function(_, text, size, font, frame)
			local f = typeof(font) == "Font" and font or E.fontFromEnum(E.coerceEnum("Font", font) or enums.Font.SourceSans)
			local w = frame and frame.X or 0
			if w >= 1e6 then
				w = 0
			end
			return measure(tostring(text), size, f, w)
		end,
		GetTextBoundsAsync = function(_, params)
			local p = D[params].props
			return measure(p.Text, p.Size, p.Font, p.Width)
		end,
		FilterStringAsync = function(_, s)
			return s
		end,
	},
})

---------------------------------------------------------------- UserInputService and input objects
defineClass("InputObject", "Instance", {
	noHost = true,
	props = {
		{ "KeyCode", "Enum:KeyCode", enums.KeyCode.Unknown },
		{ "UserInputType", "Enum:UserInputType", enums.UserInputType.None },
		{ "UserInputState", "Enum:UserInputState", enums.UserInputState.None },
		{ "Position", "Vector3", function()
			return V3(0, 0, 0)
		end },
		{ "Delta", "Vector3", function()
			return V3(0, 0, 0)
		end },
	},
	methods = {
		IsModifierKeyDown = function(_, key)
			return E.keysDown[key.Name] ~= nil
		end,
	},
})

E.keysDown = {} -- KeyCode name -> InputObject
E.buttonsDown = {} -- UserInputType name -> InputObject
E.mousePos = V2(0, 0) -- screen space (includes the topbar)
E.focusedTextBox = nil

defineClass("UserInputService", "Instance", {
	props = {
		{ "MouseEnabled", "bool", true, "r" },
		{ "KeyboardEnabled", "bool", true, "r" },
		{ "TouchEnabled", "bool", false, "r" },
		{ "GamepadEnabled", "bool", false, "r" },
		{ "AccelerometerEnabled", "bool", false, "r" },
		{ "GyroscopeEnabled", "bool", false, "r" },
		{ "VREnabled", "bool", false, "r" },
		{ "MouseBehavior", "Enum:MouseBehavior", enums.MouseBehavior.Default },
		{ "MouseIconEnabled", "bool", true },
		{ "MouseIcon", "Content", "" },
		{ "MouseDeltaSensitivity", "number", 1 },
		{ "ModalEnabled", "bool", false },
		{ "OnScreenKeyboardVisible", "bool", false, "r" },
	},
	events = {
		"InputBegan",
		"InputChanged",
		"InputEnded",
		"TextBoxFocused",
		"TextBoxFocusReleased",
		"WindowFocused",
		"WindowFocusReleased",
		"LastInputTypeChanged",
		"JumpRequest",
		"TouchStarted",
		"TouchMoved",
		"TouchEnded",
		"TouchTap",
		"GamepadConnected",
		"GamepadDisconnected",
	},
	methods = {
		GetMouseLocation = function()
			return E.mousePos
		end,
		GetMouseDelta = function()
			return V2(0, 0)
		end,
		IsKeyDown = function(_, key)
			key = E.coerceEnum("KeyCode", key)
			return key ~= nil and E.keysDown[key.Name] ~= nil
		end,
		IsMouseButtonPressed = function(_, t)
			t = E.coerceEnum("UserInputType", t)
			return t ~= nil and E.buttonsDown[t.Name] ~= nil
		end,
		GetKeysPressed = function()
			local list = {}
			for _, io in E.keysDown do
				table.insert(list, io)
			end
			return list
		end,
		GetMouseButtonsPressed = function()
			local list = {}
			for _, io in E.buttonsDown do
				table.insert(list, io)
			end
			return list
		end,
		GetFocusedTextBox = function()
			return E.focusedTextBox
		end,
		GetLastInputType = function()
			return E.lastInputType or enums.UserInputType.MouseMovement
		end,
		GetStringForKeyCode = function(_, key)
			local name = key.Name
			if #name == 1 then
				return name
			end
			local map = { Zero = "0", One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9", Space = " ", Minus = "-", Equals = "=", Comma = ",", Period = ".", Slash = "/", Semicolon = ";", Quote = "'", LeftBracket = "[", RightBracket = "]", BackSlash = "\\", Backquote = "`" }
			return map[name] or ""
		end,
		GetGamepadConnected = function()
			return false
		end,
		GetConnectedGamepads = function()
			return {}
		end,
		GetNavigationGamepads = function()
			return {}
		end,
		GetDeviceType = function()
			return "Desktop"
		end,
	},
})

---------------------------------------------------------------- DataModel
local services = {}
local serviceNames = {
	"Workspace",
	"Players",
	"Lighting",
	"ReplicatedStorage",
	"StarterGui",
	"SoundService",
	"Teams",
	"Chat",
	"TextChatService",
	"CoreGui",
	"TweenService",
	"UserInputService",
	"RunService",
	"HttpService",
	"TextService",
	"ContentProvider",
	"GuiService",
}

game = newInstance("DataModel", true)
D[game].props.Name = "Game"
E.emit("p" .. SEP .. D[game].id .. SEP .. "Name" .. SEP .. "s" .. SEP .. "Game")
Game = game

local function getService(name)
	if services[name] then
		return services[name]
	end
	local cls = E.classes[name]
	if not cls then
		return nil
	end
	local s = newInstance(name, true)
	setProp(s, "Name", name, true)
	setProp(s, "Parent", game, true)
	services[name] = s
	return s
end

defineClass("DataModel", "Instance", {
	alsoIsA = { "ServiceProvider" },
	props = {
		{ "PlaceId", "int", 0, "r" },
		{ "GameId", "int", 0, "r" },
		{ "JobId", "string", "00000000-0000-4000-8000-000000000000", "r" },
		{ "PlaceVersion", "int", 1, "r" },
		{ "CreatorId", "int", 0, "r" },
		{ "CreatorType", "string", "User", "r" },
	},
	events = { "Loaded", "Close" },
	methods = {
		GetService = function(_, name)
			local s = getService(name)
			if not s then
				error("'" .. tostring(name) .. "' is not a valid Service name", 2)
			end
			return s
		end,
		FindService = function(_, name)
			return services[name]
		end,
		IsLoaded = function()
			return true
		end,
		BindToClose = function() end,
		Shutdown = function() end,
	},
})
-- the DataModel was created before its class gained these members; refresh its class
D[game].cls = E.classes.DataModel
for _, p in { "PlaceId", "GameId", "JobId", "PlaceVersion", "CreatorId", "CreatorType" } do
	D[game].props[p] = E.classes.DataModel.props[p].default
end

for _, name in serviceNames do
	getService(name)
end
E.TweenService = services.TweenService
E.UIS = services.UserInputService
E.RunService = services.RunService

local camera = newInstance("Camera", true)
setProp(camera, "Name", "Camera", true)
setProp(camera, "Parent", services.Workspace, true)
setProp(services.Workspace, "CurrentCamera", camera, true)
E.camera = camera
workspace = services.Workspace
Workspace = workspace

local player = newInstance("Player", true)
setProp(player, "Name", "Player1", true)
setProp(player, "DisplayName", "Player1", true)
setProp(player, "UserId", 1, true)
setProp(player, "Parent", services.Players, true)
setProp(services.Players, "LocalPlayer", player, true)
local playerGui = newInstance("PlayerGui", true)
setProp(playerGui, "Name", "PlayerGui", true)
setProp(playerGui, "Parent", player, true)
E.player = player
E.mouse = newInstance("Mouse", true)

---------------------------------------------------------------- input from the host
local function inputObject(typeName, state, keyName)
	local io = newInstance("InputObject", true)
	local p = D[io].props
	p.UserInputType = enums.UserInputType[typeName]
	p.UserInputState = enums.UserInputState[state]
	p.KeyCode = keyName and enums.KeyCode[keyName] or enums.KeyCode.Unknown
	local mp = E.mousePos
	p.Position = V3(mp.X, mp.Y - E.guiInset, 0)
	return io
end

local moveInput -- persistent, like Roblox
local wheelInput

local function setInputState(io, state)
	setProp(io, "UserInputState", enums.UserInputState[state], true)
end

local function updateMouse(x, y)
	local old = E.mousePos
	E.mousePos = V2(x, y)
	local mp = D[E.mouse].props
	mp.X, mp.Y = x, y - E.guiInset
	return V3(x - old.X, y - old.Y, 0)
end

local BUTTON_TYPES = { "MouseButton1", "MouseButton2", "MouseButton3" }

local function instFrom(idStr)
	local inst = byId[tonumber(idStr) :: number]
	if inst and D[inst] and not D[inst].destroyed then
		return inst
	end
	return nil
end

local function decodeValue(f, i)
	local tag = f[i]
	local n = function(k)
		return tonumber(f[i + k]) or 0
	end
	if tag == "b" then
		return f[i + 1] == "1"
	elseif tag == "n" then
		return n(1)
	elseif tag == "s" then
		return f[i + 1] or ""
	elseif tag == "C3" then
		return C3(n(1), n(2), n(3))
	elseif tag == "V2" then
		return V2(n(1), n(2))
	elseif tag == "U2" then
		return E.UDim2(n(1), n(2), n(3), n(4))
	elseif tag == "U" then
		return E.UDim(n(1), n(2))
	elseif tag == "E" then
		return E.enums[f[i + 1]] and E.coerceEnum(f[i + 1], f[i + 2])
	end
	return nil
end

local function applyEvent(f)
	local kind = f[1]
	local UIS = E.UIS
	local ud = D[UIS]
	if kind == "mm" then
		local delta = updateMouse(tonumber(f[2]), tonumber(f[3]))
		if not moveInput then
			moveInput = inputObject("MouseMovement", "Change")
		end
		local p = D[moveInput].props
		p.Position = V3(E.mousePos.X, E.mousePos.Y - E.guiInset, 0)
		p.Delta = delta
		E.pendingMoveInput = moveInput
		fireIf(ud, "InputChanged", moveInput, f[4] == "1")
		fireIf(D[E.mouse], "Move")
	elseif kind == "md" or kind == "mu" then
		updateMouse(tonumber(f[3]), tonumber(f[4]))
		local typeName = BUTTON_TYPES[tonumber(f[2]) :: number] or "MouseButton1"
		local gp = f[5] == "1"
		E.lastInputType = enums.UserInputType[typeName]
		if kind == "md" then
			local io = inputObject(typeName, "Begin")
			E.buttonsDown[typeName] = io
			fireIf(ud, "InputBegan", io, gp)
			if typeName == "MouseButton1" then
				fireIf(D[E.mouse], "Button1Down")
			elseif typeName == "MouseButton2" then
				fireIf(D[E.mouse], "Button2Down")
			end
		else
			local io = E.buttonsDown[typeName] or inputObject(typeName, "Begin")
			E.buttonsDown[typeName] = nil
			D[io].props.Position = V3(E.mousePos.X, E.mousePos.Y - E.guiInset, 0)
			setInputState(io, "End")
			fireIf(ud, "InputEnded", io, gp)
			if typeName == "MouseButton1" then
				fireIf(D[E.mouse], "Button1Up")
			elseif typeName == "MouseButton2" then
				fireIf(D[E.mouse], "Button2Up")
			end
		end
	elseif kind == "mw" then
		updateMouse(tonumber(f[3]), tonumber(f[4]))
		if not wheelInput then
			wheelInput = inputObject("MouseWheel", "Change")
		end
		local dir = tonumber(f[2]) or 0
		D[wheelInput].props.Position = V3(E.mousePos.X, E.mousePos.Y - E.guiInset, dir)
		fireIf(ud, "InputChanged", wheelInput, f[5] == "1")
		fireIf(D[E.mouse], dir > 0 and "WheelForward" or "WheelBackward")
	elseif kind == "kd" or kind == "ku" then
		local key = enums.KeyCode[f[2]]
		if not key then
			return
		end
		local gp = f[3] == "1"
		E.lastInputType = enums.UserInputType.Keyboard
		if kind == "kd" then
			if E.keysDown[f[2]] then
				return -- auto-repeat
			end
			local io = inputObject("Keyboard", "Begin", f[2])
			E.keysDown[f[2]] = io
			fireIf(ud, "InputBegan", io, gp)
		else
			local io = E.keysDown[f[2]] or inputObject("Keyboard", "Begin", f[2])
			E.keysDown[f[2]] = nil
			setInputState(io, "End")
			fireIf(ud, "InputEnded", io, gp)
		end
	elseif kind == "ge" then
		-- MouseEnter / MouseLeave / MouseMoved / MouseWheelForward / MouseWheelBackward on a GuiObject
		local inst = instFrom(f[2])
		if inst then
			local x, y = tonumber(f[4]) or 0, (tonumber(f[5]) or 0) - E.guiInset
			fireIf(D[inst], f[3], x, y)
		end
	elseif kind == "gi" then
		-- GuiObject.InputBegan/Changed/Ended; f[4] names the input: m, w, b1..b3
		local inst = instFrom(f[2])
		if inst then
			local which = f[4]
			local io
			if which == "m" then
				io = moveInput or inputObject("MouseMovement", "Change")
				moveInput = io
			elseif which == "w" then
				io = wheelInput or inputObject("MouseWheel", "Change")
				wheelInput = io
			else
				local typeName = BUTTON_TYPES[tonumber(string.sub(which, 2)) :: number]
				io = E.buttonsDown[typeName]
				if not io then
					io = inputObject(typeName, f[3] == "InputEnded" and "End" or "Begin")
					if f[3] == "InputBegan" then
						E.buttonsDown[typeName] = io
					end
				end
			end
			fireIf(D[inst], f[3], io)
		end
	elseif kind == "gb" then
		-- GuiButton events: MouseButton1Down/Up/Click, MouseButton2..., Activated
		local inst = instFrom(f[2])
		if inst then
			local ev = f[3]
			if ev == "Activated" then
				local io = E.buttonsDown.MouseButton1 or inputObject("MouseButton1", "End")
				fireIf(D[inst], "Activated", io, tonumber(f[4]) or 1)
			elseif ev == "MouseButton1Click" or ev == "MouseButton2Click" then
				fireIf(D[inst], ev)
			else
				fireIf(D[inst], ev, tonumber(f[4]) or 0, (tonumber(f[5]) or 0) - E.guiInset)
			end
		end
	elseif kind == "gs" then
		local inst = instFrom(f[2])
		if inst then
			setProp(inst, "GuiState", f[3], true)
		end
	elseif kind == "tx" then
		local inst = instFrom(f[2])
		if inst then
			setProp(inst, "Text", f[3] or "", true)
		end
	elseif kind == "tf" then
		local inst = instFrom(f[2])
		if inst then
			E.focusedTextBox = inst
			fireIf(D[inst], "Focused")
			fireIf(ud, "TextBoxFocused", inst)
		end
	elseif kind == "tl" then
		local inst = instFrom(f[2])
		if inst then
			if E.focusedTextBox == inst then
				E.focusedTextBox = nil
			end
			fireIf(D[inst], "FocusLost", f[3] == "1", nil)
			fireIf(ud, "TextBoxFocusReleased", inst)
		end
	elseif kind == "cp" then
		local inst = instFrom(f[2])
		if inst then
			setProp(inst, "CanvasPosition", V2(tonumber(f[3]), tonumber(f[4])), true)
		end
	elseif kind == "vp" then
		local w, h = tonumber(f[2]) or 1280, tonumber(f[3]) or 720
		setProp(E.camera, "ViewportSize", V2(w, h), true)
		D[E.mouse].props.ViewSizeX = w
		D[E.mouse].props.ViewSizeY = h
		if f[4] then
			local touch = f[4] == "1"
			setProp(UIS, "TouchEnabled", touch, true)
			setProp(UIS, "MouseEnabled", not touch, true)
		end
	elseif kind == "ps" then
		local inst = instFrom(f[2])
		if inst then
			local v = decodeValue(f, 4)
			local ok, err = pcall(setProp, inst, f[3], v, false)
			if not ok then
				host.warn("Properties: " .. tostring(err))
			end
		end
	elseif kind == "rl" then
		E.dirty = true
	elseif kind == "focus" then
		fireIf(ud, f[2] == "1" and "WindowFocused" or "WindowFocusReleased")
	end
end

---------------------------------------------------------------- the frame
function E.step(dt: number, events: string?)
	if events and events ~= "" then
		for rec in string.gmatch(events, "[^\30]+") do
			local ok, err = pcall(applyEvent, string.split(rec, SEP))
			if not ok then
				host.error("input dispatch failed: " .. tostring(err), "")
			end
		end
	end
	E.runScheduler(dt)
	local rs = D[E.RunService]
	local bindings = {}
	for _, b in renderBindings do
		table.insert(bindings, b)
	end
	table.sort(bindings, function(a, b)
		return a.priority < b.priority
	end)
	for _, b in bindings do
		task.spawn(b.fn, dt)
	end
	fireIf(rs, "PreRender", dt)
	fireIf(rs, "RenderStepped", dt)
	stepTweens(dt)
	fireIf(rs, "PreSimulation", dt)
	fireIf(rs, "Stepped", E.clock, dt)
	fireIf(rs, "PostSimulation", dt)
	fireIf(rs, "Heartbeat", dt)
	E.flushDeferred()
	-- settle layout: host results can trigger handlers that change layout again
	for _ = 1, 4 do
		E.ensureLayout()
		E.firePendingChanged()
		E.flushDeferred()
		if not E.hasPendingOps() then
			break
		end
	end
	E.ensureLayout()
end
