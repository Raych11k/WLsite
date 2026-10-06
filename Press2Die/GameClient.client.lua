--[[
	PRESS2DIE — GameClient (LocalScript)  ->  StarterPlayer > StarterPlayerScripts

	Интерфейс «проклятой приставки»:
	• Единый стиль: серая рваная изолента, чёрные рамки, красные «лезвия»-стрелки,
	  пиксельные счётчики «x100», красные концентрические рамки опасности, ЭЛТ-эффекты.
	• Слева сверху — список игроков: портрет в наклонной рамке, имя, полоса здоровья
	  с «xHP» и тонкая полоса выносливости. Палач — в красной рамке.
	• Слева снизу — своя анимированная 3D-модель над шкалами здоровья и выносливости
	  (повторяет бег/стойку, вздрагивает от удара).
	• Сверху — часы-таймер в том же стиле: тревога, тряска, красная вспышка за убийство.
	• Сцена выбора: камера на 6 подиумов с прожекторами, внизу таблица из 6 картриджей
	  (у Палача — своя таблица), монитор с Палачом опускается после его выбора.
	• Экран лобби, заставка уровня, итоги матча, наблюдение за живыми, освещение по зонам.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local CollectionService = game:GetService("CollectionService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local gameState = ReplicatedStorage:WaitForChild("GameState")
local remotes = ReplicatedStorage:WaitForChild("HorrorRemotes")
local announceEvent = remotes:WaitForChild("Announce")
local sprintEvent = remotes:WaitForChild("Sprint")
local pickEvent = remotes:WaitForChild("PickCharacter")
local pickStateEvent = remotes:WaitForChild("PickState")
local abilityEvent = remotes:WaitForChild("Ability")
local fxEvent = remotes:WaitForChild("Fx")
local resultsEvent = remotes:WaitForChild("Results")
local spectateEvent = remotes:WaitForChild("Spectate")

task.spawn(function()
	for _ = 1, 10 do
		if pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Health, false) then break end
		task.wait(1)
	end
end)

------------------------------------------------------------------------
-- ХЕЛПЕРЫ И ПАЛИТРА
------------------------------------------------------------------------
local function make(class, props, parent)
	local i = Instance.new(class)
	for k, v in pairs(props) do i[k] = v end
	i.Parent = parent
	return i
end
local function corner(p, r) return make("UICorner", { CornerRadius = r }, p) end
local function stroke(p, color, th, tr)
	return make("UIStroke", { Color = color, Thickness = th, Transparency = tr or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
end
local function grad(p, c0, c1, rot, t0, t1)
	return make("UIGradient", {
		Color = ColorSequence.new(c0, c1), Rotation = rot or 90,
		Transparency = NumberSequence.new(t0 or 0, t1 or 0),
	}, p)
end
local function approach(cur, target, dt, speed)
	return cur + (target - cur) * (1 - math.exp(-dt * speed))
end
local function tween(obj, t, props, style, dir)
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Sine, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end
-- string.upper не трогает кириллицу — делаем сами
local UPPER_MAP = {}
do
	local lo, up = {}, {}
	for _, c in utf8.codes("абвгдеёжзийклмнопрстуфхцчшщъыьэюя") do table.insert(lo, utf8.char(c)) end
	for _, c in utf8.codes("АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ") do table.insert(up, utf8.char(c)) end
	for i = 1, #lo do UPPER_MAP[lo[i]] = up[i] end
end
local function upper(s)
	return (string.gsub(string.upper(s or ""), utf8.charpattern, function(ch) return UPPER_MAP[ch] end))
end
local UI = {} -- дескрипторы интерфейса (Luau: не больше 200 локальных в функции)
local function decode(attr, default)
	local ok, data = pcall(HttpService.JSONDecode, HttpService, gameState:GetAttribute(attr) or "")
	if ok and type(data) == "table" then return data end
	return default
end

local BONE = Color3.fromRGB(232, 222, 200)
local INK = Color3.fromRGB(24, 20, 22)
local PANEL = Color3.fromRGB(14, 12, 14)
local TAPE = Color3.fromRGB(176, 174, 182)
local BLOOD = Color3.fromRGB(150, 22, 28)
local BLOOD_HI = Color3.fromRGB(232, 44, 44)
local MAROON = Color3.fromRGB(112, 26, 36)
local C_ALIVE = Color3.fromRGB(108, 214, 128)
local C_DEAD = Color3.fromRGB(210, 56, 56)
local C_ESC = Color3.fromRGB(90, 200, 255)
local C_GOLD = Color3.fromRGB(255, 205, 70)
local C_YELLOW = Color3.fromRGB(240, 222, 120)
local C_LAV = Color3.fromRGB(196, 198, 255)
local C_LAV_TXT = Color3.fromRGB(60, 80, 220)
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local PIX = Enum.Font.Arcade        -- пиксельный шрифт для цифр и латиницы
local HEAVY = Enum.Font.GothamBlack -- кириллица: заголовки
local BOLD = Enum.Font.GothamBold
local MED = Enum.Font.GothamMedium

local gui = make("ScreenGui", {
	Name = "HorrorHUD", ResetOnSpawn = false, IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, player:WaitForChild("PlayerGui"))

-- общий масштаб HUD под размер экрана
local function hudScale()
	local s = gui.AbsoluteSize
	return math.clamp(math.min(s.X / 1400, s.Y / 820), 0.55, 1.15)
end

------------------------------------------------------------------------
-- ЗВУКИ (встроенные звуки движка)
------------------------------------------------------------------------
local SFX = {
	tick = "rbxasset://sounds/clickfast.wav",
	confirm = "rbxasset://sounds/button.wav",
	ping = "rbxasset://sounds/electronicpingshort.wav",
	slash = "rbxasset://sounds/swordslash.wav",
}
local sfxCache = {}
local function sfx(name, volume, pitch)
	local id = SFX[name]
	if not id then return end
	local s = sfxCache[name]
	if not s then
		s = make("Sound", { SoundId = id, Volume = volume or 0.5 }, SoundService)
		sfxCache[name] = s
	end
	s.Volume = volume or 0.5
	s.PlaybackSpeed = pitch or 1
	pcall(function() SoundService:PlayLocalSound(s) end)
end

------------------------------------------------------------------------
-- ФИРМЕННЫЙ СТИЛЬ: изолента, лезвия, рамки опасности, линии
------------------------------------------------------------------------
-- «грязная» полосатая заливка: случайный многоточечный градиент
local function grime(frame, seed, rot, lo)
	local r = Random.new(seed)
	local kps = {}
	for i = 0, 9 do
		local k = r:NextNumber(lo or 0.7, 1)
		table.insert(kps, ColorSequenceKeypoint.new(i / 9, Color3.new(k, k, k)))
	end
	return make("UIGradient", { Color = ColorSequence.new(kps), Rotation = rot or r:NextNumber(-25, 25) }, frame)
end

local function specks(frame, seed, n, color)
	local r = Random.new(seed + 13)
	for _ = 1, n or 6 do
		make("Frame", {
			Position = UDim2.fromScale(r:NextNumber(0.04, 0.92), r:NextNumber(0.08, 0.86)),
			Size = UDim2.fromOffset(r:NextInteger(2, 6), r:NextInteger(1, 3)),
			BackgroundColor3 = color or Color3.fromRGB(70, 66, 72), BackgroundTransparency = r:NextNumber(0.25, 0.7),
			BorderSizePixel = 0, ZIndex = frame.ZIndex,
		}, frame)
	end
end

-- рваная изолента: holder (с зубцами по краям) + body для содержимого
local function tape(parent, props, seed, color)
	color = color or TAPE
	local holder = make("Frame", { BackgroundTransparency = 1 }, parent)
	for k, v in pairs(props) do holder[k] = v end
	local z = holder.ZIndex
	local h = holder.Size.Y.Offset
	local n = math.max(2, math.floor(h / 7))
	for side = 0, 1 do
		for i = 0, n - 1 do
			local s = h / n * 0.72
			make("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(side, side == 0 and 1 or -1, (i + 0.5) / n, 0),
				Size = UDim2.fromOffset(s, s), Rotation = 45, BackgroundColor3 = color:Lerp(BLACK, 0.12),
				BorderSizePixel = 0, ZIndex = z,
			}, holder)
		end
	end
	local body = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = z }, holder)
	grime(body, seed)
	specks(body, seed, 6)
	return holder, body
end

-- отрезок между двумя точками (в пикселях родителя)
local function line(parent, ax, ay, bx, by, th, color, z)
	local dx, dy = bx - ax, by - ay
	return make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset((ax + bx) / 2, (ay + by) / 2),
		Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy) + th * 0.5, th), Rotation = math.deg(math.atan2(dy, dx)),
		BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = z or 1,
	}, parent)
end

-- красное «лезвие»: контур под полосой, заострённый вправо (или влево)
local function blade(parent, x0, y0, x1, y1, tip, color, z, dir)
	local ym = (y0 + y1) / 2
	local out = {}
	dir = dir or 1
	if dir == 1 then
		table.insert(out, line(parent, x0, y1, x1, y1, 2, color, z))
		table.insert(out, line(parent, x1, y1, x1 + tip, ym, 2, color, z))
		table.insert(out, line(parent, x1 + tip, ym, x1, y0, 2, color, z))
	else
		table.insert(out, line(parent, x1, y1, x0, y1, 2, color, z))
		table.insert(out, line(parent, x0, y1, x0 - tip, ym, 2, color, z))
		table.insert(out, line(parent, x0 - tip, ym, x0, y0, 2, color, z))
	end
	return out
end

-- красная концентрическая рамка опасности (как у Палача в списке)
local function dangerFrame(parent, size, z)
	local f = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, ZIndex = z,
	}, parent)
	local rings = {}
	for i, k in ipairs({ 1.0, 1.2, 1.4 }) do
		local ring = make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(k, k), BackgroundTransparency = 1, ZIndex = z,
		}, f)
		table.insert(rings, stroke(ring, BLOOD_HI, i == 1 and 3 or 2, 0))
	end
	local glow = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.55, 1.55), BackgroundColor3 = BLOOD_HI, BackgroundTransparency = 0.82,
		BorderSizePixel = 0, ZIndex = z - 1,
	}, f)
	corner(glow, UDim.new(0.2, 0))
	-- насечки по центрам сторон
	for _, d in ipairs({ { 0.5, -0.25, 3, 0.3 }, { 0.5, 1.25, 3, 0.3 }, { -0.25, 0.5, 0.3, 3 }, { 1.25, 0.5, 0.3, 3 } }) do
		make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(d[1], d[2]),
			Size = UDim2.new(d[3] == 3 and 0 or d[3], d[3] == 3 and 3 or 0, d[4] == 3 and 0 or d[4], d[4] == 3 and 3 or 0),
			BackgroundColor3 = BLOOD_HI, BorderSizePixel = 0, ZIndex = z,
		}, f)
	end
	return f, rings, glow
end

-- счётчик «x100» с чёрной обводкой
local function counter(parent, props)
	local t = make("TextLabel", {
		BackgroundTransparency = 1, Font = PIX, TextColor3 = C_YELLOW, TextStrokeColor3 = BLACK,
		TextStrokeTransparency = 0, Text = "x100", TextXAlignment = Enum.TextXAlignment.Left,
	}, parent)
	for k, v in pairs(props) do t[k] = v end
	return t
end

------------------------------------------------------------------------
-- ЭКРАННЫЕ ЭФФЕКТЫ: виньетка, сканлайны, вспышка урона, помехи, ЭЛТ-выключение
------------------------------------------------------------------------
UI.vigFrames = {}
local function vigEdge(pos, size, anchor, rot)
	local f = make("Frame", {
		Position = pos, Size = size, AnchorPoint = anchor, BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.6, BorderSizePixel = 0, ZIndex = 0,
	}, gui)
	make("UIGradient", { Rotation = rot, Transparency = NumberSequence.new(0, 1) }, f)
	table.insert(UI.vigFrames, f)
end
vigEdge(UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.3), Vector2.new(0, 0), 90)
vigEdge(UDim2.fromScale(0, 1), UDim2.fromScale(1, 0.3), Vector2.new(0, 1), 270)
vigEdge(UDim2.fromScale(0, 0), UDim2.fromScale(0.22, 1), Vector2.new(0, 0), 0)
vigEdge(UDim2.fromScale(1, 0), UDim2.fromScale(0.22, 1), Vector2.new(1, 0), 180)

-- сканлайны: полосы с повторяющимся градиентом (20 точек = 10 линий на полосу)
UI.scanRoot = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 90 }, gui)
UI.scanStrips = {}
local function buildScanlines()
	for _, s in ipairs(UI.scanStrips) do s:Destroy() end
	UI.scanStrips = {}
	local band = 40
	local h = math.max(gui.AbsoluteSize.Y, 200)
	local kps = {}
	for i = 0, 19 do
		table.insert(kps, NumberSequenceKeypoint.new(i / 19, i % 2 == 0 and 0 or 1))
	end
	local seq = NumberSequence.new(kps)
	for y = 0, h, band do
		local f = make("Frame", {
			Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, band),
			BackgroundColor3 = BLACK, BackgroundTransparency = 0.88, BorderSizePixel = 0, ZIndex = 90,
		}, UI.scanRoot)
		make("UIGradient", { Rotation = 90, Transparency = seq }, f)
		table.insert(UI.scanStrips, f)
	end
end
buildScanlines()

UI.damageFlash = make("Frame", {
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(190, 0, 0),
	BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1,
}, gui)

-- помехи (статика): случайные полосы
UI.staticRoot = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 95 }, gui)
UI.staticBars = {}
for _ = 1, 26 do
	table.insert(UI.staticBars, make("Frame", { BorderSizePixel = 0, ZIndex = 95, BackgroundColor3 = WHITE }, UI.staticRoot))
end
local staticUntil, staticStrength = 0, 0
local function showStatic(dur, strength)
	staticUntil = math.max(staticUntil, os.clock() + dur)
	staticStrength = strength or 1
end

