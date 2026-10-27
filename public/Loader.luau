-- Set getgenv().riftcommit to a commit SHA before running this loader.
-- With no pin, main is used. A failed pin never falls back to another revision.
local REPOSITORY = "https://raw.githubusercontent.com/Naymmmm/riftui/"
local env = typeof(getgenv) == "function" and getgenv() or _G
local commit = env.riftcommit
if commit == nil then
	commit = "main"
elseif type(commit) ~= "string" or #commit < 7 or #commit > 40 or not string.match(commit, "^%x+$") then
	error("[RiftUI loader] riftcommit must be a 7–40 character hexadecimal commit SHA", 0)
end

local base = REPOSITORY .. commit .. "/public/"
local url = base .. "RiftUI.luau"
local ok, source = pcall(function()
	return game:HttpGet(url)
end)
if not ok then
	error("[RiftUI loader] couldn't fetch revision " .. commit .. ": " .. tostring(source), 0)
end
if type(source) ~= "string" or source == "" then
	error("[RiftUI loader] revision " .. commit .. " returned an empty library", 0)
end
local chunk, compileError = loadstring(source, "RiftUI@" .. commit)
if not chunk then
	error("[RiftUI loader] couldn't compile revision " .. commit .. ": " .. tostring(compileError), 0)
end
local loaded, Rift = pcall(chunk)
if not loaded then
	error("[RiftUI loader] revision " .. commit .. " failed to initialise: " .. tostring(Rift), 0)
end
if type(Rift) ~= "table" or type(Rift.CreateHub) ~= "function" then
	error("[RiftUI loader] revision " .. commit .. " didn't return a RiftUI library", 0)
end

Rift.AssetBase = base
-- Keep pinned icon sheets/shadows separate from assets cached for other revisions.
if commit ~= "main" then
	Rift.AssetCacheFolder = Rift.Folder .. "/assets/" .. commit
end
Rift.Commit = commit
return Rift
