--[[
	PRESS2DIE — GameServer (Script)  ->  положить в ServerScriptService

	Асимметричный хоррор 1 vs все. Лор: люди заперты в проклятой приставке 90-х,
	но сама игра идёт в мрачных «классических» локациях — цифровая природа мира
	лишь угадывается (глитчи, ЭЛТ-телевизоры, помехи).

	Сервер строит всё кодом:
	  • ЛОББИ — заброшенный автокинотеатр в ночном лесу, экран показывает статус;
	  • СЦЕНА ВЫБОРА — старый театр: 6 подиумов с прожекторами, монитор Палача;
	  • КАРТЫ — «Туманный лес», «Комплекс» (завод, полностью закрытый), «Ферма» на закате.
	    Края скрыты холмами, лесом, туманом или стенами; выходы — ворота и двери в стенах,
	    которые открываются, когда до конца матча остаётся минута;
	  • ПЕРСОНАЖИ — мультяшные «костюмы» поверх аватара; роли выживших:
	    станнеры (Алекс, Айша), поддержка (Лилиан, Грег), одиночки (Оскар, Феликс);
	  • МАТЧ — способности (Q) у всех, оглушение Палача, выносливость, итоги, наблюдение.
	Интерфейс — в GameClient (LocalScript).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

------------------------------------------------------------------------
-- НАСТРОЙКИ
------------------------------------------------------------------------
local CONFIG = {
	MIN_PLAYERS = 2,          -- минимум игроков для старта (1 Палач + 1 выживший). Для одиночного теста поставь 1
	MAX_SURVIVORS = 6,        -- выживших в матче (+1 Палач = 7 игроков)
	LOBBY_COUNTDOWN = 30,     -- секунд лобби до старта
	BASE_MATCH_TIME = 60,     -- матч = 60 c + 60 c * число выживших
	TIME_PER_SURVIVOR = 60,
	ESCAPE_OPEN_AT = 60,      -- выход открывается, когда до конца осталось <= 60 c
	ESCAPE_RADIUS = 7,        -- радиус зоны выхода
	ENDING_TIME = 9,          -- экран итогов перед возвратом в лобби
	SELECT_TIME = 25,         -- секунд на выбор персонажа
	SELECT_SHORT = 3,         -- когда все выбрали, остаток времени сокращается до этого значения
	REVEAL_TIME = 2,          -- пауза «все на сцене» перед матчем
	KILL_BONUS_TIME = 20,     -- +секунд к матчу за убийство выжившего
	FADE_TIME = 1.2,          -- пауза под затемнение между этапами
	BUILD = "2026.10.09-b",   -- версия сборки: клиент сверяет её со своей и предупреждает о старом GameClient
	LOBBY_SPEED = 16,         -- шаг в лобби (быстрый, как раньше)
	SURVIVOR_SPEED = 14,      -- шаг в раунде (снижен, чтобы бег и ускорения ощущались отчётливо)
	KILLER_SPEED = 16,
	SURVIVOR_SPRINT_SPEED = 23,
	KILLER_SPRINT_SPEED = 25,
	STAMINA_MAX_KILLER = 125,
	STAMINA_DRAIN = 20,
	STAMINA_REGEN = 14,
	STAMINA_REGEN_DELAY = 1.5,
	STAMINA_RECOVER_FRACTION = 0.25,
	HIT_BOOST_MULT = 1.35,    -- ускорение после удара Палача
	HIT_BOOST_TIME = 3,
	KILLER_DAMAGE = 34,       -- 3 удара убивают выжившего со 100 здоровья
	KILLER_RANGE = 8,
	KILLER_COOLDOWN = 1.2,
	DASH_SPEED = 62,          -- скорость Палача во время «Рывка»
	KILLER_FIRST_ABILITY = 8, -- навык Палача готов через N секунд после старта
	SURVIVOR_FIRST_ABILITY = 12,
	STUN_IMMUNITY = 6,        -- после оглушения Палач N секунд не оглушается снова
	-- навыки выживших (подробности — в таблице CHARACTERS)
	PUNCH_RANGE = 7, PUNCH_STUN = 2,                       -- Алекс: «Удар»
	COUNTER_STUN = 3,                                      -- Алекс: «Контр-удар»
	ADRENALINE_MULT = 1.3, ADRENALINE_WINDED = 1,          -- Оскар: «Адреналин» (+30% и 1 с одышки)
	WINDED_MULT = 0.6,
	HEAL_AMOUNT = 50, HEAL_RADIUS = 8,                     -- Лилиан: «Лечение» (союзник жмёт F рядом с ней)
	SELFHEAL_AMOUNT = 35,                                  -- Лилиан: «Самолечение»
	STATION_RADIUS = 9, STATION_HEAL = 5, STATION_SPEED = 1.2, -- Грег: станция лечения (ед./с) или ускорения
	TRIPWIRE_SLOW = 0.6, TRIPWIRE_TIME = 1.1, TRIPWIRE_MAX = 2, TRIPWIRE_LIFE = 90, -- Грег: «Растяжка»
	BAT_RANGE = 8, BAT_WINDUP = 0.45, BAT_STUN = 1.5, BAT_SLOW = 0.35, BAT_SLOW_TIME = 2, -- Айша: «Бита»
	FLASH_RANGE = 22, FLASH_BLIND = 1.5,                   -- Айша: «Вспышка»
	MANA_REGEN = 1.5, TK_RANGE = 45, TK_SLOW_TIME = 3,     -- Феликс: мана (макс. в CHARACTERS) и «Телекинез»
	SHIELD_STUN = 2, SHIELD_PUSH = 75, SHIELD_PUSH_RADIUS = 12, -- Феликс: «Силовой щит»
	LOBBY_POS = Vector3.new(-3000, 0, 0),
	STAGE_POS = Vector3.new(0, 900, -3000),
}

local M = Enum.Material
local rng = Random.new()
local VERT = CFrame.Angles(0, 0, math.rad(90))   -- ставит цилиндр вертикально
local ALONG_Z = CFrame.Angles(0, math.rad(90), 0) -- ось цилиндра вдоль Z (lookAt)
local DOOR_H = 9
local NOCOL = { CanCollide = false, CanQuery = false, CastShadow = false }
local FLAT = { CanCollide = false, CanQuery = false, CastShadow = false, CanTouch = false }
local CYL = Enum.PartType.Cylinder
local BALL = Enum.PartType.Ball
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local GREEN = Color3.fromRGB(80, 255, 120)
local LAMP_RED = Color3.fromRGB(255, 50, 40)
local Terrain = Workspace:FindFirstChildOfClass("Terrain")

------------------------------------------------------------------------
-- ОКРУЖЕНИЕ
------------------------------------------------------------------------
for _, o in ipairs(Workspace:GetChildren()) do
	if o:IsA("SpawnLocation") or o.Name == "Baseplate" then o:Destroy() end
end

Lighting.ClockTime = 0
Lighting.Brightness = 1
Lighting.Ambient = Color3.fromRGB(40, 44, 52)
Lighting.OutdoorAmbient = Color3.fromRGB(36, 40, 56)
Lighting.FogColor = Color3.fromRGB(8, 10, 14)
Lighting.FogStart = 40
Lighting.FogEnd = 300
do
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atm then
		atm = Instance.new("Atmosphere")
		atm.Parent = Lighting
	end
	atm.Density = 0.35
	atm.Offset = 0.1
	atm.Color = Color3.fromRGB(40, 45, 60)
	atm.Decay = Color3.fromRGB(20, 20, 30)
	atm.Haze = 2
end
Players.RespawnTime = 3
-- без прыжков и без встроенного shift-lock: Shift — это бег, свой shift-lock на Ctrl делает клиент
do
	local sp = game:GetService("StarterPlayer")
	sp.CharacterWalkSpeed = CONFIG.LOBBY_SPEED
	sp.CharacterUseJumpPower = true
	sp.CharacterJumpPower = 0
	sp.CharacterJumpHeight = 0
	sp.EnableMouseLockOption = false
end

-- цвета материалов ландшафта (общие для всех карт, поэтому у каждой карты свои материалы)
if Terrain then
	pcall(function()
		Terrain:SetMaterialColor(M.Grass, Color3.fromRGB(34, 48, 30))       -- лес / лобби
		Terrain:SetMaterialColor(M.Mud, Color3.fromRGB(52, 42, 32))         -- лесные тропы
		Terrain:SetMaterialColor(M.Rock, Color3.fromRGB(58, 58, 62))        -- скалы
		Terrain:SetMaterialColor(M.Ground, Color3.fromRGB(96, 74, 48))      -- дорожки фермы
		Terrain:SetMaterialColor(M.LeafyGrass, Color3.fromRGB(124, 104, 58)) -- сухая трава фермы
		Terrain:SetMaterialColor(M.Asphalt, Color3.fromRGB(34, 34, 38))     -- площадка кинотеатра
		Terrain:SetMaterialColor(M.Sandstone, Color3.fromRGB(110, 84, 58))  -- холмы фермы
	end)
end

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
local abilityEvent = remote("Ability")        -- клиент: способность (Q)
local fxEvent = remote("Fx")                  -- сервер: эффекты для конкретного игрока
local resultsEvent = remote("Results")        -- сервер: итоги матча
local spectateEvent = remote("Spectate")      -- клиент: за кем наблюдаю (для стриминга)
-- клиент сообщает номер своей сборки: так видно, что GameClient запущен и не устарел
remote("Hello").OnServerEvent:Connect(function(p, build)
	p:SetAttribute("P2D_ClientBuild", tostring(build))
	if build ~= CONFIG.BUILD then
		warn(string.format("[P2D] У %s GameClient сборки %s, а GameServer — %s. Замени LocalScript GameClient целиком.", p.Name, tostring(build), CONFIG.BUILD))
	end
end)
gameState:SetAttribute("Build", CONFIG.BUILD)
print("[P2D] GameServer, сборка " .. CONFIG.BUILD)

gameState:SetAttribute("Phase", "Waiting") -- Waiting | Countdown | ToSelection | Selection | Starting | Match | Ending | Returning
gameState:SetAttribute("TimeLeft", 0)
gameState:SetAttribute("EscapeOpen", false)
gameState:SetAttribute("MinPlayers", CONFIG.MIN_PLAYERS)
gameState:SetAttribute("Roster", "[]")
gameState:SetAttribute("Killer", "{}")
gameState:SetAttribute("Stage", "{}")
gameState:SetAttribute("Taken", "[]")
gameState:SetAttribute("MapKey", "")
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
	return mk(parent, name, Vector3.new(h, d, d), cf * VERT, color, mat, withShape(opts, CYL))
end

local function ball(parent, name, d, pos, color, mat, opts)
	return mk(parent, name, Vector3.new(d, d, d), pos, color, mat, withShape(opts, BALL))
end

-- деталь по двум углам относительно точки o
local function box(parent, o, name, x1, x2, y1, y2, z1, z2, color, mat, opts)
	return mk(parent, name, Vector3.new(x2 - x1, y2 - y1, z2 - z1),
		o + Vector3.new((x1 + x2) / 2, (y1 + y2) / 2, (z1 + z2) / 2), color, mat, opts)
end

-- деталь-отрезок между двумя точками (балки, ножки, тросы)
local function beam(parent, name, a, b, th, color, mat, opts)
	local len = (b - a).Magnitude
	local mid = (a + b) / 2
	local cf
	if math.abs((b - a).Unit.Y) > 0.999 then
		cf = CFrame.new(mid)
	else
		cf = CFrame.lookAt(mid, b) * CFrame.Angles(math.rad(90), 0, 0)
	end
	return mk(parent, name, Vector3.new(th, len, th), cf, color, mat, opts)
end

local function tag(inst, name, attrs)
	CollectionService:AddTag(inst, name)
	if attrs then
		for k, v in pairs(attrs) do inst:SetAttribute(k, v) end
	end
	return inst
end

local function pointLight(part, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Parent = part
	return l
end

local function spotLight(part, face, color, range, angle, brightness)
	local l = Instance.new("SpotLight")
	l.Face = face
	l.Color = color
	l.Range = range
	l.Angle = angle
	l.Brightness = brightness
	l.Parent = part
	return l
end

-- приваривает декоративную деталь к опорной (двигается вместе с ней)
local function weldTo(part, base)
	part.Anchored = false
	part.Massless = true
	local w = Instance.new("WeldConstraint")
	w.Part0 = base
	w.Part1 = part
	w.Parent = part
	return part
end

local function wallSeg(parent, a, b, h, thick, color, mat)
	local len = (b - a).Magnitude
	if len < 0.05 then return end
	local alongX = math.abs(b.X - a.X) > math.abs(b.Z - a.Z)
	local size = alongX and Vector3.new(len, h, thick) or Vector3.new(thick, h, len)
	return mk(parent, "Wall", size, (a + b) / 2 + Vector3.new(0, h / 2, 0), color, mat)
end

-- стена от a до b с проёмами: gaps = { {t = расстояние от a до центра проёма, w = ширина, h = высота} }
local function wallWithGaps(parent, a, b, h, thick, color, mat, gaps)
	local dir = (b - a).Unit
	local len = (b - a).Magnitude
	local alongX = math.abs(dir.X) > 0.5
	table.sort(gaps, function(x, y) return x.t < y.t end)
	local cur = 0
	for _, g in ipairs(gaps) do
		local s = g.t - g.w / 2
		if s > cur then wallSeg(parent, a + dir * cur, a + dir * s, h, thick, color, mat) end
		if h > g.h then
			local lh = h - g.h
			local size = alongX and Vector3.new(g.w, lh, thick) or Vector3.new(thick, lh, g.w)
			mk(parent, "Lintel", size, a + dir * g.t + Vector3.new(0, g.h + lh / 2, 0), color, mat)
		end
		cur = g.t + g.w / 2
	end
	if cur < len then wallSeg(parent, a + dir * cur, b, h, thick, color, mat) end
end

-- прямоугольная комната (координаты относительно o) с проёмами:
-- gaps = { N = { {c = координата центра проёма вдоль стены, w, h} }, S = ..., W = ..., E = ... }
local function room(parent, o, x1, x2, z1, z2, h, color, mat, gaps, opts)
	opts = opts or {}
	gaps = gaps or {}
	local t = opts.thick or 1.6
	local function conv(list, start)
		local out = {}
		for _, g in ipairs(list or {}) do
			table.insert(out, { t = math.abs(g.c - start), w = g.w or 7, h = g.h or DOOR_H })
		end
		return out
	end
	local y = opts.y or 0
	local function P(x, z) return o + Vector3.new(x, y, z) end
	wallWithGaps(parent, P(x1 - t / 2, z1), P(x2 + t / 2, z1), h, t, color, mat, conv(gaps.N, x1 - t / 2))
	wallWithGaps(parent, P(x1 - t / 2, z2), P(x2 + t / 2, z2), h, t, color, mat, conv(gaps.S, x1 - t / 2))
	wallWithGaps(parent, P(x1, z1), P(x1, z2), h, t, color, mat, conv(gaps.W, z1))
	wallWithGaps(parent, P(x2, z1), P(x2, z2), h, t, color, mat, conv(gaps.E, z1))
	if not opts.noRoof then
		box(parent, o, "Roof", x1 - t / 2, x2 + t / 2, y + h, y + h + 1, z1 - t / 2, z2 + t / 2, opts.roofColor or color, opts.roofMat or mat)
	end
	if opts.lamp ~= false then
		local lamp = box(parent, o, "Lamp", (x1 + x2) / 2 - 1.5, (x1 + x2) / 2 + 1.5, y + h - 0.4, y + h, (z1 + z2) / 2 - 1.5, (z1 + z2) / 2 + 1.5,
			Color3.fromRGB(255, 225, 180), M.Neon, NOCOL)
		pointLight(lamp, opts.lampColor or Color3.fromRGB(255, 190, 130), math.max(x2 - x1, z2 - z1) * 0.9, opts.lampBrightness or 1)
		if opts.flicker then tag(lamp, "P2D_Flicker") end
	end
end

-- двускатная крыша над прямоугольником (конёк вдоль Z, либо вдоль X при alongX)
local function gableRoof(parent, center, w, d, rise, color, mat, alongX, over)
	over = over or 1.5
	local rot = alongX and CFrame.Angles(0, math.rad(90), 0) or CFrame.identity
	if alongX then w, d = d, w end
	local base = CFrame.new(center) * rot
	local half = w / 2
	local slope = math.atan2(rise, half)
	local len = math.sqrt(half * half + rise * rise) + over
	for _, s in ipairs({ -1, 1 }) do
		mk(parent, "RoofSlab", Vector3.new(len, 0.7, d + over * 2),
			base * CFrame.new(s * half / 2, rise / 2, 0) * CFrame.Angles(0, 0, -s * slope), color, mat)
		-- фронтоны (треугольники из двух клиньев)
		for _, e in ipairs({ -1, 1 }) do
			mkc("WedgePart", parent, "Gable", Vector3.new(0.6, rise, half),
				base * CFrame.new(s * half / 2, rise / 2, e * (d / 2 - 0.3)) * CFrame.Angles(0, s * math.rad(-90), 0), color:Lerp(BLACK, 0.15), mat)
		end
	end
end

-- клин-пандус: dir — направление ПОДЪЁМА (к верхней точке)
local function ramp(parent, pos, w, h, len, dir, color, mat)
	local center = pos + Vector3.new(0, h / 2, 0)
	return mkc("WedgePart", parent, "Ramp", Vector3.new(w, h, len), CFrame.lookAt(center, center - dir), color, mat)
end

local function railing(parent, a, b, h, color)
	local len = (b - a).Magnitude
	if len < 0.5 then return end
	local dir = (b - a).Unit
	local n = math.max(1, math.floor(len / 4))
	for i = 0, n do
		local p = a + dir * (len * i / n)
		mk(parent, "RailPost", Vector3.new(0.3, h, 0.3), p + Vector3.new(0, h / 2, 0), color, M.Metal)
	end
	local cf = CFrame.lookAt((a + b) / 2, b)
	mk(parent, "Rail", Vector3.new(0.25, 0.25, len), cf + Vector3.new(0, h, 0), color, M.Metal)
	mk(parent, "Rail", Vector3.new(0.2, 0.2, len), cf + Vector3.new(0, h * 0.5, 0), color, M.Metal)
end

local function ladder(parent, pos, height)
	local h = math.max(2, math.floor(height / 2 + 0.5) * 2)
	return mkc("TrussPart", parent, "Ladder", Vector3.new(2, h, 2), pos + Vector3.new(0, h / 2, 0), Color3.fromRGB(70, 70, 76), M.Metal)
end

-- SurfaceGui с крупным текстом
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
	t.TextColor3 = o.color or WHITE
	t.TextStrokeTransparency = o.stroke or 1
	t.Text = text
	t.Parent = sg
	return t, sg
end

-- пиксель-арт из строк: символ -> цвет палитры, «.» — пусто. Соседние пиксели склеиваются.
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

------------------------------------------------------------------------
-- ЛАНДШАФТ И ПРИРОДА
------------------------------------------------------------------------
local function terra(method, ...)
	if not Terrain then return end
	local args = table.pack(...)
	pcall(function() Terrain[method](Terrain, table.unpack(args, 1, args.n)) end)
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
groundParams.FilterDescendantsInstances = Terrain and { Terrain } or {}
-- высота поверхности ландшафта в точке (для деревьев на холмах)
local function groundY(pos)
	local r = Workspace:Raycast(Vector3.new(pos.X, pos.Y + 150, pos.Z), Vector3.new(0, -300, 0), groundParams)
	return r and r.Position.Y or pos.Y
end

-- кольцо холмов вокруг игровой зоны: прячет край карты; exits = { {pos, normal} } — там прорубаются проходы
local function hillRing(o, dist, mats, r, exits, cutW)
	local balls = {}
	for t = -dist - 30, dist + 30, 26 do
		table.insert(balls, Vector3.new(t, 0, -dist))
		table.insert(balls, Vector3.new(t, 0, dist))
		table.insert(balls, Vector3.new(-dist, 0, t))
		table.insert(balls, Vector3.new(dist, 0, t))
	end
	for _, b in ipairs(balls) do
		local rad = r:NextNumber(34, 44)
		terra("FillBall", o + Vector3.new(b.X + r:NextNumber(-6, 6), -12 + r:NextNumber(-4, 4), b.Z + r:NextNumber(-6, 6)), rad, mats[r:NextInteger(1, #mats)])
	end
	-- проходы к воротам: дорога уходит в «туман» и упирается в дальний холм
	for _, e in ipairs(exits or {}) do
		local n = e.normal
		local size = Vector3.new(n.X ~= 0 and 90 or (cutW or 20), 60, n.Z ~= 0 and 90 or (cutW or 20))
		local c = o + e.pos - n * 45
		terra("FillBlock", CFrame.new(c.X, 30, c.Z), size, M.Air)
		terra("FillBall", o + e.pos - n * 105, 34, mats[1])
	end
end

local TRUNK = Color3.fromRGB(56, 40, 30)
local PINE = Color3.fromRGB(26, 44, 30)

-- ель из двух перекрещенных «А-образных» ярусов (низкополигональный силуэт)
local function pine(parent, pos, h, r, tiers)
	tiers = tiers or 3
	local trunkH = h * 0.5
	cyl(parent, "PineTrunk", trunkH, math.max(1, h * 0.05), pos + Vector3.new(0, trunkH / 2, 0), TRUNK, M.Wood)
	local col = PINE:Lerp(Color3.fromRGB(12, 26, 22), r:NextNumber(0, 0.6))
	local yaw0 = r:NextNumber(0, math.pi)
	for i = 1, tiers do
		local k = 1 - (i - 1) / (tiers + 0.5)
		local w = h * 0.46 * k
		local th = h * 0.42 * k
		local y = h * 0.22 + (i - 1) * h * 0.22 + th / 2
		for j = 0, 1 do
			local base = CFrame.new(pos + Vector3.new(0, y, 0)) * CFrame.Angles(0, yaw0 + j * math.pi / 2 + i * 0.4, 0)
			local size = Vector3.new(w * 0.55, th, w / 2)
			mkc("WedgePart", parent, "Needles", size, base * CFrame.new(0, 0, -w / 4), col, M.Grass, NOCOL)
			mkc("WedgePart", parent, "Needles", size, base * CFrame.new(0, 0, w / 4) * CFrame.Angles(0, math.pi, 0), col, M.Grass, NOCOL)
		end
	end
end

-- лиственное дерево: ствол + шапка из шаров
local function leafTree(parent, pos, h, r, palette)
	cyl(parent, "Trunk", h * 0.62, math.max(1, h * 0.07), pos + Vector3.new(0, h * 0.31, 0), Color3.fromRGB(64, 46, 32), M.Wood)
	beam(parent, "Branch", pos + Vector3.new(0, h * 0.45, 0), pos + Vector3.new(h * 0.18, h * 0.62, h * 0.05), h * 0.035, Color3.fromRGB(64, 46, 32), M.Wood)
	for _ = 1, 5 do
		local d = h * r:NextNumber(0.3, 0.46)
		local off = Vector3.new(r:NextNumber(-0.22, 0.22) * h, h * r:NextNumber(0.6, 0.88), r:NextNumber(-0.22, 0.22) * h)
		ball(parent, "Leaves", d, pos + off, palette[r:NextInteger(1, #palette)], M.Grass, NOCOL)
	end
end

local function bush(parent, pos, r, col)
	for _ = 1, 3 do
		local d = r:NextNumber(2.5, 4.5)
		ball(parent, "Bush", d, pos + Vector3.new(r:NextNumber(-1.5, 1.5), d * 0.3, r:NextNumber(-1.5, 1.5)), col, M.Grass, NOCOL)
	end
end

local function boulder(parent, pos, s, r)
	mk(parent, "Boulder", Vector3.new(s, s * 0.7, s * 1.1),
		CFrame.new(pos + Vector3.new(0, s * 0.2, 0)) * CFrame.Angles(r:NextNumber(0, 3), r:NextNumber(0, 6), r:NextNumber(0, 1)),
		Color3.fromRGB(78, 78, 82), M.Slate)
end

-- прожектор на треноге (две панели), направлен на target
local function floodlight(parent, pos, target, color)
	color = color or Color3.fromRGB(200, 240, 255)
	local hub = pos + Vector3.new(0, 3, 0)
	for k = 0, 2 do
		local a = k * math.pi * 2 / 3
		beam(parent, "TripodLeg", hub, pos + Vector3.new(math.cos(a) * 2.2, 0, math.sin(a) * 2.2), 0.18, Color3.fromRGB(70, 74, 60), M.Metal)
	end
	beam(parent, "TripodPole", hub, pos + Vector3.new(0, 7.5, 0), 0.22, Color3.fromRGB(70, 74, 60), M.Metal)
	local top = pos + Vector3.new(0, 7.6, 0)
	local flat = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)
	local right = flat.Magnitude > 0.1 and Vector3.new(-flat.Z, 0, flat.X).Unit or Vector3.new(1, 0, 0)
	mk(parent, "Crossbar", Vector3.new(0.18, 0.18, 3.2), CFrame.lookAt(top, top + right), Color3.fromRGB(70, 74, 60), M.Metal)
	for _, s in ipairs({ -1, 1 }) do
		local p = top + right * (s * 1)
		local cf = CFrame.lookAt(p, target)
		mk(parent, "LampHousing", Vector3.new(1.5, 1.2, 0.5), cf, Color3.fromRGB(30, 32, 34), M.Metal)
		local lens = mk(parent, "LampLens", Vector3.new(1.3, 1, 0.1), cf * CFrame.new(0, 0, -0.28), color, M.Neon, NOCOL)
		spotLight(lens, Enum.NormalId.Front, color, 55, 55, 2.6)
	end
end

local function crate(parent, pos, s, yaw, col)
	return mk(parent, "Crate", Vector3.new(s, s, s), CFrame.new(pos + Vector3.new(0, s / 2, 0)) * CFrame.Angles(0, yaw or 0, 0),
		col or Color3.fromRGB(120, 90, 55), M.WoodPlanks)
end

local function barrel(parent, pos, col)
	cyl(parent, "Barrel", 3.6, 2.6, pos + Vector3.new(0, 1.8, 0), col or Color3.fromRGB(130, 30, 26), M.Metal)
end

local function pallet(parent, pos, yaw)
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw or 0, 0)
	for k = -1, 1 do
		mk(parent, "PalletBoard", Vector3.new(4.4, 0.25, 1), cf * CFrame.new(0, 0.6, k * 1.6), Color3.fromRGB(190, 170, 130), M.WoodPlanks)
		mk(parent, "PalletBlock", Vector3.new(4.4, 0.5, 0.6), cf * CFrame.new(0, 0.25, k * 1.6), Color3.fromRGB(160, 140, 105), M.WoodPlanks)
	end
end

-- старая легковушка (cf — центр на земле, LookVector — вперёд)
local function car(parent, cf, col)
	mk(parent, "CarBody", Vector3.new(6, 2.6, 13), cf * CFrame.new(0, 2.1, 0), col, M.Metal)
	mk(parent, "CarCabin", Vector3.new(5.4, 2.2, 6.5), cf * CFrame.new(0, 4.5, 0.6), col:Lerp(BLACK, 0.2), M.Metal)
	mk(parent, "CarGlass", Vector3.new(5.5, 1.6, 6.6), cf * CFrame.new(0, 4.6, 0.6), Color3.fromRGB(20, 24, 30), M.Glass, { Transparency = 0.3 })
	for _, w in ipairs({ { -3, -4.2 }, { 3, -4.2 }, { -3, 4.2 }, { 3, 4.2 } }) do
		mk(parent, "Wheel", Vector3.new(1.2, 2.6, 2.6), cf * CFrame.new(w[1], 1.3, w[2]), Color3.fromRGB(18, 18, 18), M.SmoothPlastic, { Shape = CYL })
	end
	for _, s in ipairs({ -1, 1 }) do
		mk(parent, "Headlight", Vector3.new(1, 0.6, 0.2), cf * CFrame.new(s * 2.1, 2.4, -6.55), Color3.fromRGB(255, 240, 200), M.Neon, NOCOL)
	end
end

------------------------------------------------------------------------
-- ПЕРСОНАЖИ: 6 выживших (3 роли по 2) + 3 Палача. Один персонаж = один игрок.
-- У выживших точные hp/stamina (у Феликса ещё мана) и два навыка; у Палачей пипсы 1..5 power/speed/stamina и один навык.
------------------------------------------------------------------------
local ROLES = {
	stun = { name = "СТАННЕР", color = { 255, 212, 40 } },
	support = { name = "ПОДДЕРЖКА", color = { 70, 230, 120 } },
	lone = { name = "ВЫЖИВАЛЬЩИК", color = { 255, 128, 36 } },
	killer = { name = "ПАЛАЧ", color = { 230, 40, 40 } },
}
gameState:SetAttribute("Roles", HttpService:JSONEncode(ROLES))

-- skills[1] — клавиша Q, skills[2] — клавиша E. cd — перезарядка, dur — длительность (для полосы активности в HUD).
local CHARACTERS = {
	{ id = "alex", name = "Алекс", group = "stun", role = "Уличный боец", killer = false, color = { 214, 60, 48 },
		hp = 100, stamina = 100,
		desc = "Повязка на лбу, бинты на кулаках. Серьёзный — встаёт между Палачом и командой.",
		skills = {
			{ id = "punch", name = "УДАР", key = "Q", cd = 25, dur = 0, text = "Удар в упор (до 7 м) оглушает Палача на 2 с" },
			{ id = "counter", name = "КОНТР-УДАР", key = "E", cd = 35, dur = 2.5,
				text = "2.5 с в стойке: удар Палача отражён, он оглушён на 3 с. Бежать нельзя, видна белая обводка" },
		} },
	{ id = "aisha", name = "Айша", f = true, group = "stun", role = "Неформалка", killer = false, color = { 255, 110, 190 },
		hp = 100, stamina = 100,
		desc = "Бодрая и задорная, вечно надувает пузырь из жвачки. Никого не бросит в беде.",
		skills = {
			{ id = "bat", name = "БИТА", key = "Q", cd = 20, dur = 0,
				text = "Замах и удар: в лицо — бита ломается, Палач оглушён на 1.5 с; в корпус — замедление" },
			{ id = "flash", name = "ВСПЫШКА", key = "E", cd = 30, dur = 0, text = "Вспышка камеры ослепляет Палача, смотрящего на тебя, на 1.5 с" },
		} },
	{ id = "lilian", name = "Лилиан", f = true, group = "support", role = "Медик", killer = false, color = { 90, 210, 190 },
		hp = 80, stamina = 100,
		desc = "Добрая и неравнодушная. Медицинская форма, аптечка всегда при себе.",
		skills = {
			{ id = "heal", name = "ЛЕЧЕНИЕ", key = "Q", cd = 30, dur = 10,
				text = "Встаёт в позу и предлагает лечение: выживший рядом жмёт F и получает +50. Урон отменяет" },
			{ id = "selfheal", name = "САМОЛЕЧЕНИЕ", key = "E", cd = 40, dur = 4, text = "4 с на месте, восстанавливает 35 здоровья. Урон отменяет" },
		} },
	{ id = "greg", name = "Грег", group = "support", role = "Инженер", killer = false, color = { 214, 132, 40 },
		hp = 90, stamina = 100,
		desc = "Безнравственный и потрёпанный жизнью инженер. Зато руки золотые.",
		skills = {
			{ id = "station", name = "СТАНЦИЯ", key = "Q", cd = 40, dur = 20,
				text = "ЛКМ — станция лечения, ПКМ — станция ускорения (20 с, радиус 9 м)" },
			{ id = "tripwire", name = "РАСТЯЖКА", key = "E", cd = 20, dur = 0, text = "Ставит растяжку: задевший её Палач резко замедлен на ~1 с" },
		} },
	{ id = "oscar", name = "Оскар", group = "lone", role = "Тихоня", killer = false, color = { 96, 98, 128 },
		hp = 100, stamina = 100,
		desc = "Нерешительный, с тяжёлым семейным прошлым. Тёмная одежда, взгляд в пол.",
		skills = {
			{ id = "godeye", name = "БОЖИЙ ГЛАЗ", key = "Q", cd = 35, dur = 5, text = "5 с видит всех выживших и Палача сквозь стены. Бежать нельзя" },
			{ id = "adrenaline", name = "АДРЕНАЛИН", key = "E", cd = 30, dur = 6, text = "+30% к скорости на 6 с, затем 1 с одышки" },
		} },
	{ id = "felix", name = "Феликс", group = "lone", role = "Маг", killer = false, color = { 70, 110, 240 },
		hp = 100, stamina = 100, mana = 50,
		desc = "Первым попал в приставку. Похож на мага в синих и тёмных тонах. Копит ману.",
		skills = {
			{ id = "telekinesis", name = "ТЕЛЕКИНЕЗ", key = "Q", cd = 6, dur = 0,
				text = "Сгусток силы: при попадании замедляет Палача на столько %, сколько сейчас маны. Тратит всю ману" },
			{ id = "shield", name = "СИЛОВОЙ ЩИТ", key = "E", cd = 35, dur = 3,
				text = "До 3 с: удар Палача отражён, он оглушён. Бежать нельзя. E ещё раз — сбросить щит и оттолкнуть Палача" },
		} },
	{ id = "executioner", name = "Палач", group = "killer", role = "Мясник с мешком", killer = true, color = { 200, 30, 30 },
		power = 4, speed = 3, stamina = 4,
		desc = "Мешок на голове, тесак в руке. Рывком сокращает дистанцию.",
		skills = { { id = "dash", name = "РЫВОК", key = "Q", cd = 14, dur = 0.55, text = "Мгновенный рывок вперёд" } } },
	{ id = "glitch", name = "Сбой", group = "killer", role = "Человек-телевизор", killer = true, color = { 70, 210, 235 },
		power = 3, speed = 3, stamina = 4,
		desc = "Экраны идут помехами — и Сбой видит всех сквозь стены.",
		skills = { { id = "reveal", name = "ПОМЕХИ", key = "Q", cd = 24, dur = 5, text = "5 с видит всех выживших сквозь стены" } } },
	{ id = "binky", name = "Бинки", group = "killer", role = "Талисман-маскот", killer = true, color = { 150, 80, 220 },
		power = 3, speed = 4, stamina = 3,
		desc = "Улыбается с коробки от приставки. Исчезает и появляется за спиной.",
		skills = { { id = "vanish", name = "ПРЯТКИ", key = "Q", cd = 26, dur = 6, text = "6 с невидимости, удар раскрывает" } } },
}
local CHAR_BY_ID = {}
for _, c in ipairs(CHARACTERS) do CHAR_BY_ID[c.id] = c end
gameState:SetAttribute("Characters", HttpService:JSONEncode(CHARACTERS))

local function rgb(t) return Color3.fromRGB(t[1], t[2], t[3]) end
local function charColor(c) return rgb(c.color) end
local function roleColor(c) return rgb(ROLES[c.group or "stun"].color) end

------------------------------------------------------------------------
-- КОСТЮМЫ: мультяшные гротескные силуэты поверх аватара (части приварены к телу,
-- поэтому повторяют любые анимации; исходное тело прячется). Работает с R15 и R6.
------------------------------------------------------------------------
local function V(x, y, z) return Vector3.new(x, y, z) end
local CF = CFrame.new
local SKIN = Color3.fromRGB(232, 190, 150)

local function gearPart(folder, base, name, size, offset, color, mat, shape)
	local p = Instance.new("Part")
	p.Name = name
	if shape then p.Shape = shape end
	p.Size = size
	p.Color = color
	p.Material = mat or M.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = base.CFrame * offset
	local w = Instance.new("Weld")
	w.Part0 = base
	w.Part1 = p
	w.C0 = offset
	w.Parent = p
	p.Parent = folder
	return p
end

-- мультяшные глаза: белки + зрачки (H — размер головы, y — высота глаз)
local function eyes(add, H, y, white, pupil, gap)
	gap = gap or 0.2
	for _, s in ipairs({ -1, 1 }) do
		add("EyeWhite", V(0.34 * H, 0.34 * H, 0.34 * H), CF(s * gap * H, y, -0.36 * H), white or WHITE, M.SmoothPlastic, BALL)
		add("Pupil", V(0.15 * H, 0.15 * H, 0.15 * H), CF(s * (gap - 0.02) * H, y - 0.02 * H, -0.5 * H), pupil or BLACK, M.SmoothPlastic, BALL)
	end
end

local COSTUME = {}
do
	local STUN = rgb(ROLES.stun.color)
	local SUPPORT = rgb(ROLES.support.color)
	local LONE = rgb(ROLES.lone.color)
	local function C(r, g, b) return Color3.fromRGB(r, g, b) end

	COSTUME.alex = { -- уличный боец: красная повязка с хвостами, бинты на кулаках, широкие плечи, пояс
		chest = C(36, 36, 42), chestMul = V(1.45, 1.15, 1.3), belly = C(60, 60, 68), bellyMul = V(1.2, 1.1, 1.2),
		arm = SKIN, armMul = 1.35, leg = C(60, 60, 68), legMul = 1.15, glove = C(238, 232, 214), gloveMul = 1.9,
		shoe = C(200, 40, 36), shoeMul = 1.3, accent = STUN,
		head = function(add, u)
			local H = 1.5 * u
			local y = (H - u) * 0.4
			add("BigHead", V(H, H, H), CF(0, y, 0), SKIN, M.SmoothPlastic, BALL)
			add("Hair", V(1.04 * H, 0.62 * H, 1.04 * H), CF(0, y + 0.3 * H, 0.04 * H), C(34, 26, 22), M.SmoothPlastic, BALL)
			for i, a in ipairs({ -35, 0, 35 }) do
				add("HairSpike", V(0.2 * H, 0.2 * H, 0.5 * H), CF(0, y + 0.42 * H, 0.05 * H) * CFrame.Angles(math.rad(-30 - i * 4), math.rad(a), 0) * CF(0, 0, 0.3 * H), C(34, 26, 22))
			end
			add("Headband", V(0.16 * H, 1.05 * H, 1.05 * H), CF(0, y + 0.16 * H, 0) * VERT, C(220, 30, 30), M.SmoothPlastic, CYL)
			for _, s in ipairs({ -1, 1 }) do
				add("BandTail", V(0.1 * H, 0.09 * H, 1.0 * H), CF(s * 0.12 * H, y + 0.08 * H, 0.8 * H) * CFrame.Angles(math.rad(20), math.rad(s * 14), 0), C(220, 30, 30))
				-- серьёзный взгляд: брови домиком вниз
				add("Brow", V(0.28 * H, 0.07 * H, 0.06 * H), CF(s * 0.2 * H, y + 0.2 * H, -0.47 * H) * CFrame.Angles(0, 0, math.rad(s * 20)), C(30, 22, 18))
			end
			eyes(add, H, y + 0.04 * H, nil, nil, 0.19)
			add("Mouth", V(0.24 * H, 0.04 * H, 0.05 * H), CF(0, y - 0.24 * H, -0.47 * H), C(90, 40, 36))
			add("Plaster", V(0.2 * H, 0.08 * H, 0.05 * H), CF(0.26 * H, y - 0.1 * H, -0.45 * H) * CFrame.Angles(0, 0, math.rad(-20)), C(238, 232, 214))
		end,
		extra = function(add, s, accent)
			add("Belt", V(s.X * 1.48, 0.35, s.Z * 1.34), CF(0, -s.Y * 0.48, 0), C(200, 30, 30))
			for _, x in ipairs({ -0.12, 0.12 }) do
				add("BeltTail", V(0.22, s.Y * 0.5, 0.1), CF(x * s.X, -s.Y * 0.78, -s.Z * 0.68) * CFrame.Angles(0, 0, math.rad(x * 60)), C(200, 30, 30))
			end
			add("Badge", V(0.5, 0.5, 0.1), CF(-s.X * 0.3, s.Y * 0.2, -s.Z * 0.66), accent, M.Neon)
		end,
	}
	COSTUME.aisha = { -- неформалка: розовые хвостики, джинсовка с нашивками, бита за спиной, пузырь жвачки
		chest = C(70, 100, 160), chestMul = V(1.25, 1.08, 1.25), belly = C(30, 30, 36), bellyMul = V(1.2, 1.1, 1.2),
		arm = C(70, 100, 160), armMul = 1.15, leg = C(34, 34, 40), legMul = 1.1, glove = C(205, 150, 120), gloveMul = 1.3,
		shoe = C(250, 250, 250), shoeMul = 1.45, accent = STUN,
		head = function(add, u)
			local H = 1.5 * u
			local y = (H - u) * 0.4
			local pink, violet = C(255, 110, 190), C(170, 90, 230)
			add("BackHair", V(1.06 * H, 1.0 * H, 1.0 * H), CF(0, y + 0.06 * H, 0.08 * H), pink, M.SmoothPlastic, BALL)
			add("BigHead", V(H, H, H), CF(0, y, -0.03 * H), C(205, 150, 120), M.SmoothPlastic, BALL)
			add("Bangs", V(0.95 * H, 0.26 * H, 0.5 * H), CF(0.06 * H, y + 0.36 * H, -0.24 * H) * CFrame.Angles(math.rad(-18), 0, math.rad(-12)), pink)
			for _, s in ipairs({ -1, 1 }) do
				add("Pigtail", V(0.42 * H, 0.42 * H, 0.42 * H), CF(s * 0.55 * H, y + 0.38 * H, 0.1 * H), violet, M.SmoothPlastic, BALL)
				add("PigtailTip", V(0.3 * H, 0.3 * H, 0.3 * H), CF(s * 0.72 * H, y + 0.16 * H, 0.14 * H), pink, M.SmoothPlastic, BALL)
			end
			eyes(add, H, y + 0.04 * H, nil, C(140, 60, 160))
			add("Blush", V(0.14 * H, 0.06 * H, 0.04 * H), CF(-0.28 * H, y - 0.12 * H, -0.44 * H), C(255, 130, 160))
			add("Blush", V(0.14 * H, 0.06 * H, 0.04 * H), CF(0.28 * H, y - 0.12 * H, -0.44 * H), C(255, 130, 160))
			add("Bubble", V(0.36 * H, 0.36 * H, 0.36 * H), CF(0.02 * H, y - 0.24 * H, -0.62 * H), C(255, 150, 210), M.SmoothPlastic, BALL)
		end,
		extra = function(add, s, accent)
			add("Bat", V(0.4, s.Y * 2.2, 0.4), CF(0, s.Y * 0.3, s.Z * 0.7) * CFrame.Angles(0, 0, math.rad(35)), C(176, 124, 72), M.Wood)
			add("BatTape", V(0.44, 0.6, 0.44), CF(-s.X * 0.5, -s.Y * 0.35, s.Z * 0.7) * CFrame.Angles(0, 0, math.rad(35)), C(30, 30, 30))
			add("Camera", V(s.X * 0.4, s.Y * 0.28, 0.4), CF(s.X * 0.15, -s.Y * 0.15, -s.Z * 0.68), C(40, 40, 46))
			add("Lens", V(0.3, 0.5, 0.5), CF(s.X * 0.15, -s.Y * 0.15, -s.Z * 0.68 - 0.3) * ALONG_Z, C(10, 10, 14), M.SmoothPlastic, CYL)
			add("Strap", V(0.15, s.Y * 1.2, 0.1), CF(-s.X * 0.1, s.Y * 0.15, -s.Z * 0.66) * CFrame.Angles(0, 0, math.rad(-35)), C(250, 110, 190))
			add("Patch", V(0.45, 0.45, 0.1), CF(-s.X * 0.32, s.Y * 0.22, -s.Z * 0.66), C(255, 110, 190))
			add("Badge", V(0.4, 0.4, 0.1), CF(s.X * 0.32, s.Y * 0.25, -s.Z * 0.66), accent, M.Neon)
		end,
	}
	COSTUME.lilian = { -- медик: мятный медицинский костюм, шапочка с крестом, пучок, огромная аптечка за спиной
		chest = C(110, 220, 200), chestMul = V(1.2, 1.12, 1.25), belly = C(110, 220, 200), bellyMul = V(1.3, 1.4, 1.3),
		arm = C(110, 220, 200), armMul = 1.1, leg = C(80, 190, 170), legMul = 1.0, glove = C(245, 245, 250), gloveMul = 1.35,
		shoe = C(245, 245, 250), shoeMul = 1.25, accent = SUPPORT,
		head = function(add, u)
			local H = 1.45 * u
			local y = (H - u) * 0.4
			local hair = C(120, 70, 40)
			add("BackHair", V(1.03 * H, 1.03 * H, 1.03 * H), CF(0, y + 0.03 * H, 0.1 * H), hair, M.SmoothPlastic, BALL)
			add("BigHead", V(H, H, H), CF(0, y, -0.02 * H), SKIN, M.SmoothPlastic, BALL)
			add("Bun", V(0.55 * H, 0.55 * H, 0.55 * H), CF(0, y + 0.42 * H, 0.42 * H), hair, M.SmoothPlastic, BALL)
			add("Cap", V(0.7 * H, 0.32 * H, 0.46 * H), CF(0, y + 0.52 * H, -0.08 * H), C(250, 250, 250))
			add("CapCrossH", V(0.26 * H, 0.08 * H, 0.04 * H), CF(0, y + 0.52 * H, -0.32 * H), C(220, 40, 40), M.Neon)
			add("CapCrossV", V(0.08 * H, 0.26 * H, 0.04 * H), CF(0, y + 0.52 * H, -0.32 * H), C(220, 40, 40), M.Neon)
			eyes(add, H, y + 0.04 * H, nil, C(40, 120, 70))
			for _, s in ipairs({ -1, 1 }) do
				add("Blush", V(0.13 * H, 0.06 * H, 0.04 * H), CF(s * 0.28 * H, y - 0.12 * H, -0.44 * H), C(255, 150, 160))
			end
			add("Smile", V(0.2 * H, 0.05 * H, 0.05 * H), CF(0, y - 0.22 * H, -0.47 * H), C(180, 60, 90))
		end,
		extra = function(add, s, accent)
			add("Medpack", V(s.X * 1.1, s.Y * 1.35, 1.1), CF(0, s.Y * 0.15, s.Z * 0.6 + 0.6), C(250, 250, 250))
			add("CrossH", V(s.X * 0.6, 0.35, 0.1), CF(0, s.Y * 0.2, s.Z * 0.6 + 1.17), C(220, 40, 40), M.Neon)
			add("CrossV", V(0.35, s.X * 0.6, 0.1), CF(0, s.Y * 0.2, s.Z * 0.6 + 1.17), C(220, 40, 40), M.Neon)
			add("Stethoscope", V(s.X * 0.7, 0.14, 0.12), CF(0, s.Y * 0.38, -s.Z * 0.64), C(60, 60, 66))
			add("Pocket", V(0.6, 0.5, 0.1), CF(s.X * 0.28, s.Y * 0.12, -s.Z * 0.64), C(90, 200, 180))
			add("Badge", V(0.4, 0.4, 0.1), CF(-s.X * 0.28, s.Y * 0.12, -s.Z * 0.64), accent, M.Neon)
		end,
	}
	COSTUME.greg = { -- потрёпанный инженер: грязный комбинезон, очки-гогглы на лбу, щетина, пояс с инструментами
		chest = C(196, 118, 40), chestMul = V(1.5, 1.15, 1.5), belly = C(176, 104, 36), bellyMul = V(1.55, 1.15, 1.6),
		arm = C(110, 108, 98), armMul = 1.25, leg = C(176, 104, 36), legMul = 1.2, glove = C(90, 70, 50), gloveMul = 1.75,
		shoe = C(60, 44, 30), shoeMul = 1.5, accent = SUPPORT,
		head = function(add, u)
			local H = 1.4 * u
			local y = (H - u) * 0.35
			local skin = C(210, 165, 130)
			add("BigHead", V(H, H, H), CF(0, y, 0), skin, M.SmoothPlastic, BALL)
			for i, p in ipairs({ { -0.25, 0.42, 20 }, { 0, 0.48, -10 }, { 0.25, 0.42, -25 }, { 0.1, 0.38, 40 } }) do
				add("HairTuft", V(0.32 * H, 0.22 * H, 0.32 * H), CF(p[1] * H, y + p[2] * H, (0.05 + i * 0.03) * H) * CFrame.Angles(0, 0, math.rad(p[3])), C(130, 122, 112))
			end
			add("GoggleBand", V(0.12 * H, 1.04 * H, 1.04 * H), CF(0, y + 0.28 * H, 0) * VERT, C(40, 36, 32), M.SmoothPlastic, CYL)
			for _, s in ipairs({ -1, 1 }) do
				add("Goggle", V(0.12 * H, 0.3 * H, 0.3 * H), CF(s * 0.17 * H, y + 0.32 * H, -0.48 * H) * ALONG_Z, C(90, 90, 96), M.Metal, CYL)
				add("GoggleGlass", V(0.06 * H, 0.22 * H, 0.22 * H), CF(s * 0.17 * H, y + 0.32 * H, -0.54 * H) * ALONG_Z, C(110, 220, 230), M.Neon, CYL)
				-- усталые глаза: мешки и опущенные веки
				add("EyeBag", V(0.24 * H, 0.06 * H, 0.05 * H), CF(s * 0.19 * H, y - 0.08 * H, -0.46 * H), C(160, 110, 100))
			end
			eyes(add, H, y + 0.02 * H, C(235, 225, 200))
			for _, s in ipairs({ -1, 1 }) do
				add("Lid", V(0.36 * H, 0.16 * H, 0.1 * H), CF(s * 0.2 * H, y + 0.12 * H, -0.46 * H), skin:Lerp(BLACK, 0.15))
			end
			add("Stubble", V(0.7 * H, 0.32 * H, 0.42 * H), CF(0, y - 0.28 * H, -0.24 * H), C(110, 100, 92), M.Sand)
			add("Mouth", V(0.22 * H, 0.04 * H, 0.05 * H), CF(0.04 * H, y - 0.24 * H, -0.47 * H) * CFrame.Angles(0, 0, math.rad(-8)), C(90, 40, 36))
		end,
		extra = function(add, s, accent)
			add("Bib", V(s.X * 0.8, s.Y * 0.6, 0.12), CF(0, s.Y * 0.1, -s.Z * 0.76), C(186, 110, 38))
			for _, x in ipairs({ -0.28, 0.28 }) do
				add("Strap", V(0.25, s.Y * 0.7, 0.12), CF(x * s.X, s.Y * 0.38, -s.Z * 0.76), C(150, 90, 30))
				add("Button", V(0.25, 0.25, 0.25), CF(x * s.X, s.Y * 0.1, -s.Z * 0.82), C(200, 200, 205), M.Metal, BALL)
			end
			add("Stain", V(0.6, 0.4, 0.05), CF(-s.X * 0.2, -s.Y * 0.05, -s.Z * 0.83), C(60, 50, 40))
			add("ToolBelt", V(s.X * 1.6, 0.4, s.Z * 1.65), CF(0, -s.Y * 0.5, 0), C(80, 56, 34))
			add("WrenchHandle", V(0.22, 1.6, 0.18), CF(s.X * 0.75, -s.Y * 0.7, -s.Z * 0.3), C(160, 160, 168), M.Metal)
			add("WrenchHead", V(0.6, 0.35, 0.2), CF(s.X * 0.75, -s.Y * 0.7 + 0.85, -s.Z * 0.3), C(160, 160, 168), M.Metal)
			add("Badge", V(0.4, 0.4, 0.1), CF(s.X * 0.18, s.Y * 0.2, -s.Z * 0.83), accent, M.Neon)
		end,
	}
	COSTUME.oscar = { -- тихоня: тёмная толстовка, капюшон, чёлка закрывает глаз, бледное лицо
		chest = C(40, 40, 50), chestMul = V(1.2, 1.15, 1.25), belly = C(36, 36, 46), bellyMul = V(1.2, 1.2, 1.25),
		arm = C(40, 40, 50), armMul = 1.15, leg = C(30, 32, 46), legMul = 1.05, glove = C(226, 206, 192), gloveMul = 1.15,
		shoe = C(24, 24, 28), shoeMul = 1.3, accent = LONE,
		head = function(add, u)
			local H = 1.45 * u
			local y = (H - u) * 0.4
			local pale = C(226, 206, 192)
			local hair = C(22, 22, 28)
			add("Hood", V(1.18 * H, 1.12 * H, 1.12 * H), CF(0, y + 0.04 * H, 0.14 * H), C(48, 48, 60), M.Fabric, BALL)
			add("BigHead", V(H, H, H), CF(0, y, -0.02 * H), pale, M.SmoothPlastic, BALL)
			add("Hair", V(1.02 * H, 0.6 * H, 1.0 * H), CF(0, y + 0.3 * H, 0.02 * H), hair, M.SmoothPlastic, BALL)
			-- длинная чёлка падает на правый глаз
			add("Fringe", V(0.5 * H, 0.5 * H, 0.2 * H), CF(0.14 * H, y + 0.12 * H, -0.44 * H) * CFrame.Angles(0, 0, math.rad(-22)), hair)
			-- взгляд в пол: зрачки опущены, под глазами тени
			add("EyeWhite", V(0.3 * H, 0.3 * H, 0.3 * H), CF(-0.19 * H, y + 0.02 * H, -0.37 * H), WHITE, M.SmoothPlastic, BALL)
			add("Pupil", V(0.13 * H, 0.13 * H, 0.13 * H), CF(-0.18 * H, y - 0.06 * H, -0.5 * H), BLACK, M.SmoothPlastic, BALL)
			add("DarkCircle", V(0.26 * H, 0.06 * H, 0.05 * H), CF(-0.19 * H, y - 0.13 * H, -0.45 * H), C(150, 130, 150))
			add("Mouth", V(0.14 * H, 0.04 * H, 0.05 * H), CF(0, y - 0.25 * H, -0.47 * H) * CFrame.Angles(0, 0, math.rad(6)), C(120, 80, 80))
		end,
		extra = function(add, s, accent)
			add("Pocket", V(s.X * 0.75, s.Y * 0.32, 0.14), CF(0, -s.Y * 0.18, -s.Z * 0.68), C(34, 34, 44))
			for _, x in ipairs({ -0.12, 0.12 }) do
				add("Drawstring", V(0.08, s.Y * 0.55, 0.08), CF(x * s.X, s.Y * 0.18, -s.Z * 0.7), C(200, 200, 205))
			end
			add("Earbud", V(0.1, s.Y * 0.8, 0.1), CF(-s.X * 0.3, s.Y * 0.2, -s.Z * 0.66) * CFrame.Angles(0, 0, math.rad(15)), accent, M.Neon)
			add("Bag", V(s.X * 0.8, s.Y * 0.9, 0.7), CF(0, -s.Y * 0.05, s.Z * 0.6 + 0.35), C(30, 30, 36), M.Fabric)
		end,
	}
	COSTUME.felix = { -- маг: высокая шляпа со звёздами, длинная мантия, плащ, парящая сфера маны
		chest = C(32, 42, 96), chestMul = V(1.2, 1.2, 1.25), belly = C(26, 32, 80), bellyMul = V(1.35, 2.0, 1.35),
		arm = C(44, 60, 130), armMul = 1.3, leg = C(22, 26, 60), legMul = 1.0, glove = C(200, 205, 225), gloveMul = 1.25,
		shoe = C(20, 20, 34), shoeMul = 1.3, accent = Color3.fromRGB(90, 150, 255),
		head = function(add, u)
			local H = 1.45 * u
			local y = (H - u) * 0.4
			local hat = C(34, 44, 110)
			add("BigHead", V(H, H, H), CF(0, y, 0), C(214, 214, 230), M.SmoothPlastic, BALL)
			add("Hair", V(1.04 * H, 0.5 * H, 1.04 * H), CF(0, y + 0.22 * H, 0.06 * H), C(30, 30, 60), M.SmoothPlastic, BALL)
			add("HatBrim", V(0.08 * H, 1.6 * H, 1.6 * H), CF(0, y + 0.42 * H, 0) * VERT, hat, M.Fabric, CYL)
			-- конус шляпы из ярусов, кончик загнут назад
			for i, d in ipairs({ 1.0, 0.78, 0.56, 0.36, 0.2 }) do
				add("HatCone", V(0.28 * H, d * H, d * H), CF(0, y + (0.5 + i * 0.24) * H, (i * i) * 0.012 * H) * VERT, hat, M.Fabric, CYL)
			end
			add("HatBand", V(0.1 * H, 1.02 * H, 1.02 * H), CF(0, y + 0.54 * H, 0) * VERT, C(90, 150, 255), M.Neon, CYL)
			for _, p in ipairs({ { -0.3, 0.8, -0.32 }, { 0.22, 1.05, -0.24 }, { -0.05, 1.3, -0.16 } }) do
				add("Star", V(0.12 * H, 0.12 * H, 0.12 * H), CF(p[1] * H, y + p[2] * H, p[3] * H), C(255, 220, 90), M.Neon, BALL)
			end
			-- светящиеся глаза мага
			eyes(add, H, y + 0.02 * H, C(200, 230, 255), C(60, 140, 255))
			add("Collar", V(1.0 * H, 0.3 * H, 0.95 * H), CF(0, y - 0.48 * H, 0.04 * H), C(26, 32, 80), M.Fabric)
		end,
		extra = function(add, s, accent)
			add("Cape", V(s.X * 1.4, s.Y * 2.4, 0.15), CF(0, -s.Y * 0.4, s.Z * 0.75), C(20, 24, 60), M.Fabric)
			add("CapeLining", V(s.X * 1.3, s.Y * 2.3, 0.05), CF(0, -s.Y * 0.4, s.Z * 0.66), C(60, 90, 200), M.Fabric)
			add("Pendant", V(0.4, 0.55, 0.15), CF(0, s.Y * 0.05, -s.Z * 0.7) * CFrame.Angles(0, 0, math.rad(45)), accent, M.Neon)
			add("Orb", V(0.9, 0.9, 0.9), CF(s.X * 1.1, s.Y * 0.6, -s.Z * 0.6), C(110, 170, 255), M.Neon, BALL)
			add("Sash", V(s.X * 1.3, 0.35, s.Z * 1.3), CF(0, -s.Y * 0.45, 0), C(90, 150, 255), M.Fabric)
		end,
	}
	local KILL = Color3.fromRGB(150, 10, 10)
	COSTUME.executioner = { -- мясник: мешок с крестиками-глазами, фартук, цепи, огромные руки
		chest = C(60, 32, 30), chestMul = V(1.75, 1.3, 1.55), belly = C(150, 140, 120), bellyMul = V(1.5, 1.4, 1.45),
		arm = C(60, 32, 30), armMul = 1.5, leg = C(40, 30, 30), legMul = 1.35, glove = C(20, 18, 18), gloveMul = 2.0,
		shoe = C(30, 25, 25), shoeMul = 1.5, accent = KILL,
		head = function(add, u)
			local H = 1.7 * u
			local y = (H - u) * 0.35
			add("Sack", V(H, H * 1.05, H), CF(0, y, 0), C(150, 115, 70), M.Fabric)
			add("SackTop", V(0.3 * H, 0.3 * H, 0.3 * H), CF(0, y + 0.6 * H, 0) * CFrame.Angles(0, 0, math.rad(20)), C(150, 115, 70), M.Fabric)
			add("Rope", V(0.12 * H, 0.82 * H, 0.82 * H), CF(0, y - 0.46 * H, 0) * VERT, C(100, 80, 50), M.Fabric, CYL)
			for _, s in ipairs({ -1, 1 }) do
				for _, a in ipairs({ 45, -45 }) do
					add("XEye", V(0.32 * H, 0.07 * H, 0.05 * H), CF(s * 0.22 * H, y + 0.12 * H, -0.51 * H) * CFrame.Angles(0, 0, math.rad(a)), Color3.fromRGB(255, 40, 30), M.Neon)
				end
			end
			add("Stitch", V(0.55 * H, 0.05 * H, 0.05 * H), CF(0, y - 0.2 * H, -0.51 * H), C(40, 20, 10))
			for _, x in ipairs({ -0.2, -0.07, 0.07, 0.2 }) do
				add("StitchV", V(0.03 * H, 0.14 * H, 0.05 * H), CF(x * H, y - 0.2 * H, -0.52 * H), C(40, 20, 10))
			end
		end,
		extra = function(add, s)
			for _, a in ipairs({ 35, -35 }) do
				add("Chain", V(0.25, s.Y * 1.5, 0.25), CF(0, 0, -s.Z * 0.8) * CFrame.Angles(0, 0, math.rad(a)), C(90, 90, 96), M.Metal)
			end
			add("Blood", V(s.X * 0.5, s.Y * 0.4, 0.05), CF(s.X * 0.2, -s.Y * 0.9, -s.Z * 0.76), C(110, 10, 10))
			add("Hook", V(0.2, 1.2, 0.2), CF(s.X * 0.7, -s.Y * 0.6, 0), C(140, 140, 150), M.Metal)
		end,
	}
	COSTUME.glitch = { -- человек-телевизор: тонкий длинный силуэт, ЭЛТ вместо головы, свисающие кабели
		chest = C(20, 20, 26), chestMul = V(0.95, 1.2, 0.95), belly = C(20, 20, 26), bellyMul = V(0.9, 1.1, 0.9),
		arm = C(20, 20, 26), armMul = 0.95, leg = C(20, 20, 26), legMul = 0.95, glove = C(230, 230, 240), gloveMul = 1.3,
		shoe = C(15, 15, 18), shoeMul = 1.1, accent = Color3.fromRGB(255, 60, 200),
		head = function(add, u)
			local H = 1.9 * u
			local y = (H - u) * 0.35
			add("TV", V(H, H * 0.8, H * 0.85), CF(0, y, 0.05 * H), C(44, 44, 50))
			local screen = add("TVScreen", V(0.78 * H, 0.58 * H, 0.05 * H), CF(-0.04 * H, y, -0.39 * H), C(120, 235, 255), M.Neon)
			tag(screen, "P2D_Flicker", { Strong = true })
			add("Knob", V(0.08 * H, 0.12 * H, 0.12 * H), CF(0.42 * H, y - 0.1 * H, -0.39 * H) * ALONG_Z, C(100, 100, 110), M.Metal, CYL)
			for _, s in ipairs({ -1, 1 }) do
				add("Antenna", V(0.04 * H, 0.6 * H, 0.04 * H), CF(s * 0.18 * H, y + 0.62 * H, 0.05 * H) * CFrame.Angles(0, 0, math.rad(-25 * s)), C(180, 180, 190), M.Metal)
			end
		end,
		extra = function(add, s, accent)
			add("StripeA", V(s.X * 1.0, 0.18, s.Z * 1.0), CF(0, s.Y * 0.2, 0), Color3.fromRGB(70, 230, 255), M.Neon)
			add("StripeB", V(s.X * 1.0, 0.12, s.Z * 1.0), CF(0, -s.Y * 0.1, 0), accent, M.Neon)
			for _, x in ipairs({ -0.3, 0.1, 0.35 }) do
				add("Cable", V(0.12, 3.2, 0.12), CF(x * s.X, -s.Y * 0.6, s.Z * 0.6) * CFrame.Angles(math.rad(-15), 0, math.rad(x * 30)), C(10, 10, 12))
			end
		end,
	}
	COSTUME.binky = { -- маскот: гигантская круглая голова с ушами и улыбкой, белые перчатки, большие ботинки
		chest = C(150, 80, 220), chestMul = V(1.35, 1.2, 1.35), belly = C(185, 130, 240), bellyMul = V(1.5, 1.2, 1.5),
		arm = C(150, 80, 220), armMul = 1.15, leg = C(150, 80, 220), legMul = 1.15, glove = C(245, 245, 245), gloveMul = 2.2,
		shoe = C(220, 40, 40), shoeMul = 1.75, accent = KILL,
		head = function(add, u)
			local H = 2.3 * u
			local y = (H - u) * 0.38
			add("BigHead", V(H, H, H), CF(0, y, 0), C(150, 80, 220), M.SmoothPlastic, BALL)
			for _, s in ipairs({ -1, 1 }) do
				local ear = CF(s * 0.25 * H, y + 0.72 * H, 0) * CFrame.Angles(0, 0, math.rad(-14 * s))
				add("Ear", V(0.28 * H, 0.85 * H, 0.12 * H), ear, C(150, 80, 220))
				add("EarIn", V(0.16 * H, 0.65 * H, 0.05 * H), ear * CF(0, 0, -0.07 * H), C(255, 150, 200))
				add("EyeHole", V(0.05 * H, 0.32 * H, 0.32 * H), CF(s * 0.2 * H, y + 0.1 * H, -0.46 * H) * ALONG_Z, C(5, 5, 5), M.SmoothPlastic, CYL)
				add("RedPupil", V(0.09 * H, 0.09 * H, 0.09 * H), CF(s * 0.2 * H, y + 0.1 * H, -0.49 * H), Color3.fromRGB(255, 30, 30), M.Neon, BALL)
			end
			add("Nose", V(0.14 * H, 0.14 * H, 0.14 * H), CF(0, y - 0.04 * H, -0.5 * H), C(220, 40, 40), M.SmoothPlastic, BALL)
			add("Grin", V(0.62 * H, 0.12 * H, 0.05 * H), CF(0, y - 0.22 * H, -0.46 * H), C(255, 250, 240), M.Neon)
			for _, x in ipairs({ -0.2, -0.07, 0.07, 0.2 }) do
				add("Tooth", V(0.02 * H, 0.12 * H, 0.06 * H), CF(x * H, y - 0.22 * H, -0.47 * H), C(30, 0, 0))
			end
		end,
		extra = function(add, s)
			for _, x in ipairs({ -1, 1 }) do
				add("Bow", V(0.6, 0.5, 0.2), CF(x * 0.35, s.Y * 0.42, -s.Z * 0.7) * CFrame.Angles(0, 0, math.rad(x * 20)), C(220, 40, 40))
			end
			for i = 0, 1 do
				add("Button", V(0.3, 0.3, 0.3), CF(0, -i * s.Y * 0.35, -s.Z * 0.7), C(255, 210, 60), M.SmoothPlastic, BALL)
			end
		end,
	}
end

local function segOf(name)
	if name == "Head" then return "head" end
	if name == "UpperTorso" or name == "Torso" then return "chest" end
	if name == "LowerTorso" then return "belly" end
	if string.find(name, "Hand") then return "hand" end
	if string.find(name, "Foot") then return "foot" end
	if string.find(name, "UpperArm") or string.find(name, "LowerArm") then return "arm" end
	if string.find(name, "UpperLeg") or string.find(name, "LowerLeg") then return "leg" end
	if name == "Left Arm" or name == "Right Arm" then return "arm6" end
	if name == "Left Leg" or name == "Right Leg" then return "leg6" end
	return nil
end

-- внешний вид персонажа: костюм вместо тела, обводка цвета роли
local function applyLook(char, c)
	char:SetAttribute("CharId", c.id)
	local ok, err = pcall(function()
		local spec = COSTUME[c.id]
		local old = char:FindFirstChild("P2D_Gear")
		if old then old:Destroy() end
		local oldHl = char:FindFirstChild("P2D_Outline")
		if oldHl then oldHl:Destroy() end
		for _, o in ipairs(char:GetChildren()) do
			if o:IsA("Shirt") or o:IsA("Pants") or o:IsA("ShirtGraphic") or o:IsA("Accoutrement") then
				o:Destroy()
			end
		end
		if not spec then return end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local r6 = hum and hum.RigType == Enum.HumanoidRigType.R6
		local folder = Instance.new("Model")
		folder.Name = "P2D_Gear"
		local accent = spec.accent or roleColor(c)
		local chestPart = nil
		for _, p in ipairs(char:GetChildren()) do
			local seg = p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" and segOf(p.Name) or nil
			if seg then
				local function add(name, size, off, color, mat, shape)
					return gearPart(folder, p, name, size, off, color, mat, shape)
				end
				local s = p.Size
				if seg == "head" then
					spec.head(add, r6 and 1.2 or math.clamp(s.Y, 0.8, 1.8))
				elseif seg == "chest" then
					chestPart = p
					local m = spec.chestMul
					if r6 then
						add("Chest", V(s.X * m.X, s.Y * 0.62 * m.Y, s.Z * m.Z), CF(0, s.Y * 0.2, 0), spec.chest)
						add("Belly", V(s.X * spec.bellyMul.X, s.Y * 0.42 * spec.bellyMul.Y, s.Z * spec.bellyMul.Z), CF(0, -s.Y * 0.3, 0), spec.belly)
					else
						add("Chest", V(s.X * m.X, s.Y * m.Y, s.Z * m.Z), CFrame.identity, spec.chest)
					end
					add("Accent", V(s.X * m.X + 0.06, 0.18, s.Z * m.Z + 0.06), CF(0, r6 and -s.Y * 0.08 or -s.Y * 0.42, 0), accent, M.Neon)
				elseif seg == "belly" then
					local m = spec.bellyMul
					add("Belly", V(s.X * m.X, s.Y * m.Y * 1.6, s.Z * m.Z), CF(0, -s.Y * 0.2 * (m.Y - 1), 0), spec.belly)
				elseif seg == "arm" then
					add("Sleeve", s * spec.armMul, CFrame.identity, spec.arm)
				elseif seg == "leg" then
					add("Pants", s * spec.legMul, CFrame.identity, spec.leg)
				elseif seg == "hand" then
					local d = 0.75 * spec.gloveMul
					add("Glove", V(d, d, d), CF(0, -s.Y * 0.2, 0), spec.glove, M.SmoothPlastic, BALL)
				elseif seg == "foot" then
					add("Shoe", V(0.95, 0.6, 1.5) * spec.shoeMul, CF(0, 0.05, -0.3 * spec.shoeMul), spec.shoe)
				elseif seg == "arm6" then
					add("Sleeve", V(s.X * spec.armMul, s.Y * 0.75, s.Z * spec.armMul), CF(0, s.Y * 0.12, 0), spec.arm)
					local d = 0.75 * spec.gloveMul
					add("Glove", V(d, d, d), CF(0, -s.Y * 0.42, 0), spec.glove, M.SmoothPlastic, BALL)
				elseif seg == "leg6" then
					add("Pants", V(s.X * spec.legMul, s.Y * 0.72, s.Z * spec.legMul), CF(0, s.Y * 0.12, 0), spec.leg)
					add("Shoe", V(0.95, 0.6, 1.5) * spec.shoeMul, CF(0, -s.Y * 0.42, -0.3 * spec.shoeMul), spec.shoe)
				end
				p.Transparency = 1
				for _, d in ipairs(p:GetChildren()) do
					if d:IsA("Decal") then d:Destroy() end
				end
			end
		end
		if chestPart and spec.extra then
			spec.extra(function(name, size, off, color, mat, shape)
				return gearPart(folder, chestPart, name, size, off, color, mat, shape)
			end, chestPart.Size, accent)
		end
		folder.Parent = char
		-- мультяшная обводка: силуэт читается на тёмном фоне (сквозь стены не видна)
		local hl = Instance.new("Highlight")
		hl.Name = "P2D_Outline"
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.FillTransparency = 1
		hl.OutlineColor = c.killer and Color3.fromRGB(150, 20, 20) or roleColor(c)
		hl.OutlineTransparency = c.killer and 0.45 or 0.25
		hl.Parent = char
		char:SetAttribute("CharId", c.id)
	end)
	if not ok then warn("[P2D] костюм: " .. tostring(err)) end
end

------------------------------------------------------------------------
-- КАРТЫ: общие функции
------------------------------------------------------------------------
local MAP_INFO = {
	{ key = "Forest", name = "ТУМАННЫЙ ЛЕС", sub = "ЛЕСОПИЛКА «КРАСНЫЙ БОР»" },
	{ key = "Complex", name = "КОМПЛЕКС", sub = "ЗАВОД №13 · НОЧНАЯ СМЕНА" },
	{ key = "Farm", name = "ФЕРМА", sub = "«ТИХИЙ ЛУГ» · ЗАКАТ" },
}
local MAP_BY_KEY = {}
for _, info in ipairs(MAP_INFO) do MAP_BY_KEY[info.key] = info end
gameState:SetAttribute("Maps", HttpService:JSONEncode(MAP_INFO))

local mapsFolder = Instance.new("Folder")
mapsFolder.Name = "Maps"
mapsFolder.Parent = Workspace

-- выходы — отдельные «постоянные» модели, чтобы клиент видел их при стриминге
local dynamicFolder = Instance.new("Folder")
dynamicFolder.Name = "P2D_Dynamic"
dynamicFolder.Parent = Workspace

local function newMap(info, origin, half)
	local model = Instance.new("Model")
	model.Name = "Map_" .. info.key
	model.Parent = mapsFolder
	local dyn = Instance.new("Model")
	dyn.Name = "Dyn_" .. info.key
	dyn.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	dyn.Parent = dynamicFolder
	local def = {
		key = info.key, display = info.name, info = info, origin = origin, model = model, dynamic = dyn,
		half = half, survivorSpawns = {}, killerSpawns = {}, escapes = {}, blockers = {}, beamH = 90,
	}
	-- невидимые стены по краю игровой зоны
	local function border(sz, off)
		mk(model, "Border", sz, origin + off, BLACK, M.SmoothPlastic, { Transparency = 1, CanQuery = false })
	end
	local b = half + 2
	border(Vector3.new(b * 2 + 4, 200, 4), Vector3.new(0, 100, -b))
	border(Vector3.new(b * 2 + 4, 200, 4), Vector3.new(0, 100, b))
	border(Vector3.new(4, 200, b * 2 + 4), Vector3.new(b, 100, 0))
	border(Vector3.new(4, 200, b * 2 + 4), Vector3.new(-b, 100, 0))
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
local function addSpawn(def, kind, x, z, y)
	local p = mk(def.model, kind .. "Spawn", Vector3.new(4, 1, 4), def.origin + Vector3.new(x, (y or 0) + 0.5, z),
		BLACK, M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false })
	table.insert(kind == "Killer" and def.killerSpawns or def.survivorSpawns, p)
	reserve(def, x, z, 10)
end

------------------------------------------------------------------------
-- ВЫХОДЫ: ворота / двери в стенах. Конструктор возвращает створки:
-- { part, hinge = CFrame?, angle = число?, open = CFrame? } — либо поворот на петле, либо сдвиг.
------------------------------------------------------------------------
local function addEscape(def, x, z, label, normal, build)
	local pos = def.origin + Vector3.new(x, 0, z)
	local m = Instance.new("Model")
	m.Name = "Escape"
	m.Parent = def.dynamic
	local gateCF = CFrame.lookAt(pos - normal * 6, pos - normal * 6 + normal) -- ворота стоят в 6 м за зоной, «лицом» в карту
	local doors = build(m, gateCF)
	for _, d in ipairs(doors) do d.closed = d.part.CFrame end
	-- лампа над воротами: красная — закрыто, зелёная — открыто
	local lamp = mk(m, "GateLamp", Vector3.new(1.4, 0.8, 0.8), gateCF * CFrame.new(0, (doors.lampY or 11), -0.8), LAMP_RED, M.Neon, NOCOL)
	local light = pointLight(lamp, LAMP_RED, 18, 1.2)
	local zone = mk(m, "EscapeZone", Vector3.new(14, 12, 14), pos + Vector3.new(0, 6, 0),
		Color3.new(1, 0, 0), M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false })
	zone:SetAttribute("Active", false)
	local beamPart = nil
	if def.beamH > 0 then
		beamPart = mk(m, "Beam", Vector3.new(def.beamH, 3, 3), CFrame.new(pos - normal * 10 + Vector3.new(0, def.beamH / 2, 0)) * VERT,
			GREEN, M.Neon, { Shape = CYL, Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
	end
	table.insert(def.escapes, { zone = zone, doors = doors, lamp = lamp, light = light, beam = beamPart, label = label, token = 0 })
	reserve(def, x, z, 14)
end

local function animateDoors(e, open)
	e.token += 1
	local my = e.token
	if not open then
		for _, d in ipairs(e.doors) do d.part.CFrame = d.closed end
		return
	end
	task.spawn(function()
		local t0 = os.clock()
		local dur = 1.6
		while true do
			if e.token ~= my then return end
			local a = math.clamp((os.clock() - t0) / dur, 0, 1)
			local k = 1 - (1 - a) ^ 3
			for _, d in ipairs(e.doors) do
				if d.hinge then
					local rel = d.hinge:Inverse() * d.closed
					d.part.CFrame = d.hinge * CFrame.Angles(0, d.angle * k, 0) * rel
				elseif d.open then
					d.part.CFrame = d.closed:Lerp(d.open, k)
				end
			end
			if a >= 1 then return end
			RunService.Heartbeat:Wait()
		end
	end)
end

local function setEscapeVisual(e, on)
	e.zone:SetAttribute("Active", on)
	e.lamp.Color = on and GREEN or LAMP_RED
	e.light.Color = on and GREEN or LAMP_RED
	e.light.Range = on and 30 or 18
	e.light.Brightness = on and 3 or 1.2
	if e.beam then e.beam.Transparency = on and 0.6 or 1 end
	animateDoors(e, on)
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

-- створка-«дверь» (одна опорная деталь, декор приварен к ней)
local function leaf(m, size, cf, color, mat)
	return mk(m, "GateLeaf", size, cf, color, mat)
end

-- двустворчатые ворота на петлях (сетка-рабица или доски); створки открываются наружу
local function swingGate(width, height, style)
	return function(m, g)
		local doors = {}
		local postC = style == "wood" and Color3.fromRGB(70, 50, 34) or Color3.fromRGB(70, 74, 78)
		local postM = style == "wood" and M.Wood or M.Metal
		for _, s in ipairs({ -1, 1 }) do
			mk(m, "GatePost", Vector3.new(1, height + 2, 1), g * CFrame.new(s * (width / 2 + 0.5), (height + 2) / 2, 0), postC, postM)
			local lw = width / 2
			local cf = g * CFrame.new(s * lw / 2, height / 2 + 0.3, 0)
			local p
			if style == "wood" then
				p = leaf(m, Vector3.new(lw - 0.1, height, 0.4), cf, Color3.fromRGB(96, 66, 42), M.WoodPlanks)
				for _, y in ipairs({ -0.3, 0.3 }) do
					weldTo(mk(m, "GateBar", Vector3.new(lw - 0.3, 0.6, 0.3), cf * CFrame.new(0, y * height, -0.3), Color3.fromRGB(70, 48, 30), M.Wood), p)
				end
				weldTo(mk(m, "GateBrace", Vector3.new(0.5, height * 1.05, 0.3), cf * CFrame.new(0, 0, -0.3) * CFrame.Angles(0, 0, math.rad(s * 35)), Color3.fromRGB(70, 48, 30), M.Wood), p)
			else
				p = leaf(m, Vector3.new(lw - 0.1, height, 0.15), cf, Color3.fromRGB(90, 96, 100), M.Metal)
				p.Transparency = 0.45
				for _, e in ipairs({ { 0, height / 2 - 0.15, lw, 0.25 }, { 0, -height / 2 + 0.15, lw, 0.25 }, { s * (lw / 2 - 0.15), 0, 0.25, height } }) do
					weldTo(mk(m, "GateFrame", Vector3.new(e[3], e[4], 0.25), cf * CFrame.new(e[1], e[2], 0), Color3.fromRGB(70, 74, 78), M.Metal), p)
				end
			end
			-- петля у столба; поворот наружу (от игрока)
			local hinge = g * CFrame.new(s * width / 2, 0, 0)
			table.insert(doors, { part = p, hinge = hinge, angle = math.rad(s * 100) })
		end
		doors.lampY = height + 2.6
		return doors
	end
end

-- рольставня / решётка, уезжающая вверх
local function shutterGate(width, height, color, ribs)
	return function(m, g)
		local p = leaf(m, Vector3.new(width, height, 0.4), g * CFrame.new(0, height / 2, -0.4), color, M.Metal)
		for i = 1, (ribs or 10) do
			local y = -height / 2 + i * height / ((ribs or 10) + 1)
			weldTo(mk(m, "Rib", Vector3.new(width, 0.2, 0.2), g * CFrame.new(0, height / 2 + y, -0.65), color:Lerp(BLACK, 0.3), M.Metal), p)
		end
		local doors = { { part = p, open = p.CFrame + Vector3.new(0, height - 0.6, 0) } }
		doors.lampY = height + 1.2
		return doors
	end
end

-- раздвижные двери (одна или две створки уезжают вбок)
local function slideGate(width, height, color, halves)
	return function(m, g)
		local doors = {}
		if halves == 2 then
			for _, s in ipairs({ -1, 1 }) do
				local p = leaf(m, Vector3.new(width / 2, height, 0.5), g * CFrame.new(s * width / 4, height / 2, -0.3), color, M.Metal)
				weldTo(mk(m, "Stripe", Vector3.new(width / 2, 0.6, 0.1), g * CFrame.new(s * width / 4, height * 0.35, -0.6), Color3.fromRGB(230, 180, 30), M.SmoothPlastic), p)
				table.insert(doors, { part = p, open = p.CFrame * CFrame.new(s * width / 2, 0, 0) })
			end
		else
			local p = leaf(m, Vector3.new(width, height, 0.4), g * CFrame.new(0, height / 2, -0.3), color, M.Metal)
			weldTo(mk(m, "Handle", Vector3.new(0.2, 1.2, 0.2), g * CFrame.new(width * 0.35, height * 0.45, -0.6), Color3.fromRGB(200, 200, 205), M.Metal), p)
			table.insert(doors, { part = p, open = p.CFrame * CFrame.new(width, 0, 0) })
		end
		doors.lampY = height + 1.2
		return doors
	end
end

------------------------------------------------------------------------
-- КАРТЫ
------------------------------------------------------------------------
local MAPS = {}
do
	--------------------------------------------------------------------
	-- ТУМАННЫЙ ЛЕС: ночная лесопилка, водонапорная башня, домик лесника, лагерь
	--------------------------------------------------------------------
	local function buildForest(o)
		local def = newMap(MAP_INFO[1], o, 116)
		local m = def.model
		local r = Random.new(11)
		local function B(...) return box(m, o, ...) end
		local exits = {
			{ x = 40, z = -112, normal = Vector3.new(0, 0, 1), label = "ВОРОТА ЛЕСОПИЛКИ" },
			{ x = 112, z = 15, normal = Vector3.new(-1, 0, 0), label = "СТАРЫЙ ТОННЕЛЬ" },
			{ x = -112, z = -50, normal = Vector3.new(1, 0, 0), label = "КПП ЛЕСНИЧЕСТВА" },
		}
		-- ландшафт: земля, холмы-стены вокруг, проходы к воротам
		terra("FillBlock", CFrame.new(o + Vector3.new(0, -10, 0)), Vector3.new(600, 20, 600), M.Grass)
		local ringExits = {}
		for _, e in ipairs(exits) do
			table.insert(ringExits, { pos = Vector3.new(e.x, 0, e.z) - e.normal * 6, normal = e.normal })
		end
		hillRing(o, 152, { M.Rock, M.Grass, M.Rock }, r, ringExits, 20)
		-- холмы внутри: подъёмы и укрытия
		terra("FillBall", o + Vector3.new(70, -18, 40), 30, M.Rock)
		terra("FillBall", o + Vector3.new(-25, -17, 45), 26, M.Grass)
		terra("FillBall", o + Vector3.new(-80, -20, -75), 26, M.Grass)
		reserve(def, 70, 40, 26)
		reserve(def, -25, 45, 22)
		reserve(def, -80, -75, 20)
		-- тропы
		local function path(a, b, w)
			local mid = (a + b) / 2
			terra("FillBlock", CFrame.lookAt(o + Vector3.new(mid.X, -1.5, mid.Z), o + Vector3.new(b.X, -1.5, b.Z)), Vector3.new(w or 9, 3, (b - a).Magnitude), M.Mud)
		end
		path(Vector3.new(0, 0, 105), Vector3.new(0, 0, -10))
		path(Vector3.new(0, 0, -10), Vector3.new(40, 0, -112))
		path(Vector3.new(0, 0, -10), Vector3.new(-112, 0, -50))
		path(Vector3.new(0, 0, -10), Vector3.new(112, 0, 15))
		path(Vector3.new(-65, 0, -25), Vector3.new(-70, 0, 70))

		-- ворота
		addEscape(def, exits[1].x, exits[1].z, exits[1].label, exits[1].normal, swingGate(14, 9, "metal"))
		addEscape(def, exits[2].x, exits[2].z, exits[2].label, exits[2].normal, function(gm, g)
			-- портал тоннеля в скале: бетонная арка, внутри темнота и лампы
			for _, s in ipairs({ -1, 1 }) do
				mk(gm, "Portal", Vector3.new(4, 14, 3), g * CFrame.new(s * 8.5, 7, 1), Color3.fromRGB(110, 108, 104), M.Concrete)
			end
			mk(gm, "PortalTop", Vector3.new(21, 4, 3), g * CFrame.new(0, 15, 1), Color3.fromRGB(110, 108, 104), M.Concrete)
			local sign = mk(gm, "TunnelSign", Vector3.new(10, 2, 0.3), g * CFrame.new(0, 15, -0.7), Color3.fromRGB(30, 30, 32), M.SmoothPlastic, NOCOL)
			surfaceText(sign, Enum.NormalId.Front, "ТОННЕЛЬ №3", { color = Color3.fromRGB(220, 210, 180) })
			mk(gm, "TunnelFloor", Vector3.new(13, 1, 60), g * CFrame.new(0, -0.4, 31), Color3.fromRGB(60, 58, 56), M.Concrete)
			mk(gm, "TunnelRoof", Vector3.new(17, 1, 60), g * CFrame.new(0, 13.5, 31), Color3.fromRGB(60, 58, 56), M.Concrete)
			for _, s in ipairs({ -1, 1 }) do
				mk(gm, "TunnelWall", Vector3.new(1, 14, 60), g * CFrame.new(s * 7, 7, 31), Color3.fromRGB(70, 68, 64), M.Concrete)
			end
			for i = 1, 3 do
				local l = mk(gm, "TunnelLamp", Vector3.new(1, 0.4, 1), g * CFrame.new(0, 13, i * 16), Color3.fromRGB(255, 170, 80), M.Neon, NOCOL)
				pointLight(l, Color3.fromRGB(255, 160, 80), 16, 1)
			end
			return shutterGate(13, 12, Color3.fromRGB(60, 50, 44), 6)(gm, g)
		end)
		addEscape(def, exits[3].x, exits[3].z, exits[3].label, exits[3].normal, function(gm, g)
			-- КПП: будка со шлагбаумом и откатные ворота
			mk(gm, "Booth", Vector3.new(5, 8, 5), g * CFrame.new(11, 4, 2), Color3.fromRGB(90, 110, 80), M.WoodPlanks)
			mk(gm, "BoothRoof", Vector3.new(6, 0.6, 6), g * CFrame.new(11, 8.3, 2), Color3.fromRGB(50, 50, 50), M.Metal)
			local win = mk(gm, "BoothWindow", Vector3.new(3, 2, 0.2), g * CFrame.new(11, 5, -0.55), Color3.fromRGB(255, 200, 120), M.Neon, NOCOL)
			pointLight(win, Color3.fromRGB(255, 190, 110), 14, 0.8)
			local s = mk(gm, "Sign", Vector3.new(7, 1.6, 0.2), g * CFrame.new(-11, 6, 0), Color3.fromRGB(240, 240, 230), M.SmoothPlastic)
			surfaceText(s, Enum.NormalId.Front, "ПРОЕЗД ЗАКРЫТ", { color = Color3.fromRGB(180, 20, 20) })
			mk(gm, "SignPost", Vector3.new(0.3, 5, 0.3), g * CFrame.new(-11, 2.5, 0.2), Color3.fromRGB(70, 70, 70), M.Metal)
			return slideGate(14, 8, Color3.fromRGB(90, 96, 90), 1)(gm, g)
		end)
		-- заборы у ворот (закрывают щели прохода)
		for _, e in ipairs(exits) do
			local g = CFrame.lookAt(o + Vector3.new(e.x, 0, e.z) - e.normal * 6, o + Vector3.new(e.x, 0, e.z))
			for _, s in ipairs({ -1, 1 }) do
				mk(m, "Fence", Vector3.new(4, 9, 0.3), g * CFrame.new(s * 10, 4.5, 0), Color3.fromRGB(80, 84, 88), M.Metal, { Transparency = 0.4 })
			end
		end

		-- водонапорная башня (лестница на площадку — вертикальная петля)
		do
			local c = o + Vector3.new(0, 0, -10)
			for _, s in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
				local foot = c + Vector3.new(s[1] * 8, 0, s[2] * 8)
				local top = c + Vector3.new(s[1] * 6, 26, s[2] * 6)
				beam(m, "TowerLeg", foot, top, 1, Color3.fromRGB(40, 44, 48), M.Metal)
				mk(m, "Footing", Vector3.new(2.4, 1, 2.4), foot + Vector3.new(0, 0.5, 0), Color3.fromRGB(90, 90, 88), M.Concrete)
			end
			for _, y in ipairs({ 9, 18 }) do
				local k = 8 - y / 26 * 2
				for _, side in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
					local a, b
					if side[1] ~= 0 then
						a = c + Vector3.new(side[1] * k, y - 6, -k)
						b = c + Vector3.new(side[1] * k, y + 2, k)
					else
						a = c + Vector3.new(-k, y - 6, side[2] * k)
						b = c + Vector3.new(k, y + 2, side[2] * k)
					end
					beam(m, "Brace", a, b, 0.4, Color3.fromRGB(40, 44, 48), M.Metal)
				end
			end
			-- площадка-кольцо с перилами
			for i = 0, 7 do
				local a = i / 8 * math.pi * 2
				local cf = CFrame.new(c + Vector3.new(0, 26, 0)) * CFrame.Angles(0, a, 0)
				mk(m, "Catwalk", Vector3.new(8.6, 0.6, 3.4), cf * CFrame.new(0, 0, -9.5), Color3.fromRGB(60, 62, 64), M.DiamondPlate)
				mk(m, "CatwalkRail", Vector3.new(8.6, 0.25, 0.25), cf * CFrame.new(0, 3.5, -11.1), Color3.fromRGB(60, 62, 64), M.Metal)
				mk(m, "CatwalkPost", Vector3.new(0.25, 3.5, 0.25), cf * CFrame.new(4.2, 1.75, -11.1), Color3.fromRGB(60, 62, 64), M.Metal)
			end
			mk(m, "CatwalkFloor", Vector3.new(13, 0.6, 13), c + Vector3.new(0, 26, 0), Color3.fromRGB(60, 62, 64), M.DiamondPlate)
			cyl(m, "Tank", 12, 17, c + Vector3.new(0, 33, 0), Color3.fromRGB(46, 50, 54), M.CorrodedMetal)
			cyl(m, "TankRoof", 1.2, 18, c + Vector3.new(0, 39.5, 0), Color3.fromRGB(36, 40, 44), M.Metal)
			cyl(m, "TankCap", 2, 6, c + Vector3.new(0, 41, 0), Color3.fromRGB(36, 40, 44), M.Metal)
			local lamp = ball(m, "TowerLamp", 1.4, c + Vector3.new(0, 42.6, 0), Color3.fromRGB(200, 240, 255), M.Neon, NOCOL)
			pointLight(lamp, Color3.fromRGB(180, 220, 255), 40, 1.2)
			tag(lamp, "P2D_Blink", { Rate = 0.4 })
			ladder(m, c + Vector3.new(9.5, 0, 0), 26)
			mk(m, "LadderLanding", Vector3.new(3, 0.6, 3), c + Vector3.new(9.5, 26, 0), Color3.fromRGB(60, 62, 64), M.DiamondPlate)
			floodlight(m, c + Vector3.new(12, 0, 22), c, Color3.fromRGB(150, 240, 255))
			-- обломки заборов и ящики у подножья
			for _, p in ipairs({ { -14, 4 }, { -12, -14 }, { 14, -14 } }) do
				mk(m, "BrokenFence", Vector3.new(8, 4, 0.3), CFrame.new(c + Vector3.new(p[1], 2, p[2])) * CFrame.Angles(0, r:NextNumber(0, 3), math.rad(r:NextNumber(-12, 12))),
					Color3.fromRGB(80, 84, 88), M.Metal, { Transparency = 0.35 })
			end
			crate(m, c + Vector3.new(-6, 0, 14), 4, 0.3)
			crate(m, c + Vector3.new(-2, 0, 15), 3.5, 0.9)
			reserve(def, 0, -10, 16)
		end

		-- домик лесника: два входа (петля), телевизор с помехами
		do
			local x1, x2, z1, z2 = -77, -53, -34, -16
			local wallC = Color3.fromRGB(86, 62, 42)
			room(m, o, x1, x2, z1, z2, 10, wallC, M.WoodPlanks,
				{ E = { { c = -25, w = 6 } }, W = { { c = -25, w = 6 } }, N = { { c = -65, w = 3, h = 4 } }, S = { { c = -60, w = 3, h = 4 } } },
				{ noRoof = true, lampColor = Color3.fromRGB(255, 170, 90), flicker = true })
			B("CabinFloor", x1, x2, 0, 0.3, z1, z2, Color3.fromRGB(70, 50, 34), M.WoodPlanks)
			B("Ceiling", x1, x2, 10, 10.5, z1, z2, Color3.fromRGB(60, 44, 30), M.WoodPlanks)
			gableRoof(m, o + Vector3.new((x1 + x2) / 2, 10.5, (z1 + z2) / 2), x2 - x1 + 2, z2 - z1 + 2, 6, Color3.fromRGB(46, 34, 30), M.WoodPlanks, true)
			B("Porch", x2, x2 + 6, 0, 0.8, z1 + 2, z2 - 2, Color3.fromRGB(90, 66, 44), M.WoodPlanks)
			B("Bunk", x1 + 1, x1 + 5, 0, 2.5, z1 + 1, z1 + 9, Color3.fromRGB(110, 80, 60), M.Wood)
			B("Table", -66, -62, 0, 3, -21, -18, Color3.fromRGB(100, 72, 48), M.Wood)
			local tv = B("TV", -76, -72.5, 3, 6, -31, -28, Color3.fromRGB(40, 38, 42), M.SmoothPlastic)
			local scr = mk(m, "TVScreen", Vector3.new(0.1, 2.2, 2.4), tv.Position + Vector3.new(1.8, 0, 0), Color3.fromRGB(150, 170, 200), M.Neon, NOCOL)
			tag(scr, "P2D_Flicker", { Strong = true })
			pointLight(scr, Color3.fromRGB(150, 170, 255), 12, 0.8)
			B("TVStand", -76, -72, 0, 3, -32, -27, Color3.fromRGB(70, 50, 34), M.Wood)
			local porchLamp = B("PorchLamp", x2 + 0.2, x2 + 0.8, 7, 8, -26, -24, Color3.fromRGB(255, 190, 110), M.Neon, NOCOL)
			pointLight(porchLamp, Color3.fromRGB(255, 170, 90), 22, 1.4)
			tag(porchLamp, "P2D_Flicker")
			floodlight(m, o + Vector3.new(-40, 0, -8), o + Vector3.new(-60, 2, -25))
			reserve(def, -65, -25, 20)
		end

		-- лагерь: палатки, кострище, фургон
		do
			local function tent(cx, cz, yaw, col)
				local base = CFrame.new(o + Vector3.new(cx, 0, cz)) * CFrame.Angles(0, yaw, 0)
				local size = Vector3.new(7, 5, 3.5)
				mkc("WedgePart", m, "Tent", size, base * CFrame.new(0, 2.5, -1.75), col, M.Fabric)
				mkc("WedgePart", m, "Tent", size, base * CFrame.new(0, 2.5, 1.75) * CFrame.Angles(0, math.pi, 0), col, M.Fabric)
				reserve(def, cx, cz, 5)
			end
			tent(-85, 60, 0.3, Color3.fromRGB(60, 90, 60))
			tent(-62, 82, -0.6, Color3.fromRGB(140, 60, 40))
			tent(-92, 85, 1.2, Color3.fromRGB(60, 70, 110))
			local fire = o + Vector3.new(-72, 0, 72)
			for i = 0, 7 do
				local a = i / 8 * math.pi * 2
				boulder(m, fire + Vector3.new(math.cos(a) * 2.6, 0, math.sin(a) * 2.6), 1.1, r)
			end
			local embers = ball(m, "Embers", 1.6, fire + Vector3.new(0, 0.2, 0), Color3.fromRGB(255, 90, 30), M.Neon, NOCOL)
			pointLight(embers, Color3.fromRGB(255, 110, 40), 16, 1.2)
			tag(embers, "P2D_Flicker")
			B("Picnic", -60, -54, 0, 3, 62, 66, Color3.fromRGB(90, 66, 44), M.Wood)
			-- фургон (большой объект для петель)
			local van = CFrame.new(o + Vector3.new(-42, 0, 52)) * CFrame.Angles(0, math.rad(20), 0)
			mk(m, "Camper", Vector3.new(8, 8, 20), van * CFrame.new(0, 4.8, 0), Color3.fromRGB(200, 196, 180), M.Metal)
			mk(m, "CamperStripe", Vector3.new(8.1, 0.8, 20.1), van * CFrame.new(0, 4, 0), Color3.fromRGB(140, 60, 40), M.SmoothPlastic, NOCOL)
			mk(m, "CamperWin", Vector3.new(8.15, 1.6, 12), van * CFrame.new(0, 6.4, 1), Color3.fromRGB(20, 24, 30), M.Glass, NOCOL)
			for _, w in ipairs({ { -4, -6 }, { 4, -6 }, { -4, 6 }, { 4, 6 } }) do
				mk(m, "Wheel", Vector3.new(1.2, 3, 3), van * CFrame.new(w[1], 1.5, w[2]), Color3.fromRGB(18, 18, 18), M.SmoothPlastic, { Shape = CYL })
			end
			reserve(def, -42, 52, 13)
			reserve(def, -72, 72, 6)
			floodlight(m, o + Vector3.new(-50, 0, 90), fire)
		end

		-- лесопилка: навес с погрузочной платформой и пандусом, штабеля брёвен, лесовоз
		do
			local x1, x2, z1, z2 = 44, 78, -82, -60
			for _, x in ipairs({ x1, (x1 + x2) / 2, x2 }) do
				for _, z in ipairs({ z1, z2 }) do
					B("ShedPost", x - 0.6, x + 0.6, 0, 12, z - 0.6, z + 0.6, Color3.fromRGB(70, 52, 36), M.Wood)
				end
			end
			B("ShedRoof", x1 - 2, x2 + 2, 12, 12.8, z1 - 2, z2 + 2, Color3.fromRGB(60, 56, 52), M.CorrodedMetal)
			B("LoadDeck", x1 + 2, x2 - 10, 0, 4, z1 + 2, z2 - 2, Color3.fromRGB(90, 70, 48), M.WoodPlanks)
			ramp(m, o + Vector3.new(x2 - 5, 0, (z1 + z2) / 2), 8, 4, 10, Vector3.new(-1, 0, 0), Color3.fromRGB(90, 70, 48), M.WoodPlanks)
			B("Saw", x1 + 8, x1 + 18, 4, 6, z1 + 6, z1 + 9, Color3.fromRGB(60, 60, 64), M.Metal)
			local blade = mk(m, "SawBlade", Vector3.new(0.3, 5, 5), CFrame.new(o + Vector3.new(x1 + 13, 6.5, z1 + 7.5)) * ALONG_Z, Color3.fromRGB(180, 180, 186), M.Metal, { Shape = CYL })
			blade.CanCollide = false
			local bulb = B("ShedLamp", 60, 62, 11, 11.6, -72, -70, Color3.fromRGB(255, 200, 120), M.Neon, NOCOL)
			pointLight(bulb, Color3.fromRGB(255, 180, 100), 26, 1.2)
			tag(bulb, "P2D_Flicker")
			local function logPile(cx, cz, yaw, rows)
				local base = CFrame.new(o + Vector3.new(cx, 0, cz)) * CFrame.Angles(0, yaw, 0)
				for row = 0, rows - 1 do
					for k = 0, rows - 1 - row do
						local x = (k - (rows - 1 - row) / 2) * 2.4
						mk(m, "Log", Vector3.new(16, 2.4, 2.4), base * CFrame.new(0, 1.2 + row * 2.1, x), Color3.fromRGB(96, 70, 46), M.Wood, { Shape = CYL })
					end
				end
				reserve(def, cx, cz, 9)
			end
			logPile(30, -92, 0.1, 4)
			logPile(92, -40, 1.5, 3)
			logPile(26, -55, -0.3, 3)
			-- лесовоз
			local truck = CFrame.new(o + Vector3.new(88, 0, -12)) * CFrame.Angles(0, math.rad(10), 0)
			mk(m, "TruckCab", Vector3.new(8, 8, 7), truck * CFrame.new(0, 4.5, -12), Color3.fromRGB(120, 30, 26), M.Metal)
			mk(m, "TruckWin", Vector3.new(8.1, 2, 4), truck * CFrame.new(0, 6.5, -13), Color3.fromRGB(20, 24, 30), M.Glass, NOCOL)
			mk(m, "TruckBed", Vector3.new(8, 1.2, 20), truck * CFrame.new(0, 2.4, 2), Color3.fromRGB(50, 50, 54), M.Metal)
			for k = -1, 1 do
				mk(m, "TruckLog", Vector3.new(19, 2.6, 2.6), truck * CFrame.new(k * 2.6, 4.3, 2) * ALONG_Z, Color3.fromRGB(96, 70, 46), M.Wood, { Shape = CYL })
			end
			for _, w in ipairs({ { -4, -12 }, { 4, -12 }, { -4, 6 }, { 4, 6 }, { -4, 10 }, { 4, 10 } }) do
				mk(m, "Wheel", Vector3.new(1.4, 3.6, 3.6), truck * CFrame.new(w[1], 1.8, w[2]), Color3.fromRGB(18, 18, 18), M.SmoothPlastic, { Shape = CYL })
			end
			reserve(def, 61, -71, 22)
			reserve(def, 88, -12, 16)
			floodlight(m, o + Vector3.new(38, 0, -46), o + Vector3.new(60, 0, -72), Color3.fromRGB(255, 220, 170))
		end

		-- скалистый холм со смотровой площадкой
		do
			local top = o + Vector3.new(70, 0, 40)
			local y = groundY(top + Vector3.new(0, 20, 0))
			mk(m, "Lookout", Vector3.new(8, 0.6, 8), Vector3.new(top.X, y + 0.3, top.Z), Color3.fromRGB(90, 66, 44), M.WoodPlanks)
			railing(m, Vector3.new(top.X - 4, y + 0.6, top.Z - 4), Vector3.new(top.X + 4, y + 0.6, top.Z - 4), 3, Color3.fromRGB(70, 52, 36))
			railing(m, Vector3.new(top.X + 4, y + 0.6, top.Z - 4), Vector3.new(top.X + 4, y + 0.6, top.Z + 4), 3, Color3.fromRGB(70, 52, 36))
			for _ = 1, 6 do
				local p = top + Vector3.new(r:NextNumber(-22, 22), 0, r:NextNumber(-22, 22))
				boulder(m, Vector3.new(p.X, groundY(p + Vector3.new(0, 30, 0)) - 1, p.Z), r:NextNumber(4, 8), r)
			end
		end

		-- остов школьного автобуса
		do
			local bus = CFrame.new(o + Vector3.new(52, 0, 74)) * CFrame.Angles(0, math.rad(32), math.rad(4))
			mk(m, "Bus", Vector3.new(8.5, 8, 28), bus * CFrame.new(0, 5, 0), Color3.fromRGB(176, 130, 30), M.CorrodedMetal)
			mk(m, "BusWin", Vector3.new(8.6, 2.2, 22), bus * CFrame.new(0, 6.8, 1), Color3.fromRGB(16, 18, 22), M.Glass, NOCOL)
			mk(m, "BusStripe", Vector3.new(8.6, 0.5, 28.1), bus * CFrame.new(0, 4.4, 0), Color3.fromRGB(30, 30, 30), M.SmoothPlastic, NOCOL)
			for _, w in ipairs({ { -4.3, -9 }, { 4.3, -9 }, { -4.3, 9 }, { 4.3, 9 } }) do
				mk(m, "Wheel", Vector3.new(1.2, 3, 3), bus * CFrame.new(w[1], 1.5, w[2]), Color3.fromRGB(18, 18, 18), M.SmoothPlastic, { Shape = CYL })
			end
			reserve(def, 52, 74, 17)
		end

		-- поваленные деревья (перепрыгнуть) и валуны
		for _, l in ipairs({ { -30, -60, 0.3 }, { 30, 20, 1.2 }, { -95, 5, 2 }, { -12, 70, 0.8 }, { 95, 85, 2.4 } }) do
			mk(m, "FallenTree", Vector3.new(18, 2.6, 2.6), CFrame.new(o + Vector3.new(l[1], 1.3, l[2])) * CFrame.Angles(0, l[3], 0), Color3.fromRGB(64, 46, 32), M.Wood, { Shape = CYL })
			reserve(def, l[1], l[2], 6)
		end
		floodlight(m, o + Vector3.new(20, 0, 98), o + Vector3.new(0, 0, 70), Color3.fromRGB(255, 230, 190))

		-- спавны: выжившие на юге, Палач у лесопилки
		for _, p in ipairs({ { -20, 98 }, { 0, 104 }, { 20, 100 }, { -40, 104 }, { 35, 92 } }) do addSpawn(def, "Survivor", p[1], p[2]) end
		for _, p in ipairs({ { 60, -94 }, { 82, -88 }, { 46, -100 } }) do addSpawn(def, "Killer", p[1], p[2]) end

		-- деревья: в зоне — укрытия, на холмах по краю — стена леса
		scatter(def, r, 34, 108, 5, function(x, z)
			pine(m, o + Vector3.new(x, 0, z), r:NextNumber(26, 40), r)
			reserve(def, x, z, 2)
		end)
		scatter(def, r, 26, 110, 3, function(x, z)
			bush(m, o + Vector3.new(x, 0, z), r, Color3.fromRGB(28, 44, 30))
		end)
		for _ = 1, 110 do
			local side = r:NextInteger(1, 4)
			local t = r:NextNumber(-190, 190)
			local d = r:NextNumber(124, 200)
			local x, z
			if side == 1 then x, z = t, -d elseif side == 2 then x, z = t, d elseif side == 3 then x, z = -d, t else x, z = d, t end
			local nearExit = false
			for _, e in ipairs(exits) do
				if (Vector3.new(x, 0, z) - Vector3.new(e.x, 0, e.z) + e.normal * 40).Magnitude < 40 then nearExit = true end
			end
			if not nearExit then
				local p = o + Vector3.new(x, 0, z)
				pine(m, Vector3.new(p.X, groundY(p + Vector3.new(0, 40, 0)) - 1, p.Z), r:NextNumber(34, 52), r, 2)
			end
		end
		return def
	end

	--------------------------------------------------------------------
	-- КОМПЛЕКС: закрытый завод (пол, стены, потолок), антресоль с мостом, контейнеры
	--------------------------------------------------------------------
	local function buildComplex(o)
		local def = newMap(MAP_INFO[2], o, 118)
		def.beamH = 0
		local m = def.model
		local r = Random.new(21)
		local function B(...) return box(m, o, ...) end
		local H = 32
		local FLOOR = Color3.fromRGB(28, 30, 36)
		local WALL = Color3.fromRGB(44, 48, 58)
		local STEEL = Color3.fromRGB(58, 62, 72)
		local YEL = Color3.fromRGB(230, 180, 30)
		local REDL = Color3.fromRGB(255, 40, 40)

		B("Floor", -124, 124, -2, 0, -124, 124, FLOOR, M.SmoothPlastic)
		for k = -112, 112, 8 do
			B("Grid", k - 0.08, k + 0.08, 0, 0.03, -120, 120, Color3.fromRGB(64, 72, 92), M.SmoothPlastic, FLAT)
			B("Grid", -120, 120, 0, 0.03, k - 0.08, k + 0.08, Color3.fromRGB(64, 72, 92), M.SmoothPlastic, FLAT)
		end
		-- наружные стены с проёмами под выходы
		local function outer(a, b, gaps)
			wallWithGaps(m, o + a, o + b, H, 2, WALL, M.DiamondPlate, gaps)
		end
		outer(Vector3.new(-122, 0, -121), Vector3.new(122, 0, -121), {})
		outer(Vector3.new(-122, 0, 121), Vector3.new(122, 0, 121), { { t = 202, w = 14, h = 12 } })      -- x = 80
		outer(Vector3.new(-121, 0, -122), Vector3.new(-121, 0, 122), { { t = 182, w = 6, h = 9 } })      -- z = 60
		outer(Vector3.new(121, 0, -122), Vector3.new(121, 0, 122), { { t = 42, w = 10, h = 10 } })       -- z = -80
		B("Ceiling", -124, 124, H, H + 2, -124, 124, Color3.fromRGB(22, 24, 28), M.Metal)
		for x = -100, 100, 20 do
			B("CeilBeam", x - 0.8, x + 0.8, H - 2, H, -120, 120, Color3.fromRGB(36, 38, 44), M.Metal)
		end
		for t = -100, 100, 25 do
			for _, s in ipairs({ -1, 1 }) do
				B("Pilaster", s * 120 - 1, s * 120 + 1, 0, H, t - 1, t + 1, STEEL, M.Metal)
				B("Pilaster", t - 1, t + 1, 0, H, s * 120 - 1, s * 120 + 1, STEEL, M.Metal)
			end
		end
		B("PipeN", -118, 118, 22, 23.6, -119, -117.4, Color3.fromRGB(90, 60, 40), M.Metal)
		B("PipeE", 117.4, 119, 20, 21.6, -118, 118, Color3.fromRGB(60, 80, 90), M.Metal)
		-- коридорчики за проёмами (видно, что выход куда-то ведёт)
		local function vestibule(cx, cz, nx, nz, w, h)
			local back = o + Vector3.new(cx, 0, cz) - Vector3.new(nx, 0, nz) * 9
			local across = Vector3.new(math.abs(nz), 0, math.abs(nx))
			local along = Vector3.new(math.abs(nx), 0, math.abs(nz))
			mk(m, "VestFloor", across * (w + 2) + along * 14 + Vector3.new(0, 1, 0), back - Vector3.new(0, 0.5, 0), FLOOR, M.SmoothPlastic)
			mk(m, "VestRoof", across * (w + 2) + along * 14 + Vector3.new(0, 1, 0), back + Vector3.new(0, h + 0.5, 0), WALL, M.Metal)
			for _, s in ipairs({ -1, 1 }) do
				mk(m, "VestWall", across + along * 14 + Vector3.new(0, h, 0), back + across * (s * (w / 2 + 1)) + Vector3.new(0, h / 2, 0), WALL, M.DiamondPlate)
			end
			mk(m, "VestEnd", across * (w + 2) + along + Vector3.new(0, h, 0), back - Vector3.new(nx, 0, nz) * 7 + Vector3.new(0, h / 2, 0), WALL, M.DiamondPlate)
			local l = mk(m, "VestLamp", Vector3.new(2, 0.4, 2), back + Vector3.new(0, h - 0.3, 0), Color3.fromRGB(180, 255, 200), M.Neon, NOCOL)
			pointLight(l, Color3.fromRGB(150, 255, 180), 14, 1)
		end
		vestibule(80, 121, 0, -1, 14, 12)
		vestibule(-121, 60, 1, 0, 6, 9)
		vestibule(121, -80, -1, 0, 10, 10)
		addEscape(def, 80, 115, "ГРУЗОВЫЕ ВОРОТА", Vector3.new(0, 0, -1), shutterGate(14, 12, Color3.fromRGB(120, 116, 104), 12))
		addEscape(def, -115, 60, "АВАРИЙНЫЙ ВЫХОД", Vector3.new(1, 0, 0), function(gm, g)
			local s = mk(gm, "ExitSign", Vector3.new(4, 1.2, 0.3), g * CFrame.new(0, 10.6, -0.8), Color3.fromRGB(20, 140, 60), M.Neon, NOCOL)
			surfaceText(s, Enum.NormalId.Front, "ВЫХОД", { color = Color3.fromRGB(230, 255, 230) })
			return slideGate(6, 9, Color3.fromRGB(150, 40, 36), 1)(gm, g)
		end)
		addEscape(def, 115, -80, "ШЛЮЗ", Vector3.new(-1, 0, 0), slideGate(10, 10, Color3.fromRGB(70, 76, 86), 2))

		-- антресоль на севере (над офисами), пандусы, мост через цех и южная площадка
		B("Mezzanine", -110, 30, 9, 10, -120, -100, STEEL, M.DiamondPlate)
		for x = -100, 20, 20 do B("Column", x - 0.8, x + 0.8, 0, 9, -101.6, -100, STEEL, M.Metal) end
		railing(m, o + Vector3.new(-104, 10, -100), o + Vector3.new(-3, 10, -100), 3.5, YEL)
		railing(m, o + Vector3.new(3, 10, -100), o + Vector3.new(24, 10, -100), 3.5, YEL)
		ramp(m, o + Vector3.new(-107, 0, -87), 6, 10, 26, Vector3.new(0, 0, -1), STEEL, M.DiamondPlate)
		ramp(m, o + Vector3.new(27, 0, -87), 6, 10, 26, Vector3.new(0, 0, -1), STEEL, M.DiamondPlate)
		B("Bridge", -3, 3, 9, 10, -100, 40, STEEL, M.DiamondPlate)
		railing(m, o + Vector3.new(-3, 10, -100), o + Vector3.new(-3, 10, 40), 3.5, YEL)
		railing(m, o + Vector3.new(3, 10, -100), o + Vector3.new(3, 10, 40), 3.5, YEL)
		for _, z in ipairs({ -60, -20, 20 }) do B("BridgeLeg", -0.6, 0.6, 0, 9, z - 0.6, z + 0.6, STEEL, M.Metal) end
		B("SouthDeck", -30, 30, 9, 10, 40, 56, STEEL, M.DiamondPlate)
		for _, c in ipairs({ { -29, 41 }, { 29, 41 }, { -29, 55 }, { 29, 55 } }) do B("DeckLeg", c[1] - 0.7, c[1] + 0.7, 0, 9, c[2] - 0.7, c[2] + 0.7, STEEL, M.Metal) end
		railing(m, o + Vector3.new(-30, 10, 40), o + Vector3.new(-3, 10, 40), 3.5, YEL)
		railing(m, o + Vector3.new(3, 10, 40), o + Vector3.new(30, 10, 40), 3.5, YEL)
		railing(m, o + Vector3.new(-30, 10, 56), o + Vector3.new(30, 10, 56), 3.5, YEL)
		railing(m, o + Vector3.new(-30, 10, 40), o + Vector3.new(-30, 10, 56), 3.5, YEL)
		ramp(m, o + Vector3.new(43, 0, 48), 6, 10, 26, Vector3.new(-1, 0, 0), STEEL, M.DiamondPlate)
		for _, p in ipairs({ { -107, -76 }, { 27, -76 }, { 57, 48 } }) do
			for k = 0, 3 do
				B("Hazard", p[1] - 3 + k * 1.5, p[1] - 2.25 + k * 1.5, 0, 0.04, p[2] - 1, p[2] + 1, k % 2 == 0 and YEL or BLACK, M.SmoothPlastic, FLAT)
			end
		end
		reserve(def, 0, -40, 4)

		-- офисы под антресолью
		for i, cx in ipairs({ -90, -50, -10 }) do
			room(m, o, cx - 17, cx + 17, -119, -102.4, 8.4, Color3.fromRGB(70, 74, 84), M.SmoothPlastic,
				{ S = { { c = cx + (i == 2 and -8 or 8), w = 6 } } }, { lampColor = Color3.fromRGB(200, 220, 255), flicker = i == 2, lampBrightness = 0.8 })
			B("Desk", cx - 6, cx + 2, 0, 3, -115, -111, Color3.fromRGB(90, 80, 70), M.Wood)
			local mon = B("Monitor", cx - 4, cx - 1, 3, 5.4, -114.5, -112.5, Color3.fromRGB(40, 40, 44), M.SmoothPlastic)
			local scr = mk(m, "MonitorScreen", Vector3.new(2.4, 1.8, 0.1), mon.Position + Vector3.new(0, 0, 1.05), Color3.fromRGB(120, 200, 150), M.Neon, NOCOL)
			tag(scr, "P2D_Flicker", { Strong = true })
			B("Cabinet", cx + 10, cx + 14, 0, 6, -118, -115, Color3.fromRGB(80, 84, 90), M.Metal)
		end
		for _, p in ipairs({ { -80, -92 }, { -50, -92 }, { -20, -92 }, { -100, -84 }, { 8, -92 } }) do addSpawn(def, "Survivor", p[1], p[2]) end

		-- контейнерный двор (некоторые — сквозные)
		local function container(cx, cz, alongX, col, open)
			local cf = CFrame.new(o + Vector3.new(cx, 0, cz)) * (alongX and CFrame.Angles(0, math.rad(90), 0) or CFrame.identity)
			if open then
				for _, s in ipairs({ -1, 1 }) do
					mk(m, "ContainerSide", Vector3.new(0.4, 8.5, 24), cf * CFrame.new(s * 4, 4.25, 0), col, M.CorrodedMetal)
				end
				mk(m, "ContainerTop", Vector3.new(8.4, 0.4, 24), cf * CFrame.new(0, 8.5, 0), col, M.CorrodedMetal)
			else
				mk(m, "Container", Vector3.new(8, 8.5, 24), cf * CFrame.new(0, 4.25, 0), col, M.CorrodedMetal)
			end
			for k = -5, 5 do
				for _, s in ipairs({ -1, 1 }) do
					mk(m, "Rib", Vector3.new(0.2, 8, 0.4), cf * CFrame.new(s * 4.2, 4.25, k * 2.1), col:Lerp(BLACK, 0.25), M.Metal, FLAT)
				end
			end
			reserve(def, cx, cz, 13)
		end
		container(-60, -50, true, Color3.fromRGB(150, 44, 32), false)
		container(-40, 10, false, Color3.fromRGB(40, 100, 60), true)
		container(40, -45, false, Color3.fromRGB(190, 100, 30), true)
		container(62, 12, true, Color3.fromRGB(40, 70, 130), false)
		container(-78, 62, true, Color3.fromRGB(110, 110, 116), false)
		crate(m, o + Vector3.new(-60, 0, -42.5), 4, 0)
		crate(m, o + Vector3.new(-64, 0, -42), 3.5, 0.4)
		crate(m, o + Vector3.new(-64, 4, -42), 3.5, 0.1)

		-- клетки с бочками под красным светом (как на референсе)
		local function cage(cx, cz)
			local x1, x2, z1, z2 = cx - 6, cx + 6, cz - 4, cz + 4
			for _, c in ipairs({ { x1, z1 }, { x2, z1 }, { x1, z2 }, { x2, z2 } }) do
				B("CagePost", c[1] - 0.3, c[1] + 0.3, 0, 7, c[2] - 0.3, c[2] + 0.3, REDL:Lerp(BLACK, 0.5), M.Metal)
			end
			for _, w in ipairs({ { x1, x2, z1, z1 + 0.15 }, { x1, x2, z2 - 0.15, z2 }, { x1, x1 + 0.15, z1, z2 }, { x2 - 0.15, x2, z1, z2 } }) do
				B("CageMesh", w[1], w[2], 0, 7, w[3], w[4], Color3.fromRGB(110, 30, 30), M.Metal, { Transparency = 0.55 })
			end
			for i = 0, 2 do
				for j = 0, 1 do barrel(m, o + Vector3.new(cx - 3.5 + i * 3.5, 0, cz - 1.6 + j * 3.2)) end
			end
			local glow = B("CageGlow", x1, x2, 0, 0.2, z1 - 0.4, z1 - 0.2, REDL, M.Neon, FLAT)
			pointLight(glow, REDL, 18, 1.4)
			reserve(def, cx, cz, 8)
		end
		cage(-95, 25)
		cage(60, -85)

		-- генераторная (две двери — петля), Палач появляется здесь
		room(m, o, 70, 118, -20, 50, 12, Color3.fromRGB(50, 46, 46), M.DiamondPlate,
			{ W = { { c = -5, w = 7 }, { c = 35, w = 7 } } }, { lampColor = REDL, lampBrightness = 0.8 })
		for _, g in ipairs({ { 92, 0 }, { 102, 34 } }) do
			B("Generator", g[1] - 6, g[1] + 6, 0, 7, g[2] - 8, g[2] + 8, Color3.fromRGB(70, 74, 60), M.Metal)
			cyl(m, "GenTank", 4, 5, o + Vector3.new(g[1], 9, g[2] - 3), Color3.fromRGB(90, 90, 80), M.Metal)
			cyl(m, "GenPipe", 6, 1.4, o + Vector3.new(g[1] + 3, 10, g[2] + 4), Color3.fromRGB(80, 60, 40), M.Metal)
			local beacon = ball(m, "Beacon", 1, o + Vector3.new(g[1], 7.6, g[2] + 6), REDL, M.Neon, NOCOL)
			pointLight(beacon, REDL, 16, 1.6)
			tag(beacon, "P2D_Blink", { Rate = 1.6 })
		end
		for _, p in ipairs({ { 80, 15 }, { 80, 25 }, { 80, 5 } }) do addSpawn(def, "Killer", p[1], p[2]) end
		reserve(def, 94, 15, 30)

		-- серверная (ряды стоек — короткие петли)
		room(m, o, -118, -74, -70, -10, 11, Color3.fromRGB(40, 44, 56), M.SmoothPlastic,
			{ E = { { c = -55, w = 7 }, { c = -25, w = 7 } } }, { lampColor = Color3.fromRGB(120, 160, 255), lampBrightness = 0.6 })
		for _, x in ipairs({ -110, -100, -90 }) do
			for _, z in ipairs({ { -64, -46 }, { -38, -16 } }) do
				B("Rack", x - 1.2, x + 1.2, 0, 9, z[1], z[2], Color3.fromRGB(24, 26, 30), M.Metal)
				for k = 0, 5 do
					local led = B("Led", x + 1.2, x + 1.35, 2 + k * 1.2, 2.3 + k * 1.2, z[1] + 1 + k * 2.5, z[1] + 1.6 + k * 2.5,
						k % 2 == 0 and Color3.fromRGB(80, 255, 120) or Color3.fromRGB(255, 80, 60), M.Neon, FLAT)
					if k % 3 == 0 then tag(led, "P2D_Blink", { Rate = 1 + k * 0.4 }) end
				end
			end
		end
		reserve(def, -96, -40, 30)

		-- погрузочная рампа на юге со сквозным прицепом
		B("Dock", -100, 50, 0, 4, 100, 120, Color3.fromRGB(80, 80, 84), M.Concrete)
		for k = 0, 37 do
			B("DockEdge", -100 + k * 4, -98 + k * 4, 4, 4.05, 100, 100.8, k % 2 == 0 and YEL or BLACK, M.SmoothPlastic, FLAT)
		end
		ramp(m, o + Vector3.new(-90, 0, 94), 8, 4, 12, Vector3.new(0, 0, 1), Color3.fromRGB(80, 80, 84), M.Concrete)
		ramp(m, o + Vector3.new(40, 0, 94), 8, 4, 12, Vector3.new(0, 0, 1), Color3.fromRGB(80, 80, 84), M.Concrete)
		local trailer = CFrame.new(o + Vector3.new(-30, 4, 110)) * CFrame.Angles(0, math.rad(90), 0)
		for _, s in ipairs({ -1, 1 }) do
			mk(m, "TrailerSide", Vector3.new(0.4, 9, 26), trailer * CFrame.new(s * 4.5, 4.5, 0), Color3.fromRGB(200, 200, 205), M.Metal)
		end
		mk(m, "TrailerTop", Vector3.new(9.4, 0.4, 26), trailer * CFrame.new(0, 9, 0), Color3.fromRGB(200, 200, 205), M.Metal)
		reserve(def, -25, 110, 24)

		-- конвейер, паллеты, штабеля ящиков
		B("Conveyor", -70, -10, 0, 2.6, 72, 76, Color3.fromRGB(50, 52, 58), M.Metal)
		for x = -68, -12, 3 do
			mk(m, "Roller", Vector3.new(4, 0.6, 0.6), CFrame.new(o + Vector3.new(x, 2.7, 74)) * ALONG_Z, Color3.fromRGB(130, 130, 136), M.Metal, { Shape = CYL })
		end
		reserve(def, -40, 74, 8)
		for _, p in ipairs({ { 20, -20 }, { -20, -78 }, { 78, 82 }, { -98, 92 }, { 95, -100 }, { -20, 30 } }) do
			pallet(m, o + Vector3.new(p[1], 0, p[2]), r:NextNumber(0, 3))
			crate(m, o + Vector3.new(p[1], 0.85, p[2]), r:NextNumber(3, 4), r:NextNumber(0, 1))
			reserve(def, p[1], p[2], 4)
		end
		for _, p in ipairs({ { 25, 85 }, { -60, 30 }, { 80, -40 } }) do
			crate(m, o + Vector3.new(p[1], 0, p[2]), 4.5, 0)
			crate(m, o + Vector3.new(p[1] + 4.6, 0, p[2]), 4.5, 0)
			crate(m, o + Vector3.new(p[1] + 2.3, 4.5, p[2]), 4.5, 0.2)
			reserve(def, p[1] + 2, p[2], 6)
		end

		-- станки и котёл посреди цеха: крупные укрытия, вокруг которых можно петлять
		local function machine(cx, cz, w, d, h, col)
			B("Machine", cx - w / 2, cx + w / 2, 0, h, cz - d / 2, cz + d / 2, col, M.Metal)
			B("MachineTop", cx - w / 2 + 1, cx + w / 2 - 1, h, h + 2, cz - d / 2 + 1, cz + d / 2 - 1, col:Lerp(BLACK, 0.3), M.Metal)
			B("MachineStripe", cx - w / 2 - 0.05, cx + w / 2 + 0.05, 1, 1.6, cz - d / 2 - 0.05, cz + d / 2 + 0.05, YEL, M.SmoothPlastic, FLAT)
			local lamp = B("MachineLamp", cx - 0.6, cx + 0.6, h + 2, h + 3, cz - 0.6, cz + 0.6, REDL, M.Neon, NOCOL)
			tag(lamp, "P2D_Blink", { Rate = 0.8 })
			reserve(def, cx, cz, math.max(w, d) / 2 + 3)
		end
		machine(-58, -14, 12, 9, 7, Color3.fromRGB(70, 86, 74))
		machine(-74, 40, 9, 12, 6, Color3.fromRGB(86, 74, 60))
		machine(58, -62, 10, 10, 6, Color3.fromRGB(74, 70, 86))
		cyl(m, "Boiler", 14, 11, o + Vector3.new(28, 7, 26), Color3.fromRGB(96, 80, 64), M.CorrodedMetal)
		cyl(m, "BoilerCap", 1, 12, o + Vector3.new(28, 14.5, 26), Color3.fromRGB(60, 50, 40), M.Metal)
		beam(m, "BoilerPipe", o + Vector3.new(28, 15, 26), o + Vector3.new(28, H - 1, 26), 1.4, Color3.fromRGB(80, 60, 40), M.Metal)
		reserve(def, 28, 26, 9)

		-- освещение: подвесные лампы, аварийные огни, прожекторы
		for _, x in ipairs({ -80, -20, 40, 90 }) do
			for _, z in ipairs({ -70, -20, 30, 80 }) do
				beam(m, "LampCable", o + Vector3.new(x, H - 2, z), o + Vector3.new(x, 23, z), 0.12, BLACK, M.Metal, NOCOL)
				mk(m, "LampShade", Vector3.new(3, 1, 3), o + Vector3.new(x, 22.5, z), Color3.fromRGB(40, 42, 46), M.Metal, NOCOL)
				local bulb = mk(m, "LampBulb", Vector3.new(2, 0.2, 2), o + Vector3.new(x, 21.9, z), Color3.fromRGB(255, 240, 210), M.Neon, NOCOL)
				spotLight(bulb, Enum.NormalId.Bottom, Color3.fromRGB(255, 230, 200), 40, 80, 1.3)
				if (x + z) % 3 == 0 then tag(bulb, "P2D_Flicker") end
			end
		end
		for _, p in ipairs({ { -119.5, -40 }, { -119.5, 20 }, { 119.5, 60 }, { 119.5, 100 }, { 0, -119.5 }, { -60, 119.5 } }) do
			local strobe = mk(m, "Strobe", Vector3.new(1, 1, 1), o + Vector3.new(p[1], 14, p[2]), REDL, M.Neon, NOCOL)
			pointLight(strobe, REDL, 26, 1.5)
			tag(strobe, "P2D_Blink", { Rate = 1.1 })
		end
		floodlight(m, o + Vector3.new(-20, 0, -60), o + Vector3.new(-40, 0, -40))
		floodlight(m, o + Vector3.new(45, 0, 70), o + Vector3.new(30, 0, 50))
		floodlight(m, o + Vector3.new(-100, 0, 5), o + Vector3.new(-95, 0, 25), Color3.fromRGB(255, 200, 200))
		return def
	end

	--------------------------------------------------------------------
	-- ФЕРМА на закате: амбар с сеновалом, дом, силос, мельница, кукурузное поле
	--------------------------------------------------------------------
	local function buildFarm(o)
		local def = newMap(MAP_INFO[3], o, 116)
		local m = def.model
		local r = Random.new(33)
		local function B(...) return box(m, o, ...) end
		local AUTUMN = { Color3.fromRGB(110, 70, 30), Color3.fromRGB(90, 80, 36), Color3.fromRGB(130, 60, 26), Color3.fromRGB(70, 66, 34) }
		local WOOD = Color3.fromRGB(110, 78, 50)
		local exits = {
			{ x = -10, z = 112, normal = Vector3.new(0, 0, -1), label = "ГЛАВНЫЕ ВОРОТА", w = 14 },
			{ x = -112, z = -25, normal = Vector3.new(1, 0, 0), label = "ВОРОТА ПАСТБИЩА", w = 12 },
			{ x = 60, z = -112, normal = Vector3.new(0, 0, 1), label = "КАЛИТКА ЗА СИЛОСОМ", w = 10 },
		}
		terra("FillBlock", CFrame.new(o + Vector3.new(0, -10, 0)), Vector3.new(600, 20, 600), M.LeafyGrass)
		local ringExits = {}
		for _, e in ipairs(exits) do
			table.insert(ringExits, { pos = Vector3.new(e.x, 0, e.z) - e.normal * 6, normal = e.normal })
		end
		hillRing(o, 160, { M.Sandstone, M.LeafyGrass }, r, ringExits, 22)
		terra("FillBall", o + Vector3.new(-30, -22, -70), 28, M.LeafyGrass)
		reserve(def, -30, -70, 20)
		local function path(a, b, w)
			local mid = (a + b) / 2
			terra("FillBlock", CFrame.lookAt(o + Vector3.new(mid.X, -1.5, mid.Z), o + Vector3.new(b.X, -1.5, b.Z)), Vector3.new(w or 9, 3, (b - a).Magnitude), M.Ground)
		end
		path(Vector3.new(-10, 0, 120), Vector3.new(-10, 0, 40))
		path(Vector3.new(-10, 0, 40), Vector3.new(30, 0, 20))
		path(Vector3.new(30, 0, -45), Vector3.new(60, 0, -116))
		path(Vector3.new(-55, 0, 8), Vector3.new(-116, 0, -25))

		-- забор по периметру с проёмами под ворота
		local function fenceLine(a, b, gaps)
			local dir = (b - a).Unit
			local len = (b - a).Magnitude
			local cur = 0
			table.sort(gaps, function(x, y) return x.t < y.t end)
			local segs = {}
			for _, g in ipairs(gaps) do
				table.insert(segs, { cur, g.t - g.w / 2 - 1 })
				cur = g.t + g.w / 2 + 1
			end
			table.insert(segs, { cur, len })
			for _, sgm in ipairs(segs) do
				local s0, s1 = sgm[1], sgm[2]
				if s1 - s0 > 0.5 then
					local p0, p1 = o + a + dir * s0, o + a + dir * s1
					local cf = CFrame.lookAt((p0 + p1) / 2, p1)
					mk(m, "FenceBoards", Vector3.new(0.4, 7, s1 - s0), cf + Vector3.new(0, 3.5, 0), Color3.fromRGB(96, 70, 46), M.WoodPlanks)
					mk(m, "FenceRail", Vector3.new(0.6, 0.6, s1 - s0), cf + Vector3.new(0, 6.6, 0), Color3.fromRGB(70, 50, 32), M.Wood)
					for k = 0, math.floor((s1 - s0) / 8) do
						mk(m, "FencePost", Vector3.new(0.9, 8, 0.9), p0 + dir * math.min(k * 8, s1 - s0) + Vector3.new(0, 4, 0), Color3.fromRGB(70, 50, 32), M.Wood)
					end
				end
			end
		end
		fenceLine(Vector3.new(-118, 0, -118), Vector3.new(118, 0, -118), { { t = 178, w = 10 } })
		fenceLine(Vector3.new(-118, 0, 118), Vector3.new(118, 0, 118), { { t = 108, w = 14 } })
		fenceLine(Vector3.new(-118, 0, -118), Vector3.new(-118, 0, 118), { { t = 93, w = 12 } })
		fenceLine(Vector3.new(118, 0, -118), Vector3.new(118, 0, 118), {})
		for _, e in ipairs(exits) do
			addEscape(def, e.x, e.z, e.label, e.normal, function(gm, g)
				if e.w >= 14 then
					-- арка над главными воротами
					for _, s in ipairs({ -1, 1 }) do
						mk(gm, "ArchPost", Vector3.new(1.2, 13, 1.2), g * CFrame.new(s * (e.w / 2 + 1.2), 6.5, 0), Color3.fromRGB(70, 50, 32), M.Wood)
					end
					local sign = mk(gm, "ArchSign", Vector3.new(e.w + 4, 2.4, 0.4), g * CFrame.new(0, 12, 0), Color3.fromRGB(120, 86, 56), M.WoodPlanks)
					surfaceText(sign, Enum.NormalId.Front, "ФЕРМА «ТИХИЙ ЛУГ»", { color = Color3.fromRGB(240, 220, 180) })
				end
				local doors = swingGate(e.w, 7, "wood")(gm, g)
				doors.lampY = e.w >= 14 and 14 or 9
				return doors
			end)
		end

		-- амбар: сквозной (двери с двух торцов и по бокам), сеновал с пандусом и лестницей
		do
			local x1, x2, z1, z2 = 10, 50, -45, 15
			local RED = Color3.fromRGB(130, 40, 30)
			room(m, o, x1, x2, z1, z2, 18, RED, M.WoodPlanks, {
				N = { { c = 30, w = 12, h = 14 } }, S = { { c = 30, w = 12, h = 14 } },
				W = { { c = -5, w = 6 } }, E = { { c = -20, w = 6 } },
			}, { noRoof = true, lamp = false })
			gableRoof(m, o + Vector3.new(30, 18, -15), 42, 62, 10, Color3.fromRGB(60, 44, 36), M.WoodPlanks)
			B("BarnFloor", x1, x2, 0, 0.3, z1, z2, Color3.fromRGB(110, 90, 60), M.WoodPlanks)
			for _, z in ipairs({ z1 - 0.9, z2 + 0.9 }) do
				for _, x in ipairs({ 19, 41 }) do
					B("BarnDoor", x - 4, x + 4, 0, 14, z - 0.3, z + 0.3, Color3.fromRGB(150, 50, 36), M.WoodPlanks)
				end
				B("DoorTrim", 23.5, 36.5, 14, 14.6, z - 0.4, z + 0.4, Color3.fromRGB(230, 220, 200), M.Wood)
			end
			B("Loft", x1 + 1, x2 - 1, 9, 10, z1 + 1, -18, Color3.fromRGB(120, 92, 60), M.WoodPlanks)
			railing(m, o + Vector3.new(x1 + 1, 10, -18), o + Vector3.new(38, 10, -18), 3, Color3.fromRGB(80, 60, 40))
			ramp(m, o + Vector3.new(44, 0, -7), 6, 10, 22, Vector3.new(0, 0, -1), Color3.fromRGB(120, 92, 60), M.WoodPlanks)
			ladder(m, o + Vector3.new(13, 0, -16.5), 10)
			for _, p in ipairs({ { 16, -30 }, { 16, -26 }, { 20, -30 } }) do
				B("Bale", p[1] - 2, p[1] + 2, 0, 2.6, p[2] - 1.3, p[2] + 1.3, Color3.fromRGB(210, 180, 90), M.Grass)
			end
			B("Bale", 15, 19, 2.6, 5.2, -31, -28.4, Color3.fromRGB(210, 180, 90), M.Grass)
			for _, x in ipairs({ 18, 26 }) do B("Stall", x - 0.25, x + 0.25, 0, 5, 0, 13, Color3.fromRGB(100, 76, 50), M.Wood) end
			for _, p in ipairs({ { 30, -32 }, { 30, 2 } }) do
				local lantern = B("Lantern", p[1] - 0.5, p[1] + 0.5, 16, 17, p[2] - 0.5, p[2] + 0.5, Color3.fromRGB(255, 190, 100), M.Neon, NOCOL)
				pointLight(lantern, Color3.fromRGB(255, 170, 80), 26, 1.2)
				tag(lantern, "P2D_Flicker")
			end
			for _, y in ipairs({ 13, 15 }) do
				B("Hayloft", 26, 34, y, y + 2, z1 - 0.95, z1 - 0.85, Color3.fromRGB(30, 22, 20), M.WoodPlanks, NOCOL)
			end
			reserve(def, 30, -15, 36)
		end

		-- трактор и пикап у амбара (большие укрытия)
		do
			local t = CFrame.new(o + Vector3.new(8, 0, 34)) * CFrame.Angles(0, math.rad(-20), 0)
			mk(m, "TractorBody", Vector3.new(4, 4, 9), t * CFrame.new(0, 3.5, 0), Color3.fromRGB(170, 40, 30), M.Metal)
			mk(m, "TractorHood", Vector3.new(3.2, 2.4, 4), t * CFrame.new(0, 5.6, -2), Color3.fromRGB(170, 40, 30), M.Metal)
			mk(m, "Exhaust", Vector3.new(0.4, 3, 0.4), t * CFrame.new(1, 7.5, -2.5), Color3.fromRGB(40, 40, 40), M.Metal)
			for _, w in ipairs({ { -2.8, 2.5, 6 }, { 2.8, 2.5, 6 }, { -2.2, -3, 3.2 }, { 2.2, -3, 3.2 } }) do
				mk(m, "TractorWheel", Vector3.new(1.4, w[3], w[3]), t * CFrame.new(w[1], w[3] / 2, w[2]), Color3.fromRGB(24, 22, 20), M.SmoothPlastic, { Shape = CYL })
			end
			reserve(def, 8, 34, 7)
			car(m, CFrame.new(o + Vector3.new(-20, 0, -45)) * CFrame.Angles(0, math.rad(70), 0), Color3.fromRGB(90, 110, 120))
			reserve(def, -20, -45, 9)
		end

		-- жилой дом с крыльцом (два входа + боковой)
		do
			local x1, x2, z1, z2 = -71, -39, 8, 32
			room(m, o, x1, x2, z1, z2, 11, Color3.fromRGB(176, 160, 130), M.WoodPlanks, {
				S = { { c = -55, w = 6 } }, N = { { c = -62, w = 6 } }, E = { { c = 20, w = 5 } },
			}, { noRoof = true, lampColor = Color3.fromRGB(255, 180, 110), flicker = true })
			B("HouseCeiling", x1, x2, 11, 11.5, z1, z2, Color3.fromRGB(120, 100, 80), M.WoodPlanks)
			gableRoof(m, o + Vector3.new(-55, 11.5, 20), 34, 26, 7, Color3.fromRGB(70, 46, 40), M.WoodPlanks, true)
			B("HouseFloor", x1, x2, 0, 0.3, z1, z2, Color3.fromRGB(100, 72, 48), M.WoodPlanks)
			wallWithGaps(m, o + Vector3.new(-55, 0, z1), o + Vector3.new(-55, 0, z2), 11, 0.8, Color3.fromRGB(150, 130, 100), M.WoodPlanks, { { t = 12, w = 5, h = 8 } })
			B("Porch", x1, x2, 0, 1, z2, z2 + 6, Color3.fromRGB(110, 80, 52), M.WoodPlanks)
			B("PorchRoof", x1, x2, 8, 8.5, z2, z2 + 7, Color3.fromRGB(70, 46, 40), M.WoodPlanks)
			for _, x in ipairs({ x1 + 1, -55 - 4, -55 + 4, x2 - 1 }) do B("PorchPost", x - 0.4, x + 0.4, 1, 8, z2 + 5.6, z2 + 6.4, Color3.fromRGB(200, 190, 170), M.Wood) end
			local pl = B("PorchLamp", -52, -51, 6.5, 7.5, z2 + 0.2, z2 + 0.8, Color3.fromRGB(255, 200, 120), M.Neon, NOCOL)
			pointLight(pl, Color3.fromRGB(255, 180, 100), 24, 1.4)
			for _, w in ipairs({ { -66, z2 + 0.85 }, { -45, z2 + 0.85 }, { -66, z1 - 0.85 }, { -45, z1 - 0.85 } }) do
				B("Window", w[1] - 2, w[1] + 2, 4, 7, w[2] - 0.1, w[2] + 0.1, Color3.fromRGB(255, 190, 110), M.Neon, { Transparency = 0.25, CanCollide = false })
			end
			B("Table", -67, -61, 0, 3, 14, 18, Color3.fromRGB(100, 70, 46), M.Wood)
			B("Bed", -51, -42, 0, 2.5, 10, 16, Color3.fromRGB(150, 60, 50), M.Fabric)
			local tv = B("TV", -44, -40.5, 0, 4, 26, 30, Color3.fromRGB(40, 38, 42), M.SmoothPlastic)
			local scr = mk(m, "TVScreen", Vector3.new(0.1, 2.4, 2.8), tv.Position + Vector3.new(-1.8, 0.4, 0), Color3.fromRGB(150, 170, 200), M.Neon, NOCOL)
			tag(scr, "P2D_Flicker", { Strong = true })
			reserve(def, -55, 22, 22)
		end
		for _, p in ipairs({ { -20, 52 }, { -55, 48 }, { -35, 56 }, { -75, 46 }, { -5, 62 } }) do addSpawn(def, "Survivor", p[1], p[2]) end

		-- силос с лестницей и площадкой
		do
			local c = o + Vector3.new(80, 0, -60)
			cyl(m, "Silo", 34, 14, c + Vector3.new(0, 17, 0), Color3.fromRGB(150, 150, 156), M.CorrodedMetal)
			ball(m, "SiloDome", 14, c + Vector3.new(0, 34, 0), Color3.fromRGB(120, 120, 126), M.Metal)
			ladder(m, c + Vector3.new(0, 0, 8), 16)
			mk(m, "SiloLedge", Vector3.new(6, 0.6, 4), c + Vector3.new(0, 16, 9.2), Color3.fromRGB(90, 90, 96), M.DiamondPlate)
			railing(m, c + Vector3.new(-3, 16.3, 11), c + Vector3.new(3, 16.3, 11), 3, Color3.fromRGB(90, 90, 96))
			reserve(def, 80, -60, 11)
		end
		for _, p in ipairs({ { 70, -88 }, { 98, -40 }, { 100, -86 } }) do addSpawn(def, "Killer", p[1], p[2]) end

		-- мельница (лопасти вращаются на клиенте)
		do
			local c = o + Vector3.new(-80, 0, -65)
			for _, s in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
				beam(m, "MillLeg", c + Vector3.new(s[1] * 4, 0, s[2] * 4), c + Vector3.new(s[1] * 1.2, 22, s[2] * 1.2), 0.5, Color3.fromRGB(80, 80, 84), M.Metal)
			end
			mk(m, "MillDeck", Vector3.new(4, 0.5, 4), c + Vector3.new(0, 22, 0), Color3.fromRGB(80, 80, 84), M.Metal)
			local hub = c + Vector3.new(0, 24, -2.4)
			local blades = Instance.new("Model")
			blades.Name = "MillBlades"
			blades.Parent = m
			for i = 0, 7 do
				mk(blades, "Blade", Vector3.new(1.2, 7, 0.2), CFrame.new(hub) * CFrame.Angles(0, 0, i / 8 * math.pi * 2) * CFrame.new(0, 4, 0), Color3.fromRGB(170, 170, 176), M.Metal, NOCOL)
			end
			blades.WorldPivot = CFrame.new(hub)
			tag(blades, "P2D_SpinModel", { Speed = 0.7, Axis = "Z" })
			mk(m, "MillTail", Vector3.new(0.3, 3, 6), c + Vector3.new(0, 24, 3.5), Color3.fromRGB(150, 40, 30), M.Metal)
			B("Trough", -74, -64, 0, 2, -58, -55, Color3.fromRGB(110, 110, 116), M.Metal)
			reserve(def, -80, -65, 8)
		end

		-- кукурузное поле: ряды-стены с поперечными проходами (лабиринт), пугало
		do
			for x = 34, 98, 5 do
				for _, seg in ipairs({ { 46, 58 }, { 63, 82 }, { 87, 104 } }) do
					if not (x > 58 and x < 72 and seg[1] == 63) then
						B("Corn", x - 1.3, x + 1.3, 0, 9.5, seg[1], seg[2], Color3.fromRGB(150, 138, 64), M.Grass)
						B("CornTop", x - 1.6, x + 1.6, 9.5, 10.5, seg[1], seg[2], Color3.fromRGB(190, 160, 70), M.Grass, NOCOL)
					end
				end
			end
			local s = o + Vector3.new(65, 0, 72)
			mk(m, "ScarecrowPost", Vector3.new(0.5, 9, 0.5), s + Vector3.new(0, 4.5, 0), Color3.fromRGB(80, 60, 40), M.Wood)
			mk(m, "ScarecrowArms", Vector3.new(7, 0.4, 0.4), s + Vector3.new(0, 6.5, 0), Color3.fromRGB(80, 60, 40), M.Wood)
			mk(m, "ScarecrowShirt", Vector3.new(3, 3, 1.2), s + Vector3.new(0, 6, 0), Color3.fromRGB(110, 60, 50), M.Fabric)
			mk(m, "ScarecrowHead", Vector3.new(2, 2, 2), s + Vector3.new(0, 8.6, 0), Color3.fromRGB(170, 140, 90), M.Fabric)
			cyl(m, "ScarecrowHat", 0.6, 3.2, s + Vector3.new(0, 9.8, 0), Color3.fromRGB(60, 50, 36), M.Fabric)
			for _, x in ipairs({ -0.45, 0.45 }) do
				mk(m, "ScarecrowEye", Vector3.new(0.4, 0.4, 0.1), s + Vector3.new(x, 8.8, -1.05), Color3.fromRGB(255, 60, 30), M.Neon, NOCOL)
			end
			for x = 34, 98, 5 do reserve(def, x, 75, 4) end
			reserve(def, 66, 50, 6)
			reserve(def, 66, 100, 6)
		end

		-- загоны с курятником, тюки сена
		do
			local x1, x2, z1, z2 = -105, -62, 58, 100
			local function rail(a, b)
				local cf = CFrame.lookAt(o + (a + b) / 2, o + b)
				local len = (b - a).Magnitude
				for _, y in ipairs({ 1.6, 3.4 }) do
					mk(m, "PenRail", Vector3.new(0.3, 0.4, len), cf + Vector3.new(0, y, 0), WOOD, M.Wood)
				end
				for k = 0, math.floor(len / 6) do
					mk(m, "PenPost", Vector3.new(0.6, 4.4, 0.6), o + a + (b - a).Unit * math.min(k * 6, len) + Vector3.new(0, 2.2, 0), Color3.fromRGB(80, 58, 36), M.Wood)
				end
			end
			rail(Vector3.new(x1, 0, z1), Vector3.new(-90, 0, z1))
			rail(Vector3.new(-80, 0, z1), Vector3.new(x2, 0, z1))
			rail(Vector3.new(x2, 0, z1), Vector3.new(x2, 0, 74))
			rail(Vector3.new(x2, 0, 84), Vector3.new(x2, 0, z2))
			rail(Vector3.new(x1, 0, z2), Vector3.new(x2, 0, z2))
			rail(Vector3.new(x1, 0, z1), Vector3.new(x1, 0, z2))
			for _, p in ipairs({ { -92, 72 }, { -84, 72 }, { -92, 88 }, { -84, 88 } }) do
				B("Stilt", p[1] - 0.3, p[1] + 0.3, 0, 4, p[2] - 0.3, p[2] + 0.3, Color3.fromRGB(80, 58, 36), M.Wood)
			end
			B("Coop", -93, -83, 4, 9, 71, 89, Color3.fromRGB(150, 120, 80), M.WoodPlanks)
			gableRoof(m, o + Vector3.new(-88, 9, 80), 11, 19, 3, Color3.fromRGB(80, 50, 40), M.WoodPlanks)
			ramp(m, o + Vector3.new(-88, 0, 64), 3, 4, 7, Vector3.new(0, 0, 1), WOOD, M.WoodPlanks)
			reserve(def, -84, 79, 22)
		end
		local function roundBale(x, z, yaw)
			mk(m, "RoundBale", Vector3.new(4.6, 5.6, 5.6), CFrame.new(o + Vector3.new(x, 2.8, z)) * CFrame.Angles(0, yaw, 0), Color3.fromRGB(200, 170, 80), M.Grass, { Shape = CYL })
			reserve(def, x, z, 4)
		end
		for _, b in ipairs({ { -15, 0, 0.2 }, { -10, 5, 1.4 }, { 60, 30, 0.8 }, { 64, 36, 2 }, { -40, -20, 1 }, { 95, 20, 0.3 }, { -95, 20, 1.7 }, { 30, 60, 0.6 } }) do
			roundBale(b[1], b[2], b[3])
		end
		B("YardPole", 55, 56, 0, 14, 22, 23, Color3.fromRGB(70, 56, 40), M.Wood)
		local yardLamp = B("YardLamp", 54, 57, 13.5, 14.2, 21, 24, Color3.fromRGB(255, 200, 120), M.Neon, NOCOL)
		pointLight(yardLamp, Color3.fromRGB(255, 180, 100), 40, 1.6)

		-- деревья: внутри — немного, по холмам-краю — плотная стена
		scatter(def, r, 14, 106, 6, function(x, z)
			leafTree(m, o + Vector3.new(x, 0, z), r:NextNumber(20, 30), r, AUTUMN)
			reserve(def, x, z, 3)
		end)
		for _ = 1, 90 do
			local side = r:NextInteger(1, 4)
			local t = r:NextNumber(-200, 200)
			local d = r:NextNumber(124, 205)
			local x, z
			if side == 1 then x, z = t, -d elseif side == 2 then x, z = t, d elseif side == 3 then x, z = -d, t else x, z = d, t end
			local nearExit = false
			for _, e in ipairs(exits) do
				if (Vector3.new(x, 0, z) - Vector3.new(e.x, 0, e.z) + e.normal * 40).Magnitude < 40 then nearExit = true end
			end
			if not nearExit then
				local p = o + Vector3.new(x, 0, z)
				local y = groundY(p + Vector3.new(0, 40, 0)) - 1
				if r:NextNumber() < 0.7 then
					leafTree(m, Vector3.new(p.X, y, p.Z), r:NextNumber(30, 44), r, AUTUMN)
				else
					pine(m, Vector3.new(p.X, y, p.Z), r:NextNumber(34, 48), r, 2)
				end
			end
		end
		return def
	end

	MAPS.Forest = buildForest(Vector3.new(2000, 0, 0))
	MAPS.Complex = buildComplex(Vector3.new(4000, 0, 0))
	MAPS.Farm = buildFarm(Vector3.new(6000, 0, 0))
end

------------------------------------------------------------------------
-- ЛОББИ: заброшенный автокинотеатр в ночном лесу (экран показывает статус)
------------------------------------------------------------------------
do
	local P = CONFIG.LOBBY_POS
	local model = Instance.new("Model")
	model.Name = "Lobby"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model.Parent = Workspace
	local r = Random.new(7)
	local function B(...) return box(model, P, ...) end

	terra("FillBlock", CFrame.new(P + Vector3.new(0, -10, 0)), Vector3.new(520, 20, 520), M.Grass)
	terra("FillBlock", CFrame.new(P + Vector3.new(0, -1.5, 18)), Vector3.new(120, 3, 96), M.Asphalt)
	hillRing(P, 130, { M.Rock, M.Grass }, r, {}, 0)

	-- экран
	for _, s in ipairs({ -1, 1 }) do
		B("ScreenPost", s * 33 - 1.2, s * 33 + 1.2, 0, 42, -42, -39.6, Color3.fromRGB(60, 60, 64), M.Metal)
		for y = 8, 40, 8 do
			beam(model, "ScreenBrace", P + Vector3.new(s * 33, y - 8, -40.8), P + Vector3.new(s * 25, y, -40.8), 0.5, Color3.fromRGB(60, 60, 64), M.Metal)
		end
	end
	B("ScreenFrame", -33, 33, 6, 42, -42.2, -41.2, Color3.fromRGB(30, 30, 32), M.Metal)
	local screen = B("LobbyScreen", -31, 31, 8, 40, -41.2, -40.8, Color3.fromRGB(16, 16, 18), M.SmoothPlastic)
	screen:SetAttribute("Face", "Back")
	local glow = B("ScreenGlow", -1, 1, 22, 23, -36, -35, BLACK, M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false })
	pointLight(glow, Color3.fromRGB(160, 180, 255), 40, 0.7)

	-- машины зрителей и столбики с динамиками
	local carColors = { Color3.fromRGB(120, 30, 30), Color3.fromRGB(40, 70, 110), Color3.fromRGB(150, 140, 120), Color3.fromRGB(40, 80, 50) }
	for i, x in ipairs({ -34, -12, 12, 34 }) do
		car(model, CFrame.new(P + Vector3.new(x, 0, 14 + (i % 2) * 6)) * CFrame.Angles(0, r:NextNumber(-0.15, 0.15), 0), carColors[i])
	end
	for _, z in ipairs({ 4, 30 }) do
		for x = -45, 45, 18 do
			B("SpeakerPole", x - 0.2, x + 0.2, 0, 4, z - 0.2, z + 0.2, Color3.fromRGB(70, 70, 70), M.Metal)
			B("Speaker", x - 0.8, x + 0.8, 4, 5.2, z - 0.5, z + 0.5, Color3.fromRGB(40, 40, 44), M.Metal)
		end
	end

	-- закусочная с будкой киномеханика: луч проектора бьёт в экран
	local x1, x2, z1, z2 = -11, 11, 50, 64
	room(model, P, x1, x2, z1, z2, 9, Color3.fromRGB(120, 110, 96), M.Brick, {
		N = { { c = -6, w = 5 } }, S = { { c = 6, w = 5 } },
	}, { lampColor = Color3.fromRGB(255, 200, 140), flicker = true })
	B("Counter", -9, 2, 0, 3.4, 56, 58, Color3.fromRGB(140, 40, 40), M.SmoothPlastic)
	B("Popcorn", 3, 6, 3.4, 7, 56, 58.5, Color3.fromRGB(255, 220, 120), M.Glass, { Transparency = 0.3 })
	local tv = B("TV", 6, 10, 0, 4, 60, 63, Color3.fromRGB(40, 38, 42), M.SmoothPlastic)
	local scr = mk(model, "TVScreen", Vector3.new(2.8, 2.4, 0.1), tv.Position + Vector3.new(0, 0.4, -1.55), Color3.fromRGB(150, 170, 200), M.Neon, NOCOL)
	tag(scr, "P2D_Flicker", { Strong = true })
	B("Arcade", -10, -7, 0, 6.5, 61, 63.5, Color3.fromRGB(30, 28, 34), M.SmoothPlastic)
	local arcadeScr = B("ArcadeScreen", -9.6, -7.4, 4, 5.6, 60.9, 61, Color3.fromRGB(120, 60, 200), M.Neon, NOCOL)
	tag(arcadeScr, "P2D_Flicker")
	local sign = B("KinoSign", -8, 8, 10, 13.5, 56.6, 57.4, Color3.fromRGB(20, 6, 8), M.SmoothPlastic)
	surfaceText(sign, Enum.NormalId.Front, "КИНО", { color = Color3.fromRGB(255, 50, 50), font = Enum.Font.GothamBlack })
	local neonBar = B("KinoNeon", -8, 8, 9.6, 10, 56.5, 56.7, Color3.fromRGB(255, 40, 40), M.Neon, NOCOL)
	tag(neonBar, "P2D_Flicker")
	pointLight(neonBar, Color3.fromRGB(255, 50, 50), 22, 1)
	local projector = B("ProjectorWindow", -1, 1, 6, 7.5, 49.1, 49.3, Color3.fromRGB(255, 255, 230), M.Neon, NOCOL)
	local a0 = Instance.new("Attachment")
	a0.Parent = projector
	local a1 = Instance.new("Attachment")
	a1.Parent = screen
	local pbeam = Instance.new("Beam")
	pbeam.Attachment0 = a0
	pbeam.Attachment1 = a1
	pbeam.Width0 = 1.4
	pbeam.Width1 = 44
	pbeam.FaceCamera = true
	pbeam.LightEmission = 1
	pbeam.LightInfluence = 0
	pbeam.Segments = 1
	pbeam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0.93) })
	pbeam.Color = ColorSequence.new(Color3.fromRGB(200, 210, 255))
	pbeam.Parent = projector

	-- гирлянды
	for _, z in ipairs({ -6, 40 }) do
		for x = -48, 48, 8 do
			local bulb = ball(model, "Bulb", 0.6, P + Vector3.new(x, 9 + math.sin(x / 8) * 0.6, z), Color3.fromRGB(255, 200, 120), M.Neon, NOCOL)
			if x % 24 == 0 then pointLight(bulb, Color3.fromRGB(255, 190, 110), 14, 0.7) end
		end
		for _, s in ipairs({ -1, 1 }) do
			B("GarlandPole", s * 50 - 0.3, s * 50 + 0.3, 0, 10, z - 0.3, z + 0.3, Color3.fromRGB(70, 56, 40), M.Wood)
		end
	end

	-- ограда площадки и закрытые ворота
	local fenceC = Color3.fromRGB(80, 84, 88)
	for _, w in ipairs({ { -60, 60, -46, -45.7 }, { -60, 60, 72, 72.3 }, { -60.3, -60, -46, 72 }, { 60, 60.3, -46, 50 } }) do
		B("LotFence", w[1], w[2], 0, 7, w[3], w[4], fenceC, M.Metal, { Transparency = 0.45 })
	end
	B("LotGate", 60, 60.4, 0, 7, 50, 72, Color3.fromRGB(110, 40, 30), M.Metal)
	B("TicketBooth", 63, 69, 0, 8, 54, 60, Color3.fromRGB(150, 140, 120), M.WoodPlanks)

	for _ = 1, 70 do
		local a = r:NextNumber(0, math.pi * 2)
		local d = r:NextNumber(78, 180)
		local p = P + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
		pine(model, Vector3.new(p.X, groundY(p + Vector3.new(0, 40, 0)) - 1, p.Z), r:NextNumber(30, 48), r, 2)
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(16, 1, 10)
	spawn.Position = P + Vector3.new(0, 0.5, 34)
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
	local pos = CONFIG.LOBBY_POS + Vector3.new(rng:NextNumber(-14, 14), 4, rng:NextNumber(28, 40))
	return CFrame.lookAt(pos, CONFIG.LOBBY_POS + Vector3.new(0, 4, -40))
end

------------------------------------------------------------------------
-- СЦЕНА ВЫБОРА: старый театр — 6 подиумов с прожекторами, монитор Палача, закулисье
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
	local function B(...) return box(model, S, ...) end
	local DARK = Color3.fromRGB(16, 12, 12)

	-- сцена из старых досок
	B("StageFloor", -39, 39, -2, 0, -12, 18, Color3.fromRGB(70, 50, 36), M.WoodPlanks)
	B("StageRiser", -39, 39, -6, 0, -13, -12, Color3.fromRGB(40, 26, 22), M.WoodPlanks)
	B("StageTrim", -39, 39, -0.3, 0.05, -12.4, -12, Color3.fromRGB(150, 110, 50), M.Metal, NOCOL)
	for k = -13, 13 do
		local f = mk(model, "Footlight", Vector3.new(1.2, 0.4, 0.6), L(k * 2.8, 0.2, -11.4), Color3.fromRGB(255, 190, 120), M.Neon, NOCOL)
		if k % 4 == 0 then pointLight(f, Color3.fromRGB(255, 160, 90), 9, 0.6) end
		if k % 5 == 0 then f.Color = Color3.fromRGB(60, 40, 30) end -- перегоревшие
	end
	-- зал: стены, потолок, ряды кресел
	B("Pit", -46, 46, -8, -6, -70, -13, Color3.fromRGB(20, 14, 14), M.WoodPlanks)
	for z = -22, -58, -5 do
		B("SeatRow", -36, 36, -6, -4.2, z - 1, z + 1, Color3.fromRGB(80, 16, 22), M.Fabric)
		B("SeatBack", -36, 36, -6, -2.4, z + 1, z + 1.6, Color3.fromRGB(70, 14, 20), M.Fabric)
	end
	for _, s in ipairs({ -1, 1 }) do
		B("HallWall", s * 46 - 1, s * 46 + 1, -8, 44, -72, 22, DARK, M.WoodPlanks)
		B("Proscenium", math.min(s * 39, s * 46), math.max(s * 39, s * 46), -6, 44, -14, -12, Color3.fromRGB(60, 20, 22), M.Fabric)
		local sconce = mk(model, "Sconce", Vector3.new(0.6, 1.2, 0.6), L(s * 44.6, 10, -40), Color3.fromRGB(255, 170, 90), M.Neon, NOCOL)
		pointLight(sconce, Color3.fromRGB(255, 150, 80), 18, 0.5)
		tag(sconce, "P2D_Flicker")
	end
	B("RearWall", -46, 46, -8, 44, -73, -71, DARK, M.WoodPlanks)
	B("HallCeiling", -46, 46, 44, 46, -72, 22, Color3.fromRGB(12, 10, 10), M.WoodPlanks)
	B("ProsceniumTop", -39, 39, 28, 44, -14, -12, Color3.fromRGB(60, 20, 22), M.Fabric)

	-- задник: мерцающая неоновая вывеска и пиксельные черепа (единственный «игровой» намёк)
	B("BackWall", -46, 46, -2, 44, 17, 19, DARK, M.WoodPlanks)
	local logo = mk(model, "Logo", Vector3.new(56, 8, 0.4), L(0, 23.5, 16.8), Color3.fromRGB(8, 6, 8), M.SmoothPlastic)
	surfaceText(logo, Enum.NormalId.Front, "PRESS 2 DIE", { font = Enum.Font.Arcade, color = Color3.fromRGB(230, 30, 30) })
	for _, e in ipairs({ { 0, 27.8, 57.6, 0.4 }, { 0, 19.2, 57.6, 0.4 }, { -28.6, 23.5, 0.4, 8.8 }, { 28.6, 23.5, 0.4, 8.8 } }) do
		local n = mk(model, "LogoNeon", Vector3.new(e[3], e[4], 0.4), L(e[1], e[2], 16.6), Color3.fromRGB(255, 40, 40), M.Neon, NOCOL)
		tag(n, "P2D_Flicker")
	end
	local wash = mk(model, "LogoWash", Vector3.new(50, 1, 0.2), L(0, 18.6, 16.4), BLACK, M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false })
	local sl = Instance.new("SurfaceLight")
	sl.Face = Enum.NormalId.Front
	sl.Range = 22
	sl.Angle = 110
	sl.Brightness = 0.7
	sl.Color = Color3.fromRGB(255, 40, 40)
	sl.Parent = wash
	local SKULL = { "..#####..", ".#######.", "##.###.##", "#...#...#", "##.###.##", ".#######.", "..#.#.#..", "..#####.." }
	for _, sx in ipairs({ -36, 36 }) do
		pixelArt(model, CFrame.new(L(sx, 13, 16.6)), SKULL, 1.1, { ["#"] = Color3.fromRGB(230, 225, 210) }, 0.3)
	end
	-- рваные кулисы
	for _, s in ipairs({ -1, 1 }) do
		for k = 0, 5 do
			local h = 30 - (k % 3) * 4
			cyl(model, "Curtain", h, 2.6, L(s * (35 + k * 0.6), 28 - h / 2, -9 + k * 4.4), (k % 2 == 0) and Color3.fromRGB(90, 12, 18) or Color3.fromRGB(64, 8, 12), M.Fabric)
		end
		local rim = mk(model, "RimLight", Vector3.new(1, 1, 1), L(s * 30, 8, 10), BLACK, M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false })
		pointLight(rim, Color3.fromRGB(60, 80, 255), 26, 1.2)
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

		local lampPos = L(x, 18.4, -4.2)
		local target = L(x, PODIUM_H, 0)
		local aim = CFrame.lookAt(lampPos, target) * ALONG_Z -- ось цилиндра смотрит на подиум
		mk(model, "SpotHanger", Vector3.new(0.3, 2, 0.3), L(x, 19.6, -3.8), Color3.fromRGB(40, 40, 44), M.Metal)
		mk(model, "SpotHousing", Vector3.new(2.6, 1.9, 1.9), aim, Color3.fromRGB(22, 22, 26), M.Metal, { Shape = CYL })
		local lens = mk(model, "SpotLens", Vector3.new(0.2, 1.6, 1.6), aim * CFrame.new(1.35, 0, 0), LENS_OFF, M.Neon, { Shape = CYL, CanCollide = false, CanQuery = false })
		local spot = spotLight(lens, Enum.NormalId.Right, SPOT_WARM, 30, 32, 9)
		spot.Shadows = true
		spot.Enabled = false
		local at0 = Instance.new("Attachment")
		at0.Position = Vector3.new(0.15, 0, 0)
		at0.Parent = lens
		local at1 = Instance.new("Attachment")
		at1.Position = Vector3.new(0, 0.05, 0)
		at1.Parent = pool
		local bm = Instance.new("Beam")
		bm.Attachment0 = at0
		bm.Attachment1 = at1
		bm.Width0 = 1.5
		bm.Width1 = 6.4
		bm.FaceCamera = true
		bm.LightEmission = 1
		bm.LightInfluence = 0
		bm.Segments = 1
		bm.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.86) })
		bm.Color = ColorSequence.new(SPOT_WARM)
		bm.Enabled = false
		bm.Parent = lens
		slots[i] = { podium = podium, ring = ring, pool = pool, lens = lens, spot = spot, beam = bm,
			plate = plate, charText = charText, nameText = nameText, litId = nil, token = 0 }
	end

	-- пыль в лучах
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

	-- монитор Палача: ЭЛТ-телевизор на цепях; клиент опускает его, когда Палач выбрал облик
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
		cyl(mon, "Chain", 40, 0.3, lowered * CFrame.new(s * 4.5, 24.5, 0), Color3.fromRGB(60, 60, 64), M.Metal, NOCOL)
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

