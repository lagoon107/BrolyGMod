-- Broly punch impact: green ki flash, shockwave ring, sparks, dust and a light flash.
-- EffectData: Origin = hit position, Normal = punch direction, Scale = strength (1 jab, 2+ heavy)

local MAT_GLOW = Material("sprites/light_glow02_add")
local MAT_RING = Material("effects/select_ring")

local KI = Color(140, 255, 90)

function EFFECT:Init(data)
	self.Pos = data:GetOrigin()
	self.Dir = data:GetNormal()
	self.Power = math.max(data:GetScale(), 0.5)
	self.Start = CurTime()
	self.Life = 0.25 + 0.12 * self.Power
	self:SetRenderBoundsWS(self.Pos - Vector(1, 1, 1) * 200, self.Pos + Vector(1, 1, 1) * 200)

	local p = self.Power
	local emitter = ParticleEmitter(self.Pos)
	if emitter then
		-- sparks thrown forward along the punch
		for i = 1, math.Round(14 * p) do
			local part = emitter:Add("effects/spark", self.Pos)
			if part then
				local vel = (self.Dir + VectorRand() * 0.7):GetNormalized() * math.Rand(250, 550) * p
				part:SetVelocity(vel)
				part:SetDieTime(math.Rand(0.2, 0.45))
				part:SetStartAlpha(255)
				part:SetEndAlpha(0)
				part:SetStartSize(math.Rand(2, 4) * p)
				part:SetEndSize(0)
				part:SetStartLength(math.Rand(10, 25) * p)
				part:SetEndLength(0)
				part:SetColor(KI.r, KI.g, KI.b)
				part:SetGravity(Vector(0, 0, -400))
				part:SetAirResistance(80)
			end
		end
		-- glowing ki embers
		for i = 1, math.Round(8 * p) do
			local part = emitter:Add("sprites/light_glow02_add", self.Pos)
			if part then
				part:SetVelocity(VectorRand() * math.Rand(60, 160) * p)
				part:SetDieTime(math.Rand(0.25, 0.5))
				part:SetStartAlpha(220)
				part:SetEndAlpha(0)
				part:SetStartSize(math.Rand(6, 12) * p)
				part:SetEndSize(0)
				part:SetColor(KI.r, KI.g, KI.b)
				part:SetAirResistance(150)
			end
		end
		-- dust puff
		for i = 1, math.Round(6 * p) do
			local part = emitter:Add("particle/particle_smokegrenade", self.Pos)
			if part then
				part:SetVelocity(VectorRand() * math.Rand(40, 120) * p)
				part:SetDieTime(math.Rand(0.5, 0.9))
				part:SetStartAlpha(70)
				part:SetEndAlpha(0)
				part:SetStartSize(8 * p)
				part:SetEndSize(math.Rand(30, 45) * p)
				part:SetRoll(math.Rand(0, 360))
				part:SetRollDelta(math.Rand(-1, 1))
				part:SetColor(200, 200, 190)
				part:SetAirResistance(120)
			end
		end
		emitter:Finish()
	end

	local dl = DynamicLight(math.random(10000, 20000))
	if dl then
		dl.pos = self.Pos
		dl.r, dl.g, dl.b = KI.r, KI.g, KI.b
		dl.brightness = 3 * p
		dl.decay = 2000
		dl.size = 220 * p
		dl.dietime = CurTime() + 0.25
	end
end

function EFFECT:Think()
	return CurTime() - self.Start < self.Life
end

function EFFECT:Render()
	local t = math.Clamp((CurTime() - self.Start) / self.Life, 0, 1)
	local p = self.Power
	local fade = 1 - t

	-- core flash
	render.SetMaterial(MAT_GLOW)
	render.DrawSprite(self.Pos, (40 + 50 * t) * p, (40 + 50 * t) * p, Color(KI.r, KI.g, KI.b, 255 * fade))
	render.DrawSprite(self.Pos, 22 * p * fade, 22 * p * fade, Color(255, 255, 255, 255 * fade))

	-- shockwave ring facing back along the punch
	render.SetMaterial(MAT_RING)
	local size = (15 + 110 * math.sqrt(t)) * p
	render.DrawQuadEasy(self.Pos, -self.Dir, size, size, Color(KI.r, KI.g, KI.b, 230 * fade), CurTime() * 90)
end
