--[[
	PRESS2DIE — GameClient (LocalScript)  ->  StarterPlayer > StarterPlayerScripts

	Интерфейс в духе старых консолей и аркадных автоматов, но «испорченный»:
	• пиксельные рамки со срезанными углами, пиксельные иконки вместо подписей
	  (сердце — здоровье, молния — выносливость, череп — Палач, дверь — выход);
	• глитч-текст с RGB-расслоением, помехи, ЭЛТ-включение и выключение экрана;
	• слева сверху — список игроков: портрет в наклонной рамке цвета роли, имя,
	  сегментная полоса здоровья со счётчиком и тонкая полоса выносливости;
	• слева снизу — своя анимированная 3D-модель над полосами, рядом ячейка способности (Q);
	• сверху — часы-таймер в том же стиле, под ними — дверь выхода и фигурки выживших;
	• сцена выбора — «аркадный» экран выбора бойца: 6 ячеек выживших по ролям
	  (у Палача своя таблица), монитор с Палачом опускается после его выбора;
	• экран автокинотеатра в лобби, заставка уровня, итоги, наблюдение, свет по зонам.
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
local function decode(attr, default)
	local ok, data = pcall(HttpService.JSONDecode, HttpService, gameState:GetAttribute(attr) or "")
	if ok and type(data) == "table" then return data end
	return default
end
local function fmt(t)
	t = math.max(0, math.floor(t))
	return string.format("%02d:%02d", math.floor(t / 60), t % 60)
end
local function rgb(t) return Color3.fromRGB(t[1], t[2], t[3]) end

local UI = {} -- дескрипторы интерфейса (Luau: не больше 200 локальных в функции)
local U = {}  -- «фирменный» набор элементов: пиксельные рамки, иконки, глитч-текст, полосы

local C = {
	ink = Color3.fromRGB(8, 7, 10),
	panel = Color3.fromRGB(16, 14, 20),
	panel2 = Color3.fromRGB(28, 25, 34),
	edge = Color3.fromRGB(78, 72, 92),
	bone = Color3.fromRGB(236, 228, 210),
	dim = Color3.fromRGB(150, 144, 160),
	blood = Color3.fromRGB(140, 16, 24),
	red = Color3.fromRGB(240, 46, 46),
	hp = Color3.fromRGB(96, 226, 110),
	hpMid = Color3.fromRGB(244, 206, 56),
	hpLow = Color3.fromRGB(240, 56, 48),
	st = Color3.fromRGB(110, 206, 255),
	stEx = Color3.fromRGB(255, 138, 56),
	stBoost = Color3.fromRGB(255, 232, 90),
	gold = Color3.fromRGB(255, 205, 70),
	esc = Color3.fromRGB(80, 220, 255),
	cyan = Color3.fromRGB(0, 255, 230),
	magenta = Color3.fromRGB(255, 0, 110),
	black = Color3.new(0, 0, 0),
	white = Color3.new(1, 1, 1),
}
local F = {
	pix = Enum.Font.Arcade,        -- пиксельный шрифт: цифры и латиница
	heavy = Enum.Font.GothamBlack, -- кириллица: заголовки
	bold = Enum.Font.GothamBold,
	med = Enum.Font.GothamMedium,
}

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
-- ФИРМЕННЫЙ СТИЛЬ
------------------------------------------------------------------------
-- пиксельная рамка: края без углов (как окна в 8/16-битных играх), блик сверху и тень снизу
function U.panel(parent, props, bg, edge, px)
	px = px or 3
	local f = make("Frame", { BackgroundTransparency = 1, BorderSizePixel = 0 }, parent)
	for k, v in pairs(props) do f[k] = v end
	local z = f.ZIndex
	local edges = {}
	local function bar(pos, size)
		table.insert(edges, make("Frame", { Position = pos, Size = size, BackgroundColor3 = edge or C.edge, BorderSizePixel = 0, ZIndex = z }, f))
	end
	bar(UDim2.fromOffset(px, 0), UDim2.new(1, -2 * px, 0, px))
	bar(UDim2.new(0, px, 1, -px), UDim2.new(1, -2 * px, 0, px))
	bar(UDim2.fromOffset(0, px), UDim2.new(0, px, 1, -2 * px))
	bar(UDim2.new(1, -px, 0, px), UDim2.new(0, px, 1, -2 * px))
	local body = make("Frame", {
		Position = UDim2.fromOffset(px, px), Size = UDim2.new(1, -2 * px, 1, -2 * px),
		BackgroundColor3 = bg or C.panel, BorderSizePixel = 0, ZIndex = z,
	}, f)
	local th = math.max(1, px - 1)
	make("Frame", { Size = UDim2.new(1, 0, 0, th), BackgroundColor3 = C.white, BackgroundTransparency = 0.86, BorderSizePixel = 0, ZIndex = z }, body)
	make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, th),
		BackgroundColor3 = C.black, BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = z }, body)
	return f, body, edges
end
function U.edge(edges, color, tr)
	for _, e in ipairs(edges) do
		e.BackgroundColor3 = color
		if tr then e.BackgroundTransparency = tr end
	end
end

-- пиксельная иконка из строк; соседние одинаковые пиксели склеиваются в одну полосу
function U.icon(parent, grid, px, colors, props)
	local w, h = #grid[1], #grid
	local f = make("Frame", { Size = UDim2.fromOffset(w * px, h * px), BackgroundTransparency = 1 }, parent)
	if props then
		for k, v in pairs(props) do f[k] = v end
	end
	local parts = {}
	for y, row in ipairs(grid) do
		local x = 1
		while x <= w do
			local ch = string.sub(row, x, x)
			if ch ~= "." then
				local x2 = x
				while x2 < w and string.sub(row, x2 + 1, x2 + 1) == ch do x2 += 1 end
				local p = make("Frame", {
					Position = UDim2.fromOffset((x - 1) * px, (y - 1) * px), Size = UDim2.fromOffset((x2 - x + 1) * px, px),
					BackgroundColor3 = colors[ch] or C.white, BorderSizePixel = 0, ZIndex = f.ZIndex,
				}, f)
				parts[ch] = parts[ch] or {}
				table.insert(parts[ch], p)
				x = x2 + 1
			else
				x += 1
			end
		end
	end
	return f, parts
end
function U.tint(parts, ch, color, tr)
	for _, p in ipairs(parts[ch] or {}) do
		p.BackgroundColor3 = color
		if tr then p.BackgroundTransparency = tr end
	end
end

-- глитч-текст: основной слой + пурпурный и бирюзовый сдвинутые слои (RGB-расслоение ЭЛТ)
U.glitches = {}
local ROOT_KEYS = { Position = true, Size = true, AnchorPoint = true, ZIndex = true, Rotation = true, Visible = true, LayoutOrder = true }
function U.glitch(parent, props, amp)
	local root = make("Frame", { BackgroundTransparency = 1 }, parent)
	local base = {}
	for k, v in pairs(props) do
		if ROOT_KEYS[k] then root[k] = v else base[k] = v end
	end
	local function layer(color, tr)
		local t = make("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = root.ZIndex }, root)
		for k, v in pairs(base) do t[k] = v end
		if color then
			t.TextColor3 = color
			t.TextTransparency = tr
			t.TextStrokeTransparency = 1
		end
		return t
	end
	local g = { root = root, amp = amp or 1, burst = 0 }
	g.r = layer(C.magenta, 0.3)
	g.b = layer(C.cyan, 0.35)
	g.main = layer(nil)
	table.insert(U.glitches, g)
	return g
end
function U.gtext(g, text)
	g.main.Text = text
	g.r.Text = text
	g.b.Text = text
end
function U.gburst(g, t) g.burst = math.max(g.burst, t or 0.4) end

-- сегментная полоса (как шкалы в аркадах): «след» урона, заливка, блик и насечки
function U.bar(parent, props, segs, fillColor)
	local holder, body, edges = U.panel(parent, props, C.ink, C.black, 2)
	local z = holder.ZIndex
	local ghost = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.white, BackgroundTransparency = 0.3, BorderSizePixel = 0, ZIndex = z + 1 }, body)
	local fill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = fillColor, BorderSizePixel = 0, ZIndex = z + 2 }, body)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(C.white, Color3.fromRGB(150, 150, 150)) }, fill)
	make("Frame", { Position = UDim2.fromScale(0, 0.14), Size = UDim2.new(1, 0, 0.2, 0), BackgroundColor3 = C.white,
		BackgroundTransparency = 0.7, BorderSizePixel = 0, ZIndex = z + 2 }, fill)
	segs = segs or 10
	for i = 1, segs - 1 do
		make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(i / segs, 0), Size = UDim2.new(0, 2, 1, 0),
			BackgroundColor3 = C.ink, BorderSizePixel = 0, ZIndex = z + 3 }, body)
	end
	return { holder = holder, body = body, fill = fill, ghost = ghost, edges = edges, shown = 1, ghostF = 1 }
end
-- цвет здоровья: зелёный -> жёлтый -> красный (понятен без подписи)
function U.hpColor(f)
	if f > 0.5 then return C.hpMid:Lerp(C.hp, (f - 0.5) * 2) end
	return C.hpLow:Lerp(C.hpMid, math.clamp((f - 0.2) / 0.3, 0, 1))
end

-- концентрические красные рамки опасности (у Палача и у часов в конце матча)
function U.danger(parent, size, z)
	local f = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, ZIndex = z,
	}, parent)
	local rings = {}
	for i, k in ipairs({ 1.1, 1.26, 1.44 }) do
		local ring = make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(k, k), BackgroundTransparency = 1, ZIndex = z,
		}, f)
		table.insert(rings, stroke(ring, C.red, i == 1 and 3 or 2))
	end
	return f, rings
end

-- клавиша-подсказка в пиксельной рамке
function U.key(parent, props, text)
	local f, body = U.panel(parent, props, C.bone, C.ink, 2)
	make("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = f.ZIndex + 1, Font = F.pix,
		TextScaled = true, TextColor3 = C.ink, Text = text }, body)
	return f
end

------------------------------------------------------------------------
-- ПИКСЕЛЬНЫЕ ИКОНКИ
------------------------------------------------------------------------
local ICON = {
	heart = { ".##.##.", "#o#####", "#o#####", "#######", ".#####.", "..###..", "...#..." },
	bolt = { "....##", "...##.", "..##..", ".#####", "#####.", "..##..", ".##...", "##...." },
	skull = { ".#####.", "#######", "#xx#xx#", "#xx#xx#", "###x###", ".#####.", ".#.#.#." },
	door = { "#######", "#ooooo#", "#ooooo#", "#ooooo#", "#ooo#o#", "#ooooo#", "#ooooo#", "#ooooo#" },
	person = { ".###.", ".###.", "..#..", "#####", "..#..", ".#.#.", "#...#" },
	star = { "...#...", "...#...", "#.###.#", ".#####.", "..###..", ".##.##.", "#.....#" },
	cross = { "..###..", "..###..", "#######", "#######", "#######", "..###..", "..###.." },
	shield = { "#######", "#o#####", "#o#####", "#######", ".#####.", "..###..", "...#..." },
	eye = { "..#####..", ".##ooo##.", "##oo#oo##", ".##ooo##.", "..#####.." },
	camera = { ".yy.###..", "#########", "###xxx###", "##xxoxx##", "###xxx###", "#########" },
	fist = { "..####..", ".######.", "########", "########", "#o######", "#oo#####", ".#######", "..#####.", "..xxxxx." },
	knife = { "......##", ".....###", "....###.", "...###..", ".x###...", "..xx....", ".hhx....", "hh......" },
	note = { "...#####", "...#####", "...#...#", "...#...#", "...#...#", ".###.###", "####.###", ".##...#." },
	bandage = { ".....##.", "....####", "...#o#o#", "..#o#o#.", ".#o#o#..", "####....", ".##....." },
	cloud = { "...##....", "..####.#.", ".########", "#########", "#########", ".#######." },
	dash = { "##..##...", ".##..##..", "..##..##.", "...##..##", "..##..##.", ".##..##..", "##..##..." },
	ghost = { "..####..", ".######.", "#xx##xx#", "#xx##xx#", "########", "########", "########", "#.#..#.#" },
	arrow = { "...#...", "..###..", ".#####.", "#######", "..###..", "..###..", "..###.." },
	lock = { ".###.", "#...#", "#...#", "#####", "##.##", "##.##", "#####" },
	counter = { "...#....", "..##....", ".#######", "########", ".#######", "..##...#", "...#...#", ".......#" },
	godeye = { "#...#...#", ".#.....#.", "..#####..", ".##ooo##.", "##oo#oo##", ".##ooo##.", "..#####.." },
	pulse = { "....#....", "...##....", "...#.#...", "####.#.##", ".....#.#.", ".....##..", ".....#..." },
	medkit = { "..###..", "#######", "###o###", "##ooo##", "###o###", "#######" },
	station = { "..ooo..", "..ooo..", "#######", "#.#.#.#", "#######", ".#...#.", ".#...#." },
	wire = { "#.......#", "#.......#", "#########", "#.......#", "#.......#" },
	bat = { "......##", ".....###", "....###.", "...###..", "..###...", ".##.....", "##......", "#......." },
	orb = { "#.....#", "..###..", ".#ooo#.", ".#ooo#.", ".#ooo#.", "..###..", "#.....#" },
	bubble = { "..###..", ".#...#.", "#.....#", "#..o..#", "#.....#", ".#...#.", "..###.." },
	mana = { "..#..", ".#o#.", "#ooo#", ".#o#.", "..#.." },
}
local ROLE_ICON = { stun = "star", support = "cross", lone = "shield", killer = "skull" }
local ABILITY_ICON = {
	punch = "fist", counter = "counter", bat = "bat", flash = "camera", heal = "cross", selfheal = "medkit",
	station = "station", tripwire = "wire", godeye = "godeye", adrenaline = "pulse", telekinesis = "orb", shield = "bubble",
	dash = "dash", reveal = "eye", vanish = "ghost",
}
C.mana = Color3.fromRGB(120, 150, 255)

------------------------------------------------------------------------
-- ЭКРАННЫЕ ЭФФЕКТЫ: виньетка, сканлайны, вспышки, помехи, ЭЛТ-выключение
------------------------------------------------------------------------
UI.vigFrames = {}
local function vigEdge(pos, size, anchor, rot)
	local f = make("Frame", {
		Position = pos, Size = size, AnchorPoint = anchor, BackgroundColor3 = C.black,
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
			BackgroundColor3 = C.black, BackgroundTransparency = 0.9, BorderSizePixel = 0, ZIndex = 90,
		}, UI.scanRoot)
		make("UIGradient", { Rotation = 90, Transparency = seq }, f)
		table.insert(UI.scanStrips, f)
	end
end
buildScanlines()
-- «бегущая» светлая полоса старого кинескопа
UI.rollBar = make("Frame", {
	Size = UDim2.new(1, 0, 0, 90), BackgroundColor3 = C.white, BackgroundTransparency = 0.97, BorderSizePixel = 0, ZIndex = 90,
}, UI.scanRoot)
make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) }) }, UI.rollBar)

-- цветная вспышка на весь экран (урон, аптечка, бумбокс, ослепление)
UI.flash = make("Frame", {
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(190, 0, 0),
	BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1,
}, gui)
UI.whiteout = make("Frame", { -- ослепление «Вспышкой»: поверх всего HUD
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 252, 240),
	BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 85,
}, gui)
local blur = make("BlurEffect", { Name = "P2D_Blur", Size = 0 }, Lighting)
local function flash(color, amount, t)
	UI.flash.BackgroundColor3 = color or Color3.fromRGB(190, 0, 0)
	UI.flash.BackgroundTransparency = 1 - (amount or 0.45)
	tween(UI.flash, t or 0.5, { BackgroundTransparency = 1 })
end

-- помехи (статика): случайные полосы + сдвиг «строк» кадра
UI.staticRoot = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 95 }, gui)
UI.staticBars = {}
for _ = 1, 26 do
	table.insert(UI.staticBars, make("Frame", { BorderSizePixel = 0, ZIndex = 95, BackgroundColor3 = C.white }, UI.staticRoot))
end
local staticUntil, staticStrength = 0, 0
local function showStatic(dur, strength)
	staticUntil = math.max(staticUntil, os.clock() + dur)
	staticStrength = strength or 1
end

