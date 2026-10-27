-- Enum, EnumItem, plus TweenInfo and Font, which depend on enums.

local makeType, newValue = E.makeType, E.newValue

local DEFS = {
	KeyCode = "Unknown=0,Backspace=8,Tab=9,Clear=12,Return=13,Pause=19,Escape=27,Space=32,QuotedDouble=34,Hash=35,Dollar=36,Percent=37,Ampersand=38,Quote=39,LeftParenthesis=40,RightParenthesis=41,Asterisk=42,Plus=43,Comma=44,Minus=45,Period=46,Slash=47,Zero=48,One=49,Two=50,Three=51,Four=52,Five=53,Six=54,Seven=55,Eight=56,Nine=57,Colon=58,Semicolon=59,LessThan=60,Equals=61,GreaterThan=62,Question=63,At=64,LeftBracket=91,BackSlash=92,RightBracket=93,Caret=94,Underscore=95,Backquote=96,A=97,B=98,C=99,D=100,E=101,F=102,G=103,H=104,I=105,J=106,K=107,L=108,M=109,N=110,O=111,P=112,Q=113,R=114,S=115,T=116,U=117,V=118,W=119,X=120,Y=121,Z=122,LeftCurly=123,Pipe=124,RightCurly=125,Tilde=126,Delete=127,KeypadZero=256,KeypadOne=257,KeypadTwo=258,KeypadThree=259,KeypadFour=260,KeypadFive=261,KeypadSix=262,KeypadSeven=263,KeypadEight=264,KeypadNine=265,KeypadPeriod=266,KeypadDivide=267,KeypadMultiply=268,KeypadMinus=269,KeypadPlus=270,KeypadEnter=271,KeypadEquals=272,Up=273,Down=274,Right=275,Left=276,Insert=277,Home=278,End=279,PageUp=280,PageDown=281,F1=282,F2=283,F3=284,F4=285,F5=286,F6=287,F7=288,F8=289,F9=290,F10=291,F11=292,F12=293,F13=294,F14=295,F15=296,NumLock=300,CapsLock=301,ScrollLock=302,RightShift=303,LeftShift=304,RightControl=305,LeftControl=306,RightAlt=307,LeftAlt=308,RightMeta=309,LeftMeta=310,LeftSuper=311,RightSuper=312,Mode=313,Compose=314,Help=315,Print=316,SysReq=317,Break=318,Menu=319,Power=320,Euro=321,Undo=322,ButtonX=1000,ButtonY=1001,ButtonA=1002,ButtonB=1003,ButtonR1=1004,ButtonL1=1005,ButtonR2=1006,ButtonL2=1007,ButtonR3=1008,ButtonL3=1009,ButtonStart=1010,ButtonSelect=1011,DPadLeft=1012,DPadRight=1013,DPadUp=1014,DPadDown=1015,Thumbstick1=1016,Thumbstick2=1017",
	UserInputType = "MouseButton1=0,MouseButton2=1,MouseButton3=2,MouseWheel=3,MouseMovement=4,Touch=7,Keyboard=8,Focus=9,Accelerometer=10,Gyro=11,Gamepad1=12,Gamepad2=13,Gamepad3=14,Gamepad4=15,Gamepad5=16,Gamepad6=17,Gamepad7=18,Gamepad8=19,TextInput=20,InputMethod=21,None=22",
	UserInputState = "Begin=0,Change=1,End=2,Cancel=3,None=4",
	Font = "Legacy=0,Arial=1,ArialBold=2,SourceSans=3,SourceSansBold=4,SourceSansLight=5,SourceSansItalic=6,Bodoni=7,Garamond=8,Cartoon=9,Code=10,Highway=11,SciFi=12,Arcade=13,Fantasy=14,Antique=15,SourceSansSemibold=16,Gotham=17,GothamMedium=18,GothamBold=19,GothamBlack=20,AmaticSC=21,Bangers=22,Creepster=23,DenkOne=24,Fondamento=25,FredokaOne=26,GrenzeGotisch=27,IndieFlower=28,JosefinSans=29,Jura=30,Kalam=31,LuckiestGuy=32,Merriweather=33,Michroma=34,Nunito=35,Oswald=36,PatrickHand=37,PermanentMarker=38,Roboto=39,RobotoCondensed=40,RobotoMono=41,Sarpanch=42,SpecialElite=43,TitilliumWeb=44,Ubuntu=45,BuilderSans=46,BuilderSansMedium=47,BuilderSansBold=48,BuilderSansExtraBold=49,Arimo=50,ArimoBold=51,Unknown=100",
	FontWeight = "Thin=100,ExtraLight=200,Light=300,Regular=400,Medium=500,SemiBold=600,Bold=700,ExtraBold=800,Heavy=900",
	FontStyle = "Normal=0,Italic=1",
	TextXAlignment = "Left=0,Right=1,Center=2",
	TextYAlignment = "Top=0,Center=1,Bottom=2",
	TextTruncate = "None=0,AtEnd=1,SplitWord=2",
	TextDirection = "Auto=0,LeftToRight=1,RightToLeft=2",
	FillDirection = "Horizontal=0,Vertical=1",
	HorizontalAlignment = "Center=0,Left=1,Right=2",
	VerticalAlignment = "Center=0,Top=1,Bottom=2",
	SortOrder = "Name=0,Custom=1,LayoutOrder=2",
	AutomaticSize = "None=0,X=1,Y=2,XY=3",
	SizeConstraint = "RelativeXY=0,RelativeXX=1,RelativeYY=2",
	ScaleType = "Stretch=0,Slice=1,Tile=2,Fit=3,Crop=4",
	EasingStyle = "Linear=0,Sine=1,Back=2,Quad=3,Quart=4,Quint=5,Bounce=6,Elastic=7,Exponential=8,Circular=9,Cubic=10",
	EasingDirection = "In=0,Out=1,InOut=2",
	PlaybackState = "Begin=0,Delayed=1,Playing=2,Paused=3,Completed=4,Cancelled=5",
	ZIndexBehavior = "Global=0,Sibling=1",
	ScrollingDirection = "X=1,Y=2,XY=4",
	ScrollBarInset = "None=0,ScrollBar=1,Always=2",
	VerticalScrollBarPosition = "Right=0,Left=1",
	ElasticBehavior = "WhenScrollable=0,Always=1,Never=2",
	ApplyStrokeMode = "Contextual=0,Border=1",
	LineJoinMode = "Round=0,Bevel=1,Miter=2",
	BorderMode = "Outline=0,Middle=1,Inset=2",
	AspectType = "FitWithinMaxSize=0,ScaleWithParentSize=1",
	DominantAxis = "Width=0,Height=1",
	StartCorner = "TopLeft=0,TopRight=1,BottomLeft=2,BottomRight=3",
	UIFlexAlignment = "None=0,Fill=1,SpaceAround=2,SpaceBetween=3,SpaceEvenly=4",
	ItemLineAlignment = "Automatic=0,Start=1,Center=2,End=3,Stretch=4",
	UIFlexMode = "None=0,Grow=1,Shrink=2,Fill=3,Custom=4",
	ResamplerMode = "Default=0,Pixelated=1",
	MouseBehavior = "Default=0,LockCenter=1,LockCurrentPosition=2",
	TextInputType = "Default=0,NoSuggestions=1,Number=2,Email=3,Phone=4,Password=5,PasswordShown=6,Username=7,OneTimePassword=8",
	ScreenInsets = "None=0,DeviceSafeInsets=1,CoreUISafeInsets=2,TopbarSafeInsets=3",
	SafeAreaCompatibility = "None=0,FullscreenExtension=1",
	CoreGuiType = "PlayerList=0,Health=1,Backpack=2,Chat=3,All=4,EmotesMenu=5,SelfView=6,Captures=7",
	SelectionBehavior = "Escape=0,Stop=1",
	HttpContentType = "ApplicationJson=0,ApplicationXml=1,ApplicationUrlEncoded=2,TextPlain=3,TextXml=4",
	ButtonStyle = "Custom=0,RobloxButtonDefault=1,RobloxButton=2,RobloxRoundButton=3,RobloxRoundDefaultButton=4,RobloxRoundDropdownButton=5",
	FrameStyle = "Custom=0,ChatBlue=1,RobloxSquare=2,RobloxRound=3,ChatGreen=4,ChatRed=5,DropShadow=6",
	ThumbnailType = "HeadShot=0,AvatarBust=1,AvatarThumbnail=2",
	ThumbnailSize = "Size48x48=0,Size180x180=1,Size420x420=2,Size60x60=3,Size100x100=4,Size150x150=5,Size352x352=6",
	HumanoidStateType = "FallingDown=0,Running=8,RunningNoPhysics=10,Climbing=12,StrafingNoPhysics=11,Ragdoll=1,GettingUp=2,Jumping=3,Landed=7,Flying=6,Freefall=5,Seated=13,PlatformStanding=14,Dead=15,Swimming=4,Physics=16,None=18",
	Material = "Plastic=256,SmoothPlastic=272,Neon=288,Wood=512,Glass=1568,ForceField=1584,Metal=1088",
	CameraType = "Fixed=0,Attach=1,Watch=2,Track=3,Follow=4,Custom=5,Scriptable=6,Orbital=7",
}