-- ЭЛТ-переход: экран схлопывается в линию и точку (и обратно)
UI.crtRoot = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 100 }, gui)
UI.crtTop = make("Frame", { Size = UDim2.fromScale(1, 0.5), BackgroundColor3 = BLACK, BorderSizePixel = 0, ZIndex = 100 }, UI.crtRoot)
UI.crtBottom = make("Frame", {
	AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0.5),
	BackgroundColor3 = BLACK, BorderSizePixel = 0, ZIndex = 100,
}, UI.crtRoot)
UI.crtLine = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 0, 0, 3),
	BackgroundColor3 = Color3.fromRGB(230, 240, 255), BorderSizePixel = 0, ZIndex = 101, BackgroundTransparency = 1,
}, UI.crtRoot)
local crtToken = 0
local crtIsOff = true
local function screenOff(t)
	crtToken += 1
	local my = crtToken
	crtIsOff = true
	t = t or 0.6
	UI.crtLine.Size = UDim2.new(1, 0, 0, 3)
	UI.crtLine.BackgroundTransparency = 1
	tween(UI.crtTop, t * 0.55, { Size = UDim2.fromScale(1, 0.5) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tween(UI.crtBottom, t * 0.55, { Size = UDim2.fromScale(1, 0.5) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(t * 0.5, function()
		if my ~= crtToken then return end
		UI.crtLine.BackgroundTransparency = 0
		tween(UI.crtLine, t * 0.45, { Size = UDim2.new(0, 4, 0, 3) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(t * 0.5, function()
			if my == crtToken then tween(UI.crtLine, 0.25, { BackgroundTransparency = 1 }) end
		end)
	end)
end
local function screenOn(t)
	crtToken += 1
	local my = crtToken
	crtIsOff = false
	t = t or 0.8
	UI.crtLine.Size = UDim2.new(0, 4, 0, 3)
	UI.crtLine.BackgroundTransparency = 0
	tween(UI.crtLine, t * 0.35, { Size = UDim2.new(1, 0, 0, 3) }, Enum.EasingStyle.Quad)
	task.delay(t * 0.3, function()
		if my ~= crtToken then return end
		tween(UI.crtTop, t * 0.6, { Size = UDim2.fromScale(1, 0) }, Enum.EasingStyle.Quad)
		tween(UI.crtBottom, t * 0.6, { Size = UDim2.fromScale(1, 0) }, Enum.EasingStyle.Quad)
		tween(UI.crtLine, t * 0.6, { BackgroundTransparency = 1 })
		showStatic(0.25, 0.6)
	end)
end

------------------------------------------------------------------------
-- ДАННЫЕ ПЕРСОНАЖЕЙ И КАРТ (с сервера)
------------------------------------------------------------------------
local characters, charById = {}, {}
local function loadCharacters()
	local data = decode("Characters", nil)
	if data then
		characters = data
		charById = {}
		for _, c in ipairs(characters) do charById[c.id] = c end
	end
end
loadCharacters()
local maps, mapByKey = {}, {}
local function loadMaps()
	maps = decode("Maps", {})
	mapByKey = {}
	for _, m in ipairs(maps) do mapByKey[m.key] = m end
end
loadMaps()

local function charColor(c) return Color3.fromRGB(c.color[1], c.color[2], c.color[3]) end
local function unknownChar(id) return { id = id or "?", name = "?", role = "", color = { 180, 180, 180 }, killer = false } end

------------------------------------------------------------------------
-- ПОРТРЕТЫ (плоская «официальная» графика героев, всё внутри квадрата)
------------------------------------------------------------------------
local function portrait(parent, c, z, dead)
	z = z or parent.ZIndex + 1
	local acc = charColor(c)
	local skin = Color3.fromRGB(214, 180, 150)
	local body = c.killer and Color3.fromRGB(30, 28, 32) or acc:Lerp(BLACK, 0.35)
	local V = Vector2.new
	local function px(x, y, w, h, col, round, rot, zz)
		local f = make("Frame", {
			AnchorPoint = V(0.5, 0.5), Position = UDim2.fromScale(x, y), Size = UDim2.fromScale(w, h),
			BackgroundColor3 = col, BorderSizePixel = 0, Rotation = rot or 0, ZIndex = zz or z,
		}, parent)
		if round then corner(f, round) end
		return f
	end
	local R = UDim.new(1, 0)
	-- плечи
	local sh = px(0.5, 0.88, c.id == "oscar" and 0.84 or 0.72, 0.26, c.id == "binky" and acc:Lerp(BLACK, 0.3) or body, UDim.new(0.45, 0))
	grad(sh, WHITE, Color3.fromRGB(150, 150, 150), 90)
	local headCol = (c.id == "binky") and acc:Lerp(BLACK, 0.3) or (c.killer and Color3.fromRGB(26, 24, 28) or skin)
	if c.id == "executioner" then
		px(0.5, 0.46, 0.56, 0.6, Color3.fromRGB(18, 16, 18), UDim.new(0.45, 0))
		px(0.5, 0.36, 0.3, 0.16, Color3.fromRGB(18, 16, 18), UDim.new(0.5, 0), 0, z)
		for _, x in ipairs({ 0.41, 0.59 }) do px(x, 0.47, 0.12, 0.04, Color3.fromRGB(255, 40, 30)) end
		px(0.5, 0.6, 0.18, 0.02, Color3.fromRGB(120, 10, 10))
		return
	elseif c.id == "glitch" then
		px(0.38, 0.12, 0.03, 0.2, Color3.fromRGB(180, 180, 190), nil, -25)
		px(0.62, 0.12, 0.03, 0.2, Color3.fromRGB(180, 180, 190), nil, 25)
		px(0.5, 0.45, 0.64, 0.5, Color3.fromRGB(46, 46, 52), UDim.new(0.1, 0))
		local scr = px(0.48, 0.45, 0.48, 0.36, Color3.fromRGB(120, 235, 255), UDim.new(0.12, 0))
		for i, col in ipairs({ Color3.fromRGB(255, 60, 200), WHITE, Color3.fromRGB(60, 255, 160) }) do
			make("Frame", { Position = UDim2.fromScale(0, 0.12 + i * 0.2), Size = UDim2.fromScale(1, 0.07), BackgroundColor3 = col,
				BackgroundTransparency = 0.3, BorderSizePixel = 0, ZIndex = z }, scr)
		end
		px(0.77, 0.38, 0.05, 0.05, Color3.fromRGB(120, 120, 130), R)
		return
	elseif c.id == "binky" then
		for _, s in ipairs({ -1, 1 }) do
			px(0.5 + s * 0.13, 0.18, 0.12, 0.34, acc, UDim.new(0.5, 0), -12 * s)
			px(0.5 + s * 0.13, 0.2, 0.06, 0.24, Color3.fromRGB(255, 150, 200), UDim.new(0.5, 0), -12 * s)
		end
		px(0.5, 0.48, 0.44, 0.44, headCol, R)
		for _, x in ipairs({ 0.41, 0.59 }) do
			px(x, 0.45, 0.13, 0.13, BLACK, R)
			px(x, 0.45, 0.045, 0.045, Color3.fromRGB(255, 30, 30), R)
		end
		px(0.5, 0.6, 0.3, 0.05, Color3.fromRGB(255, 250, 240), UDim.new(0.3, 0))
		for _, x in ipairs({ 0.44, 0.5, 0.56 }) do px(x, 0.6, 0.008, 0.05, Color3.fromRGB(30, 0, 0)) end
		return
	end
	-- выжившие: волосы/задний план снаряжения
	if c.id == "lilian" then px(0.5, 0.52, 0.48, 0.5, Color3.fromRGB(70, 30, 60), UDim.new(0.4, 0)) end
	if c.id == "aisha" then
		px(0.66, 0.36, 0.14, 0.14, Color3.fromRGB(40, 25, 20), R)
		px(0.72, 0.5, 0.1, 0.12, Color3.fromRGB(40, 25, 20), R)
	end
	px(0.5, 0.71, 0.14, 0.1, skin)
	px(0.5, 0.48, 0.4, 0.4, skin, R)
	-- глаза
	for _, x in ipairs({ 0.43, 0.57 }) do
		if dead then
			px(x, 0.48, 0.07, 0.015, Color3.fromRGB(40, 10, 10), nil, 45)
			px(x, 0.48, 0.07, 0.015, Color3.fromRGB(40, 10, 10), nil, -45)
		else
			px(x, 0.48, 0.035, 0.05, Color3.fromRGB(30, 24, 24))
		end
	end
	px(0.5, 0.58, 0.08, 0.012, Color3.fromRGB(120, 70, 60))
	if c.id == "alex" then
		px(0.5, 0.33, 0.44, 0.16, Color3.fromRGB(40, 90, 200), UDim.new(0.5, 0))
		px(0.3, 0.36, 0.14, 0.04, Color3.fromRGB(28, 60, 140))
	elseif c.id == "oscar" then
		px(0.5, 0.31, 0.46, 0.18, Color3.fromRGB(230, 190, 40), UDim.new(0.5, 0))
		px(0.5, 0.38, 0.58, 0.04, Color3.fromRGB(200, 160, 30))
		px(0.5, 0.3, 0.07, 0.06, Color3.fromRGB(255, 250, 220), R)
		px(0.5, 0.56, 0.18, 0.035, Color3.fromRGB(70, 44, 26), UDim.new(0.5, 0))
	elseif c.id == "lilian" then
		px(0.5, 0.27, 0.46, 0.04, Color3.fromRGB(230, 90, 170), UDim.new(0.5, 0))
		px(0.29, 0.48, 0.08, 0.16, Color3.fromRGB(230, 90, 170), UDim.new(0.4, 0))
		px(0.71, 0.48, 0.08, 0.16, Color3.fromRGB(230, 90, 170), UDim.new(0.4, 0))
	elseif c.id == "greg" then
		px(0.5, 0.47, 0.34, 0.06, Color3.fromRGB(10, 10, 12), UDim.new(0.2, 0))
		px(0.5, 0.31, 0.42, 0.12, Color3.fromRGB(90, 110, 60), UDim.new(0.5, 0))
		px(0.5, 0.36, 0.3, 0.04, Color3.fromRGB(70, 88, 46))
	elseif c.id == "aisha" then
		px(0.5, 0.39, 0.42, 0.05, Color3.fromRGB(255, 150, 40))
	elseif c.id == "felix" then
		px(0.5, 0.32, 0.42, 0.14, Color3.fromRGB(150, 120, 220), UDim.new(0.5, 0))
		px(0.5, 0.37, 0.43, 0.03, Color3.fromRGB(255, 210, 60))
		px(0.5, 0.21, 0.02, 0.06, Color3.fromRGB(120, 120, 130))
		px(0.5, 0.18, 0.2, 0.025, Color3.fromRGB(230, 50, 50))
		for _, x in ipairs({ 0.43, 0.57 }) do
			local g = px(x, 0.48, 0.11, 0.11, BLACK, R)
			g.BackgroundTransparency = 1
			stroke(g, Color3.fromRGB(20, 20, 24), 1.5)
		end
	end
end

------------------------------------------------------------------------
-- ЧАСЫ-ТАЙМЕР (в стиле HUD: наклонная рамка, изолента, пиксельные цифры)
------------------------------------------------------------------------
UI.clockRoot = make("Frame", {
	Name = "Clock", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.fromOffset(240, 200), BackgroundTransparency = 1, ZIndex = 5,
}, gui)
UI.clockScale = make("UIScale", { Scale = 1 }, UI.clockRoot)

-- рамка-квадрат (как у портретов)
UI.clockFrame = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(120, 10), Size = UDim2.fromOffset(118, 118),
	BackgroundTransparency = 1, Rotation = -5, ZIndex = 5,
}, UI.clockRoot)
make("Frame", { -- тень-треугольник
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, -10, 0.5, 14), Size = UDim2.fromScale(0.95, 0.95),
	Rotation = 24, BackgroundColor3 = Color3.fromRGB(8, 6, 8), BackgroundTransparency = 0.15, BorderSizePixel = 0, ZIndex = 4,
}, UI.clockFrame)
UI.clockDanger, UI.clockRings, UI.clockGlow = dangerFrame(UI.clockFrame, 118, 5)
UI.clockDanger.Visible = false
UI.clockBorder = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = TAPE, BorderSizePixel = 0, ZIndex = 6 }, UI.clockFrame)
grime(UI.clockBorder, 3, 40)
UI.clockInner = make("Frame", {
	Position = UDim2.fromOffset(6, 6), Size = UDim2.new(1, -12, 1, -12), BackgroundColor3 = Color3.fromRGB(10, 9, 11),
	BorderSizePixel = 0, ZIndex = 7,
}, UI.clockBorder)
UI.FACE_CALM = Color3.fromRGB(46, 42, 44)
UI.FACE_ALERT = Color3.fromRGB(104, 22, 26)
UI.clockFace = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.9, 0.9),
	BackgroundColor3 = UI.FACE_CALM, BorderSizePixel = 0, ZIndex = 8,
}, UI.clockInner)
corner(UI.clockFace, UDim.new(1, 0))
grad(UI.clockFace, WHITE, Color3.fromRGB(120, 112, 112), 90)
UI.faceStroke = stroke(UI.clockFace, BLACK, 3)
for i = 0, 11 do
	local holder = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 3, 0.86, 0), BackgroundTransparency = 1, Rotation = i * 30, ZIndex = 9,
	}, UI.clockFace)
	make("Frame", { Size = UDim2.new(1, 0, 0, i % 3 == 0 and 9 or 4), BackgroundColor3 = BONE, BorderSizePixel = 0, ZIndex = 9 }, holder)
end
UI.splatter = {}
for _, sp in ipairs({ { 0.18, 0.3, 9 }, { 0.82, 0.72, 7 }, { 0.6, 0.88, 6 }, { 0.3, 0.16, 5 } }) do
	local d = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(sp[1], sp[2]), Size = UDim2.fromOffset(sp[3], sp[3]),
		BackgroundColor3 = BLOOD, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 9,
	}, UI.clockFace)
	corner(d, UDim.new(1, 0))
	table.insert(UI.splatter, d)
end
local function hand(len, thick, color)
	local h = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(thick, len * 2), BackgroundTransparency = 1, ZIndex = 10,
	}, UI.clockFace)
	make("Frame", { Size = UDim2.fromScale(1, 0.5), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 10 }, h)
	return h
end
UI.hourHand = hand(22, 4, BONE)
UI.minuteHand = hand(32, 3, BONE)
UI.secondHand = hand(38, 2, BLOOD_HI)
corner(make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(9, 9),
	BackgroundColor3 = BLOOD_HI, BorderSizePixel = 0, ZIndex = 11,
}, UI.clockFace), UDim.new(1, 0))
-- изолента по углам рамки
tape(UI.clockRoot, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(66, 18), Size = UDim2.fromOffset(52, 16), Rotation = -38, ZIndex = 12 }, 21)
tape(UI.clockRoot, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(176, 16), Size = UDim2.fromOffset(48, 16), Rotation = 30, ZIndex = 12 }, 22)
-- табло с цифрами и красными лезвиями
UI.clockPlate = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(120, 132), Size = UDim2.fromOffset(150, 34),
	BackgroundColor3 = Color3.fromRGB(6, 6, 8), BorderSizePixel = 0, ZIndex = 6,
}, UI.clockRoot)
stroke(UI.clockPlate, BLACK, 3)
UI.plateBlades = {}
for _, l in ipairs(blade(UI.clockRoot, 45, 136, 195, 170, 14, BLOOD_HI, 5, 1)) do table.insert(UI.plateBlades, l) end
for _, l in ipairs(blade(UI.clockRoot, 45, 136, 195, 170, 14, BLOOD_HI, 5, -1)) do table.insert(UI.plateBlades, l) end
UI.timeText = make("TextLabel", {
	BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 7, Font = PIX, TextSize = 24,
	Text = "--:--", TextColor3 = C_YELLOW, TextStrokeColor3 = BLACK, TextStrokeTransparency = 0,
}, UI.clockPlate)
-- полоска цели под часами
UI.objHolder, UI.objBody = tape(UI.clockRoot, {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(120, 172), Size = UDim2.fromOffset(250, 24), Rotation = -1.5, ZIndex = 6,
}, 31)
UI.objText = make("TextLabel", {
	BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 7, Font = HEAVY, TextSize = 14,
	TextColor3 = INK, Text = "",
}, UI.objBody)
UI.objScale = make("UIScale", { Scale = 1 }, UI.objHolder)

------------------------------------------------------------------------
-- СПИСОК ИГРОКОВ (слева сверху): портрет в рамке, имя, здоровье «xHP», выносливость
------------------------------------------------------------------------
UI.listRoot = make("Frame", {
	Name = "PlayerList", Position = UDim2.fromOffset(18, 70), Size = UDim2.fromOffset(310, 10),
	AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Visible = false,
}, gui)
UI.listScale = make("UIScale", { Scale = 1 }, UI.listRoot)
make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }, UI.listRoot)
local cards = {} -- {frame, userId, isKiller, fill, hpText, stamFill, rings, dead}

