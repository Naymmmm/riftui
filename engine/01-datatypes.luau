-- Roblox datatypes implemented in plain Luau. Values are frozen tables whose metatable
-- carries __type, which the engine's typeof() reports the way Roblox does.

-- Touching the environment turns off builtin fastcalls for this state, so the typeof
-- override below is honoured by every chunk, including ones compiled later.
getfenv()

local rawtypeof = typeof
local function rtypeof(v: any): string
	local t = type(v)
	if t == "userdata" and E.D and E.D[v] then
		return "Instance"
	end
	if t == "table" or t == "userdata" then
		local mt = getmetatable(v)
		if type(mt) == "table" then
			local n = rawget(mt, "__type")
			if n then
				return n
			end
		end
	end
	return rawtypeof(v)
end
typeof = rtypeof
E.typeof = rtypeof

local function fmt(n: number): string
	if n == math.floor(n) and math.abs(n) < 1e15 then
		return string.format("%d", n)
	end
	return string.format("%.6g", n)
end
E.fmt = fmt

local function makeType(name: string, methods: { [string]: any }, getters: { [string]: (any) -> any }?)
	local mt = { __type = name }
	mt.__index = function(self, key)
		local m = methods[key]
		if m ~= nil then
			return m
		end
		if getters then
			local g = getters[key]
			if g then
				return g(self)
			end
		end
		error(tostring(key) .. " is not a valid member of " .. name, 2)
	end
	mt.__newindex = function(_, key)
		error(tostring(key) .. " cannot be assigned to", 2)
	end
	return mt
end

local function new(mt, fields)
	return table.freeze(setmetatable(fields, mt))
end

local function argNum(v, i: number, fn: string, default: number?): number
	if v == nil then
		return default or 0
	end
	if type(v) ~= "number" then
		local n = tonumber(v)
		if n then
			return n
		end
		error(string.format("invalid argument #%d to '%s' (number expected, got %s)", i, fn, rtypeof(v)), 3)
	end
	return v
end

---------------------------------------------------------------- UDim
local UDimM = {}
local UDimMT = makeType("UDim", UDimM)
local function newUDim(s, o)
	return new(UDimMT, { Scale = s, Offset = o })
end
UDimMT.__add = function(a, b)
	return newUDim(a.Scale + b.Scale, a.Offset + b.Offset)
end
UDimMT.__sub = function(a, b)
	return newUDim(a.Scale - b.Scale, a.Offset - b.Offset)
end
UDimMT.__unm = function(a)
	return newUDim(-a.Scale, -a.Offset)
end
UDimMT.__eq = function(a, b)
	return a.Scale == b.Scale and a.Offset == b.Offset
end
UDimMT.__tostring = function(a)
	return fmt(a.Scale) .. ", " .. fmt(a.Offset)
end
function UDimM.Lerp(a, b, t)
	return newUDim(a.Scale + (b.Scale - a.Scale) * t, a.Offset + (b.Offset - a.Offset) * t)
end
UDim = table.freeze({
	new = function(s, o)
		return newUDim(argNum(s, 1, "UDim.new"), argNum(o, 2, "UDim.new"))
	end,
})

---------------------------------------------------------------- UDim2
local UDim2M = {}
local UDim2MT = makeType("UDim2", UDim2M, {
	Width = function(self)
		return self.X
	end,
	Height = function(self)
		return self.Y
	end,
})
local function newUDim2(xs, xo, ys, yo)
	return new(UDim2MT, { X = newUDim(xs, xo), Y = newUDim(ys, yo) })
end
UDim2MT.__add = function(a, b)
	return newUDim2(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset)
end
UDim2MT.__sub = function(a, b)
	return newUDim2(a.X.Scale - b.X.Scale, a.X.Offset - b.X.Offset, a.Y.Scale - b.Y.Scale, a.Y.Offset - b.Y.Offset)
end
UDim2MT.__unm = function(a)
	return newUDim2(-a.X.Scale, -a.X.Offset, -a.Y.Scale, -a.Y.Offset)
end
UDim2MT.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
UDim2MT.__tostring = function(a)
	return "{" .. tostring(a.X) .. "}, {" .. tostring(a.Y) .. "}"
