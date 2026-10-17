-- Elden Ring style boss health bar.
-- Any entity with ENT.IsBrolyBoss = true (and optional ENT.BossName) gets a bar at the bottom of the
-- screen once it targets the local player or the player damages it.

local ENGAGE_RANGE = 3000       -- bar hides if you get further than this from the boss
local TRAIL_HOLD = 0.8          -- seconds the yellow "damage" chunk lingers before draining
local TRAIL_SPEED = 0.6         -- fraction of the bar per second the chunk drains at
local DAMAGE_NUMBER_TIME = 2.5  -- damage counter resets after this long without a hit
local FADE_TIME = 0.6

local bosses = {} -- [ent] = state

local function MakeFonts()
	local h = ScrH()
	surface.CreateFont("EldenBossName", {font = "Georgia", size = math.Round(h * 0.026), weight = 500, antialias = true, shadow = true})
	surface.CreateFont("EldenBossDamage", {font = "Georgia", size = math.Round(h * 0.022), weight = 500, antialias = true, shadow = true})
end
MakeFonts()
hook.Add("OnScreenSizeChanged", "EldenBossBar_Fonts", MakeFonts)

local function GetHealthFrac(ent)
	local max = ent:GetNW2Int("DrGBaseMaxHealth", ent:GetMaxHealth())
	local hp = ent:GetNW2Int("DrGBaseHealth", ent:Health())
	if max <= 0 then return 0, hp end
	return math.Clamp(hp / max, 0, 1), hp
end

local function IsEngaging(ent, ply)
	return ent.GetEnemy ~= nil and ent:GetEnemy() == ply
end

local function Engage(ent)
	local st = bosses[ent]
	if st then
		st.dying = false
		return
	end
	local frac, hp = GetHealthFrac(ent)
	bosses[ent] = {
		ent = ent, name = ent.BossName or ent.PrintName or "Boss",
		frac = frac, trail = frac, lastHp = hp, trailHold = 0,
		damage = 0, damageTime = 0, alpha = 0, dying = false, order = CurTime()
	}
end

hook.Add("Think", "EldenBossBar_Track", function()
	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	local now = CurTime()

	for _, ent in ipairs(ents.GetAll()) do
		if ent.IsBrolyBoss and IsEngaging(ent, ply) then Engage(ent) end
	end

	for ent, st in pairs(bosses) do
		if not IsValid(ent) or (st.frac <= 0) then
			st.dying = true
		elseif ply:GetPos():DistToSqr(ent:GetPos()) > ENGAGE_RANGE * ENGAGE_RANGE and not IsEngaging(ent, ply) then
			st.dying = true
		end

		if IsValid(ent) then
			local frac, hp = GetHealthFrac(ent)
			if hp < st.lastHp then
				st.damage = (now - st.damageTime < DAMAGE_NUMBER_TIME) and st.damage + (st.lastHp - hp) or (st.lastHp - hp)
				st.damageTime = now
				st.trailHold = now + TRAIL_HOLD
			end
			st.lastHp = hp
			st.frac = frac
		end

		-- trail drains after the hold, never below the real health; heals snap it up
		if st.trail < st.frac then st.trail = st.frac
		elseif now > st.trailHold then st.trail = math.max(st.frac, st.trail - TRAIL_SPEED * FrameTime()) end

		local target = st.dying and 0 or 1
		st.alpha = math.Approach(st.alpha, target, FrameTime() / FADE_TIME)
		if st.dying and st.alpha <= 0 and st.trail <= st.frac then bosses[ent] = nil end
	end
end)

-- the server tells us when we hit a boss, so the bar shows even before it targets us
net.Receive("EldenBossBar_Engage", function()
	local ent = net.ReadEntity()
	if IsValid(ent) and ent.IsBrolyBoss then Engage(ent) end
end)

