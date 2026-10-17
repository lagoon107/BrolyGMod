if not DrGBase then return end
ENT.Base = "proj_drg_default"

-- Eraser Cannon: Broly's signature ki ball. It charges in his palm (following his hand, growing),
-- then is thrown, homes in gently on the target and detonates in a giant energy dome.
ENT.PrintName = "Eraser Cannon"
ENT.Category = "Dragon Ball"
ENT.Models = {"models/hunter/misc/sphere025x025.mdl"}
ENT.Gravity = false
ENT.OnContactDelete = -1

ENT.ChargeTime = 1.1
ENT.Speed = 1100
ENT.Homing = 1.6          -- how hard it steers toward the target (per second)
ENT.Lifetime = 6
ENT.BlastRadius = 520
ENT.BlastDamage = 1500
ENT.BlastLaunch = 800

local KI = Color(140, 255, 90)
local KI_HOT = Color(215, 255, 180)

function ENT:SetupDataTables()
	self:NetworkVar("Float", 0, "Charge")
	self:NetworkVar("Bool", 0, "Launched")
end

if SERVER then
	AddCSLuaFile()

	function ENT:CustomInitialize()
		self:DrawShadow(false)
		self:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE) -- touches nothing while charging
		self:SetCharge(0)
		self._chargeStart = CurTime()
		self:Timer(0, function(self)
			local phys = self:GetPhysicsObject()
			if IsValid(phys) then phys:EnableMotion(false) end
		end)
	end

	function ENT:Launch(dir, target)
		if self:GetLaunched() then return end
		self:SetLaunched(true)
		self:SetCharge(1)
		self.Target = target
		self:SetCollisionGroup(COLLISION_GROUP_PROJECTILE)
		local phys = self:GetPhysicsObject()
		if IsValid(phys) then
			phys:EnableMotion(true)
			phys:Wake()
			phys:SetVelocity(dir:GetNormalized() * self.Speed)
		end
		util.SpriteTrail(self, 0, KI, true, 90, 0, 0.35, 1 / 90 * 0.5, "trails/laser")
		self:Timer(self.Lifetime, self.Explode)
	end

	function ENT:CustomThink()
		local owner = self:GetOwner()
		if not self:GetLaunched() then
			if not IsValid(owner) then self:Remove() return end
			-- ride in Broly's palm while it grows
			local hand = owner.BrolyHandPos and owner:BrolyHandPos("ValveBiped.Bip01_R_Hand") or owner:WorldSpaceCenter()
			self:SetPos(hand + owner:GetForward() * 14 + Vector(0, 0, 6))
			self:SetCharge(math.Clamp((CurTime() - self._chargeStart) / self.ChargeTime, 0, 1))
			return 0
		end
		-- gentle homing
		local target = self.Target
		local phys = self:GetPhysicsObject()
		if IsValid(target) and IsValid(phys) then
			local vel = phys:GetVelocity():GetNormalized()
			local want = (target:WorldSpaceCenter() - self:GetPos()):GetNormalized()
			local dir = LerpVector(math.Clamp(self.Homing * FrameTime(), 0, 1), vel, want):GetNormalized()
			phys:SetVelocity(dir * self.Speed)
		end
		return 0
	end

	function ENT:OnContact(ent)
		if not self:GetLaunched() then return false end
		local owner = self:GetOwner()
		if ent == owner or ent.IsBrolyBoss or ent.IsDrGProjectile then return false end
		self:Explode()
	end

	function ENT:Explode()
		if self._exploded then return end
		self._exploded = true
		local pos = self:GetPos()
		local owner = self:GetOwner()
		local fx = EffectData()
		fx:SetOrigin(pos)
		fx:SetNormal(self:GetVelocity():GetNormalized())
		fx:SetScale(4)
		util.Effect("broly_impact", fx, true, true)
		if IsValid(owner) and owner.BrolyShockwave then
			owner:BrolyShockwave(pos, {
				radius = self.BlastRadius, damage = self.BlastDamage, launch = self.BlastLaunch,
				power = 1.4, dome = self.BlastRadius * 1.1, hitAir = true
			})
			owner:EmitSound("Broly.Blast")
		else
			util.BlastDamage(self, self, pos, self.BlastRadius, self.BlastDamage)
		end
		self:Remove()
	end