-- ЭЛТ-переход: экран схлопывается в линию и точку (и обратно)
UI.crtRoot = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 100 }, gui)
UI.crtTop = make("Frame", { Size = UDim2.fromScale(1, 0.5), BackgroundColor3 = C.black, BorderSizePixel = 0, ZIndex = 100 }, UI.crtRoot)
UI.crtBottom = make("Frame", {
	AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0.5),
	BackgroundColor3 = C.black, BorderSizePixel = 0, ZIndex = 100,
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
-- ДАННЫЕ ПЕРСОНАЖЕЙ, РОЛЕЙ И КАРТ (с сервера)
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
local roles = decode("Roles", {})

local function charColor(c) return rgb(c.color) end
local function unknownChar(id) return { id = id or "?", name = "?", role = "", color = { 180, 180, 180 }, killer = false } end
local function groupOf(c) return c and (c.group or (c.killer and "killer")) or "lone" end
local function roleColor(c)
	local r = roles[groupOf(c)]
	if r then return rgb(r.color) end
	return c and c.killer and C.red or C.dim
end
local function roleName(c)
	local r = roles[groupOf(c)]
	return r and r.name or ""
end
-- иконка роли в цвете роли
local function roleIcon(parent, c, px, props)
	return U.icon(parent, ICON[ROLE_ICON[groupOf(c)] or "shield"], px, { ["#"] = roleColor(c), o = C.white, x = C.ink }, props)
end

------------------------------------------------------------------------
-- ПОРТРЕТЫ: мультяшные «фото» героев, повторяют костюмы на моделях
------------------------------------------------------------------------
local function portrait(parent, c, z, dead)
	z = z or parent.ZIndex + 1
	local V2 = Vector2.new
	local R = UDim.new(1, 0)
	local function px(x, y, w, h, col, round, rot)
		local f = make("Frame", {
			AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(x, y), Size = UDim2.fromScale(w, h),
			BackgroundColor3 = col, BorderSizePixel = 0, Rotation = rot or 0, ZIndex = z,
		}, parent)
		if round then corner(f, round) end
		return f
	end
	local DARK = Color3.fromRGB(34, 16, 16)
	local function deadEyes(y, gap, s)
		for _, sx in ipairs({ -1, 1 }) do
			px(0.5 + sx * gap, y, s * 1.2, 0.03, DARK, nil, 45)
			px(0.5 + sx * gap, y, s * 1.2, 0.03, DARK, nil, -45)
		end
	end
	-- огромные мультяшные глаза
	local function eyes(y, gap, s, iris)
		if dead then return deadEyes(y, gap, s) end
		for _, sx in ipairs({ -1, 1 }) do
			px(0.5 + sx * gap, y, s, s * 1.3, C.white, R)
			px(0.5 + sx * gap + sx * 0.012, y + 0.012, s * 0.5, s * 0.68, iris or C.ink, R)
			px(0.5 + sx * gap + sx * 0.004, y - 0.02, s * 0.18, s * 0.2, C.white, R)
		end
	end
	local SKIN = Color3.fromRGB(242, 198, 160)
	local id = c.id
	if id == "alex" then
		-- уличный боец: красная повязка с хвостами, бинты на кулаке, серьёзные брови
		local band = Color3.fromRGB(220, 30, 30)
		px(0.5, 0.96, 0.92, 0.3, Color3.fromRGB(36, 36, 42), UDim.new(0.35, 0))
		px(0.5, 0.52, 0.56, 0.58, SKIN, R)
		px(0.5, 0.3, 0.58, 0.22, Color3.fromRGB(34, 26, 22), UDim.new(0.5, 0))
		for _, a in ipairs({ -30, 0, 30 }) do
			px(0.5 + math.sin(math.rad(a)) * 0.16, 0.2, 0.1, 0.16, Color3.fromRGB(34, 26, 22), nil, a)
		end
		px(0.5, 0.36, 0.6, 0.07, band)
		px(0.84, 0.4, 0.22, 0.05, band, nil, 22)
		px(0.86, 0.47, 0.18, 0.05, band, nil, 40)
		if dead then deadEyes(0.53, 0.1, 0.1) else
			eyes(0.53, 0.1, 0.11)
			px(0.4, 0.44, 0.14, 0.035, Color3.fromRGB(30, 22, 18), nil, 20)
			px(0.6, 0.44, 0.14, 0.035, Color3.fromRGB(30, 22, 18), nil, -20)
		end
		px(0.5, 0.7, 0.14, 0.025, Color3.fromRGB(90, 40, 36))
		px(0.66, 0.6, 0.1, 0.04, Color3.fromRGB(238, 232, 214), nil, -20)
		px(0.2, 0.86, 0.26, 0.24, Color3.fromRGB(238, 232, 214), UDim.new(0.35, 0))
		for k = 0, 2 do px(0.2, 0.78 + k * 0.06, 0.26, 0.012, Color3.fromRGB(190, 180, 160)) end
	elseif id == "aisha" then
		-- неформалка: розовые волосы и хвостики, пузырь жвачки, джинсовка
		local pink, violet = Color3.fromRGB(255, 110, 190), Color3.fromRGB(170, 90, 230)
		px(0.5, 0.52, 0.66, 0.64, pink, R)
		px(0.16, 0.3, 0.22, 0.22, violet, R)
		px(0.84, 0.3, 0.22, 0.22, violet, R)
		px(0.5, 0.96, 0.82, 0.3, Color3.fromRGB(70, 100, 160), UDim.new(0.4, 0))
		px(0.36, 0.9, 0.1, 0.1, pink, UDim.new(0.3, 0))
		px(0.5, 0.54, 0.52, 0.54, Color3.fromRGB(205, 150, 120), R)
		px(0.54, 0.32, 0.5, 0.14, pink, UDim.new(0.5, 0), -12)
		eyes(0.53, 0.1, 0.12, Color3.fromRGB(140, 60, 160))
		if not dead then px(0.52, 0.72, 0.16, 0.16, Color3.fromRGB(255, 150, 210), R) end
		px(0.3, 0.64, 0.08, 0.035, Color3.fromRGB(255, 130, 160), UDim.new(0.5, 0))
		px(0.7, 0.64, 0.08, 0.035, Color3.fromRGB(255, 130, 160), UDim.new(0.5, 0))
	elseif id == "lilian" then
		-- медик: мятная форма, белая шапочка с красным крестом, пучок, румянец
		local hair = Color3.fromRGB(120, 70, 40)
		px(0.5, 0.52, 0.64, 0.64, hair, R)
		px(0.5, 0.14, 0.26, 0.22, hair, R)
		px(0.5, 0.96, 0.84, 0.3, Color3.fromRGB(110, 220, 200), UDim.new(0.35, 0))
		px(0.5, 0.88, 0.5, 0.03, Color3.fromRGB(60, 60, 66))
		px(0.5, 0.54, 0.52, 0.54, SKIN, R)
		px(0.5, 0.27, 0.36, 0.14, Color3.fromRGB(250, 250, 250), UDim.new(0.2, 0))
		px(0.5, 0.27, 0.12, 0.035, Color3.fromRGB(220, 40, 40))
		px(0.5, 0.27, 0.035, 0.1, Color3.fromRGB(220, 40, 40))
		eyes(0.54, 0.1, 0.12, Color3.fromRGB(40, 120, 70))
		px(0.31, 0.65, 0.08, 0.035, Color3.fromRGB(255, 150, 160), UDim.new(0.5, 0))
		px(0.69, 0.65, 0.08, 0.035, Color3.fromRGB(255, 150, 160), UDim.new(0.5, 0))
		px(0.5, 0.71, 0.1, 0.03, Color3.fromRGB(190, 60, 100), UDim.new(0.5, 0))
	elseif id == "greg" then
		-- потрёпанный инженер: комбинезон, гогглы на лбу, щетина, мешки под глазами
		local skin = Color3.fromRGB(210, 165, 130)
		px(0.5, 0.96, 0.96, 0.3, Color3.fromRGB(196, 118, 40), UDim.new(0.3, 0))
		px(0.32, 0.92, 0.06, 0.26, Color3.fromRGB(150, 90, 30))
		px(0.68, 0.92, 0.06, 0.26, Color3.fromRGB(150, 90, 30))
		px(0.5, 0.53, 0.54, 0.56, skin, R)
		for _, t in ipairs({ { 0.34, 0.27, 20 }, { 0.5, 0.24, -10 }, { 0.66, 0.27, -25 } }) do
			px(t[1], t[2], 0.18, 0.12, Color3.fromRGB(130, 122, 112), UDim.new(0.4, 0), t[3])
		end
		px(0.5, 0.36, 0.56, 0.04, Color3.fromRGB(40, 36, 32))
		for _, sx in ipairs({ -1, 1 }) do
			px(0.5 + sx * 0.1, 0.36, 0.13, 0.1, Color3.fromRGB(110, 220, 230), R)
		end
		if dead then deadEyes(0.52, 0.1, 0.09) else
			eyes(0.52, 0.1, 0.1)
			px(0.4, 0.49, 0.13, 0.04, skin:Lerp(C.black, 0.15))
			px(0.6, 0.49, 0.13, 0.04, skin:Lerp(C.black, 0.15))
		end
		px(0.5, 0.7, 0.38, 0.14, Color3.fromRGB(110, 100, 92), UDim.new(0.45, 0))
		px(0.52, 0.68, 0.12, 0.025, Color3.fromRGB(90, 40, 36), nil, -8)
	elseif id == "oscar" then
		-- тихоня: тёмный капюшон, бледное лицо, чёлка закрывает глаз, взгляд в пол
		local hair = Color3.fromRGB(22, 22, 28)
		px(0.5, 0.52, 0.72, 0.72, Color3.fromRGB(48, 48, 60), R)
		px(0.5, 0.96, 0.8, 0.3, Color3.fromRGB(40, 40, 50), UDim.new(0.35, 0))
		px(0.44, 0.9, 0.02, 0.14, Color3.fromRGB(200, 200, 205))
		px(0.56, 0.9, 0.02, 0.14, Color3.fromRGB(200, 200, 205))
		px(0.5, 0.55, 0.52, 0.54, Color3.fromRGB(226, 206, 192), R)
		px(0.5, 0.33, 0.56, 0.2, hair, UDim.new(0.5, 0))
		px(0.58, 0.46, 0.24, 0.2, hair, UDim.new(0.3, 0), -22)
		if dead then deadEyes(0.53, 0.09, 0.08) else
			px(0.41, 0.53, 0.11, 0.13, C.white, R)
			px(0.41, 0.57, 0.05, 0.06, C.ink, R)
		end
		px(0.41, 0.61, 0.1, 0.02, Color3.fromRGB(150, 130, 150))
		px(0.5, 0.71, 0.08, 0.02, Color3.fromRGB(120, 80, 80), nil, 6)
	elseif id == "felix" then
		-- маг: высокая синяя шляпа со звёздами, светящиеся глаза, плащ, сфера маны
		local hat = Color3.fromRGB(34, 44, 110)
		px(0.5, 0.96, 0.86, 0.3, Color3.fromRGB(20, 24, 60), UDim.new(0.35, 0))
		px(0.5, 0.9, 0.08, 0.1, Color3.fromRGB(90, 150, 255), nil, 45)
		px(0.5, 0.56, 0.5, 0.5, Color3.fromRGB(214, 214, 230), R)
		px(0.5, 0.36, 0.76, 0.07, hat, UDim.new(0.5, 0))
		px(0.5, 0.26, 0.4, 0.14, hat)
		px(0.53, 0.16, 0.26, 0.1, hat)
		px(0.58, 0.07, 0.14, 0.1, hat, nil, 20)
		px(0.5, 0.31, 0.42, 0.03, Color3.fromRGB(90, 150, 255))
		px(0.42, 0.2, 0.04, 0.04, Color3.fromRGB(255, 220, 90), R)
		px(0.6, 0.12, 0.035, 0.035, Color3.fromRGB(255, 220, 90), R)
		eyes(0.56, 0.09, 0.1, dead and C.ink or Color3.fromRGB(60, 140, 255))
		if not dead then px(0.86, 0.66, 0.14, 0.14, Color3.fromRGB(110, 170, 255), R) end
	elseif id == "executioner" then
		local sack = Color3.fromRGB(150, 115, 70)
		px(0.5, 0.97, 0.98, 0.3, Color3.fromRGB(60, 32, 30), UDim.new(0.3, 0))
		px(0.5, 0.98, 0.5, 0.28, Color3.fromRGB(150, 140, 120))
		px(0.5, 0.16, 0.14, 0.14, sack, nil, 20)
		px(0.5, 0.48, 0.62, 0.66, sack, UDim.new(0.25, 0))
		px(0.5, 0.79, 0.48, 0.05, Color3.fromRGB(100, 80, 50))
		for _, sx in ipairs({ -1, 1 }) do
			px(0.5 + sx * 0.13, 0.44, 0.17, 0.04, Color3.fromRGB(255, 40, 30), nil, 45)
			px(0.5 + sx * 0.13, 0.44, 0.17, 0.04, Color3.fromRGB(255, 40, 30), nil, -45)
		end
		px(0.5, 0.62, 0.32, 0.025, Color3.fromRGB(40, 20, 10))
		for _, x in ipairs({ -0.11, -0.04, 0.04, 0.11 }) do px(0.5 + x, 0.62, 0.012, 0.07, Color3.fromRGB(40, 20, 10)) end
	elseif id == "glitch" then
		px(0.5, 0.96, 0.6, 0.26, Color3.fromRGB(20, 20, 26), UDim.new(0.3, 0))
		px(0.5, 0.88, 0.6, 0.03, Color3.fromRGB(70, 230, 255))
		px(0.5, 0.94, 0.6, 0.02, Color3.fromRGB(255, 60, 200))
		px(0.38, 0.12, 0.025, 0.22, Color3.fromRGB(180, 180, 190), nil, -25)
		px(0.62, 0.12, 0.025, 0.22, Color3.fromRGB(180, 180, 190), nil, 25)
		px(0.5, 0.48, 0.78, 0.6, Color3.fromRGB(44, 44, 50), UDim.new(0.12, 0))
		local scr = px(0.46, 0.48, 0.58, 0.44, dead and Color3.fromRGB(30, 40, 44) or Color3.fromRGB(120, 235, 255), UDim.new(0.14, 0))
		for i, col in ipairs({ Color3.fromRGB(255, 60, 200), C.white, Color3.fromRGB(60, 255, 160) }) do
			make("Frame", { Position = UDim2.fromScale(0, 0.1 + i * 0.2), Size = UDim2.fromScale(1, 0.07), BackgroundColor3 = col,
				BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = z }, scr)
		end
		px(0.82, 0.42, 0.06, 0.06, Color3.fromRGB(110, 110, 120), R)
	elseif id == "binky" then
		local purple = Color3.fromRGB(150, 80, 220)
		for _, sx in ipairs({ -1, 1 }) do
			px(0.5 + sx * 0.17, 0.14, 0.14, 0.36, purple, UDim.new(0.5, 0), -14 * sx)
			px(0.5 + sx * 0.17, 0.16, 0.07, 0.26, Color3.fromRGB(255, 150, 200), UDim.new(0.5, 0), -14 * sx)
		end
		px(0.5, 0.97, 0.74, 0.26, purple, UDim.new(0.4, 0))
		px(0.5, 0.56, 0.72, 0.68, purple, R)
		for _, sx in ipairs({ -1, 1 }) do
			px(0.5 + sx * 0.14, 0.5, 0.17, 0.2, C.ink, R)
			if not dead then px(0.5 + sx * 0.14, 0.5, 0.06, 0.06, Color3.fromRGB(255, 30, 30), R) end
		end
		px(0.5, 0.62, 0.09, 0.08, Color3.fromRGB(220, 40, 40), R)
		px(0.5, 0.74, 0.42, 0.08, Color3.fromRGB(255, 250, 240), UDim.new(0.3, 0))
		for _, x in ipairs({ -0.12, -0.04, 0.04, 0.12 }) do px(0.5 + x, 0.74, 0.012, 0.07, Color3.fromRGB(40, 0, 0)) end
	else
		px(0.5, 0.95, 0.7, 0.3, C.edge, UDim.new(0.4, 0))
		px(0.5, 0.5, 0.5, 0.52, C.edge, R)
		make("TextLabel", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.5, 0.5),
			BackgroundTransparency = 1, Font = F.pix, TextScaled = true, TextColor3 = C.ink, Text = "?", ZIndex = z }, parent)
	end
end

-- рамка портрета: пиксельная, цвет роли, наклон; возвращает (holder, inner, edges)
local function portraitFrame(parent, props, c, dead, px)
	local holder, inner, edges = U.panel(parent, props, charColor(c):Lerp(C.black, 0.72), dead and C.dim or roleColor(c), px or 3)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(C.white, Color3.fromRGB(90, 90, 90)) }, inner)
	local art = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = holder.ZIndex + 1, ClipsDescendants = true }, inner)
	portrait(art, c, holder.ZIndex + 1, dead)
	if dead then
		make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.black, BackgroundTransparency = 0.45, BorderSizePixel = 0,
			ZIndex = holder.ZIndex + 3 }, inner)
	end
	return holder, inner, edges
end

------------------------------------------------------------------------
-- ЧАСЫ-ТАЙМЕР: наклонная пиксельная рамка, циферблат, табло с глитч-цифрами
------------------------------------------------------------------------
UI.clockRoot = make("Frame", {
	Name = "Clock", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.fromOffset(240, 206), BackgroundTransparency = 1, ZIndex = 5,
}, gui)
UI.clockScale = make("UIScale", { Scale = 1 }, UI.clockRoot)

UI.clockFrame = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(120, 10), Size = UDim2.fromOffset(112, 112),
	BackgroundTransparency = 1, Rotation = -5, ZIndex = 5,
}, UI.clockRoot)
make("Frame", { -- тень-ромб за рамкой, как у портретов в списке
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, -9, 0.5, 12), Size = UDim2.fromScale(0.94, 0.94),
	Rotation = 22, BackgroundColor3 = C.ink, BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = 4,
}, UI.clockFrame)
UI.clockDanger, UI.clockRings = U.danger(UI.clockFrame, 112, 5)
UI.clockDanger.Visible = false
UI.clockBox, UI.clockBody, UI.clockEdges = U.panel(UI.clockFrame, { Size = UDim2.fromScale(1, 1), ZIndex = 6 }, Color3.fromRGB(12, 11, 14), C.edge, 4)
UI.FACE_CALM = Color3.fromRGB(44, 40, 46)
UI.FACE_ALERT = Color3.fromRGB(110, 20, 26)
UI.clockFace = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.9, 0.9),
	BackgroundColor3 = UI.FACE_CALM, BorderSizePixel = 0, ZIndex = 8,
}, UI.clockBody)
corner(UI.clockFace, UDim.new(1, 0))
make("UIGradient", { Rotation = 90, Color = ColorSequence.new(C.white, Color3.fromRGB(120, 112, 112)) }, UI.clockFace)
UI.faceStroke = stroke(UI.clockFace, C.black, 3)
for i = 0, 11 do
	local holder = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 4, 0.86, 0), BackgroundTransparency = 1, Rotation = i * 30, ZIndex = 9,
	}, UI.clockFace)
	make("Frame", { Size = UDim2.new(1, 0, 0, i % 3 == 0 and 8 or 4), BackgroundColor3 = C.bone, BorderSizePixel = 0, ZIndex = 9 }, holder)
