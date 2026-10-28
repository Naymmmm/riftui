-- RiftUI feature tour. Every feature in one hub, wired to demo data only: nothing here touches
-- the game. Paste it into an executor or RiftSim, enter the demo key DEMO, and look around.
local Rift = loadstring(game:HttpGet("https://raw.githubusercontent.com/Naymmmm/riftui/main/public/Loader.luau"))()

local HUB_ID = "rift-showcase"
local HUB_ICON = "sparkles"

---------------------------------------------------------------- key gate
-- A real gate sends the key to your server, which answers with the hub script:
--
--     local source = Rift:CreateAuth({ Name = "My Hub", Url = "https://auth.example.com/v1/script" })
--     if not source then return end
--     loadstring(source)()
--
-- This tour has no server, so Request stands in for one and the hub is built below.
local accepted = Rift:CreateAuth({
	Name = "Rift Showcase",
	Id = HUB_ID,
	HubIcon = HUB_ICON,
	Subtitle = "Enter your key to continue",
	Note = "This is a demo gate. The key is DEMO.",
	GetKeyUrl = "https://riftui.naymmm.lol/#auth",
	Discord = "https://discord.gg/your-invite",
	Request = function(key)
		task.wait(0.5) -- a server round trip
		if string.upper(key) == "DEMO" then return true, "-- your server would send the hub here" end
		return false, "Invalid key. The demo key is DEMO."
	end,
})
if not accepted then return end

