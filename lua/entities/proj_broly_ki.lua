if not DrGBase then return end
ENT.Base = "proj_drg_default"

-- Small green ki blast fired by Broly's barrage. Owner = the Broly that fired it.
ENT.PrintName = "Broly Ki Blast"
ENT.Category = "Dragon Ball"
ENT.Models = {"models/hunter/misc/sphere025x025.mdl"}
ENT.ModelScale = 0.6
ENT.Gravity = false
ENT.OnContactDelete = 0

ENT.Damage = 150
ENT.BlastRadius = 90
ENT.Lifetime = 5

local KI = Color(140, 255, 90)

if SERVER then
	AddCSLuaFile()

	function ENT:CustomInitialize()
		self:SetCollisionGroup(COLLISION_GROUP_PROJECTILE)
		self:DrawShadow(false)
		util.SpriteTrail(self, 0, KI, true, 22, 0, 0.25, 1 / 22 * 0.5, "trails/laser")
		self:Timer(self.Lifetime, self.Remove)
	end

	function ENT:OnContact(ent)
		local owner = self:GetOwner()
		if ent == owner or ent:GetClass() == self:GetClass() or ent.IsBrolyBoss then return false end

		local dir = self:GetVelocity():GetNormalized()
		local fx = EffectData()
		fx:SetOrigin(self:GetPos())
		fx:SetNormal(dir)
		fx:SetScale(0.8)
		util.Effect("broly_impact", fx, true, true)
		util.ScreenShake(self:GetPos(), 4, 30, 0.25, 350)
		self:EmitSound("Broly.KiHit")

		if not ent:IsWorld() then self:DealDamage(ent, self.Damage, DMG_SHOCK) end
		self:RadiusDamage(self.Damage * 0.6, DMG_BLAST, self.BlastRadius, function(e)
			return e ~= owner and e ~= ent and not e.IsDrGProjectile and not e.IsBrolyBoss
		end)
	end

else

	local MAT_GLOW = Material("sprites/light_glow02_add")

	function ENT:Draw()
		local pos = self:GetPos()
		local flick = 1 + 0.15 * math.sin(CurTime() * 40 + self:EntIndex())
		render.SetMaterial(MAT_GLOW)
		render.DrawSprite(pos, 48 * flick, 48 * flick, KI)
		render.DrawSprite(pos, 18, 18, Color(255, 255, 255))
	end

	function ENT:Think()
		local dl = DynamicLight(self:EntIndex())
		if dl then
			dl.pos = self:GetPos()
			dl.r, dl.g, dl.b = KI.r, KI.g, KI.b
			dl.brightness = 1.5
			dl.decay = 1000
			dl.size = 160
			dl.dietime = CurTime() + 0.1
		end
	end

end