end
-- пиксельный череп в центре циферблата проступает, когда время на исходе
UI.faceSkull, UI.faceSkullParts = U.icon(UI.clockFace, ICON.skull, 4, { ["#"] = C.red, x = C.ink },
	{ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.62), ZIndex = 9 })
U.tint(UI.faceSkullParts, "#", C.red, 1)
U.tint(UI.faceSkullParts, "x", C.ink, 1)
local function hand(len, thick, color)
	local h = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(thick, len * 2), BackgroundTransparency = 1, ZIndex = 10,
	}, UI.clockFace)
	make("Frame", { Size = UDim2.fromScale(1, 0.5), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 10 }, h)
	return h
end
UI.hourHand = hand(20, 5, C.bone)
UI.minuteHand = hand(30, 4, C.bone)
UI.secondHand = hand(36, 2, C.red)
make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(8, 8),
	BackgroundColor3 = C.red, BorderSizePixel = 0, ZIndex = 11,
}, UI.clockFace)

-- табло: пиксельные цифры с RGB-расслоением
UI.clockPlate, UI.clockPlateBody, UI.plateEdges = U.panel(UI.clockRoot, {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(120, 128), Size = UDim2.fromOffset(146, 36), ZIndex = 6,
}, C.ink, C.edge, 3)
UI.timeG = U.glitch(UI.clockPlateBody, {
	Size = UDim2.fromScale(1, 1), ZIndex = 7, Font = F.pix, TextSize = 26, Text = "--:--",
	TextColor3 = C.gold, TextStrokeColor3 = C.black, TextStrokeTransparency = 0,
}, 1)

-- под часами: дверь выхода и фигурки выживших (живые / погибшие / сбежавшие)
UI.statusRow = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(120, 170), Size = UDim2.fromOffset(240, 26),
	BackgroundTransparency = 1, ZIndex = 6, Visible = false,
}, UI.clockRoot)
make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, UI.statusRow)
UI.doorIcon, UI.doorParts = U.icon(UI.statusRow, ICON.door, 3, { ["#"] = C.edge, o = C.blood }, { LayoutOrder = 0, ZIndex = 7 })
UI.doorGap = make("Frame", { LayoutOrder = 1, Size = UDim2.fromOffset(6, 2), BackgroundTransparency = 1 }, UI.statusRow)
UI.pips = {}

-- строка-цель (только когда есть что сказать: ожидание игроков, отсчёт, выход открыт)
UI.objBox, UI.objBody, UI.objEdges = U.panel(UI.clockRoot, {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(120, 200), Size = UDim2.fromOffset(300, 26), ZIndex = 6,
}, C.panel, C.edge, 2)
UI.objText = make("TextLabel", {
	BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 7, Font = F.heavy, TextSize = 13,
	TextColor3 = C.bone, Text = "",
}, UI.objBody)
UI.objScale = make("UIScale", { Scale = 1 }, UI.objBox)

local function rebuildPips()
	for _, p in ipairs(UI.pips) do p:Destroy() end
	UI.pips = {}
	for i, s in ipairs(decode("Roster", {})) do
		local col = (s.s == "escaped" and C.esc) or (s.s == "alive" and C.bone) or C.hpLow
		local c = charById[s.c or ""]
		local f, parts = U.icon(UI.statusRow, ICON.person, 3, { ["#"] = col }, { LayoutOrder = 10 + i, ZIndex = 7 })
		if s.s == "dead" then U.tint(parts, "#", col, 0.35) end
		if s.s == "alive" and c then
			make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 2), Size = UDim2.fromOffset(9, 3),
				BackgroundColor3 = roleColor(c), BorderSizePixel = 0, ZIndex = 7 }, f)
		end
		table.insert(UI.pips, f)
	end
end

------------------------------------------------------------------------
-- СПИСОК ИГРОКОВ (слева сверху): портрет в наклонной рамке, имя, здоровье, выносливость
------------------------------------------------------------------------
UI.listRoot = make("Frame", {
	Name = "PlayerList", Position = UDim2.fromOffset(18, 70), Size = UDim2.fromOffset(320, 10),
	AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Visible = false,
}, gui)
UI.listScale = make("UIScale", { Scale = 1 }, UI.listRoot)
make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }, UI.listRoot)
local cards = {}

local function buildCard(order, info, isKiller)
	local c = charById[info.c] or unknownChar(info.c)
	local status = info.s or "alive"
	local dead = status == "dead"
	local holder = make("Frame", { LayoutOrder = order, Size = UDim2.fromOffset(320, 76), BackgroundTransparency = 1 }, UI.listRoot)
	local card = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Rotation = -4, ZIndex = 2 }, holder)
	-- портрет справа, как в референсе: наклонная рамка с тенью
	local frame = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(276, 38), Size = UDim2.fromOffset(64, 64),
		BackgroundTransparency = 1, Rotation = 9, ZIndex = 3,
	}, card)
	make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, -7, 0.5, 9), Size = UDim2.fromScale(0.96, 0.96),
		Rotation = 22, BackgroundColor3 = C.ink, BackgroundTransparency = 0.1, BorderSizePixel = 0, ZIndex = 2,
	}, frame)
	local rings = nil
	if isKiller then
		local _, r = U.danger(frame, 64, 3)
		rings = r
	end
	local pf, inner = portraitFrame(frame, { Size = UDim2.fromScale(1, 1), ZIndex = 4 }, c, dead, 3)
	roleIcon(pf, c, 2, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 2, 1, -2), ZIndex = 9 })
	if dead then
		U.icon(inner, ICON.skull, 4, { ["#"] = C.hpLow, x = C.ink }, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 9 })
	elseif status == "escaped" then
		U.icon(inner, ICON.door, 4, { ["#"] = C.esc, o = C.ink }, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), ZIndex = 9 })
	end
	-- имя (у Палача — красное)
	make("TextLabel", {
		Position = UDim2.fromOffset(4, 2), Size = UDim2.fromOffset(228, 22), BackgroundTransparency = 1, ZIndex = 3,
		Font = F.bold, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = isKiller and C.red or (dead and C.dim or C.white), TextStrokeTransparency = 0.2, Text = info.n or "?",
	}, card)
	-- иконка + сегментная полоса + счётчик: у выжившего здоровье, у Палача выносливость и жертвы
	U.icon(card, isKiller and ICON.skull or ICON.heart, 2, { ["#"] = isKiller and C.red or C.hpLow, o = C.white, x = C.ink },
		{ Position = UDim2.fromOffset(18, 29), ZIndex = 3 })
	local bar = U.bar(card, { Position = UDim2.fromOffset(36, 27), Size = UDim2.fromOffset(150, 17), ZIndex = 3 }, 10,
		isKiller and C.red or C.hp)
	if dead then bar.fill.Size = UDim2.fromScale(0, 1) bar.ghost.Size = UDim2.fromScale(0, 1) end
	local cnt = make("TextLabel", {
		Position = UDim2.fromOffset(190, 25), Size = UDim2.fromOffset(46, 20), BackgroundTransparency = 1, ZIndex = 4,
		Font = F.pix, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.gold,
		TextStrokeTransparency = 0, Text = isKiller and ("x" .. tostring(info.k or 0)) or (dead and "x0" or "x100"),
	}, card)
	-- тонкая полоса выносливости
	local sb = make("Frame", {
		Position = UDim2.fromOffset(40, 48), Size = UDim2.fromOffset(144, 4),
		BackgroundColor3 = Color3.fromRGB(36, 36, 44), BorderSizePixel = 0, ZIndex = 3,
	}, card)
	local stamFill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.st, BorderSizePixel = 0, ZIndex = 4 }, sb)
	-- порт P1..P6 (у Палача — череп уже на полосе)
	if not isKiller then
		make("TextLabel", {
			Position = UDim2.fromOffset(0, 46), Size = UDim2.fromOffset(34, 14), BackgroundTransparency = 1, ZIndex = 3,
			Font = F.pix, TextSize = 11, TextColor3 = roleColor(c), TextStrokeTransparency = 0.3, Text = "P" .. tostring(info.p or "?"),
			TextXAlignment = Enum.TextXAlignment.Left,
		}, card)
	end
	table.insert(cards, { userId = info.id, isKiller = isKiller, bar = bar, cnt = cnt, stamFill = stamFill,
		rings = rings, status = status, frame = holder })
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
	rebuildPips()
	if refreshVisibility then refreshVisibility() end
end

------------------------------------------------------------------------
-- СВОЙ HUD (слева снизу): анимированная модель над полосами здоровья и выносливости,
-- справа — две ячейки навыков (Q и E). Подписей нет: сердце, молния, кристалл маны, иконки навыков.
------------------------------------------------------------------------
UI.selfRoot = make("Frame", {
	Name = "SelfHUD", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -14),
	Size = UDim2.fromOffset(548, 266), BackgroundTransparency = 1, Visible = false,
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
-- «пол» под моделью: пиксельная подставка-тень
make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(171, 168), Size = UDim2.fromOffset(120, 6),
	BackgroundColor3 = C.black, BackgroundTransparency = 0.5, BorderSizePixel = 0, ZIndex = 1 }, UI.selfShake)

-- имя героя и иконка роли над полосой
UI.selfRoleHolder = make("Frame", { Position = UDim2.fromOffset(84, 146), Size = UDim2.fromOffset(18, 18), BackgroundTransparency = 1, ZIndex = 6 }, UI.selfShake)
UI.hpCounter = make("TextLabel", {
	Position = UDim2.fromOffset(276, 140), Size = UDim2.fromOffset(96, 30), BackgroundTransparency = 1, ZIndex = 6,
	Font = F.pix, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.gold,
	TextStrokeColor3 = C.black, TextStrokeTransparency = 0, Text = "x100",
}, UI.selfShake)
UI.selfName = make("TextLabel", {
	Position = UDim2.fromOffset(106, 144), Size = UDim2.fromOffset(170, 22), BackgroundTransparency = 1, ZIndex = 6,
	Font = F.heavy, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.bone,
	TextStrokeTransparency = 0.2, Text = "",
}, UI.selfShake)

-- здоровье: сердце + широкая сегментная полоса
UI.heartIcon, UI.heartParts = U.icon(UI.selfShake, ICON.heart, 4, { ["#"] = C.hpLow, o = C.white }, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(56, 191), ZIndex = 5 })
UI.hpBar = U.bar(UI.selfShake, { Position = UDim2.fromOffset(78, 172), Size = UDim2.fromOffset(294, 38), ZIndex = 4 }, 12, C.hp)
-- выносливость: молния + полоса потоньше
UI.boltIcon, UI.boltParts = U.icon(UI.selfShake, ICON.bolt, 3, { ["#"] = C.st }, { Position = UDim2.fromOffset(48, 218), ZIndex = 5 })
UI.stBar = U.bar(UI.selfShake, { Position = UDim2.fromOffset(78, 218), Size = UDim2.fromOffset(240, 24), ZIndex = 4 }, 8, C.st)
UI.stBar.ghost.Visible = false
UI.stText = make("TextLabel", {
	Position = UDim2.fromOffset(322, 216), Size = UDim2.fromOffset(50, 28), BackgroundTransparency = 1, ZIndex = 6,
	Font = F.pix, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.st,
	TextStrokeColor3 = C.black, TextStrokeTransparency = 0, Text = "x100",
}, UI.selfShake)
-- мана (только у Феликса): кристалл + тонкая полоса
UI.manaRow = make("Frame", { Position = UDim2.fromOffset(0, 246), Size = UDim2.fromOffset(380, 18), BackgroundTransparency = 1, Visible = false, ZIndex = 4 }, UI.selfShake)
U.icon(UI.manaRow, ICON.mana, 3, { ["#"] = C.mana, o = C.white }, { Position = UDim2.fromOffset(50, 1), ZIndex = 5 })
UI.manaBar = U.bar(UI.manaRow, { Position = UDim2.fromOffset(78, 2), Size = UDim2.fromOffset(240, 14), ZIndex = 4 }, 5, C.mana)
UI.manaBar.ghost.Visible = false
UI.manaText = make("TextLabel", {
	Position = UDim2.fromOffset(322, 0), Size = UDim2.fromOffset(50, 18), BackgroundTransparency = 1, ZIndex = 6,
	Font = F.pix, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.mana,
	TextStrokeColor3 = C.black, TextStrokeTransparency = 0, Text = "x50",
}, UI.manaRow)
-- порт игрока (P1..P6) / череп Палача
UI.portBox, UI.portBody, UI.portEdges = U.panel(UI.selfShake, { Position = UDim2.fromOffset(0, 172), Size = UDim2.fromOffset(38, 38), ZIndex = 4 }, C.panel, C.edge, 2)
UI.portText = make("TextLabel", {
	BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 6, Font = F.pix, TextSize = 14, TextColor3 = C.bone, Text = "P1",
}, UI.portBody)
UI.portSkull = U.icon(UI.portBody, ICON.skull, 4, { ["#"] = C.red, x = C.ink }, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 6, Visible = false })
-- значок shift-lock рядом с портом (горит, когда включён)
UI.lockIcon, UI.lockParts = U.icon(UI.selfShake, ICON.lock, 3, { ["#"] = C.edge }, { Position = UDim2.fromOffset(12, 146), ZIndex = 6 })

-- ячейки навыков: иконка, затемнение-перезарядка сверху вниз, цифры, клавиша; полоса активности снизу
local SLOT_KEYS = { "Q", "E" }
UI.slots = {}
for i = 1, 2 do
	local sl = {}
	sl.box, sl.body, sl.edges = U.panel(UI.selfShake, { Position = UDim2.fromOffset(384 + (i - 1) * 82, 164), Size = UDim2.fromOffset(74, 74), ZIndex = 4 }, C.panel2, C.edge, 4)
	sl.iconHolder = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 5 }, sl.body)
	sl.shade = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.black, BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 7 }, sl.body)
	sl.cd = make("TextLabel", {
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 8, Font = F.pix, TextSize = 24,
		TextColor3 = C.bone, TextStrokeTransparency = 0, Text = "",
	}, sl.body)
	-- «сломано» (бита Айши): красный крест поверх ячейки
	sl.broken = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 9, Visible = false }, sl.body)
	for _, rot in ipairs({ 45, -45 }) do
		make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1.2, 0, 0, 6),
			Rotation = rot, BackgroundColor3 = C.red, BorderSizePixel = 0, ZIndex = 9 }, sl.broken)
	end
	sl.active = make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 7), Size = UDim2.new(1, 0, 0, 4),
		BackgroundColor3 = C.gold, BorderSizePixel = 0, ZIndex = 8, Visible = false }, sl.box)
	sl.key = U.key(sl.box, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(4, 4), Size = UDim2.fromOffset(24, 24), ZIndex = 10 }, SLOT_KEYS[i])
	sl.iconFor = nil
	UI.slots[i] = sl
end
local function skillsOf(c)
	return c and c.skills or {}
end
local function skillIcon(parent, sk, c, size, props)
	local grid = ICON[ABILITY_ICON[sk.id] or "star"]
	local px = math.max(2, math.floor(size / math.max(#grid[1], #grid)))
	return U.icon(parent, grid, px, { ["#"] = roleColor(c), o = C.white, x = C.ink, y = C.gold }, props)
end
local function setSlotIcons(c)
	local list = skillsOf(c)
	for i, sl in ipairs(UI.slots) do
		local sk = list[i]
		local id = sk and (c.id .. ":" .. sk.id)
		sl.box.Visible = sk ~= nil
		if id ~= sl.iconFor then
			sl.iconFor = id
			for _, ch in ipairs(sl.iconHolder:GetChildren()) do ch:Destroy() end
			if sk then
				skillIcon(sl.iconHolder, sk, c, 52, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 6 })
			end
		end
	end
end

-- подсказка управления справа снизу: только клавиши и иконки
UI.hintRoot = make("Frame", {
	AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -18, 1, -18), Size = UDim2.fromOffset(420, 30),
	BackgroundTransparency = 1, Visible = false,
}, gui)
UI.hintScale = make("UIScale", { Scale = 1 }, UI.hintRoot)
make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right,
	VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, UI.hintRoot)
local function hintPair(order, keyText, keyW, iconGrid, colors)
	local f = make("Frame", { LayoutOrder = order, Size = UDim2.fromOffset(keyW + 30, 28), BackgroundTransparency = 1 }, UI.hintRoot)
	U.key(f, { Size = UDim2.fromOffset(keyW, 24), Position = UDim2.fromOffset(0, 2), ZIndex = 2 }, keyText)
	U.icon(f, iconGrid, 3, colors, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, keyW + 5, 0.5, 0), ZIndex = 2 })
	return f
end
UI.hintRun = hintPair(1, "SHIFT", 58, ICON.bolt, { ["#"] = C.st })
UI.hintSkills = {}
for i = 1, 2 do
	UI.hintSkills[i] = make("Frame", { LayoutOrder = 1 + i, Size = UDim2.fromOffset(60, 28), BackgroundTransparency = 1 }, UI.hintRoot)
