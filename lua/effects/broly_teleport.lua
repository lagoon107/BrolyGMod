-- Broly's teleport: a burst of green light, streaks shooting up, and (when Entity is set) a fading
-- green afterimage of him left where he vanished. Origin = position, Angles = his facing.

local KI = Color(140, 255, 90)
local MAT_GLOW = Material("sprites/light_glow02_add")

function EFFECT:Init(data)
	self.Pos = data:GetOrigin()
	self.Start = CurTime()
	self.Life = 0.5
	self:SetRenderBoundsWS(self.Pos - Vector(150, 150, 20), self.Pos + Vector(150, 150, 250))

	local ent = data:GetEntity()
	if IsValid(ent) then
		local ghost = ClientsideModel(ent:GetModel(), RENDERGROUP_TRANSLUCENT)
		if IsValid(ghost) then
			ghost:SetPos(self.Pos)
			ghost:SetAngles(data:GetAngles())
			ghost:SetSequence(ent:GetSequence())
			ghost:SetCycle(ent:GetCycle())
			ghost:SetMaterial("models/debug/debugwhite")
			ghost:SetRenderMode(RENDERMODE_TRANSCOLOR)
			ghost:SetColor(Color(KI.r, KI.g, KI.b, 200))
			self.Ghost = ghost
		end
	end

	local emitter = ParticleEmitter(self.Pos)
	if emitter then
		for i = 1, 24 do
			local part = emitter:Add("effects/spark", self.Pos + Vector(math.Rand(-30, 30), math.Rand(-30, 30), math.Rand(0, 100)))
			if part then
				part:SetVelocity(Vector(0, 0, math.Rand(500, 1100)))
				part:SetDieTime(math.Rand(0.15, 0.35))
				part:SetStartAlpha(255)
				part:SetEndAlpha(0)
				part:SetStartSize(math.Rand(3, 6))
				part:SetEndSize(0)
				part:SetStartLength(math.Rand(60, 140))
				part:SetEndLength(0)
				part:SetColor(KI.r, KI.g, KI.b)
			end
		end
		for i = 1, 12 do
			local part = emitter:Add("sprites/light_glow02_add", self.Pos + Vector(0, 0, math.Rand(10, 100)))
			if part then
				part:SetVelocity(VectorRand() * Vector(250, 250, 60))
				part:SetDieTime(math.Rand(0.25, 0.45))
				part:SetStartAlpha(220)
				part:SetEndAlpha(0)
				part:SetStartSize(math.Rand(15, 30))
				part:SetEndSize(0)
				part:SetColor(KI.r, KI.g, KI.b)
				part:SetAirResistance(200)
			end
		end
		emitter:Finish()
	end

	local dl = DynamicLight(math.random(40001, 50000))
	if dl then
		dl.pos = self.Pos + Vector(0, 0, 50)
		dl.r, dl.g, dl.b = KI.r, KI.g, KI.b
		dl.brightness = 5
		dl.decay = 1500
		dl.size = 400
		dl.dietime = CurTime() + 0.3
	end
end

function EFFECT:Think()
	local t = (CurTime() - self.Start) / self.Life
	if IsValid(self.Ghost) then
		self.Ghost:SetColor(Color(KI.r, KI.g, KI.b, 200 * (1 - t)))
		self.Ghost:SetModelScale(1 + 0.15 * t, 0)
	end
	if t >= 1 then
		if IsValid(self.Ghost) then self.Ghost:Remove() end
		return false
	end
	return true
end

function EFFECT:Render()
	local t = math.Clamp((CurTime() - self.Start) / self.Life, 0, 1)
	render.SetMaterial(MAT_GLOW)
	local s = 260 * (1 - t)
	render.DrawSprite(self.Pos + Vector(0, 0, 50), s, s * 1.6, Color(KI.r, KI.g, KI.b, 255 * (1 - t)))
	render.DrawSprite(self.Pos + Vector(0, 0, 50), s * 0.4, s * 0.8, Color(255, 255, 255, 255 * (1 - t)))
end