end
function UDim2M.Lerp(a, b, t)
	return newUDim2(
		a.X.Scale + (b.X.Scale - a.X.Scale) * t,
		a.X.Offset + (b.X.Offset - a.X.Offset) * t,
		a.Y.Scale + (b.Y.Scale - a.Y.Scale) * t,
		a.Y.Offset + (b.Y.Offset - a.Y.Offset) * t
	)
end
UDim2 = table.freeze({
	new = function(a, b, c, d)
		if rtypeof(a) == "UDim" then
			local y = b or newUDim(0, 0)
			return newUDim2(a.Scale, a.Offset, y.Scale, y.Offset)
		end
		return newUDim2(
			argNum(a, 1, "UDim2.new"),
			argNum(b, 2, "UDim2.new"),
			argNum(c, 3, "UDim2.new"),
			argNum(d, 4, "UDim2.new")
		)
	end,
	fromScale = function(x, y)
		return newUDim2(argNum(x, 1, "UDim2.fromScale"), 0, argNum(y, 2, "UDim2.fromScale"), 0)
	end,
	fromOffset = function(x, y)
		return newUDim2(0, argNum(x, 1, "UDim2.fromOffset"), 0, argNum(y, 2, "UDim2.fromOffset"))
	end,
})
E.UDim2 = newUDim2
E.UDim = newUDim

---------------------------------------------------------------- Vector2
local V2M = {}
local newV2
local V2MT = makeType("Vector2", V2M, {
	Magnitude = function(v)
		return math.sqrt(v.X * v.X + v.Y * v.Y)
	end,
	Unit = function(v)
		local m = math.sqrt(v.X * v.X + v.Y * v.Y)
		if m == 0 then
			return newV2(0 / 0, 0 / 0)
		end
		return newV2(v.X / m, v.Y / m)
	end,
})
newV2 = function(x, y)
	return new(V2MT, { X = x, Y = y })
end
local function v2op(op)
	return function(a, b)
		if type(a) == "number" then
			return newV2(op(a, b.X), op(a, b.Y))
		elseif type(b) == "number" then
			return newV2(op(a.X, b), op(a.Y, b))
		end
		return newV2(op(a.X, b.X), op(a.Y, b.Y))
	end
end
V2MT.__add = v2op(function(a, b)
	return a + b
end)
V2MT.__sub = v2op(function(a, b)
	return a - b
end)
V2MT.__mul = v2op(function(a, b)
	return a * b
end)
V2MT.__div = v2op(function(a, b)
	return a / b
end)
V2MT.__idiv = v2op(function(a, b)
	return a // b
end)
V2MT.__unm = function(a)
	return newV2(-a.X, -a.Y)
end
V2MT.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
V2MT.__tostring = function(a)
	return fmt(a.X) .. ", " .. fmt(a.Y)
end
function V2M.Lerp(a, b, t)
	return newV2(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t)
end
function V2M.Dot(a, b)
	return a.X * b.X + a.Y * b.Y
end
function V2M.Cross(a, b)
	return a.X * b.Y - a.Y * b.X
end
function V2M.Abs(a)
	return newV2(math.abs(a.X), math.abs(a.Y))
end
function V2M.Floor(a)
	return newV2(math.floor(a.X), math.floor(a.Y))
end
function V2M.Ceil(a)
	return newV2(math.ceil(a.X), math.ceil(a.Y))
end
function V2M.Sign(a)
	return newV2(math.sign(a.X), math.sign(a.Y))
end
function V2M.Max(a, ...)
	local x, y = a.X, a.Y
	for _, v in { ... } do
		x, y = math.max(x, v.X), math.max(y, v.Y)
	end
	return newV2(x, y)
end
function V2M.Min(a, ...)
	local x, y = a.X, a.Y
	for _, v in { ... } do
		x, y = math.min(x, v.X), math.min(y, v.Y)
	end
	return newV2(x, y)
end
function V2M.FuzzyEq(a, b, eps)
	eps = eps or 1e-5
	return math.abs(a.X - b.X) <= eps and math.abs(a.Y - b.Y) <= eps
end
function V2M.Angle(a, b, signed)
	local ang = math.atan2(a.X * b.Y - a.Y * b.X, a.X * b.X + a.Y * b.Y)
	return signed and ang or math.abs(ang)
end
Vector2 = table.freeze({
	new = function(x, y)
		return newV2(argNum(x, 1, "Vector2.new"), argNum(y, 2, "Vector2.new"))
	end,
	zero = newV2(0, 0),
	one = newV2(1, 1),
	xAxis = newV2(1, 0),
	yAxis = newV2(0, 1),
})
E.V2 = newV2

