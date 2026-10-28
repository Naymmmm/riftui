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
		if d.cls.name == "Player" and D[old].cls.name == "Players" then
			fireIf(D[old], "PlayerRemoving", inst)
		end
	end
	if newParent then
		local nd = D[newParent]
		table.insert(nd.children, inst)
		fireIf(nd, "ChildAdded", inst)
		if d.cls.name == "Player" and nd.cls.name == "Players" then
			fireIf(nd, "PlayerAdded", inst)
		end
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
	-- Destroyed text boxes cannot keep keyboard shortcuts blocked.
	if E.focusedTextBox == self then E.focusedTextBox = nil end
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