end
UI.hintLock = hintPair(4, "CTRL", 48, ICON.lock, { ["#"] = C.bone })
UI.hintHit = hintPair(5, "LMB", 42, ICON.knife, { ["#"] = C.bone, x = C.edge, h = Color3.fromRGB(120, 60, 40) })
UI.hintFor = nil
local function setHintSkills(c)
	local id = c and c.id
	if id == UI.hintFor then return end
	UI.hintFor = id
	local list = skillsOf(c)
	for i, f in ipairs(UI.hintSkills) do
		for _, ch in ipairs(f:GetChildren()) do ch:Destroy() end
		local sk = list[i]
		f.Visible = sk ~= nil
		if sk then
			U.key(f, { Size = UDim2.fromOffset(24, 24), Position = UDim2.fromOffset(0, 2), ZIndex = 2 }, SLOT_KEYS[i])
			skillIcon(f, sk, c, 24, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 29, 0.5, 0), ZIndex = 2 })
		end
	end
end

-- выбор станции Грега: ЛКМ — лечение, ПКМ — ускорение (на телефоне — тап по кнопке)
UI.placeRoot = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -120), Size = UDim2.fromOffset(300, 70),
	BackgroundTransparency = 1, Visible = false, ZIndex = 30,
}, gui)
UI.placeScale = make("UIScale", { Scale = 1 }, UI.placeRoot)
UI.placeButtons = {}
for i, it in ipairs({ { "heal", "LMB", ICON.cross, C.hp }, { "speed", "RMB", ICON.bolt, C.stBoost } }) do
	local b = make("TextButton", { Position = UDim2.fromOffset((i - 1) * 156, 0), Size = UDim2.fromOffset(144, 70), BackgroundTransparency = 1,
		AutoButtonColor = false, Text = "", ZIndex = 30 }, UI.placeRoot)
	local _, body = U.panel(b, { Size = UDim2.fromScale(1, 1), ZIndex = 30 }, C.panel, it[4], 4)
	U.icon(body, it[3], 5, { ["#"] = it[4] }, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0), ZIndex = 31 })
	U.key(body, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(52, 26), ZIndex = 31 }, it[2])
	UI.placeButtons[it[1]] = b
end
-- забегаем вперёд: логика навыков ниже (там видны все нужные состояния)
local trySkill, chooseStation
for kind, b in pairs(UI.placeButtons) do
	b.Activated:Connect(function() if chooseStation then chooseStation(kind) end end)
end

-- модель игрока в окне: повторяет стойку/шаг/бег, вздрагивает от урона
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
			or d:IsA("Sound") or d:IsA("ForceField") or d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Highlight") then
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

-- камера окна: крупные головы костюмов выше обычных — целимся по габаритам модели
local function bustTarget(model)
	local ok, cf, size = pcall(function() return model:GetBoundingBox() end)
	if ok and cf then return cf.Position + Vector3.new(0, size.Y * 0.08, 0), math.max(size.Y, 5) end
	local head = model:FindFirstChild("Head")
	return head and head.Position - Vector3.new(0, 0.9, 0) or Vector3.new(), 5
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
-- БЕГ: Shift / L3 / кнопка. Навыки: Q и E / Y и B / кнопки (логика — в разделе «НАВЫКИ»)
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

-- UI.touchSprint, UI.touchSkills — только на сенсорных устройствах
if UserInputService.TouchEnabled then
	local function touchButton(pos, size, edge, grid, colors)
		local b = make("TextButton", {
			AnchorPoint = Vector2.new(1, 1), Position = pos, Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1,
			AutoButtonColor = false, Text = "", Visible = false, ZIndex = 30,
		}, gui)
		U.panel(b, { Size = UDim2.fromScale(1, 1), ZIndex = 30 }, C.panel, edge, 4)
		if grid then
			U.icon(b, grid, math.floor(size * 0.5 / #grid[1]), colors, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 32 })
		end
		return b
	end
	UI.touchSprint = touchButton(UDim2.new(1, -30, 1, -170), 84, C.st, ICON.bolt, { ["#"] = C.st })
	UI.touchSprint.MouseButton1Down:Connect(function() setSprint(true) end)
	UI.touchSprint.MouseButton1Up:Connect(function() setSprint(false) end)
	UI.touchSprint.MouseLeave:Connect(function() setSprint(false) end)
	UI.touchSkills = {}
	for i, pos in ipairs({ UDim2.new(1, -124, 1, -200), UDim2.new(1, -124, 1, -116) }) do
		local b = touchButton(pos, 74, C.gold, nil, nil)
		b.Name = "TouchSkill" .. i
		local cd = make("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 33, Font = F.pix,
			TextSize = 24, TextColor3 = C.bone, TextStrokeTransparency = 0, Text = "" }, b)
		b.Activated:Connect(function() if trySkill then trySkill(i) end end)
		UI.touchSkills[i] = { button = b, cd = cd, iconFor = nil }
	end
end

------------------------------------------------------------------------
-- ОБЪЯВЛЕНИЯ: пиксельная плашка с цветной меткой слева
------------------------------------------------------------------------
UI.toastBox, UI.toastBody = U.panel(gui, {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 252), Size = UDim2.fromOffset(560, 36),
	Visible = false, ZIndex = 20,
}, C.panel, C.edge, 3)
UI.toastMark = make("Frame", { Size = UDim2.new(0, 8, 1, 0), BorderSizePixel = 0, ZIndex = 21, BackgroundColor3 = C.red }, UI.toastBody)
UI.toastG = U.glitch(UI.toastBody, {
	Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -28, 1, 0), ZIndex = 21,
	Font = F.heavy, TextSize = 17, TextColor3 = C.bone, TextTruncate = Enum.TextTruncate.AtEnd, Text = "",
}, 0.6)
UI.toastScale = make("UIScale", { Scale = 1 }, UI.toastBox)
UI.TOAST_COLORS = { info = C.edge, good = Color3.fromRGB(60, 200, 90), bad = C.red, warn = Color3.fromRGB(250, 170, 30) }
local toastToken = 0
local function showToast(text, kind)
	toastToken += 1
	local my = toastToken
	U.gtext(UI.toastG, text)
	U.gburst(UI.toastG, 0.35)
	UI.toastMark.BackgroundColor3 = UI.TOAST_COLORS[kind] or UI.TOAST_COLORS.info
	UI.toastBox.Visible = true
	UI.toastScale.Scale = 0.6
	tween(UI.toastScale, 0.25, { Scale = hudScale() }, Enum.EasingStyle.Back)
	task.delay(4, function()
		if my == toastToken then
			tween(UI.toastScale, 0.2, { Scale = 0.01 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.delay(0.22, function()
				if my == toastToken then UI.toastBox.Visible = false end
			end)
		end
	end)
end
announceEvent.OnClientEvent:Connect(function(text, kind)
	showToast(text, kind)
	if kind == "bad" then sfx("slash", 0.3, 0.6) else sfx("ping", 0.35, kind == "warn" and 0.8 or 1) end
end)

------------------------------------------------------------------------
-- ЗАСТАВКА УРОВНЯ (как в старых играх) + карточка роли
------------------------------------------------------------------------
UI.titleRoot = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 60 }, gui)
UI.titleBand = make("Frame", {
	AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(-1, 0.4), Size = UDim2.new(1, 0, 0, 124),
	BackgroundColor3 = C.ink, BackgroundTransparency = 0.08, BorderSizePixel = 0, ZIndex = 60, Rotation = -3,
}, UI.titleRoot)
make("Frame", { Position = UDim2.new(0, 0, 0, -6), Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = C.red, BorderSizePixel = 0, ZIndex = 60 }, UI.titleBand)
make("Frame", { Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = C.cyan, BackgroundTransparency = 0.4, BorderSizePixel = 0, ZIndex = 60 }, UI.titleBand)
UI.titleMap = U.glitch(UI.titleBand, {
	Position = UDim2.fromScale(0.08, 0.06), Size = UDim2.fromScale(0.84, 0.56), ZIndex = 61,
	Font = F.heavy, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.white, Text = "",
}, 2)
UI.titleSub = make("TextLabel", {
	Position = UDim2.fromScale(0.08, 0.64), Size = UDim2.fromScale(0.84, 0.28), BackgroundTransparency = 1, ZIndex = 61,
	Font = F.bold, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.gold, Text = "",
}, UI.titleBand)
UI.roleBox, UI.roleBody, UI.roleEdges = U.panel(UI.titleRoot, {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.56), Size = UDim2.fromOffset(640, 104), ZIndex = 61,
}, C.panel, C.edge, 4)
UI.roleArt = make("Frame", { Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(78, 78), BackgroundTransparency = 1, ZIndex = 62 }, UI.roleBody)
UI.roleTitle = make("TextLabel", {
	Position = UDim2.fromOffset(102, 8), Size = UDim2.new(1, -114, 0, 28), BackgroundTransparency = 1, ZIndex = 62,
	Font = F.heavy, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.bone, Text = "",
}, UI.roleBody)
UI.roleText = make("TextLabel", {
	Position = UDim2.fromOffset(102, 38), Size = UDim2.new(1, -114, 0, 52), BackgroundTransparency = 1, ZIndex = 62,
	Font = F.bold, TextSize = 14, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	TextColor3 = C.dim, Text = "",
}, UI.roleBody)
UI.roleScale = make("UIScale", { Scale = 1 }, UI.roleBox)
local titleToken = 0
local function showTitleCard()
	titleToken += 1
	local my = titleToken
	local info = mapByKey[gameState:GetAttribute("MapKey") or ""] or { name = "???", sub = "" }
	U.gtext(UI.titleMap, info.name)
	U.gburst(UI.titleMap, 1.2)
	UI.titleSub.Text = "PRESS 2 DIE  ·  " .. (info.sub or "")
	for _, ch in ipairs(UI.roleArt:GetChildren()) do ch:Destroy() end
	local id = player.Character and player.Character:GetAttribute("CharId")
	local c = id and charById[id]
	if c then portraitFrame(UI.roleArt, { Size = UDim2.fromScale(1, 1), ZIndex = 62 }, c, false, 3) end
	local parts = {}
	for i, sk in ipairs(c and c.skills or {}) do
		table.insert(parts, "[" .. (sk.key or (i == 1 and "Q" or "E")) .. "] " .. sk.name)
	end
	local abText = table.concat(parts, "   ")
	if player:GetAttribute("Role") == "Killer" then
		UI.roleTitle.Text = "ТЫ — " .. upper(c and c.name or "Палач")
		UI.roleTitle.TextColor3 = C.red
		UI.roleText.Text = "Не дай никому сбежать. ЛКМ — удар. Каждое убийство добавляет время.\n" .. abText .. "   [CTRL] SHIFT-LOCK"
	else
		UI.roleTitle.Text = "ТЫ — " .. upper(c and c.name or "выживший") .. "  ·  " .. roleName(c)
		UI.roleTitle.TextColor3 = c and roleColor(c) or C.bone
		UI.roleText.Text = "Продержись: выход откроется за минуту до конца — ищи значок двери.\n" .. abText .. "   [CTRL] SHIFT-LOCK"
	end
	U.edge(UI.roleEdges, c and roleColor(c) or C.edge)
	UI.titleRoot.Visible = true
	UI.titleBand.Position = UDim2.fromScale(-1, 0.4)
	UI.roleScale.Scale = 0.01
	tween(UI.titleBand, 0.55, { Position = UDim2.fromScale(0, 0.4) }, Enum.EasingStyle.Back)
	task.delay(0.45, function()
		if my == titleToken then tween(UI.roleScale, 0.35, { Scale = hudScale() }, Enum.EasingStyle.Back) end
	end)
	task.delay(5.2, function()
		if my ~= titleToken then return end
		U.gburst(UI.titleMap, 0.6)
		tween(UI.titleBand, 0.45, { Position = UDim2.fromScale(1.1, 0.4) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(UI.roleScale, 0.3, { Scale = 0.01 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.5, function()
			if my == titleToken then UI.titleRoot.Visible = false end
		end)
	end)
end

------------------------------------------------------------------------
-- ИТОГИ МАТЧА: экран «GAME OVER» в духе аркадных автоматов
------------------------------------------------------------------------
UI.resultsRoot = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(660, 460),
	BackgroundTransparency = 1, Visible = false, ZIndex = 70,
}, gui)
UI.resultsScale = make("UIScale", { Scale = 1 }, UI.resultsRoot)
local function showResults(res)
	for _, ch in ipairs(UI.resultsRoot:GetChildren()) do
		if not ch:IsA("UIScale") then ch:Destroy() end
	end
	local titles = {
		killer = { "GAME OVER", "Палач победил — никто не выбрался", C.red },
		survivors = { "YOU ESCAPED", "Все выжившие вырвались!", C.hp },
		mixed = { "CONTINUE?", string.format("Сбежало %d из %d", res.esc or 0, res.total or 0), C.gold },
		left = { "NO SIGNAL", "Палач покинул игру — победа выживших", C.esc },
	}
	local t = titles[res.o] or titles.mixed
	local _, back = U.panel(UI.resultsRoot, { Size = UDim2.fromScale(1, 1), ZIndex = 70 }, Color3.fromRGB(10, 9, 12), t[3], 5)
	local g = U.glitch(back, {
		Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 60), ZIndex = 72,
		Font = F.pix, TextSize = 52, TextColor3 = t[3], TextStrokeTransparency = 0, Text = t[1],
	}, 2.5)
	U.gburst(g, 1)
	make("TextLabel", {
		Position = UDim2.fromOffset(0, 80), Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, ZIndex = 72,
		Font = F.heavy, TextSize = 18, TextColor3 = C.bone, Text = t[2],
	}, back)
	local list = make("Frame", { Position = UDim2.fromOffset(34, 120), Size = UDim2.new(1, -68, 1, -138), BackgroundTransparency = 1, ZIndex = 72 }, back)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	local function row(order, c, name, icon, iconColor, extra, dead)
		local _, r = U.panel(list, { LayoutOrder = order, Size = UDim2.new(1, 0, 0, 40), ZIndex = 72 }, C.panel2, roleColor(c), 2)
		portraitFrame(r, { Position = UDim2.fromOffset(2, 1), Size = UDim2.fromOffset(34, 34), ZIndex = 73 }, c, dead, 2)
		make("TextLabel", { Position = UDim2.fromOffset(46, 0), Size = UDim2.new(0.55, -46, 1, 0), BackgroundTransparency = 1, ZIndex = 73,
			Font = F.bold, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.white, TextTruncate = Enum.TextTruncate.AtEnd,
			Text = name .. "  ·  " .. c.name }, r)
		make("TextLabel", { Position = UDim2.new(0.55, 0, 0, 0), Size = UDim2.new(0.3, 0, 1, 0), BackgroundTransparency = 1, ZIndex = 73,
			Font = F.pix, TextSize = 14, TextColor3 = C.dim, Text = extra or "" }, r)
		U.icon(r, ICON[icon], 4, { ["#"] = iconColor, o = C.ink, x = icon == "knife" and C.edge or C.ink, h = Color3.fromRGB(120, 60, 40) }, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), ZIndex = 74 })
	end
	if res.killer then
		local kc = charById[res.killer.c] or unknownChar(res.killer.c)
		row(0, kc, res.killer.n or "?", "knife", C.bone, "x" .. tostring(res.killer.k or 0), false)
	end
	for i, s in ipairs(res.survivors or {}) do
		local sc = charById[s.c] or unknownChar(s.c)
		local icon = (s.s == "escaped" and "door") or (s.s == "alive" and "heart") or "skull"
		local col = (s.s == "escaped" and C.esc) or (s.s == "alive" and C.hp) or C.hpLow
		row(i, sc, s.n or "?", icon, col, "P" .. tostring(s.p or "?"), s.s == "dead")
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
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -22), Size = UDim2.fromOffset(470, 48),
	BackgroundTransparency = 1, Visible = false, ZIndex = 30,
}, gui)
UI.specScale = make("UIScale", { Scale = 1 }, UI.specRoot)
UI.specBox, UI.specBody = U.panel(UI.specRoot, { Position = UDim2.fromOffset(52, 0), Size = UDim2.fromOffset(366, 48), ZIndex = 30 }, C.panel, C.edge, 3)
U.icon(UI.specBody, ICON.eye, 3, { ["#"] = C.red, o = C.bone }, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), ZIndex = 31 })
UI.specText = make("TextLabel", {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(46, 0), Size = UDim2.new(1, -54, 1, 0), ZIndex = 31, Font = F.heavy,
	TextSize = 16, TextColor3 = C.bone, TextTruncate = Enum.TextTruncate.AtEnd, Text = "",
}, UI.specBody)
local function specButton(text, x)
	local b = make("TextButton", {
		Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(46, 48), BackgroundTransparency = 1, AutoButtonColor = false,
		Text = "", ZIndex = 31,
	}, UI.specRoot)
	local _, body = U.panel(b, { Size = UDim2.fromScale(1, 1), ZIndex = 31 }, C.ink, C.red, 3)
	make("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 32, Font = F.pix, TextSize = 20,
		TextColor3 = C.red, Text = text }, body)
	return b