-- зоны для клиентских пресетов освещения
do
	local zones = {
		{ k = "Lobby", x = CONFIG.LOBBY_POS.X, y = CONFIG.LOBBY_POS.Y, z = CONFIG.LOBBY_POS.Z, h = 240 },
		{ k = "Stage", x = STAGE.X, y = STAGE.Y, z = STAGE.Z, h = 220 },
	}
	for key, def in pairs(MAPS) do
		table.insert(zones, { k = key, x = def.origin.X, y = def.origin.Y, z = def.origin.Z, h = 240 })
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
local survivorList = {}    -- { {player, userId, name, dname, charId, port, status, char} }
local entryOf = {}
local matchConns = {}
local lastMap, lastKiller = nil, nil
local stamina = {}         -- [player] = {value, max, exhausted, regenAt, want, isKiller, speedMul}
local boostUntil = {}
local matchEndAt = 0
-- Палач: рывок, прятки, оглушение (с иммунитетом) и замедления от навыков выживших
local fx = { dashUntil = 0, vanishUntil = 0, vanishSaved = nil, stunUntil = 0, stunImmuneUntil = 0, slows = {} }
-- навыки выживших: состояние игроков, станции и растяжки Грега, бафф станции ускорения.
-- Всё в одной таблице: у главного чанка Luau лимит в 200 локальных.
local SK = { state = {}, devices = {}, stationBoost = {}, use = {} }

