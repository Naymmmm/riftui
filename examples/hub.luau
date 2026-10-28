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
	KeybindList = true, -- floating card of bound keys; users can turn it off in Settings
	-- your own strings next to RiftUI's built-in Spanish, Portuguese, German and French
	Translations = {
		es = { ["Combat"] = "Combate", ["Aim Assist"] = "Asistencia de puntería", ["Movement"] = "Movimiento", ["Visuals"] = "Visuales", ["Players"] = "Jugadores", ["Stats"] = "Estadísticas" },
		pt = { ["Combat"] = "Combate", ["Aim Assist"] = "Mira assistida", ["Movement"] = "Movimento", ["Visuals"] = "Visuais", ["Players"] = "Jogadores", ["Stats"] = "Estatísticas" },
	},
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
local AimEnabled = Aim:Toggle({
	Name = "Enabled",
	Description = "Hold MB2 to lock on",
	Flag = "AimEnabled",
	Default = true,
	Callback = function(on)
		print("Aim assist:", on)
	end,
})
Aim:Segmented({ Name = "Mode", Flag = "AimMode", Options = { "Legit", "Rage" }, Default = "Legit" })
-- folds away while aim assist is off; its header still opens it
local Tuning = Aim:Group({ Name = "Tuning", DependsOn = AimEnabled })
Tuning:Toggle({ Name = "Team check", Flag = "AimTeamCheck", Default = true })
Tuning:Slider({ Name = "Field of view", Flag = "AimFOV", Min = 10, Max = 400, Default = 248, Suffix = " px", Description = "Radius around the crosshair that counts as on target" })
Tuning:Slider({ Name = "Smoothing", Flag = "AimSmooth", Min = 0, Max = 1, Step = 0.05, Default = 0.3, Description = "Higher is slower and looks more human" })
Tuning:Dropdown({ Name = "Target part", Flag = "AimPart", Options = { "Head", "Torso", "HumanoidRootPart" }, Default = "Head" })

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
Trigger:RangeSlider({ Name = "Delay", Flag = "TriggerDelay", Min = 0, Max = 500, Step = 10, Default = { 40, 120 }, Suffix = " ms", Description = "A random delay between the two values for each shot" })
Trigger:Stepper({ Name = "Burst", Flag = "TriggerBurst", Min = 1, Max = 5, Default = 1, Description = "Shots per trigger" })

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

-- A child window keeps the detailed ESP styling off the main page. Its controls save in
-- configs and show up in the command palette like any other control.
local EspStyle = Hub:Window({ Title = "ESP style", Description = "Colours, labels and limits", Icon = "palette", Width = 560, Height = 420 })

local Colours = EspStyle:Tab({ Name = "Colours", Icon = "palette" })
local Teams = Colours:Section({ Name = "Teams", Side = "Left" })
Teams:ColorPicker({ Name = "Enemy color", Flag = "EspEnemy", Default = Color3.fromRGB(255, 92, 92) })
Teams:ColorPicker({ Name = "Team color", Flag = "EspTeam", Default = Color3.fromRGB(96, 200, 255) })
Teams:Toggle({ Name = "Use team colours", Flag = "EspTeamColours", Default = true })
local Look = Colours:Section({ Name = "Boxes", Side = "Right" })
Look:Dropdown({ Name = "Box style", Flag = "EspBoxStyle", Options = { "Full", "Corners", "3D" }, Default = "Corners" })
Look:Slider({ Name = "Thickness", Flag = "EspThickness", Min = 1, Max = 4, Default = 1, Suffix = " px" })
Look:Slider({ Name = "Fill opacity", Flag = "EspFill", Min = 0, Max = 100, Default = 15, Suffix = "%" })

local Labels = EspStyle:Tab({ Name = "Labels", Icon = "tag" })
local Text = Labels:Section({ Name = "Text", Side = "Left" })
Text:Dropdown({ Name = "Show", Flag = "EspShow", Multi = true, Options = { "Health", "Distance", "Weapon", "Tracers" }, Default = { "Health", "Distance" } })
Text:Slider({ Name = "Text size", Flag = "EspTextSize", Min = 10, Max = 20, Default = 13 })
local Limits = Labels:Section({ Name = "Limits", Side = "Right" })
Limits:Slider({ Name = "Max distance", Flag = "EspDistance", Min = 100, Max = 5000, Step = 100, Default = 1500, Suffix = " studs" })
Limits:Toggle({ Name = "Hide behind walls", Flag = "EspOccluded" })

