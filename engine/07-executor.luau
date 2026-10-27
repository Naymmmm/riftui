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