---------------------------------------------------------------- Vector3
local V3M = {}
local newV3
local V3MT = makeType("Vector3", V3M, {
	Magnitude = function(v)
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	end,
	Unit = function(v)
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		if m == 0 then
			return newV3(0 / 0, 0 / 0, 0 / 0)
		end
		return newV3(v.X / m, v.Y / m, v.Z / m)
	end,
})
newV3 = function(x, y, z)
	return new(V3MT, { X = x, Y = y, Z = z })
end
local function v3op(op)
	return function(a, b)
		if type(a) == "number" then
			return newV3(op(a, b.X), op(a, b.Y), op(a, b.Z))
		elseif type(b) == "number" then
			return newV3(op(a.X, b), op(a.Y, b), op(a.Z, b))
		end
		return newV3(op(a.X, b.X), op(a.Y, b.Y), op(a.Z, b.Z))
	end
end
V3MT.__add = v3op(function(a, b)
	return a + b
end)
V3MT.__sub = v3op(function(a, b)
	return a - b
end)
V3MT.__mul = v3op(function(a, b)
	return a * b
end)
V3MT.__div = v3op(function(a, b)
	return a / b
end)
V3MT.__unm = function(a)
	return newV3(-a.X, -a.Y, -a.Z)
end
V3MT.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3MT.__tostring = function(a)
	return fmt(a.X) .. ", " .. fmt(a.Y) .. ", " .. fmt(a.Z)
end
function V3M.Lerp(a, b, t)
	return newV3(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t)
end
function V3M.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function V3M.Cross(a, b)
	return newV3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function V3M.Abs(a)
	return newV3(math.abs(a.X), math.abs(a.Y), math.abs(a.Z))
end
function V3M.Floor(a)
	return newV3(math.floor(a.X), math.floor(a.Y), math.floor(a.Z))
end
function V3M.FuzzyEq(a, b, eps)
	eps = eps or 1e-5
	return (a - b).Magnitude <= eps
end
Vector3 = table.freeze({
	new = function(x, y, z)
		return newV3(argNum(x, 1, "Vector3.new"), argNum(y, 2, "Vector3.new"), argNum(z, 3, "Vector3.new"))
	end,
	zero = newV3(0, 0, 0),
	one = newV3(1, 1, 1),
	xAxis = newV3(1, 0, 0),
	yAxis = newV3(0, 1, 0),
	zAxis = newV3(0, 0, 1),
})
E.V3 = newV3

---------------------------------------------------------------- CFrame (positional subset)
local CFM = {}
local CFMT = makeType("CFrame", CFM, {
	X = function(c)
		return c.Position.X
	end,
	Y = function(c)
		return c.Position.Y
	end,
	Z = function(c)
		return c.Position.Z
	end,
	p = function(c)
		return c.Position
	end,
})
local function newCF(p)
	return new(CFMT, { Position = p })
end
CFMT.__add = function(a, b)
	return newCF(a.Position + b)
end
CFMT.__sub = function(a, b)
	return newCF(a.Position - b)
end
CFMT.__mul = function(a, b)
	if rtypeof(b) == "Vector3" then
		return a.Position + b
	end
	return newCF(a.Position + b.Position)
end
CFMT.__eq = function(a, b)
	return a.Position == b.Position
end
CFMT.__tostring = function(a)
	return tostring(a.Position) .. ", 1, 0, 0, 0, 1, 0, 0, 0, 1"
end
function CFM.Lerp(a, b, t)
	return newCF(a.Position:Lerp(b.Position, t))
end
function CFM.Inverse(a)
	return newCF(-a.Position)
end
CFrame = table.freeze({
	new = function(x, y, z)
		if rtypeof(x) == "Vector3" then
			return newCF(x)
		end
		return newCF(newV3(argNum(x, 1, "CFrame.new"), argNum(y, 2, "CFrame.new"), argNum(z, 3, "CFrame.new")))
	end,
	identity = newCF(newV3(0, 0, 0)),
})

---------------------------------------------------------------- Color3
local C3M = {}
local C3MT = makeType("Color3", C3M)
local function newC3(r, g, b)
	return new(C3MT, { R = r, G = g, B = b })
end
C3MT.__eq = function(a, b)
	return a.R == b.R and a.G == b.G and a.B == b.B