local function buildCard(order, info, isKiller)
	local c = charById[info.c] or unknownChar(info.c)
	local status = info.s or "alive"
	local holder = make("Frame", { LayoutOrder = order, Size = UDim2.fromOffset(310, 76), BackgroundTransparency = 1 }, UI.listRoot)
	local card = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Rotation = -4, ZIndex = 2 }, holder)
	-- портрет
	local frame = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(266, 38), Size = UDim2.fromOffset(64, 64),
		BackgroundTransparency = 1, Rotation = 9, ZIndex = 3,
	}, card)
	make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, -7, 0.5, 9), Size = UDim2.fromScale(0.96, 0.96),
		Rotation = 22, BackgroundColor3 = Color3.fromRGB(8, 6, 8), BackgroundTransparency = 0.1, BorderSizePixel = 0, ZIndex = 2,
	}, frame)
	local rings = nil
	if isKiller then
		local _, r = dangerFrame(frame, 64, 3)
		rings = r
	end
	local border = make("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = isKiller and Color3.fromRGB(70, 14, 18) or TAPE, BorderSizePixel = 0, ZIndex = 4,
	}, frame)
	grime(border, order * 7, 30)
	local inner = make("Frame", {
		Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8),
		BackgroundColor3 = charColor(c):Lerp(BLACK, 0.7), BorderSizePixel = 0, ZIndex = 5,
	}, border)
	grad(inner, WHITE, Color3.fromRGB(90, 90, 90), 90)
	portrait(inner, c, 6, status == "dead")
	if status == "dead" then
		for _, rot in ipairs({ 45, -45 }) do
			make("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1.1, 0, 0, 5),
				Rotation = rot, BackgroundColor3 = C_DEAD, BorderSizePixel = 0, ZIndex = 9,
			}, inner)
		end
	elseif status == "escaped" then
		make("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.82), Size = UDim2.new(1.1, 0, 0, 16),
			Rotation = -12, BackgroundColor3 = C_ESC, BorderSizePixel = 0, ZIndex = 9, Font = PIX, TextSize = 10,
			TextColor3 = BLACK, Text = "EXIT",
		}, inner)
	end
	-- имя
	make("TextLabel", {
		Position = UDim2.fromOffset(4, 2), Size = UDim2.fromOffset(222, 22), BackgroundTransparency = 1, ZIndex = 3,
		Font = BOLD, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = isKiller and BLOOD_HI or (status == "dead" and Color3.fromRGB(150, 146, 146) or WHITE),
		TextStrokeTransparency = 0.2, Text = info.n or "?",
	}, card)
	-- полоса здоровья (у Палача — выносливость) со счётчиком
	local bar = make("Frame", {
		Position = UDim2.fromOffset(30, 28), Size = UDim2.fromOffset(194, 15),
		BackgroundColor3 = Color3.fromRGB(96, 22, 30), BorderSizePixel = 0, ZIndex = 3,
	}, card)
	stroke(bar, BLACK, 2)
	local fill = make("Frame", {
		Size = UDim2.fromScale(status == "alive" and 1 or 0, 1),
		BackgroundColor3 = isKiller and BLOOD_HI or C_ALIVE, BorderSizePixel = 0, ZIndex = 4,
	}, bar)
	grad(fill, WHITE, Color3.fromRGB(170, 170, 170), 90)
	local tag = make("Frame", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 4, 0.5, 0), Size = UDim2.fromOffset(56, 19),
		BackgroundColor3 = MAROON, BorderSizePixel = 0, ZIndex = 5,
	}, bar)
	stroke(tag, BLACK, 2)
	local hpText = make("TextLabel", {
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 6, Font = PIX, TextSize = 11,
		TextColor3 = BONE, TextStrokeTransparency = 0, Text = status == "alive" and "x100" or "x0",
	}, tag)
	-- тонкая полоса выносливости
	local sb = make("Frame", {
		Position = UDim2.fromOffset(36, 48), Size = UDim2.fromOffset(186, 4),
		BackgroundColor3 = Color3.fromRGB(40, 40, 46), BorderSizePixel = 0, ZIndex = 3,
	}, card)
	local stamFill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(236, 236, 242), BorderSizePixel = 0, ZIndex = 4 }, sb)
	-- порт P1..P6 / метка Палача
	make("TextLabel", {
		Position = UDim2.fromOffset(0, 27), Size = UDim2.fromOffset(28, 18), BackgroundTransparency = 1, ZIndex = 3,
		Font = PIX, TextSize = 10, TextColor3 = isKiller and BLOOD_HI or Color3.fromRGB(190, 186, 196),
		TextStrokeTransparency = 0.3, Text = isKiller and "EXE" or ("P" .. tostring(info.p or "?")),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, card)
	if isKiller then
		make("TextLabel", {
			Position = UDim2.fromOffset(26, 54), Size = UDim2.fromOffset(196, 14), BackgroundTransparency = 1, ZIndex = 3,
			Font = BOLD, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(230, 120, 120),
			TextStrokeTransparency = 0.4, Text = c.name .. " — на счётчике жертвы",
		}, card)
	end
	table.insert(cards, { userId = info.id, isKiller = isKiller, fill = fill, hpText = hpText, stamFill = stamFill,
		rings = rings, status = status, frame = holder, shownHp = 1 })
end

local rowCount = 0
local refreshVisibility
local function rebuildRoster()
	for _, cd in ipairs(cards) do cd.frame:Destroy() end
	cards = {}
	rowCount = 0
	local roster = decode("Roster", {})
	local k = decode("Killer", {})
	if k.id and k.id ~= player.UserId then
		rowCount += 1
		buildCard(0, k, true)
	end
	for i, s in ipairs(roster) do
		if s.id ~= player.UserId then
			rowCount += 1
			buildCard(i, s, false)
		end
	end
	if refreshVisibility then refreshVisibility() end
end

------------------------------------------------------------------------
-- СВОЙ HUD (слева снизу): анимированная модель, здоровье «xHP», выносливость «xST»
------------------------------------------------------------------------
UI.selfRoot = make("Frame", {
	Name = "SelfHUD", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -14),
	Size = UDim2.fromOffset(420, 262), BackgroundTransparency = 1, Visible = false,
}, gui)
UI.selfScale = make("UIScale", { Scale = 1 }, UI.selfRoot)
UI.selfShake = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, UI.selfRoot)

UI.bustVP = make("ViewportFrame", {
	Position = UDim2.fromOffset(46, 0), Size = UDim2.fromOffset(250, 196), BackgroundTransparency = 1,
	ImageTransparency = 1, ZIndex = 1, Ambient = Color3.fromRGB(110, 96, 100), LightColor = Color3.fromRGB(255, 230, 215),
	LightDirection = Vector3.new(-0.5, -0.4, 1),
}, UI.selfShake)
UI.bustWorld = make("WorldModel", {}, UI.bustVP)
UI.bustCam = make("Camera", { FieldOfView = 30 }, UI.bustVP)
UI.bustVP.CurrentCamera = UI.bustCam

-- изолента слева (декор) и метка порта
tape(UI.selfShake, { Position = UDim2.fromOffset(0, 150), Size = UDim2.fromOffset(74, 30), Rotation = -12, ZIndex = 2 }, 41)
tape(UI.selfShake, { Position = UDim2.fromOffset(4, 208), Size = UDim2.fromOffset(66, 26), Rotation = 8, ZIndex = 2 }, 42)
UI._, UI.portBody = tape(UI.selfShake, { Position = UDim2.fromOffset(340, 222), Size = UDim2.fromOffset(52, 24), Rotation = 5, ZIndex = 4 }, 43)
UI.portText = make("TextLabel", {
	BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 5, Font = PIX, TextSize = 13, TextColor3 = INK, Text = "P1",
}, UI.portBody)

-- счётчик здоровья «x126»
UI.hpCounter = counter(UI.selfShake, { Position = UDim2.fromOffset(84, 146), Size = UDim2.fromOffset(160, 30), TextSize = 24, ZIndex = 6 })
UI.hpCaption = make("TextLabel", {
	Position = UDim2.fromOffset(196, 152), Size = UDim2.fromOffset(150, 18), BackgroundTransparency = 1, ZIndex = 6,
	Font = BOLD, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(220, 210, 200),
	TextStrokeTransparency = 0.3, Text = "",
}, UI.selfShake)

-- большая полоса здоровья с чёрной рамкой и красным лезвием
blade(UI.selfShake, 56, 184, 370, 222, 18, BLOOD_HI, 3, 1)
UI.hpBar = make("Frame", {
	Position = UDim2.fromOffset(44, 178), Size = UDim2.fromOffset(330, 40), BackgroundColor3 = BLACK, BorderSizePixel = 0, ZIndex = 4,
}, UI.selfShake)
UI.hpTrack = make("Frame", {
	Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8), BackgroundColor3 = Color3.fromRGB(26, 16, 30),
	BorderSizePixel = 0, ZIndex = 5,
}, UI.hpBar)
UI.hpFill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(80, 60, 200), BorderSizePixel = 0, ZIndex = 6 }, UI.hpTrack)
grime(UI.hpFill, 51, 90, 0.55)
specks(UI.hpFill, 52, 9, Color3.fromRGB(20, 10, 30))
UI.hpGhost = make("Frame", { -- след урона
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 240, 240), BackgroundTransparency = 0.4,
	BorderSizePixel = 0, ZIndex = 5,
}, UI.hpTrack)
UI.hpLabel = make("TextLabel", {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0), ZIndex = 8,
	Font = HEAVY, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = WHITE,
	TextStrokeTransparency = 0.2, Text = "",
}, UI.hpTrack)

-- выносливость: светлая полоса со счётчиком «x30»
UI.stBar = make("Frame", {
	Position = UDim2.fromOffset(44, 224), Size = UDim2.fromOffset(268, 26), BackgroundColor3 = BLACK, BorderSizePixel = 0, ZIndex = 4,
}, UI.selfShake)
UI.stTrack = make("Frame", {
	Position = UDim2.fromOffset(3, 3), Size = UDim2.new(1, -6, 1, -6), BackgroundColor3 = Color3.fromRGB(28, 28, 44),
	BorderSizePixel = 0, ZIndex = 5,
}, UI.stBar)
UI.stFill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C_LAV, BorderSizePixel = 0, ZIndex = 6 }, UI.stTrack)
grime(UI.stFill, 61, 0, 0.82)
UI.stText = counter(UI.stTrack, { Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -8, 1, 0), TextSize = 16, ZIndex = 7,
	TextColor3 = C_LAV_TXT, TextStrokeColor3 = WHITE, TextStrokeTransparency = 0.4, Text = "x100" })

-- модель игрока в окне: повторяет стойку/бег, вздрагивает от урона
local bustModel, bustTracks, bustState = nil, {}, nil
local bustShown, bustToken = false, 0
local bustHit = 0

local function animIds(char)
	local ids = {}
	local animate = char:FindFirstChild("Animate")
	if animate then
		for _, key in ipairs({ "idle", "walk", "run" }) do
			local folder = animate:FindFirstChild(key)
			if folder then
				local a = folder:FindFirstChildOfClass("Animation")
				if a and a.AnimationId ~= "" then ids[key] = a.AnimationId end
			end
		end
	end
	return ids
end

-- клон персонажа для ViewportFrame (WorldModel + Animator => анимации работают)
local function cloneRig(char, parent)
	local was = char.Archivable
	char.Archivable = true
	local ok, clone = pcall(function() return char:Clone() end)
	char.Archivable = was
	if not ok or not clone then return nil end
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("Tool") or d:IsA("BillboardGui") or d:IsA("Light")
			or d:IsA("Sound") or d:IsA("ForceField") or d:IsA("ParticleEmitter") or d:IsA("Trail") then
			d:Destroy()
		end
	end
	local hum = clone:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		if not hum:FindFirstChildOfClass("Animator") then make("Animator", {}, hum) end
	end
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = d.Name == "HumanoidRootPart"
			d.LocalTransparencyModifier = 0
		end
	end
	clone:PivotTo(CFrame.new(0, 0, 0))
	clone.Parent = parent
	return clone
end

local function playTracks(model, ids)
	local tracks = {}
	local hum = model:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not animator then return tracks end
	for key, id in pairs(ids) do
		local ok, track = pcall(function()
			local a = Instance.new("Animation")
			a.AnimationId = id
			return animator:LoadAnimation(a)
		end)
		if ok and track then
			track.Looped = true
			tracks[key] = track
		end
	end
	return tracks
end

local function buildBust()
	if bustModel then bustModel:Destroy() bustModel = nil end
	bustTracks, bustState = {}, nil
	local char = player.Character
	if not char then return end
	local ids = animIds(char)
	bustModel = cloneRig(char, UI.bustWorld)
	if not bustModel then return end
	bustTracks = playTracks(bustModel, ids)
	if bustTracks.idle then
		bustTracks.idle:Play(0.2)
		bustState = "idle"
	end
	local head = bustModel:FindFirstChild("Head")
	if head then
		local target = head.Position + Vector3.new(0, -0.9, 0)
		UI.bustCam.CFrame = CFrame.lookAt(target + Vector3.new(2.6, 0.5, -5.6), target)
	end
end

local function setBust(on)
	if on == bustShown then return end
	bustShown = on
	bustToken += 1
	local my = bustToken
	UI.bustVP.ImageTransparency = 1
	if on then
		task.delay(0.9, function()
			if my ~= bustToken then return end
			buildBust()
			tween(UI.bustVP, 1.6, { ImageTransparency = 0 })
		end)
	elseif bustModel then
		bustModel:Destroy()
		bustModel = nil
	end
end

------------------------------------------------------------------------
-- ПАНЕЛЬ СПОСОБНОСТИ / ПОДСКАЗКИ (справа снизу) + кнопки для телефона
------------------------------------------------------------------------
UI.abilityRoot = make("Frame", {
	AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -18, 1, -150), Size = UDim2.fromOffset(250, 92),
	BackgroundTransparency = 1, Visible = false,
}, gui)
UI.abilityScale = make("UIScale", { Scale = 1 }, UI.abilityRoot)
UI._, UI.abilityBody = tape(UI.abilityRoot, { Size = UDim2.fromOffset(250, 30), Rotation = 2, ZIndex = 3 }, 71)
UI.abilityTitle = make("TextLabel", {
	BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 4, Font = HEAVY, TextSize = 15, TextColor3 = INK, Text = "",
}, UI.abilityBody)
UI.abilityPlate = make("Frame", {
	Position = UDim2.fromOffset(10, 38), Size = UDim2.fromOffset(230, 30), BackgroundColor3 = BLACK, BorderSizePixel = 0, ZIndex = 3,
}, UI.abilityRoot)
UI.abilityFill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLOOD, BorderSizePixel = 0, ZIndex = 4 }, UI.abilityPlate)
grime(UI.abilityFill, 72, 0, 0.7)
UI.abilityText = make("TextLabel", {
	BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 5, Font = PIX, TextSize = 13, TextColor3 = WHITE,
	TextStrokeTransparency = 0, Text = "",
}, UI.abilityPlate)
UI.abilityBlades = blade(UI.abilityRoot, 14, 42, 236, 72, 12, BLOOD_HI, 2, 1)
UI.abilityDesc = make("TextLabel", {
	Position = UDim2.fromOffset(4, 72), Size = UDim2.fromOffset(242, 18), BackgroundTransparency = 1, ZIndex = 3,
	Font = MED, TextSize = 12, TextColor3 = Color3.fromRGB(220, 210, 210), TextStrokeTransparency = 0.3, Text = "",
}, UI.abilityRoot)

UI.controlsHint = make("TextLabel", {
	AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -18, 1, -18), Size = UDim2.fromOffset(420, 20),
	BackgroundTransparency = 1, Font = BOLD, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Right,
	TextColor3 = Color3.fromRGB(200, 196, 190), TextStrokeTransparency = 0.4, Text = "", Visible = false,
}, gui)

------------------------------------------------------------------------
-- БЕГ: Shift / L3 / кнопка на телефоне;  СПОСОБНОСТЬ: Q / Y / кнопка
------------------------------------------------------------------------
local sprintHeld = false
local function setSprint(on)
	if sprintHeld == on then return end
	sprintHeld = on
	sprintEvent:FireServer(on)
end
ContextActionService:BindActionAtPriority("HorrorSprint", function(_, state)
	setSprint(state == Enum.UserInputState.Begin)
	return Enum.ContextActionResult.Sink
end, false, Enum.ContextActionPriority.High.Value,
	Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonL3)
UserInputService.WindowFocusReleased:Connect(function() setSprint(false) end)
task.spawn(function()
	while true do
		task.wait(0.3)
		if sprintHeld then sprintEvent:FireServer(true) end
	end
end)

local function tryAbility()
	if player:GetAttribute("Role") ~= "Killer" or gameState:GetAttribute("Phase") ~= "Match" then return end
	local ready = player:GetAttribute("AbilityReadyAt") or 0
	if Workspace:GetServerTimeNow() >= ready then abilityEvent:FireServer() end
end
ContextActionService:BindAction("HorrorAbility", function(_, state)
	if state == Enum.UserInputState.Begin then tryAbility() end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.Q, Enum.KeyCode.ButtonY)

-- UI.touchSprint, UI.touchAbility — только на сенсорных устройствах
if UserInputService.TouchEnabled then
	UI.touchSprint = make("TextButton", {
		AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -30, 1, -170), Size = UDim2.fromOffset(84, 84),
		BackgroundColor3 = PANEL, BackgroundTransparency = 0.2, AutoButtonColor = false,
		Font = PIX, TextSize = 26, TextColor3 = C_LAV, Text = "RUN", Visible = false,
	}, gui)
	corner(UI.touchSprint, UDim.new(1, 0))
	stroke(UI.touchSprint, C_LAV_TXT, 3)
	UI.touchSprint.MouseButton1Down:Connect(function() setSprint(true) end)
	UI.touchSprint.MouseButton1Up:Connect(function() setSprint(false) end)
	UI.touchSprint.MouseLeave:Connect(function() setSprint(false) end)
	UI.touchAbility = make("TextButton", {
		AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -124, 1, -200), Size = UDim2.fromOffset(74, 74),
		BackgroundColor3 = BLOOD, BackgroundTransparency = 0.1, AutoButtonColor = true,
		Font = PIX, TextSize = 22, TextColor3 = WHITE, Text = "EXE", Visible = false,
	}, gui)
	corner(UI.touchAbility, UDim.new(1, 0))
	stroke(UI.touchAbility, BLACK, 3)
	UI.touchAbility.Activated:Connect(tryAbility)