local function serverNow() return Workspace:GetServerTimeNow() end

local function survivorMods(c)
	return { hp = c.hp or 100, staminaMax = c.stamina or 100, speed = 1 }
end

local function killerModsOf(c)
	return {
		speed = 1 + (c.speed - 3) * 0.025,
		stamina = 1 + (c.stamina - 3) * 0.08,
		attack = 1 - (c.power - 3) * 0.1,
	}
end

-- прыжков в игре нет: ни в лобби, ни на сцене, ни в матче
local function noJump(hum)
	hum.UseJumpPower = true
	hum.JumpPower = 0
	hum.JumpHeight = 0
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
		table.insert(list, { id = e.userId, c = e.charId, s = e.status, p = e.port, n = e.dname })
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

-- короткая вспышка частиц (Enabled переключается — надёжно реплицируется)
local function burst(part, color, texture, count)
	local pe = Instance.new("ParticleEmitter")
	if texture then pe.Texture = texture end
	pe.Rate = count or 40
	pe.Lifetime = NumberRange.new(0.6, 1.2)
	pe.Speed = NumberRange.new(4, 9)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	pe.LightEmission = 1
	pe.Color = ColorSequence.new(color)
	pe.Parent = part
	task.delay(0.35, function() pe.Enabled = false end)
	Debris:AddItem(pe, 2)