local COL_FRAME = Color(10, 8, 6)
local COL_EDGE = Color(120, 100, 60)
local COL_BACK = Color(25, 20, 18)
local COL_HP = Color(140, 18, 16)
local COL_HP_HI = Color(185, 40, 30)
local COL_TRAIL = Color(205, 170, 70)
local COL_TEXT = Color(235, 228, 210)
local COL_DOOM = Color(120, 30, 200)
local COL_DOOM_HI = Color(200, 120, 255)
local DOOM_DURATION = 12 -- matches ENT.Doomsday.duration

-- seconds of doomsday left, or nil
local function DoomLeft(st)
	local ent = st.ent
	if not IsValid(ent) then return end
	local left = ent:GetNW2Float("BrolyDoomUntil", 0) - CurTime()
	return left > 0 and left or nil
end

local function DrawBar(st, x, y, w, h)
	local a = st.alpha * 255
	local function c(col, mul) return Color(col.r, col.g, col.b, a * (mul or 1)) end

	local doom = DoomLeft(st)

	-- name + damage counter (doomsday: a purple countdown instead)
	local flicker = doom and (0.7 + 0.3 * math.sin(CurTime() * 12)) or 1
	draw.SimpleText(doom and st.name .. "  -  DOOMSDAY" or st.name, "EldenBossName", x + 2, y - 4,
		doom and c(COL_DOOM_HI, flicker) or c(COL_TEXT), TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
	if doom then
		draw.SimpleText(string.format("%.1f", doom), "EldenBossDamage", x + w - 2, y - 4, c(COL_DOOM_HI), TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
	elseif st.damage > 0 and CurTime() - st.damageTime < DAMAGE_NUMBER_TIME then
		local fade = math.Clamp((DAMAGE_NUMBER_TIME - (CurTime() - st.damageTime)) / 0.5, 0, 1)
		draw.SimpleText(tostring(st.damage), "EldenBossDamage", x + w - 2, y - 4, c(COL_TEXT, fade), TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
	end

	-- frame
	surface.SetDrawColor(c(COL_FRAME))
	surface.DrawRect(x - 3, y - 3, w + 6, h + 6)
	surface.SetDrawColor(c(COL_EDGE, 0.8))
	surface.DrawOutlinedRect(x - 2, y - 2, w + 4, h + 4, 1)
	surface.SetDrawColor(c(COL_BACK))
	surface.DrawRect(x, y, w, h)

	if doom then -- the bar becomes his remaining time, draining in purple
		local dw = math.Round(w * doom / DOOM_DURATION)
		surface.SetDrawColor(c(COL_DOOM))
		surface.DrawRect(x, y, dw, h)
		surface.SetDrawColor(c(COL_DOOM_HI, 0.7 * flicker))
		surface.DrawRect(x, y, dw, math.max(1, math.floor(h * 0.3)))
		return
	end

	-- yellow damage chunk, then red health on top
	surface.SetDrawColor(c(COL_TRAIL))
	surface.DrawRect(x, y, math.Round(w * st.trail), h)
	local hw = math.Round(w * st.frac)
	surface.SetDrawColor(c(COL_HP))
	surface.DrawRect(x, y, hw, h)
	surface.SetDrawColor(c(COL_HP_HI, 0.6))
	surface.DrawRect(x, y, hw, math.max(1, math.floor(h * 0.3)))
end

hook.Add("HUDPaint", "EldenBossBar_Draw", function()
	local list = {}
	for _, st in pairs(bosses) do list[#list + 1] = st end
	if #list == 0 then return end
	table.sort(list, function(a, b) return a.order < b.order end)

	local sw, sh = ScrW(), ScrH()
	local w, h = math.Round(sw * 0.56), math.max(6, math.Round(sh * 0.011))
	local x = math.Round((sw - w) / 2)
	local y = math.Round(sh * 0.89)
	local step = math.Round(sh * 0.06)
	for i, st in ipairs(list) do
		DrawBar(st, x, y - (i - 1) * step, w, h)
	end
end)
