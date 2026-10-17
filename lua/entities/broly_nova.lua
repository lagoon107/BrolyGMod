-- Broly's crowd-control nova: a dome of violent energy centered on him that doubles in size every
-- Interval seconds, mauling and shoving everything inside, then detonates at full size.
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Broly Nova"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT

ENT.BaseRadius = 90
ENT.Doublings = 4         -- 90 -> 180 -> 360 -> 720 -> 1440
ENT.Interval = 0.35
ENT.HurtDamage = 150      -- every 0.2 s to everything inside
ENT.ExplodeDamage = 1500

local KI = Color(140, 255, 90)
local KI_HOT = Color(215, 255, 180)

function ENT:SetupDataTables()
	self:NetworkVar("Float", 0, "Radius")
end

function ENT:MaxRadius()
	return self.BaseRadius * 2 ^ self.Doublings
end

if SERVER then

	function ENT:Initialize()
		self:SetModel("models/hunter/misc/sphere025x025.mdl")
		self:SetSolid(SOLID_NONE)
		self:SetMoveType(MOVETYPE_NONE)
		self:DrawShadow(false)
		self:SetRadius(self.BaseRadius)
		self.Born = CurTime()
		self.Stage = 0
		self.NextHurt = 0
		util.ScreenShake(self:GetPos(), 15, 40, 0.5, 1500)
	end

	function ENT:Think()
		local owner = self:GetOwner()
		if IsValid(owner) then self:SetPos(owner:GetPos()) end
		local pos = self:GetPos()
		local t = CurTime() - self.Born

		local stage = math.min(self.Doublings, math.floor(t / self.Interval))
		if stage > self.Stage then
			self.Stage = stage
			self:SetRadius(self.BaseRadius * 2 ^ stage)
			util.ScreenShake(pos, 10 + 6 * stage, 50, 0.4, self:GetRadius() * 2.5)
			if BrolyFlash then BrolyFlash(pos, self:GetRadius() * 1.5, 0.15 + 0.05 * stage) end
			self:EmitSound("Broly.KiHit", 100 + stage * 5, 130 - stage * 12)
			self:EmitSound("Physics.ImpactHard", 95, 70 - stage * 5)
		end

		if CurTime() > self.NextHurt and IsValid(owner) and owner.BrolyCanHurt then
			self.NextHurt = CurTime() + 0.2
			for _, ent in ipairs(ents.FindInSphere(pos, self:GetRadius())) do
				if not owner:BrolyCanHurt(ent) then continue end
				local out = ent:WorldSpaceCenter() - pos
				out.z = 0
				out:Normalize()
				owner:BrolyDamage(ent, self.HurtDamage, DMG_SHOCK, out * 15000)
				owner:BrolyPush(ent, out * 450 + Vector(0, 0, 120))
			end
		end

		if t >= self.Interval * self.Doublings + 0.12 then
			if IsValid(owner) and owner.BrolyShockwave then
				local r = self:MaxRadius()
				owner:BrolyShockwave(pos, {radius = r, damage = self.ExplodeDamage, launch = 1400, power = 2,
					dome = r * 1.05, hitAir = true})
				owner:EmitSound("Broly.Blast")
				if BrolyHitStop then BrolyHitStop(0.3, 0.2) end
			end
			self:Remove()
			return
		end
		self:NextThink(CurTime())
		return true
	end

