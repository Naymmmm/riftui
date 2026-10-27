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