end

------------------------------------------------------------------------
-- ВЫНОСЛИВОСТЬ, БЕГ (Shift), УСКОРЕНИЯ, ОГЛУШЕНИЕ, ЗАМЕДЛЕНИЯ, РЫВОК/ПРЯТКИ
-- Всё считается на сервере; клиент только сообщает «держу Shift».
------------------------------------------------------------------------
local function initStamina(p, isKiller, mods)
	mods = mods or { stamina = 1, speed = 1 }
	local max = mods.staminaMax or CONFIG.STAMINA_MAX_KILLER * (mods.stamina or 1)
	stamina[p] = {
		value = max, max = max, exhausted = false, regenAt = 0, want = false,
		isKiller = isKiller, speedMul = mods.speed or 1,
	}
	p:SetAttribute("MaxStamina", math.floor(max + 0.5))
	p:SetAttribute("Stamina", math.floor(max + 0.5))
	p:SetAttribute("Exhausted", false)
	p:SetAttribute("Boosted", false)
end

local function clearStamina(p)
	stamina[p] = nil
	boostUntil[p] = nil
	SK.stationBoost[p] = nil
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
			SK.interrupt(p) -- любой урон срывает лечение Лилиан
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
		if not char or fx.vanishSaved then return end
		fx.vanishSaved = {}
		for _, d in ipairs(char:GetDescendants()) do
			if (d:IsA("BasePart") or d:IsA("Decal")) and d.Name ~= "HumanoidRootPart" then
				fx.vanishSaved[d] = d.Transparency
				d.Transparency = 1
			end
		end
		for _, n in ipairs({ "KillerAura", "P2D_Outline" }) do
			local x = char:FindFirstChild(n, true)
			if x then x.Enabled = false end
		end
	else
		if fx.vanishSaved then
			for d, t in pairs(fx.vanishSaved) do
				if d.Parent then d.Transparency = t end
			end
		end
		fx.vanishSaved = nil
		fx.vanishUntil = 0
		if char then
			for _, n in ipairs({ "KillerAura", "P2D_Outline" }) do
				local x = char:FindFirstChild(n, true)
				if x then x.Enabled = true end
			end
		end
		if killer then killer:SetAttribute("Skill1Until", 0) end
	end
