-- Violent energy dome: a green sphere that bursts outward (overshooting), crackles with lightning
-- and dissolves. EffectData: Origin = center (ground), Scale = max radius, Magnitude = power.

local KI = Color(140, 255, 90)
local KI_HOT = Color(215, 255, 180)
local MAT_GLOW = Material("sprites/light_glow02_add")
local MAT_RING = Material("effects/select_ring")
local MAT_BEAM = Material("trails/electric")
local MAT_SHELL = CreateMaterial("broly_dome_shell", "UnlitGeneric", {
	["$basetexture"] = "models/effects/comball_tape",
	["$additive"] = 1,
	["$vertexcolor"] = 1,
	["$vertexalpha"] = 1,
	["$nocull"] = 1,
	["Proxies"] = {["TextureScroll"] = {
		["texturescrollvar"] = "$basetexturetransform", ["texturescrollrate"] = 1.6, ["texturescrollangle"] = 60
	}},
})

function EFFECT:Init(data)
	self.Pos = data:GetOrigin()
	self.Radius = math.max(data:GetScale(), 60)
	self.Power = data:GetMagnitude() > 0 and data:GetMagnitude() or 1
	self.Start = CurTime()
	self.Life = 0.9 + 0.3 * self.Power
	self.Arcs = {}
	local r = self.Radius * 1.3
	self:SetRenderBoundsWS(self.Pos - Vector(r, r, r), self.Pos + Vector(r, r, r))

	local emitter = ParticleEmitter(self.Pos)
	if emitter then
		-- rocks hurled into the sky
		for i = 1, math.Round(40 * self.Power) do
			local part = emitter:Add("effects/fleck_cement" .. math.random(2), self.Pos + VectorRand() * Vector(40, 40, 0))
			if part then
				local out = VectorRand() * Vector(1, 1, 0)
				out:Normalize()
				part:SetVelocity(out * math.Rand(200, 700) * self.Power + Vector(0, 0, math.Rand(400, 1100) * self.Power))
				part:SetDieTime(math.Rand(1.5, 2.5))
				part:SetStartAlpha(255)
				part:SetEndAlpha(255)
				part:SetStartSize(math.Rand(3, 10))
				part:SetEndSize(math.Rand(1, 3))
				part:SetRoll(math.Rand(0, 360))
				part:SetRollDelta(math.Rand(-8, 8))
				part:SetGravity(Vector(0, 0, -900))
				part:SetCollide(true)
				part:SetBounce(0.25)
			end
		end
		-- dust column rushing up the middle
		for i = 1, math.Round(14 * self.Power) do
			local part = emitter:Add("particle/particle_smokegrenade", self.Pos + VectorRand() * Vector(30, 30, 0))
			if part then
				part:SetVelocity(Vector(math.Rand(-80, 80), math.Rand(-80, 80), math.Rand(300, 700) * self.Power))
				part:SetDieTime(math.Rand(1.2, 2))
				part:SetStartAlpha(110)
				part:SetEndAlpha(0)
				part:SetStartSize(30 * self.Power)
				part:SetEndSize(math.Rand(110, 170) * self.Power)
				part:SetRoll(math.Rand(0, 360))
				part:SetRollDelta(math.Rand(-0.5, 0.5))
				part:SetColor(170, 165, 150)
				part:SetAirResistance(90)
			end
		end
		-- ki shards flying off the dome
		for i = 1, math.Round(30 * self.Power) do
			local part = emitter:Add("effects/spark", self.Pos + Vector(0, 0, 30))
			if part then
				local dir = VectorRand()
				dir.z = math.abs(dir.z)
				part:SetVelocity(dir:GetNormalized() * math.Rand(800, 1600) * self.Power)
				part:SetDieTime(math.Rand(0.2, 0.45))
				part:SetStartAlpha(255)
				part:SetEndAlpha(0)
				part:SetStartSize(math.Rand(5, 9))
				part:SetEndSize(0)
				part:SetStartLength(math.Rand(80, 180))
				part:SetEndLength(10)
				part:SetColor(KI_HOT.r, KI_HOT.g, KI_HOT.b)
			end
		end
		emitter:Finish()
	end

	local dl = DynamicLight(math.random(30001, 40000))
	if dl then
		dl.pos = self.Pos + Vector(0, 0, 60)
		dl.r, dl.g, dl.b = KI.r, KI.g, KI.b
		dl.brightness = 8 * self.Power
		dl.decay = 1200
		dl.size = self.Radius * 3
		dl.dietime = CurTime() + self.Life
	end

	-- scorched crater
	util.Decal("Scorch", self.Pos + Vector(0, 0, 10), self.Pos - Vector(0, 0, 30))
	for i = 1, math.Round(5 * self.Power) do
		local off = VectorRand() * Vector(self.Radius * 0.5, self.Radius * 0.5, 0)
		util.Decal("Scorch", self.Pos + off + Vector(0, 0, 10), self.Pos + off - Vector(0, 0, 40))
	end
