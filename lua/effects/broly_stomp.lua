-- Heavy footstep: a burst of dust and pebbles at Broly's feet. Origin = foot position, Scale = strength.

function EFFECT:Init(data)
	local pos = data:GetOrigin()
	local p = math.max(data:GetScale(), 0.3)
	local emitter = ParticleEmitter(pos)
	if not emitter then return end
	for i = 1, math.Round(6 * p) do
		local part = emitter:Add("particle/particle_smokegrenade", pos + VectorRand() * Vector(8, 8, 0))
		if part then
			local dir = VectorRand() * Vector(1, 1, 0)
			dir:Normalize()
			part:SetVelocity(dir * math.Rand(60, 140) * p + Vector(0, 0, math.Rand(10, 40)))
			part:SetDieTime(math.Rand(0.5, 0.9))
			part:SetStartAlpha(70)
			part:SetEndAlpha(0)
			part:SetStartSize(6 * p)
			part:SetEndSize(math.Rand(22, 34) * p)
			part:SetRoll(math.Rand(0, 360))
			part:SetColor(180, 175, 160)
			part:SetAirResistance(150)
		end
	end
	for i = 1, math.Round(5 * p) do
		local part = emitter:Add("effects/fleck_cement" .. math.random(2), pos)
		if part then
			part:SetVelocity(VectorRand() * Vector(80, 80, 0) + Vector(0, 0, math.Rand(120, 220) * p))
			part:SetDieTime(math.Rand(0.6, 1))
			part:SetStartAlpha(255)
			part:SetEndAlpha(255)
			part:SetStartSize(math.Rand(1.5, 3))
			part:SetEndSize(0)
			part:SetGravity(Vector(0, 0, -800))
			part:SetCollide(true)
			part:SetBounce(0.3)
		end
	end
	emitter:Finish()
end

function EFFECT:Think() return false end
function EFFECT:Render() end