end

RunService.Heartbeat:Connect(function(dt)
	if not matchActive then return end
	local now = os.clock()
	if fx.vanishSaved and now >= fx.vanishUntil then setVanish(false) end
	SK.tick(now, dt)
	local slow = SK.killerSlow(now)
	for p, s in pairs(stamina) do
		local char = p.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			local st = SK.state[p]
			local base = (s.isKiller and CONFIG.KILLER_SPEED or CONFIG.SURVIVOR_SPEED) * s.speedMul
			local run = (s.isKiller and CONFIG.KILLER_SPRINT_SPEED or CONFIG.SURVIVOR_SPRINT_SPEED) * s.speedMul
			local moving = hum.MoveDirection.Magnitude > 0.1
			local canRun = not (st and SK.noRun(st, now))
			local sprinting = s.want and moving and canRun and not s.exhausted and s.value > 0

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
			local boosted = false
			if boostUntil[p] and now < boostUntil[p] then
				speed *= CONFIG.HIT_BOOST_MULT
				boosted = true
			end
			if (SK.stationBoost[p] or 0) > now then
				speed *= CONFIG.STATION_SPEED
				boosted = true
			end
			if st then
				speed *= SK.speedMul(st, now)
				if st.adrenalineUntil > now then boosted = true end
			end
			if p == killer then
				if now < fx.dashUntil then speed = CONFIG.DASH_SPEED end
				if fx.vanishSaved then speed *= 1.08 end
				speed *= 1 - slow
				if now < fx.stunUntil then speed = 0 end
			end
			hum.WalkSpeed = speed

			p:SetAttribute("Stamina", math.floor(s.value + 0.5))
			p:SetAttribute("Exhausted", s.exhausted or (st ~= nil and st.windedUntil > now and st.adrenalineUntil <= now))
			p:SetAttribute("Boosted", boosted)
			p:SetAttribute("NoSprint", not canRun)
		end
	end
end)

