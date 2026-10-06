--[[
	PRESS2DIE — GameServer (Script)  ->  положить в ServerScriptService

	Проклятая игровая приставка 90-х, внутри которой заперты люди.
	Асимметричный хоррор 1 vs все: один Палач против до 6 выживших.

	Сервер строит всё кодом и ведёт игру:
	  • ЛОББИ «внутри приставки»: материнская плата, чипы, радиатор, шлейф,
	    большой экран статуса и 4 картриджа-платформы для голосования за уровень;
	  • СЦЕНА ВЫБОРА: 6 подиумов P1..P6 с прожекторами (выжившие встают на сцену
	    слева направо в порядке выбора) и монитор, который опускается, когда
	    Палач выбрал облик;
	  • 4 КАРТРИДЖА-КАРТЫ: «Холмы радости», «Аркада «Полночь»», «Лабиринт 8-бит»
	    (стены перестраиваются каждый матч) и «Детская 1996» (выжившие крошечные);
	  • МАТЧ: жетоны открывают выход раньше времени, 3 Палача со способностями,
	    выносливость и бег, бонус времени за убийство, итоги матча.

	Клиентский интерфейс — в GameClient (LocalScript).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

------------------------------------------------------------------------
-- НАСТРОЙКИ
------------------------------------------------------------------------
local CONFIG = {
	MIN_PLAYERS = 2,          -- минимум игроков для старта (1 Палач + 1 выживший). Для одиночного теста поставь 1
	MAX_SURVIVORS = 6,        -- выживших в матче (+1 Палач = 7 игроков)
	LOBBY_COUNTDOWN = 30,     -- секунд лобби до старта
	BASE_MATCH_TIME = 60,     -- матч = 60 c + 60 c * число выживших
	TIME_PER_SURVIVOR = 60,
	ESCAPE_OPEN_AT = 60,      -- выход открывается сам, когда до конца осталось <= 60 c
	ESCAPE_RADIUS = 7,        -- радиус зоны выхода
	ENDING_TIME = 9,          -- экран итогов перед возвратом в лобби
	SELECT_TIME = 25,         -- секунд на выбор персонажа
	SELECT_SHORT = 3,         -- когда все выбрали, остаток времени сокращается до этого значения
	REVEAL_TIME = 2,          -- пауза «все на сцене» перед матчем
	KILL_BONUS_TIME = 20,     -- +секунд к матчу за убийство выжившего
	FADE_TIME = 1.2,          -- пауза под затемнение между этапами
	SURVIVOR_HEALTH = 100,
	SURVIVOR_SPEED = 16,
	KILLER_SPEED = 18,
	SURVIVOR_SPRINT_SPEED = 23,
	KILLER_SPRINT_SPEED = 25,
	STAMINA_MAX_SURVIVOR = 100,
	STAMINA_MAX_KILLER = 125,
	STAMINA_DRAIN = 20,
	STAMINA_REGEN = 14,
	STAMINA_REGEN_DELAY = 1.5,
	STAMINA_RECOVER_FRACTION = 0.25,
	HIT_BOOST_MULT = 1.35,
	HIT_BOOST_TIME = 3,
	KILLER_DAMAGE = 34,       -- 3 удара убивают обычного выжившего
	KILLER_RANGE = 8,
	KILLER_COOLDOWN = 1.2,
	DASH_SPEED = 62,          -- скорость Палача во время «Рывка»
	ABILITY_FIRST_DELAY = 8,  -- способность Палача готова через N секунд после старта
	TOKEN_RADIUS = 4.5,       -- радиус подбора жетона
	TOKENS_BASE = 2,          -- нужно жетонов = 2 + 2 за каждого выжившего (не больше 12)
	TOKENS_PER_SURVIVOR = 2,
	TOKENS_MAX = 12,
	TOKENS_EXTRA = 4,         -- запасные жетоны на карте
	TOKEN_OPEN_CAP = 75,      -- после сбора всех жетонов до конца матча остаётся не больше N секунд
	LOBBY_POS = Vector3.new(0, 300, 0),
	STAGE_POS = Vector3.new(0, 900, -3000),
}

local M = Enum.Material
local rng = Random.new()
local VERT = CFrame.Angles(0, 0, math.rad(90))   -- ставит цилиндр вертикально
local ALONG_Z = CFrame.Angles(0, math.rad(90), 0) -- ось цилиндра вдоль Z
local DOOR_H = 9
local NOCOL = { CanCollide = false, CanQuery = false, CastShadow = false }
local FLAT = { CanCollide = false, CanQuery = false, CastShadow = false, CanTouch = false }

local GOLD = Color3.fromRGB(255, 196, 60)
local GREEN = Color3.fromRGB(80, 255, 120)
local BLOOD = Color3.fromRGB(190, 26, 32)
local PLASTIC = Color3.fromRGB(150, 148, 156)
local PLASTIC_DARK = Color3.fromRGB(38, 37, 43)
local BLACK = Color3.new(0, 0, 0)

------------------------------------------------------------------------
-- ОКРУЖЕНИЕ: очистка шаблона, базовое освещение (пресеты по зонам ставит клиент)
------------------------------------------------------------------------
for _, o in ipairs(Workspace:GetChildren()) do
	if o:IsA("SpawnLocation") or o.Name == "Baseplate" then o:Destroy() end
end

Lighting.ClockTime = 0
Lighting.Brightness = 1
Lighting.Ambient = Color3.fromRGB(40, 46, 52)
Lighting.OutdoorAmbient = Color3.fromRGB(40, 46, 60)
Lighting.FogColor = Color3.fromRGB(8, 10, 14)
Lighting.FogStart = 60
Lighting.FogEnd = 420
do
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atm then
		atm = Instance.new("Atmosphere")
		atm.Parent = Lighting
	end
	atm.Density = 0.3
	atm.Offset = 0.2
	atm.Color = Color3.fromRGB(40, 45, 60)
	atm.Decay = Color3.fromRGB(20, 20, 30)
	atm.Haze = 1.5
end
Players.RespawnTime = 3

------------------------------------------------------------------------
-- РЕПЛИЦИРУЕМОЕ СОСТОЯНИЕ (читает клиент)
------------------------------------------------------------------------
local gameState = Instance.new("Folder")
gameState.Name = "GameState"
gameState.Parent = ReplicatedStorage

local remotes = Instance.new("Folder")
remotes.Name = "HorrorRemotes"
remotes.Parent = ReplicatedStorage

local function remote(name)
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local announceEvent = remote("Announce")      -- (text, kind)
local sprintEvent = remote("Sprint")          -- клиент: держу Shift
local pickEvent = remote("PickCharacter")     -- клиент: выбираю персонажа
local pickStateEvent = remote("PickState")    -- сервер: (мой выбор, моя роль)
local abilityEvent = remote("Ability")        -- клиент: способность Палача
local fxEvent = remote("Fx")                  -- сервер: эффекты (жетон, помехи, подсветка...)
local resultsEvent = remote("Results")        -- сервер: итоги матча
local spectateEvent = remote("Spectate")      -- клиент: за кем наблюдаю (для стриминга)

gameState:SetAttribute("Phase", "Waiting") -- Waiting | Countdown | ToSelection | Selection | Starting | Match | Ending | Returning
gameState:SetAttribute("TimeLeft", 0)
gameState:SetAttribute("EscapeOpen", false)
gameState:SetAttribute("MinPlayers", CONFIG.MIN_PLAYERS)
gameState:SetAttribute("Roster", "[]")
gameState:SetAttribute("Killer", "{}")
gameState:SetAttribute("Stage", "{}")
gameState:SetAttribute("Taken", "[]")
gameState:SetAttribute("Votes", "{}")
gameState:SetAttribute("MapKey", "")
gameState:SetAttribute("Tokens", 0)
gameState:SetAttribute("TokensNeeded", 0)
gameState:SetAttribute("ExitName", "")
gameState:SetAttribute("SelectLocked", false)
gameState:SetAttribute("BonusSeq", 0)
gameState:SetAttribute("StageCenter", CONFIG.STAGE_POS)

------------------------------------------------------------------------
-- СТРОИТЕЛЬНЫЕ ХЕЛПЕРЫ
------------------------------------------------------------------------
local function mkc(class, parent, name, size, cf, color, material, opts)
	local p = Instance.new(class)
	p.Name = name
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	if typeof(cf) == "Vector3" then
		p.CFrame = CFrame.new(cf)
	else
		p.CFrame = cf
	end
	p.Color = color
	p.Material = material
	if opts then
		for k, v in pairs(opts) do
			p[k] = v
		end
	end
	p.Parent = parent
	return p
end

local function mk(parent, name, size, cf, color, material, opts)
	return mkc("Part", parent, name, size, cf, color, material, opts)
end

local function withShape(opts, shape)
	local t = { Shape = shape }
	if opts then
		for k, v in pairs(opts) do t[k] = v end
	end
	return t
end

-- вертикальный цилиндр высотой h и диаметром d с центром в pos
local function cyl(parent, name, h, d, pos, color, mat, opts)
	local cf = typeof(pos) == "Vector3" and CFrame.new(pos) or pos
	return mk(parent, name, Vector3.new(h, d, d), cf * VERT, color, mat, withShape(opts, Enum.PartType.Cylinder))
end

local function ball(parent, name, d, pos, color, mat, opts)
	return mk(parent, name, Vector3.new(d, d, d), pos, color, mat, withShape(opts, Enum.PartType.Ball))
end

local function tag(inst, name, attrs)
	CollectionService:AddTag(inst, name)
	if attrs then
		for k, v in pairs(attrs) do inst:SetAttribute(k, v) end
	end
	return inst
end

local function wallSeg(parent, a, b, h, thick, color, mat)
	local len = (b - a).Magnitude
	if len < 0.05 then return end
	local alongX = math.abs(b.X - a.X) > math.abs(b.Z - a.Z)
	local size = alongX and Vector3.new(len, h, thick) or Vector3.new(thick, h, len)
	mk(parent, "Wall", size, (a + b) / 2 + Vector3.new(0, h / 2, 0), color, mat)
end

-- стена от a до b (оси X или Z), опционально с дверным проёмом по центру
local function wall(parent, a, b, h, thick, color, mat, doorW)
	if not doorW then
		wallSeg(parent, a, b, h, thick, color, mat)
		return
	end
	local dir = (b - a).Unit
	local half = ((b - a).Magnitude - doorW) / 2
	wallSeg(parent, a, a + dir * half, h, thick, color, mat)
	wallSeg(parent, b - dir * half, b, h, thick, color, mat)
	if h > DOOR_H then
		local alongX = math.abs(b.X - a.X) > math.abs(b.Z - a.Z)
		local lh = h - DOOR_H
		local size = alongX and Vector3.new(doorW, lh, thick) or Vector3.new(thick, lh, doorW)
		mk(parent, "Lintel", size, (a + b) / 2 + Vector3.new(0, DOOR_H + lh / 2, 0), color, mat)
	end
end

-- комната: 4 стены, крыша, лампа. doors = {N=true,S=true,W=true,E=true}
local function room(parent, center, w, d, h, color, mat, doors, doorW, lampColor)
	doorW = doorW or 8
	local t = 2
	local x1, x2 = center.X - w / 2, center.X + w / 2
	local z1, z2 = center.Z - d / 2, center.Z + d / 2
	local y = center.Y
	local function P(x, z) return Vector3.new(x, y, z) end
	wall(parent, P(x1 - t / 2, z1), P(x2 + t / 2, z1), h, t, color, mat, doors.N and doorW)
	wall(parent, P(x1 - t / 2, z2), P(x2 + t / 2, z2), h, t, color, mat, doors.S and doorW)
	wall(parent, P(x1, z1), P(x1, z2), h, t, color, mat, doors.W and doorW)
	wall(parent, P(x2, z1), P(x2, z2), h, t, color, mat, doors.E and doorW)
	mk(parent, "Roof", Vector3.new(w + t, 1, d + t), Vector3.new(center.X, y + h + 0.5, center.Z), color, mat)
	local lamp = mk(parent, "Lamp", Vector3.new(4, 0.5, 4), Vector3.new(center.X, y + h - 0.25, center.Z),
		Color3.fromRGB(255, 235, 190), M.Neon, NOCOL)
	local light = Instance.new("PointLight")
	light.Range = math.max(w, d) * 0.8
	light.Brightness = 1.2
	light.Color = lampColor or Color3.fromRGB(255, 200, 140)
	light.Parent = lamp
	tag(lamp, "P2D_Flicker")
end

local function pointLight(part, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Parent = part
	return l
end

-- SurfaceGui с крупным текстом (PixelsPerStud подбирается под высоту грани)
local function faceDims(part, face)
	local s = part.Size
	if face == Enum.NormalId.Front or face == Enum.NormalId.Back then return s.X, s.Y end
	if face == Enum.NormalId.Left or face == Enum.NormalId.Right then return s.Z, s.Y end
	return s.X, s.Z
end

local function surfaceGui(part, face, pps)
	local _, h = faceDims(part, face)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = pps or math.clamp(160 / math.max(h, 0.1), 4, 60)
	sg.LightInfluence = 0
	sg.Parent = part
	return sg
end

local function surfaceText(part, face, text, o)
	o = o or {}
	local sg = surfaceGui(part, face, o.pps)
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.BorderSizePixel = 0
	t.BackgroundTransparency = o.bg and 0 or 1
	t.BackgroundColor3 = o.bg or BLACK
	t.Size = UDim2.fromScale(1, 1)
	t.Font = o.font or Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextWrapped = true
	t.TextColor3 = o.color or Color3.new(1, 1, 1)
	t.TextStrokeTransparency = o.stroke or 1
	t.Text = text
	t.Parent = sg
	return t, sg
end

-- пиксель-арт из строк: символ -> цвет палитры, «.» — пусто. Соседние пиксели склеиваются в одну деталь.
local function pixelArt(parent, cf, rows, px, palette, depth)
	local h = #rows
	for r, row in ipairs(rows) do
		local w = #row
		local c = 1
		while c <= w do
			local ch = string.sub(row, c, c)
			local run = 1
			while c + run <= w and string.sub(row, c + run, c + run) == ch do
				run += 1
			end
			local col = palette[ch]
			if col then
				local x = (c - 1 + run / 2 - w / 2) * px
				local y = (h / 2 - (r - 1) - 0.5) * px
				mk(parent, "Px", Vector3.new(run * px, px, depth or px), cf * CFrame.new(x, y, 0), col, M.Neon, NOCOL)
			end
			c += run
		end
	end
end

local SKULL = {
	"..#####..",
	".#######.",
	"##.###.##",
	"#...#...#",
	"##.###.##",
	".#######.",
	"..#.#.#..",
	"..#####..",
}

------------------------------------------------------------------------
-- ПЕРСОНАЖИ: 6 выживших + 3 Палача. Один персонаж = один игрок.
-- Пипсы 1..5 (3 = базовое значение). У выживших hp/speed/stamina, у Палачей power/speed/stamina.
------------------------------------------------------------------------
local CHARACTERS = {
	{ id = "alex", name = "Алекс", role = "Школьник", killer = false, color = { 86, 156, 214 },
		hp = 3, speed = 3, stamina = 3,
		desc = "Первым вставил картридж — первым и пропал. Ровный во всём." },
	{ id = "oscar", name = "Оскар", role = "Мастер по ремонту", killer = false, color = { 150, 110, 70 },
		hp = 5, speed = 2, stamina = 3,
		desc = "Чинил приставки на радиорынке. Выдержит лишний удар, но бегает медленно." },
	{ id = "lilian", name = "Лилиан", role = "Спидраннерша", killer = false, f = true, color = { 190, 90, 160 },
		hp = 2, speed = 4, stamina = 4,
		desc = "Знает каждый баг уровня. Быстрая и выносливая, но хрупкая." },
	{ id = "greg", name = "Грег", role = "Продавец картриджей", killer = false, color = { 110, 160, 90 },
		hp = 4, speed = 3, stamina = 2,
		desc = "Торговал «999 игр в 1». Держит удар, но быстро выдыхается." },
	{ id = "aisha", name = "Айша", role = "Чемпионка аркад", killer = false, f = true, color = { 230, 160, 60 },
		hp = 2, speed = 5, stamina = 3,
		desc = "Рекорд в каждом автомате. Самая быстрая из запертых." },
	{ id = "felix", name = "Феликс", role = "Бета-тестер", killer = false, color = { 150, 120, 220 },
		hp = 3, speed = 3, stamina = 4,
		desc = "Тестировал PRESS2DIE до релиза. Знает, когда бежать." },
	{ id = "executioner", name = "Палач", role = "Хозяин картриджа", killer = true, color = { 200, 30, 30 },
		power = 4, speed = 3, stamina = 4,
		desc = "Ржавый тесак и рывок на добычу. Догоняет на прямой.",
		ability = { id = "dash", name = "РЫВОК", cd = 14, dur = 0.55, text = "Мгновенный рывок вперёд" } },
	{ id = "glitch", name = "Сбой", role = "Ошибка в коде", killer = true, color = { 70, 210, 235 },
		power = 3, speed = 3, stamina = 4,
		desc = "Экраны идут помехами — и Сбой видит всех сквозь стены.",
		ability = { id = "reveal", name = "ПОМЕХИ", cd = 24, dur = 5, text = "5 с видит всех выживших сквозь стены" } },
	{ id = "binky", name = "Бинки", role = "Талисман приставки", killer = true, color = { 150, 80, 220 },
		power = 3, speed = 4, stamina = 3,
		desc = "Улыбается с коробки. Исчезает и появляется за спиной.",
		ability = { id = "vanish", name = "ПРЯТКИ", cd = 26, dur = 6, text = "6 с невидимости, удар раскрывает" } },
}
local CHAR_BY_ID = {}
for _, c in ipairs(CHARACTERS) do CHAR_BY_ID[c.id] = c end
gameState:SetAttribute("Characters", HttpService:JSONEncode(CHARACTERS))

local function charColor(c) return Color3.fromRGB(c.color[1], c.color[2], c.color[3]) end

-- снаряжение на голове (детали приварены к Head)
local function V(x, y, z) return Vector3.new(x, y, z) end
local CF = CFrame.new
local CYL = Enum.PartType.Cylinder
local BALL = Enum.PartType.Ball
local GEAR = {
	alex = function(add, u)
		add("Cap", V(0.34 * u, 1.06 * u, 1.06 * u), CF(0, 0.42 * u, 0) * VERT, Color3.fromRGB(40, 90, 200), M.SmoothPlastic, CYL)
		add("Brim", V(0.8 * u, 0.08 * u, 0.5 * u), CF(0, 0.32 * u, 0.66 * u), Color3.fromRGB(28, 60, 140))
	end,
	oscar = function(add, u)
		add("Hat", V(0.42 * u, 1.12 * u, 1.12 * u), CF(0, 0.46 * u, 0) * VERT, Color3.fromRGB(230, 190, 40), M.SmoothPlastic, CYL)
		add("HatBrim", V(0.08 * u, 1.45 * u, 1.45 * u), CF(0, 0.28 * u, 0) * VERT, Color3.fromRGB(200, 160, 30), M.SmoothPlastic, CYL)
		add("Headlamp", V(0.18 * u, 0.26 * u, 0.26 * u), CF(0, 0.48 * u, -0.6 * u) * ALONG_Z, Color3.fromRGB(255, 250, 220), M.Neon, CYL)
		add("Mustache", V(0.55 * u, 0.12 * u, 0.08 * u), CF(0, -0.18 * u, -0.54 * u), Color3.fromRGB(70, 44, 26))
	end,
	lilian = function(add, u)
		add("Hair", V(1.0 * u, 0.95 * u, 0.32 * u), CF(0, -0.08 * u, 0.5 * u), Color3.fromRGB(70, 30, 60))
		add("Band", V(1.2 * u, 0.12 * u, 0.2 * u), CF(0, 0.6 * u, 0), Color3.fromRGB(230, 90, 170))
		add("CupL", V(0.24 * u, 0.52 * u, 0.52 * u), CF(-0.6 * u, 0.02 * u, 0), Color3.fromRGB(230, 90, 170), M.SmoothPlastic, CYL)
		add("CupR", V(0.24 * u, 0.52 * u, 0.52 * u), CF(0.6 * u, 0.02 * u, 0), Color3.fromRGB(230, 90, 170), M.SmoothPlastic, CYL)
	end,
	greg = function(add, u)
		add("Shades", V(0.98 * u, 0.2 * u, 0.08 * u), CF(0, 0.08 * u, -0.53 * u), Color3.fromRGB(10, 10, 12), M.Glass)
		add("Cap", V(0.24 * u, 1.08 * u, 1.08 * u), CF(0, 0.5 * u, 0) * VERT, Color3.fromRGB(90, 110, 60), M.SmoothPlastic, CYL)
		add("Brim", V(0.85 * u, 0.06 * u, 0.45 * u), CF(0, 0.42 * u, -0.6 * u), Color3.fromRGB(70, 88, 46))
	end,
	aisha = function(add, u)
		add("Headband", V(0.16 * u, 1.1 * u, 1.1 * u), CF(0, 0.26 * u, 0) * VERT, Color3.fromRGB(255, 150, 40), M.Neon, CYL)
		add("Bun", V(0.5 * u, 0.5 * u, 0.5 * u), CF(0, 0.32 * u, 0.62 * u), Color3.fromRGB(40, 25, 20), M.SmoothPlastic, BALL)
		add("Tail", V(0.38 * u, 0.38 * u, 0.38 * u), CF(0, 0, 0.8 * u), Color3.fromRGB(40, 25, 20), M.SmoothPlastic, BALL)
	end,
	felix = function(add, u)
		add("Beanie", V(0.32 * u, 1.08 * u, 1.08 * u), CF(0, 0.48 * u, 0) * VERT, Color3.fromRGB(150, 120, 220), M.SmoothPlastic, CYL)
		add("Stripe", V(0.1 * u, 1.1 * u, 1.1 * u), CF(0, 0.4 * u, 0) * VERT, Color3.fromRGB(255, 210, 60), M.SmoothPlastic, CYL)
		add("Stem", V(0.3 * u, 0.08 * u, 0.08 * u), CF(0, 0.76 * u, 0) * VERT, Color3.fromRGB(120, 120, 130), M.Metal, CYL)
		add("BladeA", V(1.0 * u, 0.04 * u, 0.16 * u), CF(0, 0.9 * u, 0), Color3.fromRGB(230, 50, 50))
		add("BladeB", V(0.16 * u, 0.04 * u, 1.0 * u), CF(0, 0.9 * u, 0), Color3.fromRGB(255, 210, 60))
		add("LensL", V(0.06 * u, 0.34 * u, 0.34 * u), CF(-0.21 * u, 0.06 * u, -0.55 * u) * ALONG_Z, Color3.fromRGB(20, 20, 24), M.SmoothPlastic, CYL)
		add("LensR", V(0.06 * u, 0.34 * u, 0.34 * u), CF(0.21 * u, 0.06 * u, -0.55 * u) * ALONG_Z, Color3.fromRGB(20, 20, 24), M.SmoothPlastic, CYL)
	end,
	executioner = function(add, u)
		add("Hood", V(1.32 * u, 1.36 * u, 1.3 * u), CF(0, 0.08 * u, 0.04 * u), Color3.fromRGB(18, 16, 18), M.Fabric)
		add("EyeL", V(0.26 * u, 0.08 * u, 0.06 * u), CF(-0.22 * u, 0.1 * u, -0.68 * u), Color3.fromRGB(255, 40, 30), M.Neon)
		add("EyeR", V(0.26 * u, 0.08 * u, 0.06 * u), CF(0.22 * u, 0.1 * u, -0.68 * u), Color3.fromRGB(255, 40, 30), M.Neon)
		add("Stitch", V(0.5 * u, 0.04 * u, 0.06 * u), CF(0, -0.28 * u, -0.68 * u), Color3.fromRGB(110, 10, 10))
	end,
	glitch = function(add, u)
		add("TV", V(1.62 * u, 1.32 * u, 1.3 * u), CF(0, 0.12 * u, 0.05 * u), Color3.fromRGB(44, 44, 50))
		local screen = add("TVScreen", V(1.28 * u, 0.98 * u, 0.06 * u), CF(0, 0.14 * u, -0.62 * u), Color3.fromRGB(120, 235, 255), M.Neon)
		tag(screen, "P2D_Flicker", { Strong = true })
		add("AntL", V(0.05 * u, 0.9 * u, 0.05 * u), CF(-0.28 * u, 1.12 * u, 0.05 * u) * CFrame.Angles(0, 0, math.rad(25)), Color3.fromRGB(180, 180, 190), M.Metal)
		add("AntR", V(0.05 * u, 0.9 * u, 0.05 * u), CF(0.28 * u, 1.12 * u, 0.05 * u) * CFrame.Angles(0, 0, math.rad(-25)), Color3.fromRGB(180, 180, 190), M.Metal)
	end,
	binky = function(add, u)
		for _, s in ipairs({ -1, 1 }) do
			local ear = CF(s * 0.34 * u, 1.05 * u, 0) * CFrame.Angles(0, 0, math.rad(-12 * s))
			add("Ear", V(0.34 * u, 1.25 * u, 0.14 * u), ear, Color3.fromRGB(150, 80, 220))
			add("EarIn", V(0.2 * u, 0.9 * u, 0.05 * u), ear * CF(0, 0, -0.08 * u), Color3.fromRGB(255, 150, 200))
			add("Eye", V(0.06 * u, 0.4 * u, 0.4 * u), CF(s * 0.22 * u, 0.12 * u, -0.6 * u) * ALONG_Z, Color3.fromRGB(5, 5, 5), M.SmoothPlastic, CYL)
			add("Pupil", V(0.12 * u, 0.12 * u, 0.12 * u), CF(s * 0.22 * u, 0.12 * u, -0.64 * u), Color3.fromRGB(255, 30, 30), M.Neon, BALL)
		end
		add("Grin", V(0.82 * u, 0.14 * u, 0.06 * u), CF(0, -0.22 * u, -0.6 * u), Color3.fromRGB(255, 250, 240), M.Neon)
		for _, x in ipairs({ -0.2, 0, 0.2 }) do
			add("Tooth", V(0.03 * u, 0.14 * u, 0.07 * u), CF(x * u, -0.22 * u, -0.61 * u), Color3.fromRGB(20, 0, 0))
		end
	end,
}

local function gearPart(folder, head, name, size, offset, color, mat, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	if shape then p.Shape = shape end
	p.Color = color
	p.Material = mat or M.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = head.CFrame * offset
	local w = Instance.new("Weld")
	w.Part0 = head
	w.Part1 = p
	w.C0 = offset
	w.Parent = p
	p.Parent = folder
	return p
end

-- внешний вид персонажа: цвет тела + снаряжение (одежда и аксессуары аватара убираются)
local function applyLook(char, c)
	pcall(function()
		local col = charColor(c)
		local body
		if c.id == "binky" then
			body = col:Lerp(BLACK, 0.3)
		elseif c.killer then
			body = Color3.fromRGB(28, 26, 30)
		else
			body = col:Lerp(BLACK, 0.35)
		end
		local old = char:FindFirstChild("P2D_Gear")
		if old then old:Destroy() end
		for _, o in ipairs(char:GetChildren()) do
			if o:IsA("Shirt") or o:IsA("Pants") or o:IsA("ShirtGraphic") or o:IsA("Accoutrement") then
				o:Destroy()
			elseif o:IsA("BasePart") and o.Name ~= "HumanoidRootPart" then
				if o.Name ~= "Head" or c.killer then
					o.Color = body
				end
			end
		end
		local head = char:FindFirstChild("Head")
		if not head then return end
		if c.killer then
			local face = head:FindFirstChildOfClass("Decal")
			if face then face:Destroy() end
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local u = (hum and hum.RigType == Enum.HumanoidRigType.R6) and 1.2 or math.clamp(head.Size.Y, 0.8, 1.8)
		local folder = Instance.new("Model")
		folder.Name = "P2D_Gear"
		local fn = GEAR[c.id]
		if fn then
			fn(function(name, size, offset, color, mat, shape)
				return gearPart(folder, head, name, size, offset, color, mat, shape)
			end, u)
		end
		folder.Parent = char
		char:SetAttribute("CharId", c.id)
	end)
end

------------------------------------------------------------------------
-- КАРТЫ: общие функции
------------------------------------------------------------------------
local MAP_INFO = {
	{ key = "Hills", name = "ХОЛМЫ РАДОСТИ", sub = "ЗОНА 1 · АКТ 1", color = { 90, 190, 90 } },
	{ key = "Arcade", name = "АРКАДА «ПОЛНОЧЬ»", sub = "ЗАЛ ИГРОВЫХ АВТОМАТОВ", color = { 220, 70, 210 } },
	{ key = "Maze", name = "ЛАБИРИНТ 8-БИТ", sub = "УРОВЕНЬ 255", color = { 70, 120, 255 } },
	{ key = "Room", name = "ДЕТСКАЯ 1996", sub = "РЕАЛЬНЫЙ МИР?", color = { 235, 165, 60 } },
}
local MAP_BY_KEY = {}
for _, info in ipairs(MAP_INFO) do MAP_BY_KEY[info.key] = info end
gameState:SetAttribute("Maps", HttpService:JSONEncode(MAP_INFO))

local mapsFolder = Instance.new("Folder")
mapsFolder.Name = "Maps"
mapsFolder.Parent = Workspace

-- динамика карт (жетоны, выходы) — отдельные «постоянные» модели, чтобы клиент видел их при стриминге
local dynamicFolder = Instance.new("Folder")
dynamicFolder.Name = "P2D_Dynamic"
dynamicFolder.Parent = Workspace

local function newMap(info, origin, size, groundColor, groundMat)
	local model = Instance.new("Model")
	model.Name = "Map_" .. info.key
	model.Parent = mapsFolder
	local dyn = Instance.new("Model")
	dyn.Name = "Dyn_" .. info.key
	dyn.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	dyn.Parent = dynamicFolder
	local def = {
		key = info.key, display = info.name, info = info, origin = origin, model = model, dynamic = dyn,
		size = size, survivorSpawns = {}, killerSpawns = {}, escapes = {}, blockers = {}, tokenSpots = {},
		beamH = 120,
	}
	mk(model, "Ground", Vector3.new(size + 8, 4, size + 8), origin + Vector3.new(0, -2, 0), groundColor, groundMat)
	local h = size / 2
	local function border(sz, off)
		mk(model, "Border", sz, origin + off, BLACK, M.SmoothPlastic, { Transparency = 1 })
	end
	border(Vector3.new(size + 8, 160, 4), Vector3.new(0, 80, -(h + 2)))
	border(Vector3.new(size + 8, 160, 4), Vector3.new(0, 80, h + 2))
	border(Vector3.new(4, 160, size + 8), Vector3.new(h + 2, 80, 0))
	border(Vector3.new(4, 160, size + 8), Vector3.new(-(h + 2), 80, 0))
	return def
end

local function reserve(def, x, z, r)
	table.insert(def.blockers, { x = x, z = z, r = r })
end

local function isFree(def, x, z, margin)
	for _, b in ipairs(def.blockers) do
		local dx, dz = b.x - x, b.z - z
		if dx * dx + dz * dz < (b.r + margin) ^ 2 then return false end
	end
	return true
end

local function scatter(def, r, count, half, margin, place, filter)
	local placed, tries = 0, 0
	while placed < count and tries < count * 30 do
		tries += 1
		local x, z = r:NextNumber(-half, half), r:NextNumber(-half, half)
		if isFree(def, x, z, margin) and (not filter or filter(x, z)) then
			placed += 1
			place(x, z)
		end
	end
end

-- точка спавна (невидимый маркер). Несколько игроков могут выбрать одну точку.
local function addSpawn(def, kind, x, z)
	local p = mk(def.model, kind .. "Spawn", Vector3.new(4, 1, 4), def.origin + Vector3.new(x, 0.5, z),
		BLACK, M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false })
	table.insert(kind == "Killer" and def.killerSpawns or def.survivorSpawns, p)
	reserve(def, x, z, 12)
end

local function addTokenSpot(def, x, z, y)
	table.insert(def.tokenSpots, def.origin + Vector3.new(x, y or 0, z))
end

-- точки жетонов на свободной земле
local function scatterTokenSpots(def, r, count, half, filter)
	local spots = {}
	scatter(def, r, count, half, 3, function(x, z)
		table.insert(spots, { x, z })
	end, filter)
	for _, s in ipairs(spots) do
		addTokenSpot(def, s[1], s[2])
		reserve(def, s[1], s[2], 3)
	end
end

-- точка побега: зона + столб света + подпись; декор задаёт style(model, pos). Неактивна, пока не откроется.
local function addEscape(def, x, z, label, style)
	local pos = def.origin + Vector3.new(x, 0, z)
	local m = Instance.new("Model")
	m.Name = "Escape"
	m.Parent = def.dynamic
	if style then style(m, pos) end
	local pad = mk(m, "Pad", Vector3.new(0.5, 12, 12), CFrame.new(pos + Vector3.new(0, 0.25, 0)) * VERT,
		Color3.fromRGB(70, 18, 22), M.Metal, { Shape = CYL, CanCollide = false })
	local zone = mk(m, "EscapeZone", Vector3.new(14, 12, 14), pos + Vector3.new(0, 6, 0),
		Color3.new(1, 0, 0), M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false })
	zone:SetAttribute("Active", false)
	local bh = def.beamH
	local beam = mk(m, "Beam", Vector3.new(bh, 4, 4), CFrame.new(pos + Vector3.new(0, bh / 2, 0)) * VERT,
		GREEN, M.Neon, { Shape = CYL, Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
	local light = pointLight(pad, GREEN, 35, 3)
	light.Enabled = false
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(260, 40)
	bb.StudsOffset = Vector3.new(0, 12, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 1200
	bb.Adornee = zone
	bb.Enabled = false
	bb.Parent = zone
	local txt = Instance.new("TextLabel")
	txt.Size = UDim2.fromScale(1, 1)
	txt.BackgroundTransparency = 1
	txt.Font = Enum.Font.GothamBlack
	txt.TextSize = 20
	txt.TextStrokeTransparency = 0.2
	txt.TextColor3 = GREEN
	txt.Text = "ВЫХОД: " .. label
	txt.Parent = bb
	table.insert(def.escapes, { zone = zone, pad = pad, beam = beam, light = light, gui = bb, label = label })
	reserve(def, x, z, 16)
end

local function setEscapeVisual(e, on)
	e.zone:SetAttribute("Active", on)
	e.pad.Color = on and Color3.fromRGB(60, 230, 110) or Color3.fromRGB(70, 18, 22)
	e.pad.Material = on and M.Neon or M.Metal
	e.beam.Transparency = on and 0.55 or 1
	e.light.Enabled = on
	e.gui.Enabled = on
end

local function resetEscapes(def)
	for _, e in ipairs(def.escapes) do setEscapeVisual(e, false) end
end

-- открывает ОДИН случайный выход, остальные остаются закрытыми
local function openRandomEscape(def)
	resetEscapes(def)
	local e = def.escapes[rng:NextInteger(1, #def.escapes)]
	setEscapeVisual(e, true)
	return e
end

-- деталь по двум углам (удобно для мебели)
local function boxAt(def, name, x1, x2, y1, y2, z1, z2, color, mat, opts)
	return mk(def.model, name, Vector3.new(x2 - x1, y2 - y1, z2 - z1),
		def.origin + Vector3.new((x1 + x2) / 2, (y1 + y2) / 2, (z1 + z2) / 2), color, mat, opts)
end

-- клин-пандус: dir — направление ПОДЪЁМА (к платформе)
local function ramp(def, x, z, w, h, len, dir, color, mat)
	local center = def.origin + Vector3.new(x, h / 2, z)
	return mkc("WedgePart", def.model, "Ramp", Vector3.new(w, h, len), CFrame.lookAt(center, center - dir), color, mat)
end

-- дверь в стене с неоновой табличкой (normal — внутрь карты)
local function exitDoorStyle(normal, sign, doorColor)
	return function(m, pos)
		local center = pos - normal * 6.8 + Vector3.new(0, 5, 0)
		local cf = CFrame.lookAt(center, center + normal)
		mk(m, "Door", Vector3.new(8, 10, 0.4), cf, doorColor or Color3.fromRGB(30, 60, 40), M.Metal)
		for _, sx in ipairs({ -4.2, 4.2 }) do
			mk(m, "DoorFrame", Vector3.new(0.4, 10.6, 0.5), cf * CFrame.new(sx, 0.3, 0), GREEN, M.Neon, NOCOL)
		end
		local s = mk(m, "ExitSign", Vector3.new(7, 1.8, 0.3), cf * CFrame.new(0, 6.6, -0.2), Color3.fromRGB(20, 120, 50), M.Neon, NOCOL)
		surfaceText(s, Enum.NormalId.Front, sign or "ВЫХОД", { color = Color3.fromRGB(230, 255, 230) })
	end
end

------------------------------------------------------------------------
-- КАРТРИДЖ 1: ХОЛМЫ РАДОСТИ (проклятый уровень платформера)
------------------------------------------------------------------------
local CHK_A = Color3.fromRGB(150, 84, 34)
local CHK_B = Color3.fromRGB(92, 48, 22)
local GRASS_TOP = Color3.fromRGB(66, 120, 48)
local GRASS_DARK = Color3.fromRGB(40, 84, 34)

-- плато с шахматными боками и травяной шапкой; возвращает высоту верха
local function checkerBlock(def, cx, cz, w, d, h, y0)
	y0 = y0 or 0
	local o = def.origin
	local m = def.model
	mk(m, "Plateau", Vector3.new(w, h, d), o + Vector3.new(cx, y0 + h / 2, cz), CHK_B, M.SmoothPlastic)
	local T = 4
	local function side(alongX, sign)
		local len = alongX and w or d
		local cols = math.max(1, math.floor(len / T + 0.5))
		local tw = len / cols
		local rows = math.max(1, math.floor(h / T + 0.5))
		local th = h / rows
		for i = 0, cols - 1 do
			for j = 0, rows - 1 do
				if (i + j) % 2 == 0 then
					local along = -len / 2 + (i + 0.5) * tw
					local yy = y0 + (j + 0.5) * th
					if alongX then
						mk(m, "Chk", Vector3.new(tw, th, 0.12), o + Vector3.new(cx + along, yy, cz + sign * (d / 2 + 0.06)), CHK_A, M.SmoothPlastic, FLAT)
					else
						mk(m, "Chk", Vector3.new(0.12, th, tw), o + Vector3.new(cx + sign * (w / 2 + 0.06), yy, cz + along), CHK_A, M.SmoothPlastic, FLAT)
					end
				end
			end
		end
	end
	side(true, 1)
	side(true, -1)
	side(false, 1)
	side(false, -1)
	mk(m, "GrassTop", Vector3.new(w + 0.8, 1.2, d + 0.8), o + Vector3.new(cx, y0 + h + 0.3, cz), GRASS_TOP, M.Grass)
	mk(m, "GrassLip", Vector3.new(w + 1.2, 0.6, d + 1.2), o + Vector3.new(cx, y0 + h - 0.5, cz), GRASS_DARK, M.Grass, FLAT)
	return y0 + h + 0.9
end

-- мёртвая петля: кольцо в вертикальной плоскости, низ открыт — можно пробежать насквозь
local function loopArch(def, cx, cz, R, alongX)
	local N = 30
	local segLen = 2 * math.pi * R / N * 1.08
	local base = CFrame.new(def.origin + Vector3.new(cx, R + 0.6, cz)) * (alongX and CFrame.identity or ALONG_Z)
	for i = 0, N - 1 do
		local th = (i + 0.5) / N * 2 * math.pi
		local deg = math.deg(th)
		if not (deg > 245 and deg < 295) then
			local cf = base * CFrame.new(R * math.cos(th), R * math.sin(th), 0) * CFrame.Angles(0, 0, th + math.pi / 2)
			mk(def.model, "Loop", Vector3.new(segLen, 1.6, 7), cf, i % 2 == 0 and CHK_A or CHK_B, M.SmoothPlastic)
			mk(def.model, "LoopTrack", Vector3.new(segLen, 0.3, 7.4), cf * CFrame.new(0, 0.9, 0), Color3.fromRGB(58, 58, 70), M.Metal, FLAT)
		end
	end
	reserve(def, cx, cz, R + 4)
end

local function palm(def, x, z, r)
	local pos = def.origin + Vector3.new(x, 0, z)
	local leanX, leanZ = r:NextNumber(-0.22, 0.22), r:NextNumber(-0.22, 0.22)
	local segs = r:NextInteger(6, 8)
	local p = pos
	for i = 1, segs do
		local nxt = p + Vector3.new(leanX * 2.6, 2.6, leanZ * 2.6)
		local d = 2.1 - i * 0.09
		local cf = CFrame.new((p + nxt) / 2) * CFrame.Angles(leanZ, 0, -leanX)
		cyl(def.model, "Trunk", 2.9, d, cf, i % 2 == 0 and Color3.fromRGB(104, 74, 46) or Color3.fromRGB(78, 54, 34), M.Wood)
		p = nxt
	end
	for k = 0, 6 do
		local yaw = k / 7 * math.pi * 2 + r:NextNumber(-0.2, 0.2)
		local cf = CFrame.new(p) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(-r:NextNumber(25, 50)), 0, 0) * CFrame.new(0, 0, -4)
		mk(def.model, "Frond", Vector3.new(1.8, 0.25, 8.5), cf, Color3.fromRGB(96, 92, 40):Lerp(Color3.fromRGB(60, 40, 20), r:NextNumber()), M.Grass, NOCOL)
	end
	ball(def.model, "Coconut", 1.3, p + Vector3.new(0.6, -0.8, 0.4), Color3.fromRGB(60, 36, 20), M.Wood, NOCOL)
end

local function totem(def, x, z)
	local o = def.origin
	for i = 0, 2 do
		local c = o + Vector3.new(x, 1.7 + i * 3.4, z)
		mk(def.model, "Totem", Vector3.new(3.4, 3.4, 3.4), c, i % 2 == 0 and Color3.fromRGB(120, 70, 40) or Color3.fromRGB(160, 100, 50), M.Wood)
		for _, s in ipairs({ -1, 1 }) do
			for _, fz in ipairs({ -1, 1 }) do
				mk(def.model, "TotemEye", Vector3.new(0.6, 0.6, 0.1), c + Vector3.new(s * 0.7, 0.5, fz * 1.72), Color3.fromRGB(255, 40, 30), M.Neon, NOCOL)
			end
		end
		for _, fz in ipairs({ -1, 1 }) do
			mk(def.model, "TotemMouth", Vector3.new(1.6, 0.3, 0.1), c + Vector3.new(0, -0.6, fz * 1.72), BLACK, M.SmoothPlastic, NOCOL)
		end
	end
	for _, s in ipairs({ -1, 1 }) do
		mk(def.model, "TotemWing", Vector3.new(2.4, 1.2, 0.4), o + Vector3.new(x + s * 2.8, 8.6, z), Color3.fromRGB(200, 60, 40), M.Wood)
	end
end

-- гигантское кольцо в воздухе (крутится на клиенте)
local function goldRing(def, x, z, y, R)
	local mdl = Instance.new("Model")
	mdl.Name = "GiantRing"
	mdl.Parent = def.model
	local c = def.origin + Vector3.new(x, y, z)
	local N = 16
	for i = 0, N - 1 do
		local th = (i + 0.5) / N * 2 * math.pi
		local cf = CFrame.new(c) * CFrame.new(R * math.cos(th), R * math.sin(th), 0) * CFrame.Angles(0, 0, th + math.pi / 2)
		mk(mdl, "Ring", Vector3.new(2 * math.pi * R / N * 1.1, 0.9, 0.9), cf, GOLD, M.Neon, NOCOL)
	end
	for i = 1, 3 do
		mk(mdl, "Drip", Vector3.new(0.25, 1 + i * 0.8, 0.25), c + Vector3.new(-1.2 + i * 0.7, -R - 0.6 - i * 0.4, 0), BLOOD, M.Neon, NOCOL)
	end
	mdl.WorldPivot = CFrame.new(c)
	tag(mdl, "P2D_SpinModel", { Speed = 0.8 })
	pointLight(mdl:FindFirstChildWhichIsA("BasePart"), GOLD, 18, 1)
end

local function checkpoint(def, x, z)
	local base = def.origin + Vector3.new(x, 0, z)
	cyl(def.model, "Checkpoint", 9, 0.7, base + Vector3.new(0, 4.5, 0), Color3.fromRGB(60, 70, 110), M.Metal)
	local bulb = ball(def.model, "CheckpointBall", 1.8, base + Vector3.new(0, 9.6, 0), Color3.fromRGB(255, 50, 50), M.Neon, NOCOL)
	pointLight(bulb, Color3.fromRGB(255, 70, 60), 34, 1.6)
	tag(bulb, "P2D_Blink", { Rate = 1.2 })
	reserve(def, x, z, 3)
end

local function goalSign(m, pos)
	cyl(m, "GoalPost", 13, 0.8, pos + Vector3.new(-9, 6.5, 0), Color3.fromRGB(150, 150, 160), M.Metal)
	local sign = mk(m, "GoalSign", Vector3.new(6.5, 6.5, 0.5), pos + Vector3.new(-9, 15.5, 0), Color3.fromRGB(245, 205, 60), M.SmoothPlastic)
	surfaceText(sign, Enum.NormalId.Front, "GOAL", { font = Enum.Font.Arcade, color = Color3.fromRGB(150, 20, 20) })
	surfaceText(sign, Enum.NormalId.Back, "P2D", { font = Enum.Font.Arcade, color = Color3.fromRGB(150, 20, 20) })
	tag(sign, "P2D_Spin", { Speed = 2.5 })
end

local function buildHills(origin)
	local def = newMap(MAP_INFO[1], origin, 260, Color3.fromRGB(58, 92, 42), M.Grass)
	local r = Random.new(11)
	for _, p in ipairs({ { -100, -100 }, { -112, -76 }, { -78, -112 }, { -96, -56 }, { -56, -102 } }) do
		addSpawn(def, "Survivor", p[1], p[2])
	end
	for _, p in ipairs({ { 96, 96 }, { 108, 72 }, { 72, 108 } }) do
		addSpawn(def, "Killer", p[1], p[2])
	end
	addEscape(def, 112, -112, "ФИНИШ · АКТ 1", goalSign)
	addEscape(def, -112, 112, "ФИНИШ · СЕКРЕТ", goalSign)
	addEscape(def, 4, 118, "ФИНИШ · АКТ 2", goalSign)

	-- плато {x, z, w, d, h, сторона пандуса}
	local plats = {
		{ -40, -30, 40, 28, 8, "S" },
		{ 44, 20, 36, 30, 8, "W" },
		{ -72, 46, 30, 24, 4, "E" },
		{ 62, -62, 34, 26, 4, "N" },
		{ 0, -86, 28, 20, 8, "N" },
		{ -12, 74, 30, 22, 8, "S" },
	}
	for _, pl in ipairs(plats) do
		local x, z, w, d, h, side = pl[1], pl[2], pl[3], pl[4], pl[5], pl[6]
		local top = checkerBlock(def, x, z, w, d, h)
		local len = top * 2.3
		if side == "S" then
			ramp(def, x, z + d / 2 + len / 2, 10, top, len, Vector3.new(0, 0, -1), GRASS_TOP, M.Grass)
		elseif side == "N" then
			ramp(def, x, z - d / 2 - len / 2, 10, top, len, Vector3.new(0, 0, 1), GRASS_TOP, M.Grass)
		elseif side == "E" then
			ramp(def, x + w / 2 + len / 2, z, 10, top, len, Vector3.new(-1, 0, 0), GRASS_TOP, M.Grass)
		else
			ramp(def, x - w / 2 - len / 2, z, 10, top, len, Vector3.new(1, 0, 0), GRASS_TOP, M.Grass)
		end
		reserve(def, x, z, math.max(w, d) / 2 + 6)
		addTokenSpot(def, x + w * 0.25, z, top)
	end
	local top2 = checkerBlock(def, 48, 24, 16, 14, 4, 8.9) -- второй ярус
	addTokenSpot(def, 48, 24, top2)

	loopArch(def, 0, 0, 14, true)
	loopArch(def, -100, 8, 12, false)
	goldRing(def, 30, -30, 13, 4)
	goldRing(def, -60, -70, 11, 3.5)
	goldRing(def, 90, -10, 12, 4)
	for _, p in ipairs({ { -20, -62 }, { 22, 52 }, { -86, -24 }, { 84, -22 }, { 30, 96 }, { -40, 100 } }) do
		checkpoint(def, p[1], p[2])
	end

	-- табличка у старта
	local post = def.origin + Vector3.new(-80, 0, -80)
	mk(def.model, "SignPost", Vector3.new(0.6, 6, 0.6), post + Vector3.new(0, 3, 0), Color3.fromRGB(90, 60, 36), M.Wood)
	local board = mk(def.model, "SignBoard", Vector3.new(7, 3, 0.4), CFrame.new(post + Vector3.new(0, 6.5, 0)) * CFrame.Angles(0, math.rad(45), 0),
		Color3.fromRGB(120, 84, 50), M.Wood)
	surfaceText(board, Enum.NormalId.Front, "НЕ ОГЛЯДЫВАЙСЯ", { color = Color3.fromRGB(150, 15, 15) })
	surfaceText(board, Enum.NormalId.Back, "ТЫ УЖЕ ПРОИГРАЛ", { color = Color3.fromRGB(150, 15, 15) })
	reserve(def, -80, -80, 4)

	scatter(def, r, 6, 120, 6, function(x, z)
		totem(def, x, z)
		reserve(def, x, z, 4)
	end)
	scatterTokenSpots(def, r, 22, 118)
	scatter(def, r, 34, 122, 5, function(x, z) palm(def, x, z, r) end)
	scatter(def, r, 22, 122, 3, function(x, z)
		local s = r:NextNumber(3, 7)
		mk(def.model, "Rock", Vector3.new(s, s * 0.7, s * 1.2),
			CFrame.new(def.origin + Vector3.new(x, s * 0.2, z)) * CFrame.Angles(r:NextNumber(0, 3), r:NextNumber(0, 6), 0),
			Color3.fromRGB(110, 96, 86), M.Slate)
	end)
	return def
end

------------------------------------------------------------------------
-- КАРТРИДЖ 2: АРКАДА «ПОЛНОЧЬ» (зал игровых автоматов)
------------------------------------------------------------------------
local NEON_SET = {
	Color3.fromRGB(255, 60, 200), Color3.fromRGB(60, 230, 255), Color3.fromRGB(255, 220, 60),
	Color3.fromRGB(90, 255, 120), Color3.fromRGB(170, 90, 255), Color3.fromRGB(255, 130, 40),
}
local SCREEN_TEXT = { "INSERT COIN", "GAME OVER", "PRESS 2 DIE", "1UP", "HI SCORE", "CONTINUE?", "HELP ME", "NO EXIT", "P2D", "YOU DIED", "PLAYER 2?", "DON'T" }

local function arcadeCabinet(def, cf, col, text)
	local m = def.model
	mk(m, "Cabinet", Vector3.new(3, 6.6, 2.8), cf * CFrame.new(0, 3.3, 0), Color3.fromRGB(22, 20, 26), M.SmoothPlastic)
	mk(m, "SideArt", Vector3.new(0.12, 5.6, 2.4), cf * CFrame.new(-1.56, 3.4, 0), col, M.SmoothPlastic, FLAT)
	mk(m, "SideArt", Vector3.new(0.12, 5.6, 2.4), cf * CFrame.new(1.56, 3.4, 0), col, M.SmoothPlastic, FLAT)
	mk(m, "Marquee", Vector3.new(2.8, 0.8, 0.3), cf * CFrame.new(0, 6.2, -1.5), col, M.Neon, FLAT)
	local screen = mk(m, "Screen", Vector3.new(2.3, 1.9, 0.15), cf * CFrame.new(0, 4.7, -1.42) * CFrame.Angles(math.rad(-12), 0, 0),
		col:Lerp(BLACK, 0.75), M.Neon, FLAT)
	surfaceText(screen, Enum.NormalId.Front, text, { font = Enum.Font.Arcade, color = col:Lerp(Color3.new(1, 1, 1), 0.5), pps = 60 })
	tag(screen, "P2D_Flicker")
	mk(m, "Panel", Vector3.new(3, 0.5, 1.3), cf * CFrame.new(0, 3.3, -1.9) * CFrame.Angles(math.rad(10), 0, 0), Color3.fromRGB(40, 38, 44), M.SmoothPlastic)
	ball(m, "Button", 0.42, (cf * CFrame.new(0.5, 3.62, -1.95)).Position, Color3.fromRGB(255, 50, 50), M.Neon, FLAT)
	ball(m, "Button", 0.42, (cf * CFrame.new(0.95, 3.62, -1.85)).Position, Color3.fromRGB(60, 140, 255), M.Neon, FLAT)
	cyl(m, "Stick", 0.7, 0.14, cf * CFrame.new(-0.6, 3.85, -1.9), Color3.fromRGB(30, 30, 30), M.Metal, FLAT)
end

local function clawMachine(def, x, z, r)
	local o = def.origin + Vector3.new(x, 0, z)
	local m = def.model
	mk(m, "ClawBase", Vector3.new(5, 3, 5), o + Vector3.new(0, 1.5, 0), Color3.fromRGB(200, 40, 140), M.SmoothPlastic)
	mk(m, "ClawGlass", Vector3.new(4.6, 5.6, 4.6), o + Vector3.new(0, 5.8, 0), Color3.fromRGB(180, 220, 255), M.Glass, { Transparency = 0.75 })
	mk(m, "ClawTop", Vector3.new(5, 1, 5), o + Vector3.new(0, 9.1, 0), Color3.fromRGB(200, 40, 140), M.SmoothPlastic)
	for _, s in ipairs({ { -2.4, -2.4 }, { 2.4, -2.4 }, { -2.4, 2.4 }, { 2.4, 2.4 } }) do
		mk(m, "ClawPost", Vector3.new(0.3, 5.6, 0.3), o + Vector3.new(s[1], 5.8, s[2]), NEON_SET[1], M.Neon, FLAT)
	end
	for _ = 1, 6 do
		ball(m, "Plush", r:NextNumber(0.9, 1.4), o + Vector3.new(r:NextNumber(-1.6, 1.6), 3.7, r:NextNumber(-1.6, 1.6)),
			NEON_SET[r:NextInteger(1, #NEON_SET)]:Lerp(Color3.new(1, 1, 1), 0.3), M.Fabric, FLAT)
	end
	cyl(m, "ClawWire", 2.2, 0.1, o + Vector3.new(0.6, 7.4, 0.3), Color3.fromRGB(180, 180, 190), M.Metal, FLAT)
	ball(m, "Claw", 0.6, o + Vector3.new(0.6, 6.2, 0.3), Color3.fromRGB(200, 200, 210), M.Metal, FLAT)
	reserve(def, x, z, 5)
end

local function buildArcade(origin)
	local def = newMap(MAP_INFO[2], origin, 260, Color3.fromRGB(26, 20, 40), M.Fabric)
	def.beamH = 21
	local r = Random.new(42)
	local o = origin
	local m = def.model
	local H = 22

	-- ковёр с «конфетти»
	for _ = 1, 170 do
		local x, z = r:NextNumber(-126, 126), r:NextNumber(-126, 126)
		local s = r:NextNumber(0.8, 2.2)
		mk(m, "Confetti", Vector3.new(s, 0.06, s * r:NextNumber(0.3, 1)),
			CFrame.new(o + Vector3.new(x, 0.03, z)) * CFrame.Angles(0, r:NextNumber(0, 6.28), 0),
			NEON_SET[r:NextInteger(1, #NEON_SET)]:Lerp(BLACK, 0.35), M.SmoothPlastic, FLAT)
	end
	-- стены здания, плинтус-неон и потолок
	local wallC = Color3.fromRGB(36, 28, 52)
	for _, s in ipairs({ -1, 1 }) do
		mk(m, "OuterWall", Vector3.new(264, H, 2), o + Vector3.new(0, H / 2, s * 131), wallC, M.SmoothPlastic)
		mk(m, "OuterWall", Vector3.new(2, H, 264), o + Vector3.new(s * 131, H / 2, 0), wallC, M.SmoothPlastic)
		mk(m, "WallNeon", Vector3.new(262, 0.4, 0.3), o + Vector3.new(0, 2, s * 129.9), NEON_SET[1], M.Neon, FLAT)
		mk(m, "WallNeon", Vector3.new(0.3, 0.4, 262), o + Vector3.new(s * 129.9, 2, 0), NEON_SET[2], M.Neon, FLAT)
	end
	mk(m, "Ceiling", Vector3.new(264, 1, 264), o + Vector3.new(0, H + 0.5, 0), Color3.fromRGB(14, 10, 20), M.SmoothPlastic)
	for i, z in ipairs({ -72, -36, 0, 36, 72 }) do
		local strip = mk(m, "CeilingNeon", Vector3.new(130, 0.4, 0.8), o + Vector3.new(-6, H - 0.2, z), NEON_SET[i % 2 == 0 and 1 or 2], M.Neon, FLAT)
		local sl = Instance.new("SurfaceLight")
		sl.Face = Enum.NormalId.Bottom
		sl.Range = 18
		sl.Brightness = 1.3
		sl.Angle = 120
		sl.Color = strip.Color
		sl.Parent = strip
		tag(strip, "P2D_Flicker")
	end

	addEscape(def, 0, -122, "ГЛАВНЫЙ ВХОД", exitDoorStyle(Vector3.new(0, 0, 1)))
	addEscape(def, -122, 110, "ЗАПАСНОЙ ВЫХОД", exitDoorStyle(Vector3.new(1, 0, 0)))
	addEscape(def, 122, 30, "ЧЁРНЫЙ ХОД", exitDoorStyle(Vector3.new(-1, 0, 0)))

	for _, p in ipairs({ { -100, -112 }, { -80, -116 }, { -60, -112 }, { -40, -116 }, { -112, -94 } }) do
		addSpawn(def, "Survivor", p[1], p[2])
	end
	for _, p in ipairs({ { 100, -96 }, { 104, -30 }, { 100, 78 } }) do
		addSpawn(def, "Killer", p[1], p[2])
	end

	-- ряды автоматов спиной к спине; проходы между группами
	local n = 0
	for _, rz in ipairs({ -54, -18, 18, 54 }) do
		for _, gx in ipairs({ -66, -36, -6, 24 }) do
			for g = 0, 2 do
				local cx = gx + g * 3.2
				n += 1
				local col = NEON_SET[(n % #NEON_SET) + 1]
				arcadeCabinet(def, CFrame.new(o + Vector3.new(cx, 0, rz - 1.5)), col, SCREEN_TEXT[(n % #SCREEN_TEXT) + 1])
				arcadeCabinet(def, CFrame.new(o + Vector3.new(cx, 0, rz + 1.5)) * CFrame.Angles(0, math.pi, 0),
					NEON_SET[((n + 3) % #NEON_SET) + 1], SCREEN_TEXT[((n + 5) % #SCREEN_TEXT) + 1])
			end
			reserve(def, gx + 3.2, rz, 9)
		end
	end

	-- автоматы с игрушками вдоль западной стены
	for _, z in ipairs({ -70, -40, -10, 20 }) do
		clawMachine(def, -108, z, r)
	end
	-- танцевальный автомат
	do
		local c = o + Vector3.new(-100, 0, 60)
		mk(m, "DancePad", Vector3.new(10, 0.6, 10), c + Vector3.new(0, 0.3, 0), Color3.fromRGB(30, 30, 36), M.SmoothPlastic)
		for i, d in ipairs({ { -2.6, 0 }, { 2.6, 0 }, { 0, -2.6 }, { 0, 2.6 } }) do
			local a = mk(m, "Arrow", Vector3.new(2.2, 0.15, 2.2), c + Vector3.new(d[1], 0.65, d[2]), NEON_SET[i], M.Neon, FLAT)
			tag(a, "P2D_Blink", { Rate = 2 + i * 0.3 })
		end
		mk(m, "DanceScreen", Vector3.new(10, 9, 2), c + Vector3.new(0, 4.5, 6), Color3.fromRGB(22, 20, 26), M.SmoothPlastic)
		local s = mk(m, "DanceDisplay", Vector3.new(8, 4.5, 0.2), c + Vector3.new(0, 6, 4.9), Color3.fromRGB(40, 20, 60), M.Neon, FLAT)
		surfaceText(s, Enum.NormalId.Front, "DANCE\nOR DIE", { font = Enum.Font.Arcade, color = NEON_SET[1] })
		reserve(def, -100, 60, 9)
	end
	-- аэрохоккей
	for _, z in ipairs({ 92, 112 }) do
		local c = o + Vector3.new(-96, 0, z)
		mk(m, "Hockey", Vector3.new(12, 3, 6), c + Vector3.new(0, 1.5, 0), Color3.fromRGB(230, 230, 240), M.SmoothPlastic)
		mk(m, "HockeyRim", Vector3.new(12.4, 0.4, 6.4), c + Vector3.new(0, 3.1, 0), NEON_SET[2], M.Neon, FLAT)
		reserve(def, -96, z, 7)
	end

	-- стойка призов на севере
	mk(m, "Counter", Vector3.new(60, 3.6, 4), o + Vector3.new(-10, 1.8, 100), Color3.fromRGB(70, 30, 90), M.SmoothPlastic)
	mk(m, "CounterGlass", Vector3.new(60, 0.3, 4), o + Vector3.new(-10, 3.75, 100), Color3.fromRGB(180, 220, 255), M.Glass, { Transparency = 0.5 })
	mk(m, "PrizeWall", Vector3.new(60, 14, 2), o + Vector3.new(-10, 7, 124), Color3.fromRGB(46, 22, 60), M.SmoothPlastic)
	for row = 0, 2 do
		mk(m, "Shelf", Vector3.new(60, 0.5, 3), o + Vector3.new(-10, 3 + row * 4, 121.8), Color3.fromRGB(120, 90, 60), M.Wood)
		for k = 0, 11 do
			ball(m, "Plush", r:NextNumber(1.4, 2.2), o + Vector3.new(-37 + k * 5 + r:NextNumber(-1, 1), 4.3 + row * 4, 121.6),
				NEON_SET[r:NextInteger(1, #NEON_SET)]:Lerp(Color3.new(1, 1, 1), 0.25), M.Fabric, FLAT)
		end
	end
	local prize = mk(m, "PrizeSign", Vector3.new(24, 3, 0.4), o + Vector3.new(-10, 16, 122.6), Color3.fromRGB(40, 10, 50), M.Neon, FLAT)
	surfaceText(prize, Enum.NormalId.Front, "ПРИЗЫ ДЛЯ ВЫЖИВШИХ", { color = NEON_SET[3] })
	reserve(def, -10, 100, 8)
	for x = -38, 18, 14 do reserve(def, x, 100, 6) end

	-- служебные комнаты на востоке
	room(m, o + Vector3.new(102, 0, -96), 40, 30, 12, Color3.fromRGB(60, 56, 70), M.Concrete, { W = true, N = true }, 9, Color3.fromRGB(190, 220, 255))
	room(m, o + Vector3.new(104, 0, -30), 36, 50, 12, Color3.fromRGB(70, 60, 50), M.Concrete, { W = true }, 9)
	room(m, o + Vector3.new(102, 0, 80), 40, 36, 12, Color3.fromRGB(70, 90, 96), M.Concrete, { W = true, S = true }, 9, Color3.fromRGB(200, 255, 230))
	reserve(def, 102, -96, 24)
	reserve(def, 104, -30, 30)
	reserve(def, 102, 80, 26)
	-- склад: ящики
	for _ = 1, 8 do
		local s = r:NextNumber(3.5, 5)
		mk(m, "Crate", Vector3.new(s, s, s), CFrame.new(o + Vector3.new(r:NextNumber(92, 118), s / 2, r:NextNumber(-50, -10))) * CFrame.Angles(0, r:NextNumber(0, 6), 0),
			Color3.fromRGB(120, 90, 55), M.Wood)
	end
	-- охрана: стол с мониторами
	mk(m, "Desk", Vector3.new(12, 3, 4), o + Vector3.new(108, 1.5, -104), Color3.fromRGB(60, 50, 40), M.Wood)
	for i = -1, 1 do
		mk(m, "SecurityMonitor", Vector3.new(3, 2.4, 2.4), o + Vector3.new(108 + i * 3.6, 4.2, -104.5), Color3.fromRGB(30, 30, 34), M.SmoothPlastic)
		local scr = mk(m, "SecurityScreen", Vector3.new(2.5, 1.9, 0.1), o + Vector3.new(108 + i * 3.6, 4.2, -103.25), Color3.fromRGB(160, 200, 180), M.Neon, FLAT)
		tag(scr, "P2D_Flicker", { Strong = true })
		surfaceText(scr, Enum.NormalId.Back, i == 0 and "REC" or "CAM " .. (i + 2), { font = Enum.Font.Arcade, color = Color3.fromRGB(20, 40, 30), pps = 60 })
	end
	-- туалет: кабинки
	for i = 0, 3 do
		mk(m, "Stall", Vector3.new(0.4, 7, 7), o + Vector3.new(96 + i * 6, 3.5, 92), Color3.fromRGB(120, 140, 150), M.SmoothPlastic)
	end

	-- касса у входа
	room(m, o + Vector3.new(-40, 0, -92), 14, 10, 9, Color3.fromRGB(80, 30, 60), M.SmoothPlastic, { N = true }, 6, NEON_SET[1])
	reserve(def, -40, -92, 10)

	-- жетоны: проходы, служебки, углы
	for _, z in ipairs({ -72, -36, 0, 36, 72 }) do
		for _, x in ipairs({ -50, -20, 10, 40 }) do
			addTokenSpot(def, x + r:NextNumber(-6, 6), z)
		end
	end
	for _, p in ipairs({ { 96, -88 }, { 110, -18 }, { 96, -42 }, { 90, 76 }, { 112, 86 }, { -88, -58 }, { -88, 34 },
		{ -20, 86 }, { 30, 88 }, { -86, -104 }, { 60, -104 }, { 70, 110 } }) do
		addTokenSpot(def, p[1], p[2])
	end
	return def
end

------------------------------------------------------------------------
-- КАРТРИДЖ 3: ЛАБИРИНТ 8-БИТ (стены перестраиваются каждый матч)
------------------------------------------------------------------------
local MAZE_N, MAZE_C, MAZE_H = 13, 18, 11
local MAZE_WALL = Color3.fromRGB(18, 22, 70)
local MAZE_NEON = Color3.fromRGB(60, 110, 255)

local function mazeCell(i, j)
	return Vector3.new((i - (MAZE_N + 1) / 2) * MAZE_C, 0, (j - (MAZE_N + 1) / 2) * MAZE_C)
end

local function genMaze(seed)
	local r = Random.new(seed)
	local N = MAZE_N
	local east, south, seen = {}, {}, {}
	for i = 1, N do
		east[i], south[i], seen[i] = {}, {}, {}
		for j = 1, N do
			east[i][j] = i < N
			south[i][j] = j < N
			seen[i][j] = false
		end
	end
	-- центральная «клетка» 3x3 — логово Палача
	local c0, c1 = (N + 1) / 2 - 1, (N + 1) / 2 + 1
	local stack = {}
	for i = c0, c1 do
		for j = c0, c1 do
			seen[i][j] = true
			if i < c1 then east[i][j] = false end
			if j < c1 then south[i][j] = false end
			table.insert(stack, { i, j })
		end
	end
	for k = #stack, 2, -1 do
		local q = r:NextInteger(1, k)
		stack[k], stack[q] = stack[q], stack[k]
	end
	-- обход в глубину
	while #stack > 0 do
		local top = stack[#stack]
		local i, j = top[1], top[2]
		local nb = {}
		if i > 1 and not seen[i - 1][j] then table.insert(nb, { i - 1, j, "W" }) end
		if i < N and not seen[i + 1][j] then table.insert(nb, { i + 1, j, "E" }) end
		if j > 1 and not seen[i][j - 1] then table.insert(nb, { i, j - 1, "N" }) end
		if j < N and not seen[i][j + 1] then table.insert(nb, { i, j + 1, "S" }) end
		if #nb == 0 then
			table.remove(stack)
		else
			local n = nb[r:NextInteger(1, #nb)]
			if n[3] == "W" then
				east[i - 1][j] = false
			elseif n[3] == "E" then
				east[i][j] = false
			elseif n[3] == "N" then
				south[i][j - 1] = false
			else
				south[i][j] = false
			end
			seen[n[1]][n[2]] = true
			table.insert(stack, { n[1], n[2] })
		end
	end
	-- петли для погонь: убираем часть оставшихся стен
	for i = 1, N do
		for j = 1, N do
			if east[i][j] and r:NextNumber() < 0.3 then east[i][j] = false end
			if south[i][j] and r:NextNumber() < 0.3 then south[i][j] = false end
		end
	end
	return east, south
end

local function ghostStatue(def, pos, col)
	local m = def.model
	cyl(m, "GhostBody", 5, 6, pos + Vector3.new(0, 3.2, 0), col, M.SmoothPlastic)
	local head = ball(m, "GhostHead", 6, pos + Vector3.new(0, 5.7, 0), col, M.SmoothPlastic)
	for k = 0, 3 do
		local a = k / 4 * math.pi * 2 + math.pi / 4
		ball(m, "GhostSkirt", 1.8, pos + Vector3.new(math.cos(a) * 2.4, 0.7, math.sin(a) * 2.4), col, M.SmoothPlastic)
	end
	for _, s in ipairs({ -1, 1 }) do
		ball(m, "GhostEye", 1.8, pos + Vector3.new(s * 1.1, 6.2, -2.3), Color3.fromRGB(240, 240, 255), M.SmoothPlastic, NOCOL)
		ball(m, "GhostPupil", 0.9, pos + Vector3.new(s * 1.1, 6.0, -3.1), Color3.fromRGB(30, 50, 200), M.Neon, NOCOL)
	end
	pointLight(head, col, 22, 1.6)
end

local function warpStyle(normal)
	return function(m, pos)
		local tangent = Vector3.new(normal.Z, 0, -normal.X)
		for _, s in ipairs({ -1, 1 }) do
			mk(m, "WarpPillar", Vector3.new(1.6, 13, 1.6), pos + tangent * (s * 7) + Vector3.new(0, 6.5, 0), GREEN, M.Neon)
		end
		local cf = CFrame.lookAt(pos + Vector3.new(0, 13.8, 0), pos + Vector3.new(0, 13.8, 0) + normal)
		local bar = mk(m, "WarpBar", Vector3.new(15.6, 2.4, 1.6), cf, Color3.fromRGB(10, 40, 20), M.SmoothPlastic)
		surfaceText(bar, Enum.NormalId.Front, "WARP", { font = Enum.Font.Arcade, color = GREEN })
	end
end

local function buildMaze(origin)
	local def = newMap(MAP_INFO[3], origin, 260, Color3.fromRGB(6, 6, 12), M.SmoothPlastic)
	local o = origin
	local m = def.model
	local half = MAZE_N * MAZE_C / 2
	local mid = (MAZE_N + 1) / 2

	-- сетка на полу
	for k = 0, MAZE_N do
		local v = -half + k * MAZE_C
		mk(m, "Grid", Vector3.new(0.3, 0.05, 2 * half), o + Vector3.new(v, 0.03, 0), Color3.fromRGB(20, 26, 70), M.Neon, FLAT)
		mk(m, "Grid", Vector3.new(2 * half, 0.05, 0.3), o + Vector3.new(0, 0.03, v), Color3.fromRGB(20, 26, 70), M.Neon, FLAT)
	end
	-- внешний контур с проходами по центру каждой стороны (там «варпы»)
	local function wallPiece(parent, localPos, alongX)
		local L = MAZE_C + 2
		local size = alongX and Vector3.new(L, MAZE_H, 2) or Vector3.new(2, MAZE_H, L)
		mk(parent, "Wall", size, o + localPos + Vector3.new(0, MAZE_H / 2, 0), MAZE_WALL, M.SmoothPlastic)
		local cap = alongX and Vector3.new(L, 0.5, 2.3) or Vector3.new(2.3, 0.5, L)
		mk(parent, "WallCap", cap, o + localPos + Vector3.new(0, MAZE_H + 0.25, 0), MAZE_NEON, M.Neon, FLAT)
	end
	for i = 1, MAZE_N do
		if i ~= mid then
			local c = mazeCell(i, 1)
			wallPiece(m, Vector3.new(c.X, 0, -half), true)
			wallPiece(m, Vector3.new(c.X, 0, half), true)
			wallPiece(m, Vector3.new(-half, 0, c.X), false)
			wallPiece(m, Vector3.new(half, 0, c.X), false)
		end
	end
	-- граница внешнего кольца
	for _, s in ipairs({ -1, 1 }) do
		mk(m, "RimNeon", Vector3.new(262, 0.4, 0.4), o + Vector3.new(0, 0.2, s * 130), Color3.fromRGB(255, 60, 200), M.Neon, FLAT)
		mk(m, "RimNeon", Vector3.new(0.4, 0.4, 262), o + Vector3.new(s * 130, 0.2, 0), Color3.fromRGB(255, 60, 200), M.Neon, FLAT)
	end

	-- логово Палача в центре
	local c = mazeCell(mid, mid)
	mk(m, "LairFloor", Vector3.new(MAZE_C * 3 - 2, 0.1, MAZE_C * 3 - 2), o + c + Vector3.new(0, 0.06, 0), Color3.fromRGB(40, 10, 40), M.SmoothPlastic, FLAT)
	for _, s in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		local p = mk(m, "LairPost", Vector3.new(1.4, 6, 1.4), o + c + Vector3.new(s[1] * 25, 3, s[2] * 25), Color3.fromRGB(255, 80, 200), M.Neon)
		pointLight(p, Color3.fromRGB(255, 60, 200), 22, 1.2)
	end

	-- точки и статуи-призраки (ориентиры)
	local statueCells = { { 3, 3, Color3.fromRGB(255, 40, 40) }, { MAZE_N - 2, 3, Color3.fromRGB(255, 150, 220) },
		{ 3, MAZE_N - 2, Color3.fromRGB(60, 230, 255) }, { MAZE_N - 2, MAZE_N - 2, Color3.fromRGB(255, 170, 50) } }
	local skip = {}
	for _, s in ipairs(statueCells) do
		ghostStatue(def, o + mazeCell(s[1], s[2]), s[3])
		skip[s[1] .. ":" .. s[2]] = true
	end
	for i = 1, MAZE_N do
		for j = 1, MAZE_N do
			local p = mazeCell(i, j)
			local inLair = math.abs(i - mid) <= 1 and math.abs(j - mid) <= 1
			local corner = (i == 1 or i == MAZE_N) and (j == 1 or j == MAZE_N)
			if not skip[i .. ":" .. j] and not inLair then
				ball(m, "Pellet", 0.8, o + p + Vector3.new(0, 0.7, 0), Color3.fromRGB(255, 230, 200), M.Neon, NOCOL)
				if not corner then addTokenSpot(def, p.X + 4, p.Z + 4) end
			end
		end
	end

	-- спавны: выжившие по углам, Палач в логове
	for _, ij in ipairs({ { 1, 1 }, { MAZE_N, 1 }, { 1, MAZE_N }, { MAZE_N, MAZE_N } }) do
		local p = mazeCell(ij[1], ij[2])
		addSpawn(def, "Survivor", p.X, p.Z)
	end
	for _, d in ipairs({ { 0, 0 }, { -10, 0 }, { 10, 0 } }) do
		addSpawn(def, "Killer", c.X + d[1], c.Z + d[2])
	end
	addEscape(def, 0, -124, "ВАРП · СЕВЕР", warpStyle(Vector3.new(0, 0, 1)))
	addEscape(def, 0, 124, "ВАРП · ЮГ", warpStyle(Vector3.new(0, 0, -1)))
	addEscape(def, -124, 0, "ВАРП · ЗАПАД", warpStyle(Vector3.new(1, 0, 0)))
	addEscape(def, 124, 0, "ВАРП · ВОСТОК", warpStyle(Vector3.new(-1, 0, 0)))

	-- внутренние стены строятся перед каждым матчем
	local wallsModel = nil
	def.prepare = function(seed)
		if wallsModel then wallsModel:Destroy() end
		wallsModel = Instance.new("Model")
		wallsModel.Name = "MazeWalls"
		wallsModel.Parent = m
		local east, south = genMaze(seed)
		for i = 1, MAZE_N do
			for j = 1, MAZE_N do
				local p = mazeCell(i, j)
				if east[i][j] then wallPiece(wallsModel, p + Vector3.new(MAZE_C / 2, 0, 0), false) end
				if south[i][j] then wallPiece(wallsModel, p + Vector3.new(0, 0, MAZE_C / 2), true) end
			end
		end
	end
	def.prepare(12345)
	return def
end

------------------------------------------------------------------------
-- КАРТРИДЖ 4: ДЕТСКАЯ 1996 (выжившие крошечные, мебель гигантская)
------------------------------------------------------------------------
local function toyBlock(def, x, z, s, letter, col, yaw)
	local p = mk(def.model, "ToyBlock", Vector3.new(s, s, s), CFrame.new(def.origin + Vector3.new(x, s / 2, z)) * CFrame.Angles(0, yaw or 0, 0), col, M.Wood)
	for _, f in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right, Enum.NormalId.Top }) do
		surfaceText(p, f, letter, { color = Color3.new(1, 1, 1), stroke = 0.4 })
	end
	reserve(def, x, z, s * 0.8)
end

local function bookStack(def, x, z, n, r)
	local y = 0
	for i = 1, n do
		local h = r:NextNumber(3, 4.5)
		local col = NEON_SET[r:NextInteger(1, #NEON_SET)]:Lerp(BLACK, 0.45)
		mk(def.model, "Book", Vector3.new(24 - i * 1.5, h, 18 - i),
			CFrame.new(def.origin + Vector3.new(x, y + h / 2, z)) * CFrame.Angles(0, r:NextNumber(-0.3, 0.3), 0), col, M.SmoothPlastic)
		y += h
	end
	reserve(def, x, z, 14)
	return y
end

local function cableLine(def, pts, y, d, col)
	for i = 1, #pts - 1 do
		local a = def.origin + Vector3.new(pts[i][1], y, pts[i][2])
		local b = def.origin + Vector3.new(pts[i + 1][1], y, pts[i + 1][2])
		local mid = (a + b) / 2
		local cf = CFrame.lookAt(mid, b) * CFrame.Angles(0, math.rad(90), 0)
		mk(def.model, "Cable", Vector3.new((b - a).Magnitude + d, d, d), cf, col, M.SmoothPlastic, { Shape = CYL })
		ball(def.model, "CableJoint", d, b, col, M.SmoothPlastic)
	end
end

local function holeStyle(normal, kind)
	return function(m, pos)
		local wallC = pos - normal * 7.6
		local cf = CFrame.lookAt(wallC, wallC + normal)
		if kind == "door" then
			local gap = mk(m, "DoorGapLight", Vector3.new(34, 1.4, 0.4), cf * CFrame.new(0, 0.7, 0), Color3.fromRGB(255, 210, 140), M.Neon, NOCOL)
			local sl = Instance.new("SurfaceLight")
			sl.Face = Enum.NormalId.Front
			sl.Range = 30
			sl.Brightness = 2
			sl.Color = Color3.fromRGB(255, 200, 130)
			sl.Parent = gap
		elseif kind == "hole" then
			mk(m, "MouseHole", Vector3.new(8, 7, 0.3), cf * CFrame.new(0, 3.5, 0), Color3.fromRGB(4, 3, 3), M.SmoothPlastic, NOCOL)
			cyl(m, "MouseHoleTop", 0.3, 8, cf * CFrame.new(0, 7, 0) * ALONG_Z * VERT:Inverse(), Color3.fromRGB(4, 3, 3), M.SmoothPlastic, NOCOL)
		else
			mk(m, "Vent", Vector3.new(14, 10, 0.3), cf * CFrame.new(0, 6, 0), Color3.fromRGB(150, 150, 160), M.Metal, NOCOL)
			for k = -2, 2 do
				mk(m, "VentSlat", Vector3.new(12, 0.6, 0.5), cf * CFrame.new(0, 6 + k * 1.8, -0.2), Color3.fromRGB(30, 30, 34), M.Metal, NOCOL)
			end
		end
	end
end

local function buildRoom(origin)
	local def = newMap(MAP_INFO[4], origin, 260, Color3.fromRGB(120, 82, 52), M.WoodPlanks)
	local r = Random.new(96)
	local o = origin
	local m = def.model
	local WH = 110

	-- обои в полоску, плинтус
	local wallC = Color3.fromRGB(64, 74, 108)
	local stripeC = Color3.fromRGB(78, 90, 128)
	for _, s in ipairs({ -1, 1 }) do
		mk(m, "Wallpaper", Vector3.new(264, WH, 2), o + Vector3.new(0, WH / 2, s * 131), wallC, M.SmoothPlastic)
		mk(m, "Wallpaper", Vector3.new(2, WH, 264), o + Vector3.new(s * 131, WH / 2, 0), wallC, M.SmoothPlastic)
		mk(m, "Baseboard", Vector3.new(262, 4, 0.6), o + Vector3.new(0, 2, s * 129.7), Color3.fromRGB(210, 200, 180), M.Wood)
		mk(m, "Baseboard", Vector3.new(0.6, 4, 262), o + Vector3.new(s * 129.7, 2, 0), Color3.fromRGB(210, 200, 180), M.Wood)
		for k = -10, 10 do
			mk(m, "Stripe", Vector3.new(4, WH - 4, 0.2), o + Vector3.new(k * 12, WH / 2 + 2, s * 129.9), stripeC, M.SmoothPlastic, FLAT)
			mk(m, "Stripe", Vector3.new(0.2, WH - 4, 4), o + Vector3.new(s * 129.9, WH / 2 + 2, k * 12), stripeC, M.SmoothPlastic, FLAT)
		end
	end

	-- ковёр-автотрек
	mk(m, "Rug", Vector3.new(150, 0.3, 110), o + Vector3.new(0, 0.15, -10), Color3.fromRGB(50, 110, 60), M.Fabric)
	local roadC = Color3.fromRGB(70, 70, 78)
	for _, s in ipairs({ -1, 1 }) do
		mk(m, "Road", Vector3.new(120, 0.1, 10), o + Vector3.new(0, 0.35, -10 + s * 40), roadC, M.Fabric, FLAT)
		mk(m, "Road", Vector3.new(10, 0.1, 90), o + Vector3.new(s * 55, 0.35, -10), roadC, M.Fabric, FLAT)
	end
	mk(m, "Road", Vector3.new(10, 0.1, 80), o + Vector3.new(0, 0.36, -10), roadC, M.Fabric, FLAT)
	for k = -5, 5 do
		mk(m, "RoadLine", Vector3.new(4, 0.05, 0.6), o + Vector3.new(k * 10, 0.42, -50), Color3.fromRGB(240, 240, 230), M.SmoothPlastic, FLAT)
		mk(m, "RoadLine", Vector3.new(4, 0.05, 0.6), o + Vector3.new(k * 10, 0.42, 30), Color3.fromRGB(240, 240, 230), M.SmoothPlastic, FLAT)
	end

	-- кровать (северо-запад): под ней можно спрятаться
	local bedC = Color3.fromRGB(110, 70, 50)
	for _, p in ipairs({ { -125, -125 }, { -62, -125 }, { -125, -31 }, { -62, -31 } }) do
		boxAt(def, "BedLeg", p[1] - 3, p[1] + 3, 0, 24, p[2] - 3, p[2] + 3, bedC, M.Wood)
	end
	boxAt(def, "BedFrame", -128, -58, 20, 24, -128, -28, bedC, M.Wood)
	boxAt(def, "Mattress", -127, -59, 24, 36, -127, -29, Color3.fromRGB(230, 230, 240), M.Fabric)
	boxAt(def, "Blanket", -128, -57, 36, 38, -100, -27, Color3.fromRGB(150, 40, 60), M.Fabric)
	boxAt(def, "BlanketDrape", -57.5, -55.5, 12, 38, -98, -36, Color3.fromRGB(150, 40, 60), M.Fabric)
	boxAt(def, "Pillow", -122, -66, 36, 44, -124, -106, Color3.fromRGB(240, 240, 250), M.Fabric)
	boxAt(def, "Headboard", -128, -58, 0, 56, -131, -127, bedC, M.Wood)
	for _ = 1, 6 do
		ball(m, "DustBunny", r:NextNumber(2.5, 4.5), o + Vector3.new(r:NextNumber(-118, -70), 1.6, r:NextNumber(-118, -40)), Color3.fromRGB(150, 150, 150), M.Fabric, NOCOL)
	end
	reserve(def, -93, -78, 52)

	-- письменный стол (северо-восток)
	local deskC = Color3.fromRGB(150, 110, 70)
	for _, p in ipairs({ { 63, -123 }, { 63, -89 } }) do
		boxAt(def, "DeskLeg", p[1] - 2.5, p[1] + 2.5, 0, 40, p[2] - 2.5, p[2] + 2.5, deskC, M.Wood)
	end
	boxAt(def, "Drawers", 104, 126, 0, 40, -126, -86, deskC:Lerp(BLACK, 0.15), M.Wood)
	boxAt(def, "Desktop", 60, 127, 40, 43, -127, -85, deskC, M.Wood)
	boxAt(def, "LampBase", 80, 92, 43, 45, -120, -108, Color3.fromRGB(40, 40, 46), M.Metal)
	boxAt(def, "LampArm", 85, 87, 45, 75, -116, -114, Color3.fromRGB(40, 40, 46), M.Metal)
	boxAt(def, "LampHead", 80, 92, 72, 78, -116, -102, Color3.fromRGB(40, 40, 46), M.Metal)
	local bulb = boxAt(def, "LampBulb", 82, 90, 71, 72, -112, -104, Color3.fromRGB(255, 220, 160), M.Neon, NOCOL)
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Bottom
	spot.Range = 60
	spot.Angle = 70
	spot.Brightness = 3
	spot.Color = Color3.fromRGB(255, 210, 150)
	spot.Parent = bulb
	-- стул
	for _, p in ipairs({ { 70, -78 }, { 92, -78 }, { 70, -56 }, { 92, -56 } }) do
		boxAt(def, "ChairLeg", p[1] - 1.5, p[1] + 1.5, 0, 22, p[2] - 1.5, p[2] + 1.5, Color3.fromRGB(60, 60, 70), M.Metal)
	end
	boxAt(def, "ChairSeat", 67, 95, 22, 25, -81, -53, Color3.fromRGB(200, 50, 50), M.SmoothPlastic)
	boxAt(def, "ChairBack", 67, 95, 25, 55, -55, -52, Color3.fromRGB(200, 50, 50), M.SmoothPlastic)
	cyl(m, "TrashBin", 18, 16, o + Vector3.new(74, 9, -108), Color3.fromRGB(80, 90, 100), M.Metal)
	for _ = 1, 5 do
		ball(m, "PaperBall", r:NextNumber(4, 6), o + Vector3.new(r:NextNumber(50, 100), 2.5, r:NextNumber(-80, -40)), Color3.fromRGB(235, 235, 225), M.Fabric)
	end
	-- карандаш
	cyl(m, "Pencil", 46, 3, CFrame.new(o + Vector3.new(26, 1.5, -100)) * CFrame.Angles(0, math.rad(20), 0) * VERT:Inverse(), Color3.fromRGB(250, 200, 40), M.SmoothPlastic)
	reserve(def, 92, -105, 26)
	reserve(def, 81, -66, 16)
	reserve(def, 26, -100, 24)

	-- тумба с ЭЛТ-телевизором (юг)
	local standC = Color3.fromRGB(70, 50, 40)
	boxAt(def, "StandTop", -30, 30, 20, 23, 98, 128, standC, M.Wood)
	boxAt(def, "StandShelf", -27, 27, 10, 12, 99, 127, standC, M.Wood)
	for _, x in ipairs({ -30, 27 }) do
		boxAt(def, "StandSide", x, x + 3, 0, 20, 98, 128, standC, M.Wood)
	end
	boxAt(def, "StandBack", -30, 30, 0, 20, 127, 129, standC, M.Wood)
	for i = 0, 3 do
		boxAt(def, "ShelfCart", -24 + i * 7, -19 + i * 7, 12, 22, 110, 112, PLASTIC, M.SmoothPlastic)
	end
	local tvC = Color3.fromRGB(44, 42, 48)
	boxAt(def, "TV", -26, 26, 23, 61, 96, 130, tvC, M.SmoothPlastic)
	local screen = boxAt(def, "TVScreen", -20, 16, 29, 57, 95.4, 96, Color3.fromRGB(100, 120, 160), M.Neon, NOCOL)
	surfaceText(screen, Enum.NormalId.Front, "PRESS 2 DIE", { font = Enum.Font.Arcade, color = Color3.fromRGB(220, 30, 30) })
	tag(screen, "P2D_Flicker", { Strong = true })
	local tvLight = Instance.new("SurfaceLight")
	tvLight.Face = Enum.NormalId.Front
	tvLight.Range = 60
	tvLight.Angle = 100
	tvLight.Brightness = 2.5
	tvLight.Color = Color3.fromRGB(150, 180, 255)
	tvLight.Parent = screen
	for _, s in ipairs({ -1, 1 }) do
		mk(m, "Antenna", Vector3.new(0.8, 34, 0.8), CFrame.new(o + Vector3.new(s * 8, 76, 113)) * CFrame.Angles(0, 0, math.rad(-25 * s)), Color3.fromRGB(190, 190, 200), M.Metal)
	end
	reserve(def, 0, 112, 32)

	-- сама приставка PRESS2DIE и джойстик
	boxAt(def, "Console", -17, 17, 0, 8, 66, 90, PLASTIC, M.SmoothPlastic)
	boxAt(def, "ConsoleSlot", -12, 12, 8, 8.6, 74, 80, PLASTIC_DARK, M.SmoothPlastic)
	local cart = boxAt(def, "ConsoleCartridge", -11, 11, 8, 26, 75.5, 78.5, Color3.fromRGB(120, 118, 126), M.SmoothPlastic)
	surfaceText(cart, Enum.NormalId.Front, "PRESS\n2 DIE", { font = Enum.Font.Arcade, color = Color3.fromRGB(200, 20, 20), bg = Color3.fromRGB(20, 18, 22) })
	local led = boxAt(def, "PowerLED", 10, 13, 3, 5, 65.6, 66.2, Color3.fromRGB(255, 30, 30), M.Neon, NOCOL)
	pointLight(led, Color3.fromRGB(255, 30, 30), 26, 2)
	tag(led, "P2D_Blink", { Rate = 0.8 })
	reserve(def, 0, 78, 20)
	local pad = def.origin + Vector3.new(-34, 0, 56)
	mk(m, "Controller", Vector3.new(16, 3, 8), pad + Vector3.new(0, 1.5, 0), Color3.fromRGB(60, 60, 68), M.SmoothPlastic)
	mk(m, "DPad", Vector3.new(3.6, 0.4, 1.2), pad + Vector3.new(-4.5, 3.2, 0), BLACK, M.SmoothPlastic)
	mk(m, "DPad", Vector3.new(1.2, 0.4, 3.6), pad + Vector3.new(-4.5, 3.2, 0), BLACK, M.SmoothPlastic)
	cyl(m, "ButtonA", 0.6, 1.6, pad + Vector3.new(3.5, 3.2, 1), Color3.fromRGB(220, 30, 30), M.SmoothPlastic)
	cyl(m, "ButtonB", 0.6, 1.6, pad + Vector3.new(5.6, 3.2, -0.6), Color3.fromRGB(240, 200, 40), M.SmoothPlastic)
	cableLine(def, { { -34, 60 }, { -40, 70 }, { -30, 84 }, { -22, 92 }, { -17, 84 } }, 0.7, 1.4, Color3.fromRGB(30, 30, 34))
	reserve(def, -34, 56, 10)

	-- книжный шкаф (запад)
	local shelfC = Color3.fromRGB(120, 86, 56)
	boxAt(def, "ShelfBack", -130, -128, 0, 96, 0, 90, shelfC, M.Wood)
	boxAt(def, "ShelfSide", -128, -112, 0, 96, -2, 0, shelfC, M.Wood)
	boxAt(def, "ShelfSide", -128, -112, 0, 96, 90, 92, shelfC, M.Wood)
	for k = 1, 4 do
		local y = k * 24
		boxAt(def, "ShelfBoard", -128, -112, y - 2, y, 0, 90, shelfC, M.Wood)
	end
	for k = 0, 3 do
		local z = 2
		while z < 86 do
			local th = r:NextNumber(3, 5)
			local bh = r:NextNumber(14, 20)
			if r:NextNumber() < 0.8 and (k > 0 or z > 40) then
				boxAt(def, "ShelfBook", -127, -114, k * 24, k * 24 + bh, z, z + th, NEON_SET[r:NextInteger(1, #NEON_SET)]:Lerp(BLACK, 0.4), M.SmoothPlastic)
			end
			z += th + r:NextNumber(0.3, 4)
		end
	end
	reserve(def, -120, 45, 20)
	reserve(def, -120, 70, 20)
	reserve(def, -120, 20, 20)

	-- игрушки
	toyBlock(def, -30, -30, 12, "P", Color3.fromRGB(220, 60, 60), 0.3)
	toyBlock(def, -16, -40, 10, "2", Color3.fromRGB(60, 120, 220), -0.2)
	toyBlock(def, 40, 10, 12, "D", Color3.fromRGB(60, 180, 90), 0.6)
	toyBlock(def, 20, -60, 11, "I", Color3.fromRGB(240, 190, 40), 0.1)
	toyBlock(def, -70, 50, 12, "E", Color3.fromRGB(170, 80, 220), -0.5)
	toyBlock(def, 90, 40, 10, "!", Color3.fromRGB(240, 120, 40), 0.9)
	local stackTop = bookStack(def, -50, -4, 4, r)
	bookStack(def, 70, 70, 3, r)
	addTokenSpot(def, -50, -4, stackTop)
	-- машинка
	do
		local c = o + Vector3.new(60, 0, 38)
		mk(m, "ToyCar", Vector3.new(20, 5, 10), c + Vector3.new(0, 4, 0), Color3.fromRGB(210, 30, 30), M.SmoothPlastic)
		mk(m, "ToyCarCabin", Vector3.new(10, 4, 9), c + Vector3.new(-1, 8.5, 0), Color3.fromRGB(160, 200, 240), M.Glass, { Transparency = 0.3 })
		for _, w in ipairs({ { -6, -5 }, { 6, -5 }, { -6, 5 }, { 6, 5 } }) do
			mk(m, "ToyWheel", Vector3.new(2.4, 5, 5), CFrame.new(c + Vector3.new(w[1], 2.5, w[2])) * ALONG_Z, Color3.fromRGB(20, 20, 20), M.SmoothPlastic, { Shape = CYL })
		end
		reserve(def, 60, 38, 12)
	end
	-- кассеты
	for _, p in ipairs({ { 30, 60 }, { -90, 10 }, { 100, -10 } }) do
		local c = o + Vector3.new(p[1], 0, p[2])
		mk(m, "Cassette", Vector3.new(16, 1.6, 10), CFrame.new(c + Vector3.new(0, 0.8, 0)) * CFrame.Angles(0, r:NextNumber(0, 3), 0), Color3.fromRGB(24, 24, 28), M.SmoothPlastic)
		reserve(def, p[1], p[2], 9)
	end

	-- окно с лунным светом (восток), постер, календарь
	boxAt(def, "WindowFrame", 128.5, 129.5, 46, 94, -32, 32, Color3.fromRGB(230, 230, 230), M.Wood)
	boxAt(def, "WindowGlass", 128.2, 128.5, 50, 90, -28, 28, Color3.fromRGB(110, 140, 220), M.Neon, NOCOL)
	boxAt(def, "WindowCross", 127.9, 128.2, 50, 90, -1, 1, Color3.fromRGB(230, 230, 230), M.Wood, NOCOL)
	boxAt(def, "WindowCross", 127.9, 128.2, 69, 71, -28, 28, Color3.fromRGB(230, 230, 230), M.Wood, NOCOL)
	for _, s in ipairs({ -1, 1 }) do
		boxAt(def, "Curtain", 126, 128, 40, 100, s * 34 - 6, s * 34 + 6, Color3.fromRGB(40, 50, 100), M.Fabric, NOCOL)
	end
	local moonPart = mk(m, "MoonLight", Vector3.new(1, 1, 1), CFrame.lookAt(o + Vector3.new(126, 80, 0), o + Vector3.new(40, 0, 0)),
		BLACK, M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false })
	local moon = Instance.new("SpotLight")
	moon.Face = Enum.NormalId.Front
	moon.Range = 60
	moon.Angle = 50
	moon.Brightness = 4
	moon.Color = Color3.fromRGB(150, 170, 255)
	moon.Parent = moonPart
	local poster = boxAt(def, "Poster", -40, 20, 40, 84, -129.6, -129.2, Color3.fromRGB(20, 12, 16), M.SmoothPlastic, NOCOL)
	surfaceText(poster, Enum.NormalId.Back, "PRESS 2 DIE\nТЕПЕРЬ\nНА 16 БИТ!", { color = Color3.fromRGB(230, 40, 40) })
	local cal = boxAt(def, "Calendar", -129.6, -129.2, 50, 70, -80, -64, Color3.fromRGB(240, 240, 230), M.SmoothPlastic, NOCOL)
	surfaceText(cal, Enum.NormalId.Right, "ОКТЯБРЬ\n1996", { color = Color3.fromRGB(30, 30, 30) })

	-- дверь (восток)
	boxAt(def, "Door", 129, 129.6, 2, 84, 70, 106, Color3.fromRGB(150, 110, 70), M.Wood, NOCOL)
	ball(m, "DoorKnob", 3, o + Vector3.new(128, 40, 102), GOLD, M.Metal, NOCOL)

	-- спавны и выходы
	for _, p in ipairs({ { 0, 54 }, { -20, 50 }, { 20, 50 }, { -42, 40 }, { 38, 54 } }) do
		addSpawn(def, "Survivor", p[1], p[2])
	end
	for _, p in ipairs({ { -92, -60 }, { -104, -84 }, { -80, -100 } }) do
		addSpawn(def, "Killer", p[1], p[2])
	end
	addEscape(def, 122, 88, "ЩЕЛЬ ПОД ДВЕРЬЮ", holeStyle(Vector3.new(-1, 0, 0), "door"))
	addEscape(def, -20, -122, "МЫШИНАЯ НОРА", holeStyle(Vector3.new(0, 0, 1), "hole"))
	addEscape(def, -122, 112, "ВЕНТИЛЯЦИЯ", holeStyle(Vector3.new(1, 0, 0), "vent"))

	scatterTokenSpots(def, r, 26, 118)
	for _, p in ipairs({ { 84, -100 }, { 96, -112 }, { -16, 106 }, { 14, 106 }, { -96, -70 } }) do
		addTokenSpot(def, p[1], p[2])
	end
	return def
end

------------------------------------------------------------------------
-- ЛОББИ: внутри приставки (материнская плата)
------------------------------------------------------------------------
local lobbyPads = {}
do
	local model = Instance.new("Model")
	model.Name = "Lobby"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model.Parent = Workspace
	local P = CONFIG.LOBBY_POS
	local half, H = 80, 56
	local r = Random.new(7)
	local PCB = Color3.fromRGB(14, 58, 38)
	local TRACE = Color3.fromRGB(176, 140, 60)
	local TRACE_NEON = Color3.fromRGB(80, 255, 150)
	local SHELL = Color3.fromRGB(40, 40, 46)
	local function L(x, y, z) return P + Vector3.new(x, y, z) end

	mk(model, "Floor", Vector3.new(half * 2 + 4, 2, half * 2 + 4), L(0, -1, 0), PCB, M.SmoothPlastic)
	-- дорожки платы
	local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
	for _ = 1, 42 do
		local x, z = r:NextInteger(-18, 18) * 4, r:NextInteger(-18, 18) * 4
		local d = dirs[r:NextInteger(1, 4)]
		local neon = r:NextNumber() < 0.3
		for _ = 1, r:NextInteger(2, 4) do
			local len = r:NextInteger(3, 8) * 4
			local x2 = math.clamp(x + d[1] * len, -76, 76)
			local z2 = math.clamp(z + d[2] * len, -76, 76)
			local L2 = math.abs(x2 - x) + math.abs(z2 - z)
			if L2 > 0.5 then
				local size = d[1] ~= 0 and Vector3.new(L2 + 0.6, 0.16, 0.6) or Vector3.new(0.6, 0.16, L2 + 0.6)
				local tr = mk(model, "Trace", size, L((x + x2) / 2, 0.08, (z + z2) / 2), neon and TRACE_NEON or TRACE, neon and M.Neon or M.Metal, FLAT)
				if neon then tag(tr, "P2D_Pulse") end
			end
			x, z = x2, z2
			if d[1] ~= 0 then
				d = r:NextNumber() < 0.5 and dirs[3] or dirs[4]
			else
				d = r:NextNumber() < 0.5 and dirs[1] or dirs[2]
			end
		end
		cyl(model, "Via", 0.2, 1.4, L(x, 0.1, z), TRACE, M.Metal, FLAT)
	end

	-- корпус приставки: стены с вентиляционными прорезями и потолок
	for _, s in ipairs({ -1, 1 }) do
		mk(model, "Shell", Vector3.new(half * 2 + 4, H, 2), L(0, H / 2, s * (half + 1)), SHELL, M.SmoothPlastic)
		mk(model, "Shell", Vector3.new(2, H, half * 2 + 4), L(s * (half + 1), H / 2, 0), SHELL, M.SmoothPlastic)
	end
	mk(model, "Ceiling", Vector3.new(half * 2 + 4, 2, half * 2 + 4), L(0, H + 1, 0), Color3.fromRGB(28, 28, 32), M.SmoothPlastic)
	for k = -7, 7 do
		local slot = mk(model, "VentSlot", Vector3.new(1.2, 16, 0.3), L(k * 9, 38, half - 0.2), Color3.fromRGB(150, 20, 24), M.Neon, FLAT)
		if k % 3 == 0 then pointLight(slot, Color3.fromRGB(255, 40, 40), 14, 0.6) end
	end

	-- центральный процессор = точка появления
	local cpu = mk(model, "CPU", Vector3.new(28, 3, 28), L(0, 1.5, 0), Color3.fromRGB(24, 24, 28), M.SmoothPlastic)
	for i = -6, 6 do
		for _, s in ipairs({ -1, 1 }) do
			mk(model, "Pin", Vector3.new(0.8, 0.5, 2.4), L(i * 2, 0.3, s * 15), Color3.fromRGB(200, 200, 210), M.Metal, FLAT)
			mk(model, "Pin", Vector3.new(2.4, 0.5, 0.8), L(s * 15, 0.3, i * 2), Color3.fromRGB(200, 200, 210), M.Metal, FLAT)
		end
	end
	surfaceText(cpu, Enum.NormalId.Top, "PRESS2DIE\nCPU-16  ©1994", { color = Color3.fromRGB(110, 110, 120), pps = 8 })

	-- чипы
	for _, c in ipairs({
		{ -56, -30, 20, 12, "RAM 64K" }, { 56, -30, 20, 12, "VIDEO PPU" },
		{ -56, 14, 14, 14, "SOUND FM" }, { 56, 22, 12, 18, "BIOS v1.0" },
	}) do
		local chip = mk(model, "Chip", Vector3.new(c[3], 3, c[4]), L(c[1], 1.5, c[2]), Color3.fromRGB(20, 20, 24), M.SmoothPlastic)
		surfaceText(chip, Enum.NormalId.Top, c[5], { color = Color3.fromRGB(150, 150, 160), font = Enum.Font.Arcade, pps = 10 })
		local n = math.floor(c[3] / 2.5)
		for i = 0, n - 1 do
			local x = c[1] - c[3] / 2 + 1.25 + i * 2.5
			for _, s in ipairs({ -1, 1 }) do
				mk(model, "Pin", Vector3.new(0.7, 0.5, 1.8), L(x, 0.3, c[2] + s * (c[4] / 2 + 0.8)), Color3.fromRGB(200, 200, 210), M.Metal, FLAT)
			end
		end
	end
	-- конденсаторы
	for _, c in ipairs({ { -66, -64 }, { -56, -66 }, { -66, -54 }, { 64, -64 }, { 54, -66 }, { -30, -64 }, { 30, -64 } }) do
		cyl(model, "Capacitor", 9, 5, L(c[1], 4.5, c[2]), Color3.fromRGB(24, 36, 90), M.SmoothPlastic)
		cyl(model, "CapTop", 0.3, 4.6, L(c[1], 9.1, c[2]), Color3.fromRGB(190, 190, 200), M.Metal, FLAT)
		mk(model, "CapStripe", Vector3.new(0.4, 8, 1), L(c[1] + 2.45, 4.5, c[2]), Color3.fromRGB(220, 220, 230), M.SmoothPlastic, FLAT)
	end
	-- радиатор: между рёбрами можно пройти
	mk(model, "HeatsinkBase", Vector3.new(24, 1, 22), L(62, 0.5, -4), Color3.fromRGB(150, 155, 165), M.Metal)
	for i = 0, 6 do
		mk(model, "Fin", Vector3.new(0.8, 14, 22), L(51 + i * 3.6, 8, -4), Color3.fromRGB(170, 175, 185), M.Metal)
	end
	-- радужный шлейф
	local ribbon = { Color3.fromRGB(230, 60, 60), Color3.fromRGB(240, 150, 40), Color3.fromRGB(240, 220, 60),
		Color3.fromRGB(80, 200, 90), Color3.fromRGB(60, 140, 240), Color3.fromRGB(150, 90, 230), Color3.fromRGB(220, 220, 230) }
	for i, col in ipairs(ribbon) do
		mk(model, "Ribbon", Vector3.new(50, 0.25, 0.9), L(-54, 0.15, -14 + i * 0.95), col, M.SmoothPlastic, FLAT)
	end
	mk(model, "RibbonPlug", Vector3.new(4, 2.5, 9), L(-27, 1.25, -10.2), Color3.fromRGB(30, 30, 34), M.SmoothPlastic)

	-- картридж, вставленный сверху: светящиеся контакты над процессором
	local cart = mk(model, "TopCartridge", Vector3.new(44, 16, 6), L(0, H - 8, 0), Color3.fromRGB(120, 118, 126), M.SmoothPlastic)
	surfaceText(cart, Enum.NormalId.Front, "PRESS 2 DIE", { font = Enum.Font.Arcade, color = Color3.fromRGB(190, 20, 20) })
	surfaceText(cart, Enum.NormalId.Back, "НЕ ВЫНИМАЙ", { color = Color3.fromRGB(190, 20, 20) })
	for i = -9, 9 do
		mk(model, "CartPin", Vector3.new(1.2, 2, 6.4), L(i * 2.2, H - 17, 0), GOLD, M.Neon, NOCOL)
	end
	local pinsLight = mk(model, "CartGlow", Vector3.new(1, 1, 1), L(0, H - 20, 0), BLACK, M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false })
	pointLight(pinsLight, Color3.fromRGB(255, 120, 60), 50, 1.4)

	-- большой экран статуса (содержимое рисует клиент)
	mk(model, "ScreenBezel", Vector3.new(64, 34, 1.4), L(0, 25, -half + 0.3), Color3.fromRGB(26, 26, 30), M.SmoothPlastic)
	mk(model, "LobbyScreen", Vector3.new(60, 30, 0.4), L(0, 25, -half + 1.1), Color3.fromRGB(4, 6, 8), M.SmoothPlastic)
	local screenLight = mk(model, "ScreenGlow", Vector3.new(1, 1, 1), L(0, 25, -half + 6), BLACK, M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false })
	pointLight(screenLight, Color3.fromRGB(255, 70, 70), 40, 0.8)

	-- надписи на стенах
	local w1 = mk(model, "WallSign", Vector3.new(0.3, 7, 50), L(-half + 0.2, 26, 0), BLACK, M.SmoothPlastic, { Transparency = 1, CanCollide = false })
	surfaceText(w1, Enum.NormalId.Right, "НЕ ВЫКЛЮЧАЙ ПРИСТАВКУ", { color = Color3.fromRGB(190, 20, 20) })
	local w2 = mk(model, "WallSign", Vector3.new(0.3, 7, 50), L(half - 0.2, 26, 0), BLACK, M.SmoothPlastic, { Transparency = 1, CanCollide = false })
	surfaceText(w2, Enum.NormalId.Left, "ИГРА НЕ СОХРАНЕНА", { color = Color3.fromRGB(190, 20, 20) })
	local floorHint = mk(model, "FloorHint", Vector3.new(70, 0.1, 5), L(0, 0.06, 30), BLACK, M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false })
	surfaceText(floorHint, Enum.NormalId.Top, "»  ВСТАНЬ НА ПЛАТФОРМУ КАРТРИДЖА — ВЫБЕРИ УРОВЕНЬ  «", { color = Color3.fromRGB(230, 220, 150), pps = 12 })

	-- индикатор питания
	local power = mk(model, "PowerLED", Vector3.new(3, 3, 1), L(-70, 46, -half + 0.6), Color3.fromRGB(255, 30, 30), M.Neon, NOCOL)
	pointLight(power, Color3.fromRGB(255, 30, 30), 30, 2)
	tag(power, "P2D_Blink", { Rate = 0.5 })
	for _, p in ipairs({ { -40, -40 }, { 40, -40 }, { -40, 40 }, { 40, 40 } }) do
		local lamp = mk(model, "AmbientLamp", Vector3.new(1, 1, 1), L(p[1], 30, p[2]), BLACK, M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false })
		pointLight(lamp, Color3.fromRGB(120, 255, 170), 60, 0.5)
	end

	-- картриджи-голосовалки на юге
	for idx, info in ipairs(MAP_INFO) do
		local x = -45 + (idx - 1) * 30
		local col = Color3.fromRGB(info.color[1], info.color[2], info.color[3])
		mk(model, "CartSlot", Vector3.new(20, 3, 6), L(x, 1.5, 62), Color3.fromRGB(20, 20, 24), M.SmoothPlastic)
		for k = -4, 4 do
			mk(model, "SlotPin", Vector3.new(0.6, 0.2, 5), L(x + k * 2, 3.05, 62), GOLD, M.Metal, FLAT)
		end
		mk(model, "VoteCartridge", Vector3.new(16, 20, 3), L(x, 12, 62), Color3.fromRGB(150, 148, 156), M.SmoothPlastic)
		for k = 0, 3 do
			mk(model, "Ridge", Vector3.new(14, 0.4, 0.3), L(x, 20.5 - k * 0.9, 60.4), Color3.fromRGB(110, 108, 116), M.SmoothPlastic, FLAT)
		end
		local label = mk(model, "CartLabel", Vector3.new(13, 12, 0.2), L(x, 12.5, 60.4), Color3.new(1, 1, 1), M.SmoothPlastic, NOCOL)
		local sg = surfaceGui(label, Enum.NormalId.Front, 24)
		local bg = Instance.new("Frame")
		bg.Size = UDim2.fromScale(1, 1)
		bg.BackgroundColor3 = col
		bg.BorderSizePixel = 0
		bg.Parent = sg
		local grad = Instance.new("UIGradient")
		grad.Rotation = 90
		grad.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(40, 30, 40))
		grad.Parent = bg
		for k = 0, 2 do
			local stripe = Instance.new("Frame")
			stripe.AnchorPoint = Vector2.new(0.5, 0.5)
			stripe.Position = UDim2.fromScale(0.15 + k * 0.12, 0.3)
			stripe.Size = UDim2.new(0, 18, 1.6, 0)
			stripe.Rotation = 30
			stripe.BorderSizePixel = 0
			stripe.BackgroundColor3 = Color3.new(1, 1, 1)
			stripe.BackgroundTransparency = 0.75
			stripe.Parent = bg
		end
		local function lbl(text, y, h, font, color)
			local t = Instance.new("TextLabel")
			t.BackgroundTransparency = 1
			t.Position = UDim2.fromScale(0.06, y)
			t.Size = UDim2.fromScale(0.88, h)
			t.Font = font
			t.TextScaled = true
			t.TextColor3 = color
			t.TextStrokeTransparency = 0.4
			t.Text = text
			t.Parent = bg
			return t
		end
		lbl("PRESS2DIE", 0.04, 0.1, Enum.Font.Arcade, Color3.fromRGB(255, 230, 230))
		lbl(info.name, 0.24, 0.24, Enum.Font.GothamBlack, Color3.new(1, 1, 1))
		lbl(info.sub, 0.5, 0.1, Enum.Font.GothamBold, Color3.fromRGB(230, 230, 230))
		local votes = lbl("ГОЛОСОВ: 0", 0.78, 0.14, Enum.Font.GothamBlack, Color3.fromRGB(255, 230, 120))
		local padPart = mk(model, "VotePad", Vector3.new(14, 0.4, 12), L(x, 0.2, 47), col, M.Neon, { Transparency = 0.5 })
		surfaceText(padPart, Enum.NormalId.Top, "ГОЛОС", { color = Color3.new(1, 1, 1), pps = 14 })
		pointLight(padPart, col, 18, 0.8)
		table.insert(lobbyPads, { key = info.key, center = padPart.Position, hx = 7, hz = 6, label = votes, pad = padPart })
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.Position = L(0, 3.5, 0)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.CanQuery = false
	local decal = spawn:FindFirstChildOfClass("Decal")
	if decal then decal:Destroy() end
	spawn.Parent = model
end

local function lobbyCFrame()
	return CFrame.new(CONFIG.LOBBY_POS + Vector3.new(rng:NextNumber(-9, 9), 7, rng:NextNumber(-9, 9)))
end

------------------------------------------------------------------------
-- СЦЕНА ВЫБОРА: 6 подиумов с прожекторами, монитор Палача, закулисье
------------------------------------------------------------------------
local STAGE = CONFIG.STAGE_POS
local SLOT_SPACING = 9
local PODIUM_H = 2.5
local SLOT_X = {}
for i = 1, CONFIG.MAX_SURVIVORS do
	SLOT_X[i] = (i - (CONFIG.MAX_SURVIVORS + 1) / 2) * SLOT_SPACING
end
local HOLD_SURV = STAGE + Vector3.new(0, -60, 60)
local HOLD_KILLER = STAGE + Vector3.new(0, -60, -120)
local slots = {}
local SPOT_WARM = Color3.fromRGB(255, 236, 200)
local LENS_OFF = Color3.fromRGB(40, 36, 34)

do
	local model = Instance.new("Model")
	model.Name = "SelectionStage"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model.Parent = Workspace
	local S = STAGE
	local function L(x, y, z) return S + Vector3.new(x, y, z) end

	mk(model, "StageFloor", Vector3.new(78, 2, 30), L(0, -1, 3), Color3.fromRGB(18, 16, 20), M.SmoothPlastic, { Reflectance = 0.12 })
	mk(model, "StageRiser", Vector3.new(78, 6, 1), L(0, -3, -12.5), Color3.fromRGB(14, 12, 16), M.SmoothPlastic)
	mk(model, "StageTrim", Vector3.new(78, 0.35, 0.35), L(0, -0.1, -12.1), BLOOD, M.Neon, NOCOL)
	for k = -13, 13 do
		local f = mk(model, "Footlight", Vector3.new(1.2, 0.4, 0.6), L(k * 2.8, 0.2, -11.4), Color3.fromRGB(255, 190, 120), M.Neon, NOCOL)
		if k % 4 == 0 then pointLight(f, Color3.fromRGB(255, 160, 90), 9, 0.6) end
	end
	mk(model, "Pit", Vector3.new(220, 2, 120), L(0, -7, -70), Color3.fromRGB(6, 6, 8), M.Slate)

	-- задник: логотип и пиксельные черепа
	mk(model, "BackWall", Vector3.new(100, 46, 2), L(0, 21, 18), Color3.fromRGB(14, 12, 16), M.SmoothPlastic)
	local logo = mk(model, "Logo", Vector3.new(56, 8, 0.4), L(0, 23.5, 16.8), Color3.fromRGB(8, 6, 8), M.SmoothPlastic)
	surfaceText(logo, Enum.NormalId.Front, "PRESS 2 DIE", { font = Enum.Font.Arcade, color = Color3.fromRGB(230, 30, 30) })
	for _, e in ipairs({ { 0, 27.8, 57.6, 0.4 }, { 0, 19.2, 57.6, 0.4 }, { -28.6, 23.5, 0.4, 8.8 }, { 28.6, 23.5, 0.4, 8.8 } }) do
		mk(model, "LogoNeon", Vector3.new(e[3], e[4], 0.4), L(e[1], e[2], 16.6), Color3.fromRGB(255, 40, 40), M.Neon, NOCOL)
	end
	local wash = mk(model, "LogoWash", Vector3.new(50, 1, 0.2), L(0, 18.6, 16.4), BLACK, M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false })
	local sl = Instance.new("SurfaceLight")
	sl.Face = Enum.NormalId.Front
	sl.Range = 22
	sl.Angle = 110
	sl.Brightness = 0.7
	sl.Color = Color3.fromRGB(255, 40, 40)
	sl.Parent = wash
	for _, sx in ipairs({ -36, 36 }) do
		pixelArt(model, CFrame.new(L(sx, 13, 16.6)), SKULL, 1.1, { ["#"] = Color3.fromRGB(230, 225, 210) }, 0.3)
	end
	-- кулисы
	for _, s in ipairs({ -1, 1 }) do
		for k = 0, 5 do
			cyl(model, "Curtain", 34, 2.6, L(s * (35 + k * 0.9), 17, -9 + k * 4.4), (k % 2 == 0) and Color3.fromRGB(90, 12, 18) or Color3.fromRGB(64, 8, 12), M.Fabric)
		end
		local rim = mk(model, "RimLight", Vector3.new(1, 1, 1), L(s * 30, 8, 10), BLACK, M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false })
		pointLight(rim, Color3.fromRGB(60, 80, 255), 26, 1.4)
		mk(model, "TrussLeg", Vector3.new(0.8, 21, 0.8), L(s * 33, 10.5, -3.5), Color3.fromRGB(60, 60, 66), M.Metal)
	end
	mk(model, "Truss", Vector3.new(68, 0.8, 0.8), L(0, 20.6, -3.5), Color3.fromRGB(60, 60, 66), M.Metal)
	mk(model, "Truss", Vector3.new(68, 0.8, 0.8), L(0, 21.6, -2.5), Color3.fromRGB(60, 60, 66), M.Metal)

	-- подиумы P1..P6 с прожекторами
	for i = 1, CONFIG.MAX_SURVIVORS do
		local x = SLOT_X[i]
		local podium = cyl(model, "Podium", PODIUM_H, 6, L(x, PODIUM_H / 2, 0), Color3.fromRGB(26, 24, 30), M.SmoothPlastic)
		local ring = cyl(model, "PodiumRing", 0.3, 6.4, L(x, PODIUM_H - 0.1, 0), Color3.fromRGB(50, 46, 54), M.SmoothPlastic, NOCOL)
		local pool = cyl(model, "LightPool", 0.06, 5.4, L(x, PODIUM_H + 0.04, 0), SPOT_WARM, M.Neon, { Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
		-- табло на передней стороне подиума
		local panel = mk(model, "PodiumPanel", Vector3.new(4.8, 1.7, 0.3), L(x, 1.2, -3.05), BLACK, M.SmoothPlastic, NOCOL)
		local sg = surfaceGui(panel, Enum.NormalId.Front, 80)
		local plate = Instance.new("Frame")
		plate.Size = UDim2.fromScale(1, 1)
		plate.BackgroundColor3 = Color3.fromRGB(16, 14, 18)
		plate.BorderSizePixel = 0
		plate.Parent = sg
		local function txt(props)
			local t = Instance.new("TextLabel")
			t.BackgroundTransparency = 1
			t.TextScaled = true
			t.TextStrokeTransparency = 0.5
			for k, v in pairs(props) do t[k] = v end
			t.Parent = plate
			return t
		end
		txt({ Position = UDim2.fromScale(0.03, 0.1), Size = UDim2.fromScale(0.28, 0.8), Font = Enum.Font.Arcade, Text = "P" .. i,
			TextColor3 = Color3.fromRGB(255, 220, 110) })
		local charText = txt({ Position = UDim2.fromScale(0.33, 0.06), Size = UDim2.fromScale(0.64, 0.52), Font = Enum.Font.GothamBlack,
			Text = "СВОБОДНО", TextColor3 = Color3.fromRGB(120, 116, 124), TextXAlignment = Enum.TextXAlignment.Left })
		local nameText = txt({ Position = UDim2.fromScale(0.33, 0.58), Size = UDim2.fromScale(0.64, 0.34), Font = Enum.Font.GothamMedium,
			Text = "", TextColor3 = Color3.fromRGB(220, 220, 220), TextXAlignment = Enum.TextXAlignment.Left })

		-- прожектор над местом
		local lampPos = L(x, 18.4, -4.2)
		local target = L(x, PODIUM_H, 0)
		local aim = CFrame.lookAt(lampPos, target) * ALONG_Z -- ось цилиндра смотрит на подиум
		mk(model, "SpotHanger", Vector3.new(0.3, 2, 0.3), L(x, 19.6, -3.8), Color3.fromRGB(40, 40, 44), M.Metal)
		mk(model, "SpotHousing", Vector3.new(2.6, 1.9, 1.9), aim, Color3.fromRGB(22, 22, 26), M.Metal, { Shape = CYL })
		local lens = mk(model, "SpotLens", Vector3.new(0.2, 1.6, 1.6), aim * CFrame.new(1.35, 0, 0), LENS_OFF, M.Neon, { Shape = CYL, CanCollide = false, CanQuery = false })
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Right
		spot.Range = 30
		spot.Angle = 32
		spot.Brightness = 9
		spot.Shadows = true
		spot.Color = SPOT_WARM
		spot.Enabled = false
		spot.Parent = lens
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0.15, 0, 0)
		a0.Parent = lens
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, 0.05, 0)
		a1.Parent = pool
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Width0 = 1.5
		beam.Width1 = 6.4
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Segments = 1
		beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.86) })
		beam.Color = ColorSequence.new(SPOT_WARM)
		beam.Enabled = false
		beam.Parent = lens
		slots[i] = { podium = podium, ring = ring, pool = pool, lens = lens, spot = spot, beam = beam,
			plate = plate, charText = charText, nameText = nameText, litId = nil, token = 0 }
	end

	-- туман на сцене
	local fog = mk(model, "StageFog", Vector3.new(66, 1, 18), L(0, 0.6, 2), BLACK, M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false })
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
	pe.Rate = 5
	pe.Lifetime = NumberRange.new(6, 9)
	pe.Speed = NumberRange.new(0.3, 0.8)
	pe.SpreadAngle = Vector2.new(180, 10)
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(1, 9) })
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.86), NumberSequenceKeypoint.new(1, 1) })
	pe.Color = ColorSequence.new(Color3.fromRGB(130, 120, 140))
	pe.RotSpeed = NumberRange.new(-10, 10)
	pe.Parent = fog

	-- монитор Палача: висит над сценой; клиент опускает его, когда Палач выбрал облик
	local mon = Instance.new("Model")
	mon.Name = "KillerMonitor"
	mon.Parent = model
	local lowered = CFrame.new(L(0, 12.2, 5))
	local body = mk(mon, "Body", Vector3.new(12, 9, 7), lowered, Color3.fromRGB(34, 32, 38), M.SmoothPlastic)
	mk(mon, "Back", Vector3.new(9, 7, 4), lowered * CFrame.new(0, 0, 5.4), Color3.fromRGB(30, 28, 34), M.SmoothPlastic)
	mk(mon, "Screen", Vector3.new(9.4, 6.4, 0.2), lowered * CFrame.new(-0.6, 0.5, -3.55), BLACK, M.SmoothPlastic, NOCOL)
	local brand = mk(mon, "Brand", Vector3.new(5, 0.8, 0.1), lowered * CFrame.new(-0.6, -3.65, -3.52), Color3.fromRGB(34, 32, 38), M.SmoothPlastic, NOCOL)
	surfaceText(brand, Enum.NormalId.Front, "P2D-TV", { font = Enum.Font.Arcade, color = Color3.fromRGB(160, 160, 170) })
	for k = 0, 2 do
		cyl(mon, "Knob", 0.3, 0.7, lowered * CFrame.new(5.1, 2 - k * 1.4, -3.6) * ALONG_Z * VERT:Inverse(), Color3.fromRGB(80, 80, 90), M.Metal, NOCOL)
	end
	local rec = ball(mon, "RecLED", 0.4, (lowered * CFrame.new(5.1, -2.8, -3.6)).Position, Color3.fromRGB(255, 30, 30), M.Neon, NOCOL)
	tag(rec, "P2D_Blink", { Rate = 1.4 })
	for _, s in ipairs({ -1, 1 }) do
		mk(mon, "Antenna", Vector3.new(0.15, 5, 0.15), lowered * CFrame.new(s * 1.4, 6.4, 1) * CFrame.Angles(0, 0, math.rad(-28 * s)), Color3.fromRGB(180, 180, 190), M.Metal, NOCOL)
		cyl(mon, "Cable", 40, 0.3, lowered * CFrame.new(s * 4.5, 24.5, 0), BLACK, M.SmoothPlastic, NOCOL)
	end
	mon.PrimaryPart = body
	local raised = lowered + Vector3.new(0, 30, 0)
	mon:SetAttribute("Lowered", lowered)
	mon:SetAttribute("Raised", raised)
	mon:PivotTo(raised)

	-- закулисье: сюда прячут тех, кто ещё не выбрал, и Палача
	local function sealedBox(center, w, d)
		local c = Color3.fromRGB(10, 10, 12)
		mk(model, "HoldFloor", Vector3.new(w, 1, d), center - Vector3.new(0, 0.5, 0), c, M.SmoothPlastic)
		mk(model, "HoldRoof", Vector3.new(w, 1, d), center + Vector3.new(0, 10.5, 0), c, M.SmoothPlastic)
		for _, s in ipairs({ -1, 1 }) do
			mk(model, "HoldWall", Vector3.new(w, 10, 1), center + Vector3.new(0, 5, s * (d / 2 + 0.5)), c, M.SmoothPlastic)
			mk(model, "HoldWall", Vector3.new(1, 10, d), center + Vector3.new(s * (w / 2 + 0.5), 5, 0), c, M.SmoothPlastic)
		end
	end
	sealedBox(HOLD_SURV, 40, 12)
	sealedBox(HOLD_KILLER, 12, 12)
end

------------------------------------------------------------------------
-- РЕЕСТР КАРТ
------------------------------------------------------------------------
local MAPS = {
	Hills = buildHills(Vector3.new(2000, 0, 0)),
	Arcade = buildArcade(Vector3.new(4000, 0, 0)),
	Maze = buildMaze(Vector3.new(6000, 0, 0)),
	Room = buildRoom(Vector3.new(8000, 0, 0)),
}

-- зоны для клиентских пресетов освещения
do
	local zones = {
		{ k = "Lobby", x = CONFIG.LOBBY_POS.X, y = CONFIG.LOBBY_POS.Y, z = CONFIG.LOBBY_POS.Z, h = 140 },
		{ k = "Stage", x = STAGE.X, y = STAGE.Y, z = STAGE.Z, h = 220 },
	}
	for key, def in pairs(MAPS) do
		table.insert(zones, { k = key, x = def.origin.X, y = def.origin.Y, z = def.origin.Z, h = 170 })
	end
	gameState:SetAttribute("Zones", HttpService:JSONEncode(zones))
end

------------------------------------------------------------------------
-- СОСТОЯНИЕ МАТЧА
------------------------------------------------------------------------
local matchActive = false
local currentDef = nil
local killer = nil
local killerChar = nil     -- данные персонажа Палача
local killerMods = nil
local kills = 0
local survivorList = {}    -- { {player, userId, name, dname, charId, port, tokens, status} }
local entryOf = {}
local matchConns = {}
local lastMap, lastKiller = nil, nil
local stamina = {}         -- [player] = {value, max, exhausted, regenAt, want, isKiller, speedMul}
local boostUntil = {}
local matchEndAt = 0
local activeTokens = {}
local tokensGot, tokensNeeded = 0, 0
local dashUntil, vanishUntil = 0, 0
local vanishSaved = nil

local function serverNow() return Workspace:GetServerTimeNow() end

-- бонусы из пипсов
local function survivorMods(c)
	return {
		hp = 1 + (c.hp - 3) * 0.08,
		speed = 1 + (c.speed - 3) * 0.025,
		stamina = 1 + (c.stamina - 3) * 0.08,
	}
end

local function killerModsOf(c)
	return {
		speed = 1 + (c.speed - 3) * 0.025,
		stamina = 1 + (c.stamina - 3) * 0.08,
		attack = 1 - (c.power - 3) * 0.1,
	}
end

local function setPhase(p) gameState:SetAttribute("Phase", p) end

-- глагол с учётом рода героя: said(e, "погиб", "погибла")
local function said(e, male, female)
	return e.name .. " " .. ((e.char and e.char.f) and female or male)
end

local function announce(text, kind, target)
	if target then
		if target.Parent == Players then announceEvent:FireClient(target, text, kind) end
	else
		announceEvent:FireAllClients(text, kind)
	end
end

local function publishRoster()
	local list = {}
	for _, e in ipairs(survivorList) do
		table.insert(list, { id = e.userId, c = e.charId, s = e.status, p = e.port, n = e.dname, t = e.tokens })
	end
	gameState:SetAttribute("Roster", HttpService:JSONEncode(list))
	if killer and killerChar then
		gameState:SetAttribute("Killer", HttpService:JSONEncode({ id = killer.UserId, c = killerChar.id, n = killer.DisplayName, k = kills }))
	else
		gameState:SetAttribute("Killer", "{}")
	end
end

local function shuffle(t)
	for i = #t, 2, -1 do
		local j = rng:NextInteger(1, i)
		t[i], t[j] = t[j], t[i]
	end
end

local function countStatus(st)
	local n = 0
	for _, e in ipairs(survivorList) do
		if e.status == st then n += 1 end
	end
	return n
end

local function getReadyPlayers()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local c = p.Character
		local h = c and c:FindFirstChildOfClass("Humanoid")
		if h and h.Health > 0 and c:FindFirstChild("HumanoidRootPart") then
			table.insert(list, p)
		end
	end
	return list
end

local function spawnCFrame(part, center)
	local off = Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3))
	local pos = part.Position + Vector3.new(0, 4, 0) + off
	return CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, center.Z))
end

-- при включённом стриминге заранее подгружаем место телепорта
local function preStream(list)
	if not Workspace.StreamingEnabled then return end
	local pending = #list
	for _, it in ipairs(list) do
		task.spawn(function()
			pcall(function() it[1]:RequestStreamAroundAsync(it[2], 2) end)
			pending -= 1
		end)
	end
	local t0 = os.clock()
	while pending > 0 and os.clock() - t0 < 2.5 do task.wait(0.05) end
end

local function addFlashlight(char)
	local head = char:FindFirstChild("Head")
	if not head or head:FindFirstChild("HorrorLight") then return end
	local l = Instance.new("SpotLight")
	l.Name = "HorrorLight"
	l.Brightness = 4
	l.Range = 55
	l.Angle = 75
	l.Face = Enum.NormalId.Front
	l.Color = Color3.fromRGB(255, 240, 210)
	l.Parent = head
end

local function removeFlashlight(char)
	local head = char and char:FindFirstChild("Head")
	local l = head and head:FindFirstChild("HorrorLight")
	if l then l:Destroy() end
end

local function setRootAnchored(p, on)
	local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	if hrp then hrp.Anchored = on end
end

------------------------------------------------------------------------
-- ВЫНОСЛИВОСТЬ, БЕГ (Shift), УСКОРЕНИЕ ПОСЛЕ УРОНА, РЫВОК/ПРЯТКИ ПАЛАЧА
-- Всё считается на сервере; клиент только сообщает «держу Shift».
------------------------------------------------------------------------
local function initStamina(p, isKiller, mods)
	mods = mods or { stamina = 1, speed = 1 }
	local max = (isKiller and CONFIG.STAMINA_MAX_KILLER or CONFIG.STAMINA_MAX_SURVIVOR) * mods.stamina
	stamina[p] = {
		value = max, max = max, exhausted = false, regenAt = 0, want = false,
		isKiller = isKiller, speedMul = mods.speed,
	}
	p:SetAttribute("MaxStamina", math.floor(max + 0.5))
	p:SetAttribute("Stamina", math.floor(max + 0.5))
	p:SetAttribute("Exhausted", false)
	p:SetAttribute("Boosted", false)
end

local function clearStamina(p)
	stamina[p] = nil
	boostUntil[p] = nil
	p:SetAttribute("MaxStamina", nil)
	p:SetAttribute("Stamina", nil)
	p:SetAttribute("Exhausted", nil)
	p:SetAttribute("Boosted", nil)
end

local function watchDamage(p, hum)
	local last = hum.Health
	table.insert(matchConns, hum.HealthChanged:Connect(function(h)
		if h < last and h > 0 then
			boostUntil[p] = os.clock() + CONFIG.HIT_BOOST_TIME
		end
		last = h
	end))
end

sprintEvent.OnServerEvent:Connect(function(p, want)
	local s = stamina[p]
	if s then s.want = (want == true) end
end)

local function setVanish(on)
	local char = killer and killer.Character
	if on then
		if not char or vanishSaved then return end
		vanishSaved = {}
		for _, d in ipairs(char:GetDescendants()) do
			if (d:IsA("BasePart") or d:IsA("Decal")) and d.Name ~= "HumanoidRootPart" then
				vanishSaved[d] = d.Transparency
				d.Transparency = 1
			end
		end
		local aura = char:FindFirstChild("KillerAura", true)
		if aura then aura.Enabled = false end
	else
		if vanishSaved then
			for d, t in pairs(vanishSaved) do
				if d.Parent then d.Transparency = t end
			end
		end
		vanishSaved = nil
		vanishUntil = 0
		if char then
			local aura = char:FindFirstChild("KillerAura", true)
			if aura then aura.Enabled = true end
		end
		if killer then killer:SetAttribute("AbilityUntil", 0) end
	end
end

RunService.Heartbeat:Connect(function(dt)
	if not matchActive then return end
	local now = os.clock()
	if vanishSaved and now >= vanishUntil then setVanish(false) end
	for p, s in pairs(stamina) do
		local char = p.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			local base = (s.isKiller and CONFIG.KILLER_SPEED or CONFIG.SURVIVOR_SPEED) * s.speedMul
			local run = (s.isKiller and CONFIG.KILLER_SPRINT_SPEED or CONFIG.SURVIVOR_SPRINT_SPEED) * s.speedMul
			local moving = hum.MoveDirection.Magnitude > 0.1
			local sprinting = s.want and moving and not s.exhausted and s.value > 0

			if sprinting then
				s.value = math.max(0, s.value - CONFIG.STAMINA_DRAIN * dt)
				s.regenAt = now + CONFIG.STAMINA_REGEN_DELAY
				if s.value <= 0 then
					s.exhausted = true -- выдохся: бег недоступен, пока не восстановится часть запаса
					sprinting = false
				end
			elseif now >= s.regenAt then
				s.value = math.min(s.max, s.value + CONFIG.STAMINA_REGEN * dt)
				if s.exhausted and s.value >= s.max * CONFIG.STAMINA_RECOVER_FRACTION then
					s.exhausted = false
				end
			end

			local speed = sprinting and run or base
			local boosted = boostUntil[p] ~= nil and now < boostUntil[p]
			if boosted then speed *= CONFIG.HIT_BOOST_MULT end
			if p == killer then
				if now < dashUntil then speed = CONFIG.DASH_SPEED end
				if vanishSaved then speed *= 1.08 end
			end
			hum.WalkSpeed = speed

			p:SetAttribute("Stamina", math.floor(s.value + 0.5))
			p:SetAttribute("Exhausted", s.exhausted)
			p:SetAttribute("Boosted", boosted)
		end
	end
end)

------------------------------------------------------------------------
-- СМЕРТЬ / ПОБЕГ
------------------------------------------------------------------------
local function markDead(e, text)
	if e.status ~= "alive" then return end
	e.status = "dead"
	e.player:SetAttribute("Status", "dead")
	clearStamina(e.player)
	removeFlashlight(e.player.Character)
	publishRoster()
	announce(text or said(e, "погиб", "погибла"), "bad")
end

local function markEscaped(e)
	if e.status ~= "alive" then return end
	e.status = "escaped"
	e.player:SetAttribute("Status", "escaped")
	clearStamina(e.player)
	local char = e.player.Character
	removeFlashlight(char)
	if char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then hum.WalkSpeed = 16 end
		char:PivotTo(lobbyCFrame())
	end
	publishRoster()
	announce(said(e, "сбежал", "сбежала") .. " из приставки!", "good")
	announce("ПОБЕГ УДАЛСЯ! Можно наблюдать за остальными.", "good", e.player)
end

------------------------------------------------------------------------
-- ОРУЖИЕ И СПОСОБНОСТИ ПАЛАЧА
------------------------------------------------------------------------
local function weldTool(handle, name, size, offset, color, mat, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	if shape then p.Shape = shape end
	p.Color = color
	p.Material = mat
	p.CanCollide = false
	p.Massless = true
	p.CastShadow = false
	p.CFrame = handle.CFrame * offset
	local w = Instance.new("Weld")
	w.Part0 = handle
	w.Part1 = p
	w.C0 = offset
	w.Parent = p
	p.Parent = handle.Parent
	return p
end

local TOOL_LOOKS = {
	executioner = function(handle)
		handle.Color = Color3.fromRGB(60, 40, 28)
		handle.Material = M.Wood
		weldTool(handle, "Blade", Vector3.new(0.14, 1.9, 1.1), CFrame.new(0, 1.55, 0.3), Color3.fromRGB(170, 170, 176), M.Metal)
		weldTool(handle, "Edge", Vector3.new(0.16, 1.9, 0.12), CFrame.new(0, 1.55, 0.86), Color3.fromRGB(200, 20, 20), M.Neon)
		return "Тесак"
	end,
	glitch = function(handle)
		handle.Color = Color3.fromRGB(20, 20, 24)
		local tip = weldTool(handle, "Spark", Vector3.new(0.6, 0.6, 0.6), CFrame.new(0, 1.9, 0), Color3.fromRGB(120, 240, 255), M.Neon, BALL)
		local pe = Instance.new("ParticleEmitter")
		pe.Rate = 18
		pe.Lifetime = NumberRange.new(0.15, 0.35)
		pe.Speed = NumberRange.new(4, 8)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Size = NumberSequence.new(0.15)
		pe.LightEmission = 1
		pe.Color = ColorSequence.new(Color3.fromRGB(120, 240, 255))
		pe.Parent = tip
		return "Оборванный кабель"
	end,
	binky = function(handle)
		handle.Color = Color3.fromRGB(240, 240, 240)
		weldTool(handle, "Candy", Vector3.new(0.4, 2, 2), CFrame.new(0, 2.2, 0), Color3.fromRGB(255, 80, 160), M.SmoothPlastic, CYL)
		weldTool(handle, "Swirl", Vector3.new(0.42, 1.1, 1.1), CFrame.new(0, 2.2, 0), Color3.fromRGB(255, 240, 250), M.Neon, CYL)
		return "Леденец"
	end,
}

local function giveKillerTool(player, hum)
	local tool = Instance.new("Tool")
	tool.ToolTip = "Нажми, чтобы ударить"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.GripPos = Vector3.new(0, -0.5, 0)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.3, 1.6, 0.3)
	handle.CanCollide = false
	handle.Parent = tool
	local look = TOOL_LOOKS[killerChar and killerChar.id or "executioner"] or TOOL_LOOKS.executioner
	tool.Name = look(handle)
	local swing = Instance.new("Sound")
	swing.SoundId = "rbxasset://sounds/swordslash.wav"
	swing.Volume = 0.8
	swing.Parent = handle

	local last = 0
	tool.Activated:Connect(function()
		if not matchActive then return end
		local cd = CONFIG.KILLER_COOLDOWN * (killerMods and killerMods.attack or 1)
		if os.clock() - last < cd then return end
		last = os.clock()
		if vanishSaved then setVanish(false) end -- удар раскрывает невидимку
		local anim = Instance.new("StringValue")
		anim.Name = "toolanim"
		anim.Value = "Slash"
		anim.Parent = tool
		game:GetService("Debris"):AddItem(anim, 1)
		swing:Play()
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		for _, e in ipairs(survivorList) do
			if e.status == "alive" then
				local c = e.player.Character
				local h = c and c:FindFirstChildOfClass("Humanoid")
				local r = c and c:FindFirstChild("HumanoidRootPart")
				if h and r and h.Health > 0 then
					local delta = r.Position - hrp.Position
					if delta.Magnitude > 0 and delta.Magnitude <= CONFIG.KILLER_RANGE
						and delta.Unit:Dot(hrp.CFrame.LookVector) > 0.3 then
						h:TakeDamage(CONFIG.KILLER_DAMAGE) -- ускорение выдаст watchDamage
						fxEvent:FireClient(e.player, "hit")
						fxEvent:FireClient(player, "landed")
					end
				end
			end
		end
	end)

	tool.Parent = player:WaitForChild("Backpack")
	hum:EquipTool(tool)
end

local function setupKiller()
	if not killer or not currentDef or not killerChar then return end
	local char = killer.Character
	if not char then return end
	local hum = char:WaitForChild("Humanoid", 5)
	local hrp = char:WaitForChild("HumanoidRootPart", 5)
	if not hum or not hrp then return end
	local sp = currentDef.killerSpawns[rng:NextInteger(1, #currentDef.killerSpawns)]
	hrp.Anchored = false
	char:PivotTo(spawnCFrame(sp, currentDef.origin))
	applyLook(char, killerChar)
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.WalkSpeed = CONFIG.KILLER_SPEED * killerMods.speed
	initStamina(killer, true, killerMods)
	watchDamage(killer, hum)
	if not hrp:FindFirstChild("KillerAura") then
		local aura = Instance.new("PointLight")
		aura.Name = "KillerAura"
		aura.Color = charColor(killerChar)
		aura.Range = 14
		aura.Brightness = 1.5
		aura.Parent = hrp
	end
	if killerChar.ability.id == "dash" and not hrp:FindFirstChild("DashTrail") then
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 1, 0)
		a0.Parent = hrp
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -1, 0)
		a1.Parent = hrp
		local trail = Instance.new("Trail")
		trail.Name = "DashTrail"
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = 0.35
		trail.LightEmission = 1
		trail.Color = ColorSequence.new(Color3.fromRGB(255, 40, 30))
		trail.Transparency = NumberSequence.new(0.2, 1)
		trail.Enabled = false
		trail.Parent = hrp
	end
	giveKillerTool(killer, hum)
end

abilityEvent.OnServerEvent:Connect(function(p)
	if not matchActive or p ~= killer or not killerChar then return end
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	local now = serverNow()
	if now < (p:GetAttribute("AbilityReadyAt") or 0) then return end
	local ab = killerChar.ability
	p:SetAttribute("AbilityReadyAt", now + ab.cd)
	p:SetAttribute("AbilityUntil", now + ab.dur)
	if ab.id == "dash" then
		dashUntil = os.clock() + ab.dur
		local trail = char:FindFirstChild("DashTrail", true)
		if trail then
			trail.Enabled = true
			task.delay(ab.dur + 0.2, function()
				if trail.Parent then trail.Enabled = false end
			end)
		end
		fxEvent:FireClient(p, "dash", ab.dur)
	elseif ab.id == "reveal" then
		fxEvent:FireClient(p, "reveal", ab.dur)
		for _, e in ipairs(survivorList) do
			if e.status == "alive" then fxEvent:FireClient(e.player, "static", 1.6) end
		end
	elseif ab.id == "vanish" then
		vanishUntil = os.clock() + ab.dur
		setVanish(true)
		fxEvent:FireClient(p, "vanish", ab.dur)
		for _, e in ipairs(survivorList) do
			if e.status == "alive" then fxEvent:FireClient(e.player, "giggle") end
		end
	end
end)

------------------------------------------------------------------------
-- ЖЕТОНЫ
------------------------------------------------------------------------
local function clearTokens()
	for _, t in ipairs(activeTokens) do
		if t.part.Parent then t.part:Destroy() end
		if t.pillar.Parent then t.pillar:Destroy() end
	end
	activeTokens = {}
end

local function spawnTokens(def, count)
	clearTokens()
	local folder = def.dynamic:FindFirstChild("Tokens")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Tokens"
		folder.Parent = def.dynamic
	end
	local spots = table.clone(def.tokenSpots)
	shuffle(spots)
	for i = 1, math.min(count, #spots) do
		local pos = spots[i]
		local coin = mk(folder, "Token", Vector3.new(0.6, 3, 3), CFrame.new(pos + Vector3.new(0, 2.6, 0)), GOLD, M.Neon,
			{ Shape = CYL, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
		pointLight(coin, GOLD, 12, 1.4)
		surfaceText(coin, Enum.NormalId.Right, "P", { font = Enum.Font.Arcade, color = Color3.fromRGB(150, 70, 0), pps = 40 })
		surfaceText(coin, Enum.NormalId.Left, "2", { font = Enum.Font.Arcade, color = Color3.fromRGB(150, 70, 0), pps = 40 })
		tag(coin, "P2D_Token")
		local pillar = mk(folder, "TokenPillar", Vector3.new(26, 0.5, 0.5), CFrame.new(pos + Vector3.new(0, 16, 0)) * VERT, GOLD, M.Neon,
			{ Shape = CYL, Transparency = 0.8, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
		table.insert(activeTokens, { part = coin, pillar = pillar, pos = coin.Position })
	end
end

local function checkTokens()
	if #activeTokens == 0 then return end
	for _, e in ipairs(survivorList) do
		if e.status == "alive" then
			local hrp = e.player.Character and e.player.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				for i = #activeTokens, 1, -1 do
					local t = activeTokens[i]
					if (hrp.Position - t.pos).Magnitude <= CONFIG.TOKEN_RADIUS then
						t.part:Destroy()
						t.pillar:Destroy()
						table.remove(activeTokens, i)
						tokensGot += 1
						e.tokens += 1
						gameState:SetAttribute("Tokens", tokensGot)
						fxEvent:FireClient(e.player, "token", tokensGot, tokensNeeded)
						publishRoster()
					end
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- ПРОВЕРКА ПОБЕГА (работает только на открытом выходе)
------------------------------------------------------------------------
local function checkEscapes(def)
	for _, e in ipairs(survivorList) do
		if e.status == "alive" then
			local char = e.player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then
				for _, esc in ipairs(def.escapes) do
					if esc.zone:GetAttribute("Active") then
						local d = hrp.Position - esc.zone.Position
						if Vector3.new(d.X, 0, d.Z).Magnitude <= CONFIG.ESCAPE_RADIUS and math.abs(d.Y) <= 12 then
							markEscaped(e)
							break
						end
					end
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- ВОЗВРАТ В ЛОББИ
------------------------------------------------------------------------
local function returnAllToLobby()
	for _, p in ipairs(Players:GetPlayers()) do
		p:SetAttribute("InMatch", false)
		p:SetAttribute("Status", nil)
		p:SetAttribute("Role", nil)
		p:SetAttribute("Port", nil)
		p:SetAttribute("AbilityReadyAt", nil)
		p:SetAttribute("AbilityUntil", nil)
		p:SetAttribute("Kills", nil)
		pcall(function() p.ReplicationFocus = nil end)
		task.spawn(function()
			pcall(function() p:LoadCharacter() end) -- спавн в лобби, сброс инструментов/света/скорости/внешности
		end)
	end
end

------------------------------------------------------------------------
-- ЛОББИ: голосование за картридж и таймер
------------------------------------------------------------------------
local function updateVotes()
	local counts = {}
	for _, info in ipairs(MAP_INFO) do counts[info.key] = 0 end
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and p:GetAttribute("InMatch") ~= true then
			for _, pad in ipairs(lobbyPads) do
				local d = hrp.Position - pad.center
				if math.abs(d.X) <= pad.hx and math.abs(d.Z) <= pad.hz and d.Y > -2 and d.Y < 10 then
					if p:GetAttribute("Vote") ~= pad.key then p:SetAttribute("Vote", pad.key) end
				end
			end
		end
		local v = p:GetAttribute("Vote")
		if v and counts[v] then counts[v] += 1 end
	end
	for _, pad in ipairs(lobbyPads) do
		local n = counts[pad.key]
		pad.label.Text = "ГОЛОСОВ: " .. n
		pad.pad.Transparency = n > 0 and 0.12 or 0.5
	end
	gameState:SetAttribute("Votes", HttpService:JSONEncode(counts))
	return counts
end

task.spawn(function()
	while true do
		task.wait(0.4)
		local ok, err = pcall(updateVotes)
		if not ok then warn("[P2D] голосование: " .. tostring(err)) end
	end
end)

local function pickMap()
	local counts = updateVotes()
	local best, pool = 0, {}
	for _, info in ipairs(MAP_INFO) do
		local n = counts[info.key] or 0
		if n > best then
			best, pool = n, { info.key }
		elseif n == best and n > 0 then
			table.insert(pool, info.key)
		end
	end
	if best == 0 then
		pool = {}
		for _, info in ipairs(MAP_INFO) do
			if info.key ~= lastMap then table.insert(pool, info.key) end
		end
	end
	return pool[rng:NextInteger(1, #pool)]
end

local function runCountdown()
	setPhase("Countdown")
	for t = CONFIG.LOBBY_COUNTDOWN, 1, -1 do
		if #Players:GetPlayers() < CONFIG.MIN_PLAYERS then return nil end
		gameState:SetAttribute("TimeLeft", t)
		task.wait(1)
	end
	if #getReadyPlayers() < CONFIG.MIN_PLAYERS then return nil end
	local mapKey = pickMap()
	gameState:SetAttribute("MapKey", mapKey)
	announce("КАРТРИДЖ ВЫБРАН: " .. MAP_BY_KEY[mapKey].name, "info")
	return mapKey
end

------------------------------------------------------------------------
-- ВЫБОР ПЕРСОНАЖА НА СЦЕНЕ
------------------------------------------------------------------------
local selRoles = {}    -- [player] = "Survivor" | "Killer": роль известна ДО выбора, у каждой роли своя таблица
local picks = {}       -- [charId] = player
local pickOf = {}      -- [player] = charId
local stageOrder = {}  -- выжившие в порядке ПЕРВОГО выбора = места P1..P6 слева направо
local waitIndex = {}   -- [player] = место в закулисье
local selLocked = false

local function rootOffset(char)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hum and hrp and hum.RigType == Enum.HumanoidRigType.R15 then
		return hum.HipHeight + hrp.Size.Y / 2
	end
	return 3
end

local function standAt(p, footPos)
	local char = p.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local pos = footPos + Vector3.new(0, rootOffset(char) + 0.05, 0)
	hrp.Anchored = true
	char:PivotTo(CFrame.lookAt(pos, pos + Vector3.new(0, 0, -1))) -- лицом к камере
end

local function slotFoot(i)
	return STAGE + Vector3.new(SLOT_X[i], PODIUM_H, 0)
end

local function restage(p)
	local role = selRoles[p]
	if not role or p.Parent ~= Players then return end
	if role == "Killer" then
		standAt(p, HOLD_KILLER)
		return
	end
	local idx = table.find(stageOrder, p)
	if idx then
		standAt(p, slotFoot(idx))
	else
		standAt(p, HOLD_SURV + Vector3.new(-15 + (waitIndex[p] or 1) * 4, 0, 0))
	end
end

-- прожектор: щелчок включения с коротким миганием
local function setSlotLight(i, on, color)
	local s = slots[i]
	s.token += 1
	local my = s.token
	if not on then
		s.spot.Enabled = false
		s.beam.Enabled = false
		s.pool.Transparency = 1
		s.lens.Color = LENS_OFF
		return
	end
	local col = SPOT_WARM:Lerp(color, 0.35)
	s.spot.Color = col
	s.beam.Color = ColorSequence.new(col)
	s.pool.Color = col
	task.spawn(function()
		for k, v in ipairs({ true, false, true, false, true }) do
			if s.token ~= my then return end
			s.spot.Enabled = v
			s.beam.Enabled = v
			s.pool.Transparency = v and 0.55 or 1
			s.lens.Color = v and col or LENS_OFF
			if k < 5 then task.wait(0.06 + k * 0.01) end
		end
	end)
end

local function refreshPodiums()
	for i = 1, CONFIG.MAX_SURVIVORS do
		local p = stageOrder[i]
		local c = p and CHAR_BY_ID[pickOf[p]]
		local s = slots[i]
		if c then
			local col = charColor(c)
			s.charText.Text = c.name
			s.charText.TextColor3 = Color3.new(1, 1, 1)
			s.nameText.Text = p.DisplayName
			s.plate.BackgroundColor3 = col:Lerp(BLACK, 0.55)
			s.ring.Color = col
			s.ring.Material = M.Neon
			if s.litId ~= c.id then
				s.litId = c.id
				setSlotLight(i, true, col)
			end
		else
			s.charText.Text = "СВОБОДНО"
			s.charText.TextColor3 = Color3.fromRGB(120, 116, 124)
			s.nameText.Text = ""
			s.plate.BackgroundColor3 = Color3.fromRGB(16, 14, 18)
			s.ring.Color = Color3.fromRGB(50, 46, 54)
			s.ring.Material = M.SmoothPlastic
			if s.litId then
				s.litId = nil
				setSlotLight(i, false)
			end
		end
	end
end

local function publishStage()
	local s = {}
	for i, p in ipairs(stageOrder) do
		s[i] = { u = p.UserId, n = p.DisplayName, c = pickOf[p] }
	end
	local k = nil
	for p, role in pairs(selRoles) do
		if role == "Killer" and p.Parent == Players then
			k = { u = p.UserId, n = p.DisplayName, c = pickOf[p] }
		end
	end
	gameState:SetAttribute("Stage", HttpService:JSONEncode({ s = s, k = k }))
	local t = {}
	for id in pairs(picks) do table.insert(t, id) end
	gameState:SetAttribute("Taken", HttpService:JSONEncode(t))
	refreshPodiums()
end

local function resetPicks()
	picks, pickOf, stageOrder, waitIndex = {}, {}, {}, {}
	selLocked = false
	gameState:SetAttribute("SelectLocked", false)
	publishStage()
end

local function setPick(p, id)
	local old = pickOf[p]
	if old then picks[old] = nil end
	picks[id] = p
	pickOf[p] = id
	if selRoles[p] == "Survivor" and not table.find(stageOrder, p) then
		table.insert(stageOrder, p) -- место на сцене = порядок первого выбора
	end
	if p.Character then applyLook(p.Character, CHAR_BY_ID[id]) end
	restage(p)
	publishStage()
	pickStateEvent:FireClient(p, id)
end

local function freezePlayers(on, only)
	for _, p in ipairs(Players:GetPlayers()) do
		if not only or only[p] then
			local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.WalkSpeed = on and 0 or 16
				hum.JumpPower = on and 0 or 50
				hum.JumpHeight = on and 0 or 7.2
			end
		end
	end
end

-- роли: один Палач (случайный игрок, не повторяя прошлого) и до 6 выживших
local function pickRoles()
	selRoles = {}
	local ready = getReadyPlayers()
	shuffle(ready)
	if #ready >= 2 then
		local idx = (ready[1] == lastKiller) and 2 or 1
		selRoles[table.remove(ready, idx)] = "Killer"
	end
	for i, p in ipairs(ready) do
		if i <= CONFIG.MAX_SURVIVORS then
			selRoles[p] = "Survivor"
			waitIndex[p] = i
		end
	end
end

local function participantsLeft()
	local n = 0
	for p in pairs(selRoles) do
		if p.Parent == Players then n += 1 end
	end
	return n
end

pickEvent.OnServerEvent:Connect(function(p, id)
	if gameState:GetAttribute("Phase") ~= "Selection" or selLocked then return end
	local role = selRoles[p]
	if not role or type(id) ~= "string" then return end
	local c = CHAR_BY_ID[id]
	if not c or c.killer ~= (role == "Killer") then return end -- чужая таблица
	if picks[id] and picks[id] ~= p then
		pickStateEvent:FireClient(p, pickOf[p]) -- занято: возвращаем актуальный выбор
		return
	end
	if pickOf[p] == id then return end
	setPick(p, id)
end)

-- все участники выбрали
local function allPicked()
	local total = 0
	for p in pairs(selRoles) do
		if p.Parent == Players then
			total += 1
			if not pickOf[p] then return false end
		end
	end
	return total > 0
end

-- итоговые назначения: [player] = charId
local function resolveAssignments()
	local assigned = {}
	for p, role in pairs(selRoles) do
		if p.Parent == Players then
			local id = pickOf[p]
			if id and CHAR_BY_ID[id] and CHAR_BY_ID[id].killer == (role == "Killer") then
				assigned[p] = id
			end
		end
	end
	local used = {}
	for _, id in pairs(assigned) do used[id] = true end
	local freeSurvivors, freeKillers = {}, {}
	for _, c in ipairs(CHARACTERS) do
		if not used[c.id] then
			table.insert(c.killer and freeKillers or freeSurvivors, c.id)
		end
	end
	shuffle(freeSurvivors)
	shuffle(freeKillers)
	-- кто не выбрал — получает случайного свободного из СВОЕЙ таблицы
	for p, role in pairs(selRoles) do
		if p.Parent == Players and not assigned[p] then
			local pool = role == "Killer" and freeKillers or freeSurvivors
			if #pool > 0 then assigned[p] = table.remove(pool) end
		end
	end
	return assigned
end

local function runSelection()
	resetPicks()
	pickRoles()
	if participantsLeft() < CONFIG.MIN_PLAYERS then return false end
	for p, role in pairs(selRoles) do
		p:SetAttribute("Role", role)
		pickStateEvent:FireClient(p, nil, role) -- клиент узнаёт свою таблицу
	end
	publishStage()
	freezePlayers(true, selRoles)

	setPhase("ToSelection")                      -- клиенты гасят экран
	gameState:SetAttribute("TimeLeft", 0)
	task.wait(CONFIG.FADE_TIME)
	for p in pairs(selRoles) do restage(p) end   -- переезд на сцену под чёрным экраном
	setPhase("Selection")

	local endAt = os.clock() + CONFIG.SELECT_TIME
	local shortened = false
	local lastShown = -1
	while true do
		task.wait(0.1)
		if participantsLeft() < CONFIG.MIN_PLAYERS then return false end
		if not shortened and allPicked() then
			shortened = true
			endAt = math.min(endAt, os.clock() + CONFIG.SELECT_SHORT) -- все выбрали: остаётся 3 секунды
		end
		local rem = math.max(0, math.ceil(endAt - os.clock()))
		if rem ~= lastShown then
			lastShown = rem
			gameState:SetAttribute("TimeLeft", rem)
		end
		if rem <= 0 then break end
	end

	-- кто не успел — получает случайного героя и тоже выходит на сцену
	selLocked = true
	gameState:SetAttribute("SelectLocked", true)
	local assigned = resolveAssignments()
	local late = {}
	for p, id in pairs(assigned) do
		if not pickOf[p] then table.insert(late, { p, id }) end
	end
	shuffle(late)
	for _, it in ipairs(late) do setPick(it[1], it[2]) end
	publishStage()
	task.wait(CONFIG.REVEAL_TIME)
	return participantsLeft() >= CONFIG.MIN_PLAYERS
end

-- +время за убийство; клиент по BonusSeq плавно краснит часы
local function addMatchTime(sec)
	matchEndAt += sec
	gameState:SetAttribute("BonusSeq", (gameState:GetAttribute("BonusSeq") or 0) + 1)
end

------------------------------------------------------------------------
-- МАТЧ
------------------------------------------------------------------------
local function cleanupMatchState()
	matchActive = false
	if vanishSaved then setVanish(false) end
	dashUntil, vanishUntil = 0, 0
	for _, c in ipairs(matchConns) do c:Disconnect() end
	matchConns = {}
	for p in pairs(stamina) do clearStamina(p) end
	boostUntil = {}
	clearTokens()
	gameState:SetAttribute("Tokens", 0)
	gameState:SetAttribute("TokensNeeded", 0)
	gameState:SetAttribute("ExitName", "")
end

local function runMatch(mapKey)
	local def = MAPS[mapKey]
	local assigned = resolveAssignments()
	local killerP = nil
	for p, id in pairs(assigned) do
		if CHAR_BY_ID[id].killer then killerP = p end
	end
	-- выжившие в порядке мест на сцене (P1..P6)
	local picked = {}
	local seen = {}
	for i, p in ipairs(stageOrder) do
		local id = assigned[p]
		if id and not CHAR_BY_ID[id].killer then
			table.insert(picked, { player = p, char = CHAR_BY_ID[id], port = i })
			seen[p] = true
		end
	end
	for p, id in pairs(assigned) do
		if not seen[p] and not CHAR_BY_ID[id].killer then
			table.insert(picked, { player = p, char = CHAR_BY_ID[id], port = #picked + 1 })
		end
	end
	if #picked == 0 or #picked + (killerP and 1 or 0) < CONFIG.MIN_PLAYERS then
		return false
	end

	if def.prepare then def.prepare(rng:NextInteger(1, 1000000)) end
	currentDef = def
	lastMap = mapKey
	killer = killerP
	lastKiller = killerP
	killerChar = killerP and CHAR_BY_ID[assigned[killerP]] or nil
	killerMods = killerChar and killerModsOf(killerChar) or nil
	kills = 0
	freezePlayers(false)

	for _, p in ipairs(Players:GetPlayers()) do
		p:SetAttribute("InMatch", false)
		p:SetAttribute("Status", nil)
		p:SetAttribute("Vote", nil)
	end
	survivorList, entryOf = {}, {}
	for _, it in ipairs(picked) do
		local e = {
			player = it.player, userId = it.player.UserId, charId = it.char.id, port = it.port,
			name = it.char.name, dname = it.player.DisplayName, char = it.char, status = "alive", tokens = 0,
		}
		table.insert(survivorList, e)
		entryOf[it.player] = e
		it.player:SetAttribute("InMatch", true)
		it.player:SetAttribute("Status", "alive")
		it.player:SetAttribute("Role", "Survivor")
		it.player:SetAttribute("Port", it.port)
	end
	if killer then
		killer:SetAttribute("InMatch", true)
		killer:SetAttribute("Status", "alive")
		killer:SetAttribute("Role", "Killer")
		killer:SetAttribute("Port", nil)
		killer:SetAttribute("Kills", 0)
		killer:SetAttribute("AbilityReadyAt", serverNow() + CONFIG.ABILITY_FIRST_DELAY)
		killer:SetAttribute("AbilityUntil", 0)
	end

	-- таймер матча: 1 минута + 1 минута за каждого выжившего
	local total = #survivorList
	local matchTime = CONFIG.BASE_MATCH_TIME + CONFIG.TIME_PER_SURVIVOR * total
	tokensGot = 0
	tokensNeeded = math.clamp(CONFIG.TOKENS_BASE + CONFIG.TOKENS_PER_SURVIVOR * total, 1, CONFIG.TOKENS_MAX)
	spawnTokens(def, tokensNeeded + CONFIG.TOKENS_EXTRA)
	tokensNeeded = math.min(tokensNeeded, #activeTokens)
	gameState:SetAttribute("Tokens", 0)
	gameState:SetAttribute("TokensNeeded", tokensNeeded)
	gameState:SetAttribute("MapKey", mapKey)

	resetEscapes(def)
	gameState:SetAttribute("EscapeOpen", false)
	gameState:SetAttribute("ExitName", "")
	gameState:SetAttribute("TimeLeft", matchTime)
	publishRoster()

	-- подгрузка мест спавна (экран в это время чёрный)
	local streamList = {}
	for _, e in ipairs(survivorList) do
		e.spawn = def.survivorSpawns[rng:NextInteger(1, #def.survivorSpawns)]
		table.insert(streamList, { e.player, e.spawn.Position })
	end
	if killer then table.insert(streamList, { killer, def.killerSpawns[1].Position }) end
	preStream(streamList)

	for _, e in ipairs(survivorList) do
		local char = e.player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			local mods = survivorMods(e.char)
			char:PivotTo(spawnCFrame(e.spawn, def.origin))
			setRootAnchored(e.player, false)
			applyLook(char, e.char)
			hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			hum.MaxHealth = CONFIG.SURVIVOR_HEALTH * mods.hp
			hum.Health = hum.MaxHealth
			hum.WalkSpeed = CONFIG.SURVIVOR_SPEED * mods.speed
			addFlashlight(char)
			initStamina(e.player, false, mods)
			watchDamage(e.player, hum)
			table.insert(matchConns, hum.Died:Connect(function()
				-- убийство выжившего добавляет время (не за уход из игры и не за истечение времени)
				if e.status == "alive" and matchActive then
					addMatchTime(CONFIG.KILL_BONUS_TIME)
					kills += 1
					if killer then killer:SetAttribute("Kills", kills) end
				end
				markDead(e)
			end))
		else
			markDead(e)
		end
	end
	if killer then setupKiller() end

	matchActive = true
	matchEndAt = os.clock() + matchTime
	setPhase("Match") -- клиент «включает» экран и показывает заставку уровня

	-- основной цикл матча
	local lastShown = -1
	local escapesOpen = false
	local killerLeft = false
	local function openExit(byTokens)
		escapesOpen = true
		local e = openRandomEscape(def)
		gameState:SetAttribute("EscapeOpen", true)
		gameState:SetAttribute("ExitPos", e.zone.Position)
		gameState:SetAttribute("ExitName", e.label)
		if byTokens then
			matchEndAt = math.min(matchEndAt, os.clock() + CONFIG.TOKEN_OPEN_CAP)
			announce("ЖЕТОНЫ ВСТАВЛЕНЫ! ОТКРЫТ ВЫХОД: " .. e.label, "warn")
		else
			announce("ОТКРЫТ ВЫХОД: " .. e.label .. ". Ищите зелёный столб света!", "warn")
		end
	end
	while true do
		task.wait(0.2)
		local remaining = math.max(0, math.ceil(matchEndAt - os.clock()))
		if remaining ~= lastShown then
			lastShown = remaining
			gameState:SetAttribute("TimeLeft", remaining)
		end
		checkTokens()
		if not escapesOpen and (remaining <= CONFIG.ESCAPE_OPEN_AT or tokensGot >= tokensNeeded) then
			openExit(tokensGot >= tokensNeeded and remaining > CONFIG.ESCAPE_OPEN_AT)
		end
		checkEscapes(def)

		if killer and killer.Parent ~= Players then
			killerLeft = true
			break
		end
		if countStatus("alive") == 0 then break end -- все погибли/сбежали
		if remaining <= 0 then                        -- время вышло
			announce("ВРЕМЯ ВЫШЛО!", "warn")
			for _, e in ipairs(survivorList) do
				if e.status == "alive" then
					markDead(e, said(e, "не успел", "не успела") .. " сбежать")
					local h = e.player.Character and e.player.Character:FindFirstChildOfClass("Humanoid")
					if h then h.Health = 0 end
				end
			end
			break
		end
	end

	-- итоги
	cleanupMatchState()
	resetEscapes(def)
	gameState:SetAttribute("EscapeOpen", false)
	local escapedN = countStatus("escaped")
	local outcome
	if killerLeft then
		outcome = "left"
	elseif escapedN == 0 then
		outcome = "killer"
	elseif escapedN == total then
		outcome = "survivors"
	else
		outcome = "mixed"
	end
	local res = { o = outcome, esc = escapedN, total = total, map = mapKey, survivors = {} }
	for _, e in ipairs(survivorList) do
		table.insert(res.survivors, { n = e.dname, c = e.charId, s = e.status, t = e.tokens, p = e.port })
	end
	if killer and killerChar then
		res.killer = { n = killer.DisplayName, c = killerChar.id, k = kills }
	end
	resultsEvent:FireAllClients(res)
	setPhase("Ending")
	task.wait(CONFIG.ENDING_TIME)

	-- плавный возврат: экран гаснет -> лобби -> включается
	setPhase("Returning")
	task.wait(CONFIG.FADE_TIME)
	returnAllToLobby()
	resetPicks()
	survivorList, entryOf, killer, killerChar, killerMods, currentDef = {}, {}, nil, nil, nil, nil
	publishRoster()
	task.wait(1.5)
	return true
end

------------------------------------------------------------------------
-- СОБЫТИЯ ИГРОКОВ
------------------------------------------------------------------------
spectateEvent.OnServerEvent:Connect(function(p, userId)
	pcall(function()
		local target = typeof(userId) == "number" and Players:GetPlayerByUserId(userId) or nil
		local hrp = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
		p.ReplicationFocus = hrp
	end)
end)

local function onPlayerAdded(p)
	p:SetAttribute("InMatch", false)
	p.CharacterAdded:Connect(function(char)
		local ph = gameState:GetAttribute("Phase")
		if (ph == "Selection" or ph == "Starting") and selRoles[p] then
			-- переродился во время выбора — вернуть на сцену
			task.wait(0.3)
			if pickOf[p] then applyLook(char, CHAR_BY_ID[pickOf[p]]) end
			restage(p)
		elseif matchActive and p == killer then
			-- Палач возродился во время матча — вернуть на карту с оружием
			task.wait(0.5)
			setupKiller()
		end
	end)
end
Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do onPlayerAdded(p) end

Players.PlayerRemoving:Connect(function(p)
	if matchActive then
		local e = entryOf[p]
		if e then markDead(e, said(e, "покинул", "покинула") .. " игру") end
	end
	stamina[p] = nil
	boostUntil[p] = nil
	local picked = pickOf[p]
	if picked then
		picks[picked] = nil
		pickOf[p] = nil
	end
	local idx = table.find(stageOrder, p)
	if idx then
		-- места сдвигаются влево, чтобы сцена оставалась заполненной по порядку
		table.remove(stageOrder, idx)
		if gameState:GetAttribute("Phase") == "Selection" then
			for _, other in ipairs(stageOrder) do restage(other) end
		end
	end
	selRoles[p] = nil
	publishStage()
end)

------------------------------------------------------------------------
-- ГЛАВНЫЙ ЦИКЛ:
-- ожидание -> таймер лобби (голосование) -> сцена выбора -> матч -> итоги -> лобби
------------------------------------------------------------------------
local function backToLobby()
	setPhase("Waiting")
	freezePlayers(false)
	returnAllToLobby()
	resetPicks()
	selRoles = {}
	task.wait(1.5)
end

task.spawn(function()
	while true do
		setPhase("Waiting")
		gameState:SetAttribute("TimeLeft", 0)
		while #Players:GetPlayers() < CONFIG.MIN_PLAYERS do
			task.wait(1)
		end
		local mapKey = runCountdown()
		if mapKey then
			local okSel, selDone = pcall(runSelection)
			if okSel and selDone then
				setPhase("Starting") -- клиент гасит экран
				gameState:SetAttribute("TimeLeft", 0)
				task.wait(CONFIG.FADE_TIME)
				local ok, res = pcall(runMatch, mapKey)
				if not ok then
					warn("[P2D] Ошибка матча: " .. tostring(res))
					cleanupMatchState()
					for _, d in pairs(MAPS) do resetEscapes(d) end
					survivorList, entryOf, killer, killerChar, killerMods, currentDef = {}, {}, nil, nil, nil, nil
					publishRoster()
					backToLobby()
				elseif res == false then
					backToLobby()
				end
				selRoles = {}
			else
				if not okSel then warn("[P2D] Ошибка выбора: " .. tostring(selDone)) end
				backToLobby()
			end
		end
		task.wait(1)
	end
end)
