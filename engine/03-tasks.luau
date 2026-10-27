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