end

-- radius over time: violent burst that overshoots, then wobbles while it fades
function EFFECT:CurRadius(t)
	local u = math.Clamp(t / 0.28, 0, 1)
	local burst = 1 + 2.4 * (u - 1) ^ 3 + 1.4 * (u - 1) ^ 2 -- ease-out-back
	local wobble = 1 + 0.05 * math.sin(t * 70) * (1 - t / self.Life)
	return self.Radius * burst * wobble
end

function EFFECT:RandomSurfacePoint(r)
	local d = VectorRand()
	d.z = math.abs(d.z) * 0.9 + 0.1
	d:Normalize()
	return self.Pos + d * r
end

function EFFECT:Think()
	local t = CurTime() - self.Start
	if t > self.Life then return false end
	-- refresh lightning crawling over the dome
	for i = #self.Arcs, 1, -1 do
		if self.Arcs[i].die < CurTime() then table.remove(self.Arcs, i) end
	end
	local r = self:CurRadius(t)
	while #self.Arcs < math.Round(6 * self.Power * (1 - t / self.Life)) + 1 do
		local a, b = self:RandomSurfacePoint(r), self:RandomSurfacePoint(r)
		local pts = {}
		for k = 0, 7 do
			local p = LerpVector(k / 7, a, b)
			p = self.Pos + (p - self.Pos):GetNormalized() * r * math.Rand(0.97, 1.05) -- hug the surface
			pts[#pts + 1] = p + VectorRand() * 6
		end
		self.Arcs[#self.Arcs + 1] = {pts = pts, die = CurTime() + math.Rand(0.04, 0.1), w = math.Rand(4, 10)}
	end
	return true
end

function EFFECT:Render()
	local t = CurTime() - self.Start
	local fade = math.Clamp(1 - t / self.Life, 0, 1)
	local r = self:CurRadius(t)
	local flick = math.Rand(0.85, 1)

	-- solid-ish shell (outside and inside)
	render.SetColorMaterial()
	render.DrawSphere(self.Pos, r, 40, 40, Color(KI.r, KI.g, KI.b, 55 * fade * flick))
	render.DrawSphere(self.Pos, -r, 40, 40, Color(KI.r, KI.g, KI.b, 40 * fade * flick))
	-- swirling energy layer
	if not MAT_SHELL:IsError() then
		render.SetMaterial(MAT_SHELL)
		render.DrawSphere(self.Pos, r * 1.02, 32, 32, Color(KI.r, KI.g, KI.b, 255 * fade))
	end
	-- lattice
	render.DrawWireframeSphere(self.Pos, r * 1.01, 18, 18, Color(KI_HOT.r, KI_HOT.g, KI_HOT.b, 160 * fade), true)

	-- blinding core + ground rings
	render.SetMaterial(MAT_GLOW)
	local core = (1 - math.Clamp(t / 0.4, 0, 1))
	render.DrawSprite(self.Pos + Vector(0, 0, 40), r * 2.4 * core, r * 2.4 * core, Color(255, 255, 255, 255 * core))
	render.DrawSprite(self.Pos + Vector(0, 0, 40), r * 3 * fade, r * 1.6 * fade, Color(KI.r, KI.g, KI.b, 200 * fade))
	render.SetMaterial(MAT_RING)
	local up = Vector(0, 0, 1)
	render.DrawQuadEasy(self.Pos + Vector(0, 0, 3), up, r * 2.3, r * 2.3, Color(KI.r, KI.g, KI.b, 255 * fade), t * 120)
	local outer = self.Radius * 2 * (0.5 + 2 * math.Clamp(t / self.Life, 0, 1))
	render.DrawQuadEasy(self.Pos + Vector(0, 0, 2), up, outer, outer, Color(255, 255, 255, 120 * fade), -t * 60)

	-- lightning
	render.SetMaterial(MAT_BEAM)
	for _, arc in ipairs(self.Arcs) do
		render.StartBeam(#arc.pts)
		for i, p in ipairs(arc.pts) do render.AddBeam(p, arc.w, i / #arc.pts, KI_HOT) end
		render.EndBeam()
	end
end