end
UI.specPrev = specButton("<", 0)
UI.specNext = specButton(">", 424)
UI.watchButton = make("TextButton", {
	Name = "WatchButton",
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -22), Size = UDim2.fromOffset(276, 44),
	BackgroundTransparency = 1, AutoButtonColor = false, Text = "", Visible = false, ZIndex = 30,
}, gui)
do
	local _, body = U.panel(UI.watchButton, { Size = UDim2.fromScale(1, 1), ZIndex = 30 }, C.ink, C.red, 3)
	U.icon(body, ICON.eye, 3, { ["#"] = C.red, o = C.bone }, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), ZIndex = 31 })
	UI.watchLabel = make("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(46, 0), Size = UDim2.new(1, -52, 1, 0),
		ZIndex = 31, Font = F.heavy, TextSize = 15, TextColor3 = C.bone, Text = "НАБЛЮДАТЬ ЗА МАТЧЕМ" }, body)
end
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
	UI.specText.Text = (t.n or "?") .. (c and ("  ·  " .. c.name) or "")
	UI.specText.TextColor3 = t.killer and C.red or (c and roleColor(c) or C.bone)
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
-- ВЫБОР ПЕРСОНАЖА: «аркадный» экран выбора бойца под сценой
------------------------------------------------------------------------
UI.selectRoot = make("Frame", { Name = "CharacterSelect", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 40 }, gui)
UI.selBackdrop = make("Frame", {
	AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0.46),
	BackgroundColor3 = C.black, BorderSizePixel = 0, ZIndex = 40,
}, UI.selectRoot)
make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.3), NumberSequenceKeypoint.new(1, 0.05) }) }, UI.selBackdrop)

local CELL_W, CELL_H, CELL_GAP, INFO_W, TOP = 150, 226, 14, 360, 66
UI.selPanel = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.fromOffset(1250, TOP + CELL_H + 12),
	BackgroundTransparency = 1, ZIndex = 41,
}, UI.selectRoot)
UI.selScale = make("UIScale", { Scale = 1 }, UI.selPanel)
UI.headerG = U.glitch(UI.selPanel, {
	Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(520, 30), ZIndex = 43,
	Font = F.heavy, TextSize = 24, TextColor3 = C.bone, TextXAlignment = Enum.TextXAlignment.Left, Text = "",
}, 1.5)
UI.selHint = make("Frame", { Position = UDim2.fromOffset(530, 3), Size = UDim2.fromOffset(300, 26), BackgroundTransparency = 1, ZIndex = 42 }, UI.selPanel)
U.key(UI.selHint, { Size = UDim2.fromOffset(26, 24), ZIndex = 42 }, "<")
U.key(UI.selHint, { Position = UDim2.fromOffset(30, 0), Size = UDim2.fromOffset(26, 24), ZIndex = 42 }, ">")
U.key(UI.selHint, { Position = UDim2.fromOffset(74, 0), Size = UDim2.fromOffset(70, 24), ZIndex = 42 }, "SPACE")
UI.tableFrame = make("Frame", { Position = UDim2.fromOffset(0, 36), Size = UDim2.fromOffset(940, TOP - 36 + CELL_H + 10), BackgroundTransparency = 1, ZIndex = 41 }, UI.selPanel)

-- инфо-панель выбранного героя
UI.infoBox, UI.infoPanel, UI.infoEdges = U.panel(UI.selPanel, {
	Position = UDim2.fromOffset(950, TOP), Size = UDim2.fromOffset(INFO_W, CELL_H), ZIndex = 42,
}, Color3.fromRGB(12, 11, 15), C.edge, 4)
UI.infoName = U.glitch(UI.infoPanel, {
	Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 30), ZIndex = 43,
	Font = F.heavy, TextSize = 26, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.white, Text = "",
}, 1)
UI.infoRoleIcon = make("Frame", { Position = UDim2.fromOffset(12, 40), Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, ZIndex = 43 }, UI.infoPanel)
UI.infoRole = make("TextLabel", {
	Position = UDim2.fromOffset(34, 38), Size = UDim2.new(1, -46, 0, 18), BackgroundTransparency = 1, ZIndex = 43,
	Font = F.bold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.dim, Text = "",
}, UI.infoPanel)
UI.infoDesc = make("TextLabel", {
	Position = UDim2.fromOffset(12, 58), Size = UDim2.new(1, -24, 0, 30), BackgroundTransparency = 1, ZIndex = 43,
	Font = F.med, TextSize = 12, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	TextColor3 = Color3.fromRGB(210, 206, 200), Text = "",
}, UI.infoPanel)
-- характеристики без слов: сердце/молния/кристалл и число (у Палачей — пипсы силы, скорости, выносливости)
UI.statChips = {}
for i = 1, 3 do
	local chip = {}
	chip.root = make("Frame", { Position = UDim2.fromOffset(12 + (i - 1) * 110, 92), Size = UDim2.fromOffset(104, 16), BackgroundTransparency = 1, ZIndex = 43 }, UI.infoPanel)
	chip.icon = make("Frame", { Size = UDim2.fromOffset(18, 16), BackgroundTransparency = 1, ZIndex = 43 }, chip.root)
	chip.text = make("TextLabel", { Position = UDim2.fromOffset(22, 0), Size = UDim2.fromOffset(60, 16), BackgroundTransparency = 1, ZIndex = 43,
		Font = F.pix, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.bone, TextStrokeTransparency = 0.3, Text = "" }, chip.root)
	chip.pips = {}
	for k = 1, 5 do
		chip.pips[k] = make("Frame", { Position = UDim2.fromOffset(22 + (k - 1) * 14, 3), Size = UDim2.fromOffset(11, 10),
			BackgroundColor3 = Color3.fromRGB(40, 36, 44), BorderSizePixel = 0, ZIndex = 43 }, chip.root)
	end
	UI.statChips[i] = chip
end
-- навыки героя: иконка, клавиша и название, описание
UI.skillRows = {}
for i = 1, 2 do
	local row = {}
	row.root = make("Frame", { Position = UDim2.fromOffset(12, 112 + (i - 1) * 40), Size = UDim2.new(1, -24, 0, 38), BackgroundTransparency = 1, ZIndex = 43 }, UI.infoPanel)
	row.box, row.body, row.edges = U.panel(row.root, { Size = UDim2.fromOffset(34, 34), ZIndex = 43 }, C.panel2, C.edge, 2)
	row.title = make("TextLabel", { Position = UDim2.fromOffset(42, 0), Size = UDim2.new(1, -42, 0, 14), BackgroundTransparency = 1, ZIndex = 43,
		Font = F.bold, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.gold, Text = "" }, row.root)
	row.text = make("TextLabel", { Position = UDim2.fromOffset(42, 14), Size = UDim2.new(1, -42, 0, 24), BackgroundTransparency = 1, ZIndex = 43,
		Font = F.med, TextSize = 10, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Color3.fromRGB(200, 196, 190), Text = "" }, row.root)
	UI.skillRows[i] = row
end
UI.confirmBtn = make("TextButton", {
	Position = UDim2.fromOffset(12, 192), Size = UDim2.new(1, -24, 0, 24), BackgroundTransparency = 1, AutoButtonColor = false,
	Text = "", ZIndex = 44,
}, UI.infoPanel)
UI.confirmBox, UI.confirmBody, UI.confirmEdges = U.panel(UI.confirmBtn, { Size = UDim2.fromScale(1, 1), ZIndex = 44 }, C.blood, C.ink, 3)
UI.confirmText = make("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 45, Font = F.heavy,
	TextSize = 15, TextColor3 = C.white, Text = "ВЫБРАТЬ" }, UI.confirmBody)

local selCells = {}      -- [id] = {root, scale, lift, edges, overlay, badge, badgeText, cursor}
local selList = {}       -- персонажи ТОЛЬКО моей таблицы
local cursor = 1
local myPick, myList = nil, nil
local takenSet, takenBy = {}, {}
local ROLE_PLURAL = { stun = "СТАННЕРЫ", support = "ПОДДЕРЖКА", lone = "ВЫЖИВАЛЬЩИКИ", killer = "ОБЛИКИ ПАЛАЧА" }
local onPhase

local function fitSelection()
	local n = math.max(#selList, 1)
	local tableW = n * CELL_W + (n - 1) * CELL_GAP
	UI.tableFrame.Size = UDim2.fromOffset(tableW, TOP - 36 + CELL_H + 10)
	UI.infoBox.Position = UDim2.fromOffset(tableW + 20, TOP)
	local w = tableW + 20 + INFO_W
	local h = TOP + CELL_H + 12
	UI.selPanel.Size = UDim2.fromOffset(w, h)
	local s = gui.AbsoluteSize
	UI.selScale.Scale = math.clamp(math.min(s.X * 0.96 / w, s.Y * 0.42 / h), 0.4, 1.1)
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

local function setConfirm(text, bg, edge)
	UI.confirmText.Text = text
	UI.confirmBody.BackgroundColor3 = bg
	U.edge(UI.confirmEdges, edge or C.ink)
end

local function refreshInfo()
	local c = selList[cursor]
	if not c then return end
	local col = charColor(c)
	local rc = roleColor(c)
	U.gtext(UI.infoName, upper(c.name))
	UI.infoName.main.TextColor3 = col:Lerp(C.white, 0.3)
	for _, ch in ipairs(UI.infoRoleIcon:GetChildren()) do ch:Destroy() end
	roleIcon(UI.infoRoleIcon, c, 2, { ZIndex = 43 })
	UI.infoRole.Text = roleName(c) .. "  ·  " .. (c.role or "")
	UI.infoRole.TextColor3 = rc
	UI.infoDesc.Text = c.desc or ""
	U.edge(UI.infoEdges, rc)
	local stats = c.killer and {
		{ "fist", C.red, c.power or 0, true }, { "dash", C.gold, c.speed or 0, true }, { "bolt", C.st, c.stamina or 0, true },
	} or { { "heart", C.hpLow, c.hp or 100 }, { "bolt", C.st, c.stamina or 100 }, c.mana and { "mana", C.mana, c.mana } or nil }
	for i, chip in ipairs(UI.statChips) do
		local st = stats[i]
		chip.root.Visible = st ~= nil
		if st then
			for _, ch in ipairs(chip.icon:GetChildren()) do ch:Destroy() end
			U.icon(chip.icon, ICON[st[1]], 2, { ["#"] = st[2], o = C.white }, { ZIndex = 43 })
			chip.text.Visible = not st[4]
			chip.text.Text = tostring(st[3])
			chip.text.TextColor3 = st[2]
			for k, pip in ipairs(chip.pips) do
				pip.Visible = st[4] == true
				pip.BackgroundColor3 = k <= st[3] and st[2] or Color3.fromRGB(40, 36, 44)
			end
		end
	end
	for i, row in ipairs(UI.skillRows) do
		local sk = c.skills and c.skills[i]
		row.root.Visible = sk ~= nil
		if sk then
			for _, ch in ipairs(row.body:GetChildren()) do
				if ch.Name == "SkIcon" then ch:Destroy() end
			end
			local ic = skillIcon(row.body, sk, c, 24, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 44 })
			ic.Name = "SkIcon"
			row.title.Text = "[" .. (sk.key or (i == 1 and "Q" or "E")) .. "] " .. sk.name
			row.title.TextColor3 = rc
			row.text.Text = sk.text or ""
			U.edge(row.edges, rc)
		end
	end
	local locked = gameState:GetAttribute("SelectLocked") == true
	if myPick == c.id then
		setConfirm("ВЫБРАН", Color3.fromRGB(40, 120, 60), C.gold)
	elseif takenSet[c.id] then
		setConfirm("ЗАНЯТО", Color3.fromRGB(46, 42, 50))
	elseif locked then
		setConfirm("ИГРА НАЧИНАЕТСЯ…", Color3.fromRGB(46, 42, 50))
	else
		setConfirm("ВЫБРАТЬ", C.blood)
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
			cd.badge.Visible = takenSet[c.id] or false
			if takenSet[c.id] then
				local tb = takenBy[c.id]
				cd.badgeText.Text = mine and ("ТЫ" .. (tb and tb.port and (" · P" .. tb.port) or "")) or
					((tb and tb.port and ("P" .. tb.port .. " · ") or "") .. (tb and tb.n or ""))
				cd.badgeBody.BackgroundColor3 = mine and C.gold or C.ink
				cd.badgeText.TextColor3 = mine and C.ink or C.bone
			end
			tween(cd.lift, 0.18, { Position = UDim2.fromOffset(0, cur and -12 or 0) }, Enum.EasingStyle.Back)
			tween(cd.scale, 0.18, { Scale = cur and 1.04 or 1 }, Enum.EasingStyle.Back)
			U.edge(cd.edges, mine and C.gold or (cur and C.white or roleColor(c)))
			cd.cursor.Visible = cur
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
	U.gburst(UI.headerG, 0.3)
	pickEvent:FireServer(c.id)
end
UI.confirmBtn.Activated:Connect(confirmPick)

local function buildSelection()
	for _, cd in pairs(selCells) do cd.root:Destroy() end
	for _, ch in ipairs(UI.tableFrame:GetChildren()) do ch:Destroy() end
	selCells, selList = {}, {}
	if myList then
		for _, c in ipairs(characters) do
			if c.killer == (myList == "Killer") then table.insert(selList, c) end
		end
	end
	cursor = math.clamp(cursor, 1, math.max(#selList, 1))
	fitSelection()
	U.gtext(UI.headerG, myList == "Killer" and "ПАЛАЧ: ВЫБЕРИ ОБЛИК" or "ВЫБЕРИ ВЫЖИВШЕГО")
	UI.headerG.main.TextColor3 = myList == "Killer" and C.red or C.bone
	-- заголовки групп над соседними ячейками одной роли (Станнеры / Поддержка / Выживальщики)
	local runStart = 1
	for i = 1, #selList + 1 do
		local c = selList[i]
		local prev = selList[runStart]
		if not c or groupOf(c) ~= groupOf(prev) then
			if prev then
				local x0 = (runStart - 1) * (CELL_W + CELL_GAP)
				local w = (i - runStart) * (CELL_W + CELL_GAP) - CELL_GAP
				local _, gb = U.panel(UI.tableFrame, { Position = UDim2.fromOffset(x0, 0), Size = UDim2.fromOffset(w, 22), ZIndex = 42 }, C.ink, roleColor(prev), 2)
				roleIcon(gb, prev, 2, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 6, 0.5, 0), ZIndex = 43 })
				make("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(26, 0), Size = UDim2.new(1, -30, 1, 0), ZIndex = 43,
					Font = F.heavy, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = roleColor(prev), Text = ROLE_PLURAL[groupOf(prev)] or roleName(prev) }, gb)
			end
			runStart = i
		end
	end
	for order, c in ipairs(selList) do
		local acc = charColor(c)
		local root = make("TextButton", {
			Position = UDim2.fromOffset((order - 1) * (CELL_W + CELL_GAP), TOP - 36), Size = UDim2.fromOffset(CELL_W, CELL_H),
			BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 1,
		}, UI.tableFrame)
		local lift = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, root)
		local sc = make("UIScale", { Scale = 1 }, lift)
		local _, body, edges = U.panel(lift, { Size = UDim2.fromScale(1, 1), ZIndex = 44 }, c.killer and Color3.fromRGB(26, 12, 14) or C.panel, roleColor(c), 4)
		-- арт героя на фоне его цвета
		local art = make("Frame", {
			Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 0, 160), BackgroundColor3 = acc:Lerp(C.black, 0.45),
			BorderSizePixel = 0, ZIndex = 45, ClipsDescendants = true,
		}, body)
		make("UIGradient", { Rotation = 90, Color = ColorSequence.new(C.white, Color3.fromRGB(40, 30, 40)) }, art)
		for k = 0, 6 do -- пиксельные полосы фона, как на заставках
			make("Frame", { Position = UDim2.fromOffset(0, 10 + k * 18), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = C.black,
				BackgroundTransparency = 0.75, BorderSizePixel = 0, ZIndex = 45 }, art)
		end
		local face = make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.fromOffset(136, 136),
			BackgroundTransparency = 1, ZIndex = 46 }, art)
		portrait(face, c, 46)
		roleIcon(body, c, 3, { Position = UDim2.fromOffset(8, 8), ZIndex = 49 })
		-- табличка с именем
		local plate = make("Frame", {
			Position = UDim2.fromOffset(4, 168), Size = UDim2.new(1, -8, 0, 46), BackgroundColor3 = C.ink, BorderSizePixel = 0, ZIndex = 48,
		}, body)
		make("Frame", { Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = roleColor(c), BorderSizePixel = 0, ZIndex = 49 }, plate)
		make("TextLabel", {
			Position = UDim2.fromOffset(6, 5), Size = UDim2.new(1, -12, 0, 20), BackgroundTransparency = 1, ZIndex = 49,
			Font = F.heavy, TextSize = 17, TextColor3 = c.killer and C.red or C.white, Text = upper(c.name),
		}, plate)
		make("TextLabel", {
			Position = UDim2.fromOffset(6, 25), Size = UDim2.new(1, -12, 0, 16), BackgroundTransparency = 1, ZIndex = 49,
			Font = F.med, TextSize = 10, TextColor3 = C.dim, Text = c.role or "",
		}, plate)
		-- занято / мой выбор
		local overlay = make("Frame", {
			Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.black, BackgroundTransparency = 0.45,
			BorderSizePixel = 0, ZIndex = 50, Visible = false,
		}, body)
		local badge, badgeBody = U.panel(body, {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 142), Size = UDim2.new(1, 8, 0, 24), Rotation = -6,
			ZIndex = 52, Visible = false,
		}, C.gold, C.ink, 2)
		local badgeText = make("TextLabel", {
			BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 53, Font = F.heavy, TextSize = 12,
			TextColor3 = C.ink, TextTruncate = Enum.TextTruncate.AtEnd, Text = "",
		}, badgeBody)
		-- курсор игрока: мигающая пиксельная стрелка под ячейкой
		local cur = U.icon(root, ICON.arrow, 3, { ["#"] = C.red }, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 2), ZIndex = 43, Visible = false })
		root.Activated:Connect(function()
			if cursor ~= order then
				cursor = order
				sfx("tick", 0.35)
				refreshSelection()
			else
				confirmPick()
			end
		end)
		selCells[c.id] = { root = root, scale = sc, lift = lift, edges = edges, overlay = overlay, badge = badge,
			badgeBody = badgeBody, badgeText = badgeText, cursor = cur }
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
local monitorKillerKey = nil
local dof = make("DepthOfFieldEffect", { Enabled = false, FarIntensity = 0, NearIntensity = 0, FocusDistance = 40, InFocusRadius = 30 }, Lighting)

