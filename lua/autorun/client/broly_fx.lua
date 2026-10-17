-- Broly's client-side power effects: burning green aura, crackling lightning, pulsing light,
-- and screen flashes. Everything gets wilder while he's using an ability (NW2Bool "BrolyPowered").

local KI = Color(140, 255, 90)
local KI_HOT = Color(210, 255, 170)
local MAT_GLOW = Material("sprites/light_glow02_add")
local MAT_BEAM = Material("trails/electric")
local MAT_LASER = Material("trails/laser")
local MAT_RING = Material("effects/select_ring")
local AURA_DIST = 4000

local state = {} -- [ent] = {emitter, nextPuff, arcs = {}}

local function BonePos(ent, name)
	local b = ent:LookupBone(name)
	return b and ent:GetBonePosition(b) or ent:WorldSpaceCenter()
end

local ARC_BONES = {
	"ValveBiped.Bip01_Head1", "ValveBiped.Bip01_Spine2", "ValveBiped.Bip01_Pelvis",
	"ValveBiped.Bip01_L_Hand", "ValveBiped.Bip01_R_Hand", "ValveBiped.Bip01_L_Forearm",
	"ValveBiped.Bip01_R_Forearm", "ValveBiped.Bip01_L_Calf", "ValveBiped.Bip01_R_Calf"
}

