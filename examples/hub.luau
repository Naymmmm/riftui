-- Example hub. Every value here is demo data; wire the callbacks to your own game logic.
local Rift = loadstring(game:HttpGet("https://raw.githubusercontent.com/Naymmmm/riftui/main/public/Loader.luau"))()

-- Build inside xpcall so a mistake shows RiftUI's "Hub failed to load" card instead of
-- dying silently in the executor console.
xpcall(function()

local Hub = Rift:CreateHub({
	Name = "Rift Hub",
	Id = "rift-hub", -- files live in RiftUI/rift-hub/ (setup.json, configs/)
	Subtitle = "Baseplate",
	ToggleKey = Enum.KeyCode.RightShift,
	-- shown once, on first launch, after the toolbar key and theme steps
	Setup = {
		Title = "How do you play?",
		Description = "Sets the starting values. Everything can be changed later.",
		Options = {
			{ Type = "Dropdown", Name = "Play style", Flag = "SetupStyle", Options = { "Legit", "Balanced", "Blatant" }, Default = "Legit" },
			{ Type = "Toggle", Name = "Show watermark", Description = "FPS and ping in the corner", Flag = "SetupWatermark", Default = true },
			{ Type = "Toggle", Name = "Auto-load last config", Flag = "SetupAutoload" },
		},
	},
})

---------------------------------------------------------------- Combat
local Combat = Hub:Tab({ Name = "Combat", Icon = "crosshair", Description = "Aim assist · Triggerbot" })

local Aim = Combat:Section({ Name = "Aim Assist" })
Aim:Toggle({
	Name = "Enabled",
	Description = "Hold MB2 to lock on",
	Flag = "AimEnabled",
	Default = true,
	Callback = function(on)
		print("Aim assist:", on)
	end,
})
Aim:Toggle({ Name = "Team check", Flag = "AimTeamCheck", Default = true })
Aim:Slider({ Name = "Field of view", Flag = "AimFOV", Min = 10, Max = 400, Default = 248, Suffix = " px" })
Aim:Slider({ Name = "Smoothing", Flag = "AimSmooth", Min = 0, Max = 1, Step = 0.05, Default = 0.3 })
Aim:Dropdown({ Name = "Target part", Flag = "AimPart", Options = { "Head", "Torso", "HumanoidRootPart" }, Default = "Head" })

local Trigger = Combat:Section({ Name = "Triggerbot" })
Trigger:Toggle({ Name = "Enabled", Description = "Fires when the crosshair is on a target", Flag = "Trigger" })
Trigger:Keybind({
	Name = "Hold key",
	Flag = "TriggerKey",
	Default = Enum.UserInputType.MouseButton2,
	Mode = "Hold",
	Callback = function(held)
		print("Triggerbot held:", held)
	end,
})
Trigger:Slider({ Name = "Delay", Flag = "TriggerDelay", Min = 0, Max = 500, Default = 60, Suffix = " ms" })

---------------------------------------------------------------- Movement
local Movement = Hub:Tab({ Name = "Movement", Icon = "footprints", Description = "Speed, flight and jumps" })

local Fly = Movement:Section({ Name = "Flight" })
Fly:Toggle({ Name = "Fly", Flag = "Fly", Default = true })
Fly:Keybind({ Name = "Fly toggle", Flag = "FlyKey", Default = Enum.KeyCode.F, Mode = "Toggle", Callback = function(state)
	Rift.Flags.Fly:Set(state)
end })
Fly:Slider({ Name = "Fly speed", Flag = "FlySpeed", Min = 10, Max = 300, Default = 80 })

local Walk = Movement:Section({ Name = "Walking" })
Walk:Slider({ Name = "Walk speed", Flag = "WalkSpeed", Min = 16, Max = 120, Default = 16 })
Walk:Slider({ Name = "Jump power", Flag = "JumpPower", Min = 50, Max = 200, Default = 50 })
Walk:Toggle({ Name = "Infinite jump", Flag = "InfJump" })
Walk:Toggle({ Name = "Noclip", Flag = "Noclip" })

---------------------------------------------------------------- Visuals
local Visuals = Hub:Tab({ Name = "Visuals", Icon = "eye", Description = "ESP and world" })

local Esp = Visuals:Section({ Name = "Player ESP" })
Esp:Toggle({ Name = "Boxes", Flag = "EspBoxes" })
Esp:Toggle({ Name = "Names", Flag = "EspNames" })
Esp:ColorPicker({ Name = "Enemy color", Flag = "EspEnemy", Default = Color3.fromRGB(255, 92, 92) })
Esp:ColorPicker({ Name = "Team color", Flag = "EspTeam", Default = Color3.fromRGB(96, 200, 255) })
Esp:Dropdown({ Name = "Show", Flag = "EspShow", Multi = true, Options = { "Health", "Distance", "Weapon", "Tracers" }, Default = { "Health", "Distance" } })

local World = Visuals:Section({ Name = "World" })
World:Toggle({ Name = "Fullbright", Flag = "Fullbright" })
World:Slider({ Name = "Field of view", Flag = "CameraFOV", Min = 50, Max = 120, Default = 70, Suffix = "°" })

---------------------------------------------------------------- Players
local PlayersTab = Hub:Tab({ Name = "Players", Icon = "users", Description = "Spectate and teleport" })
local Target = PlayersTab:Section({ Name = "Target" })
Target:Dropdown({
	Name = "Player",
	Flag = "TargetPlayer",
	Options = { "Builderman", "Noob_2009", "xXSniperXx", "CoolKid42", "Guest_1337", "BaconHair", "Telamon", "Shedletsky", "Stickmasterluke", "ROBLOX" },
})
Target:Button({ Name = "Spectate", Callback = function()
	Hub:Notify({ Title = "Spectating", Content = tostring(Rift.Flags.TargetPlayer.Value), Icon = "eye" })
end })
Target:Button({ Name = "Teleport to player", Callback = function()
	Hub:Notify({ Title = "Teleported", Content = "Demo only: no character in the simulator.", Icon = "map-pin" })
end })
local Chat = PlayersTab:Section({ Name = "Chat" })
Chat:Input({ Name = "Spam message", Flag = "SpamText", Placeholder = "Type a message" })
Chat:Paragraph({ Title = "Heads up", Content = "Values on this page are demo data for the simulator." })

Hub:Notify({ Title = "Rift Hub loaded", Content = "Click a tile to open it. RightShift hides the toolbar.", Icon = "sparkles", Duration = 5 })

end, Rift.HandleError)