else

	local MAT_GLOW = Material("sprites/light_glow02_add")
	local MAT_BEAM = Material("trails/electric")

	function ENT:CustomInitialize()
		self.Emitter = ParticleEmitter(self:GetPos())
		self.NextPart = 0
		self.Arcs = {}
	end

	function ENT:OnRemove()
		if self.Emitter then self.Emitter:Finish() end
	end

	function ENT:OrbRadius()
		return 6 + 34 * self:GetCharge()
	end

	function ENT:Think()
		local pos = self:GetPos()
		local r = self:OrbRadius()
		local em = self.Emitter
		if em and CurTime() > self.NextPart then
			self.NextPart = CurTime() + 0.02
			em:SetPos(pos)
			if not self:GetLaunched() then
				-- energy being sucked into the ball
				local from = pos + VectorRand():GetNormalized() * math.Rand(70, 130)
				local p = em:Add("sprites/light_glow02_add", from)
				if p then
					p:SetVelocity((pos - from) * 3)
					p:SetDieTime(0.3)
					p:SetStartAlpha(0)
					p:SetEndAlpha(255)
					p:SetStartSize(math.Rand(8, 14))
					p:SetEndSize(2)
					p:SetColor(KI.r, KI.g, KI.b)
				end
			else
				local p = em:Add("sprites/light_glow02_add", pos + VectorRand() * r * 0.6)
				if p then
					p:SetVelocity(VectorRand() * 40)
					p:SetDieTime(math.Rand(0.3, 0.6))
					p:SetStartAlpha(200)
					p:SetEndAlpha(0)
					p:SetStartSize(r * math.Rand(0.8, 1.4))
					p:SetEndSize(0)
					p:SetColor(KI.r, KI.g, KI.b)
				end
			end
		end
		for i = #self.Arcs, 1, -1 do
			if self.Arcs[i].die < CurTime() then table.remove(self.Arcs, i) end
		end
		if math.random() < 0.5 then
			local a = pos + VectorRand():GetNormalized() * r
			local b = pos + VectorRand():GetNormalized() * r * math.Rand(1.6, 2.6)
			local pts = {}
			for k = 0, 4 do pts[#pts + 1] = LerpVector(k / 4, a, b) + VectorRand() * r * 0.15 end
			self.Arcs[#self.Arcs + 1] = {pts = pts, die = CurTime() + 0.06}
		end
		local dl = DynamicLight(self:EntIndex())
		if dl then
			dl.pos = pos
			dl.r, dl.g, dl.b = KI.r, KI.g, KI.b
			dl.brightness = 2 + 3 * self:GetCharge()
			dl.decay = 1500
			dl.size = 150 + 400 * self:GetCharge()
			dl.dietime = CurTime() + 0.1
		end
	end

	function ENT:Draw()
		local pos = self:GetPos()
		local r = self:OrbRadius()
		local pulse = 1 + 0.08 * math.sin(CurTime() * 30)
		render.SetMaterial(MAT_GLOW)
		render.DrawSprite(pos, r * 7 * pulse, r * 7 * pulse, Color(KI.r, KI.g, KI.b, 120))
		render.DrawSprite(pos, r * 3.2, r * 3.2, KI)
		render.SetColorMaterial()
		render.DrawSphere(pos, r * pulse, 24, 24, Color(KI.r, KI.g, KI.b, 170))
		render.DrawSphere(pos, r * 0.6, 16, 16, Color(255, 255, 255, 230))
		render.SetMaterial(MAT_BEAM)
		for _, arc in ipairs(self.Arcs) do
			render.StartBeam(#arc.pts)
			for i, p in ipairs(arc.pts) do render.AddBeam(p, 3 + r * 0.08, i / #arc.pts, KI_HOT) end
			render.EndBeam()
		end
	end

end