-- a jagged lightning bolt between two points, kept for a few frames
local function NewArc(ent, powered)
	local a = BonePos(ent, ARC_BONES[math.random(#ARC_BONES)]) + VectorRand() * 10
	local b
	if powered and math.random() < 0.4 then
		b = ent:GetPos() + VectorRand() * Vector(140, 140, 0) -- strikes the ground around him
	else
		b = BonePos(ent, ARC_BONES[math.random(#ARC_BONES)]) + VectorRand() * 25
	end
	local pts = {a}
	local segs = math.random(5, 8)
	for i = 1, segs - 1 do
		pts[#pts + 1] = LerpVector(i / segs, a, b) + VectorRand() * 12
	end
	pts[#pts + 1] = b
	return {pts = pts, die = CurTime() + math.Rand(0.05, 0.14), width = math.Rand(2, powered and 7 or 4)}
end

-- mouth blast endpoints: his mouth attachment -> where the server says the beam hits
local function BeamPoints(ent)
	local att = ent:GetAttachment(ent:LookupAttachment("mouth"))
	local a = att and att.Pos or BonePos(ent, "ValveBiped.Bip01_Head1")
	return a, ent:GetNW2Vector("BrolyBeamEnd", a)
end

local function DrawBeam(ent)
	local a, b = BeamPoints(ent)
	local len = a:Distance(b)
	if len < 1 then return end
	local dir = (b - a):GetNormalized()
	local flick = math.Rand(0.85, 1.1)
	local scroll = -CurTime() * 6

	render.SetMaterial(MAT_LASER)
	render.DrawBeam(a, b, 260 * flick, scroll, scroll + len / 250, Color(KI.r, KI.g, KI.b, 110))
	render.DrawBeam(a, b, 140 * flick, scroll, scroll + len / 250, Color(170, 255, 130, 230))
	render.DrawBeam(a, b, 55 * flick, scroll * 2, scroll * 2 + len / 250, Color(255, 255, 255, 255))

	-- rings racing down the beam
	render.SetMaterial(MAT_RING)
	for i = 0, math.floor(len / 300) do
		local d = (CurTime() * 1800 + i * 300) % len
		render.DrawQuadEasy(a + dir * d, -dir, 190, 190, Color(KI.r, KI.g, KI.b, 200), CurTime() * 300 + i * 40)
	end

	-- lightning wrapped around it
	render.SetMaterial(MAT_BEAM)
	for k = 1, 3 do
		local pts = math.min(16, math.floor(len / 120) + 2)
		render.StartBeam(pts)
		for i = 0, pts - 1 do
			local p = a + dir * (len * i / (pts - 1)) + VectorRand() * 70
			render.AddBeam(p, math.Rand(5, 10), i / pts, KI_HOT)
		end
		render.EndBeam()
	end

	render.SetMaterial(MAT_GLOW)
	render.DrawSprite(a, 280 * flick, 280 * flick, Color(KI.r, KI.g, KI.b, 255))
	render.DrawSprite(a, 110, 110, Color(255, 255, 255, 255))
	render.DrawSprite(b, 600 * flick, 600 * flick, Color(KI.r, KI.g, KI.b, 255))
	render.DrawSprite(b, 250 * flick, 250 * flick, Color(255, 255, 255, 230))
end

hook.Add("Think", "BrolyFX_Aura", function()
	local eye = EyePos()
	for ent, st in pairs(state) do
		if not IsValid(ent) then
			if st.emitter then st.emitter:Finish() end
			state[ent] = nil
		end
	end

	-- (ents.FindByClass misses DrGBase nextbots on the client; the boss flag is reliable)
	for _, ent in ipairs(ents.GetAll()) do
		if not ent.IsBrolyBoss then continue end
		if ent:IsDormant() or ent:GetPos():DistToSqr(eye) > AURA_DIST * AURA_DIST then continue end
		local st = state[ent]
		if not st then
			st = {emitter = ParticleEmitter(ent:GetPos()), nextPuff = 0, arcs = {}}
			state[ent] = st
		end
		local powered = ent:GetNW2Bool("BrolyPowered")
		local now = CurTime()
		local center = ent:WorldSpaceCenter()
		local em = st.emitter
		em:SetPos(center)

		-- rising aura flames
		if now > st.nextPuff then
			st.nextPuff = now + (powered and 0.012 or 0.035)
			for i = 1, powered and 3 or 1 do
				local base = ent:GetPos() + Vector(math.Rand(-22, 22), math.Rand(-22, 22), math.Rand(0, 90))
				local p = em:Add("sprites/light_glow02_add", base)
				if p then
					p:SetVelocity(Vector(math.Rand(-15, 15), math.Rand(-15, 15), math.Rand(80, powered and 260 or 150)))
					p:SetDieTime(math.Rand(0.4, 0.8))
					p:SetStartAlpha(powered and 160 or 90)
					p:SetEndAlpha(0)
					p:SetStartSize(math.Rand(10, powered and 34 or 22))
					p:SetEndSize(2)
					p:SetColor(KI.r, KI.g, KI.b)
					p:SetAirResistance(40)
				end
			end
			if powered and math.random() < 0.5 then -- dust and pebbles kicked up by the pressure
				local p = em:Add("particle/particle_smokegrenade", ent:GetPos() + VectorRand() * Vector(60, 60, 0))
				if p then
					local out = (p:GetPos() - ent:GetPos()):GetNormalized()
					p:SetVelocity(out * math.Rand(150, 300) + Vector(0, 0, 40))
					p:SetDieTime(math.Rand(0.6, 1))
					p:SetStartAlpha(60)
					p:SetEndAlpha(0)
					p:SetStartSize(15)
					p:SetEndSize(math.Rand(50, 80))
					p:SetColor(180, 175, 160)
					p:SetAirResistance(120)
				end
			end
		end

		-- lightning
		for i = #st.arcs, 1, -1 do
			if st.arcs[i].die < now then table.remove(st.arcs, i) end
		end
		local chance = powered and 0.6 or 0.12
		if math.random() < chance then st.arcs[#st.arcs + 1] = NewArc(ent, powered) end

		-- mouth blast: debris and embers boiling off the beam and its impact point
		if ent:GetNW2Float("BrolyBeamUntil", 0) > now then
			local a, b = BeamPoints(ent)
			local hit = em:Add("sprites/light_glow02_add", b)
			if hit then
				hit:SetVelocity(VectorRand() * 400)
				hit:SetDieTime(math.Rand(0.3, 0.6))
				hit:SetStartAlpha(255)
				hit:SetEndAlpha(0)
				hit:SetStartSize(math.Rand(30, 60))
				hit:SetEndSize(0)
				hit:SetColor(KI.r, KI.g, KI.b)
				hit:SetAirResistance(100)
			end
			local smoke = em:Add("particle/particle_smokegrenade", b)
			if smoke then
				smoke:SetVelocity(VectorRand() * 200 + Vector(0, 0, 150))
				smoke:SetDieTime(math.Rand(0.8, 1.4))
				smoke:SetStartAlpha(90)
				smoke:SetEndAlpha(0)
				smoke:SetStartSize(40)
				smoke:SetEndSize(math.Rand(120, 180))
				smoke:SetColor(170, 165, 150)
				smoke:SetAirResistance(80)
			end
			local along = em:Add("sprites/light_glow02_add", LerpVector(math.random(), a, b) + VectorRand() * 30)
			if along then
				along:SetVelocity(VectorRand() * 120)
				along:SetDieTime(math.Rand(0.2, 0.4))
				along:SetStartAlpha(200)
				along:SetEndAlpha(0)
				along:SetStartSize(math.Rand(20, 40))
				along:SetEndSize(0)
				along:SetColor(KI_HOT.r, KI_HOT.g, KI_HOT.b)
			end
			local bl = DynamicLight(ent:EntIndex() + 4096)
			if bl then
				bl.pos = b
				bl.r, bl.g, bl.b = KI.r, KI.g, KI.b
				bl.brightness = 6
				bl.decay = 3000
				bl.size = 700
				bl.dietime = now + 0.1
			end
		end

		-- pulsing light
		local dl = DynamicLight(ent:EntIndex())
		if dl then
			dl.pos = center
			dl.r, dl.g, dl.b = KI.r, KI.g, KI.b
			dl.brightness = (powered and 3 or 1) + math.Rand(0, powered and 2 or 0.6)
			dl.decay = 2000
			dl.size = powered and 420 or 220
			dl.dietime = now + 0.1
		end
	end
end)

hook.Add("PostDrawTranslucentRenderables", "BrolyFX_Draw", function(depth, skybox)
	if skybox then return end
	for ent, st in pairs(state) do
		if not IsValid(ent) or ent:IsDormant() then continue end
		local powered = ent:GetNW2Bool("BrolyPowered")

		-- body glow
		render.SetMaterial(MAT_GLOW)
		local flick = math.Rand(0.9, 1.1)
		local size = (powered and 230 or 150) * flick
		render.DrawSprite(ent:WorldSpaceCenter(), size, size * 1.4, Color(KI.r, KI.g, KI.b, powered and 70 or 35))

		if ent:GetNW2Float("BrolyBeamUntil", 0) > CurTime() then DrawBeam(ent) end

		-- lightning bolts
		render.SetMaterial(MAT_BEAM)
		for _, arc in ipairs(st.arcs) do
			render.StartBeam(#arc.pts)
			for i, p in ipairs(arc.pts) do
				render.AddBeam(p, arc.width, i / #arc.pts, KI_HOT)
			end
			render.EndBeam()
		end
	end
end)

-- screen flash ---------------------------------------------------------------------------------
local flash = {a = 0, col = KI}
net.Receive("BrolyFlash", function()
	local s = net.ReadFloat()
	local col = net.ReadColor(false)
	flash.a = math.min(255, flash.a + 255 * s)
	flash.col = col
end)

hook.Add("HUDPaint", "BrolyFX_Flash", function()
	if flash.a <= 0 then return end
	surface.SetDrawColor(flash.col.r, flash.col.g, flash.col.b, flash.a)
	surface.DrawRect(0, 0, ScrW(), ScrH())
	flash.a = math.max(0, flash.a - FrameTime() * 600)
end)