------------------------------------------------------------------------
-- СМЕРТЬ / ПОБЕГ
------------------------------------------------------------------------
-- без всплывающих сообщений: гибель видна по статусу в списке игроков
local function markDead(e)
	if e.status ~= "alive" then return end
	e.status = "dead"
	e.player:SetAttribute("Status", "dead")
	SK.reset(e.player)
	clearStamina(e.player)
	removeFlashlight(e.player.Character)
	publishRoster()
end

local function markEscaped(e)
	if e.status ~= "alive" then return end
	e.status = "escaped"
	e.player:SetAttribute("Status", "escaped")
	SK.reset(e.player)
	clearStamina(e.player)
	local char = e.player.Character
	removeFlashlight(char)
	if char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then hum.WalkSpeed = CONFIG.LOBBY_SPEED end
		char:PivotTo(lobbyCFrame())
	end
	publishRoster()
	announce(said(e, "сбежал", "сбежала") .. "!", "good")
	announce("ПОБЕГ УДАЛСЯ! Можно наблюдать за остальными.", "good", e.player)
end

------------------------------------------------------------------------
-- ОРУЖИЕ, ОГЛУШЕНИЕ И НАВЫКИ
------------------------------------------------------------------------
local function weldTool(handle, name, size, offset, color, mat, shape)
	local p = Instance.new("Part")
	p.Name = name
	if shape then p.Shape = shape end
	p.Size = size
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
		weldTool(handle, "Blade", Vector3.new(0.18, 2.4, 1.5), CFrame.new(0, 1.8, 0.4), Color3.fromRGB(170, 170, 176), M.Metal)
		weldTool(handle, "Edge", Vector3.new(0.2, 2.4, 0.14), CFrame.new(0, 1.8, 1.16), Color3.fromRGB(200, 20, 20), M.Neon)
		return "Тесак"
	end,
	glitch = function(handle)
		handle.Color = Color3.fromRGB(20, 20, 24)
		local tip = weldTool(handle, "Spark", Vector3.new(0.7, 0.7, 0.7), CFrame.new(0, 1.9, 0), Color3.fromRGB(120, 240, 255), M.Neon, BALL)
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
		weldTool(handle, "Candy", Vector3.new(0.4, 2.4, 2.4), CFrame.new(0, 2.4, 0), Color3.fromRGB(255, 80, 160), M.SmoothPlastic, CYL)
		weldTool(handle, "Swirl", Vector3.new(0.42, 1.3, 1.3), CFrame.new(0, 2.4, 0), Color3.fromRGB(255, 240, 250), M.Neon, CYL)
		return "Леденец"
	end,
}