end
C3MT.__tostring = function(a)
	return fmt(a.R) .. ", " .. fmt(a.G) .. ", " .. fmt(a.B)
end
function C3M.Lerp(a, b, t)
	return newC3(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end
local function toHSV(r, g, b)
	local max, min = math.max(r, g, b), math.min(r, g, b)
	local d = max - min
	local h = 0
	if d > 0 then
		if max == r then
			h = ((g - b) / d) % 6
		elseif max == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
		h /= 6
	end
	return h, max == 0 and 0 or d / max, max
end
local function fromHSV(h, s, v)
	h = (h % 1) * 6
	local i = math.floor(h)
	local f = h - i
	local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
	i %= 6
	if i == 0 then
		return newC3(v, t, p)
	elseif i == 1 then
		return newC3(q, v, p)
	elseif i == 2 then
		return newC3(p, v, t)
	elseif i == 3 then
		return newC3(p, q, v)
	elseif i == 4 then
		return newC3(t, p, v)
	end
	return newC3(v, p, q)
end
function C3M.ToHSV(c)
	return toHSV(c.R, c.G, c.B)
end
function C3M.ToHex(c)
	local function b(x)
		return math.clamp(math.round(x * 255), 0, 255)
	end
	return string.format("%02X%02X%02X", b(c.R), b(c.G), b(c.B))
end
Color3 = table.freeze({
	new = function(r, g, b)
		return newC3(argNum(r, 1, "Color3.new"), argNum(g, 2, "Color3.new"), argNum(b, 3, "Color3.new"))
	end,
	fromRGB = function(r, g, b)
		return newC3(
			argNum(r, 1, "Color3.fromRGB") / 255,
			argNum(g, 2, "Color3.fromRGB") / 255,
			argNum(b, 3, "Color3.fromRGB") / 255
		)
	end,
	fromHSV = function(h, s, v)
		return fromHSV(argNum(h, 1, "Color3.fromHSV"), argNum(s, 2, "Color3.fromHSV"), argNum(v, 3, "Color3.fromHSV"))
	end,
	toHSV = function(c)
		return toHSV(c.R, c.G, c.B)
	end,
	fromHex = function(hex: string)
		hex = string.gsub(hex, "^#", "")
		if #hex == 3 then
			hex = string.gsub(hex, ".", "%0%0")
		end
		local n = tonumber(hex, 16)
		if #hex ~= 6 or not n then
			error("Unable to convert characters to hex value", 2)
		end
		return newC3(bit32.extract(n, 16, 8) / 255, bit32.extract(n, 8, 8) / 255, bit32.extract(n, 0, 8) / 255)
	end,
})
E.C3 = newC3

---------------------------------------------------------------- Sequences, ranges, rects
local CSKMT = makeType("ColorSequenceKeypoint", {})
ColorSequenceKeypoint = table.freeze({
	new = function(t, c)
		return new(CSKMT, { Time = argNum(t, 1, "ColorSequenceKeypoint.new"), Value = c })
	end,
})
local CSMT = makeType("ColorSequence", {})
CSMT.__eq = function(a, b)
	if #a.Keypoints ~= #b.Keypoints then
		return false
	end
	for i, k in a.Keypoints do
		local o = b.Keypoints[i]
		if k.Time ~= o.Time or k.Value ~= o.Value then
			return false
		end
	end
	return true
end
CSMT.__tostring = function(s)
	local parts = {}
	for _, k in s.Keypoints do
		table.insert(parts, fmt(k.Time) .. " " .. tostring(k.Value) .. " 0")
	end
	return table.concat(parts, " ")
end
ColorSequence = table.freeze({
	new = function(a, b)
		local kps
		if rtypeof(a) == "Color3" then
			b = b or a
			kps = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b) }
		elseif type(a) == "table" then
			kps = table.clone(a)
			table.sort(kps, function(x, y)
				return x.Time < y.Time
			end)
			if #kps < 2 or kps[1].Time ~= 0 or kps[#kps].Time ~= 1 then
				error("ColorSequence: requires at least 2 keypoints, starting at time 0 and ending at time 1", 2)
			end
		else
			error("ColorSequence.new: invalid arguments", 2)
		end
		return new(CSMT, { Keypoints = table.freeze(kps) })
	end,
})