end

------------------------------------------------------------------------
-- ОБЪЯВЛЕНИЯ (полоса изоленты)
------------------------------------------------------------------------
UI.toastHolder, UI.toastBody = tape(gui, {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 214), Size = UDim2.fromOffset(560, 34),
	Rotation = -1, Visible = false, ZIndex = 20,
}, 81)
UI.toastText = make("TextLabel", {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -28, 1, 0), ZIndex = 21,
	Font = HEAVY, TextSize = 17, TextColor3 = INK, TextTruncate = Enum.TextTruncate.AtEnd, Text = "",
}, UI.toastBody)
UI.toastMark = make("Frame", { Size = UDim2.new(0, 8, 1, 0), BorderSizePixel = 0, ZIndex = 21, BackgroundColor3 = BLOOD_HI }, UI.toastBody)
UI.toastScale = make("UIScale", { Scale = 1 }, UI.toastHolder)
UI.TOAST_COLORS = { info = Color3.fromRGB(90, 90, 100), good = Color3.fromRGB(60, 190, 90),
	bad = BLOOD_HI, warn = Color3.fromRGB(240, 170, 30) }
local toastToken = 0
local function showToast(text, kind)
	toastToken += 1
	local my = toastToken
	UI.toastText.Text = text
	UI.toastMark.BackgroundColor3 = UI.TOAST_COLORS[kind] or UI.TOAST_COLORS.info
	UI.toastHolder.Visible = true
	UI.toastScale.Scale = 0.6
	tween(UI.toastScale, 0.25, { Scale = hudScale() }, Enum.EasingStyle.Back)
	task.delay(4, function()
		if my == toastToken then
			tween(UI.toastScale, 0.2, { Scale = 0.01 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.delay(0.22, function()
				if my == toastToken then UI.toastHolder.Visible = false end
			end)
		end
	end)
end
announceEvent.OnClientEvent:Connect(function(text, kind)
	showToast(text, kind)
	if kind == "bad" then sfx("slash", 0.3, 0.6) else sfx("ping", 0.35, kind == "warn" and 0.8 or 1) end
end)

------------------------------------------------------------------------
-- ЗАСТАВКА УРОВНЯ (как в 16-битных играх) + роль и цель
------------------------------------------------------------------------
UI.titleRoot = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 60 }, gui)
UI.titleBand = make("Frame", {
	AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(-1, 0.42), Size = UDim2.new(1, 0, 0, 120),
	BackgroundColor3 = Color3.fromRGB(10, 8, 10), BorderSizePixel = 0, ZIndex = 60, Rotation = -3,
}, UI.titleRoot)
make("Frame", { Position = UDim2.new(0, 0, 0, -6), Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = BLOOD_HI, BorderSizePixel = 0, ZIndex = 60 }, UI.titleBand)
make("Frame", { Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = TAPE, BorderSizePixel = 0, ZIndex = 60 }, UI.titleBand)
UI.titleMap = make("TextLabel", {
	Position = UDim2.fromScale(0.08, 0.06), Size = UDim2.fromScale(0.84, 0.56), BackgroundTransparency = 1, ZIndex = 61,
	Font = HEAVY, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = WHITE, Text = "",
}, UI.titleBand)
UI.titleSub = make("TextLabel", {
	Position = UDim2.fromScale(0.08, 0.62), Size = UDim2.fromScale(0.84, 0.3), BackgroundTransparency = 1, ZIndex = 61,
	Font = PIX, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C_YELLOW, Text = "",
}, UI.titleBand)
UI.roleHolder, UI.roleBody = tape(UI.titleRoot, {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.58), Size = UDim2.fromOffset(620, 74), Rotation = 1.5, ZIndex = 61,
}, 91)
UI.roleTitle = make("TextLabel", {
	Position = UDim2.fromOffset(16, 4), Size = UDim2.new(1, -32, 0, 30), BackgroundTransparency = 1, ZIndex = 62,
	Font = HEAVY, TextSize = 24, TextColor3 = INK, Text = "",
}, UI.roleBody)
UI.roleText = make("TextLabel", {
	Position = UDim2.fromOffset(16, 34), Size = UDim2.new(1, -32, 0, 36), BackgroundTransparency = 1, ZIndex = 62,
	Font = BOLD, TextSize = 14, TextWrapped = true, TextColor3 = Color3.fromRGB(50, 40, 44), Text = "",
}, UI.roleBody)
UI.roleScale = make("UIScale", { Scale = 1 }, UI.roleHolder)
local titleToken = 0
local function showTitleCard()
	titleToken += 1
	local my = titleToken
	local info = mapByKey[gameState:GetAttribute("MapKey") or ""] or { name = "???", sub = "" }
	UI.titleMap.Text = info.name
	UI.titleSub.Text = "PRESS 2 DIE  ·  " .. (info.sub or "")
	local role = player:GetAttribute("Role")
	if role == "Killer" then
		local k = decode("Killer", {})
		local c = charById[k.c or ""]
		UI.roleTitle.Text = "ТЫ — " .. upper(c and c.name or "Палач")
		UI.roleText.Text = "Не дай никому сбежать. ЛКМ — удар, Q — " .. (c and c.ability and c.ability.name or "способность")
			.. ", Shift — бег. Каждое убийство добавляет время."
		UI.roleTitle.TextColor3 = BLOOD
	else
		UI.roleTitle.Text = "ТЫ — ВЫЖИВШИЙ  ·  P" .. tostring(player:GetAttribute("Port") or "?")
		UI.roleText.Text = string.format("Соберите %d жетонов, чтобы открыть выход раньше. Shift — бег. Выход откроется и сам за минуту до конца.",
			gameState:GetAttribute("TokensNeeded") or 0)
		UI.roleTitle.TextColor3 = INK
	end
	UI.titleRoot.Visible = true
	UI.titleBand.Position = UDim2.fromScale(-1, 0.42)
	UI.roleScale.Scale = 0.01
	tween(UI.titleBand, 0.55, { Position = UDim2.fromScale(0, 0.42) }, Enum.EasingStyle.Back)
	task.delay(0.45, function()
		if my == titleToken then tween(UI.roleScale, 0.35, { Scale = hudScale() }, Enum.EasingStyle.Back) end
	end)
	task.delay(4.6, function()
		if my ~= titleToken then return end
		tween(UI.titleBand, 0.45, { Position = UDim2.fromScale(1.1, 0.42) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(UI.roleScale, 0.3, { Scale = 0.01 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.5, function()
			if my == titleToken then UI.titleRoot.Visible = false end
		end)
	end)
end

------------------------------------------------------------------------
-- ИТОГИ МАТЧА
------------------------------------------------------------------------
UI.resultsRoot = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(640, 440),
	BackgroundTransparency = 1, Visible = false, ZIndex = 70,
}, gui)
UI.resultsScale = make("UIScale", { Scale = 1 }, UI.resultsRoot)
local function showResults(res)
	for _, ch in ipairs(UI.resultsRoot:GetChildren()) do
		if not ch:IsA("UIScale") then ch:Destroy() end
	end
	local titles = {
		killer = { "GAME OVER", "Палач победил — никто не выбрался из приставки", BLOOD_HI },
		survivors = { "YOU ESCAPED", "Все выжившие вырвались из приставки!", C_ALIVE },
		mixed = { "CONTINUE?", string.format("Сбежало %d из %d", res.esc or 0, res.total or 0), C_GOLD },
		left = { "NO SIGNAL", "Палач покинул игру — победа выживших", C_ESC },
	}
	local t = titles[res.o] or titles.mixed
	local back = make("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(8, 7, 9), BackgroundTransparency = 0.08,
		BorderSizePixel = 0, ZIndex = 70,
	}, UI.resultsRoot)
	stroke(back, BLACK, 4)
	grime(back, 101, 90, 0.6)
	tape(UI.resultsRoot, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(30, 8), Size = UDim2.fromOffset(90, 24), Rotation = -30, ZIndex = 75 }, 102)
	tape(UI.resultsRoot, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(610, 8), Size = UDim2.fromOffset(90, 24), Rotation = 28, ZIndex = 75 }, 103)
	make("TextLabel", {
		Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 56), BackgroundTransparency = 1, ZIndex = 72,
		Font = PIX, TextSize = 46, TextColor3 = t[3], TextStrokeTransparency = 0, Text = t[1],
	}, back)
	make("TextLabel", {
		Position = UDim2.fromOffset(0, 80), Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, ZIndex = 72,
		Font = HEAVY, TextSize = 18, TextColor3 = BONE, Text = t[2],
	}, back)
	local list = make("Frame", { Position = UDim2.fromOffset(40, 118), Size = UDim2.new(1, -80, 1, -136), BackgroundTransparency = 1, ZIndex = 72 }, back)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	local STATUS_TEXT = { escaped = "СБЕЖАЛ", dead = "ПОГИБ", alive = "ВЫЖИЛ" }
	local function row(order, c, name, status, statusColor, extra)
		local r = make("Frame", { LayoutOrder = order, Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = Color3.fromRGB(22, 20, 24),
			BorderSizePixel = 0, ZIndex = 72 }, list)
		local pic = make("Frame", { Position = UDim2.fromOffset(4, 3), Size = UDim2.fromOffset(32, 32),
			BackgroundColor3 = charColor(c):Lerp(BLACK, 0.6), BorderSizePixel = 0, ZIndex = 73 }, r)
		portrait(pic, c, 74, status == "dead")
		make("TextLabel", { Position = UDim2.fromOffset(46, 0), Size = UDim2.new(0.5, -46, 1, 0), BackgroundTransparency = 1, ZIndex = 73,
			Font = BOLD, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = WHITE, TextTruncate = Enum.TextTruncate.AtEnd,
			Text = name .. "  ·  " .. c.name }, r)
		make("TextLabel", { Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.new(0.25, 0, 1, 0), BackgroundTransparency = 1, ZIndex = 73,
			Font = MED, TextSize = 13, TextColor3 = Color3.fromRGB(190, 186, 180), Text = extra or "" }, r)
		make("TextLabel", { Position = UDim2.new(0.75, 0, 0, 0), Size = UDim2.new(0.25, -8, 1, 0), BackgroundTransparency = 1, ZIndex = 73,
			Font = HEAVY, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = statusColor,
			Text = STATUS_TEXT[status] and (STATUS_TEXT[status] .. ((c.f and status ~= "killer") and "А" or "")) or status }, r)
	end
	if res.killer then
		local kc = charById[res.killer.c] or unknownChar(res.killer.c)
		row(0, kc, res.killer.n or "?", "ПАЛАЧ", BLOOD_HI, "жертв: " .. tostring(res.killer.k or 0))
	end
	for i, s in ipairs(res.survivors or {}) do
		local sc = charById[s.c] or unknownChar(s.c)
		local col = (s.s == "escaped" and C_ESC) or (s.s == "alive" and C_ALIVE) or C_DEAD
		row(i, sc, s.n or "?", s.s, col, "P" .. tostring(s.p or "?") .. " · жетонов: " .. tostring(s.t or 0))
	end
	UI.resultsRoot.Visible = true
	UI.resultsScale.Scale = 0.01
	tween(UI.resultsScale, 0.4, { Scale = hudScale() }, Enum.EasingStyle.Back)
	showStatic(0.4, 0.8)
end
resultsEvent.OnClientEvent:Connect(showResults)

------------------------------------------------------------------------
-- НАБЛЮДЕНИЕ за живыми (для погибших, сбежавших и тех, кто в лобби)
------------------------------------------------------------------------
local spectating, specIndex, specTarget = false, 1, nil
UI.specRoot = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -22), Size = UDim2.fromOffset(460, 50),
	BackgroundTransparency = 1, Visible = false, ZIndex = 30,
}, gui)
UI.specScale = make("UIScale", { Scale = 1 }, UI.specRoot)
UI._, UI.specBody = tape(UI.specRoot, { Position = UDim2.fromOffset(50, 4), Size = UDim2.fromOffset(360, 40), ZIndex = 30 }, 111)
UI.specText = make("TextLabel", {
	BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 31, Font = HEAVY, TextSize = 16, TextColor3 = INK, Text = "",
}, UI.specBody)
local function specButton(text, x)
	local b = make("TextButton", {
		Position = UDim2.fromOffset(x, 4), Size = UDim2.fromOffset(42, 40), BackgroundColor3 = BLACK, AutoButtonColor = true,
		Font = PIX, TextSize = 18, TextColor3 = BLOOD_HI, Text = text, ZIndex = 31,
	}, UI.specRoot)
	stroke(b, BLOOD_HI, 2)
	return b
end
UI.specPrev = specButton("<", 0)
UI.specNext = specButton(">", 418)
UI.watchButton = make("TextButton", {
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -22), Size = UDim2.fromOffset(260, 40),
	BackgroundColor3 = BLACK, AutoButtonColor = true, Font = HEAVY, TextSize = 16, TextColor3 = BONE,
	Text = "НАБЛЮДАТЬ ЗА МАТЧЕМ", Visible = false, ZIndex = 30,
}, gui)
stroke(UI.watchButton, BLOOD_HI, 2)
UI.watchScale = make("UIScale", { Scale = 1 }, UI.watchButton)

local function aliveTargets()
	local out = {}
	local k = decode("Killer", {})
	for _, s in ipairs(decode("Roster", {})) do
		if s.s == "alive" and s.id ~= player.UserId then table.insert(out, { id = s.id, n = s.n, c = s.c }) end
	end
	if k.id and k.id ~= player.UserId then table.insert(out, { id = k.id, n = k.n, c = k.c, killer = true }) end
	return out
end

local function stopSpectate()
	if not spectating then return end
	spectating = false
	specTarget = nil
	spectateEvent:FireServer(nil)
	ContextActionService:UnbindAction("HorrorSpectate")
	camera = Workspace.CurrentCamera
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then camera.CameraSubject = hum end
end

local function focusSpectate()
	local list = aliveTargets()
	if #list == 0 then
		stopSpectate()
		return
	end
	specIndex = (specIndex - 1) % #list + 1
	local t = list[specIndex]
	specTarget = t.id
	local c = charById[t.c or ""]
	UI.specText.Text = (t.killer and "ПАЛАЧ: " or "НАБЛЮДЕНИЕ: ") .. (t.n or "?") .. (c and ("  ·  " .. c.name) or "")
	spectateEvent:FireServer(t.id)
end

local function startSpectate()
	if spectating then return end
	spectating = true
	specIndex = 1
	focusSpectate()
	ContextActionService:BindActionAtPriority("HorrorSpectate", function(_, state, input)
		if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
		if input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.DPadLeft then
			specIndex -= 1
		else
			specIndex += 1
		end
		focusSpectate()
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadRight)
end
UI.specPrev.Activated:Connect(function() specIndex -= 1 focusSpectate() end)
UI.specNext.Activated:Connect(function() specIndex += 1 focusSpectate() end)
UI.watchButton.Activated:Connect(function()
	if spectating then stopSpectate() else startSpectate() end
end)

------------------------------------------------------------------------
-- ВЫБОР ПЕРСОНАЖА: таблица картриджей под сценой
------------------------------------------------------------------------
UI.selectRoot = make("Frame", { Name = "CharacterSelect", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 40 }, gui)
UI.selBackdrop = make("Frame", {
	AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0.44),
	BackgroundColor3 = BLACK, BorderSizePixel = 0, ZIndex = 40,
}, UI.selectRoot)
make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.35, 0.35), NumberSequenceKeypoint.new(1, 0.05) }) }, UI.selBackdrop)

local CELL_W, CELL_H, CELL_GAP, INFO_W = 150, 206, 14, 300
UI.selPanel = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.fromOffset(1250, 262),
	BackgroundTransparency = 1, ZIndex = 41,
}, UI.selectRoot)
UI.selScale = make("UIScale", { Scale = 1 }, UI.selPanel)
UI._, UI.headerBody = tape(UI.selPanel, { Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(330, 30), Rotation = -1.5, ZIndex = 42 }, 121)
UI.headerText = make("TextLabel", {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0), ZIndex = 43,
	Font = HEAVY, TextSize = 16, TextColor3 = INK, TextXAlignment = Enum.TextXAlignment.Left, Text = "",
}, UI.headerBody)
UI.hintText = make("TextLabel", {
	Position = UDim2.fromOffset(344, 4), Size = UDim2.fromOffset(600, 24), BackgroundTransparency = 1, ZIndex = 42,
	Font = BOLD, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(200, 196, 190),
	TextStrokeTransparency = 0.4, Text = "← →  выбор героя     ПРОБЕЛ / ЕЩЁ РАЗ НАЖАТЬ — подтвердить",
}, UI.selPanel)
UI.tableFrame = make("Frame", { Position = UDim2.fromOffset(0, 46), Size = UDim2.fromOffset(940, CELL_H + 10), BackgroundTransparency = 1, ZIndex = 41 }, UI.selPanel)