else

	local MAT_GLOW = Material("sprites/light_glow02_add")
	local MAT_RING = Material("effects/select_ring")
	local MAT_BEAM = Material("trails/electric")
	local MAT_SHELL = CreateMaterial("broly_nova_shell", "UnlitGeneric", {
		["$basetexture"] = "models/effects/comball_tape",
		["$additive"] = 1, ["$vertexcolor"] = 1, ["$vertexalpha"] = 1, ["$nocull"] = 1,
		["Proxies"] = {["TextureScroll"] = {
			["texturescrollvar"] = "$basetexturetransform", ["texturescrollrate"] = 3, ["texturescrollangle"] = 80
		}},
	})

	function ENT:Initialize()
		self.Arcs = {}
		self.ShownR = self:GetRadius()
		self.FromR, self.ToR, self.GrowStart = self.ShownR, self.ShownR, CurTime()
	end

	-- each doubling snaps outward with an overshoot
	function ENT:DisplayRadius()
		local target = self:GetRadius()
		if target ~= self.ToR then
			self.FromR, self.ToR, self.GrowStart = self.ShownR or target, target, CurTime()
		end
		local u = math.Clamp((CurTime() - self.GrowStart) / 0.16, 0, 1)
		local back = 1 + 2.7 * (u - 1) ^ 3 + 1.7 * (u - 1) ^ 2
		self.ShownR = self.FromR + (self.ToR - self.FromR) * back
		return self.ShownR * (1 + 0.03 * math.sin(CurTime() * 90))
	end

	function ENT:Think()
		local pos = self:GetPos()
		local r = self.ShownR or self:GetRadius()
		local b = self:GetRadius() * 1.4
		self:SetRenderBounds(Vector(-b, -b, -b), Vector(b, b, b))
		for i = #self.Arcs, 1, -1 do
			if self.Arcs[i].die < CurTime() then table.remove(self.Arcs, i) end
		end
		while #self.Arcs < 10 do
			local a, b = VectorRand(), VectorRand()
			a.z, b.z = math.abs(a.z), math.abs(b.z)
			local pts = {}
			for k = 0, 8 do
				local d = LerpVector(k / 8, a, b):GetNormalized()
				pts[#pts + 1] = pos + d * r * math.Rand(0.97, 1.04)
			end
			self.Arcs[#self.Arcs + 1] = {pts = pts, die = CurTime() + math.Rand(0.04, 0.09), w = math.Rand(6, 14)}
		end
		local dl = DynamicLight(self:EntIndex())
		if dl then
			dl.pos = pos + Vector(0, 0, 60)
			dl.r, dl.g, dl.b = KI.r, KI.g, KI.b
			dl.brightness = 6
			dl.decay = 2000
			dl.size = r * 2
			dl.dietime = CurTime() + 0.1
		end
	end

	function ENT:Draw() end

	function ENT:DrawTranslucent()
		local pos = self:GetPos()
		local r = self:DisplayRadius()
		local flick = math.Rand(0.8, 1)

		render.SetColorMaterial()
		render.DrawSphere(pos, r, 48, 48, Color(KI.r, KI.g, KI.b, 70 * flick))
		render.DrawSphere(pos, -r, 48, 48, Color(KI.r, KI.g, KI.b, 50 * flick))
		if not MAT_SHELL:IsError() then
			render.SetMaterial(MAT_SHELL)
			render.DrawSphere(pos, r * 1.015, 36, 36, Color(KI.r, KI.g, KI.b, 255))
		end
		render.DrawWireframeSphere(pos, r * 1.01, 20, 20, Color(KI_HOT.r, KI_HOT.g, KI_HOT.b, 170), true)

		render.SetMaterial(MAT_RING)
		render.DrawQuadEasy(pos + Vector(0, 0, 3), Vector(0, 0, 1), r * 2.2, r * 2.2, Color(KI.r, KI.g, KI.b, 230), CurTime() * 160)
		render.SetMaterial(MAT_GLOW)
		render.DrawSprite(pos + Vector(0, 0, 50), r * 1.2 * flick, r * 1.2 * flick, Color(255, 255, 255, 90))

		render.SetMaterial(MAT_BEAM)
		for _, arc in ipairs(self.Arcs) do
			render.StartBeam(#arc.pts)
			for i, p in ipairs(arc.pts) do render.AddBeam(p, arc.w, i / #arc.pts, KI_HOT) end
			render.EndBeam()
		end
	end

end
