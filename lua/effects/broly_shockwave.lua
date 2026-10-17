-- Ground slam shockwave: expanding green ground ring, dust wall, flying debris, flash.
-- EffectData: Origin = ground point, Scale = radius (units), Magnitude = 1 normal / <1 small (leap landing)

local MAT_RING = Material("effects/select_ring")
local MAT_GLOW = Material("sprites/light_glow02_add")
local KI = Color(140, 255, 90)

function EFFECT:Init(data)
	self.Pos = data:GetOrigin() + Vector(0, 0, 2)
	self.Radius = math.max(data:GetScale(), 50)
	self.Power = data:GetMagnitude() > 0 and data:GetMagnitude() or 1
	self.Start = CurTime()
	self.Life = 0.6
	local r = self.Radius
	self:SetRenderBoundsWS(self.Pos - Vector(r, r, 50), self.Pos + Vector(r, r, 200))

	local emitter = ParticleEmitter(self.Pos)
	if emitter then
		-- dust wall rolling outward
		local count = math.Round(36 * self.Power)
		for i = 1, count do
			local a = (i / count) * math.pi * 2
			local dir = Vector(math.cos(a), math.sin(a), 0)
			local part = emitter:Add("particle/particle_smokegrenade", self.Pos + dir * 20)
			if part then
				part:SetVelocity(dir * math.Rand(0.9, 1.2) * r * 1.6 + Vector(0, 0, math.Rand(10, 60)))
				part:SetDieTime(math.Rand(0.9, 1.5))
				part:SetStartAlpha(120)
				part:SetEndAlpha(0)
				part:SetStartSize(25 * self.Power)
				part:SetEndSize(math.Rand(70, 110) * self.Power)
				part:SetRoll(math.Rand(0, 360))
				part:SetRollDelta(math.Rand(-1, 1))
				part:SetColor(185, 180, 165)
				part:SetAirResistance(140)
			end
		end
		-- debris chunks
		for i = 1, math.Round(25 * self.Power) do
			local part = emitter:Add("effects/fleck_cement" .. math.random(2), self.Pos)
			if part then
				part:SetVelocity(VectorRand():GetNormalized() * Vector(1, 1, 0) * math.Rand(150, 450) + Vector(0, 0, math.Rand(250, 600) * self.Power))
				part:SetDieTime(math.Rand(1, 1.8))
				part:SetStartAlpha(255)
				part:SetEndAlpha(255)
				part:SetStartSize(math.Rand(3, 7))
				part:SetEndSize(0)
				part:SetRoll(math.Rand(0, 360))
				part:SetRollDelta(math.Rand(-6, 6))
				part:SetGravity(Vector(0, 0, -800))
				part:SetCollide(true)
				part:SetBounce(0.3)
			end
		end
		-- ki embers burst
		for i = 1, math.Round(20 * self.Power) do
			local part = emitter:Add("sprites/light_glow02_add", self.Pos)
			if part then
				part:SetVelocity(VectorRand() * Vector(1, 1, 0.5) * math.Rand(150, 400))
				part:SetDieTime(math.Rand(0.4, 0.8))
				part:SetStartAlpha(230)
				part:SetEndAlpha(0)
				part:SetStartSize(math.Rand(10, 20))
				part:SetEndSize(0)
				part:SetColor(KI.r, KI.g, KI.b)
				part:SetAirResistance(100)
			end
		end
		emitter:Finish()
	end

	local dl = DynamicLight(math.random(20001, 30000))
	if dl then
		dl.pos = self.Pos + Vector(0, 0, 40)
		dl.r, dl.g, dl.b = KI.r, KI.g, KI.b
		dl.brightness = 5 * self.Power
		dl.decay = 1500
		dl.size = r * 1.5
		dl.dietime = CurTime() + 0.4
	end

	util.Decal("Scorch", self.Pos + Vector(0, 0, 10), self.Pos - Vector(0, 0, 30))
end

function EFFECT:Think()
	return CurTime() - self.Start < self.Life
end

function EFFECT:Render()
	local t = math.Clamp((CurTime() - self.Start) / self.Life, 0, 1)
	local fade = 1 - t
	local up = Vector(0, 0, 1)

	render.SetMaterial(MAT_RING)
	local size = self.Radius * 2 * math.sqrt(t)
	render.DrawQuadEasy(self.Pos, up, size, size, Color(KI.r, KI.g, KI.b, 255 * fade), 0)
	render.DrawQuadEasy(self.Pos, up, size * 0.7, size * 0.7, Color(255, 255, 255, 160 * fade), 45)

	render.SetMaterial(MAT_GLOW)
	local g = (80 + 160 * t) * self.Power
	render.DrawSprite(self.Pos + Vector(0, 0, 20), g, g * 0.6, Color(KI.r, KI.g, KI.b, 255 * fade))
end
