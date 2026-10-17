-- Lock-on: press ; (semicolon) to lock onto the boss/NPC nearest your crosshair. Your view then tracks
-- its chest; press ; again to release.

local MAX_DIST = 4000
local CONE = math.cos(math.rad(35))
local LOST_SIGHT_TIME = 2
local TURN_SPEED = 14 -- higher = snappier tracking

local target, lockAng, lostSince
local keyWasDown, nextToggle = false, 0

local function Alive(ent)
	return IsValid(ent) and (ent:Health() > 0 or ent:GetNW2Int("DrGBaseHealth", 0) > 0)
end

local function AimPos(ent)
	local bone = ent:LookupBone("ValveBiped.Bip01_Spine2")
	if bone then
		local pos = ent:GetBonePosition(bone)
		if pos and pos ~= ent:GetPos() then return pos end
	end
	return ent:WorldSpaceCenter()
end

local function CanSee(ply, ent)
	local tr = util.TraceLine({start = ply:EyePos(), endpos = AimPos(ent), mask = MASK_SOLID, filter = function(e)
		return not (e == ply or e == ent or e:IsNPC() or e:IsPlayer() or e:IsNextBot())
	end})
	return not tr.Hit
end

local function FindTarget(ply)
	local eye, fwd = ply:EyePos(), ply:GetAimVector()
	local best, bestScore
	for _, ent in ipairs(ents.GetAll()) do
		if ent == ply or not (ent.IsBrolyBoss or ent:IsNPC() or ent:IsNextBot()) or not Alive(ent) then continue end
		local to = AimPos(ent) - eye
		local dist = to:Length()
		if dist > MAX_DIST then continue end
		local dot = fwd:Dot(to / dist)
		if dot < CONE or not CanSee(ply, ent) then continue end
		local score = dot - dist / MAX_DIST * 0.2 + (ent.IsBrolyBoss and 1 or 0)
		if not best or score > bestScore then best, bestScore = ent, score end
	end
	return best
end

local function Release()
	if target then surface.PlaySound("buttons/blip2.wav") end
	target, lockAng, lostSince = nil, nil, nil
end

hook.Add("Think", "BrolyLockOn_Input", function()
	local ply = LocalPlayer()
	if not IsValid(ply) then return end

	local keyDown = input.IsKeyDown(KEY_SEMICOLON)
	local typing = ply:IsTyping() or gui.IsGameUIVisible() or IsValid(vgui.GetKeyboardFocus())
	if keyDown and not keyWasDown and not typing and CurTime() > nextToggle then
		nextToggle = CurTime() + 0.25
		if target then
			Release()
		else
			target = FindTarget(ply)
			if target then
				lockAng = ply:EyeAngles()
				surface.PlaySound("buttons/blip1.wav")
			end
		end
	end
	keyWasDown = keyDown

	if not target then return end
	if not Alive(target) or not ply:Alive() or ply:EyePos():Distance(AimPos(target)) > MAX_DIST then
		Release()
		return
	end
	if CanSee(ply, target) then
		lostSince = nil
	else
		lostSince = lostSince or CurTime()
		if CurTime() - lostSince > LOST_SIGHT_TIME then Release() end
	end
end)

hook.Add("CreateMove", "BrolyLockOn_Aim", function(cmd)
	if not target or not lockAng then return end
	local ply = LocalPlayer()
	local want = (AimPos(target) - ply:EyePos()):Angle()
	want.p = math.NormalizeAngle(want.p)
	lockAng = LerpAngle(math.Clamp(FrameTime() * TURN_SPEED, 0, 1), lockAng, want)
	lockAng.r = 0
	cmd:SetViewAngles(lockAng) -- overrides mouse look while locked
end)

local MARK_COL = Color(205, 170, 70)
local MARK_CORE = Color(185, 40, 30)

hook.Add("HUDPaint", "BrolyLockOn_Marker", function()
	if not target then return end
	local sp = AimPos(target):ToScreen()
	if not sp.visible then return end
	local pulse = 1 + 0.15 * math.sin(CurTime() * 8)
	local r = math.Round(ScrH() * 0.012 * pulse)
	local x, y = sp.x, sp.y

	-- rotated diamond outline with a red core
	draw.NoTexture()
	surface.SetDrawColor(MARK_CORE)
	surface.DrawPoly({{x = x, y = y - r * 0.45}, {x = x + r * 0.45, y = y}, {x = x, y = y + r * 0.45}, {x = x - r * 0.45, y = y}})
	surface.SetDrawColor(MARK_COL)
	for i = 0, 1 do
		local rr = r + i
		surface.DrawLine(x, y - rr, x + rr, y)
		surface.DrawLine(x + rr, y, x, y + rr)
		surface.DrawLine(x, y + rr, x - rr, y)
		surface.DrawLine(x - rr, y, x, y - rr)
	end
end)