-- инфо-панель
UI.infoPanel = make("Frame", {
	Position = UDim2.fromOffset(950, 46), Size = UDim2.fromOffset(INFO_W, CELL_H), BackgroundColor3 = Color3.fromRGB(10, 9, 11),
	BorderSizePixel = 0, ZIndex = 42,
}, UI.selPanel)
stroke(UI.infoPanel, BLACK, 3)
grime(UI.infoPanel, 131, 90, 0.75)
tape(UI.infoPanel, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -8, 0, 4), Size = UDim2.fromOffset(60, 18), Rotation = 34, ZIndex = 46 }, 132)
UI.infoName = make("TextLabel", {
	Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 0, 30), BackgroundTransparency = 1, ZIndex = 43,
	Font = HEAVY, TextSize = 26, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = WHITE, TextStrokeTransparency = 0.5, Text = "",
}, UI.infoPanel)
UI.infoRole = make("TextLabel", {
	Position = UDim2.fromOffset(14, 38), Size = UDim2.new(1, -28, 0, 16), BackgroundTransparency = 1, ZIndex = 43,
	Font = BOLD, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(180, 176, 170), Text = "",
}, UI.infoPanel)
UI.infoDesc = make("TextLabel", {
	Position = UDim2.fromOffset(14, 58), Size = UDim2.new(1, -28, 0, 34), BackgroundTransparency = 1, ZIndex = 43,
	Font = MED, TextSize = 12, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	TextColor3 = Color3.fromRGB(210, 206, 200), Text = "",
}, UI.infoPanel)
UI.statRows = {}
for r = 1, 3 do
	local y = 96 + (r - 1) * 18
	local lbl = make("TextLabel", {
		Position = UDim2.fromOffset(14, y), Size = UDim2.fromOffset(100, 14), BackgroundTransparency = 1, ZIndex = 43,
		Font = BOLD, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(190, 186, 180), Text = "",
	}, UI.infoPanel)
	local pips = {}
	for i = 1, 5 do
		local p = make("Frame", {
			Position = UDim2.fromOffset(118 + (i - 1) * 32, y + 2), Size = UDim2.fromOffset(28, 10),
			BackgroundColor3 = Color3.fromRGB(40, 36, 40), BorderSizePixel = 0, ZIndex = 43,
		}, UI.infoPanel)
		stroke(p, BLACK, 1)
		pips[i] = p
	end
	UI.statRows[r] = { label = lbl, pips = pips }
end
UI.infoAbility = make("TextLabel", {
	Position = UDim2.fromOffset(14, 150), Size = UDim2.new(1, -28, 0, 14), BackgroundTransparency = 1, ZIndex = 43,
	Font = BOLD, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 120, 120), Text = "",
}, UI.infoPanel)
UI.confirmBtn = make("TextButton", {
	Position = UDim2.fromOffset(14, 168), Size = UDim2.new(1, -28, 0, 30), BackgroundColor3 = BLOOD, AutoButtonColor = true,
	BorderSizePixel = 0, ZIndex = 44, Font = HEAVY, TextSize = 15, TextColor3 = WHITE, Text = "ВЫБРАТЬ  [ПРОБЕЛ]",
}, UI.infoPanel)
stroke(UI.confirmBtn, BLACK, 2)

local selCells = {}      -- [id] = {root, scale, lift, stroke, overlay, badge, badgeText, acc, cursorBlade}
local selList = {}       -- персонажи ТОЛЬКО моей таблицы
local cursor = 1
local myPick, myList = nil, nil
local takenSet, takenBy = {}, {}
local STAT_COLORS = { BLOOD_HI, C_GOLD, Color3.fromRGB(90, 170, 255) }
local onPhase

local function fitSelection()
	local n = math.max(#selList, 1)
	local tableW = n * CELL_W + (n - 1) * CELL_GAP
	UI.tableFrame.Size = UDim2.fromOffset(tableW, CELL_H + 10)
	UI.infoPanel.Position = UDim2.fromOffset(tableW + 20, 46)
	local w = tableW + 20 + INFO_W
	UI.selPanel.Size = UDim2.fromOffset(w, 262)
	local s = gui.AbsoluteSize
	UI.selScale.Scale = math.clamp(math.min(s.X * 0.96 / w, s.Y * 0.4 / 262), 0.4, 1.1)
end

local function readTaken()
	takenSet, takenBy = {}, {}
	local stage = decode("Stage", {})
	for i, s in ipairs(stage.s or {}) do
		if s.c then
			takenSet[s.c] = true
			takenBy[s.c] = { n = s.n, port = i, u = s.u }
		end
	end
	if stage.k and stage.k.c then
		takenSet[stage.k.c] = true
		takenBy[stage.k.c] = { n = stage.k.n, killer = true, u = stage.k.u }
	end
end

local function refreshInfo()
	local c = selList[cursor]
	if not c then return end
	local col = charColor(c)
	UI.infoName.Text = c.name
	UI.infoName.TextColor3 = col:Lerp(WHITE, 0.25)
	UI.infoRole.Text = upper(c.role)
	UI.infoDesc.Text = c.desc or ""
	local labels = c.killer and { "СИЛА", "СКОРОСТЬ", "ВЫНОСЛИВОСТЬ" } or { "ЗДОРОВЬЕ", "СКОРОСТЬ", "ВЫНОСЛИВОСТЬ" }
	local vals = c.killer and { c.power, c.speed, c.stamina } or { c.hp, c.speed, c.stamina }
	for r, row in ipairs(UI.statRows) do
		row.label.Text = labels[r]
		for i, p in ipairs(row.pips) do
			p.BackgroundColor3 = i <= (vals[r] or 0) and STAT_COLORS[r] or Color3.fromRGB(40, 36, 40)
		end
	end
	UI.infoAbility.Text = c.ability and ("Q — " .. c.ability.name .. ": " .. c.ability.text) or ""
	local locked = gameState:GetAttribute("SelectLocked") == true
	if myPick == c.id then
		UI.confirmBtn.Text = "ВЫБРАН ✓"
		UI.confirmBtn.BackgroundColor3 = Color3.fromRGB(40, 120, 60)
	elseif takenSet[c.id] then
		UI.confirmBtn.Text = "ЗАНЯТО"
		UI.confirmBtn.BackgroundColor3 = Color3.fromRGB(50, 46, 50)
	elseif locked then
		UI.confirmBtn.Text = "ИГРА НАЧИНАЕТСЯ…"
		UI.confirmBtn.BackgroundColor3 = Color3.fromRGB(50, 46, 50)
	else
		UI.confirmBtn.Text = "ВЫБРАТЬ  [ПРОБЕЛ]"
		UI.confirmBtn.BackgroundColor3 = BLOOD
	end
end

local function refreshSelection()
	readTaken()
	for i, c in ipairs(selList) do
		local cd = selCells[c.id]
		if cd then
			local mine = myPick == c.id
			local cur = i == cursor
			local other = takenSet[c.id] and not mine
			cd.overlay.Visible = other
			cd.badge.Visible = (takenSet[c.id] or false)
			if takenSet[c.id] then
				local tb = takenBy[c.id]
				cd.badgeText.Text = mine and ("ТЫ" .. (tb and tb.port and (" · P" .. tb.port) or "")) or
					((tb and tb.port and ("P" .. tb.port .. " · ") or "") .. (tb and tb.n or ""))
				cd.badge.BackgroundColor3 = mine and C_GOLD or Color3.fromRGB(30, 28, 32)
				cd.badgeText.TextColor3 = mine and INK or BONE
			end
			tween(cd.lift, 0.18, { Position = UDim2.fromOffset(0, cur and -12 or 0) }, Enum.EasingStyle.Back)
			tween(cd.scale, 0.18, { Scale = cur and 1.04 or 1 }, Enum.EasingStyle.Back)
			cd.stroke.Color = mine and C_GOLD or (cur and BLOOD_HI or BLACK)
			cd.stroke.Thickness = (mine or cur) and 4 or 2
			for _, b in ipairs(cd.cursorBlade) do b.Visible = cur end
			cd.root.ZIndex = cur and 3 or 1
		end
	end
	refreshInfo()
end

local function confirmPick()
	local c = selList[cursor]
	if not c or gameState:GetAttribute("SelectLocked") then return end
	readTaken()
	if takenSet[c.id] and myPick ~= c.id then
		sfx("tick", 0.4, 0.6)
		return
	end
	sfx("confirm", 0.5)
	pickEvent:FireServer(c.id)
end
UI.confirmBtn.Activated:Connect(confirmPick)

local function buildSelection()
	for _, cd in pairs(selCells) do cd.root:Destroy() end
	selCells, selList = {}, {}
	if myList then
		for _, c in ipairs(characters) do
			if c.killer == (myList == "Killer") then table.insert(selList, c) end
		end
	end
	cursor = math.clamp(cursor, 1, math.max(#selList, 1))
	fitSelection()
	UI.headerText.Text = myList == "Killer" and "ТАБЛИЦА ПАЛАЧА — ВЫБЕРИ ОБЛИК" or "ВЫБЕРИ ВЫЖИВШЕГО — ВСТАНЬ НА СЦЕНУ"
	UI.headerBody.BackgroundColor3 = myList == "Killer" and Color3.fromRGB(200, 120, 120) or TAPE
	for order, c in ipairs(selList) do
		local acc = charColor(c)
		local killerCell = c.killer
		local root = make("TextButton", {
			Position = UDim2.fromOffset((order - 1) * (CELL_W + CELL_GAP), 8), Size = UDim2.fromOffset(CELL_W, CELL_H),
			BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 1,
		}, UI.tableFrame)
		local lift = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, root)
		local sc = make("UIScale", { Scale = 1 }, lift)
		-- корпус картриджа
		local body = make("Frame", {
			Size = UDim2.fromScale(1, 1), BackgroundColor3 = killerCell and Color3.fromRGB(30, 26, 30) or Color3.fromRGB(162, 160, 168),
			BorderSizePixel = 0, ZIndex = 44,
		}, lift)
		corner(body, UDim.new(0, 8))
		grime(body, 140 + order, 90, 0.75)
		local st = stroke(body, BLACK, 2)
		for k = 0, 3 do
			make("Frame", { Position = UDim2.fromOffset(18, 8 + k * 5), Size = UDim2.new(1, -36, 0, 2),
				BackgroundColor3 = killerCell and Color3.fromRGB(70, 20, 24) or Color3.fromRGB(110, 108, 116), BorderSizePixel = 0, ZIndex = 45 }, body)
		end
		-- наклейка с артом
		local label = make("Frame", {
			Position = UDim2.fromOffset(10, 32), Size = UDim2.new(1, -20, 0, 136), BackgroundColor3 = acc,
			BorderSizePixel = 0, ZIndex = 45,
		}, body)
		grad(label, WHITE, Color3.fromRGB(40, 30, 40), 90)
		local art = make("Frame", { Position = UDim2.fromOffset(12, 4), Size = UDim2.fromOffset(106, 98), BackgroundTransparency = 1, ZIndex = 46 }, label)
		portrait(art, c, 47)
		make("TextLabel", {
			Position = UDim2.fromOffset(3, 3), Size = UDim2.fromOffset(30, 11), BackgroundColor3 = BLOOD, BorderSizePixel = 0, ZIndex = 49,
			Font = PIX, TextSize = 7, TextColor3 = WHITE, Text = "P2D",
		}, label)
		local banner = make("Frame", {
			AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 36),
			BackgroundColor3 = BLACK, BackgroundTransparency = 0.1, BorderSizePixel = 0, ZIndex = 48,
		}, label)
		make("TextLabel", {
			Position = UDim2.fromOffset(6, 2), Size = UDim2.new(1, -12, 0, 18), BackgroundTransparency = 1, ZIndex = 49,
			Font = HEAVY, TextSize = 16, TextColor3 = killerCell and BLOOD_HI or WHITE, Text = c.name,
		}, banner)
		make("TextLabel", {
			Position = UDim2.fromOffset(6, 19), Size = UDim2.new(1, -12, 0, 14), BackgroundTransparency = 1, ZIndex = 49,
			Font = MED, TextSize = 10, TextColor3 = Color3.fromRGB(190, 186, 180), Text = c.role or "",
		}, banner)
		-- контакты
		local pins = make("Frame", {
			Position = UDim2.fromOffset(16, 174), Size = UDim2.new(1, -32, 0, 22), BackgroundColor3 = Color3.fromRGB(24, 22, 26),
			BorderSizePixel = 0, ZIndex = 45,
		}, body)
		for k = 0, 9 do
			make("Frame", { Position = UDim2.fromOffset(5 + k * 11.4, 6), Size = UDim2.fromOffset(7, 13),
				BackgroundColor3 = Color3.fromRGB(214, 170, 70), BorderSizePixel = 0, ZIndex = 46 }, pins)
		end
		-- занято / мой выбор
		local overlay = make("Frame", {
			Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLACK, BackgroundTransparency = 0.45,
			BorderSizePixel = 0, ZIndex = 50, Visible = false,
		}, body)
		corner(overlay, UDim.new(0, 8))
		local badge = make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 108), Size = UDim2.new(1, 6, 0, 22), Rotation = -6,
			BackgroundColor3 = C_GOLD, BorderSizePixel = 0, ZIndex = 52, Visible = false,
		}, body)
		stroke(badge, BLACK, 2)
		local badgeText = make("TextLabel", {
			BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 53, Font = HEAVY, TextSize = 12,
			TextColor3 = INK, TextTruncate = Enum.TextTruncate.AtEnd, Text = "",
		}, badge)
		local cursorBlade = blade(root, 8, CELL_H - 2, CELL_W - 14, CELL_H + 6, 10, BLOOD_HI, 43, 1)
		for _, b in ipairs(cursorBlade) do b.Visible = false end
		root.Activated:Connect(function()
			if cursor ~= order then
				cursor = order
				sfx("tick", 0.35)
				refreshSelection()
			else
				confirmPick()
			end
		end)
		selCells[c.id] = { root = root, scale = sc, lift = lift, stroke = st, overlay = overlay, badge = badge,
			badgeText = badgeText, acc = acc, cursorBlade = cursorBlade }
	end
	refreshSelection()
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	fitSelection()
	buildScanlines()
end)

pickStateEvent.OnClientEvent:Connect(function(id, kind)
	if kind ~= nil then -- начало выбора: сервер сообщает, из какой таблицы выбирать
		myList = (kind == "Killer" or kind == "Survivor") and kind or nil
		myPick, cursor = nil, 1
		buildSelection()
		local ph = gameState:GetAttribute("Phase")
		if (ph == "ToSelection" or ph == "Selection") and onPhase then onPhase(true) end
		return
	end
	if id ~= myPick then
		myPick = id
		for i, c in ipairs(selList) do
			if c.id == id then cursor = i end
		end
	end
	refreshSelection()
end)

-- клавиши выбора
local function onSelectKey(_, state, input)
	if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Sink end
	local n = #selList
	if n > 0 then
		local k = input.KeyCode
		if k == Enum.KeyCode.Left or k == Enum.KeyCode.Up or k == Enum.KeyCode.A or k == Enum.KeyCode.DPadLeft then
			cursor = (cursor - 2) % n + 1
			sfx("tick", 0.35)
			refreshSelection()
		elseif k == Enum.KeyCode.Right or k == Enum.KeyCode.Down or k == Enum.KeyCode.D or k == Enum.KeyCode.DPadRight then
			cursor = cursor % n + 1
			sfx("tick", 0.35)
			refreshSelection()
		elseif k == Enum.KeyCode.Space or k == Enum.KeyCode.Return or k == Enum.KeyCode.ButtonA then
			confirmPick()
		end
	end
	return Enum.ContextActionResult.Sink
end