local function findStage()
	if stageModel and stageModel.Parent then return stageModel end
	stageModel = Workspace:FindFirstChild("SelectionStage")
	monitorModel = stageModel and stageModel:FindFirstChild("KillerMonitor") or nil
	return stageModel
end

-- экран ЭЛТ-телевизора: «прямой эфир» с Палачом
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
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 120, 120), Color3.fromRGB(60, 10, 14)) }, bg)
	UI.monitorVP = make("ViewportFrame", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Ambient = Color3.fromRGB(140, 60, 60),
		LightColor = Color3.fromRGB(255, 120, 110), LightDirection = Vector3.new(-0.4, -0.5, 1), ZIndex = 2,
	}, bg)
	UI.monitorWorld = make("WorldModel", {}, UI.monitorVP)
	UI.monitorCam = make("Camera", { FieldOfView = 34 }, UI.monitorVP)
	UI.monitorVP.CurrentCamera = UI.monitorCam
	for y = 0, 270, 6 do
		make("Frame", { Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = C.black,
			BackgroundTransparency = 0.7, BorderSizePixel = 0, ZIndex = 3 }, bg)
	end
	UI.monitorRec = make("TextLabel", {
		Position = UDim2.fromOffset(14, 10), Size = UDim2.fromOffset(120, 24), BackgroundTransparency = 1, ZIndex = 4,
		Font = F.pix, TextSize = 18, TextColor3 = Color3.fromRGB(255, 40, 40), TextXAlignment = Enum.TextXAlignment.Left, Text = "● REC",
	}, bg)
	make("TextLabel", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 10), Size = UDim2.fromOffset(160, 24), BackgroundTransparency = 1,
		ZIndex = 4, Font = F.pix, TextSize = 14, TextColor3 = Color3.fromRGB(255, 200, 200), TextXAlignment = Enum.TextXAlignment.Right, Text = "CH 13",
	}, bg)
	local strip = make("Frame", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 52),
		BackgroundColor3 = C.black, BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 4,
	}, bg)
	UI.monitorName = make("TextLabel", {
		Position = UDim2.fromOffset(14, 2), Size = UDim2.new(1, -28, 1, -4), BackgroundTransparency = 1, ZIndex = 5,
		Font = F.heavy, TextScaled = true, TextColor3 = C.white, Text = "",
	}, strip)
	UI.monitorNoise = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.white, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 6 }, bg)
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
	task.delay(0.45, function() -- ждём, пока долетит костюм Палача
		if monitorKillerKey ~= key or not buildMonitorGui() then return end
		if UI.monitorClone then UI.monitorClone:Destroy() UI.monitorClone = nil end
		local c = charById[k.c] or unknownChar(k.c)
		UI.monitorName.Text = upper(c.name) .. "  ·  " .. (k.n or "")
		UI.monitorName.TextColor3 = charColor(c):Lerp(C.white, 0.3)
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
-- ЭКРАН АВТОКИНОТЕАТРА В ЛОББИ
------------------------------------------------------------------------
local TIPS = {
	"Shift — бег. Выдохся — подожди, пока молния восстановится.",
	"Q и E — два навыка героя. Ctrl — включить или выключить shift-lock.",
	"Прыгать нельзя: петляй вокруг укрытий и по рампам.",
	"Алекс и Айша умеют оглушать Палача. Контр-удар и щит отражают удар.",
	"Лилиан встала в позу лечения? Подойди к ней и нажми F.",
	"Станции Грега лечат и ускоряют, а растяжка тормозит Палача.",
	"Оскар видит всех сквозь стены, а Феликс копит ману для телекинеза.",
	"Выход откроется за минуту до конца. Ищи значок двери.",
	"Удар Палача на миг ускоряет тебя — используй, чтобы оторваться.",
	"Каждое убийство добавляет Палачу 20 секунд.",
	"Погиб или сбежал? Нажми «Наблюдать за матчем».",
}
local function buildLobbyGui()
	if UI.lobbyGui and UI.lobbyGui.Parent and UI.lobbyGui.Adornee and UI.lobbyGui.Adornee.Parent then return end
	local lobby = Workspace:FindFirstChild("Lobby")
	local screen = lobby and lobby:FindFirstChild("LobbyScreen")
	if not screen then return end
	if UI.lobbyGui then UI.lobbyGui:Destroy() end
	local face = Enum.NormalId[screen:GetAttribute("Face") or "Front"] or Enum.NormalId.Front
	UI.lobbyGui = make("SurfaceGui", {
		Name = "LobbyScreenGui", Adornee = screen, Face = face, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 20, LightInfluence = 0, ResetOnSpawn = false,
	}, player.PlayerGui)
	local bg = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(8, 8, 10), BorderSizePixel = 0 }, UI.lobbyGui)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(70, 74, 90), Color3.fromRGB(10, 10, 12)) }, bg)
	for y = 0, 700, 5 do
		make("Frame", { Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = C.black,
			BackgroundTransparency = 0.72, BorderSizePixel = 0, ZIndex = 5 }, bg)
	end
	-- царапины киноплёнки
	UI.lobbyScratches = {}
	for i = 1, 5 do
		table.insert(UI.lobbyScratches, make("Frame", { Size = UDim2.new(0, 2, 1, 0), Position = UDim2.fromScale(i / 6, 0),
			BackgroundColor3 = C.bone, BackgroundTransparency = 0.85, BorderSizePixel = 0, ZIndex = 4 }, bg))
	end
	UI.lobbyTitle = U.glitch(bg, { Position = UDim2.fromScale(0.05, 0.04), Size = UDim2.fromScale(0.9, 0.22), ZIndex = 2,
		Font = F.pix, TextScaled = true, TextColor3 = Color3.fromRGB(230, 30, 30), Text = "PRESS 2 DIE" }, 5)
	make("TextLabel", { Position = UDim2.fromScale(0.2, 0.26), Size = UDim2.fromScale(0.6, 0.06), BackgroundTransparency = 1,
		Font = F.heavy, TextScaled = true, TextColor3 = C.bone, Text = "НОЧНОЙ СЕАНС", ZIndex = 2 }, bg)
	UI.lobbyBlink = make("TextLabel", { Position = UDim2.fromScale(0.25, 0.34), Size = UDim2.fromScale(0.5, 0.05), BackgroundTransparency = 1,
		Font = F.pix, TextScaled = true, TextColor3 = C.gold, Text = "INSERT COIN", ZIndex = 2 }, bg)
	UI.lobbyStatus = make("TextLabel", { Position = UDim2.fromScale(0.05, 0.42), Size = UDim2.fromScale(0.9, 0.08), BackgroundTransparency = 1,
		Font = F.heavy, TextScaled = true, TextColor3 = C.white, Text = "", ZIndex = 2 }, bg)
	UI.lobbyBig = U.glitch(bg, { Position = UDim2.fromScale(0.05, 0.51), Size = UDim2.fromScale(0.9, 0.2), ZIndex = 2,
		Font = F.pix, TextScaled = true, TextColor3 = C.gold, Text = "" }, 4)
	UI.lobbyPips = make("Frame", { Position = UDim2.fromScale(0.1, 0.74), Size = UDim2.fromScale(0.8, 0.1), BackgroundTransparency = 1, ZIndex = 2 }, bg)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 14) }, UI.lobbyPips)
	UI.lobbyPipCount = -1
	UI.lobbyTip = make("TextLabel", { Position = UDim2.fromScale(0.04, 0.89), Size = UDim2.fromScale(0.92, 0.06), BackgroundTransparency = 1,
		Font = F.bold, TextScaled = true, TextColor3 = Color3.fromRGB(190, 196, 210), Text = TIPS[1], ZIndex = 2 }, bg)
end

local function refreshLobbyScreen()
	buildLobbyGui()
	if not UI.lobbyGui then return end
	local phase = gameState:GetAttribute("Phase")
	local t = gameState:GetAttribute("TimeLeft") or 0
	local need = gameState:GetAttribute("MinPlayers") or 2
	local n = #Players:GetPlayers()
	if phase == "Waiting" then
		UI.lobbyStatus.Text = "ЖДЁМ ЗРИТЕЛЕЙ"
		U.gtext(UI.lobbyBig, string.format("%d / %d", n, need))
	elseif phase == "Countdown" then
		UI.lobbyStatus.Text = "СЕАНС НАЧНЁТСЯ ЧЕРЕЗ"
		U.gtext(UI.lobbyBig, tostring(t))
	elseif phase == "Match" or phase == "Ending" then
		local info = mapByKey[gameState:GetAttribute("MapKey") or ""]
		local alive = 0
		for _, s in ipairs(decode("Roster", {})) do
			if s.s == "alive" then alive += 1 end
		end
		UI.lobbyStatus.Text = "НА ЭКРАНЕ: " .. (info and info.name or "") .. " · ЖИВЫХ " .. alive
		U.gtext(UI.lobbyBig, fmt(t))
	else
		UI.lobbyStatus.Text = "СМЕНА ПЛЁНКИ…"
		U.gtext(UI.lobbyBig, "...")
	end
	if n ~= UI.lobbyPipCount then
		UI.lobbyPipCount = n
		for _, ch in ipairs(UI.lobbyPips:GetChildren()) do
			if ch:IsA("Frame") then ch:Destroy() end
		end
		for i = 1, math.min(n, 12) do
			U.icon(UI.lobbyPips, ICON.person, 9, { ["#"] = i <= need and C.bone or C.dim }, { LayoutOrder = i, ZIndex = 2 })
		end
	end
end

------------------------------------------------------------------------
-- ОСВЕЩЕНИЕ ПО ЗОНАМ (клиентские пресеты). Туман Atmosphere прячет края карт.
------------------------------------------------------------------------
local cc = make("ColorCorrectionEffect", { Name = "P2D_Color" }, Lighting)
local bloom = make("BloomEffect", { Name = "P2D_Bloom", Intensity = 0.6, Size = 24, Threshold = 1.6 }, Lighting)
local PRESETS = {
	Lobby = { light = { ClockTime = 0, Brightness = 1.2, Ambient = Color3.fromRGB(40, 46, 58), OutdoorAmbient = Color3.fromRGB(34, 40, 60),
		FogColor = Color3.fromRGB(10, 14, 22), FogStart = 30, FogEnd = 260 },
		atm = { Density = 0.45, Offset = 0.25, Color = Color3.fromRGB(40, 50, 70), Decay = Color3.fromRGB(14, 16, 26), Haze = 2 },
		cc = { Contrast = 0.12, Saturation = -0.1, TintColor = Color3.fromRGB(220, 230, 255) }, bloom = 0.7 },
	Stage = { light = { ClockTime = 0, Brightness = 0.6, Ambient = Color3.fromRGB(26, 22, 30), OutdoorAmbient = Color3.fromRGB(12, 10, 16),
		FogColor = Color3.fromRGB(0, 0, 0), FogStart = 80, FogEnd = 500 },
		atm = { Density = 0, Offset = 0, Color = Color3.fromRGB(0, 0, 0), Decay = Color3.fromRGB(0, 0, 0), Haze = 0 },
		cc = { Contrast = 0.15, Saturation = 0, TintColor = Color3.fromRGB(255, 245, 240) }, bloom = 1 },
	Forest = { light = { ClockTime = 1, Brightness = 0.9, Ambient = Color3.fromRGB(36, 44, 50), OutdoorAmbient = Color3.fromRGB(40, 50, 62),
		FogColor = Color3.fromRGB(40, 48, 56), FogStart = 10, FogEnd = 190 },
		atm = { Density = 0.55, Offset = 0.3, Color = Color3.fromRGB(70, 80, 90), Decay = Color3.fromRGB(30, 36, 44), Haze = 3 },
		cc = { Contrast = 0.1, Saturation = -0.25, TintColor = Color3.fromRGB(210, 225, 235) }, bloom = 0.6 },
	Complex = { light = { ClockTime = 0, Brightness = 0.4, Ambient = Color3.fromRGB(46, 40, 40), OutdoorAmbient = Color3.fromRGB(20, 20, 24),
		FogColor = Color3.fromRGB(14, 10, 10), FogStart = 20, FogEnd = 220 },
		atm = { Density = 0.3, Offset = 0, Color = Color3.fromRGB(60, 30, 30), Decay = Color3.fromRGB(20, 10, 10), Haze = 1 },
		cc = { Contrast = 0.18, Saturation = 0, TintColor = Color3.fromRGB(255, 225, 215) }, bloom = 1 },
	Farm = { light = { ClockTime = 18.1, Brightness = 1.4, Ambient = Color3.fromRGB(90, 56, 48), OutdoorAmbient = Color3.fromRGB(140, 80, 64),
		FogColor = Color3.fromRGB(150, 70, 50), FogStart = 30, FogEnd = 260 },
		atm = { Density = 0.42, Offset = 0.25, Color = Color3.fromRGB(200, 110, 70), Decay = Color3.fromRGB(110, 40, 40), Haze = 2.5 },
		cc = { Contrast = 0.1, Saturation = 0.05, TintColor = Color3.fromRGB(255, 225, 200) }, bloom = 0.5 },
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
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
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
-- АНИМАЦИИ ОКРУЖЕНИЯ ПО ТЕГАМ (лампы, вывески, мельница, звёзды над оглушённым)
------------------------------------------------------------------------
local tagged = { P2D_Spin = {}, P2D_Flicker = {}, P2D_Blink = {}, P2D_Pulse = {}, P2D_SpinModel = {}, P2D_Dizzy = {} }
for tagName, set in pairs(tagged) do
	local function add(inst)
		if inst:IsA("Model") then
			set[inst] = { base = inst:GetPivot(), seed = math.random() * 10 }
		elseif inst:IsA("BasePart") then
			set[inst] = { base = inst.CFrame, color = inst.Color, tr = inst.Transparency, seed = math.random() * 10 }
		elseif inst:IsA("BillboardGui") then
			set[inst] = { seed = math.random() * 10 }
		end
	end
	for _, inst in ipairs(CollectionService:GetTagged(tagName)) do add(inst) end
	CollectionService:GetInstanceAddedSignal(tagName):Connect(add)
	CollectionService:GetInstanceRemovedSignal(tagName):Connect(function(inst) set[inst] = nil end)
end
local flickerClock = 0

------------------------------------------------------------------------
-- МЕТКА ВЫХОДА: только пиксельная дверь (над воротами или у края экрана), без названия и расстояния
------------------------------------------------------------------------
UI.exitMarker = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(40, 40), BackgroundTransparency = 1, Visible = false, ZIndex = 12,
}, gui)
UI.exitDoor, UI.exitDoorParts = U.icon(UI.exitMarker, ICON.door, 5, { ["#"] = C.hp, o = C.ink },
	{ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 12 })

-- звёзды перед глазами оглушённого Палача
UI.dizzyRoot = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(240, 100),
	BackgroundTransparency = 1, Visible = false, ZIndex = 80,
}, gui)
UI.dizzyStars = {}
for _ = 1, 5 do
	table.insert(UI.dizzyStars, (U.icon(UI.dizzyRoot, ICON.star, 4, { ["#"] = C.gold }, { AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 80 })))
end
UI.heartScale = make("UIScale", { Scale = 1 }, UI.heartIcon)

local function myChar()
	local id = player.Character and player.Character:GetAttribute("CharId")
	return id and charById[id] or nil
end

