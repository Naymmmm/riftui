-- Deterministic loader checks: compile the fetched body and inspect requested URLs.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local source = fs.readFile("public/Loader.luau")
local checks = 0
local function check(value, message)
	assert(value, message)
	checks += 1
end
local function run(pin, body, failure)
	local requests = {}
	local env
	env = setmetatable({
		getgenv = function() return { riftcommit = pin } end,
		game = { HttpGet = function(_, url)
			table.insert(requests, url)
			if failure then error(failure) end
			return body or 'return { Version = "abc1234", Folder = "RiftUI", CreateHub = function() end }'
		end },
		loadstring = function(code, name)
			local ok, chunk = pcall(luau.load, code, { debugName = name, environment = env })
			if ok then return chunk end
			return nil, chunk
		end,
	}, { __index = getfenv() })
	local ok, result = pcall(luau.load(source, { environment = env }))
	return ok, result, requests
end
local sha = string.rep("a1", 20)
local ok, Rift, requests = run(sha)
check(ok, "pinned loader executes")
check(#requests == 1 and requests[1] == "https://raw.githubusercontent.com/Naymmmm/riftui/" .. sha .. "/public/RiftUI.luau", "fetches the exact pinned URL once")
check(Rift.Commit == sha and Rift.AssetBase == "https://raw.githubusercontent.com/Naymmmm/riftui/" .. sha .. "/public/", "library and assets use the same revision")
check(Rift.Version == string.sub(sha, 1, 7), "pinned version displays its commit hash")
check(Rift.AssetCacheFolder == "RiftUI/assets/" .. sha, "pins have isolated asset caches")
ok, Rift, requests = run(nil)
check(ok and Rift.Commit == "main" and string.find(requests[1], "/main/public/", 1, true), "unset pin uses main")
check(Rift.Version == "abc1234", "main retains the bundled build hash")
check(Rift.AssetCacheFolder == nil, "main keeps the existing asset cache")
ok, Rift, requests = run("abcdef1")
check(ok and Rift.Commit == "abcdef1", "accepts abbreviated hexadecimal commits")
for _, pin in { "main", "../main", "", "abcdef", string.rep("f", 41), 123, false } do
	local valid, err, urls = run(pin)
	check(not valid and #urls == 0 and string.find(err, "riftcommit", 1, true), "invalid pins stop before fetching")
end
ok, Rift, requests = run(sha, nil, "404 Not Found")
check(not ok and #requests == 1 and string.find(Rift, sha, 1, true), "missing revisions fail without falling back")
ok, Rift, requests = run(sha, "")
check(not ok and #requests == 1 and string.find(Rift, "empty library", 1, true), "rejects empty downloads")
ok, Rift = run(sha, "this isn't Luau")
check(not ok and string.find(Rift, "couldn't compile", 1, true), "reports compile errors")
ok, Rift = run(sha, 'error("broken revision")')
check(not ok and string.find(Rift, "failed to initialise", 1, true), "reports runtime errors")
ok, Rift = run(sha, "return {}")
check(not ok and string.find(Rift, "didn't return a RiftUI library", 1, true), "rejects non-library responses")
print(string.format("%d loader checks passed", checks))