------------------------------------------------------------------------
-- КАМЕРА СЦЕНЫ ВЫБОРА И МОНИТОР ПАЛАЧА
------------------------------------------------------------------------
local camOn, camFresh = false, true
local stageModel, monitorModel = nil, nil
local monitorAlpha, monitorTarget = 0, 0
UI.monitorGui, UI.monitorVP, UI.monitorWorld, UI.monitorCam, UI.monitorClone = nil, nil, nil, nil, nil
local monitorKillerKey = nil
UI.monitorName, UI.monitorRec, UI.monitorNoise = nil, nil, nil
local dof = make("DepthOfFieldEffect", { Enabled = false, FarIntensity = 0, NearIntensity = 0, FocusDistance = 40, InFocusRadius = 30 }, Lighting)

local function findStage()
	if stageModel and stageModel.Parent then return stageModel end
	stageModel = Workspace:FindFirstChild("SelectionStage")
	monitorModel = stageModel and stageModel:FindFirstChild("KillerMonitor") or nil
	return stageModel
end

local function buildMonitorGui()
	if UI.monitorGui and UI.monitorGui.Parent and UI.monitorGui.Adornee and UI.monitorGui.Adornee.Parent then return true end
	findStage()
	local screen = monitorModel and monitorModel:FindFirstChild("Screen")
	if not screen then return false end
	if UI.monitorGui then UI.monitorGui:Destroy() end
	UI.monitorGui = make("SurfaceGui", {
		Name = "KillerMonitorGui", Adornee = screen, Face = Enum.NormalId.Front, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 40, LightInfluence = 0, ResetOnSpawn = false,
	}, player.PlayerGui)
	local bg = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(20, 4, 6), BorderSizePixel = 0 }, UI.monitorGui)
	grad(bg, Color3.fromRGB(255, 120, 120), Color3.fromRGB(60, 10, 14), 90)
	UI.monitorVP = make("ViewportFrame", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Ambient = Color3.fromRGB(140, 60, 60),
		LightColor = Color3.fromRGB(255, 120, 110), LightDirection = Vector3.new(-0.4, -0.5, 1), ZIndex = 2,
	}, bg)
	UI.monitorWorld = make("WorldModel", {}, UI.monitorVP)
	UI.monitorCam = make("Camera", { FieldOfView = 34 }, UI.monitorVP)
	UI.monitorVP.CurrentCamera = UI.monitorCam
	for y = 0, 270, 6 do
		make("Frame", { Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = BLACK,
			BackgroundTransparency = 0.7, BorderSizePixel = 0, ZIndex = 3 }, bg)
	end
	UI.monitorRec = make("TextLabel", {
		Position = UDim2.fromOffset(14, 10), Size = UDim2.fromOffset(120, 24), BackgroundTransparency = 1, ZIndex = 4,
		Font = PIX, TextSize = 18, TextColor3 = Color3.fromRGB(255, 40, 40), TextXAlignment = Enum.TextXAlignment.Left, Text = "● REC",
	}, bg)
	make("TextLabel", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 10), Size = UDim2.fromOffset(160, 24), BackgroundTransparency = 1,
		ZIndex = 4, Font = PIX, TextSize = 14, TextColor3 = Color3.fromRGB(255, 200, 200), TextXAlignment = Enum.TextXAlignment.Right, Text = "CH 666",
	}, bg)
	local strip = make("Frame", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 52),
		BackgroundColor3 = BLACK, BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 4,
	}, bg)
	UI.monitorName = make("TextLabel", {
		Position = UDim2.fromOffset(14, 2), Size = UDim2.new(1, -28, 1, -4), BackgroundTransparency = 1, ZIndex = 5,
		Font = HEAVY, TextScaled = true, TextColor3 = WHITE, Text = "",
	}, strip)
	UI.monitorNoise = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 6 }, bg)
	return true
end

local function refreshMonitorKiller()
	local stage = decode("Stage", {})
	local k = stage.k
	local key = k and k.c and (tostring(k.u) .. ":" .. k.c) or nil
	monitorTarget = key and 1 or 0
	if key == monitorKillerKey then return end
	monitorKillerKey = key
	if not key then return end
	sfx("ping", 0.5, 0.5)
	task.delay(0.45, function() -- ждём, пока долетит внешность Палача
		if monitorKillerKey ~= key or not buildMonitorGui() then return end
		if UI.monitorClone then UI.monitorClone:Destroy() UI.monitorClone = nil end
		local c = charById[k.c] or unknownChar(k.c)
		UI.monitorName.Text = upper(c.name) .. "  ·  " .. (k.n or "")
		UI.monitorName.TextColor3 = charColor(c):Lerp(WHITE, 0.3)
		UI.monitorNoise.BackgroundTransparency = 0
		tween(UI.monitorNoise, 0.8, { BackgroundTransparency = 1 })
		local kp = Players:GetPlayerByUserId(k.u)
		local char = kp and kp.Character
		if char then
			local ids = animIds(char)
			UI.monitorClone = cloneRig(char, UI.monitorWorld)
			if UI.monitorClone then
				local tracks = playTracks(UI.monitorClone, ids)
				if tracks.idle then tracks.idle:Play(0.2) end
				local head = UI.monitorClone:FindFirstChild("Head")
				if head then
					local target = head.Position + Vector3.new(0, -1.1, 0)
					UI.monitorCam.CFrame = CFrame.lookAt(target + Vector3.new(1.6, 0.6, -6.4), target)
				end
			end
		end
	end)
end

local function setSelectionVisible(on)
	UI.selectRoot.Visible = on
	if on == camOn then return end
	camOn = on
	camera = Workspace.CurrentCamera
	if on then
		camFresh = true
		camera.CameraType = Enum.CameraType.Scriptable
		dof.Enabled = true
		tween(dof, 1, { FarIntensity = 0.35 })
		ContextActionService:BindActionAtPriority("HorrorSelect", onSelectKey, false,
			Enum.ContextActionPriority.High.Value,
			Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.A, Enum.KeyCode.D,
			Enum.KeyCode.Space, Enum.KeyCode.Return, Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadRight, Enum.KeyCode.ButtonA)
		pcall(function() StarterGui:SetCore("ResetButtonCallback", false) end)
	else
		ContextActionService:UnbindAction("HorrorSelect")
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = 70
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then camera.CameraSubject = hum end
		dof.FarIntensity = 0
		dof.Enabled = false
		pcall(function() StarterGui:SetCore("ResetButtonCallback", true) end)
	end
end

------------------------------------------------------------------------
-- ЭКРАН ЛОББИ (на стене внутри приставки)
------------------------------------------------------------------------
UI.lobbyGui, UI.lobbyStatus, UI.lobbyBig, UI.lobbyBlink, UI.lobbyVotes, UI.lobbyTip = nil, nil, nil, nil, {}, nil
local TIPS = {
	"Shift — бег. Выдохся — жди, пока полоса восстановится.",
	"Собирайте золотые жетоны: когда их хватит, откроется выход.",
	"Удар Палача на миг ускоряет тебя — используй, чтобы оторваться.",
	"Выход открывается один. Ищи зелёный столб света.",
	"Каждое убийство добавляет Палачу 20 секунд.",
	"Погиб или сбежал? Нажми «Наблюдать за матчем».",
	"Стены «Лабиринта 8-бит» меняются каждый матч.",
}
local function buildLobbyGui()
	if UI.lobbyGui and UI.lobbyGui.Parent and UI.lobbyGui.Adornee and UI.lobbyGui.Adornee.Parent then return end
	local lobby = Workspace:FindFirstChild("Lobby")
	local screen = lobby and lobby:FindFirstChild("LobbyScreen")
	if not screen then return end
	if UI.lobbyGui then UI.lobbyGui:Destroy() end
	UI.lobbyVotes = {}
	UI.lobbyGui = make("SurfaceGui", {
		Name = "LobbyScreenGui", Adornee = screen, Face = Enum.NormalId.Back, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 20, LightInfluence = 0, ResetOnSpawn = false,
	}, player.PlayerGui)
	local bg = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(6, 8, 10), BorderSizePixel = 0 }, UI.lobbyGui)
	grad(bg, Color3.fromRGB(40, 60, 50), Color3.fromRGB(6, 8, 10), 90)
	for y = 0, 600, 5 do
		make("Frame", { Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = BLACK,
			BackgroundTransparency = 0.75, BorderSizePixel = 0, ZIndex = 5 }, bg)
	end
	make("TextLabel", { Position = UDim2.fromScale(0.05, 0.04), Size = UDim2.fromScale(0.9, 0.2), BackgroundTransparency = 1,
		Font = PIX, TextScaled = true, TextColor3 = Color3.fromRGB(230, 30, 30), TextStrokeTransparency = 0.5, Text = "PRESS 2 DIE", ZIndex = 2 }, bg)
	UI.lobbyBlink = make("TextLabel", { Position = UDim2.fromScale(0.2, 0.25), Size = UDim2.fromScale(0.6, 0.06), BackgroundTransparency = 1,
		Font = PIX, TextScaled = true, TextColor3 = BONE, Text = "PRESS START", ZIndex = 2 }, bg)
	UI.lobbyStatus = make("TextLabel", { Position = UDim2.fromScale(0.05, 0.34), Size = UDim2.fromScale(0.9, 0.08), BackgroundTransparency = 1,
		Font = HEAVY, TextScaled = true, TextColor3 = WHITE, Text = "", ZIndex = 2 }, bg)
	UI.lobbyBig = make("TextLabel", { Position = UDim2.fromScale(0.05, 0.43), Size = UDim2.fromScale(0.9, 0.16), BackgroundTransparency = 1,
		Font = PIX, TextScaled = true, TextColor3 = C_YELLOW, TextStrokeTransparency = 0.3, Text = "", ZIndex = 2 }, bg)
	for i, m in ipairs(maps) do
		local col = Color3.fromRGB(m.color[1], m.color[2], m.color[3])
		local y = 0.62 + (i - 1) * 0.07
		make("TextLabel", { Position = UDim2.fromScale(0.08, y), Size = UDim2.fromScale(0.36, 0.055), BackgroundTransparency = 1,
			Font = HEAVY, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = col, Text = m.name, ZIndex = 2 }, bg)
		local track = make("Frame", { Position = UDim2.fromScale(0.47, y + 0.01), Size = UDim2.fromScale(0.4, 0.035),
			BackgroundColor3 = Color3.fromRGB(30, 30, 34), BorderSizePixel = 0, ZIndex = 2 }, bg)
		local fill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = col, BorderSizePixel = 0, ZIndex = 3 }, track)
		local n = make("TextLabel", { Position = UDim2.fromScale(0.88, y), Size = UDim2.fromScale(0.08, 0.055), BackgroundTransparency = 1,
			Font = PIX, TextScaled = true, TextColor3 = BONE, Text = "0", ZIndex = 2 }, bg)
		UI.lobbyVotes[m.key] = { fill = fill, n = n }
	end
	UI.lobbyTip = make("TextLabel", { Position = UDim2.fromScale(0.04, 0.92), Size = UDim2.fromScale(0.92, 0.05), BackgroundTransparency = 1,
		Font = BOLD, TextScaled = true, TextColor3 = Color3.fromRGB(170, 200, 180), Text = TIPS[1], ZIndex = 2 }, bg)
end

local function fmt(t)
	t = math.max(0, math.floor(t))
	return string.format("%02d:%02d", math.floor(t / 60), t % 60)
end

local function refreshLobbyScreen()
	buildLobbyGui()
	if not UI.lobbyGui then return end
	local phase = gameState:GetAttribute("Phase")
	local t = gameState:GetAttribute("TimeLeft") or 0
	local need = gameState:GetAttribute("MinPlayers") or 2
	if phase == "Waiting" then
		UI.lobbyStatus.Text = "ОЖИДАНИЕ ИГРОКОВ"
		UI.lobbyBig.Text = string.format("%d / %d", #Players:GetPlayers(), need)
	elseif phase == "Countdown" then
		UI.lobbyStatus.Text = "ГОЛОСУЙ ЗА КАРТРИДЖ · СТАРТ ЧЕРЕЗ"
		UI.lobbyBig.Text = tostring(t)
	elseif phase == "Match" or phase == "Ending" then
		local info = mapByKey[gameState:GetAttribute("MapKey") or ""]
		local alive = 0
		for _, s in ipairs(decode("Roster", {})) do
			if s.s == "alive" then alive += 1 end
		end
		UI.lobbyStatus.Text = "ИДЁТ МАТЧ: " .. (info and info.name or "") .. " · ЖИВЫХ " .. alive
		UI.lobbyBig.Text = fmt(t)
	else
		UI.lobbyStatus.Text = "ЗАГРУЗКА КАРТРИДЖА…"
		UI.lobbyBig.Text = "..."
	end
	local votes = decode("Votes", {})
	local total = 0
	for _, n in pairs(votes) do total += n end
	for key, v in pairs(UI.lobbyVotes) do
		local n = votes[key] or 0
		v.n.Text = tostring(n)
		tween(v.fill, 0.3, { Size = UDim2.fromScale(total > 0 and n / total or 0, 1) })
	end
end

-- подсказка про голосование внизу экрана в лобби
UI.voteHolder, UI.voteBody = tape(gui, {
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -76), Size = UDim2.fromOffset(560, 30), Rotation = 1, Visible = false, ZIndex = 20,
}, 151)
UI.voteText = make("TextLabel", {
	BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 21, Font = HEAVY, TextSize = 14, TextColor3 = INK, Text = "",
}, UI.voteBody)
UI.voteScale = make("UIScale", { Scale = 1 }, UI.voteHolder)

------------------------------------------------------------------------
-- ОСВЕЩЕНИЕ ПО ЗОНАМ (клиентские пресеты)
------------------------------------------------------------------------
local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
local cc = make("ColorCorrectionEffect", { Name = "P2D_Color" }, Lighting)
local bloom = make("BloomEffect", { Name = "P2D_Bloom", Intensity = 0.6, Size = 24, Threshold = 1.6 }, Lighting)
local PRESETS = {
	Lobby = { light = { ClockTime = 0, Brightness = 1, Ambient = Color3.fromRGB(44, 56, 50), OutdoorAmbient = Color3.fromRGB(30, 40, 36),
		FogColor = Color3.fromRGB(6, 14, 10), FogStart = 60, FogEnd = 320 },
		atm = { Density = 0.25, Color = Color3.fromRGB(30, 60, 45), Decay = Color3.fromRGB(10, 20, 14), Haze = 1 },
		cc = { Contrast = 0.1, Saturation = -0.05, TintColor = Color3.fromRGB(235, 255, 240) }, bloom = 0.7 },
	Stage = { light = { ClockTime = 0, Brightness = 0.6, Ambient = Color3.fromRGB(26, 22, 30), OutdoorAmbient = Color3.fromRGB(12, 10, 16),
		FogColor = Color3.fromRGB(0, 0, 0), FogStart = 80, FogEnd = 500 },
		atm = { Density = 0, Color = Color3.fromRGB(0, 0, 0), Decay = Color3.fromRGB(0, 0, 0), Haze = 0 },
		cc = { Contrast = 0.15, Saturation = 0, TintColor = Color3.fromRGB(255, 245, 240) }, bloom = 1 },
	Hills = { light = { ClockTime = 17.7, Brightness = 1.6, Ambient = Color3.fromRGB(80, 44, 44), OutdoorAmbient = Color3.fromRGB(130, 64, 58),
		FogColor = Color3.fromRGB(90, 20, 24), FogStart = 40, FogEnd = 330 },
		atm = { Density = 0.4, Color = Color3.fromRGB(150, 44, 40), Decay = Color3.fromRGB(70, 10, 16), Haze = 2 },
		cc = { Contrast = 0.12, Saturation = 0.05, TintColor = Color3.fromRGB(255, 225, 220) }, bloom = 0.5 },
	Arcade = { light = { ClockTime = 0, Brightness = 0.8, Ambient = Color3.fromRGB(60, 44, 84), OutdoorAmbient = Color3.fromRGB(24, 14, 36),
		FogColor = Color3.fromRGB(14, 6, 22), FogStart = 30, FogEnd = 260 },
		atm = { Density = 0.2, Color = Color3.fromRGB(60, 30, 90), Decay = Color3.fromRGB(20, 8, 30), Haze = 1 },
		cc = { Contrast = 0.12, Saturation = 0.15, TintColor = Color3.fromRGB(250, 235, 255) }, bloom = 1.1 },
	Maze = { light = { ClockTime = 0, Brightness = 0.7, Ambient = Color3.fromRGB(34, 40, 84), OutdoorAmbient = Color3.fromRGB(22, 28, 70),
		FogColor = Color3.fromRGB(0, 0, 12), FogStart = 20, FogEnd = 230 },
		atm = { Density = 0.3, Color = Color3.fromRGB(10, 14, 40), Decay = Color3.fromRGB(4, 4, 20), Haze = 1 },
		cc = { Contrast = 0.15, Saturation = 0.1, TintColor = Color3.fromRGB(230, 235, 255) }, bloom = 1.2 },
	Room = { light = { ClockTime = 0, Brightness = 0.9, Ambient = Color3.fromRGB(50, 56, 84), OutdoorAmbient = Color3.fromRGB(56, 66, 104),
		FogColor = Color3.fromRGB(10, 12, 24), FogStart = 70, FogEnd = 420 },
		atm = { Density = 0.22, Color = Color3.fromRGB(40, 50, 80), Decay = Color3.fromRGB(14, 16, 30), Haze = 1 },
		cc = { Contrast = 0.08, Saturation = -0.1, TintColor = Color3.fromRGB(230, 235, 255) }, bloom = 0.8 },
}
local zones = decode("Zones", {})
local currentPreset = nil
local function applyPreset(name, instant)
	if name == currentPreset then return end
	local p = PRESETS[name]
	if not p then return end
	currentPreset = name
	local t = instant and 0.01 or 1.5
	pcall(function()
		Lighting.ClockTime = p.light.ClockTime
		tween(Lighting, t, {
			Brightness = p.light.Brightness, Ambient = p.light.Ambient, OutdoorAmbient = p.light.OutdoorAmbient,
			FogColor = p.light.FogColor, FogStart = p.light.FogStart, FogEnd = p.light.FogEnd,
		})
		if atmosphere then tween(atmosphere, t, p.atm) end
		tween(cc, t, p.cc)
		tween(bloom, t, { Intensity = p.bloom })
	end)