------------------------------------------------------------------------
-- ВИДИМОСТЬ И ТЕКСТЫ
------------------------------------------------------------------------
local function refreshTop()
	local phase = gameState:GetAttribute("Phase")
	local showTime = phase == "Match" or phase == "Countdown" or phase == "Selection"
	if not showTime then U.gtext(UI.timeG, "--:--") end
	local text, col = "", C.bone
	if phase == "Waiting" then
		text = string.format("ОЖИДАНИЕ ИГРОКОВ  %d / %d", #Players:GetPlayers(), gameState:GetAttribute("MinPlayers") or 2)
	elseif phase == "Countdown" then
		text = "СКОРО НАЧНЁТСЯ СЕАНС"
	elseif phase == "Selection" and gameState:GetAttribute("SelectLocked") and myList then
		U.gtext(UI.headerG, "ВСЕ НА СЦЕНЕ!")
		U.gburst(UI.headerG, 0.6)
	elseif phase == "Ending" then
		text = "МАТЧ ОКОНЧЕН"
	end
	UI.objText.Text = text
	UI.objText.TextColor3 = col
	U.edge(UI.objEdges, col == C.hp and C.hp or C.edge)
	UI.objBox.Visible = text ~= ""
	UI.statusRow.Visible = phase == "Match" or phase == "Ending"
	UI.objBox.Position = UDim2.fromOffset(120, UI.statusRow.Visible and 202 or 172)
	local open = gameState:GetAttribute("EscapeOpen") == true
	U.tint(UI.doorParts, "#", open and C.hp or C.edge)
	U.tint(UI.doorParts, "o", open and C.ink or C.blood)
end

local placing, setPlacing = false, nil -- режим выбора станции Грега (см. «НАВЫКИ»)
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
	UI.hintRoot.Visible = bars
	UI.hintHit.Visible = role == "Killer"
	UI.manaRow.Visible = bars and player:GetAttribute("MaxMana") ~= nil
	if UI.touchSprint then UI.touchSprint.Visible = bars end
	if UI.touchSkills then
		local c = myChar()
		for i, t in ipairs(UI.touchSkills) do t.button.Visible = bars and c ~= nil and c.skills ~= nil and c.skills[i] ~= nil end
	end
	if not bars and placing and setPlacing then setPlacing(false) end
	if bars ~= lastBars then
		lastBars = bars
		if bars then sprintHeld = false end
	end

	local canWatch = phase == "Match" and not alive and #aliveTargets() > 0
	UI.watchButton.Visible = canWatch and not spectating
	UI.specRoot.Visible = spectating
	if spectating and not canWatch then stopSpectate() UI.specRoot.Visible = false end
	if selecting then
		UI.clockRoot.AnchorPoint = Vector2.new(1, 0)
		UI.clockRoot.Position = UDim2.new(1, -6, 0, 8)
	else
		UI.clockRoot.AnchorPoint = Vector2.new(0.5, 0)
		UI.clockRoot.Position = UDim2.new(0.5, 0, 0, 8)
	end
end

------------------------------------------------------------------------
-- ЗДОРОВЬЕ / ВЫНОСЛИВОСТЬ / ОФОРМЛЕНИЕ СВОЕГО HUD
------------------------------------------------------------------------
local curHealth, curMax = 100, 100
local function setHealth(h, maxH)
	curHealth, curMax = h, math.max(1, maxH)
	UI.hpCounter.Text = "x" .. tostring(math.max(0, math.ceil(h)))
end

local function refreshSelfStyle()
	local role = player:GetAttribute("Role")
	local c = myChar()
	local killer = role == "Killer"
	UI.portText.Visible = not killer
	UI.portSkull.Visible = killer
	UI.portText.Text = "P" .. tostring(player:GetAttribute("Port") or "?")
	U.edge(UI.portEdges, killer and C.red or (c and roleColor(c) or C.edge))
	UI.portText.TextColor3 = c and roleColor(c) or C.bone
	UI.selfName.Text = c and upper(c.name) or ""
	UI.selfName.TextColor3 = killer and C.red or (c and roleColor(c) or C.bone)
	if killer then UI.selfName.Text ..= "  x" .. tostring(player:GetAttribute("Kills") or 0) end
	for _, ch in ipairs(UI.selfRoleHolder:GetChildren()) do ch:Destroy() end
	if c then roleIcon(UI.selfRoleHolder, c, 2, { ZIndex = 6 }) end
	setSlotIcons(c)
	setHintSkills(c)
	if UI.touchSkills and c then
		for i, t in ipairs(UI.touchSkills) do
			local sk = c.skills and c.skills[i]
			local id = sk and (c.id .. ":" .. sk.id)
			if id ~= t.iconFor then
				t.iconFor = id
				for _, ch in ipairs(t.button:GetChildren()) do
					if ch.Name == "SkIcon" then ch:Destroy() end
				end
				if sk then
					local ic = skillIcon(t.button, sk, c, 38, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 32 })
					ic.Name = "SkIcon"
				end
			end
		end
	end
end

local boosted, exhausted = false, false
local function refreshStamina()
	local v = player:GetAttribute("Stamina") or 0
	local m = player:GetAttribute("MaxStamina") or 100
	tween(UI.stBar.fill, 0.1, { Size = UDim2.fromScale(math.clamp(v / math.max(m, 1), 0, 1), 1) })
	UI.stText.Text = "x" .. tostring(v)
	exhausted = player:GetAttribute("Exhausted") == true
	boosted = player:GetAttribute("Boosted") == true
	local col = (boosted and C.stBoost) or (exhausted and C.stEx) or C.st
	UI.stBar.fill.BackgroundColor3 = col
	UI.stText.TextColor3 = col
	U.tint(UI.boltParts, "#", col)
end

local function refreshMana()
	local v = player:GetAttribute("Mana") or 0
	local m = player:GetAttribute("MaxMana")
	if not m then return end
	UI.manaBar.fill.Size = UDim2.fromScale(math.clamp(v / math.max(m, 1), 0, 1), 1)
	UI.manaText.Text = "x" .. tostring(v)
end