local function killerAlive()
	local char = killer and killer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hum and hrp and hum.Health > 0 then return char, hrp end
	return nil
end

-- оглушение Палача: стоит на месте, не бьёт; над головой мультяшные звёзды
local function stunKiller(sec, byName)
	if not matchActive or not killer then return false end
	local now = os.clock()
	if now < fx.stunImmuneUntil then return false end
	local char = killerAlive()
	if not char then return false end
	fx.stunUntil = now + sec
	fx.stunImmuneUntil = fx.stunUntil + CONFIG.STUN_IMMUNITY
	fx.dashUntil = 0
	if fx.vanishSaved then setVanish(false) end
	killer:SetAttribute("StunnedUntil", serverNow() + sec)
	fxEvent:FireClient(killer, "stunned", sec)
	local head = char:FindFirstChild("Head")
	if head then
		local bb = Instance.new("BillboardGui")
		bb.Name = "Dizzy"
		bb.Size = UDim2.fromOffset(110, 44)
		bb.StudsOffset = Vector3.new(0, 4.2, 0)
		bb.Adornee = head
		for i = 1, 4 do
			local s = Instance.new("Frame")
			s.AnchorPoint = Vector2.new(0.5, 0.5)
			s.Size = UDim2.fromOffset(14, 14)
			s.Rotation = 45
			s.Position = UDim2.fromScale(i / 5, 0.5)
			s.BackgroundColor3 = Color3.fromRGB(255, 220, 60)
			s.BorderSizePixel = 0
			s.Parent = bb
		end
		bb.Parent = head
		tag(bb, "P2D_Dizzy")
		Debris:AddItem(bb, sec)
	end
	announce(byName .. " оглушает Палача!", "good")
	return true
end

