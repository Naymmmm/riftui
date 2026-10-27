-- 00-head.luau
-- RiftSim engine: a Roblox client emulated in Luau. The host (browser or Lune) supplies
-- __HOST with sync, measure, print, warn, error, now, load, fs, http, clipboard, register.
local E = {}
E.host = __HOST
__HOST = nil

-- 01-datatypes.luau
do
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

end
-- 02-enums.luau
do
-- Enum, EnumItem, plus TweenInfo and Font, which depend on enums.

local makeType, newValue = E.makeType, E.newValue

local DEFS = {
	KeyCode = "Unknown=0,Backspace=8,Tab=9,Clear=12,Return=13,Pause=19,Escape=27,Space=32,QuotedDouble=34,Hash=35,Dollar=36,Percent=37,Ampersand=38,Quote=39,LeftParenthesis=40,RightParenthesis=41,Asterisk=42,Plus=43,Comma=44,Minus=45,Period=46,Slash=47,Zero=48,One=49,Two=50,Three=51,Four=52,Five=53,Six=54,Seven=55,Eight=56,Nine=57,Colon=58,Semicolon=59,LessThan=60,Equals=61,GreaterThan=62,Question=63,At=64,LeftBracket=91,BackSlash=92,RightBracket=93,Caret=94,Underscore=95,Backquote=96,A=97,B=98,C=99,D=100,E=101,F=102,G=103,H=104,I=105,J=106,K=107,L=108,M=109,N=110,O=111,P=112,Q=113,R=114,S=115,T=116,U=117,V=118,W=119,X=120,Y=121,Z=122,LeftCurly=123,Pipe=124,RightCurly=125,Tilde=126,Delete=127,KeypadZero=256,KeypadOne=257,KeypadTwo=258,KeypadThree=259,KeypadFour=260,KeypadFive=261,KeypadSix=262,KeypadSeven=263,KeypadEight=264,KeypadNine=265,KeypadPeriod=266,KeypadDivide=267,KeypadMultiply=268,KeypadMinus=269,KeypadPlus=270,KeypadEnter=271,KeypadEquals=272,Up=273,Down=274,Right=275,Left=276,Insert=277,Home=278,End=279,PageUp=280,PageDown=281,F1=282,F2=283,F3=284,F4=285,F5=286,F6=287,F7=288,F8=289,F9=290,F10=291,F11=292,F12=293,F13=294,F14=295,F15=296,NumLock=300,CapsLock=301,ScrollLock=302,RightShift=303,LeftShift=304,RightControl=305,LeftControl=306,RightAlt=307,LeftAlt=308,RightMeta=309,LeftMeta=310,LeftSuper=311,RightSuper=312,Mode=313,Compose=314,Help=315,Print=316,SysReq=317,Break=318,Menu=319,Power=320,Euro=321,Undo=322,ButtonX=1000,ButtonY=1001,ButtonA=1002,ButtonB=1003,ButtonR1=1004,ButtonL1=1005,ButtonR2=1006,ButtonL2=1007,ButtonR3=1008,ButtonL3=1009,ButtonStart=1010,ButtonSelect=1011,DPadLeft=1012,DPadRight=1013,DPadUp=1014,DPadDown=1015,Thumbstick1=1016,Thumbstick2=1017",
	UserInputType = "MouseButton1=0,MouseButton2=1,MouseButton3=2,MouseWheel=3,MouseMovement=4,Touch=7,Keyboard=8,Focus=9,Accelerometer=10,Gyro=11,Gamepad1=12,Gamepad2=13,Gamepad3=14,Gamepad4=15,Gamepad5=16,Gamepad6=17,Gamepad7=18,Gamepad8=19,TextInput=20,InputMethod=21,None=22",
	UserInputState = "Begin=0,Change=1,End=2,Cancel=3,None=4",
	Font = "Legacy=0,Arial=1,ArialBold=2,SourceSans=3,SourceSansBold=4,SourceSansLight=5,SourceSansItalic=6,Bodoni=7,Garamond=8,Cartoon=9,Code=10,Highway=11,SciFi=12,Arcade=13,Fantasy=14,Antique=15,SourceSansSemibold=16,Gotham=17,GothamMedium=18,GothamBold=19,GothamBlack=20,AmaticSC=21,Bangers=22,Creepster=23,DenkOne=24,Fondamento=25,FredokaOne=26,GrenzeGotisch=27,IndieFlower=28,JosefinSans=29,Jura=30,Kalam=31,LuckiestGuy=32,Merriweather=33,Michroma=34,Nunito=35,Oswald=36,PatrickHand=37,PermanentMarker=38,Roboto=39,RobotoCondensed=40,RobotoMono=41,Sarpanch=42,SpecialElite=43,TitilliumWeb=44,Ubuntu=45,BuilderSans=46,BuilderSansMedium=47,BuilderSansBold=48,BuilderSansExtraBold=49,Arimo=50,ArimoBold=51,Unknown=100",
	FontWeight = "Thin=100,ExtraLight=200,Light=300,Regular=400,Medium=500,SemiBold=600,Bold=700,ExtraBold=800,Heavy=900",
	FontStyle = "Normal=0,Italic=1",
	TextXAlignment = "Left=0,Right=1,Center=2",
	TextYAlignment = "Top=0,Center=1,Bottom=2",
	TextTruncate = "None=0,AtEnd=1,SplitWord=2",
	TextDirection = "Auto=0,LeftToRight=1,RightToLeft=2",
	FillDirection = "Horizontal=0,Vertical=1",
	HorizontalAlignment = "Center=0,Left=1,Right=2",
	VerticalAlignment = "Center=0,Top=1,Bottom=2",
	SortOrder = "Name=0,Custom=1,LayoutOrder=2",
	AutomaticSize = "None=0,X=1,Y=2,XY=3",
	SizeConstraint = "RelativeXY=0,RelativeXX=1,RelativeYY=2",
	ScaleType = "Stretch=0,Slice=1,Tile=2,Fit=3,Crop=4",
	EasingStyle = "Linear=0,Sine=1,Back=2,Quad=3,Quart=4,Quint=5,Bounce=6,Elastic=7,Exponential=8,Circular=9,Cubic=10",
	EasingDirection = "In=0,Out=1,InOut=2",
	PlaybackState = "Begin=0,Delayed=1,Playing=2,Paused=3,Completed=4,Cancelled=5",
	ZIndexBehavior = "Global=0,Sibling=1",
	ScrollingDirection = "X=1,Y=2,XY=4",
	ScrollBarInset = "None=0,ScrollBar=1,Always=2",
	VerticalScrollBarPosition = "Right=0,Left=1",
	ElasticBehavior = "WhenScrollable=0,Always=1,Never=2",
	ApplyStrokeMode = "Contextual=0,Border=1",
	LineJoinMode = "Round=0,Bevel=1,Miter=2",
	BorderMode = "Outline=0,Middle=1,Inset=2",
	AspectType = "FitWithinMaxSize=0,ScaleWithParentSize=1",
	DominantAxis = "Width=0,Height=1",
	StartCorner = "TopLeft=0,TopRight=1,BottomLeft=2,BottomRight=3",
	UIFlexAlignment = "None=0,Fill=1,SpaceAround=2,SpaceBetween=3,SpaceEvenly=4",
	ItemLineAlignment = "Automatic=0,Start=1,Center=2,End=3,Stretch=4",
	UIFlexMode = "None=0,Grow=1,Shrink=2,Fill=3,Custom=4",
	ResamplerMode = "Default=0,Pixelated=1",
	MouseBehavior = "Default=0,LockCenter=1,LockCurrentPosition=2",
	TextInputType = "Default=0,NoSuggestions=1,Number=2,Email=3,Phone=4,Password=5,PasswordShown=6,Username=7,OneTimePassword=8",
	ScreenInsets = "None=0,DeviceSafeInsets=1,CoreUISafeInsets=2,TopbarSafeInsets=3",
	SafeAreaCompatibility = "None=0,FullscreenExtension=1",
	CoreGuiType = "PlayerList=0,Health=1,Backpack=2,Chat=3,All=4,EmotesMenu=5,SelfView=6,Captures=7",
	SelectionBehavior = "Escape=0,Stop=1",
	HttpContentType = "ApplicationJson=0,ApplicationXml=1,ApplicationUrlEncoded=2,TextPlain=3,TextXml=4",
	ButtonStyle = "Custom=0,RobloxButtonDefault=1,RobloxButton=2,RobloxRoundButton=3,RobloxRoundDefaultButton=4,RobloxRoundDropdownButton=5",
	FrameStyle = "Custom=0,ChatBlue=1,RobloxSquare=2,RobloxRound=3,ChatGreen=4,ChatRed=5,DropShadow=6",
	ThumbnailType = "HeadShot=0,AvatarBust=1,AvatarThumbnail=2",
	ThumbnailSize = "Size48x48=0,Size180x180=1,Size420x420=2,Size60x60=3,Size100x100=4,Size150x150=5,Size352x352=6",
	HumanoidStateType = "FallingDown=0,Running=8,RunningNoPhysics=10,Climbing=12,StrafingNoPhysics=11,Ragdoll=1,GettingUp=2,Jumping=3,Landed=7,Flying=6,Freefall=5,Seated=13,PlatformStanding=14,Dead=15,Swimming=4,Physics=16,None=18",
	Material = "Plastic=256,SmoothPlastic=272,Neon=288,Wood=512,Glass=1568,ForceField=1584,Metal=1088",
	CameraType = "Fixed=0,Attach=1,Watch=2,Track=3,Follow=4,Custom=5,Scriptable=6,Orbital=7",
}

