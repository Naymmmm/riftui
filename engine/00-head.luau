-- RiftSim engine: a Roblox client emulated in Luau. The host (browser or Lune) supplies
-- __HOST with sync, measure, print, warn, error, now, load, fs, http, clipboard, register.
local E = {}
E.host = __HOST
__HOST = nil