end
local function zoneAt(pos)
	for _, z in ipairs(zones) do
		local d = pos - Vector3.new(z.x, z.y, z.z)
		if math.abs(d.X) <= z.h and math.abs(d.Z) <= z.h and math.abs(d.Y) <= 160 then return z.k end
	end
	return nil
end

------------------------------------------------------------------------
-- АНИМАЦИИ ОКРУЖЕНИЯ ПО ТЕГАМ (жетоны, вывески, мигающие лампы, кольца)
------------------------------------------------------------------------
local tagged = { P2D_Spin = {}, P2D_Token = {}, P2D_Flicker = {}, P2D_Blink = {}, P2D_Pulse = {}, P2D_SpinModel = {} }
for tagName, set in pairs(tagged) do
	local function add(inst)
		if inst:IsA("Model") then
			set[inst] = { base = inst:GetPivot(), seed = math.random() * 10 }
		elseif inst:IsA("BasePart") then
			set[inst] = { base = inst.CFrame, color = inst.Color, tr = inst.Transparency, seed = math.random() * 10 }
		end
	end
	for _, inst in ipairs(CollectionService:GetTagged(tagName)) do add(inst) end
	CollectionService:GetInstanceAddedSignal(tagName):Connect(add)
	CollectionService:GetInstanceRemovedSignal(tagName):Connect(function(inst) set[inst] = nil end)
end
local flickerClock = 0