local EnumItemM = {}
local EnumItemMT = makeType("EnumItem", EnumItemM)
EnumItemMT.__tostring = function(item)
	return "Enum." .. item.EnumType._name .. "." .. item.Name
end
function EnumItemM.IsA(item, name)
	return item.EnumType._name == name
end

local EnumTypeM = {}
local EnumTypeMT = { __type = "Enum" }
EnumTypeMT.__index = function(self, key)
	local item = rawget(self, "_items")[key]
	if item then
		return item
	end
	local m = EnumTypeM[key]
	if m then
		return m
	end
	error(tostring(key) .. " is not a valid member of \"Enum." .. rawget(self, "_name") .. "\"", 2)
end
EnumTypeMT.__newindex = function()
	error("Enums are read-only", 2)
end
EnumTypeMT.__tostring = function(self)
	return rawget(self, "_name")
end
function EnumTypeM.GetEnumItems(self)
	local list = table.clone(rawget(self, "_list"))
	return list
end
function EnumTypeM.FromName(self, name)
	return rawget(self, "_items")[name]
end
function EnumTypeM.FromValue(self, value)
	return rawget(self, "_byValue")[value]
end

local enums = {}
for name, spec in DEFS do
	local et = setmetatable({ _name = name, _items = {}, _byValue = {}, _list = {} }, EnumTypeMT)
	for pair in string.gmatch(spec, "[^,]+") do
		local n, v = string.match(pair, "^(%w+)=(%-?%d+)$")
		local value = tonumber(v) :: number
		local item = newValue(EnumItemMT, { Name = n, Value = value, EnumType = et })
		rawget(et, "_items")[n] = item
		if rawget(et, "_byValue")[value] == nil then
			rawget(et, "_byValue")[value] = item
		end
		table.insert(rawget(et, "_list"), item)
	end
	table.sort(rawget(et, "_list"), function(a, b)
		return a.Value < b.Value
	end)
	enums[name] = et
end

local EnumsMT = { __type = "Enums" }
EnumsMT.__index = function(_, key)
	if key == "GetEnums" then
		return function()
			local list = {}
			for _, e in enums do
				table.insert(list, e)
			end
			return list
		end
	end
	local e = enums[key]
	if e then
		return e
	end
	error(tostring(key) .. " is not a valid member of \"Enum\"", 2)
end
EnumsMT.__newindex = function()
	error("Enums are read-only", 2)
end
Enum = setmetatable({}, EnumsMT)
E.enums = enums

-- Coerce a number, string or EnumItem into an item of the named enum.
function E.coerceEnum(enumName: string, v: any): any
	local et = enums[enumName]
	local t = E.typeof(v)
	if t == "EnumItem" then
		if v.EnumType == et then
			return v
		end
		return nil
	elseif t == "number" then
		return rawget(et, "_byValue")[v]
	elseif t == "string" then
		return rawget(et, "_items")[v]
	end
	return nil
end

---------------------------------------------------------------- TweenInfo
local TweenInfoMT = makeType("TweenInfo", {})
TweenInfoMT.__tostring = function(t)
	return string.format(
		"Time:%s DelayTime:%s RepeatCount:%d Reverses:%s EasingDirection:%s EasingStyle:%s",
		E.fmt(t.Time),
		E.fmt(t.DelayTime),
		t.RepeatCount,
		tostring(t.Reverses),
		t.EasingDirection.Name,
		t.EasingStyle.Name
	)
end
TweenInfo = table.freeze({
	new = function(time, style, direction, repeatCount, reverses, delay)
		return newValue(TweenInfoMT, {
			Time = time or 1,
			EasingStyle = style and E.coerceEnum("EasingStyle", style) or enums.EasingStyle.Quad,
			EasingDirection = direction and E.coerceEnum("EasingDirection", direction) or enums.EasingDirection.Out,
			RepeatCount = repeatCount or 0,
			Reverses = reverses or false,
			DelayTime = delay or 0,
		})
	end,
})

---------------------------------------------------------------- Font
local FontM = {}
local FontMT = makeType("Font", FontM, {
	Bold = function(f)
		return f.Weight.Value >= 700
	end,
})
FontMT.__eq = function(a, b)
	return a.Family == b.Family and a.Weight == b.Weight and a.Style == b.Style
end
FontMT.__tostring = function(f)
	return string.format("Font { Family = %s, Weight = %s, Style = %s }", f.Family, f.Weight.Name, f.Style.Name)
end
local function newFont(family: string, weight, style)
	return newValue(FontMT, {
		Family = family,
		Weight = weight and E.coerceEnum("FontWeight", weight) or enums.FontWeight.Regular,
		Style = style and E.coerceEnum("FontStyle", style) or enums.FontStyle.Normal,
	})
end
local FAMILY = function(name)
	return "rbxasset://fonts/families/" .. name .. ".json"
end
-- Enum.Font name -> family file, weight, style
local ENUM_FONTS = {
	Legacy = { "LegacyArial", 400 },
	Arial = { "Arial", 400 },
	ArialBold = { "Arial", 700 },
	SourceSans = { "SourceSansPro", 400 },
	SourceSansBold = { "SourceSansPro", 700 },
	SourceSansSemibold = { "SourceSansPro", 600 },
	SourceSansLight = { "SourceSansPro", 300 },
	SourceSansItalic = { "SourceSansPro", 400, 1 },
	Bodoni = { "AccanthisADFStd", 400 },
	Garamond = { "Guru", 400 },
	Cartoon = { "ComicNeueAngular", 400 },
	Code = { "Inconsolata", 400 },
	Highway = { "HighwayGothic", 400 },
	SciFi = { "Zekton", 400 },
	Arcade = { "PressStart2P", 400 },
	Fantasy = { "Balthazar", 400 },
	Antique = { "Kaushan Script", 400 },
	Gotham = { "GothamSSm", 400 },
	GothamMedium = { "GothamSSm", 500 },
	GothamBold = { "GothamSSm", 700 },
	GothamBlack = { "GothamSSm", 900 },
	BuilderSans = { "BuilderSans", 400 },
	BuilderSansMedium = { "BuilderSans", 500 },
	BuilderSansBold = { "BuilderSans", 700 },
	BuilderSansExtraBold = { "BuilderSans", 800 },
	Arimo = { "Arimo", 400 },
	ArimoBold = { "Arimo", 700 },
}
function E.fontFromEnum(item)
	local spec = ENUM_FONTS[item.Name]
	if spec then
		return newFont(FAMILY(spec[1]), spec[2], spec[3] or 0)
	end
	return newFont(FAMILY(item.Name), 400, 0)