local Esp = Visuals:Section({ Name = "Player ESP" })
Esp:Toggle({ Name = "Boxes", Flag = "EspBoxes" })
Esp:Toggle({ Name = "Names", Flag = "EspNames" })
Esp:Button({ Name = "ESP style", Window = EspStyle })

local World = Visuals:Section({ Name = "World" })
World:Toggle({ Name = "Fullbright", Flag = "Fullbright" })
World:Slider({ Name = "Field of view", Flag = "CameraFOV", Min = 50, Max = 120, Default = 70, Suffix = "°" })

---------------------------------------------------------------- Players
local PlayersTab = Hub:Tab({ Name = "Players", Icon = "users", Description = "Spectate and teleport" })
-- a badge is for something worth a glance: here, how many players are in the server
local Players = game:GetService("Players")
local function countPlayers() PlayersTab:SetBadge(#Players:GetPlayers()) end
Players.PlayerAdded:Connect(countPlayers)
Players.PlayerRemoving:Connect(function() task.defer(countPlayers) end)
countPlayers()
local Target = PlayersTab:Section({ Name = "Target" })
-- fills itself from Players and keeps up as people join and leave
Target:PlayerPicker({ Name = "Player", Flag = "TargetPlayer" })
Target:Button({ Name = "Spectate", Callback = function()
	local p = Rift.Flags.TargetPlayer.Value
	Hub:Notify({ Title = "Spectating", Content = p and p.DisplayName or "Pick a player first", Icon = "eye" })
end })
Target:Button({ Name = "Teleport to player", Callback = function()
	Hub:Notify({ Title = "Teleported", Content = "Demo only: no character in the simulator.", Icon = "map-pin" })
end })
local Chat = PlayersTab:Section({ Name = "Chat" })
Chat:Input({ Name = "Spam message", Flag = "SpamText", Placeholder = "Type a message" })
Chat:Paragraph({ Title = "Heads up", Content = "Values on this page are demo data for the simulator." })

---------------------------------------------------------------- Stats
local StatsTab = Hub:Tab({ Name = "Stats", Icon = "activity", Description = "Session numbers, demo data" })
local Session = StatsTab:Section({ Name = "Session", Side = "Left" })
local Money = Session:Stat({ Name = "Money", Default = 12500, Delta = true, Suffix = " $" })
local Kills = Session:Stat({ Name = "Kills", Default = 0, Delta = true })
local Health = Session:Progress({ Name = "Health", Max = 100, Default = 82 })
local Ammo = Session:Progress({ Name = "Ammo", Max = 30, Default = 24, Segments = 6, Format = function(v, _, max) return v .. " / " .. max end })
local Perf = StatsTab:Section({ Name = "Performance", Side = "Right" })
local Fps = Perf:Sparkline({ Name = "Frame rate", Suffix = " fps", Points = 40 })
local Earn = Perf:Sparkline({ Name = "Money per minute", Suffix = " $" })
local Events = Perf:Console({ Name = "Events", Height = 120 })
Session:Toggle({ Name = "Show watermark", Description = "Name, FPS, ping and time in the corner", Callback = function(on) Hub:SetWatermark(on) end })

-- demo numbers that move on their own
task.spawn(function()
	local RunService = game:GetService("RunService")
	local frames, last, money = 0, os.clock(), 12500
	RunService.RenderStepped:Connect(function() frames += 1 end)
	while task.wait(1) do
		local now = os.clock()
		Fps:Push(math.floor(frames / (now - last) + 0.5))
		frames, last = 0, now
		local earned = math.random(-40, 160)
		money += earned
		Money:Update(money)
		Earn:Push(earned * 60)
		Health:Set(math.clamp(Health.Value + math.random(-12, 9), 5, 100))
		Ammo:Set((Ammo.Value - 1) % 31)
		if math.random() < 0.3 then
			Kills:Update(Kills.Value + 1)
			Events:Log("Eliminated " .. ({ "builderman", "Noob_2009", "xXSniperXx" })[math.random(3)])
		elseif earned < 0 then
			Events:Log("Spent " .. -earned .. " $", "warn")
		end
	end
end)

Hub:Notify({ Title = "Rift Hub loaded", Content = "Click a tile to open it. F2 searches everything. RightShift hides the toolbar.", Icon = "sparkles", Duration = 5 })

end, Rift.HandleError)