local EnumItemM = {}
local EnumItemMT = makeType("EnumItem", EnumItemM)
EnumItemMT.__tostring = function(item)
	return "Enum." .. item.EnumType._name .. "." .. item.Name
end
function EnumItemM.IsA(item, name)
	return item.EnumType._name == name
end

local EnumTypeM = {}
local EnumTypeMT = { __type = "Enum" }
EnumTypeMT.__index = function(self, key)
	local item = rawget(self, "_items")[key]
	if item then
		return item
	end
	local m = EnumTypeM[key]
	if m then
		return m
	end
	error(tostring(key) .. " is not a valid member of \"Enum." .. rawget(self, "_name") .. "\"", 2)
end
EnumTypeMT.__newindex = function()
	error("Enums are read-only", 2)
end
EnumTypeMT.__tostring = function(self)
	return rawget(self, "_name")
end
function EnumTypeM.GetEnumItems(self)
	local list = table.clone(rawget(self, "_list"))
	return list
end
function EnumTypeM.FromName(self, name)
	return rawget(self, "_items")[name]
end
function EnumTypeM.FromValue(self, value)
	return rawget(self, "_byValue")[value]
end

local enums = {}
for name, spec in DEFS do
	local et = setmetatable({ _name = name, _items = {}, _byValue = {}, _list = {} }, EnumTypeMT)
	for pair in string.gmatch(spec, "[^,]+") do
		local n, v = string.match(pair, "^(%w+)=(%-?%d+)$")
		local value = tonumber(v) :: number
		local item = newValue(EnumItemMT, { Name = n, Value = value, EnumType = et })
		rawget(et, "_items")[n] = item
		if rawget(et, "_byValue")[value] == nil then
			rawget(et, "_byValue")[value] = item
		end
		table.insert(rawget(et, "_list"), item)
	end
	table.sort(rawget(et, "_list"), function(a, b)
		return a.Value < b.Value
	end)
	enums[name] = et