end
-- Best Enum.Font for a FontFace (used to keep TextLabel.Font in sync).
function E.enumFromFont(font)
	local fam = string.match(font.Family, "families/(.-)%.json$")
	if not fam then
		return enums.Font.Unknown
	end
	local best
	for name, spec in ENUM_FONTS do
		if spec[1] == fam and spec[2] == font.Weight.Value then
			return enums.Font[name]
		elseif spec[1] == fam and not best then
			best = enums.Font[name]
		end
	end
	if best then
		return best
	end
	local ok, item = pcall(function()
		return enums.Font[fam]
	end)
	return ok and item or enums.Font.Unknown
end
Font = table.freeze({
	new = function(family, weight, style)
		if type(family) ~= "string" then
			error("Font.new: family must be a string", 2)
		end
		return newFont(family, weight, style)
	end,
	fromEnum = function(item)
		return E.fontFromEnum(E.coerceEnum("Font", item))
	end,
	fromName = function(name, weight, style)
		return newFont(FAMILY(name), weight, style)
	end,
	fromId = function(id, weight, style)
		return newFont("rbxassetid://" .. tostring(id), weight, style)
	end,
})
E.newFont = newFont

end
-- 03-tasks.luau
do
-- Task scheduler and RBXScriptSignal. Everything runs on coroutines resumed by step(),
-- which the host calls once per rendered frame.

local host = E.host
local makeType, newValue = E.makeType, E.newValue

E.clock = 0 -- simulated seconds since the game started
local waiting = {} -- array of { thread, resumeAt, startedAt, fn?, args? }
local deferred = {} -- array of { thread, args }

local function report(err, thread)
	local msg = tostring(err)
	local trace = debug.traceback(thread, nil, 1) or ""
	host.error(msg, trace)
end
E.report = report

local function resume(thread, ...)
	local ok, err = coroutine.resume(thread, ...)
	if not ok then
		report(err, thread)
	end
	return ok
end
E.resume = resume

local function asThread(f)
	if type(f) == "thread" then
		return f
	end
	if type(f) ~= "function" then
		error("invalid argument #1 (function or thread expected, got " .. E.typeof(f) .. ")", 3)
	end
	return coroutine.create(f)
end

task = {}

function task.spawn(f, ...)
	local thread = asThread(f)
	resume(thread, ...)
	return thread
end

function task.defer(f, ...)
	local thread = asThread(f)
	table.insert(deferred, { thread, table.pack(...) })
	return thread
end

function task.delay(t, f, ...)
	local thread = asThread(f)
	table.insert(waiting, { thread, E.clock + math.max(tonumber(t) or 0, 0), E.clock, args = table.pack(...) })
	return thread
end

function task.wait(t)
	local thread = coroutine.running()
	if not coroutine.isyieldable() then
		error("task.wait can only be called from a coroutine (scripts and callbacks run in one)", 2)
	end
	table.insert(waiting, { thread, E.clock + math.max(tonumber(t) or 0, 0), E.clock })
	return coroutine.yield()
end

function task.cancel(thread)
	for i = #waiting, 1, -1 do
		if waiting[i][1] == thread then
			table.remove(waiting, i)
		end
	end
	for i = #deferred, 1, -1 do
		if deferred[i][1] == thread then
			table.remove(deferred, i)
		end
	end
	if coroutine.status(thread) == "suspended" then
		coroutine.close(thread)
	end
end

function task.synchronize() end
function task.desynchronize() end
task = table.freeze(task)

function wait(t)
	local elapsed = task.wait(t or 0.03)
	return elapsed, E.clock
end
function spawn(f)
	task.defer(f)
end
function delay(t, f)
	task.delay(t, f)
end
function tick()
	return host.now() / 1000
end
function time()
	return E.clock
end
function elapsedTime()
	return E.clock
end

-- Advance the clock and resume due threads; deferred threads run until none remain.
function E.runScheduler(dt)
	E.clock += dt
	local now = E.clock
	local due = {}
	local i = 1
	while i <= #waiting do
		local w = waiting[i]
		if w[2] <= now then
			table.insert(due, w)
			table.remove(waiting, i)
		else
			i += 1
		end
	end
	table.sort(due, function(a, b)
		return a[2] < b[2]
	end)
	for _, w in due do
		local thread = w[1]
		if coroutine.status(thread) == "suspended" then
			if w.args then
				resume(thread, table.unpack(w.args, 1, w.args.n))
			else
				resume(thread, now - w[3], now)
			end
		end
	end
	E.flushDeferred()
end

function E.flushDeferred()
	local guard = 0
	while #deferred > 0 and guard < 10000 do
		local batch = deferred
		deferred = {}
		for _, d in batch do
			if coroutine.status(d[1]) == "suspended" then
				resume(d[1], table.unpack(d[2], 1, d[2].n))
			end
			guard += 1
		end
	end
end

---------------------------------------------------------------- Signals
local ConnM = {}
local ConnMT = makeType("RBXScriptConnection", ConnM)
ConnMT.__newindex = nil
ConnMT.__tostring = function()
	return "Connection"
end
local ConnGetters = {}
ConnMT.__index = function(self, k)
	if k == "Connected" then
		return rawget(self, "_on")
	end
	local m = ConnM[k]
	if m then
		return m
	end
	error(tostring(k) .. " is not a valid member of RBXScriptConnection", 2)
end
function ConnM.Disconnect(self)
	if not rawget(self, "_on") then
		return
	end
	rawset(self, "_on", false)
	local sig = rawget(self, "_sig")
	local list = rawget(sig, "_conns")
	local idx = table.find(list, self)
	if idx then
		-- copy-on-write so a Fire in progress keeps iterating the old list
		local copy = table.clone(list)
		table.remove(copy, idx)
		rawset(sig, "_conns", copy)
	end
	local onEmpty = rawget(sig, "_onDisconnect")
	if onEmpty and #rawget(sig, "_conns") == 0 then
		onEmpty()
	end
end

local SigM = {}
local SigMT = makeType("RBXScriptSignal", SigM)
SigMT.__tostring = function(self)
	return "Signal " .. (rawget(self, "_name") or "")
end
local function newSignal(name: string?)
	return setmetatable({ _conns = {}, _name = name }, SigMT)
end
local function connect(self, fn, once)
	if type(fn) ~= "function" then
		error("Attempt to connect failed: Passed value is not a function", 3)
	end
	local c = setmetatable({ _fn = fn, _sig = self, _on = true, _once = once }, ConnMT)
	local copy = table.clone(rawget(self, "_conns"))
	table.insert(copy, c)
	rawset(self, "_conns", copy)
	local onConnect = rawget(self, "_onConnect")
	if onConnect then
		onConnect()
	end
	return c
end
function SigM.Connect(self, fn)
	return connect(self, fn, false)
end
SigM.ConnectParallel = SigM.Connect
function SigM.Once(self, fn)
	return connect(self, fn, true)
end
function SigM.Wait(self)
	local thread = coroutine.running()
	local c
	c = connect(self, function(...)
		c:Disconnect()
		task.spawn(thread, ...)
	end, false)
	return coroutine.yield()