local function clearLine(fromPos, toPos, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	return Workspace:Raycast(fromPos, toPos - fromPos, params) == nil
end

------------------------------------------------------------------------
-- НАВЫКИ ВЫЖИВШИХ: skills[1] — Q, skills[2] — E
-- Атрибуты игрока для HUD: Skill1ReadyAt/Skill2ReadyAt (время готовности), Skill1Until/Skill2Until
-- (конец активной фазы), Skill1Broken (бита Айши), Mana/MaxMana (Феликс), NoSprint.
------------------------------------------------------------------------
function SK.get(p)
	local st = SK.state[p]
	if not st then
		st = { noSprintUntil = 0, windupUntil = 0, adrenalineUntil = 0, windedUntil = 0 }
		SK.state[p] = st
	end
	return st
end

function SK.setReady(p, slot, t) p:SetAttribute("Skill" .. slot .. "ReadyAt", t) end
function SK.setActive(p, slot, t) p:SetAttribute("Skill" .. slot .. "Until", t) end

-- подсветка через обводку персонажа: белая — контр-удар, зелёная — лечение, синяя — щит
function SK.glow(char, color)
	local hl = char and char:FindFirstChild("P2D_Outline")
	if not hl then return end
	if color then
		hl.OutlineColor = color
		hl.OutlineTransparency = 0
		hl.FillColor = color
		hl.FillTransparency = 0.72
	else
		local c = CHAR_BY_ID[char:GetAttribute("CharId") or ""]
		hl.OutlineColor = c and roleColor(c) or WHITE
		hl.OutlineTransparency = 0.25
		hl.FillTransparency = 1
	end
end

-- Палач перед выжившим (дальность, конус) — для удара, биты, вспышки
function SK.inFront(hrp, range, minDot)
	local kchar, khrp = killerAlive()
	if not kchar then return nil end
	local d = khrp.Position - hrp.Position
	local flat = Vector3.new(d.X, 0, d.Z)
	if flat.Magnitude > range or flat.Magnitude < 0.05 or math.abs(d.Y) > 8 then return nil end
	local look = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
	if look.Magnitude < 0.05 or flat.Unit:Dot(look.Unit) < minDot then return nil end
	return kchar, khrp
end

-- Палач смотрит в сторону pos (удар битой «в лицо», ослепление вспышкой)
function SK.killerFaces(khrp, pos, minDot)
	local d = pos - khrp.Position
	d = Vector3.new(d.X, 0, d.Z)
	local look = Vector3.new(khrp.CFrame.LookVector.X, 0, khrp.CFrame.LookVector.Z)
	if d.Magnitude < 0.05 or look.Magnitude < 0.05 then return false end
	return d.Unit:Dot(look.Unit) >= minDot
end

function SK.flatLook(hrp)
	local look = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
	return look.Magnitude > 0.05 and look.Unit or Vector3.new(0, 0, -1)
end

function SK.slowKiller(frac, sec)
	if not matchActive or not killer then return end
	frac = math.clamp(frac, 0, 0.9)
	table.insert(fx.slows, { frac = frac, untilT = os.clock() + sec })
	fxEvent:FireClient(killer, "slowed", math.floor(frac * 100 + 0.5), sec)
end

-- самое сильное из действующих замедлений Палача (доля 0..0.9)
function SK.killerSlow(now)
	local m = 0
	for i = #fx.slows, 1, -1 do
		local sl = fx.slows[i]
		if now >= sl.untilT then table.remove(fx.slows, i) else m = math.max(m, sl.frac) end
	end
	return m
end

function SK.noRun(st, now)
	return st.noSprintUntil > now or st.guard ~= nil or st.channel ~= nil or st.windupUntil > now
		or (st.windedUntil > now and st.adrenalineUntil <= now)
end

function SK.speedMul(st, now)
	if st.channel then return 0 end -- поза лечения и самолечение: на месте
	local m = 1
	if st.adrenalineUntil > now then
		m *= CONFIG.ADRENALINE_MULT
	elseif st.windedUntil > now then
		m *= CONFIG.WINDED_MULT -- одышка после адреналина
	end
	if st.windupUntil > now then m *= 0.5 end
	return m
end

-- предмет в правой руке на время навыка (бита, камера)
function SK.handProp(char, name, size, offset, color, mat)
	local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
	if not hand then return nil end
	return gearPart(char, hand, name, size, offset, color, mat)
end

function SK.swish(part)
	local s = Instance.new("Sound")
	s.SoundId = "rbxasset://sounds/swordslash.wav"
	s.Volume = 0.6
	s.PlaybackSpeed = 1.3
	s.Parent = part
	s:Play()
	Debris:AddItem(s, 2)
end

-- стойки: контр-удар Алекса и силовой щит Феликса
function SK.startGuard(p, kind, dur, slot)
	local st = SK.get(p)
	local char = p.Character
	st.guard = { kind = kind, untilT = os.clock() + dur, slot = slot }
	SK.setActive(p, slot, serverNow() + dur)
	SK.glow(char, kind == "counter" and WHITE or Color3.fromRGB(90, 150, 255))
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if kind == "shield" and hrp then
		local bubble = gearPart(char, hrp, "P2D_Shield", Vector3.new(8, 8, 8), CFrame.identity, Color3.fromRGB(90, 150, 255), M.ForceField, BALL)
		bubble.Transparency = 0.15
	end
end

function SK.endGuard(p)
	local st = SK.state[p]
	if not st or not st.guard then return end
	SK.setActive(p, st.guard.slot, 0)
	st.guard = nil
	local char = p.Character
	SK.glow(char, nil)
	local b = char and char:FindFirstChild("P2D_Shield")
	if b then b:Destroy() end
end

-- удар Палача по выжившему в стойке: урона нет, Палач оглушён
function SK.tryBlock(e)
	local st = SK.state[e.player]
	if not st or not st.guard then return false end
	local kind = st.guard.kind
	SK.endGuard(e.player)
	local hrp = e.player.Character and e.player.Character:FindFirstChild("HumanoidRootPart")
	if hrp then burst(hrp, kind == "counter" and WHITE or Color3.fromRGB(90, 150, 255), nil, 60) end
	stunKiller(kind == "counter" and CONFIG.COUNTER_STUN or CONFIG.SHIELD_STUN, e.name)
	fxEvent:FireClient(e.player, "blocked", kind)
	return true
end

-- щит можно сбросить раньше: волна отталкивает Палача
function SK.releaseShield(p, hrp)
	SK.endGuard(p)
	burst(hrp, Color3.fromRGB(90, 150, 255), nil, 70)
	local kchar, khrp = killerAlive()
	if not kchar then return end
	local d = khrp.Position - hrp.Position
	local flat = Vector3.new(d.X, 0, d.Z)
	if flat.Magnitude <= CONFIG.SHIELD_PUSH_RADIUS then
		local dir = flat.Magnitude > 0.05 and flat.Unit or SK.flatLook(hrp)
		fxEvent:FireClient(killer, "knockback", dir * CONFIG.SHIELD_PUSH + Vector3.new(0, 16, 0))
		announce("Щит отбросил Палача!", "good", p)
	end
end

-- поза лечения и самолечение Лилиан: на месте, любой урон отменяет
function SK.startChannel(p, e, kind, dur, slot)
	local st = SK.get(p)
	local char = p.Character
	st.channel = { kind = kind, untilT = os.clock() + dur, dur = dur, slot = slot }
	SK.setActive(p, slot, serverNow() + dur)
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if kind == "heal" then
		SK.glow(char, Color3.fromRGB(80, 255, 140))
		if hrp then
			-- союзник подходит и жмёт F; Палачу и самой Лилиан клиент подсказку не показывает
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "P2D_HealPrompt"
			prompt.ActionText = "Лечение"
			prompt.ObjectText = e.name
			prompt.KeyboardKeyCode = Enum.KeyCode.F
			prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
			prompt.HoldDuration = 0.6
			prompt.MaxActivationDistance = CONFIG.HEAL_RADIUS
			prompt.RequiresLineOfSight = false
			prompt:SetAttribute("OwnerId", p.UserId)
			prompt.Triggered:Connect(function(other) SK.acceptHeal(p, other) end)
			prompt.Parent = hrp
			tag(prompt, "P2D_HealPrompt")
			st.channel.prompt = prompt
		end
	elseif hrp then
		burst(hrp, Color3.fromRGB(80, 255, 140), nil, 25)
	end
end

function SK.endChannel(p, reason)
	local st = SK.state[p]
	local ch = st and st.channel
	if not ch then return end
	st.channel = nil
	if ch.prompt then ch.prompt:Destroy() end
	SK.glow(p.Character, nil)
	SK.setActive(p, ch.slot, 0)
	local e = entryOf[p]
	local sk = e and e.char.skills and e.char.skills[ch.slot]
	if sk then SK.setReady(p, ch.slot, serverNow() + sk.cd) end -- перезарядка — с момента окончания
	if reason == "hit" then fxEvent:FireClient(p, "interrupted") end
end

function SK.interrupt(p)
	SK.endChannel(p, "hit")
end

function SK.acceptHeal(p, other)
	local st = SK.state[p]
	if not st or not st.channel or st.channel.kind ~= "heal" or other == p then return end
	local oe = entryOf[other]
	if not oe or oe.status ~= "alive" then return end
	local oh = other.Character and other.Character:FindFirstChildOfClass("Humanoid")
	if not oh or oh.Health <= 0 then return end
	oh.Health = math.min(oh.MaxHealth, oh.Health + CONFIG.HEAL_AMOUNT)
	local orp = other.Character:FindFirstChild("HumanoidRootPart")
	if orp then burst(orp, Color3.fromRGB(80, 255, 140), nil, 50) end
	fxEvent:FireClient(other, "healed", entryOf[p] and entryOf[p].name)
	fxEvent:FireClient(p, "healgiven", oe.name)
	SK.endChannel(p, "done")
end

-- точка на земле под pos (для станций и растяжек)
function SK.groundAt(pos, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local r = Workspace:Raycast(pos + Vector3.new(0, 2, 0), Vector3.new(0, -14, 0), params)
	return r and r.Position or (pos - Vector3.new(0, 3, 0))
end

function SK.removeDevice(i)
	local d = table.remove(SK.devices, i)
	if d and d.model then d.model:Destroy() end
end

function SK.placeStation(p, kind, hrp, dur)
	for i = #SK.devices, 1, -1 do -- у Грега одна станция: старая убирается
		if SK.devices[i].owner == p and SK.devices[i].kind ~= "wire" then SK.removeDevice(i) end
	end
	local look = SK.flatLook(hrp)
	local ground = SK.groundAt(hrp.Position + look * 3, { p.Character, killer and killer.Character })
	local heal = kind == "heal"
	local col = heal and Color3.fromRGB(80, 255, 140) or Color3.fromRGB(255, 220, 60)
	local m = Instance.new("Model")
	m.Name = heal and "HealStation" or "SpeedStation"
	local cf = CFrame.lookAt(ground, ground - look) -- лицевой стороной к Грегу
	local body = mk(m, "StationBody", Vector3.new(2.4, 2, 2.4), cf * CFrame.new(0, 1, 0),
		heal and Color3.fromRGB(230, 230, 236) or Color3.fromRGB(50, 50, 56), M.Metal)
	mk(m, "StationBase", Vector3.new(3, 0.3, 3), cf * CFrame.new(0, 0.15, 0), Color3.fromRGB(70, 70, 76), M.DiamondPlate)
	local lamp = mk(m, "StationLamp", Vector3.new(1.2, 0.6, 1.2), cf * CFrame.new(0, 2.3, 0), col, M.Neon, NOCOL)
	pointLight(lamp, col, 16, 1.5)
	tag(lamp, "P2D_Blink", { Rate = 1.2 })
	if heal then
		mk(m, "CrossH", Vector3.new(1.4, 0.4, 0.05), cf * CFrame.new(0, 1.1, -1.23), col, M.Neon, NOCOL)
		mk(m, "CrossV", Vector3.new(0.4, 1.4, 0.05), cf * CFrame.new(0, 1.1, -1.23), col, M.Neon, NOCOL)
	else
		mk(m, "BoltA", Vector3.new(0.35, 1, 0.05), cf * CFrame.new(0.12, 1.4, -1.23) * CFrame.Angles(0, 0, math.rad(-25)), col, M.Neon, NOCOL)
		mk(m, "BoltB", Vector3.new(0.35, 1, 0.05), cf * CFrame.new(-0.12, 0.8, -1.23) * CFrame.Angles(0, 0, math.rad(-25)), col, M.Neon, NOCOL)
	end
	cyl(m, "StationRing", 0.06, CONFIG.STATION_RADIUS * 2, ground + Vector3.new(0, 0.06, 0), col, M.Neon,
		{ Transparency = 0.82, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	m.Parent = currentDef and currentDef.dynamic or Workspace
	table.insert(SK.devices, { kind = kind, owner = p, model = m, body = body, pos = ground, untilT = os.clock() + dur })
end

function SK.placeWire(p, hrp)
	local mine = {}
	for i, d in ipairs(SK.devices) do
		if d.owner == p and d.kind == "wire" then table.insert(mine, i) end
	end
	if #mine >= CONFIG.TRIPWIRE_MAX then SK.removeDevice(mine[1]) end
	local look = SK.flatLook(hrp)
	local right = Vector3.new(-look.Z, 0, look.X)
	local center = SK.groundAt(hrp.Position + look * 2, { p.Character, killer and killer.Character })
	local a, b = center + right * 3.5, center - right * 3.5
	local m = Instance.new("Model")
	m.Name = "Tripwire"
	local post = mk(m, "WirePost", Vector3.new(0.25, 1.3, 0.25), a + Vector3.new(0, 0.65, 0), Color3.fromRGB(80, 70, 60), M.Wood)
	mk(m, "WirePost", Vector3.new(0.25, 1.3, 0.25), b + Vector3.new(0, 0.65, 0), Color3.fromRGB(80, 70, 60), M.Wood)
	beam(m, "Wire", a + Vector3.new(0, 0.8, 0), b + Vector3.new(0, 0.8, 0), 0.06, Color3.fromRGB(150, 150, 140), M.Metal,
		{ CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	m.Parent = currentDef and currentDef.dynamic or Workspace
	table.insert(SK.devices, { kind = "wire", owner = p, model = m, body = post, a = a, b = b, untilT = os.clock() + CONFIG.TRIPWIRE_LIFE })
end

-- Палач у отрезка растяжки (по горизонтали r, по высоте h)
function SK.nearSegment(pos, a, b, r, h)
	if math.abs(pos.Y - (a.Y + 3)) > h then return false end
	local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local ap = Vector3.new(pos.X - a.X, 0, pos.Z - a.Z)
	local t = math.clamp(ap:Dot(ab) / math.max(ab:Dot(ab), 1e-6), 0, 1)
	return (ap - ab * t).Magnitude <= r
end

-- удар Палача ломает станции перед ним
function SK.hitDevices(hrp)
	local look = SK.flatLook(hrp)
	for i = #SK.devices, 1, -1 do
		local d = SK.devices[i]
		if d.kind ~= "wire" then
			local delta = d.pos - hrp.Position
			local flat = Vector3.new(delta.X, 0, delta.Z)
			if flat.Magnitude <= CONFIG.KILLER_RANGE and (flat.Magnitude < 1 or flat.Unit:Dot(look) > 0.2) then
				burst(d.body, Color3.fromRGB(255, 140, 60), nil, 40)
				announce("Палач сломал станцию!", "bad", d.owner)
				SK.removeDevice(i)
			end
		end
	end
end

function SK.tick(now, dt)
	for p, st in pairs(SK.state) do
		local e = entryOf[p]
		if not e or e.status ~= "alive" or p.Parent ~= Players then
			SK.reset(p)
		else
			if st.guard and now >= st.guard.untilT then SK.endGuard(p) end
			local ch = st.channel
			if ch then
				if ch.kind == "selfheal" then
					local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
					if hum and hum.Health > 0 then
						hum.Health = math.min(hum.MaxHealth, hum.Health + CONFIG.SELFHEAL_AMOUNT / ch.dur * dt)
					end
				end
				if now >= ch.untilT then SK.endChannel(p, "done") end
			end
			if st.manaMax then -- мана Феликса копится сама
				st.mana = math.min(st.manaMax, st.mana + CONFIG.MANA_REGEN * dt)
				local shown = math.floor(st.mana)
				if shown ~= st.manaShown then
					st.manaShown = shown
					p:SetAttribute("Mana", shown)
				end
			end
		end
	end
	local _, khrp = killerAlive()
	for i = #SK.devices, 1, -1 do
		local d = SK.devices[i]
		if now >= d.untilT or not d.model.Parent then
			SK.removeDevice(i)
		elseif d.kind == "wire" then
			if khrp and SK.nearSegment(khrp.Position, d.a, d.b, 1.8, 4) then
				SK.slowKiller(CONFIG.TRIPWIRE_SLOW, CONFIG.TRIPWIRE_TIME)
				burst(khrp, Color3.fromRGB(200, 200, 190), nil, 30)
				announce("Палач задел растяжку!", "good", d.owner)
				SK.removeDevice(i)
			end
		else
			for _, e in ipairs(survivorList) do
				if e.status == "alive" then
					local c = e.player.Character
					local hrp = c and c:FindFirstChild("HumanoidRootPart")
					local hum = c and c:FindFirstChildOfClass("Humanoid")
					if hrp and hum and hum.Health > 0 and (hrp.Position - d.pos).Magnitude <= CONFIG.STATION_RADIUS then
						if d.kind == "heal" then
							hum.Health = math.min(hum.MaxHealth, hum.Health + CONFIG.STATION_HEAL * dt)
						else
							SK.stationBoost[e.player] = now + 0.3
						end
					end
				end
			end
		end
	end
end

-- сброс навыков игрока (смерть, побег, конец матча)
function SK.reset(p)
	local st = SK.state[p]
	if st then
		if st.guard then SK.endGuard(p) end
		if st.channel then
			local ch = st.channel
			st.channel = nil
			if ch.prompt then ch.prompt:Destroy() end
			SK.glow(p.Character, nil)
		end
	end
	SK.state[p] = nil
	SK.stationBoost[p] = nil
	local char = p.Character
	for _, n in ipairs({ "P2D_Bat", "P2D_Camera", "P2D_Shield" }) do
		local x = char and char:FindFirstChild(n)
		if x then x:Destroy() end
	end
end

function SK.resetAll()
	for p in pairs(SK.state) do SK.reset(p) end
	for i = #SK.devices, 1, -1 do SK.removeDevice(i) end
	SK.stationBoost = {}
	fx.slows = {}
end

-- настройка навыков выжившего на старте матча
function SK.setup(p, c, readyAt)
	SK.state[p] = nil
	local st = SK.get(p)
	for slot = 1, 2 do
		SK.setReady(p, slot, readyAt)
		SK.setActive(p, slot, 0)
	end
	p:SetAttribute("Skill1Broken", nil)
	if c.mana then
		st.mana, st.manaMax = c.mana, c.mana
		p:SetAttribute("MaxMana", c.mana)
		p:SetAttribute("Mana", c.mana)
	else
		p:SetAttribute("MaxMana", nil)
		p:SetAttribute("Mana", nil)
	end
end

-- обработчики: возвращают true (перезарядка с этого момента), "guard"/"channel" (свои правила) или nil (не сработало)
SK.use.punch = function(_, e, char, _, hrp)
	burst(hrp, Color3.fromRGB(255, 220, 60), nil, 30)
	SK.swish(hrp)
	local kchar, khrp = SK.inFront(hrp, CONFIG.PUNCH_RANGE, 0.35)
	if kchar and clearLine(hrp.Position, khrp.Position, { char, kchar }) then
		stunKiller(CONFIG.PUNCH_STUN, e.name)
	end
	return true
end

SK.use.counter = function(p, _, _, _, _, sk, slot)
	SK.startGuard(p, "counter", sk.dur, slot)
	return "guard"
end

SK.use.godeye = function(p, _, _, _, _, sk)
	SK.get(p).noSprintUntil = os.clock() + sk.dur
	fxEvent:FireClient(p, "godseye", sk.dur)
	return true
end

SK.use.adrenaline = function(p, _, _, _, hrp, sk)
	local st = SK.get(p)
	local now = os.clock()
	st.adrenalineUntil = now + sk.dur
	st.windedUntil = now + sk.dur + CONFIG.ADRENALINE_WINDED
	burst(hrp, Color3.fromRGB(255, 60, 60), nil, 40)
	fxEvent:FireClient(p, "adrenaline", sk.dur)
	return true
end

SK.use.heal = function(p, e, _, _, _, sk, slot)
	SK.startChannel(p, e, "heal", sk.dur, slot)
	return "channel"
end

SK.use.selfheal = function(p, e, _, _, _, sk, slot)
	SK.startChannel(p, e, "selfheal", sk.dur, slot)
	return "channel"
end

SK.use.station = function(p, _, _, _, hrp, sk, _, kind)
	if kind ~= "heal" and kind ~= "speed" then return nil end -- выбор ЛКМ/ПКМ приходит с клиента
	SK.placeStation(p, kind, hrp, sk.dur)
	return true
end

SK.use.tripwire = function(p, _, _, _, hrp)
	SK.placeWire(p, hrp)
	return true
end

SK.use.bat = function(p, e, char, _, hrp)
	local st = SK.get(p)
	if st.batBroken then return nil end
	st.windupUntil = os.clock() + CONFIG.BAT_WINDUP
	local bat = SK.handProp(char, "P2D_Bat", Vector3.new(0.4, 3.4, 0.4), CFrame.new(0, -0.4, -1.4) * CFrame.Angles(math.rad(-75), 0, 0),
		Color3.fromRGB(176, 124, 72), M.Wood)
	fxEvent:FireClient(p, "windup", CONFIG.BAT_WINDUP)
	task.delay(CONFIG.BAT_WINDUP, function()
		if bat then Debris:AddItem(bat, 0.35) end
		if not matchActive or e.status ~= "alive" or not hrp.Parent then return end
		SK.swish(hrp)
		local kchar, khrp = SK.inFront(hrp, CONFIG.BAT_RANGE, 0.3)
		if not kchar or not clearLine(hrp.Position, khrp.Position, { char, kchar }) then return end
		if SK.killerFaces(khrp, hrp.Position, 0.45) then
			-- попадание в лицо: бита ломается до конца матча, Палач оглушён
			st.batBroken = true
			p:SetAttribute("Skill1Broken", true)
			burst(khrp, Color3.fromRGB(176, 124, 72), nil, 50)
			if bat then bat:Destroy() end
			fxEvent:FireClient(p, "batbroke")
			stunKiller(CONFIG.BAT_STUN, e.name)
		else
			SK.slowKiller(CONFIG.BAT_SLOW, CONFIG.BAT_SLOW_TIME)
			fxEvent:FireClient(p, "bathit")
		end
	end)
	return true
end

SK.use.flash = function(p, e, char, _, hrp)
	local cam = SK.handProp(char, "P2D_Camera", Vector3.new(0.9, 0.7, 0.5), CFrame.new(0, -0.5, -0.6), Color3.fromRGB(40, 40, 46), M.SmoothPlastic)
	task.delay(0.25, function()
		if cam then Debris:AddItem(cam, 0.5) end
		if not matchActive or e.status ~= "alive" or not hrp.Parent then return end
		local head = char:FindFirstChild("Head") or hrp
		local l = pointLight(head, WHITE, 36, 14)
		Debris:AddItem(l, 0.18)
		burst(hrp, WHITE, nil, 60)
		local kchar, khrp = SK.inFront(hrp, CONFIG.FLASH_RANGE, 0.5)
		if kchar and SK.killerFaces(khrp, hrp.Position, 0.2) and clearLine(head.Position, khrp.Position, { char, kchar }) then
			fxEvent:FireClient(killer, "blinded", CONFIG.FLASH_BLIND)
			announce("Палач ослеплён вспышкой!", "good", p)
		end
	end)
	return true
end

SK.use.telekinesis = function(p, _, char, _, hrp, _, _, aim)
	local st = SK.get(p)
	if (st.mana or 0) < 5 then
		fxEvent:FireClient(p, "nomana")
		return nil
	end
	local dir = (typeof(aim) == "Vector3" and aim.Magnitude > 0.5 and aim.Magnitude < 1.5) and aim.Unit or hrp.CFrame.LookVector
	local from = hrp.Position + Vector3.new(0, 1.5, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	local res = Workspace:Raycast(from, dir * CONFIG.TK_RANGE, params)
	local endPos = res and res.Position or (from + dir * CONFIG.TK_RANGE)
	local hit = false
	local kchar, khrp = killerAlive()
	if kchar then
		if res and res.Instance and res.Instance:IsDescendantOf(kchar) then
			hit = true
		else
			-- снисхождение к прицелу: Палач не дальше 2.5 м от линии прицела (по горизонтали) и в прямой видимости
			local d = khrp.Position - hrp.Position
			local flatD = Vector3.new(d.X, 0, d.Z)
			local flatDir = Vector3.new(dir.X, 0, dir.Z)
			if flatDir.Magnitude > 0.1 and math.abs(d.Y) < 8 then
				local along = flatD:Dot(flatDir.Unit)
				local lateral = (flatD - flatDir.Unit * along).Magnitude
				if along > 0 and along <= CONFIG.TK_RANGE and lateral <= 2.5 and clearLine(from, khrp.Position, { char, kchar }) then
					hit = true
					endPos = khrp.Position
				end
			end
		end
	end
	local pct = math.floor(st.mana)
	st.mana = 0
	local bolt = beam(Workspace, "P2D_TKBolt", from, endPos, 0.5, Color3.fromRGB(120, 170, 255), M.Neon,
		{ CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	if bolt then Debris:AddItem(bolt, 0.25) end
	if hit then
		SK.slowKiller(pct / 100, CONFIG.TK_SLOW_TIME)
		burst(khrp, Color3.fromRGB(120, 170, 255), nil, 50)
		fxEvent:FireClient(p, "tkhit", pct)
	end
	return true
end

SK.use.shield = function(p, _, _, _, _, sk, slot)
	SK.startGuard(p, "shield", sk.dur, slot)
	return "guard"
end

------------------------------------------------------------------------
-- ПАЛАЧ: оружие и навык (Q)
------------------------------------------------------------------------
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
		if not matchActive or os.clock() < fx.stunUntil then return end
		local cd = CONFIG.KILLER_COOLDOWN * (killerMods and killerMods.attack or 1)
		if os.clock() - last < cd then return end
		last = os.clock()
		if fx.vanishSaved then setVanish(false) end -- удар раскрывает невидимку
		local anim = Instance.new("StringValue")
		anim.Name = "toolanim"
		anim.Value = "Slash"
		anim.Parent = tool
		Debris:AddItem(anim, 1)
		swing:Play()
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		SK.hitDevices(hrp)
		for _, e in ipairs(survivorList) do
			if e.status == "alive" then
				local c = e.player.Character
				local h = c and c:FindFirstChildOfClass("Humanoid")
				local r = c and c:FindFirstChild("HumanoidRootPart")
				if h and r and h.Health > 0 then
					local delta = r.Position - hrp.Position
					if delta.Magnitude > 0 and delta.Magnitude <= CONFIG.KILLER_RANGE
						and delta.Unit:Dot(hrp.CFrame.LookVector) > 0.3 then
						if SK.tryBlock(e) then break end -- контр-удар / щит: урона нет, Палач оглушён
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
	noJump(hum)
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
	if killerChar.skills[1].id == "dash" and not hrp:FindFirstChild("DashTrail") then
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

local function killerAbility(p, char, ab)
	if os.clock() < fx.stunUntil then return false end
	if ab.id == "dash" then
		fx.dashUntil = os.clock() + ab.dur
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
		fx.vanishUntil = os.clock() + ab.dur
		setVanish(true)
		fxEvent:FireClient(p, "vanish", ab.dur)
		for _, e in ipairs(survivorList) do
			if e.status == "alive" then fxEvent:FireClient(e.player, "giggle") end
		end
	end
	return true
end

-- клиент: (номер навыка 1|2, доп. данные: "heal"/"speed" для станции, направление прицела для телекинеза)
abilityEvent.OnServerEvent:Connect(function(p, slot, arg)
	if not matchActive then return end
	slot = (slot == 2) and 2 or 1
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp or hum.Health <= 0 then return end
	local now = serverNow()
	if p == killer and killerChar then
		local ab = killerChar.skills[1]
		if slot ~= 1 or now < (p:GetAttribute("Skill1ReadyAt") or math.huge) then return end
		if killerAbility(p, char, ab) then
			SK.setReady(p, 1, now + ab.cd)
			SK.setActive(p, 1, now + (ab.dur or 0))
		end
		return
	end
	local e = entryOf[p]
	if not e or e.status ~= "alive" then return end
	local sk = e.char.skills and e.char.skills[slot]
	if not sk then return end
	local st = SK.get(p)
	-- повторное нажатие: сбросить щит (с отталкиванием) или выйти из позы лечения
	if st.guard then
		if st.guard.slot == slot and st.guard.kind == "shield" then SK.releaseShield(p, hrp) end
		return
	end
	if st.channel then
		if st.channel.slot == slot and st.channel.kind == "heal" then SK.endChannel(p, "cancel") end
		return
	end
	if now < (p:GetAttribute("Skill" .. slot .. "ReadyAt") or math.huge) or p:GetAttribute("Skill" .. slot .. "Broken") then return end
	local fn = SK.use[sk.id]
	if not fn then return end
	local res = fn(p, e, char, hum, hrp, sk, slot, arg)
	if res == true then
		SK.setReady(p, slot, now + sk.cd)
		SK.setActive(p, slot, now + (sk.dur or 0))
	elseif res == "guard" then
		SK.setReady(p, slot, now + sk.cd)
	elseif res == "channel" then
		SK.setReady(p, slot, now + sk.dur + sk.cd) -- уточнится, когда поза/самолечение закончится
	end
end)

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
		for slot = 1, 2 do
			p:SetAttribute("Skill" .. slot .. "ReadyAt", nil)
			p:SetAttribute("Skill" .. slot .. "Until", nil)
		end
		p:SetAttribute("Skill1Broken", nil)
		p:SetAttribute("Mana", nil)
		p:SetAttribute("MaxMana", nil)
		p:SetAttribute("NoSprint", nil)
		p:SetAttribute("StunnedUntil", nil)
		p:SetAttribute("Kills", nil)
		pcall(function() p.ReplicationFocus = nil end)
		task.spawn(function()
			pcall(function() p:LoadCharacter() end) -- спавн в лобби, сброс инструментов/света/скорости/внешности
		end)
	end
end

------------------------------------------------------------------------
-- ЛОББИ-ТАЙМЕР; карта выбирается случайно и не повторяет прошлую
------------------------------------------------------------------------
local function pickMap()
	local pool = {}
	for _, info in ipairs(MAP_INFO) do
		if info.key ~= lastMap then table.insert(pool, info.key) end
	end
	return pool[rng:NextInteger(1, #pool)]
end

local function runCountdown(seconds)
	setPhase("Countdown")
	for t = seconds or CONFIG.LOBBY_COUNTDOWN, 1, -1 do
		if #Players:GetPlayers() < CONFIG.MIN_PLAYERS then return nil end
		gameState:SetAttribute("TimeLeft", t)
		task.wait(1)
	end
	if #getReadyPlayers() < CONFIG.MIN_PLAYERS then return nil end
	return pickMap()
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
			local col = roleColor(c)
			s.charText.Text = c.name
			s.charText.TextColor3 = WHITE
			s.nameText.Text = p.DisplayName
			s.plate.BackgroundColor3 = col:Lerp(BLACK, 0.6)
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
				hum.WalkSpeed = on and 0 or CONFIG.LOBBY_SPEED
				noJump(hum)
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
	for p, role in pairs(selRoles) do
		if p.Parent == Players and not assigned[p] then
			local pool = role == "Killer" and freeKillers or freeSurvivors
			if #pool > 0 then assigned[p] = table.remove(pool) end
		end
	end
	return assigned
end

-- Палач ушёл со сцены (в одиночном тесте с MIN_PLAYERS = 1 Палача нет изначально — это не ошибка)
local selHadKiller = false
local function killerOnStage()
	if not selHadKiller then return true end
	for p, role in pairs(selRoles) do
		if role == "Killer" and p.Parent == Players then return true end
	end
	return false
end

local function runSelection()
	resetPicks()
	pickRoles()
	selHadKiller = false
	for _, role in pairs(selRoles) do
		if role == "Killer" then selHadKiller = true end
	end
	if participantsLeft() < CONFIG.MIN_PLAYERS then return false end
	for p, role in pairs(selRoles) do
		p:SetAttribute("Role", role)
		pickStateEvent:FireClient(p, nil, role) -- клиент узнаёт свою таблицу
	end
	publishStage()
	freezePlayers(true, selRoles)

	setPhase("ToSelection")
	gameState:SetAttribute("TimeLeft", 0)
	task.wait(CONFIG.FADE_TIME)
	for p in pairs(selRoles) do restage(p) end
	setPhase("Selection")

	local endAt = os.clock() + CONFIG.SELECT_TIME
	local shortened = false
	local lastShown = -1
	while true do
		task.wait(0.1)
		if participantsLeft() < CONFIG.MIN_PLAYERS then return false end
		if not killerOnStage() then
			announce("Палач покинул сцену. Новый отбор…", "warn")
			return false
		end
		if not shortened and allPicked() then
			shortened = true
			endAt = math.min(endAt, os.clock() + CONFIG.SELECT_SHORT)
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
	return participantsLeft() >= CONFIG.MIN_PLAYERS and killerOnStage()
end

-- +время за убийство; клиент по BonusSeq плавно краснит часы
local function addMatchTime(sec)
	matchEndAt += sec
	gameState:SetAttribute("BonusAmount", sec)
	gameState:SetAttribute("BonusSeq", (gameState:GetAttribute("BonusSeq") or 0) + 1)
end

------------------------------------------------------------------------
-- МАТЧ
------------------------------------------------------------------------
local function cleanupMatchState()
	matchActive = false
	if fx.vanishSaved then setVanish(false) end
	fx.dashUntil, fx.vanishUntil, fx.stunUntil, fx.stunImmuneUntil = 0, 0, 0, 0
	SK.resetAll()
	for _, c in ipairs(matchConns) do c:Disconnect() end
	matchConns = {}
	for p in pairs(stamina) do clearStamina(p) end
	boostUntil = {}
end

local function runMatch(mapKey)
	local def = MAPS[mapKey]
	local assigned = resolveAssignments()
	local killerP = nil
	for p, id in pairs(assigned) do
		if CHAR_BY_ID[id].killer then killerP = p end
	end
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
	end
	survivorList, entryOf = {}, {}
	local firstAbility = serverNow() + CONFIG.SURVIVOR_FIRST_ABILITY
	for _, it in ipairs(picked) do
		local e = {
			player = it.player, userId = it.player.UserId, charId = it.char.id, port = it.port,
			name = it.char.name, dname = it.player.DisplayName, char = it.char, status = "alive",
		}
		table.insert(survivorList, e)
		entryOf[it.player] = e
		it.player:SetAttribute("InMatch", true)
		it.player:SetAttribute("Status", "alive")
		it.player:SetAttribute("Role", "Survivor")
		it.player:SetAttribute("Port", it.port)
		SK.setup(it.player, it.char, firstAbility)
	end
	if killer then
		killer:SetAttribute("InMatch", true)
		killer:SetAttribute("Status", "alive")
		killer:SetAttribute("Role", "Killer")
		killer:SetAttribute("Port", nil)
		killer:SetAttribute("Kills", 0)
		SK.setReady(killer, 1, serverNow() + CONFIG.KILLER_FIRST_ABILITY)
		SK.setActive(killer, 1, 0)
		killer:SetAttribute("Skill2ReadyAt", nil)
		killer:SetAttribute("MaxMana", nil)
		killer:SetAttribute("StunnedUntil", 0)
	end

	-- таймер матча: 1 минута + 1 минута за каждого выжившего
	local total = #survivorList
	local matchTime = CONFIG.BASE_MATCH_TIME + CONFIG.TIME_PER_SURVIVOR * total
	gameState:SetAttribute("MapKey", mapKey)
	resetEscapes(def)
	gameState:SetAttribute("EscapeOpen", false)
	gameState:SetAttribute("TimeLeft", matchTime)
	publishRoster()

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
			hum.MaxHealth = mods.hp
			hum.Health = hum.MaxHealth
			hum.WalkSpeed = CONFIG.SURVIVOR_SPEED * mods.speed
			noJump(hum)
			addFlashlight(char)
			initStamina(e.player, false, mods)
			watchDamage(e.player, hum)
			table.insert(matchConns, hum.Died:Connect(function()
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
	setPhase("Match")

	local lastShown = -1
	local escapesOpen = false
	local killerLeft = false
	while true do
		task.wait(0.2)
		local remaining = math.max(0, math.ceil(matchEndAt - os.clock()))
		if remaining ~= lastShown then
			lastShown = remaining
			gameState:SetAttribute("TimeLeft", remaining)
		end
		if not escapesOpen and remaining <= CONFIG.ESCAPE_OPEN_AT then
			escapesOpen = true
			local e = openRandomEscape(def) -- открывается ОДИН случайный выход
			gameState:SetAttribute("EscapeOpen", true)
			gameState:SetAttribute("ExitPos", e.zone.Position)
		end
		checkEscapes(def)

		if killer and killer.Parent ~= Players then
			killerLeft = true
			break
		end
		if countStatus("alive") == 0 then break end
		if remaining <= 0 then
			announce("ВРЕМЯ ВЫШЛО!", "warn")
			for _, e in ipairs(survivorList) do
				if e.status == "alive" then
					markDead(e)
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
		table.insert(res.survivors, { n = e.dname, c = e.charId, s = e.status, p = e.port })
	end
	if killer and killerChar then
		res.killer = { n = killer.DisplayName, c = killerChar.id, k = kills }
	end
	resultsEvent:FireAllClients(res)
	setPhase("Ending")
	task.wait(CONFIG.ENDING_TIME)

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
	pcall(function() p.DevEnableMouseLock = false end) -- встроенный shift-lock на Shift выключен: Shift — бег
	task.delay(20, function()
		if p.Parent == Players and not p:GetAttribute("P2D_ClientBuild") then
			warn("[P2D] " .. p.Name .. ": GameClient не отозвался. Проверь, что свежий LocalScript GameClient лежит в StarterPlayer > StarterPlayerScripts (одна копия).")
		end
	end)
	p.CharacterAdded:Connect(function(char)
		local hum = char:WaitForChild("Humanoid", 5)
		if hum then noJump(hum) end
		local ph = gameState:GetAttribute("Phase")
		if (ph == "Selection" or ph == "Starting") and selRoles[p] then
			task.wait(0.3)
			if pickOf[p] then applyLook(char, CHAR_BY_ID[pickOf[p]]) end
			restage(p)
		elseif matchActive and p == killer then
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
		if e then markDead(e) end
	end
	stamina[p] = nil
	boostUntil[p] = nil
	SK.reset(p)
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
-- ожидание -> таймер лобби -> сцена выбора -> матч -> итоги -> лобби
------------------------------------------------------------------------
local function backToLobby()
	setPhase("Waiting")
	gameState:SetAttribute("TimeLeft", 0)
	freezePlayers(false)
	returnAllToLobby()
	resetPicks()
	selRoles = {}
	task.wait(1.5)
end

task.spawn(function()
	local quickRestart = false -- после сорванного отбора лобби ждёт меньше
	while true do
		setPhase("Waiting")
		gameState:SetAttribute("TimeLeft", 0)
		while #Players:GetPlayers() < CONFIG.MIN_PLAYERS do
			task.wait(1)
		end
		local mapKey = runCountdown(quickRestart and 10 or nil)
		quickRestart = false
		if mapKey then
			local okSel, selDone = pcall(runSelection)
			if okSel and selDone then
				setPhase("Starting")
				gameState:SetAttribute("MapKey", mapKey)
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
				quickRestart = true
			end
		end
		task.wait(1)
	end
end)