end

local EnumsMT = { __type = "Enums" }
EnumsMT.__index = function(_, key)
	if key == "GetEnums" then
		return function()
			local list = {}
			for _, e in enums do
				table.insert(list, e)
			end
			return list
		end
	end
	local e = enums[key]
	if e then
		return e
	end
	error(tostring(key) .. " is not a valid member of \"Enum\"", 2)
end
EnumsMT.__newindex = function()
	error("Enums are read-only", 2)
end
Enum = setmetatable({}, EnumsMT)
E.enums = enums

-- Coerce a number, string or EnumItem into an item of the named enum.
function E.coerceEnum(enumName: string, v: any): any
	local et = enums[enumName]
	local t = E.typeof(v)
	if t == "EnumItem" then
		if v.EnumType == et then
			return v
		end
		return nil
	elseif t == "number" then
		return rawget(et, "_byValue")[v]
	elseif t == "string" then
		return rawget(et, "_items")[v]
	end
	return nil
end

---------------------------------------------------------------- TweenInfo
local TweenInfoMT = makeType("TweenInfo", {})
TweenInfoMT.__tostring = function(t)
	return string.format(
		"Time:%s DelayTime:%s RepeatCount:%d Reverses:%s EasingDirection:%s EasingStyle:%s",
		E.fmt(t.Time),
		E.fmt(t.DelayTime),
		t.RepeatCount,
		tostring(t.Reverses),
		t.EasingDirection.Name,
		t.EasingStyle.Name
	)