end
local function fire(self, ...)
	for _, c in rawget(self, "_conns") do
		if rawget(c, "_on") then
			if rawget(c, "_once") then
				c:Disconnect()
			end
			task.spawn(rawget(c, "_fn"), ...)
		end
	end
end
E.newSignal = newSignal
E.fire = fire
function E.hasListeners(sig)
	return sig ~= nil and #rawget(sig, "_conns") > 0
end

end
-- 04-instance.luau
do
-- The Instance tree. Instance state lives here in Luau; every change is also queued as an
-- op for the host, which keeps a mirror for layout, rendering, input and the Explorer.

local host = E.host
local typeof = E.typeof
local fire, newSignal = E.fire, E.newSignal

local D = setmetatable({}, { __mode = "k" }) -- proxy -> instance data
local byId = setmetatable({}, { __mode = "v" }) -- id -> proxy
local classes = {}
local nextId = 0
E.D = D
E.byId = byId
E.classes = classes

---------------------------------------------------------------- host op queue
local ops = {}
local SEP, REC = "\31", "\30"
E.dirty = false

local function clean(s: string): string
	if string.find(s, "[\30\31]") then
		return (string.gsub(s, "[\30\31]", ""))
	end
	return s
end

local function num(n: number): string
	if n ~= n then
		return "NaN"
	elseif n == math.huge then
		return "Infinity"
	elseif n == -math.huge then
		return "-Infinity"
	end
	return tostring(n)
end