local function bindCharacter(char)
	local hum = char:WaitForChild("Humanoid")
	local last = hum.Health
	setHealth(hum.Health, hum.MaxHealth)
	UI.hpBar.ghostF = 1
	hum.HealthChanged:Connect(function(h)
		if h < last then
			flash(Color3.fromRGB(190, 0, 0), 0.45)
			bustHit = 1
			sfx("slash", 0.4, 0.8)
		elseif h > last + 5 then
			flash(Color3.fromRGB(60, 255, 120), 0.18, 0.6)
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
-- ЭФФЕКТЫ С СЕРВЕРА: удары, помехи, подсветки, оглушение, ослепление, замедление, лечение
------------------------------------------------------------------------
local revealHighlights = {}
local vanishUntilLocal, stunUntilLocal = 0, 0
-- временная подсветка персонажей сквозь стены (видна только этому игроку)
local function xray(list, dur)
	for _, h in ipairs(revealHighlights) do h:Destroy() end
	revealHighlights = {}
	for _, it in ipairs(list) do
		local p = Players:GetPlayerByUserId(it.id)
		if p and p ~= player and p.Character then
			table.insert(revealHighlights, make("Highlight", {
				FillColor = it.color, FillTransparency = 0.55, OutlineColor = C.white,
				DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
			}, p.Character))
		end
	end
	local mine = revealHighlights
	task.delay(dur, function()
		for _, h in ipairs(mine) do h:Destroy() end
	end)
end

-- отталкивание силовым щитом: персонаж Палача принадлежит его клиенту, поэтому толчок применяется здесь
local function knockback(vel)
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp or typeof(vel) ~= "Vector3" then return end
	local att = make("Attachment", { Name = "P2D_Knock" }, hrp)
	local lv = make("LinearVelocity", { Attachment0 = att, MaxForce = 1e6, VectorVelocity = vel, RelativeTo = Enum.ActuatorRelativeTo.World }, hrp)
	task.delay(0.22, function()
		lv:Destroy()
		att:Destroy()
	end)
end

fxEvent.OnClientEvent:Connect(function(kind, a)
	if kind == "hit" then
		showStatic(0.15, 0.5)
	elseif kind == "landed" then
		flash(Color3.fromRGB(190, 0, 0), 0.15)
	elseif kind == "static" then
		showStatic(a or 1.5, 1)
		showToast("ПОМЕХИ! Сбой видит тебя сквозь стены", "bad")
	elseif kind == "giggle" then
		showStatic(0.3, 0.4)
		showToast("Где-то рядом хихикают… Бинки исчез", "bad")
	elseif kind == "reveal" then
		local list = {}
		for _, s in ipairs(decode("Roster", {})) do
			if s.s == "alive" then table.insert(list, { id = s.id, color = Color3.fromRGB(120, 235, 255) }) end
		end
		xray(list, a or 5)
		showStatic(0.4, 0.6)
	elseif kind == "godseye" then
		-- «Божий глаз» Оскара: все выжившие (в цвете роли) и Палач (красный)
		local list = {}
		for _, s in ipairs(decode("Roster", {})) do
			local c = charById[s.c or ""]
			if s.s == "alive" then table.insert(list, { id = s.id, color = c and roleColor(c) or C.bone }) end
		end
		local k = decode("Killer", {})
		if k.id then table.insert(list, { id = k.id, color = C.red }) end
		xray(list, a or 5)
		flash(Color3.fromRGB(255, 240, 180), 0.25, 0.6)
		sfx("ping", 0.5, 0.7)
	elseif kind == "vanish" then
		vanishUntilLocal = os.clock() + (a or 6)
		showToast("ТЫ НЕВИДИМ — удар раскроет тебя", "warn")
	elseif kind == "dash" then
		showStatic(0.12, 0.3)
	elseif kind == "stunned" then
		stunUntilLocal = os.clock() + (a or 2.5)
		blur.Size = 14
		tween(blur, a or 2.5, { Size = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		showStatic(0.3, 0.7)
		showToast("ТЫ ОГЛУШЁН!", "bad")
	elseif kind == "blinded" then
		local t = a or 1.5
		UI.whiteout.BackgroundTransparency = 0.02
		tween(UI.whiteout, t, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		blur.Size = 24
		tween(blur, t + 0.2, { Size = 0 })
		sfx("ping", 0.7, 1.6)
	elseif kind == "slowed" then
		flash(Color3.fromRGB(80, 140, 255), 0.25, 0.6)
		showToast(string.format("ЗАМЕДЛЕН: −%d%%", a or 0), "bad")
	elseif kind == "knockback" then
		knockback(a)
		showStatic(0.2, 0.5)
	elseif kind == "blocked" then
		flash(a == "shield" and Color3.fromRGB(90, 150, 255) or C.white, 0.3, 0.5)
		showToast(a == "shield" and "ЩИТ ОТРАЗИЛ УДАР!" or "КОНТР-УДАР!", "good")
		sfx("slash", 0.5, 1.4)
	elseif kind == "adrenaline" then
		flash(Color3.fromRGB(255, 60, 60), 0.2, 0.5)
		sfx("ping", 0.5, 1.8)
	elseif kind == "healed" then
		flash(Color3.fromRGB(60, 255, 120), 0.3, 0.8)
		showToast((a or "Медик") .. " лечит тебя: +50", "good")
		sfx("ping", 0.5, 1.3)
	elseif kind == "healgiven" then
		showToast("Ты вылечила: " .. tostring(a or "союзник"), "good")
		sfx("ping", 0.5, 1.3)
	elseif kind == "interrupted" then
		showToast("Лечение сорвано!", "bad")
		showStatic(0.15, 0.4)
	elseif kind == "batbroke" then
		showToast("Бита сломалась о лицо Палача!", "good")
		sfx("slash", 0.6, 0.6)
	elseif kind == "bathit" then
		showToast("Попадание! Палач замедлен", "good")
	elseif kind == "tkhit" then
		showToast(string.format("Телекинез: Палач замедлен на %d%%", a or 0), "good")
	elseif kind == "nomana" then
		showToast("Мало маны", "warn")
		sfx("tick", 0.4, 0.6)
	elseif kind == "windup" then
		sfx("tick", 0.4, 0.8)
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
			U.gburst(UI.headerG, 1)
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
-- НАВЫКИ (Q / E), ВЫБОР СТАНЦИИ ГРЕГА, SHIFT-LOCK НА CTRL, БЕЗ ПРЫЖКОВ
------------------------------------------------------------------------
UI.placingUntil = 0
do -- в блоке: у главного чанка Luau лимит 200 локальных
	function setPlacing(on)
		placing = on
		UI.placeRoot.Visible = on
		UI.placingUntil = on and os.clock() + 6 or 0
		if on then
			ContextActionService:BindActionAtPriority("HorrorPlace", function(_, state, input)
				if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Sink end
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
					chooseStation("heal")
				elseif input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.ButtonL2 then
					chooseStation("speed")
				end
				return Enum.ContextActionResult.Sink
			end, false, Enum.ContextActionPriority.High.Value + 1,
				Enum.UserInputType.MouseButton1, Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonR2, Enum.KeyCode.ButtonL2)
		else
			ContextActionService:UnbindAction("HorrorPlace")
		end
	end

	function chooseStation(kind)
		if not placing then return end
		setPlacing(false)
		abilityEvent:FireServer(1, kind)
		sfx("confirm", 0.5, 0.9)
	end

	local lastSkillPress = { 0, 0 }
	function trySkill(slot)
		if gameState:GetAttribute("Phase") ~= "Match" or not player:GetAttribute("InMatch") then return end
		if player:GetAttribute("Role") ~= "Killer" and player:GetAttribute("Status") ~= "alive" then return end
		local c = myChar()
		local sk = c and c.skills and c.skills[slot]
		if not sk then return end
		local now = os.clock()
		if now - lastSkillPress[slot] < 0.25 then return end
		lastSkillPress[slot] = now
		local sNow = Workspace:GetServerTimeNow()
		-- активная стойка/поза: повторное нажатие уходит на сервер (сбросить щит, выйти из позы лечения)
		if (sk.id == "shield" or sk.id == "heal") and (player:GetAttribute("Skill" .. slot .. "Until") or 0) > sNow then
			abilityEvent:FireServer(slot)
			return
		end
		if placing then
			setPlacing(false)
			return
		end
		if player:GetAttribute("Skill" .. slot .. "Broken") or sNow < (player:GetAttribute("Skill" .. slot .. "ReadyAt") or math.huge) then
			sfx("tick", 0.3, 0.6)
			return
		end
		if sk.id == "station" then
			setPlacing(true)
			sfx("tick", 0.5, 1.2)
			return
		end
		local arg = nil
		if sk.id == "telekinesis" then
			-- прицел — направление камеры, почти горизонтально
			camera = Workspace.CurrentCamera
			local look = camera.CFrame.LookVector
			local v = Vector3.new(look.X, look.Y * 0.3, look.Z)
			arg = v.Magnitude > 0.01 and v.Unit or nil
		end
		abilityEvent:FireServer(slot, arg)
		sfx("confirm", 0.45, 0.8)
		U.edge(UI.slots[slot].edges, C.white)
	end
	ContextActionService:BindAction("HorrorSkill1", function(_, state)
		if state == Enum.UserInputState.Begin then trySkill(1) end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.Q, Enum.KeyCode.ButtonY)
	ContextActionService:BindAction("HorrorSkill2", function(_, state)
		if state == Enum.UserInputState.Begin then trySkill(2) end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.E, Enum.KeyCode.ButtonB)

	-- shift-lock на Ctrl: курсор в центре, персонаж смотрит туда же, куда камера, камера за плечом.
	-- Встроенный shift-lock сервер отключает (Shift занят бегом).
	local shiftLock = false
	local function applyLockToChar()
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.AutoRotate = not shiftLock
			hum.CameraOffset = shiftLock and Vector3.new(1.75, 0.25, 0) or Vector3.new()
		end
	end
	local function setShiftLock(on)
		shiftLock = on
		applyLockToChar()
		if not on then UserInputService.MouseBehavior = Enum.MouseBehavior.Default end
		U.tint(UI.lockParts, "#", on and C.gold or C.edge)
		sfx("tick", 0.35, on and 1.3 or 0.9)
	end
	ContextActionService:BindAction("HorrorShiftLock", function(_, state)
		if state == Enum.UserInputState.Begin then setShiftLock(not shiftLock) end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl)
	RunService:BindToRenderStep("P2D_ShiftLock", Enum.RenderPriority.Camera.Value + 1, function()
		if not shiftLock then return end
		camera = Workspace.CurrentCamera
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if camOn or spectating or not hum or not hrp or hum.Health <= 0 or camera.CameraType ~= Enum.CameraType.Custom then
			-- сцена выбора, наблюдение, смерть: курсор свободен
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			if hum then hum.AutoRotate = true end
			return
		end
		hum.AutoRotate = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		if hrp.Anchored then return end
		local look = camera.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 0.01 then
			hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flat.Unit)
		end
	end)

	-- прыжков нет (сервер обнуляет силу прыжка, клиент ещё и выключает состояние прыжка)
	local function prepCharacter(char)
		local hum = char:WaitForChild("Humanoid", 10)
		if not hum then return end
		pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false) end)
		applyLockToChar()
	end
	player.CharacterAdded:Connect(prepCharacter)
	if player.Character then task.spawn(prepCharacter, player.Character) end

	-- подсказку «Лечение [F]» видят только другие живые выжившие
	local function filterPrompt(prompt)
		if not prompt:IsA("ProximityPrompt") then return end
		if prompt:GetAttribute("OwnerId") == player.UserId or player:GetAttribute("Role") == "Killer" or player:GetAttribute("Status") ~= "alive" then
			prompt.Enabled = false
		end
	end
	for _, pr in ipairs(CollectionService:GetTagged("P2D_HealPrompt")) do filterPrompt(pr) end
	CollectionService:GetInstanceAddedSignal("P2D_HealPrompt"):Connect(filterPrompt)
end

------------------------------------------------------------------------
-- КАЖДЫЙ КАДР: часы, полосы, модель, способность, метка выхода, камера сцены, окружение
------------------------------------------------------------------------
local lastTimeLeft, timeChangedAt = nil, os.clock()
local shownT = 0
local glow, glowS = 0, 0
local tension, redness, shake = 0, 0, 0
local zoneCheckAt = 0
local specRetryAt = 0

local function updateGlitches(dt)
	for i = #U.glitches, 1, -1 do
		local g = U.glitches[i]
		if not g.root.Parent then
			table.remove(U.glitches, i)
		elseif g.root.Visible then
			g.burst = math.max(0, g.burst - dt)
			local k = g.amp * (1 + g.burst * 6)
			local j = (math.random() < 0.03 + g.burst * 0.5) and (math.random() - 0.5) * 8 * k or 0
			g.r.Position = UDim2.fromOffset(-k + j, 0)
			g.b.Position = UDim2.fromOffset(k - j * 0.5, 0)
			g.main.Position = UDim2.fromOffset(j * 0.25, 0)
		end
	end
end

local function updateBars(dt, now)
	-- свои полосы: заливка и «след» урона
	local f = math.clamp(curHealth / curMax, 0, 1)
	local hb = UI.hpBar
	hb.shown = approach(hb.shown, f, dt, 10)
	hb.ghostF = approach(hb.ghostF, f, dt, 2.2)
	if hb.ghostF < f then hb.ghostF = f end
	hb.fill.Size = UDim2.fromScale(hb.shown, 1)
	hb.ghost.Size = UDim2.fromScale(hb.ghostF, 1)
	hb.fill.BackgroundColor3 = U.hpColor(f)
	local low = UI.selfRoot.Visible and math.clamp((0.4 - f) / 0.4, 0, 1) or 0
	local beat = math.max(0, math.sin(now * math.pi * (1.4 + 3 * (1 - f)))) ^ 3
	UI.heartScale.Scale = 1 + 0.18 * beat * (0.3 + low)
	UI.hpCounter.TextColor3 = C.gold:Lerp(C.red, low * beat)
	U.edge(hb.edges, C.black:Lerp(C.red, low * beat))
	UI.stBar.fill.BackgroundTransparency = exhausted and 0.3 * (0.5 + 0.5 * math.sin(now * 14)) or 0
	bustHit = math.max(0, bustHit - dt * 2.5)
	UI.selfShake.Position = UDim2.fromOffset(math.noise(now * 30, 2) * 10 * bustHit, math.noise(now * 30, 5) * 6 * bustHit)
	UI.bustVP.ImageColor3 = C.white:Lerp(Color3.fromRGB(255, 80, 80), bustHit)

	-- карточки игроков
	for _, cd in ipairs(cards) do
		local p = Players:GetPlayerByUserId(cd.userId)
		local hum = p and p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		if cd.isKiller then
			local v = p and p:GetAttribute("Stamina")
			local m = p and p:GetAttribute("MaxStamina")
			if v and m then
				cd.bar.fill.Size = UDim2.fromScale(math.clamp(v / math.max(m, 1), 0, 1), 1)
				cd.bar.ghost.Size = cd.bar.fill.Size
				cd.cnt.Text = "x" .. tostring(p:GetAttribute("Kills") or 0)
			end
			if cd.rings then
				for i, st in ipairs(cd.rings) do
					st.Transparency = 0.15 * (i - 1) + 0.35 * (0.5 + 0.5 * math.sin(now * 3 + i))
				end
			end
		elseif cd.status == "alive" and hum then
			local hf = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
			cd.bar.shown = approach(cd.bar.shown, hf, dt, 8)
			cd.bar.ghostF = math.max(approach(cd.bar.ghostF, hf, dt, 2), hf)
			cd.bar.fill.Size = UDim2.fromScale(cd.bar.shown, 1)
			cd.bar.ghost.Size = UDim2.fromScale(cd.bar.ghostF, 1)
			cd.bar.fill.BackgroundColor3 = U.hpColor(hf)
			cd.cnt.Text = "x" .. tostring(math.max(0, math.ceil(hum.Health)))
			local v = p:GetAttribute("Stamina")
			local m = p:GetAttribute("MaxStamina")
			if v and m then cd.stamFill.Size = UDim2.fromScale(math.clamp(v / math.max(m, 1), 0, 1), 1) end
		end
	end
	return low, beat
end

local function updateSlots(now)
	if placing and os.clock() > UI.placingUntil then setPlacing(false) end -- выбор станции гаснет сам
	if not UI.selfRoot.Visible then return end
	local c = myChar()
	local sNow = Workspace:GetServerTimeNow()
	local stunned = (player:GetAttribute("StunnedUntil") or 0) > sNow
	local rc = c and roleColor(c) or C.edge
	for i, sl in ipairs(UI.slots) do
		local sk = c and c.skills and c.skills[i]
		if sk then
			local readyAt = player:GetAttribute("Skill" .. i .. "ReadyAt")
			local untilT = player:GetAttribute("Skill" .. i .. "Until") or 0
			local broken = player:GetAttribute("Skill" .. i .. "Broken") == true
			sl.broken.Visible = broken
			sl.active.Visible = false
			local cdText = ""
			if broken or stunned then
				sl.shade.Size = UDim2.fromScale(1, 1)
				U.edge(sl.edges, C.red)
			elseif untilT > sNow and (sk.dur or 0) > 0 then
				sl.shade.Size = UDim2.fromScale(1, 0)
				sl.active.Visible = true
				sl.active.Size = UDim2.new(math.clamp((untilT - sNow) / sk.dur, 0, 1), 0, 0, 4)
				U.edge(sl.edges, C.gold)
			elseif not readyAt or readyAt > sNow then
				local left = readyAt and (readyAt - sNow) or 0
				sl.shade.Size = UDim2.fromScale(1, readyAt and math.clamp(left / math.max(sk.cd, 1), 0, 1) or 1)
				cdText = readyAt and tostring(math.ceil(left)) or ""
				U.edge(sl.edges, C.edge)
			elseif sk.id == "telekinesis" and (player:GetAttribute("Mana") or 0) < 5 then
				sl.shade.Size = UDim2.fromScale(1, 1) -- телекинезу нужна мана
				U.edge(sl.edges, C.edge)
			else
				sl.shade.Size = UDim2.fromScale(1, 0)
				U.edge(sl.edges, rc:Lerp(C.white, 0.5 + 0.5 * math.sin(now * 6 + i)))
			end
			sl.cd.Text = cdText
			if UI.touchSkills and UI.touchSkills[i] then UI.touchSkills[i].cd.Text = cdText end
		end
	end
end

local function updateExitMarker(now, match)
	local exitPos = gameState:GetAttribute("ExitPos")
	local show = match and gameState:GetAttribute("EscapeOpen") == true and typeof(exitPos) == "Vector3"
		and player:GetAttribute("InMatch") == true and player:GetAttribute("Role") ~= "Killer" and player:GetAttribute("Status") == "alive"
	UI.exitMarker.Visible = show
	if not show then return end
	camera = Workspace.CurrentCamera
	local sp = camera:WorldToViewportPoint(exitPos + Vector3.new(0, 8, 0))
	local vp = camera.ViewportSize
	local margin = 50
	if sp.Z > 0 and sp.X > margin and sp.X < vp.X - margin and sp.Y > margin and sp.Y < vp.Y - margin then
		UI.exitMarker.Position = UDim2.fromOffset(sp.X, sp.Y)
	else
		-- выход за кадром: значок прижимается к краю экрана со стороны выхода
		local cx, cy = vp.X / 2, vp.Y / 2
		local dx, dy = sp.X - cx, sp.Y - cy
		if sp.Z <= 0 then dx, dy = -dx, -dy end
		if math.abs(dx) < 1e-3 and math.abs(dy) < 1e-3 then dy = 1 end
		local k = math.min((cx - margin) / math.max(math.abs(dx), 1e-3), (cy - margin) / math.max(math.abs(dy), 1e-3))
		UI.exitMarker.Position = UDim2.fromOffset(cx + dx * k, cy + dy * k)
	end
	U.tint(UI.exitDoorParts, "#", C.hp, (math.floor(now * 2) % 2 == 0) and 0 or 0.45)
end

local function updateStage(dt, now)
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
	-- монитор Палача: опускается после его выбора, качается на цепях
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
		if UI.monitorClone and UI.monitorClone.Parent then
			local target, size = bustTarget(UI.monitorClone)
			local d = size * 1.3
			target += Vector3.new(0, size * 0.06, 0)
			UI.monitorCam.CFrame = CFrame.lookAt(target + Vector3.new((0.25 + math.sin(now * 0.7) * 0.1) * d, 0.1 * d, -0.95 * d), target)
		end
	elseif not camOn then
		monitorAlpha = 0
	end
end

local function updateWorld(dt, now)
	for part, d in pairs(tagged.P2D_Spin) do
		if part.Parent then part.CFrame = d.base * CFrame.Angles(0, now * (part:GetAttribute("Speed") or 2), 0) end
	end
	for mdl, d in pairs(tagged.P2D_SpinModel) do
		if mdl.Parent then
			local a = now * (mdl:GetAttribute("Speed") or 1)
			mdl:PivotTo(d.base * (mdl:GetAttribute("Axis") == "Z" and CFrame.Angles(0, 0, a) or CFrame.Angles(0, a, 0)))
		end
	end
	for part, d in pairs(tagged.P2D_Blink) do
		if part.Parent then
			local on = math.sin(now * math.pi * (part:GetAttribute("Rate") or 1) + d.seed) > -0.2
			part.Transparency = on and d.tr or 0.85
		end
	end
	for part, d in pairs(tagged.P2D_Pulse) do
		if part.Parent then
			part.Color = d.color:Lerp(C.white, 0.35 * (0.5 + 0.5 * math.sin(now * 2 + d.seed * 3)))
		end
	end
	for bb, d in pairs(tagged.P2D_Dizzy) do
		if bb.Parent then
			local stars = bb:GetChildren()
			for i, s in ipairs(stars) do
				if s:IsA("GuiObject") then
					local a = now * 4 + d.seed + i * (math.pi * 2 / #stars)
					s.Position = UDim2.fromScale(0.5 + math.cos(a) * 0.4, 0.5 + math.sin(a) * 0.3)
					s.Rotation = now * 240
				end
			end
		end
	end
	flickerClock += dt
	if flickerClock > 0.08 then
		flickerClock = 0
		for part, d in pairs(tagged.P2D_Flicker) do
			if part.Parent then
				local strong = part:GetAttribute("Strong")
				if math.random() < (strong and 0.25 or 0.03) then
					part.Color = d.color:Lerp(C.black, math.random() * (strong and 0.7 or 0.85))
				else
					part.Color = d.color
				end
			end
		end
	end
end

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	local phase = gameState:GetAttribute("Phase")
	local t = gameState:GetAttribute("TimeLeft") or 0
	local timed = phase == "Match" or phase == "Countdown" or phase == "Selection"
	local match = phase == "Match"
	local sc = hudScale()
	-- список игроков ужимается, чтобы при 7 игроках не наезжать на свой HUD
	local avail = gui.AbsoluteSize.Y - 80 - (UI.selfRoot.Visible and (276 * sc) or 20)
	UI.listScale.Scale = math.clamp(math.min(sc, avail / math.max(rowCount * 84, 1)), 0.4, sc)
	UI.selfScale.Scale = sc
	UI.hintScale.Scale = sc
	UI.placeScale.Scale = sc
	UI.specScale.Scale = sc
	UI.watchScale.Scale = sc
	if not UI.resultsRoot.Visible then UI.resultsScale.Scale = sc end

	-- часы: спокойно -> тревога (<= 60 c) -> критично (<= 10 c)
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
	if timed then U.gtext(UI.timeG, fmt(math.ceil(shownT))) end
	UI.secondHand.Rotation = timed and -(shownT % 60) * 6 or now * 90
	UI.minuteHand.Rotation = -((shownT / 60) % 60) * 6
	UI.hourHand.Rotation = -((shownT / 3600) % 12) * 30

	local r = math.clamp(redness + glowS * 0.9, 0, 1)
	UI.faceStroke.Color = C.black:Lerp(C.red, r)
	UI.clockFace.BackgroundColor3 = UI.FACE_CALM:Lerp(UI.FACE_ALERT, r)
	UI.timeG.main.TextColor3 = C.gold:Lerp(C.red, r)
	UI.timeG.amp = 1 + 2.5 * tension + 3 * glowS
	U.tint(UI.faceSkullParts, "#", C.red, 1 - r * 0.6)
	U.tint(UI.faceSkullParts, "x", C.ink, 1 - r * 0.6)
	U.edge(UI.clockEdges, C.edge:Lerp(C.red, r))
	U.edge(UI.plateEdges, C.edge:Lerp(C.red, r))
	UI.clockDanger.Visible = r > 0.05
	local pulse = 0.5 + 0.5 * math.sin(now * (4 + 6 * tension))
	for i, st in ipairs(UI.clockRings) do
		st.Transparency = math.clamp(1 - r * (1 - 0.25 * (i - 1)) + pulse * 0.25, 0, 1)
	end
	local freq = 12 + 30 * shake
	local nx = math.noise(now * freq, 1.3) * 2
	local ny = math.noise(now * freq, 7.7) * 2
	local nr = math.noise(now * freq, 4.2) * 2
	local cs = camOn and sc * 0.75 or sc
	UI.clockScale.Scale = cs * (1 + 0.045 * tension * math.max(0, math.sin(now * 9)) ^ 2)
	UI.objScale.Scale = approach(UI.objScale.Scale, 1, dt, 6)
	UI.toastBox.Position = UDim2.new(0.5, 0, 0, 16 + (UI.objBox.Visible and 232 or 200) * UI.clockScale.Scale)
	UI.clockFrame.Rotation = -5 + nr * shake * 5
	UI.clockFrame.Position = UDim2.fromOffset(120 + nx * shake * 5, 10 + ny * shake * 5)

	local low, beat = updateBars(dt, now)

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
		local target, size = bustTarget(bustModel)
		target += Vector3.new(0, size * 0.12, 0)
		local d = size * 1.2
		local sway = math.sin(now * 0.9) * 0.08
		UI.bustCam.CFrame = CFrame.lookAt(target + Vector3.new((0.42 + sway) * d, 0.12 * d, -0.9 * d), target)
	end

	updateSlots(now)
	updateExitMarker(now, match)

	-- оглушение: звёзды кружат перед глазами
	local stunned = stunUntilLocal > now
	UI.dizzyRoot.Visible = stunned
	if stunned then
		for i, s in ipairs(UI.dizzyStars) do
			local a = now * 5 + i * (math.pi * 2 / #UI.dizzyStars)
			s.Position = UDim2.fromScale(0.5 + math.cos(a) * 0.45, 0.5 + math.sin(a) * 0.35)
		end
	end

	-- виньетка: краснеет при низком здоровье, фиолетовая при невидимости
	local alpha = 0.42 + 0.18 * tension + 0.28 * low * (0.6 + 0.4 * beat)
	local vcol = C.black:Lerp(Color3.fromRGB(80, 0, 0), math.clamp(low * 0.9 + redness * 0.25, 0, 1))
	if vanishUntilLocal > now then vcol = Color3.fromRGB(60, 20, 90) end
	for _, vf in ipairs(UI.vigFrames) do
		vf.BackgroundColor3 = vcol
		vf.BackgroundTransparency = 1 - math.clamp(alpha, 0, 0.95)
	end
	UI.rollBar.Position = UDim2.new(0, 0, (now * 0.07) % 1.2 - 0.1, 0)

	-- помехи
	local sOn = now < staticUntil
	UI.staticRoot.Visible = sOn
	if sOn then
		local k = math.clamp((staticUntil - now) / 0.4, 0.2, 1) * staticStrength
		for _, bar in ipairs(UI.staticBars) do
			bar.Position = UDim2.fromScale(math.random() * 0.4 - 0.2, math.random())
			bar.Size = UDim2.new(math.random() * 0.8 + 0.4, 0, 0, math.random(2, 22))
			local g = math.random(120, 255)
			local roll = math.random()
			bar.BackgroundColor3 = (roll < 0.12 and C.magenta) or (roll < 0.24 and C.cyan) or Color3.fromRGB(g, g, g)
			bar.BackgroundTransparency = 1 - k * math.random() * 0.7
		end
	end
	updateGlitches(dt)
	updateStage(dt, now)

	-- наблюдение
	if spectating and specTarget and now >= specRetryAt then
		specRetryAt = now + 0.5
		local p = Players:GetPlayerByUserId(specTarget)
		local hum = p and p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		camera = Workspace.CurrentCamera
		if hum and camera.CameraSubject ~= hum then camera.CameraSubject = hum end
	end

	updateWorld(dt, now)

	-- освещение по зоне, где находится камера; экран лобби
	if now >= zoneCheckAt then
		zoneCheckAt = now + 0.5
		camera = Workspace.CurrentCamera
		local z = zoneAt(camera.CFrame.Position) or zoneAt(camera.Focus.Position)
		if z then applyPreset(z) end
		if UI.lobbyBlink then UI.lobbyBlink.TextTransparency = (math.floor(now * 1.6) % 2 == 0) and 0 or 1 end
		if UI.lobbyTip and math.floor(now) % 6 == 0 then UI.lobbyTip.Text = TIPS[(math.floor(now / 6) % #TIPS) + 1] end
		if UI.lobbyScratches then
			for _, s in ipairs(UI.lobbyScratches) do
				s.Position = UDim2.fromScale(math.random(), 0)
				s.BackgroundTransparency = math.random() < 0.5 and 0.8 or 1
			end
		end
		if UI.lobbyTitle and math.random() < 0.3 then U.gburst(UI.lobbyTitle, 0.3) end
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
			if ph == "Match" and t <= 10 and t > 0 then
				sfx("tick", 0.6, 0.7)
				U.gburst(UI.timeG, 0.25)
			end
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
	elseif name == "Roles" then
		roles = decode("Roles", {})
	elseif name == "Maps" then
		loadMaps()
	elseif name == "Zones" then
		zones = decode("Zones", {})
	elseif name == "BonusSeq" then
		local seq = gameState:GetAttribute("BonusSeq") or 0
		if seq ~= lastBonusSeq then
			lastBonusSeq = seq
			glow = 1
			U.gburst(UI.timeG, 0.8)
		end
	elseif name == "EscapeOpen" then
		if gameState:GetAttribute("EscapeOpen") then
			showStatic(0.3, 0.5)
			sfx("ping", 0.7, 0.6)
			UI.objScale.Scale = 1.3
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
	elseif name == "Mana" or name == "MaxMana" then
		refreshMana()
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