------------------------------------------------------------------------
-- ВИДИМОСТЬ И ТЕКСТЫ
------------------------------------------------------------------------
local function refreshTop()
	local phase = gameState:GetAttribute("Phase")
	local showTime = phase == "Match" or phase == "Countdown" or phase == "Selection"
	if not showTime then UI.timeText.Text = "--:--" end
	local text = ""
	if phase == "Waiting" then
		text = string.format("ОЖИДАНИЕ ИГРОКОВ  %d / %d", #Players:GetPlayers(), gameState:GetAttribute("MinPlayers") or 2)
	elseif phase == "Countdown" then
		text = "ГОЛОСУЙ ЗА КАРТРИДЖ · СТАРТ СКОРО"
	elseif phase == "Selection" then
		text = gameState:GetAttribute("SelectLocked") and "ВСЕ НА СЦЕНЕ!" or "ВЫБОР ГЕРОЕВ"
	elseif phase == "Match" then
		if gameState:GetAttribute("EscapeOpen") then
			text = "ВЫХОД ОТКРЫТ: " .. (gameState:GetAttribute("ExitName") or "")
		else
			text = string.format("ЖЕТОНЫ  %d / %d", gameState:GetAttribute("Tokens") or 0, gameState:GetAttribute("TokensNeeded") or 0)
		end
	elseif phase == "Ending" then
		text = "МАТЧ ОКОНЧЕН"
	end
	UI.objText.Text = text
	UI.objHolder.Visible = text ~= ""
end

local lastBars = false
function refreshVisibility()
	local phase = gameState:GetAttribute("Phase")
	local inMatch = player:GetAttribute("InMatch") == true
	local status = player:GetAttribute("Status")
	local role = player:GetAttribute("Role")
	local playing = (phase == "Match" or phase == "Ending") and inMatch
	local alive = playing and status == "alive"
	local bars = alive and phase == "Match"
	local selecting = camOn

	UI.clockRoot.Visible = true
	UI.listRoot.Visible = (playing or spectating) and rowCount > 0 and not selecting
	UI.selfRoot.Visible = bars
	setBust(bars)
	UI.abilityRoot.Visible = bars and role == "Killer"
	UI.controlsHint.Visible = bars
	UI.controlsHint.Text = role == "Killer" and "ЛКМ — удар   Q — способность   SHIFT — бег" or "SHIFT — бег   собирай жетоны   ищи выход"
	if UI.touchSprint then UI.touchSprint.Visible = bars end
	if UI.touchAbility then UI.touchAbility.Visible = bars and role == "Killer" end
	if bars ~= lastBars then
		lastBars = bars
		if bars then sprintHeld = false end
	end

	local canWatch = phase == "Match" and not alive and #aliveTargets() > 0
	UI.watchButton.Visible = canWatch and not spectating
	UI.specRoot.Visible = spectating
	if spectating and not canWatch then stopSpectate() UI.specRoot.Visible = false end

	local inLobby = not inMatch and not selecting and (phase == "Waiting" or phase == "Countdown")
	UI.voteHolder.Visible = inLobby
	if inLobby then
		local v = player:GetAttribute("Vote")
		local info = v and mapByKey[v]
		UI.voteText.Text = info and ("ТВОЙ ГОЛОС: " .. info.name .. "  ·  встань на другой картридж, чтобы сменить")
			or "ВСТАНЬ НА ПЛАТФОРМУ КАРТРИДЖА, ЧТОБЫ ВЫБРАТЬ УРОВЕНЬ"
	end
	if selecting then
		UI.clockRoot.AnchorPoint = Vector2.new(1, 0)
		UI.clockRoot.Position = UDim2.new(1, -6, 0, 8)
	else
		UI.clockRoot.AnchorPoint = Vector2.new(0.5, 0)
		UI.clockRoot.Position = UDim2.new(0.5, 0, 0, 8)
	end
end

------------------------------------------------------------------------
-- ЗДОРОВЬЕ / ВЫНОСЛИВОСТЬ / СПОСОБНОСТЬ
------------------------------------------------------------------------
local curHealth, curMax = 100, 100
local ghostF = 1
local function setHealth(h, maxH)
	curHealth, curMax = h, math.max(1, maxH)
	local f = math.clamp(h / curMax, 0, 1)
	tween(UI.hpFill, 0.2, { Size = UDim2.fromScale(f, 1) })
	UI.hpCounter.Text = "x" .. tostring(math.max(0, math.ceil(h)))
end

local function refreshSelfStyle()
	local role = player:GetAttribute("Role")
	local id = player.Character and player.Character:GetAttribute("CharId")
	local c = id and charById[id]
	if role == "Killer" then
		UI.hpFill.BackgroundColor3 = c and charColor(c):Lerp(BLOOD, 0.4) or BLOOD
		UI.hpCaption.Text = (c and upper(c.name) or "ПАЛАЧ") .. " · ЖЕРТВ: " .. tostring(player:GetAttribute("Kills") or 0)
		UI.hpCaption.TextColor3 = BLOOD_HI
		UI.portText.Text = "EXE"
	else
		UI.hpFill.BackgroundColor3 = c and charColor(c) or Color3.fromRGB(80, 60, 200)
		UI.hpCaption.Text = c and (c.name .. " · " .. (c.role or "")) or ""
		UI.hpCaption.TextColor3 = Color3.fromRGB(220, 210, 200)
		UI.portText.Text = "P" .. tostring(player:GetAttribute("Port") or "?")
	end
end

local boosted, exhausted = false, false
local function refreshStamina()
	local v = player:GetAttribute("Stamina") or 0
	local m = player:GetAttribute("MaxStamina") or 100
	tween(UI.stFill, 0.1, { Size = UDim2.fromScale(math.clamp(v / math.max(m, 1), 0, 1), 1) })
	UI.stText.Text = "x" .. tostring(v)
	exhausted = player:GetAttribute("Exhausted") == true
	boosted = player:GetAttribute("Boosted") == true
	if boosted then
		UI.stFill.BackgroundColor3 = Color3.fromRGB(255, 226, 120)
		UI.stText.TextColor3 = Color3.fromRGB(150, 90, 0)
	elseif exhausted then
		UI.stFill.BackgroundColor3 = Color3.fromRGB(255, 150, 90)
		UI.stText.TextColor3 = Color3.fromRGB(140, 40, 10)
	else
		UI.stFill.BackgroundColor3 = C_LAV
		UI.stText.TextColor3 = C_LAV_TXT
	end
end

local function flash(amount)
	UI.damageFlash.BackgroundTransparency = 1 - (amount or 0.45)
	tween(UI.damageFlash, 0.5, { BackgroundTransparency = 1 })
end

local function bindCharacter(char)
	local hum = char:WaitForChild("Humanoid")
	local last = hum.Health
	setHealth(hum.Health, hum.MaxHealth)
	ghostF = 1
	hum.HealthChanged:Connect(function(h)
		if h < last then
			flash()
			bustHit = 1
			sfx("slash", 0.4, 0.8)
		end
		last = h
		setHealth(h, hum.MaxHealth)
	end)
	hum:GetPropertyChangedSignal("MaxHealth"):Connect(function() setHealth(hum.Health, hum.MaxHealth) end)
	char:GetAttributeChangedSignal("CharId"):Connect(function()
		refreshSelfStyle()
		if bustShown then
			task.delay(0.3, function()
				if bustShown then buildBust() end
			end)
		end
	end)
	refreshSelfStyle()
end
player.CharacterAdded:Connect(bindCharacter)
if player.Character then task.spawn(bindCharacter, player.Character) end

------------------------------------------------------------------------
-- ЭФФЕКТЫ С СЕРВЕРА: жетон, удар, помехи, подсветка, прятки
------------------------------------------------------------------------
local revealHighlights = {}
local vanishUntilLocal = 0
fxEvent.OnClientEvent:Connect(function(kind, a, b)
	if kind == "token" then
		sfx("ping", 0.6, 1.3)
		showToast(string.format("+1 ЖЕТОН  (%d / %d)", a or 0, b or 0), "good")
		UI.objScale.Scale = 1.25
		tween(UI.objScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	elseif kind == "hit" then
		showStatic(0.15, 0.5)
	elseif kind == "landed" then
		flash(0.15)
	elseif kind == "static" then
		showStatic(a or 1.5, 1)
		showToast("ПОМЕХИ! Сбой видит тебя сквозь стены", "bad")
	elseif kind == "giggle" then
		showStatic(0.3, 0.4)
		showToast("Где-то рядом хихикают… Бинки исчез", "bad")
	elseif kind == "reveal" then
		for _, h in ipairs(revealHighlights) do h:Destroy() end
		revealHighlights = {}
		for _, s in ipairs(decode("Roster", {})) do
			if s.s == "alive" then
				local p = Players:GetPlayerByUserId(s.id)
				if p and p.Character then
					-- локальная подсветка (видна только Сбою)
					table.insert(revealHighlights, make("Highlight", {
						FillColor = Color3.fromRGB(120, 235, 255), FillTransparency = 0.6,
						OutlineColor = WHITE, DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
					}, p.Character))
				end
			end
		end
		showStatic(0.4, 0.6)
		task.delay(a or 5, function()
			for _, h in ipairs(revealHighlights) do h:Destroy() end
			revealHighlights = {}
		end)
	elseif kind == "vanish" then
		vanishUntilLocal = os.clock() + (a or 6)
		showToast("ТЫ НЕВИДИМ — удар раскроет тебя", "warn")
	elseif kind == "dash" then
		showStatic(0.12, 0.3)
	end
end)

------------------------------------------------------------------------
-- ПЕРЕХОДЫ МЕЖДУ ЭТАПАМИ (лобби -> сцена -> матч -> итоги -> лобби)
------------------------------------------------------------------------
local lastPhase, phaseToken = nil, 0
function onPhase(force)
	local phase = gameState:GetAttribute("Phase")
	if phase == lastPhase and not force then return end
	local prev = lastPhase
	lastPhase = phase
	phaseToken += 1
	local my = phaseToken

	if phase == "Waiting" or phase == "Countdown" then
		myList, myPick = nil, nil
		buildSelection()
		UI.resultsRoot.Visible = false
	end
	local involved = myList ~= nil

	if phase == "ToSelection" then
		if involved then screenOff(0.8) end
	elseif phase == "Selection" then
		if involved then
			setSelectionVisible(true)
			refreshSelection()
			refreshMonitorKiller()
			screenOn(1)
		end
	elseif phase == "Starting" then
		if involved then
			screenOff(0.8)
			task.delay(0.9, function()
				if my == phaseToken then setSelectionVisible(false) end
			end)
		end
	elseif phase == "Match" then
		setSelectionVisible(false)
		if player:GetAttribute("InMatch") then
			screenOn(1.2)
			task.delay(0.5, function()
				if my == phaseToken then showTitleCard() end
			end)
		elseif crtIsOff then
			screenOn(0.8)
		end
	elseif phase == "Ending" then
		stopSpectate()
	elseif phase == "Returning" then
		screenOff(0.8)
		task.delay(0.9, function()
			if my == phaseToken then
				setSelectionVisible(false)
				UI.resultsRoot.Visible = false
			end
		end)
	else
		setSelectionVisible(false)
		if crtIsOff then screenOn(prev == nil and 1.4 or 1) end
	end
	-- не участвуешь в переходе — экран не должен остаться чёрным
	local keepsDark = ((phase == "ToSelection" or phase == "Starting") and involved) or phase == "Returning"
	if crtIsOff and not keepsDark then screenOn(0.8) end
	refreshTop()
	refreshVisibility()
end

------------------------------------------------------------------------
-- КАЖДЫЙ КАДР: часы, полосы, модель, камера сцены, монитор, окружение
------------------------------------------------------------------------
local lastTimeLeft, timeChangedAt = nil, os.clock()
local shownT = 0
local glow, glowS = 0, 0
local tension, redness, shake = 0, 0, 0
local TEXT_CALM, TEXT_RED = C_YELLOW, Color3.fromRGB(240, 70, 60)
local zoneCheckAt = 0
local specRetryAt = 0

local function triggerBonus() glow = 1 end

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	local phase = gameState:GetAttribute("Phase")
	local t = gameState:GetAttribute("TimeLeft") or 0
	local timed = phase == "Match" or phase == "Countdown" or phase == "Selection"
	local match = phase == "Match"
	local sc = hudScale()
	UI.listScale.Scale = sc
	UI.selfScale.Scale = sc
	UI.abilityScale.Scale = sc
	UI.specScale.Scale = sc
	UI.watchScale.Scale = sc
	UI.voteScale.Scale = sc
	if not UI.resultsRoot.Visible then UI.resultsScale.Scale = sc end

	-- часы: спокойно -> тревога (<=60 c) -> критично (<=10 c)
	local crit = match and t <= 10
	local tense = match and t <= 60
	tension = approach(tension, crit and 1 or (tense and 0.4 or 0), dt, 3)
	redness = approach(redness, crit and 1 or (tense and 0.45 or 0), dt, 3)
	shake = approach(shake, crit and (1 + 0.7 * (10 - math.max(t, 0)) / 10) or (tense and 0.16 or 0), dt, 2.5)
	glow = math.max(0, glow - dt / 2.4)
	glowS = approach(glowS, glow, dt, 6)

	local smooth = t
	if timed then smooth = t - math.clamp(now - timeChangedAt, 0, 0.999) end
	if math.abs(smooth - shownT) > 1.2 then
		shownT = approach(shownT, smooth, dt, 5)
	else
		shownT = smooth
	end
	if timed then UI.timeText.Text = fmt(math.ceil(shownT)) end
	if timed then
		UI.secondHand.Rotation = -(shownT % 60) * 6
	else
		UI.secondHand.Rotation = now * 90
	end
	UI.minuteHand.Rotation = -((shownT / 60) % 60) * 6
	UI.hourHand.Rotation = -((shownT / 3600) % 12) * 30

	local r = math.clamp(redness + glowS * 0.9, 0, 1)
	UI.faceStroke.Color = BLACK:Lerp(BLOOD_HI, r)
	UI.clockFace.BackgroundColor3 = UI.FACE_CALM:Lerp(UI.FACE_ALERT, r)
	UI.timeText.TextColor3 = TEXT_CALM:Lerp(TEXT_RED, r)
	for i, d in ipairs(UI.splatter) do
		d.BackgroundTransparency = 1 - r * (0.5 + 0.05 * i)
	end
	UI.clockDanger.Visible = r > 0.05
	local pulse = 0.5 + 0.5 * math.sin(now * (4 + 6 * tension))
	for i, st in ipairs(UI.clockRings) do
		st.Transparency = math.clamp(1 - r * (1 - 0.25 * (i - 1)) + pulse * 0.25, 0, 1)
	end
	UI.clockGlow.BackgroundTransparency = 1 - 0.25 * r * pulse
	for _, b in ipairs(UI.plateBlades) do b.BackgroundColor3 = BLOOD:Lerp(BLOOD_HI, 0.5 + 0.5 * r) end

	local freq = 12 + 30 * shake
	local nx = math.noise(now * freq, 1.3) * 2
	local ny = math.noise(now * freq, 7.7) * 2
	local nr = math.noise(now * freq, 4.2) * 2
	local cs = camOn and sc * 0.75 or sc
	UI.clockScale.Scale = cs * (1 + 0.045 * tension * math.max(0, math.sin(now * 9)) ^ 2)
	UI.clockFrame.Rotation = -5 + nr * shake * 5
	UI.clockFrame.Position = UDim2.fromOffset(120 + nx * shake * 5, 10 + ny * shake * 5)

	-- карточки игроков: здоровье и выносливость
	for _, cd in ipairs(cards) do
		local p = Players:GetPlayerByUserId(cd.userId)
		local hum = p and p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		if cd.isKiller then
			local v = p and p:GetAttribute("Stamina")
			local m = p and p:GetAttribute("MaxStamina")
			if v and m then
				cd.fill.Size = UDim2.fromScale(math.clamp(v / math.max(m, 1), 0, 1), 1)
				cd.hpText.Text = "x" .. tostring(p:GetAttribute("Kills") or 0)
			end
			if cd.rings then
				for i, st in ipairs(cd.rings) do
					st.Transparency = 0.15 * (i - 1) + 0.35 * (0.5 + 0.5 * math.sin(now * 3 + i))
				end
			end
			cd.stamFill.Size = UDim2.fromScale(1, 1)
		elseif cd.status == "alive" and hum then
			local f = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
			cd.shownHp = approach(cd.shownHp, f, dt, 8)
			cd.fill.Size = UDim2.fromScale(cd.shownHp, 1)
			cd.fill.BackgroundColor3 = f < 0.35 and C_DEAD:Lerp(C_GOLD, 0.5 + 0.5 * math.sin(now * 8)) or C_ALIVE
			cd.hpText.Text = "x" .. tostring(math.max(0, math.ceil(hum.Health)))
			local v = p:GetAttribute("Stamina")
			local m = p:GetAttribute("MaxStamina")
			if v and m then cd.stamFill.Size = UDim2.fromScale(math.clamp(v / math.max(m, 1), 0, 1), 1) end
		end
	end

	-- своя полоса: след урона, низкое здоровье, выносливость
	local f = math.clamp(curHealth / curMax, 0, 1)
	ghostF = approach(ghostF, f, dt, 2.2)
	if ghostF < f then ghostF = f end
	UI.hpGhost.Size = UDim2.fromScale(ghostF, 1)
	local low = UI.selfRoot.Visible and math.clamp((0.4 - f) / 0.4, 0, 1) or 0
	local beat = math.max(0, math.sin(now * math.pi * (1.4 + 3 * (1 - f)))) ^ 3
	UI.hpCounter.TextColor3 = C_YELLOW:Lerp(BLOOD_HI, low * beat)
	UI.stFill.BackgroundTransparency = exhausted and 0.3 * (0.5 + 0.5 * math.sin(now * 14)) or 0
	bustHit = math.max(0, bustHit - dt * 2.5)
	UI.selfShake.Position = UDim2.fromOffset(math.noise(now * 30, 2) * 10 * bustHit, math.noise(now * 30, 5) * 6 * bustHit)
	UI.bustVP.ImageColor3 = WHITE:Lerp(Color3.fromRGB(255, 80, 80), bustHit)

	-- модель повторяет движение: стойка / шаг / бег
	if bustModel and bustShown then
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local speed = hum and hum.MoveDirection.Magnitude > 0.1 and hum.WalkSpeed or 0
		local want = speed > 20 and "run" or (speed > 0 and "walk" or "idle")
		if not bustTracks[want] then want = bustTracks.walk and speed > 0 and "walk" or "idle" end
		if want ~= bustState and bustTracks[want] then
			for k, tr in pairs(bustTracks) do
				if k ~= want and tr.IsPlaying then tr:Stop(0.25) end
			end
			bustTracks[want]:Play(0.25)
			bustState = want
		end
		local head = bustModel:FindFirstChild("Head")
		if head then
			local target = head.Position + Vector3.new(0, -0.9, 0)
			local sway = math.sin(now * 0.9) * 0.4
			UI.bustCam.CFrame = CFrame.lookAt(target + Vector3.new(2.6 + sway, 0.5, -5.6), target)
		end
	end

	-- способность Палача
	if UI.abilityRoot.Visible then
		local id = player.Character and player.Character:GetAttribute("CharId")
		local c = id and charById[id]
		local ab = c and c.ability
		local readyAt = player:GetAttribute("AbilityReadyAt") or 0
		local untilT = player:GetAttribute("AbilityUntil") or 0
		local sNow = Workspace:GetServerTimeNow()
		local left = readyAt - sNow
		UI.abilityTitle.Text = ab and (ab.name .. "  [Q]") or "СПОСОБНОСТЬ"
		UI.abilityDesc.Text = ab and ab.text or ""
		if untilT > sNow then
			UI.abilityText.Text = "ACTIVE"
			UI.abilityFill.Size = UDim2.fromScale(math.clamp((untilT - sNow) / math.max(ab and ab.dur or 1, 0.1), 0, 1), 1)
			UI.abilityFill.BackgroundColor3 = C_GOLD
		elseif left > 0 then
			UI.abilityText.Text = string.format("%d", math.ceil(left))
			UI.abilityFill.Size = UDim2.fromScale(1 - math.clamp(left / math.max(ab and ab.cd or 1, 1), 0, 1), 1)
			UI.abilityFill.BackgroundColor3 = BLOOD
		else
			UI.abilityText.Text = "READY"
			UI.abilityFill.Size = UDim2.fromScale(1, 1)
			UI.abilityFill.BackgroundColor3 = BLOOD_HI:Lerp(C_GOLD, 0.3 + 0.3 * math.sin(now * 6))
		end
		for _, b in ipairs(UI.abilityBlades) do b.Visible = left <= 0 end
		if UI.touchAbility then UI.touchAbility.Text = left > 0 and tostring(math.ceil(left)) or "EXE" end
		UI.hpLabel.Text = ""
		if vanishUntilLocal > now then
			UI.hpLabel.Text = "НЕВИДИМ " .. math.ceil(vanishUntilLocal - now)
		end
	else
		UI.hpLabel.Text = ""
	end

	-- виньетка
	local alpha = 0.42 + 0.18 * tension + 0.28 * low * (0.6 + 0.4 * beat)
	local vcol = BLACK:Lerp(Color3.fromRGB(80, 0, 0), math.clamp(low * 0.9 + redness * 0.25, 0, 1))
	if vanishUntilLocal > now then vcol = Color3.fromRGB(60, 20, 90) end
	for _, vf in ipairs(UI.vigFrames) do
		vf.BackgroundColor3 = vcol
		vf.BackgroundTransparency = 1 - math.clamp(alpha, 0, 0.95)
	end

	-- помехи
	local sOn = now < staticUntil
	UI.staticRoot.Visible = sOn
	if sOn then
		local k = math.clamp((staticUntil - now) / 0.4, 0.2, 1) * staticStrength
		for _, bar in ipairs(UI.staticBars) do
			bar.Position = UDim2.fromScale(math.random() * 0.4 - 0.2, math.random())
			bar.Size = UDim2.new(math.random() * 0.8 + 0.4, 0, 0, math.random(2, 22))
			local g = math.random(120, 255)
			bar.BackgroundColor3 = math.random() < 0.15 and Color3.fromRGB(255, 40, 40) or Color3.fromRGB(g, g, g)
			bar.BackgroundTransparency = 1 - k * math.random() * 0.7
		end
	end

	-- камера сцены выбора: подиумы в верхней части экрана, лёгкое покачивание
	if camOn then
		local S = gameState:GetAttribute("StageCenter")
		if typeof(S) == "Vector3" then
			camera = Workspace.CurrentCamera
			local vp = camera.ViewportSize
			local aspect = vp.X / math.max(vp.Y, 1)
			local fov = 40
			local H = math.max(32, 60 / aspect)
			local D = H / (2 * math.tan(math.rad(fov / 2)))
			local hc = 0.2 * H
			local sway = math.sin(now * 0.35) * 1.2
			local target = CFrame.lookAt(S + Vector3.new(sway, hc + math.sin(now * 0.5) * 0.2, -D), S + Vector3.new(sway * 0.4, hc, 0))
			camera.FieldOfView = fov
			if camFresh then
				camera.CFrame = target
				camFresh = false
			else
				camera.CFrame = camera.CFrame:Lerp(target, 1 - math.exp(-dt * 3))
			end
		end
	end

	-- монитор Палача: опускается после его выбора, качается на тросах
	if camOn and findStage() and monitorModel then
		monitorAlpha = approach(monitorAlpha, monitorTarget, dt, monitorTarget > 0 and 2.6 or 4)
		local lowered = monitorModel:GetAttribute("Lowered")
		local raised = monitorModel:GetAttribute("Raised")
		if typeof(lowered) == "CFrame" and typeof(raised) == "CFrame" then
			local e = monitorAlpha
			local swing = math.sin(now * 2.2) * 0.04 * e * math.max(0, 1 - math.abs(monitorTarget - monitorAlpha) * 3)
			monitorModel:PivotTo(raised:Lerp(lowered, e) * CFrame.Angles(0, 0, swing))
		end
		if UI.monitorRec then UI.monitorRec.TextTransparency = (math.floor(now * 1.5) % 2 == 0) and 0 or 1 end
		if UI.monitorNoise and monitorTarget > 0 and math.random() < 0.02 then
			UI.monitorNoise.BackgroundTransparency = 0.6
			tween(UI.monitorNoise, 0.15, { BackgroundTransparency = 1 })
		end
		if UI.monitorClone then
			local head = UI.monitorClone:FindFirstChild("Head")
			if head then
				local target = head.Position + Vector3.new(0, -1.1, 0)
				UI.monitorCam.CFrame = CFrame.lookAt(target + Vector3.new(1.6 + math.sin(now * 0.7) * 0.6, 0.6, -6.4), target)
			end
		end
	elseif not camOn then
		monitorAlpha = 0
	end

	-- наблюдение
	if spectating and specTarget and now >= specRetryAt then
		specRetryAt = now + 0.5
		local p = Players:GetPlayerByUserId(specTarget)
		local hum = p and p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		camera = Workspace.CurrentCamera
		if hum and camera.CameraSubject ~= hum then camera.CameraSubject = hum end
	end

	-- окружение по тегам
	for part, d in pairs(tagged.P2D_Spin) do
		if part.Parent then part.CFrame = d.base * CFrame.Angles(0, now * (part:GetAttribute("Speed") or 2), 0) end
	end
	for part, d in pairs(tagged.P2D_Token) do
		if part.Parent then
			part.CFrame = CFrame.new(d.base.Position + Vector3.new(0, math.sin(now * 2 + d.seed) * 0.4, 0)) * CFrame.Angles(0, now * 2.4 + d.seed, 0)
		end
	end
	for mdl, d in pairs(tagged.P2D_SpinModel) do
		if mdl.Parent then mdl:PivotTo(d.base * CFrame.Angles(0, now * (mdl:GetAttribute("Speed") or 1), 0)) end
	end
	for part, d in pairs(tagged.P2D_Blink) do
		if part.Parent then
			local on = math.sin(now * math.pi * (part:GetAttribute("Rate") or 1) + d.seed) > -0.2
			part.Transparency = on and d.tr or 0.85
		end
	end
	for part, d in pairs(tagged.P2D_Pulse) do
		if part.Parent then
			part.Color = d.color:Lerp(WHITE, 0.35 * (0.5 + 0.5 * math.sin(now * 2 + d.seed * 3)))
		end
	end
	flickerClock += dt
	if flickerClock > 0.08 then
		flickerClock = 0
		for part, d in pairs(tagged.P2D_Flicker) do
			if part.Parent then
				local strong = part:GetAttribute("Strong")
				local roll = math.random()
				if roll < (strong and 0.25 or 0.03) then
					part.Color = d.color:Lerp(BLACK, math.random() * (strong and 0.7 or 0.85))
				else
					part.Color = d.color
				end
			end
		end
	end

	-- освещение по зоне, где находится камера
	if now >= zoneCheckAt then
		zoneCheckAt = now + 0.5
		camera = Workspace.CurrentCamera
		local z = zoneAt(camera.CFrame.Position) or zoneAt(camera.Focus.Position)
		if z then applyPreset(z) end
		if UI.lobbyBlink then UI.lobbyBlink.TextTransparency = (math.floor(now * 1.6) % 2 == 0) and 0 or 1 end
		if UI.lobbyTip and math.floor(now) % 6 == 0 then UI.lobbyTip.Text = TIPS[(math.floor(now / 6) % #TIPS) + 1] end
		refreshLobbyScreen()
	end
end)

------------------------------------------------------------------------
-- ПОДПИСКИ
------------------------------------------------------------------------
local lastBonusSeq = gameState:GetAttribute("BonusSeq") or 0

gameState.AttributeChanged:Connect(function(name)
	if name == "TimeLeft" then
		local t = gameState:GetAttribute("TimeLeft")
		if t ~= lastTimeLeft then
			lastTimeLeft = t
			timeChangedAt = os.clock()
			local ph = gameState:GetAttribute("Phase")
			if ph == "Countdown" and t <= 5 and t > 0 then sfx("tick", 0.5, 1.2) end
			if ph == "Match" and t <= 10 and t > 0 then sfx("tick", 0.6, 0.7) end
		end
	elseif name == "Roster" or name == "Killer" then
		rebuildRoster()
		if spectating then focusSpectate() end
	elseif name == "Taken" or name == "Stage" or name == "SelectLocked" then
		refreshSelection()
		refreshMonitorKiller()
	elseif name == "Characters" then
		loadCharacters()
		buildSelection()
		rebuildRoster()
	elseif name == "Maps" then
		loadMaps()
		if UI.lobbyGui then UI.lobbyGui:Destroy() UI.lobbyGui = nil end
	elseif name == "Zones" then
		zones = decode("Zones", {})
	elseif name == "BonusSeq" then
		local seq = gameState:GetAttribute("BonusSeq") or 0
		if seq ~= lastBonusSeq then
			lastBonusSeq = seq
			triggerBonus()
		end
	elseif name == "EscapeOpen" then
		if gameState:GetAttribute("EscapeOpen") then
			showStatic(0.3, 0.5)
			sfx("ping", 0.7, 0.6)
		end
	elseif name == "Phase" then
		onPhase()
	end
	refreshTop()
	refreshVisibility()
end)

player.AttributeChanged:Connect(function(name)
	if name == "Stamina" or name == "MaxStamina" or name == "Exhausted" or name == "Boosted" then
		refreshStamina()
	elseif name == "Role" or name == "Port" or name == "Kills" then
		refreshSelfStyle()
	end
	refreshVisibility()
end)

Players.PlayerAdded:Connect(refreshTop)
Players.PlayerRemoving:Connect(function() task.defer(refreshTop) end)

buildSelection()
rebuildRoster()
refreshStamina()
refreshTop()
refreshVisibility()
applyPreset("Lobby", true)
onPhase()