local function encode(v: any): string
	local t = typeof(v)
	if t == "nil" then
		return "x"
	elseif t == "boolean" then
		return v and "b\0311" or "b\0310"
	elseif t == "number" then
		return "n" .. SEP .. num(v)
	elseif t == "string" then
		return "s" .. SEP .. clean(v)
	elseif t == "UDim2" then
		return "U2" .. SEP .. num(v.X.Scale) .. SEP .. num(v.X.Offset) .. SEP .. num(v.Y.Scale) .. SEP .. num(v.Y.Offset)
	elseif t == "UDim" then
		return "U" .. SEP .. num(v.Scale) .. SEP .. num(v.Offset)
	elseif t == "Vector2" then
		return "V2" .. SEP .. num(v.X) .. SEP .. num(v.Y)
	elseif t == "Vector3" then
		return "V3" .. SEP .. num(v.X) .. SEP .. num(v.Y) .. SEP .. num(v.Z)
	elseif t == "Color3" then
		return "C3" .. SEP .. num(v.R) .. SEP .. num(v.G) .. SEP .. num(v.B)
	elseif t == "EnumItem" then
		return "E" .. SEP .. rawget(v.EnumType, "_name") .. SEP .. v.Name .. SEP .. v.Value
	elseif t == "Instance" then
		return "I" .. SEP .. D[v].id
	elseif t == "Font" then
		return "F" .. SEP .. clean(v.Family) .. SEP .. v.Weight.Value .. SEP .. v.Style.Value
	elseif t == "Rect" then
		return "R" .. SEP .. num(v.Min.X) .. SEP .. num(v.Min.Y) .. SEP .. num(v.Max.X) .. SEP .. num(v.Max.Y)
	elseif t == "ColorSequence" then
		local parts = { "CS", tostring(#v.Keypoints) }
		for _, k in v.Keypoints do
			table.insert(parts, num(k.Time))
			table.insert(parts, num(k.Value.R))
			table.insert(parts, num(k.Value.G))
			table.insert(parts, num(k.Value.B))
		end
		return table.concat(parts, SEP)
	elseif t == "NumberSequence" then
		local parts = { "NS", tostring(#v.Keypoints) }
		for _, k in v.Keypoints do
			table.insert(parts, num(k.Time))
			table.insert(parts, num(k.Value))
		end
		return table.concat(parts, SEP)
	elseif t == "NumberRange" then
		return "NR" .. SEP .. num(v.Min) .. SEP .. num(v.Max)
	end
	return "s" .. SEP .. clean(tostring(v))
end
E.encode = encode

local function emit(s: string)
	ops[#ops + 1] = s
	E.dirty = true
end
E.emit = emit

---------------------------------------------------------------- classes
--[[
	defineClass(name, super, spec)
	spec.props = { { name, kind, default, flags? } }  flags: "r" readonly, "h" hidden (not sent)
	spec.events = { names }
	spec.methods = { name = fn(self, ...) }
	spec.creatable = bool, spec.service = bool
]]
local function defineClass(name: string, super: string?, spec)
	local parent = super and classes[super]
	local c = {
		name = name,
		super = parent,
		props = parent and table.clone(parent.props) or {},
		propOrder = parent and table.clone(parent.propOrder) or {},
		events = parent and table.clone(parent.events) or {},
		methods = parent and table.clone(parent.methods) or {},
		creatable = spec.creatable or false,
		noHost = spec.noHost or (parent and parent.noHost) or false,
		isA = parent and table.clone(parent.isA) or {},
		onCreate = spec.onCreate or (parent and parent.onCreate),
		onSet = spec.onSet or (parent and parent.onSet),
	}
	c.isA[name] = true
	for _, alias in spec.alsoIsA or {} do
		c.isA[alias] = true
	end
	for _, p in spec.props or {} do
		local def = { name = p[1], kind = p[2], default = p[3], readonly = p[4] == "r", hidden = p[4] == "h" }
		if not c.props[p[1]] then
			table.insert(c.propOrder, p[1])
		end
		c.props[p[1]] = def
	end
	for _, ev in spec.events or {} do
		c.events[ev] = true
	end
	for k, fn in spec.methods or {} do
		c.methods[k] = fn
	end
	classes[name] = c
	return c
end
E.defineClass = defineClass

---------------------------------------------------------------- value coercion
local function kindName(kind: string): string
	local enumName = string.match(kind, "^Enum:(.+)$")
	if enumName then
		return "Enum." .. enumName
	end
	return kind
end

local function coerce(def, v: any, instName: string): any
	local kind = def.kind
	local t = typeof(v)
	if kind == "any" then
		return v
	elseif kind == "bool" then
		if t == "boolean" then
			return v
		end
		if t == "nil" then
			return false
		end
		return v and true or false
	elseif kind == "number" or kind == "int" then
		if t == "number" then
			return kind == "int" and math.floor(v) or v
		end
		if t == "string" and tonumber(v) then
			return tonumber(v)
		end
	elseif kind == "string" or kind == "Content" then
		if t == "string" then
			return v
		end
		if t == "number" then
			return tostring(v)
		end
	elseif kind == "Instance" then
		if t == "nil" or t == "Instance" then
			return v
		end
	else
		local enumName = string.match(kind, "^Enum:(.+)$")
		if enumName then
			local item = E.coerceEnum(enumName, v)
			if item then
				return item
			end
		elseif t == kind then
			return v
		end
	end
	error(
		string.format(
			"Unable to assign property %s. %s expected, got %s",
			def.name,
			kindName(kind),
			t
		),
		4
	)
end

---------------------------------------------------------------- change notification
local pendingChanged = {} -- deferred Changed firings from layout results

local function propChanged(d, prop: string)
	local ps = d.psig and d.psig[prop]
	if ps then
		fire(ps)
	end
	local ch = d.signals.Changed
	if ch then
		fire(ch, prop)
	end
end
E.propChanged = propChanged

local function signalOf(d, name: string)
	local s = d.signals[name]
	if not s then
		s = newSignal(name)
		d.signals[name] = s
	end
	return s
end
E.signalOf = signalOf

local function fireIf(d, name: string, ...)
	local s = d.signals[name]
	if s then
		fire(s, ...)
	end
end
E.fireIf = fireIf

---------------------------------------------------------------- tree helpers
local function isDescendantOf(child, ancestor): boolean
	local p = D[child].parent
	while p do
		if p == ancestor then
			return true
		end
		p = D[p].parent
	end
	return false
end

local function eachDescendant(inst, fn)
	for _, c in D[inst].children do
		fn(c)
		eachDescendant(c, fn)
	end
end

local function fullName(inst): string
	local parts = {}
	local cur = inst
	while cur do
		local d = D[cur]
		if d.cls.name == "DataModel" then
			break
		end
		table.insert(parts, 1, d.props.Name)
		cur = d.parent
	end
	return table.concat(parts, ".")
end
E.fullName = fullName

local function setParent(inst, newParent)
	local d = D[inst]
	if d.parentLocked then
		error(
			string.format(
				"The Parent property of %s is locked, current parent: %s, new parent %s",
				d.props.Name,
				d.parent and D[d.parent].props.Name or "NULL",
				newParent and D[newParent].props.Name or "NULL"
			),
			3
		)
	end
	if newParent == inst or (newParent and isDescendantOf(newParent, inst)) then
		error(
			string.format(
				"Attempt to set parent of %s to %s would result in circular reference",
				fullName(inst),
				fullName(newParent)
			),
			3
		)
	end
	local old = d.parent
	if old == newParent then
		return
	end
	if old then
		local od = D[old]
		local idx = table.find(od.children, inst)
		if idx then
			table.remove(od.children, idx)
		end
		-- DescendantRemoving fires on every ancestor before the subtree leaves
		local anc = old
		while anc do
			local ad = D[anc]
			if ad.signals.DescendantRemoving then
				fire(ad.signals.DescendantRemoving, inst)
				eachDescendant(inst, function(x)
					fire(ad.signals.DescendantRemoving, x)
				end)
			end
			anc = ad.parent
		end
	end
	d.parent = newParent
	d.props.Parent = newParent
	if not d.cls.noHost then
		emit("p" .. SEP .. d.id .. SEP .. "Parent" .. SEP .. encode(newParent))
	end
	if old then
		fireIf(D[old], "ChildRemoved", inst)
	end
	if newParent then
		local nd = D[newParent]
		table.insert(nd.children, inst)
		fireIf(nd, "ChildAdded", inst)
		local anc = newParent
		while anc do
			local ad = D[anc]
			if ad.signals.DescendantAdded then
				fire(ad.signals.DescendantAdded, inst)
				eachDescendant(inst, function(x)
					fire(ad.signals.DescendantAdded, x)
				end)
			end
			anc = ad.parent
		end
	end
	fireIf(d, "AncestryChanged", inst, newParent)
	eachDescendant(inst, function(x)
		fireIf(D[x], "AncestryChanged", inst, newParent)
	end)
	propChanged(d, "Parent")
end

---------------------------------------------------------------- property access
local function setProp(inst, key, value, fromEngine: boolean?)
	local d = D[inst]
	if key == "Parent" then
		if value ~= nil and typeof(value) ~= "Instance" then
			error("Unable to assign property Parent. Instance expected, got " .. typeof(value), 3)
		end
		setParent(inst, value)
		return
	end
	local def = d.cls.props[key]
	if not def then
		error(string.format("%s is not a valid member of %s \"%s\"", tostring(key), d.cls.name, fullName(inst)), 3)
	end
	if def.readonly and not fromEngine then
		error(string.format("Unable to assign property %s. Property is read only", key), 3)
	end
	value = coerce(def, value, d.props.Name)
	local hook = d.cls.onSet and d.cls.onSet[key]
	if hook then
		value = hook(inst, d, value)
	end
	if d.props[key] == value then
		return
	end
	d.props[key] = value
	if not def.hidden and not d.cls.noHost then
		emit("p" .. SEP .. d.id .. SEP .. key .. SEP .. encode(value))
	end
	propChanged(d, key)
end
E.setProp = setProp

-- Set without validation or ops (values coming back from the host).
local function setFromHost(d, key, value)
	if d.props[key] == value then
		return
	end
	d.props[key] = value
	table.insert(pendingChanged, { d, key })
end

local LAYOUT_PROPS = {
	AbsolutePosition = true,
	AbsoluteSize = true,
	AbsoluteContentSize = true,
	AbsoluteCanvasSize = true,
	AbsoluteWindowSize = true,
	TextBounds = true,
	TextFits = true,
}

local InstanceMT -- set below
local function index(self, key)
	local d = D[self]
	if d == nil then
		error("attempt to index a destroyed or foreign Instance", 2)
	end
	local cls = d.cls
	if LAYOUT_PROPS[key] and cls.props[key] then
		E.ensureLayout()
		return d.props[key]
	end
	local v = d.props[key]
	if v ~= nil or cls.props[key] then
		return v
	end
	local m = cls.methods[key]
	if m then
		return m
	end
	if cls.events[key] then
		return signalOf(d, key)
	end
	if key == "Parent" then
		return d.parent
	end
	for _, c in d.children do
		if D[c].props.Name == key then
			return c
		end
	end
	error(string.format("%s is not a valid member of %s \"%s\"", tostring(key), cls.name, fullName(self)), 2)
end

local function newindex(self, key, value)
	setProp(self, key, value, false)
end

local function tostr(self)
	return D[self].props.Name
end

local function eq(a, b)
	return rawequal(a, b)
end

---------------------------------------------------------------- construction
local function newInstance(className: string, fromEngine: boolean?)
	local cls = classes[className]
	if not cls or (not cls.creatable and not fromEngine) then
		error("Unable to create an Instance of type \"" .. tostring(className) .. "\"", 3)
	end
	nextId += 1
	local proxy = newproxy(true)
	local mt = getmetatable(proxy)
	mt.__index = index
	mt.__newindex = newindex
	mt.__tostring = tostr
	mt.__type = "Instance"
	mt.__eq = eq
	mt.__metatable = "The metatable is locked"
	local props = {}
	for _, pname in cls.propOrder do
		local def = cls.props[pname]
		local dv = def.default
		if type(dv) == "function" then
			dv = dv()
		end
		props[pname] = dv
	end
	props.Name = className
	props.ClassName = className
	local d = {
		id = nextId,
		cls = cls,
		props = props,
		children = {},
		parent = nil,
		signals = {},
		psig = nil,
		attrs = {},
		mt = mt,
	}
	D[proxy] = d
	byId[nextId] = proxy
	if cls.noHost then
		if cls.onCreate then
			cls.onCreate(proxy, d)
		end
		return proxy
	end
	-- announce to the host with every property so its mirror and the Explorer are complete
	local parts = { "c" .. SEP .. nextId .. SEP .. className }
	for _, pname in cls.propOrder do
		local def = cls.props[pname]
		if not def.hidden and pname ~= "Parent" then
			table.insert(parts, "p" .. SEP .. nextId .. SEP .. pname .. SEP .. encode(props[pname]))
		end
	end
	emit(table.concat(parts, REC))
	if cls.onCreate then
		cls.onCreate(proxy, d)
	end
	return proxy
end
E.newInstance = newInstance

-- Typeof checks for Instances route through the shared __type field; IsA through the class.
function E.isInstance(v)
	return typeof(v) == "Instance" and D[v] ~= nil
end

---------------------------------------------------------------- Instance base class
local function checkSelf(self, method)
	if D[self] == nil then
		error("Expected ':' not '.' calling member function " .. method, 3)
	end
	return D[self]
end

local function destroy(self)
	local d = D[self]
	if d.destroyed then
		return
	end
	fireIf(d, "Destroying")
	for i = #d.children, 1, -1 do
		local c = d.children[i]
		if c then
			destroy(c)
		end
	end
	if d.parent then
		setParent(self, nil)
	end
	d.parentLocked = true
	d.destroyed = true
	for _, s in d.signals do
		for _, c in rawget(s, "_conns") do
			c:Disconnect()
		end
	end
	if d.psig then
		for _, s in d.psig do
			for _, c in rawget(s, "_conns") do
				c:Disconnect()
			end
		end
	end
	if not d.cls.noHost then
		emit("d" .. SEP .. d.id)
	end
end
E.destroy = destroy

local function clone(self)
	local d = D[self]
	if not d.props.Archivable then
		return nil
	end
	local c = newInstance(d.cls.name, true)
	local cd = D[c]
	for _, pname in d.cls.propOrder do
		local def = d.cls.props[pname]
		if pname ~= "Parent" and pname ~= "ClassName" and not def.readonly then
			local v = d.props[pname]
			if v ~= cd.props[pname] then
				setProp(c, pname, v, true)
			end
		end
	end
	for k, v in d.attrs do
		cd.attrs[k] = v
	end
	for _, child in d.children do
		local cc = clone(child)
		if cc then
			setParent(cc, c)
		end
	end
	return c
end

local function findFirstChild(self, name, recursive)
	local d = checkSelf(self, "FindFirstChild")
	for _, c in d.children do
		if D[c].props.Name == name then
			return c
		end
	end
	if recursive then
		for _, c in d.children do
			local f = findFirstChild(c, name, true)
			if f then
				return f
			end
		end
	end
	return nil
end

local ATTR_TYPES = {
	["nil"] = true,
	string = true,
	boolean = true,
	number = true,
	UDim = true,
	UDim2 = true,
	BrickColor = true,
	Color3 = true,
	Vector2 = true,
	Vector3 = true,
	CFrame = true,
	NumberSequence = true,
	ColorSequence = true,
	NumberRange = true,
	Rect = true,
	Font = true,
	EnumItem = true,
}

defineClass("Instance", nil, {
	props = {
		{ "Name", "string", "Instance" },
		{ "ClassName", "string", "Instance", "r" },
		{ "Archivable", "bool", true },
		{ "Parent", "Instance", nil },
	},
	events = {
		"Changed",
		"ChildAdded",
		"ChildRemoved",
		"DescendantAdded",
		"DescendantRemoving",
		"AncestryChanged",
		"AttributeChanged",
		"Destroying",
	},
	methods = {
		Destroy = function(self)
			checkSelf(self, "Destroy")
			destroy(self)
		end,
		Remove = function(self)
			setParent(self, nil)
		end,
		Clone = function(self)
			checkSelf(self, "Clone")
			return clone(self)
		end,
		ClearAllChildren = function(self)
			local d = checkSelf(self, "ClearAllChildren")
			for i = #d.children, 1, -1 do
				local c = d.children[i]
				if c then
					destroy(c)
				end
			end
		end,
		GetChildren = function(self)
			return table.clone(checkSelf(self, "GetChildren").children)
		end,
		GetDescendants = function(self)
			checkSelf(self, "GetDescendants")
			local list = {}
			eachDescendant(self, function(x)
				table.insert(list, x)
			end)
			return list
		end,
		FindFirstChild = findFirstChild,
		FindFirstChildOfClass = function(self, className)
			for _, c in checkSelf(self, "FindFirstChildOfClass").children do
				if D[c].cls.name == className then
					return c
				end
			end
			return nil
		end,
		FindFirstChildWhichIsA = function(self, className, recursive)
			for _, c in checkSelf(self, "FindFirstChildWhichIsA").children do
				if D[c].cls.isA[className] then
					return c
				end
			end
			if recursive then
				for _, c in D[self].children do
					local f = c:FindFirstChildWhichIsA(className, true)
					if f then
						return f
					end
				end
			end
			return nil
		end,
		FindFirstAncestor = function(self, name)
			local p = checkSelf(self, "FindFirstAncestor").parent
			while p do
				if D[p].props.Name == name then
					return p
				end
				p = D[p].parent
			end
			return nil
		end,
		FindFirstAncestorOfClass = function(self, className)
			local p = checkSelf(self, "FindFirstAncestorOfClass").parent
			while p do
				if D[p].cls.name == className then
					return p
				end
				p = D[p].parent
			end
			return nil
		end,
		FindFirstAncestorWhichIsA = function(self, className)
			local p = checkSelf(self, "FindFirstAncestorWhichIsA").parent
			while p do
				if D[p].cls.isA[className] then
					return p
				end
				p = D[p].parent
			end
			return nil
		end,
		FindFirstDescendant = function(self, name)
			return findFirstChild(self, name, true)
		end,
		WaitForChild = function(self, name, timeout)
			local found = findFirstChild(self, name)
			if found then
				return found
			end
			local start = E.clock
			local warned = false
			while true do
				task.wait()
				found = findFirstChild(self, name)
				if found then
					return found
				end
				if timeout and E.clock - start >= timeout then
					return nil
				end
				if not timeout and not warned and E.clock - start >= 5 then
					warned = true
					host.warn("Infinite yield possible on '" .. fullName(self) .. ":WaitForChild(\"" .. tostring(name) .. "\")'")
				end
			end
		end,
		IsA = function(self, className)
			return checkSelf(self, "IsA").cls.isA[className] == true
		end,
		IsDescendantOf = function(self, ancestor)
			return isDescendantOf(self, ancestor)
		end,
		IsAncestorOf = function(self, descendant)
			return isDescendantOf(descendant, self)
		end,
		GetFullName = function(self)
			return fullName(self)
		end,
		GetDebugId = function(self)
			return tostring(checkSelf(self, "GetDebugId").id)
		end,
		GetPropertyChangedSignal = function(self, prop)
			local d = checkSelf(self, "GetPropertyChangedSignal")
			if not d.cls.props[prop] and prop ~= "Parent" then
				error(tostring(prop) .. " is not a valid property name.", 2)
			end
			d.psig = d.psig or {}
			local s = d.psig[prop]
			if not s then
				s = newSignal(prop)
				d.psig[prop] = s
			end
			return s
		end,
		SetAttribute = function(self, name, value)
			local d = checkSelf(self, "SetAttribute")
			if type(name) ~= "string" then
				error("Attribute name must be a string", 2)
			end
			if not ATTR_TYPES[typeof(value)] then
				error(typeof(value) .. " is not a supported attribute type", 2)
			end
			if d.attrs[name] == value then
				return
			end
			d.attrs[name] = value
			fireIf(d, "AttributeChanged", name)
			local key = "@" .. name
			if d.psig and d.psig[key] then
				fire(d.psig[key])
			end
		end,
		GetAttribute = function(self, name)
			return checkSelf(self, "GetAttribute").attrs[name]
		end,
		GetAttributes = function(self)
			return table.clone(checkSelf(self, "GetAttributes").attrs)
		end,
		GetAttributeChangedSignal = function(self, name)
			local d = checkSelf(self, "GetAttributeChangedSignal")
			d.psig = d.psig or {}
			local key = "@" .. name
			local s = d.psig[key]
			if not s then
				s = newSignal(key)
				d.psig[key] = s
			end
			return s
		end,
		GetTags = function()
			return {}
		end,
		HasTag = function()
			return false
		end,
		AddTag = function() end,
		RemoveTag = function() end,
	},
})

Instance = table.freeze({
	new = function(className, parent)
		if type(className) ~= "string" then
			error("invalid argument #1 to 'new' (string expected, got " .. typeof(className) .. ")", 2)
		end
		local inst = newInstance(className, false)
		if parent ~= nil then
			setProp(inst, "Parent", parent, false)
		end
		return inst
	end,
	fromExisting = function(inst)
		return clone(inst)
	end,
})

---------------------------------------------------------------- host layout sync
local function applyLayout(res: string)
	if res == nil or res == "" then
		return
	end
	for rec in string.gmatch(res, "[^\30]+") do
		local f = string.split(rec, SEP)
		local kind = f[1]
		local inst = byId[tonumber(f[2]) :: number]
		local d = inst and D[inst]
		if d then
			if kind == "a" then
				setFromHost(d, "AbsolutePosition", E.V2(tonumber(f[3]), tonumber(f[4])))
				setFromHost(d, "AbsoluteSize", E.V2(tonumber(f[5]), tonumber(f[6])))
			elseif kind == "c" then
				setFromHost(d, "AbsoluteContentSize", E.V2(tonumber(f[3]), tonumber(f[4])))
			elseif kind == "w" then
				setFromHost(d, "AbsoluteCanvasSize", E.V2(tonumber(f[3]), tonumber(f[4])))
				setFromHost(d, "AbsoluteWindowSize", E.V2(tonumber(f[5]), tonumber(f[6])))
			elseif kind == "t" then
				setFromHost(d, "TextBounds", E.V2(tonumber(f[3]), tonumber(f[4])))
				setFromHost(d, "TextFits", f[5] == "1")
			end
		end
	end
end

local syncing = false
function E.ensureLayout()
	if syncing or (not E.dirty and #ops == 0) then
		return
	end
	syncing = true
	local payload = table.concat(ops, REC)
	table.clear(ops)
	E.dirty = false
	local ok, res = pcall(host.sync, payload)
	syncing = false
	if not ok then
		host.error("host sync failed: " .. tostring(res), "")
		return
	end
	applyLayout(res)
end

function E.firePendingChanged()
	local guard = 0
	while #pendingChanged > 0 and guard < 50 do
		local batch = pendingChanged
		pendingChanged = {}
		for _, p in batch do
			if not p[1].destroyed then
				propChanged(p[1], p[2])
			end
		end
		guard += 1
	end
end

function E.hasPendingOps()
	return #ops > 0
end

end
-- 05-classes.luau
do
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

end
-- 06-services.luau
do
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

end
-- 07-executor.luau
do
-- The sUNC surface RiftUI and hub scripts rely on: environment, filesystem, custom
-- assets, HTTP, clipboard and loadstring. Binary data crosses to the host as base64.

local host = E.host
local typeof = E.typeof
local D, newInstance, setProp = E.D, E.newInstance, E.setProp
local services = game

---------------------------------------------------------------- base64
local ALPHA = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local ENC = buffer.create(64)
local DEC = buffer.create(256)
buffer.fill(DEC, 0, 255)
for i = 1, 64 do
	local c = string.byte(ALPHA, i)
	buffer.writeu8(ENC, i - 1, c)
	buffer.writeu8(DEC, c, i - 1)
end

local function b64encode(s: string): string
	local n = #s
	local src = buffer.fromstring(s)
	local out = buffer.create(math.ceil(n / 3) * 4)
	local o = 0
	for i = 0, n - 1, 3 do
		local a = buffer.readu8(src, i)
		local b = i + 1 < n and buffer.readu8(src, i + 1) or 0
		local c = i + 2 < n and buffer.readu8(src, i + 2) or 0
		local v = a * 65536 + b * 256 + c
		buffer.writeu8(out, o, buffer.readu8(ENC, bit32.extract(v, 18, 6)))
		buffer.writeu8(out, o + 1, buffer.readu8(ENC, bit32.extract(v, 12, 6)))
		buffer.writeu8(out, o + 2, i + 1 < n and buffer.readu8(ENC, bit32.extract(v, 6, 6)) or 61)
		buffer.writeu8(out, o + 3, i + 2 < n and buffer.readu8(ENC, bit32.extract(v, 0, 6)) or 61)
		o += 4
	end
	return buffer.tostring(out)
end

local function b64decode(s: string): string
	s = string.gsub(s, "[^%w%+/=]", "")
	local n = #s
	if n == 0 then
		return ""
	end
	local src = buffer.fromstring(s)
	local pad = 0
	if string.sub(s, -2) == "==" then
		pad = 2
	elseif string.sub(s, -1) == "=" then
		pad = 1
	end
	local outLen = (n // 4) * 3 - pad
	local out = buffer.create(math.max(outLen, 0))
	local o = 0
	for i = 0, n - 4, 4 do
		local a = buffer.readu8(DEC, buffer.readu8(src, i))
		local b = buffer.readu8(DEC, buffer.readu8(src, i + 1))
		local c = buffer.readu8(DEC, buffer.readu8(src, i + 2))
		local d = buffer.readu8(DEC, buffer.readu8(src, i + 3))
		local v = bit32.lshift(a, 18) + bit32.lshift(bit32.band(b, 63), 12) + bit32.lshift(bit32.band(c, 63), 6) + bit32.band(d, 63)
		if o < outLen then
			buffer.writeu8(out, o, bit32.extract(v, 16, 8))
		end
		if o + 1 < outLen then
			buffer.writeu8(out, o + 1, bit32.extract(v, 8, 8))
		end
		if o + 2 < outLen then
			buffer.writeu8(out, o + 2, bit32.extract(v, 0, 8))
		end
		o += 3
	end
	return buffer.tostring(out)
end
E.b64encode = b64encode
E.b64decode = b64decode

local function receiveHostText(res)
	if type(res) ~= "string" or string.sub(res, 1, 15) ~= "\31RIFT_TRANSFER\31" then
		return res
	end
	local id, count = string.match(res, "^\31RIFT_TRANSFER\31(%d+)\31(%d+)$")
	if not id or not count then error("invalid host transfer", 3) end
	local chunks = {}
	for i = 0, tonumber(count) - 1 do
		chunks[i + 1] = host.transfer("read", id, i)
	end
	host.transfer("release", id, 0)
	return table.concat(chunks)
end

local function hostCall(fn, ...)
	local res = receiveHostText(fn(...))
	if type(res) == "string" and string.sub(res, 1, 4) == "ERR\31" then
		error(string.sub(res, 5), 3)
	end
	return res
end

---------------------------------------------------------------- environment
local genv = getfenv(1)
-- Roblox's _G and shared are plain writable tables shared between scripts
_G = {}
shared = {}
function getgenv()
	return genv
end
function getrenv()
	return genv
end
function getreg()
	return {}
end
function identifyexecutor()
	return "RiftSim", "1.0"
end
getexecutorname = identifyexecutor
function getthreadidentity()
	return 8
end
getidentity = getthreadidentity
getthreadcontext = getthreadidentity
function setthreadidentity() end
setidentity = setthreadidentity
function printidentity()
	host.print("Current identity is 8")
end
function isrbxactive()
	return true
end
iswindowactive = isrbxactive
function cloneref(x)
	return x
end
function compareinstances(a, b)
	return rawequal(a, b)
end
function checkcaller()
	return true
end
function newcclosure(f)
	return f
end
function iscclosure()
	return false
end
function islclosure(f)
	return type(f) == "function"
end
function getrawmetatable(v)
	if typeof(v) == "Instance" then
		return D[v].mt
	end
	return getmetatable(v)
end
function setrawmetatable(t, mt)
	return setmetatable(t, mt)
end
function setreadonly(t, ro)
	if ro then
		table.freeze(t)
	end
end
function isreadonly(t)
	return table.isfrozen(t)
end
makereadonly = function(t)
	table.freeze(t)
end
function queue_on_teleport() end
queueonteleport = queue_on_teleport
function getconnections(signal)
	local list = {}
	for _, c in rawget(signal, "_conns") or {} do
		table.insert(list, {
			Function = rawget(c, "_fn"),
			Enabled = rawget(c, "_on"),
			ForeignState = false,
			LuaConnection = true,
			Thread = nil,
			Disconnect = function()
				c:Disconnect()
			end,
			Disable = function()
				c:Disconnect()
			end,
			Enable = function() end,
			Fire = function(_, ...)
				task.spawn(rawget(c, "_fn"), ...)
			end,
		})
	end
	return list
end
function firesignal(signal, ...)
	E.fire(signal, ...)
end

-- gethui: a hidden folder that renders like CoreGui
local hidden = newInstance("Folder", true)
setProp(hidden, "Name", "RobloxGui", true)
setProp(hidden, "Parent", game:GetService("CoreGui"), true)
function gethui()
	return hidden
end
get_hidden_gui = gethui
function protectgui() end
protect_gui = protectgui
syn = { protect_gui = protectgui, unprotect_gui = function() end }

---------------------------------------------------------------- loadstring
function loadstring(source, chunkname)
	if type(source) ~= "string" then
		error("invalid argument #1 to 'loadstring' (string expected, got " .. typeof(source) .. ")", 2)
	end
	local res = host.load(source, chunkname or "=loadstring")
	if type(res) == "string" then
		return nil, res
	end
	-- chunks share the executor environment no matter how the host compiled them
	setfenv(res, genv)
	return res
end
function loadfile(path)
	return loadstring(readfile(path), "=" .. path)
end
function dofile(path)
	local fn, err = loadfile(path)
	if not fn then
		error(err, 2)
	end
	return fn()
end

---------------------------------------------------------------- filesystem
local function checkPath(path, fn)
	if type(path) ~= "string" then
		error("invalid argument #1 to '" .. fn .. "' (string expected, got " .. typeof(path) .. ")", 3)
	end
	return path
end
function writefile(path, content)
	checkPath(path, "writefile")
	if type(content) ~= "string" then
		content = tostring(content)
	end
	hostCall(host.fs, "write", path, b64encode(content))
end
function appendfile(path, content)
	checkPath(path, "appendfile")
	hostCall(host.fs, "append", path, b64encode(tostring(content)))
end
function readfile(path)
	checkPath(path, "readfile")
	return b64decode(hostCall(host.fs, "read", path, ""))
end
function isfile(path)
	return hostCall(host.fs, "isfile", checkPath(path, "isfile"), "") == "1"
end
function isfolder(path)
	return hostCall(host.fs, "isfolder", checkPath(path, "isfolder"), "") == "1"
end
function makefolder(path)
	hostCall(host.fs, "mkdir", checkPath(path, "makefolder"), "")
end
function delfile(path)
	hostCall(host.fs, "delfile", checkPath(path, "delfile"), "")
end
function delfolder(path)
	hostCall(host.fs, "delfolder", checkPath(path, "delfolder"), "")
end
function listfiles(path)
	local res = hostCall(host.fs, "list", checkPath(path or "", "listfiles"), "")
	if res == "" then
		return {}
	end
	return string.split(res, "\31")
end
function getcustomasset(path)
	checkPath(path, "getcustomasset")
	return hostCall(host.fs, "asset", path, "")
end
getsynasset = getcustomasset

---------------------------------------------------------------- HTTP
local function doRequest(opts)
	if type(opts) ~= "table" or type(opts.Url) ~= "string" then
		error("request expects a table with a Url field", 3)
	end
	local headers = opts.Headers or {}
	local body = opts.Body and b64encode(tostring(opts.Body)) or ""
	local res = receiveHostText(host.http(string.upper(opts.Method or "GET"), opts.Url, E.jsonEncode(headers), body))
	local status, b64, hdrs = string.match(res, "^(%-?%d+)\31([^\31]*)\31(.*)$")
	local code = tonumber(status) or 0
	local okHeaders, parsed = pcall(E.jsonDecode, hdrs or "{}")
	return {
		StatusCode = code,
		StatusMessage = code == 0 and "network error" or tostring(code),
		Success = code >= 200 and code < 300,
		Body = b64decode(b64 or ""),
		Headers = okHeaders and parsed or {},
	}
end
function request(opts)
	return doRequest(opts)
end
http_request = request
http = { request = request }
syn.request = request

local dm = E.classes.DataModel
dm.methods.HttpGet = function(_, url)
	local r = doRequest({ Url = url, Method = "GET" })
	if not r.Success then
		error("HttpGet failed (HTTP " .. r.StatusCode .. "): " .. string.sub(r.Body, 1, 500), 2)
	end
	return r.Body
end
dm.methods.HttpGetAsync = dm.methods.HttpGet
dm.methods.HttpPost = function(_, url, data, contentType)
	local r = doRequest({ Url = url, Method = "POST", Body = data, Headers = { ["Content-Type"] = contentType or "application/json" } })
	return r.Body
end
dm.methods.HttpPostAsync = dm.methods.HttpPost

---------------------------------------------------------------- misc
function setclipboard(text)
	host.clipboard(tostring(text))
end
toclipboard = setclipboard
setrbxclipboard = setclipboard
function getclipboard()
	return ""
end
crypt = {
	base64encode = b64encode,
	base64decode = b64decode,
	base64_encode = b64encode,
	base64_decode = b64decode,
	generatebytes = function(n)
		local t = {}
		for i = 1, n do
			t[i] = string.char(math.random(0, 255))
		end
		return b64encode(table.concat(t))
	end,
	generatekey = function()
		return crypt.generatebytes(32)
	end,
}
base64_encode = b64encode
base64_decode = b64decode
base64 = { encode = b64encode, decode = b64decode }

---------------------------------------------------------------- print/warn/error routing
local function join(...)
	local n = select("#", ...)
	local parts = table.create(n)
	for i = 1, n do
		parts[i] = tostring((select(i, ...)))
	end
	return table.concat(parts, " ")
end
function print(...)
	host.print(join(...))
end
function warn(...)
	host.warn(join(...))
end
rconsoleprint = function(s)
	host.print(tostring(s))
end
rconsoleclear = function() end
rconsolecreate = function() end
rconsoledestroy = function() end

-- Run a script source the way an executor does: compiled, then started on its own thread.
local engineLoadstring = loadstring
function E.run(source: string, chunkname: string)
	local fn, err = engineLoadstring(source, "=" .. chunkname)
	if not fn then
		host.error(tostring(err), "")
		return false
	end
	task.spawn(fn)
	E.ensureLayout()
	return true
end

end
-- 08-profile.luau
do
-- Executor profiles: the simulator can pretend to be a weaker executor. The host passes
-- "name=<identifyexecutor>;off=<globals to remove>;broken=<globals that misbehave>".

local spec = E.host.profile and E.host.profile() or ""
local name = string.match(spec, "name=([^;]*)")
local off = string.match(spec, "off=([^;]*)") or ""
local broken = string.match(spec, "broken=([^;]*)") or ""
local genv = getfenv(1)

local BROKEN = {
	-- returns nothing, like executors whose listfiles ignores subfolders
	listfiles = function()
		return {}
	end,
	-- exists but throws, like a stubbed function
	setclipboard = function()
		error("setclipboard is not supported", 2)
	end,
	request = function()
		error("request is not supported on this executor", 2)
	end,
}

for fn in string.gmatch(broken, "[^,]+") do
	if BROKEN[fn] then
		genv[fn] = BROKEN[fn]
	end
end
for fn in string.gmatch(off, "[^,]+") do
	genv[fn] = nil
end
if name and name ~= "" then
	local exec, version = string.match(name, "^(.-)%s+(%S+)$")
	exec = exec or name
	if genv.identifyexecutor then
		genv.identifyexecutor = function()
			return exec, version or "1.0"
		end
		if genv.getexecutorname then
			genv.getexecutorname = genv.identifyexecutor
		end
	end
end

end
-- 99-tail.luau
E.host.register(function(dt, events)
	local ok, err = pcall(E.step, dt, events)
	if not ok then
		E.host.error("engine step failed: " .. tostring(err), debug.traceback())
	end
	return 0
end, function(source, chunkname)
	return E.run(source, chunkname)
end)