local NSKMT = makeType("NumberSequenceKeypoint", {})
NumberSequenceKeypoint = table.freeze({
	new = function(t, v, e)
		return new(NSKMT, { Time = argNum(t, 1, "NumberSequenceKeypoint.new"), Value = argNum(v, 2, "NumberSequenceKeypoint.new"), Envelope = e or 0 })
	end,
})
local NSMT = makeType("NumberSequence", {})
NSMT.__eq = function(a, b)
	if #a.Keypoints ~= #b.Keypoints then
		return false
	end
	for i, k in a.Keypoints do
		local o = b.Keypoints[i]
		if k.Time ~= o.Time or k.Value ~= o.Value then
			return false
		end
	end
	return true
end
NumberSequence = table.freeze({
	new = function(a, b)
		local kps
		if type(a) == "number" then
			b = b or a
			kps = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) }
		elseif type(a) == "table" then
			kps = table.clone(a)
			table.sort(kps, function(x, y)
				return x.Time < y.Time
			end)
		else
			error("NumberSequence.new: invalid arguments", 2)
		end
		return new(NSMT, { Keypoints = table.freeze(kps) })
	end,
})

local NRMT = makeType("NumberRange", {})
NRMT.__eq = function(a, b)
	return a.Min == b.Min and a.Max == b.Max
end
NumberRange = table.freeze({
	new = function(a, b)
		a = argNum(a, 1, "NumberRange.new")
		b = b == nil and a or argNum(b, 2, "NumberRange.new")
		return new(NRMT, { Min = a, Max = b })
	end,
})

local RectMT = makeType("Rect", {}, {
	Width = function(r)
		return r.Max.X - r.Min.X
	end,
	Height = function(r)
		return r.Max.Y - r.Min.Y
	end,
})
RectMT.__eq = function(a, b)
	return a.Min == b.Min and a.Max == b.Max
end
RectMT.__tostring = function(r)
	return tostring(r.Min) .. ", " .. tostring(r.Max)
end
local function newRect(a, b, c, d)
	return new(RectMT, { Min = newV2(a, b), Max = newV2(c, d) })
end
Rect = table.freeze({
	new = function(a, b, c, d)
		if rtypeof(a) == "Vector2" then
			return newRect(a.X, a.Y, b.X, b.Y)
		end
		return newRect(a or 0, b or 0, c or 0, d or 0)
	end,
})
E.Rect = newRect

---------------------------------------------------------------- Random, DateTime
local RandM = {}
local RandMT = makeType("Random", RandM)
local function newRandom(seed)
	local self = setmetatable({}, RandMT)
	rawset(self, "_s", (seed or (os.clock() * 1e6)) % 2147483647)
	if rawget(self, "_s") <= 0 then
		rawset(self, "_s", 1)
	end
	return self
end
local function nextRaw(self)
	local s = (rawget(self, "_s") * 48271) % 2147483647
	rawset(self, "_s", s)
	return s / 2147483647
end
function RandM.NextNumber(self, a, b)
	a, b = a or 0, b or 1
	return a + (b - a) * nextRaw(self)
end
function RandM.NextInteger(self, a, b)
	return math.floor(a + (b - a + 1) * nextRaw(self))
end
function RandM.Clone(self)
	local c = newRandom(1)
	rawset(c, "_s", rawget(self, "_s"))
	return c
end
Random = table.freeze({ new = newRandom })

local DTMT = makeType("DateTime", {
	FormatUniversalTime = function(self, f)
		return os.date("!%Y-%m-%d %H:%M:%S", self.UnixTimestamp)
	end,
	FormatLocalTime = function(self, f)
		return os.date("%Y-%m-%d %H:%M:%S", self.UnixTimestamp)
	end,
	ToIsoDate = function(self)
		return os.date("!%Y-%m-%dT%H:%M:%SZ", self.UnixTimestamp)
	end,
})
DateTime = table.freeze({
	now = function()
		local ms = E.host.now()
		return new(DTMT, { UnixTimestamp = math.floor(ms / 1000), UnixTimestampMillis = math.floor(ms) })
	end,
	fromUnixTimestamp = function(s)
		return new(DTMT, { UnixTimestamp = math.floor(s), UnixTimestampMillis = math.floor(s * 1000) })
	end,
})

---------------------------------------------------------------- TweenInfo, Font (need Enum; filled after 02-enums)
E.makeType = makeType
E.newValue = new