-- Build inside xpcall so a mistake shows RiftUI's failure card instead of dying silently.
xpcall(function()

local Hub = Rift:CreateHub({
	Name = "Rift Showcase",
	Id = HUB_ID,
	Subtitle = "Feature tour",
	HubIcon = HUB_ICON,
	ToggleKey = Enum.KeyCode.RightShift,
	CommandKey = Enum.KeyCode.F2,
	Watermark = true,
	KeybindList = true,
	-- the card stays up while the tabs below are built, then hands over to the toolbar
	Loading = { Manual = true, Subtitle = "Building the tour" },
	Requirements = {
		Roster = { Name = "Player list", Test = function()
			local ok, list = pcall(function() return game:GetService("Players"):GetPlayers() end)
			return ok and type(list) == "table", "This executor can't read the player list"
		end },
	},
	Translations = {
		es = { ["Controls"] = "Controles", ["Text & data"] = "Texto y datos", ["Live"] = "En vivo", ["People"] = "Personas", ["Hub"] = "Hub" },
	},
	Setup = {
		Title = "Tune the tour",
		Description = "Shown once on first launch. Change these later in Settings.",
		Options = {
			{ Type = "Dropdown", Name = "Starting mode", Flag = "SetupMode", Options = { "Explore", "Build", "Practice" }, Default = "Explore" },
			{ Type = "Toggle", Name = "Start with demo data running", Flag = "SetupLive", Default = true },
		},
	},
})
local Flags = Rift.Flags

---------------------------------------------------------------- Controls
Hub:SetLoading("Adding controls", 0.15)
local Controls = Hub:Tab({ Name = "Controls", Icon = "sliders-horizontal", Description = "Every input control" })

local Basics = Controls:Section({ Name = "Basics", Side = "Left" })
local Status = Basics:Label("Nothing clicked yet.")
local clicks = 0
Basics:Button({ Name = "Click me", Description = "Updates the label above", Callback = function()
	clicks += 1
	Status:Set("Clicked " .. clicks .. (clicks == 1 and " time." or " times."))
end })
local Enabled = Basics:Toggle({ Name = "Feature enabled", Flag = "Enabled", Default = true, Description = "Turns the group below on and off" })
-- folds away while the toggle is off; its header still opens it by hand
local Tuning = Basics:Group({ Name = "Tuning", DependsOn = Enabled })
Tuning:Slider({ Name = "Strength", Flag = "Strength", Min = 0, Max = 100, Default = 40, Suffix = "%" })
Tuning:Slider({ Name = "Smoothing", Flag = "Smoothing", Min = 0, Max = 1, Step = 0.05, Default = 0.3, Description = "Hover any control with a description for help" })
Basics:Dropdown({ Name = "Mode", Flag = "Mode", Options = { "Explore", "Build", "Practice" }, Default = "Explore" })
Basics:Dropdown({ Name = "Layers", Flag = "Layers", Multi = true, Options = { "Grid", "Labels", "Outlines", "Shadows" }, Default = { "Grid", "Labels" } })

local More = Controls:Section({ Name = "More inputs", Side = "Right" })
More:Segmented({ Name = "Quality", Flag = "Quality", Options = { "Low", "Medium", "High" }, Default = "Medium" })
More:Stepper({ Name = "Copies", Flag = "Copies", Min = 1, Max = 8, Default = 2 })
More:RangeSlider({ Name = "Time window", Flag = "Window", Min = 0, Max = 60, Default = { 10, 30 }, Suffix = " s" })
More:Keybind({ Name = "Quick action", Flag = "QuickKey", Default = Enum.KeyCode.G, Mode = "Toggle", Callback = function(on)
	Hub:Notify({ Title = "Quick action", Content = on and "On" or "Off", Duration = 2 })
end })
More:Keybind({ Name = "Hold to preview", Flag = "PreviewKey", Default = Enum.KeyCode.H, Mode = "Hold" })
More:ColorPicker({ Name = "Highlight colour", Flag = "Highlight", Default = Color3.fromRGB(127, 178, 255) })

-- starts folded; click its header to open it, and the choice is remembered
local Extra = Controls:Section({ Name = "Folded by default", Side = "Right", Collapsed = true })
Extra:Input({ Name = "Profile name", Flag = "ProfileName", Placeholder = "Enter a name", Default = "Tour profile", MaxLength = 24 })
Extra:Input({ Name = "Seed", Flag = "Seed", Numeric = true, Default = "1234" })

---------------------------------------------------------------- Text & data
Hub:SetLoading("Adding text and lists", 0.35)
local Data = Hub:Tab({ Name = "Text & data", Icon = "database", Description = "Multiline input, lists and logs" })

local Notes = Data:Section({ Name = "Notes", Side = "Left" })
Notes:Input({
	Name = "Snippet",
	Flag = "Snippet",
	MultiLine = true,
	Lines = 6,
	Code = true,
	Default = 'print("Hello from the tour")\nfor i = 1, 3 do\n    print(i)\nend',
	Callback = function(text) print("Snippet is now " .. #string.split(text, "\n") .. " lines") end,
})
Notes:Paragraph({ Title = "Plain text", Content = "Paragraphs wrap to the column and grow with their content." })

local Bookmarks = Data:Section({ Name = "Bookmarks", Side = "Right" })
local Marks = Bookmarks:List({
	Name = "Saved spots",
	Columns = { "Name", "Note" },
	Widths = { 2, 3 },
	Items = { { "Lobby", "Where everyone spawns" }, { "Lookout", "Best view of the map" }, { "Garden", "Quiet corner" } },
	Removable = true,
	Placeholder = "No bookmarks yet",
	Callback = function(item) Hub:Notify({ Title = item[1], Content = item[2], Icon = "bookmark", Duration = 3 }) end,
	OnRemove = function(item) print("Removed bookmark", item[1]) end,
})
Bookmarks:Button({ Name = "Add bookmark", Callback = function()
	Marks:Add({ "Spot " .. (#Marks.Items + 1), "Added at " .. os.date("%H:%M:%S") })
end })
local Log = Bookmarks:Console({ Name = "Activity", Height = 110, MaxLines = 50 })
Log:Log("Tour started")

---------------------------------------------------------------- Live
Hub:SetLoading("Adding live widgets", 0.55)
local Live = Hub:Tab({ Name = "Live", Icon = "activity", Description = "Readouts fed by demo data" })
local Numbers = Live:Section({ Name = "Numbers", Side = "Left" })
local Coins = Numbers:Stat({ Name = "Coins", Default = 1200, Delta = true })
local Visitors = Numbers:Stat({ Name = "Visitors", Default = 0, Delta = true })
local Energy = Numbers:Progress({ Name = "Energy", Max = 100, Default = 70 })
local Steps = Numbers:Progress({ Name = "Steps", Max = 10, Default = 3, Segments = 5, Format = function(v, _, max) return v .. " / " .. max end })
local Running = Numbers:Toggle({ Name = "Run demo data", Flag = "LiveData", Default = true })
local Graphs = Live:Section({ Name = "Graphs", Side = "Right" })
local Fps = Graphs:Sparkline({ Name = "Frame rate", Suffix = " fps", Points = 40 })
local Rate = Graphs:Sparkline({ Name = "Coins per tick", Min = -50, Max = 150 })

---------------------------------------------------------------- People
Hub:SetLoading("Adding the player list", 0.7)
local People = Hub:Tab({ Name = "People", Icon = "users", Description = "Player picker and requirements" })
local Players = game:GetService("Players")
local function countPlayers() People:SetBadge(#Players:GetPlayers()) end
Players.PlayerAdded:Connect(countPlayers)
Players.PlayerRemoving:Connect(function() task.defer(countPlayers) end)
countPlayers()
-- locked behind the Roster requirement until its test passes
local Pick = People:Section({ Name = "Pick someone", Requires = "Roster" })
Pick:PlayerPicker({ Name = "Player", Flag = "Player", Callback = function(p)
	Log:Log("Picked " .. (p and p.DisplayName or "nobody"))
end })
Pick:Button({ Name = "Say hello", Callback = function()
	local p = Flags.Player.Value
	Hub:Notify({ Title = p and ("Hello, " .. p.DisplayName) or "Pick a player first", Icon = "hand", Duration = 3 })
end })

---------------------------------------------------------------- Hub
Hub:SetLoading("Adding hub tools", 0.85)
local Tools = Hub:Tab({ Name = "Hub", Icon = "layout-grid", Description = "Windows, themes, configs and more" })

-- a child window with its own tabs, opened from a button, with a Discord button in its header
local About = Hub:Window({ Title = "About the tour", Description = "Community and credits", Icon = "info", Width = 520, Height = 360 })
About:SocialButton({ Discord = "https://discord.gg/your-invite" })
local Credits = About:Tab({ Name = "Credits", Icon = "heart" })
Credits:Section({ Name = "Made with RiftUI" }):Paragraph({ Title = "Open source", Content = "RiftUI is licensed under MPL-2.0. This window has two tabs and a Discord button in its header." })
local Shortcuts = About:Tab({ Name = "Shortcuts", Icon = "keyboard" })
local Keys = Shortcuts:Section({ Name = "Keys" })
Keys:List({ Columns = { "Key", "Action" }, Selectable = false, Height = 110, Items = {
	{ "Right Shift", "Show or hide the toolbar" },
	{ "F2", "Search everything" },
	{ "G", "Quick action" },
	{ "H (hold)", "Preview" },
} })

local Windows = Tools:Section({ Name = "Windows & messages", Side = "Left" })
Windows:Button({ Name = "About the tour", Window = About })
Windows:Button({ Name = "Show a notification", Callback = function()
	Hub:Notify({ Title = "Saved", Content = "Hover to pause the timer, click to dismiss.", Icon = "check", Tone = Hub.Theme.Success })
end })
Windows:Button({ Name = "Reset values", Danger = true, Callback = function()
	Hub:Prompt({
		Title = "Reset the tour values?",
		Content = "Toggles, sliders and the mode go back to their defaults.",
		Buttons = {
			{ Text = "Cancel" },
			{ Text = "Reset", Primary = true, Callback = function()
				Flags.Enabled:Set(true)
				Flags.Strength:Set(40)
				Flags.Smoothing:Set(0.3)
				Flags.Mode:Set("Explore")
				Hub:Notify({ Title = "Values reset", Icon = "rotate-ccw", Duration = 3 })
			end },
		},
	})
end })
Windows:Button({ Name = "Search everything", Description = "Same as pressing F2", Callback = function() Hub:OpenCommandPalette() end })

local Look = Tools:Section({ Name = "Look & feel", Side = "Right" })
Look:Segmented({ Options = { "Graphite", "Ink", "Slate", "Ember" }, Default = Hub.ThemeName, Callback = function(name) Hub:SetTheme(name) end })
Look:Button({ Name = "Theme studio", Callback = function() Hub:OpenThemeStudio() end })
Look:Stepper({ Name = "Interface scale", Min = 0.8, Max = 1.2, Step = 0.1, Default = 1, Callback = function(v) Hub:SetScale(v) end })
Look:Segmented({ Name = "Language", Options = { "English", "Español" }, Default = "English", Callback = function(v) Hub:SetLanguage(v == "Español" and "es" or "en") end })
Look:Toggle({ Name = "Watermark", Default = true, Callback = function(on) Hub:SetWatermark(on) end })
Look:Toggle({ Name = "Keybind list", Default = true, Callback = function(on) Hub:SetKeybindList(on) end })

local Profiles = Tools:Section({ Name = "Configs & pins", Side = "Left" })
Profiles:Button({ Name = "Save config", Callback = function()
	local ok, err = Hub:SaveConfig("tour")
	Hub:Notify({ Title = ok and "Config saved" or "Couldn't save", Content = ok and "Saved as \"tour\"." or err, Duration = 3 })
end })
Profiles:Button({ Name = "Load config", Callback = function()
	local ok, err = Hub:LoadConfig("tour")
	Hub:Notify({ Title = ok and "Config loaded" or "Couldn't load", Content = ok and "Values restored." or err, Duration = 3 })
end })
Profiles:Button({ Name = "Copy share code", Callback = function()
	local code, err = Hub:ExportConfig("tour")
	if code and typeof(setclipboard) == "function" then setclipboard(code) end
	Hub:Notify({ Title = code and "Share code copied" or "Save a config first", Content = code and nil or err, Duration = 3 })
end })
local pinned = false
Profiles:Button({ Name = "Pin the numbers", Description = "Floats the Numbers section; drag its header", Callback = function()
	pinned = not pinned
	if pinned then Numbers:Pin(Vector2.new(24, 120)) else Numbers:Unpin() end
end })

---------------------------------------------------------------- demo data
task.spawn(function()
	local RunService = game:GetService("RunService")
	local frames, last, coins = 0, os.clock(), 1200
	RunService.RenderStepped:Connect(function() frames += 1 end)
	while task.wait(1) do
		local now = os.clock()
		Fps:Push(math.floor(frames / (now - last) + 0.5))
		frames, last = 0, now
		if Running.Value then
			local earned = math.random(-30, 120)
			coins += earned
			Coins:Update(coins)
			Rate:Push(earned)
			Energy:Set(math.clamp(Energy.Value + math.random(-10, 8), 5, 100))
			Steps:Set((Steps.Value + 1) % 11)
			if math.random() < 0.25 then
				Visitors:Update(Visitors.Value + 1)
				Log:Log("A visitor arrived")
			elseif earned < 0 then
				Log:Log("Spent " .. -earned .. " coins", "warn")
			end
		end
	end
end)

Hub:SetLoading("Ready", 1)
Hub:FinishLoading()
Hub:Notify({ Title = "Welcome to the tour", Content = "F2 searches everything. Click a section header to fold it.", Icon = "sparkles", Duration = 6 })

end, Rift.HandleError)