end
TweenInfo = table.freeze({
	new = function(time, style, direction, repeatCount, reverses, delay)
		return newValue(TweenInfoMT, {
			Time = time or 1,
			EasingStyle = style and E.coerceEnum("EasingStyle", style) or enums.EasingStyle.Quad,
			EasingDirection = direction and E.coerceEnum("EasingDirection", direction) or enums.EasingDirection.Out,
			RepeatCount = repeatCount or 0,
			Reverses = reverses or false,
			DelayTime = delay or 0,
		})
	end,
})

---------------------------------------------------------------- Font
local FontM = {}
local FontMT = makeType("Font", FontM, {
	Bold = function(f)
		return f.Weight.Value >= 700
	end,
})
FontMT.__eq = function(a, b)
	return a.Family == b.Family and a.Weight == b.Weight and a.Style == b.Style
end
FontMT.__tostring = function(f)
	return string.format("Font { Family = %s, Weight = %s, Style = %s }", f.Family, f.Weight.Name, f.Style.Name)
end
local function newFont(family: string, weight, style)
	return newValue(FontMT, {
		Family = family,
		Weight = weight and E.coerceEnum("FontWeight", weight) or enums.FontWeight.Regular,
		Style = style and E.coerceEnum("FontStyle", style) or enums.FontStyle.Normal,
	})
end
local FAMILY = function(name)
	return "rbxasset://fonts/families/" .. name .. ".json"
end
-- Enum.Font name -> family file, weight, style
local ENUM_FONTS = {
	Legacy = { "LegacyArial", 400 },
	Arial = { "Arial", 400 },
	ArialBold = { "Arial", 700 },
	SourceSans = { "SourceSansPro", 400 },
	SourceSansBold = { "SourceSansPro", 700 },
	SourceSansSemibold = { "SourceSansPro", 600 },
	SourceSansLight = { "SourceSansPro", 300 },
	SourceSansItalic = { "SourceSansPro", 400, 1 },
	Bodoni = { "AccanthisADFStd", 400 },
	Garamond = { "Guru", 400 },
	Cartoon = { "ComicNeueAngular", 400 },
	Code = { "Inconsolata", 400 },
	Highway = { "HighwayGothic", 400 },
	SciFi = { "Zekton", 400 },
	Arcade = { "PressStart2P", 400 },
	Fantasy = { "Balthazar", 400 },
	Antique = { "Kaushan Script", 400 },
	Gotham = { "GothamSSm", 400 },
	GothamMedium = { "GothamSSm", 500 },
	GothamBold = { "GothamSSm", 700 },
	GothamBlack = { "GothamSSm", 900 },
	BuilderSans = { "BuilderSans", 400 },
	BuilderSansMedium = { "BuilderSans", 500 },
	BuilderSansBold = { "BuilderSans", 700 },
	BuilderSansExtraBold = { "BuilderSans", 800 },
	Arimo = { "Arimo", 400 },
	ArimoBold = { "Arimo", 700 },
}
function E.fontFromEnum(item)
	local spec = ENUM_FONTS[item.Name]
	if spec then
		return newFont(FAMILY(spec[1]), spec[2], spec[3] or 0)
	end
	return newFont(FAMILY(item.Name), 400, 0)
end
-- Best Enum.Font for a FontFace (used to keep TextLabel.Font in sync).
function E.enumFromFont(font)
	local fam = string.match(font.Family, "families/(.-)%.json$")
	if not fam then
		return enums.Font.Unknown
	end
	local best
	for name, spec in ENUM_FONTS do
		if spec[1] == fam and spec[2] == font.Weight.Value then
			return enums.Font[name]
		elseif spec[1] == fam and not best then
			best = enums.Font[name]
		end
	end
	if best then
		return best
	end
	local ok, item = pcall(function()
		return enums.Font[fam]
	end)
	return ok and item or enums.Font.Unknown
end
Font = table.freeze({
	new = function(family, weight, style)
		if type(family) ~= "string" then
			error("Font.new: family must be a string", 2)
		end
		return newFont(family, weight, style)
	end,
	fromEnum = function(item)
		return E.fontFromEnum(E.coerceEnum("Font", item))
	end,
	fromName = function(name, weight, style)
		return newFont(FAMILY(name), weight, style)
	end,
	fromId = function(id, weight, style)
		return newFont("rbxassetid://" .. tostring(id), weight, style)
	end,
})
E.newFont = newFont
