if not DrGBase then return end -- requires DrGBase (workshop 1560118657)
ENT.Base = "drgbase_nextbot"

-- Misc --
ENT.PrintName = "Broly"
ENT.Category = "Dragon Ball"
ENT.Models = {"models/broly/broly.mdl"}
ENT.CollisionBounds = Vector(16, 16, 96)
ENT.BloodColor = BLOOD_COLOR_RED
ENT.RagdollOnDeath = true

-- Boss bar (lua/autorun/client/broly_bossbar.lua) --
ENT.IsBrolyBoss = true
ENT.BossName = "Broly, the Legendary Super Saiyan"

-- Stats: a force of nature --
ENT.SpawnHealth = 40000
ENT.MinPhysDamage = 99999
ENT.MinFallDamage = 99999
ENT.DamageResist = 0.35       -- bullets, melee, everything that isn't explosive
ENT.BlastResist = 1           -- explosives hurt him the most

-- AI --
ENT.RangeAttackRange = 3000   -- abilities are picked from OnRangeAttack/OnChaseEnemy
ENT.MeleeAttackRange = 80
ENT.ReachEnemyRange = 60
ENT.AvoidEnemyRange = 0
ENT.SpotDuration = 600        -- once he's seen you, he doesn't forget

-- Relationships --
ENT.DefaultRelationship = D_HT
ENT.Factions = {"FACTION_BROLY"}

-- Detection --
ENT.EyeBone = "ValveBiped.Bip01_Head1"
ENT.EyeOffset = Vector(6, 0, 3)

-- Locomotion / movement --
ENT.MaxYawRate = 360
ENT.Acceleration = 2000
ENT.Deceleration = 2000
ENT.UseWalkframes = false
ENT.WalkSpeed = 140
ENT.RunSpeed = 380

-- Animations (ValveBiped player animations, via the proportions trick in the model) --
ENT.IdleAnimation = ACT_HL2MP_IDLE_FIST
ENT.WalkAnimation = ACT_HL2MP_WALK_FIST
ENT.RunAnimation = ACT_HL2MP_RUN_FIST
ENT.RunAnimRate = 1.35
ENT.JumpAnimation = ACT_HL2MP_JUMP_FIST

-- Sounds (lua/autorun/broly_sounds.lua) --
ENT.OnDamageSounds = {}
ENT.OnDeathSounds = {"Broly.DeathRoar"}

-- Melee attacks --
-- Each attack: a sequence, its playback rate, when (cycle) the hit lands, and the hit itself.
-- hand = bone the impact VFX spawns from; impact = VFX scale; shake = {amplitude, frequency, duration, radius}
ENT.BrolyAttacks = {
	jab_left = {
		seq = "range_fists_l", gesture = true, rate = 1, hit = 0.25,
		damage = 500, range = 90, angle = 70, force = Vector(500, 0, 100), recover = 0.3,
		hand = "ValveBiped.Bip01_L_Hand", impact = 1, shake = {6, 40, 0.3, 500}
	},
	jab_right = {
		seq = "range_fists_r", gesture = true, rate = 1, hit = 0.25,
		damage = 500, range = 90, angle = 70, force = Vector(500, 0, 100), recover = 0.3,
		hand = "ValveBiped.Bip01_R_Hand", impact = 1, shake = {6, 40, 0.3, 500}
	},
	heavy = {
		seq = "seq_meleeattack01", rate = 0.8, hit = 0.45,
		damage = 900, range = 110, angle = 90, force = Vector(800, 0, 300), recover = 0.2,
		hand = "ValveBiped.Bip01_R_Hand", impact = 2.2, shake = {20, 60, 0.8, 900}
	}
}

-- Abilities --
-- cooldown (s), distance window to the enemy, weight for the random pick
ENT.BrolyAbilities = {
	leap    = {fn = "AbilityLeap",    cooldown = 3.5, min = 1100, max = 4500, weight = 6, noSight = true},
	slam    = {fn = "AbilitySlam",    cooldown = 8,   min = 250,  max = 900,  weight = 4},
	barrage = {fn = "AbilityBarrage", cooldown = 11,  min = 500,  max = 2800, weight = 3},
	eraser  = {fn = "AbilityEraser",  cooldown = 14,  min = 450,  max = 3500, weight = 4},
	mouthblast = {fn = "AbilityMouthBlast", cooldown = 16, min = 350, max = 3000, weight = 3},
	nova    = {fn = "AbilityNova",    cooldown = 20,  min = 0,    max = 700,  weight = 6, cond = "BrolyCrowded"},
	ambush  = {fn = "AbilityAmbush",  cooldown = 10,  weight = 7, cond = "BrolyAmbushTarget", noSight = true},
	grab    = {fn = "AbilityGrab",    cooldown = 12,  min = 0,    max = 110,  weight = 0}, -- picked from melee, see OnMeleeAttack
}
ENT.GrabChance = 0.4
ENT.AbilityGap = 1.0 -- minimum seconds between any two abilities

if SERVER then

	function ENT:CustomInitialize()
		self:SetDefaultRelationship(D_HT)
		self._brolyCombo = 0
		self._brolyCooldowns = {}
		self._brolyNextAbility = 0
		self._brolyPowerUntil = 0
		self._brolyNextStep = 0
		self._brolyStepFoot = false
		self._brolyAttackers = {}
		self:CallOnRemove("BrolyReleaseGrab", function(self) self:BrolyGrabRelease(false) end)
		-- announce himself
		self:Timer(0.3, function(self)
			self:EmitSound("Broly.Scream")
			self:BrolyPowerFor(5)
		end)
	end

	-- Aura flares up (client effects read NW2Bool "BrolyPowered") for the given time.
	function ENT:BrolyPowerFor(seconds)
		self._brolyPowerUntil = math.max(self._brolyPowerUntil, CurTime() + seconds)
	end

	function ENT:CustomThink()
		self:BrolyGrabUpdate()
		local powered = CurTime() < self._brolyPowerUntil
		if self:GetNW2Bool("BrolyPowered") ~= powered then self:SetNW2Bool("BrolyPowered", powered) end
		self:BrolyFootsteps()
		return 0
	end

	-- Heavy, ground-shaking footsteps while running.
	function ENT:BrolyFootsteps()
		if CurTime() < self._brolyNextStep or not self:IsOnGround() then return end
		local speed = self:GetVelocity():Length2D()
		if speed < 150 then return end
		self._brolyNextStep = CurTime() + math.Clamp(110 / speed, 0.22, 0.5)
		self._brolyStepFoot = not self._brolyStepFoot
		local foot = self:BrolyHandPos(self._brolyStepFoot and "ValveBiped.Bip01_L_Foot" or "ValveBiped.Bip01_R_Foot")
		foot.z = self:GetPos().z + 2
		local fx = EffectData()
		fx:SetOrigin(foot)
		fx:SetScale(speed > 300 and 1 or 0.6)
		util.Effect("broly_stomp", fx, true, true)
		util.ScreenShake(foot, 3, 25, 0.25, 700)
		self:EmitSound("physics/concrete/concrete_impact_hard" .. math.random(1, 3) .. ".wav", 75, math.random(55, 70), 0.7)
	end

	-- Plays one of the model's custom upper-body gestures. Returns its duration.
	function ENT:BrolyGesture(name, rate)
		local seq = self:LookupSequence(name)
		if seq < 0 then return 0 end
		rate = rate or 1
		local layer = self:AddGestureSequence(seq, true)
		self:SetLayerPlaybackRate(layer, rate)
		self:SetLayerBlendIn(layer, 0.08)
		self:SetLayerBlendOut(layer, 0.15)
		return self:SequenceDuration(seq) / rate
	end

	function ENT:OnNewEnemy()
		self:SetOmniscient(true) -- always knows where you are once the fight starts
	end

	-- Damage resistance: small arms barely scratch him, explosives are the way.
	function ENT:OnTakeDamage(dmg)
		local attacker = dmg:GetAttacker()
		self:SpotEntity(attacker)
		if IsValid(attacker) and attacker ~= self and (attacker:IsNPC() or attacker:IsPlayer() or attacker:IsNextBot()) then
			self._brolyAttackers[attacker] = CurTime() -- remembered for the ambush
		end
		if dmg:IsDamageType(DMG_FALL) or dmg:IsDamageType(DMG_CRUSH) or dmg:IsDamageType(DMG_PHYSGUN) then return true end
		local inflictor = dmg:GetInflictor()
		if IsValid(inflictor) and inflictor:GetClass():StartWith("prop_physics") then return true end
		if dmg:IsDamageType(DMG_BLAST) or dmg:IsDamageType(DMG_BLAST_SURFACE) then
			return dmg:GetDamage() * self.BlastResist
		end
		return dmg:GetDamage() * self.DamageResist
	end

	-- Coroutine-safe pause. DrGBase's Wait() returns immediately while an enemy exists.
	function ENT:BrolyPause(duration, face)
		local stop = CurTime() + duration
		while CurTime() < stop do
			if IsValid(face) then self:FaceTowards(face) end
			self:YieldCoroutine(false)
		end
	end

	function ENT:BrolyHandPos(hand)
		local bone = self:LookupBone(hand)
		return bone and self:GetBonePosition(bone) or self:WorldSpaceCenter()
	end

	-- Hit feedback: VFX where the fist meets the target, screen shake, and a heavier thud on big hits.
	function ENT:BrolyImpact(atk, ent)
		local fist = self:BrolyHandPos(atk.hand)
		local pos = ent:NearestPoint(fist)
		local dir = (pos - fist):GetNormalized()
		if dir:IsZero() then dir = self:GetForward() end

		local fx = EffectData()
		fx:SetOrigin(pos)
		fx:SetNormal(dir)
		fx:SetScale(atk.impact)
		util.Effect("broly_impact", fx, true, true)

		local s = atk.shake
		util.ScreenShake(pos, s[1], s[2], s[3], s[4])
		if atk.impact >= 2 then
			self:EmitSound("Physics.ImpactHard", 90, math.random(70, 80))
			util.ScreenShake(pos, s[1] * 0.5, 5, s[3] * 1.5, s[4]) -- low rumble under the sharp shake
		end
	end

	-- Plays one entry of ENT.BrolyAttacks. Runs inside DrGBase's AI coroutine.
	function ENT:BrolyAttack(name)
		local atk = self.BrolyAttacks[name]
		local hitDone = false
		if atk.impact >= 2 or math.random() < 0.35 then self:EmitSound("Broly.Grunt") end
		local function onCycle(self, cycle)
			if not hitDone and cycle >= atk.hit then
				hitDone = true
				self:Attack({
					damage = atk.damage, range = atk.range, angle = atk.angle,
					type = DMG_CLUB, force = atk.force, push = true,
					viewpunch = Angle(math.min(atk.damage * 0.5, 25), math.random(-10, 10), 0)
				}, function(self, hit)
					self:EmitSound(#hit > 0 and "Flesh.ImpactHard" or "WeaponFrag.Throw", 80, math.random(80, 95))
					for _, ent in ipairs(hit) do self:BrolyImpact(atk, ent) end
				end)
			end
		end

		if atk.gesture then
			-- upper-body punch layered over the fighting stance; keep turning toward the target
			local seq = self:LookupSequence(atk.seq)
			local dur = self:SequenceDuration(seq) / atk.rate
			local start = CurTime()
			self:PlaySequence(atk.seq, atk.rate)
			while CurTime() - start < dur * 0.6 do
				onCycle(self, (CurTime() - start) / dur)
				if self:HasEnemy() then self:FaceEnemy() end
				self:YieldCoroutine(false)
			end
		else
			self:PlaySequenceAndMove(atk.seq, atk.rate, function(self, cycle)
				if cycle < atk.hit and self:HasEnemy() then self:FaceEnemy() end
				onCycle(self, cycle)
			end)
		end
		self:BrolyPause(atk.recover)
	end

	------------------------------------------------------------------ ability selection

	function ENT:BrolyAbilityReady(name)
		return CurTime() >= (self._brolyCooldowns[name] or 0)
	end

	local DebugCvar = CreateConVar("broly_debug", "0", FCVAR_ARCHIVE, "Print Broly ability decisions to the console")
	function ENT:BrolyDebug(...)
		if DebugCvar:GetBool() then print("[Broly]", self, ...) end
	end

	function ENT:BrolyUseAbility(name, enemy)
		self:BrolyDebug("ability", name, "on", enemy, "dist", math.Round(self:GetPos():Distance(enemy:GetPos())))
		self._brolyCooldowns[name] = CurTime() + self.BrolyAbilities[name].cooldown
		self[self.BrolyAbilities[name].fn](self, enemy)
		self._brolyNextAbility = CurTime() + self.AbilityGap
		return true
	end

	-- Picks a ready ability whose distance window fits; returns true if one was used.
	function ENT:BrolyTryAbility(enemy)
		if not IsValid(enemy) then return false end
		if self._brolyForce then
			local name = self._brolyForce
			if name == "grab" and self:GetPos():Distance(enemy:GetPos()) > self.BrolyAbilities.grab.max then return false end
			self._brolyForce = nil
			return self:BrolyUseAbility(name, enemy)
		end
		if CurTime() < self._brolyNextAbility then return false end

		local dist = self:GetPos():Distance(enemy:GetPos())
		local above = enemy:GetPos().z - self:GetPos().z > 150
		local visible = self:Visible(enemy)
		local pool, total = {}, 0
		for name, ab in pairs(self.BrolyAbilities) do
			if ab.weight <= 0 or not self:BrolyAbilityReady(name) then continue end
			local inRange = (not ab.min or dist >= ab.min) and (not ab.max or dist <= ab.max)
			if name == "leap" and above and dist > 200 then inRange = true end
			if not ab.noSight and not visible then inRange = false end
			if inRange and ab.cond and not self[ab.cond](self, enemy) then inRange = false end
			if inRange then
				pool[#pool + 1] = name
				total = total + ab.weight
			end
		end
		if #pool == 0 then return false end
		local roll = math.Rand(0, total)
		for _, name in ipairs(pool) do
			roll = roll - self.BrolyAbilities[name].weight
			if roll <= 0 then return self:BrolyUseAbility(name, enemy) end
		end
		return self:BrolyUseAbility(pool[#pool], enemy)
	end

	function ENT:OnChaseEnemy(enemy)
		if self:BrolyTryAbility(enemy) then return true end
	end
	function ENT:OnRangeAttack(enemy)
		self:BrolyTryAbility(enemy)
	end
	function ENT:OnEnemyUnreachable(enemy)
		if self:BrolyAbilityReady("leap") then self:BrolyUseAbility("leap", enemy) end
	end

	function ENT:OnMeleeAttack(enemy)
		if self._brolyForce then return self:BrolyTryAbility(enemy) end
		if (enemy:IsPlayer() or enemy:IsNPC()) and self:BrolyAbilityReady("grab") and math.random() < self.GrabChance then
			return self:BrolyUseAbility("grab", enemy)
		end
		-- jab, jab, heavy
		self._brolyCombo = (self._brolyCombo % 3) + 1
		if self._brolyCombo == 1 then self:BrolyAttack("jab_left")
		elseif self._brolyCombo == 2 then self:BrolyAttack("jab_right")
		else self:BrolyAttack("heavy") end
	end

	function ENT:OnIdle()
		self:AddPatrolPos(self:RandomPos(1000))
	end

	------------------------------------------------------------------ shared ability helpers

	-- Damages and launches everything within radius.
	-- opts: radius, damage, launch, power (VFX/shake scale), dome (energy dome radius, optional),
	--       hitAir (also hits airborne targets; ground shockwaves can be jumped over)
	function ENT:BrolyShockwave(pos, opts)
		local radius, damage, launch, power = opts.radius, opts.damage, opts.launch, opts.power or 1
		local fx = EffectData()
		fx:SetOrigin(pos)
		fx:SetScale(radius)
		fx:SetMagnitude(power)
		util.Effect("broly_shockwave", fx, true, true)
		if opts.dome then
			local dome = EffectData()
			dome:SetOrigin(pos)
			dome:SetScale(opts.dome)
			dome:SetMagnitude(power)
			util.Effect("broly_dome", dome, true, true)
		end
		util.ScreenShake(pos, 25 * power, 50, 1.2 * power, radius * 3)
		util.ScreenShake(pos, 10 * power, 4, 2 * power, radius * 3) -- slow rolling aftershock
		BrolyFlash(pos, radius * 2.5, (opts.dome and 0.7 or 0.45) * power)
		self:EmitSound("Broly.Explosion", 100 + 25 * power)
		self:EmitSound("Physics.ImpactHard", 95, 60)

		for _, ent in ipairs(ents.FindInSphere(pos, radius)) do
			if ent == self or not IsValid(ent) or ent.IsDrGProjectile or ent.IsBrolyBoss then continue end
			local isChar = ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot()
			local phys = ent:GetPhysicsObject()
			if not isChar and not (IsValid(phys) and ent:GetMoveType() == MOVETYPE_VPHYSICS) then continue end
			if isChar and ((not opts.hitAir and not ent:IsOnGround()) or (ent:IsPlayer() and not ent:Alive())) then continue end

			local flat = ent:GetPos() - pos
			flat.z = 0
			local falloff = 1 - math.Clamp(flat:Length() / radius, 0, 1) * 0.6
			local dir = flat:GetNormalized()
			if dir:IsZero() then dir = self:GetForward() end

			local dmg = DamageInfo()
			dmg:SetDamage(damage * falloff)
			dmg:SetAttacker(self)
			dmg:SetInflictor(self)
			dmg:SetDamageType(DMG_CLUB)
			dmg:SetDamagePosition(pos)
			dmg:SetDamageForce((dir + Vector(0, 0, 0.7)) * launch * 50)
			ent:TakeDamageInfo(dmg)

			local vel = dir * launch * falloff + Vector(0, 0, launch * 0.7 * falloff)
			if ent:IsPlayer() then
				ent:SetVelocity(vel)
			elseif ent:IsNPC() then
				ent:SetVelocity(vel)
			elseif not isChar then
				phys:ApplyForceCenter((dir + Vector(0, 0, 0.8)) * phys:GetMass() * launch)
			end
		end
	end

	-- Ballistic jump at a point. Speed is picked so the arc can reach it. Returns true if he actually jumped.
	function ENT:BrolyLeapTo(pos, arc, face)
		local start = self:GetPos()
		local speed = math.max(700, math.sqrt(1000 * start:Distance(pos)) * arc)
		self:EmitSound("Broly.Grunt")
		util.ScreenShake(start, 8, 30, 0.4, 600)
		local fx = EffectData()
		fx:SetOrigin(start)
		fx:SetScale(1.6)
		util.Effect("broly_stomp", fx, true, true)
		self:Leap(pos, speed, function(self)
			if IsValid(face) then self:FaceTowards(face) end
		end)
		return self:GetPos():Distance(start) > 64
	end

	------------------------------------------------------------------ abilities

	-- Giant leap: closes huge distances in one jump and cracks the ground where he lands.
	function ENT:AbilityLeap(enemy)
		local away = (self:GetPos() - enemy:GetPos())
		away.z = 0
		local target = enemy:GetPos() + away:GetNormalized() * 90
		self:FaceTowards(enemy)
		self:PlaySequenceAndWait("jump_land", 1.4) -- quick crouch
		if not self:BrolyLeapTo(target, 1.1, enemy) then return end
		self:BrolyShockwave(self:GetPos(), {radius = 320, damage = 500, launch = 500, power = 0.8, dome = 260})
		self:BrolyPause(0.2)
	end

	-- Ground slam: big crouch windup, high leap onto the player, shockwave that launches anything grounded.
	function ENT:AbilitySlam(enemy)
		self:FaceTowards(enemy)
		self:BrolyPowerFor(3)
		self:EmitSound("Broly.KiCharge")
		self:PlaySequenceAndWait("jump_land", 0.5) -- slow, readable windup
		local target = enemy:GetPos() + enemy:GetVelocity() * 0.3
		if not self:BrolyLeapTo(target, 1.02, enemy) then return end
		self:BrolyShockwave(self:GetPos(), {radius = 480, damage = 900, launch = 800, power = 1.2, dome = 440})
		self:PlaySequenceAndWait("jump_land", 0.7) -- recovery crouch
	end

	-- Ki barrage: plants his feet and hoses the player with ki blasts from alternating hands.
	function ENT:BrolyFireKi(hand, enemy)
		local pos = self:BrolyHandPos(hand) + self:GetForward() * 40
		local ki = ents.Create("proj_broly_ki")
		if not IsValid(ki) then return end
		ki:SetOwner(self)
		ki:SetPos(pos)
		ki:Spawn()
		local dist = pos:Distance(enemy:WorldSpaceCenter())
		local aim = enemy:WorldSpaceCenter() + enemy:GetVelocity() * (dist / 1600) * 0.6 + VectorRand() * 25
		local phys = ki:GetPhysicsObject()
		if IsValid(phys) then phys:SetVelocity((aim - pos):GetNormalized() * 1600) end
		self:EmitSound("Broly.KiShot")
	end

	function ENT:AbilityBarrage(enemy)
		self:BrolyPowerFor(3.5)
		self:EmitSound("Broly.Yell")
		self:BrolyPause(0.25, enemy)
		for i = 1, 14 do
			if not IsValid(enemy) or (enemy:IsPlayer() and not enemy:Alive()) then break end
			local left = i % 2 == 0
			self:AddGestureSequence(self:LookupSequence(left and "range_fists_l" or "range_fists_r"), true)
			self:BrolyFireKi(left and "ValveBiped.Bip01_L_Hand" or "ValveBiped.Bip01_R_Hand", enemy)
			self:BrolyPause(0.12, enemy)
		end
		self:BrolyPause(0.5)
	end

	------------------------------------------------------------------ damage helpers

	-- Trace filter that only stops on the world and props (characters and projectiles are ignored).
	-- Note: MASK_SOLID_BRUSHONLY passes through gm_flatgrass's ground, so use MASK_SOLID with this.
	local function WorldOnly(e)
		return not (e:IsNPC() or e:IsPlayer() or e:IsNextBot() or e.IsDrGProjectile)
	end

	-- Anything Broly is allowed to hurt (never himself, other Brolys, or projectiles).
	function ENT:BrolyCanHurt(ent)
		if not IsValid(ent) or ent == self or ent.IsBrolyBoss or ent.IsDrGProjectile then return false end
		if ent:IsPlayer() then return ent:Alive() end
		if ent:IsNPC() or ent:IsNextBot() then return ent:Health() > 0 end
		local phys = ent:GetPhysicsObject()
		return IsValid(phys) and ent:GetMoveType() == MOVETYPE_VPHYSICS
	end

	function ENT:BrolyDamage(ent, amount, type, force, pos)
		local dmg = DamageInfo()
		dmg:SetDamage(amount)
		dmg:SetAttacker(self)
		dmg:SetInflictor(self)
		dmg:SetDamageType(type or DMG_CLUB)
		dmg:SetDamageForce(force or vector_origin)
		dmg:SetDamagePosition(pos or ent:WorldSpaceCenter())
		ent:TakeDamageInfo(dmg)
	end

	function ENT:BrolyPush(ent, vel)
		if ent:IsPlayer() or ent:IsNPC() then
			ent:SetVelocity(vel)
		elseif not ent:IsNextBot() then
			local phys = ent:GetPhysicsObject()
			if IsValid(phys) then phys:ApplyForceCenter(vel * phys:GetMass()) end
		end
	end

	-- Enemies (players/NPCs/nextbots he hates) within radius of him.
	function ENT:BrolyEnemiesNear(radius)
		local list = {}
		for _, ent in ipairs(ents.FindInSphere(self:GetPos(), radius)) do
			if (ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot()) and self:BrolyCanHurt(ent)
				and self:GetRelationship(ent) == D_HT then
				list[#list + 1] = ent
			end
		end
		return list
	end

	------------------------------------------------------------------ mouth blast

	-- Throws his head back, then unleashes a huge wave of ki from his mouth that sweeps toward
	-- the target, shredding everything along it and erupting where it hits.
	ENT.BeamStart, ENT.BeamEnd = 0.70, 2.30 -- broly_mouthblast firing window (tools/anim_broly.py)
	ENT.BeamRange = 3500
	ENT.BeamRadius = 80
	ENT.BeamDamage = 150    -- per 0.1 s to everything inside the beam
	ENT.BeamBlastDamage = 300
	ENT.BeamTurn = 1.4      -- how fast the beam sweeps toward the target

	function ENT:BrolyMouthPos()
		local att = self:GetAttachment(self:LookupAttachment("mouth"))
		if att then return att.Pos end
		return self:BrolyHandPos("ValveBiped.Bip01_Head1") + self:GetForward() * 8
	end

	function ENT:AbilityMouthBlast(enemy)
		self:BrolyPowerFor(3.2)
		self:EmitSound("Broly.KiCharge")
		self:BrolyGesture("broly_mouthblast")
		local start = CurTime()
		while CurTime() - start < self.BeamStart do
			if IsValid(enemy) then self:FaceTowards(enemy) end
			self:YieldCoroutine(false)
		end

		self:BrolyDebug("mouthblast: firing")
		self:EmitSound("Broly.Roar")
		self:EmitSound("Broly.Blast")
		local dir = IsValid(enemy) and (enemy:WorldSpaceCenter() - self:BrolyMouthPos()):GetNormalized() or self:GetForward()
		self:SetNW2Float("BrolyBeamUntil", start + self.BeamEnd)
		local nextTick, nextBoom = 0, 0
		while CurTime() - start < self.BeamEnd do
			if IsValid(enemy) then
				self:FaceTowards(enemy)
				local want = (enemy:WorldSpaceCenter() - self:BrolyMouthPos()):GetNormalized()
				dir = LerpVector(math.Clamp(self.BeamTurn * FrameTime(), 0, 1), dir, want):GetNormalized()
			end
			local mouth = self:BrolyMouthPos()
			local tr = util.TraceLine({start = mouth, endpos = mouth + dir * self.BeamRange, mask = MASK_SOLID, filter = WorldOnly})
			self:SetNW2Vector("BrolyBeamEnd", tr.HitPos)

			if CurTime() > nextTick then
				nextTick = CurTime() + 0.1
				local r = self.BeamRadius
				for _, ent in ipairs(ents.FindAlongRay(mouth, tr.HitPos, Vector(-r, -r, -r), Vector(r, r, r))) do
					if not self:BrolyCanHurt(ent) then continue end
					self:BrolyDamage(ent, self.BeamDamage, DMG_ENERGYBEAM + DMG_DISSOLVE, dir * 30000)
					self:BrolyPush(ent, dir * 300)
				end
			end
			if tr.Hit and CurTime() > nextBoom then
				nextBoom = CurTime() + 0.2
				local fx = EffectData()
				fx:SetOrigin(tr.HitPos)
				fx:SetNormal(dir)
				fx:SetScale(2.6)
				util.Effect("broly_impact", fx, true, true)
				util.Decal("Scorch", tr.HitPos - dir * 10, tr.HitPos + dir * 20)
				util.ScreenShake(tr.HitPos, 18, 40, 0.4, 1400)
				for _, ent in ipairs(ents.FindInSphere(tr.HitPos, 240)) do
					if self:BrolyCanHurt(ent) then
						self:BrolyDamage(ent, self.BeamBlastDamage, DMG_BLAST, dir * 20000, tr.HitPos)
						self:BrolyPush(ent, (ent:WorldSpaceCenter() - tr.HitPos):GetNormalized() * 500 + Vector(0, 0, 200))
					end
				end
				if CurTime() > (self._brolyBeamSound or 0) then
					self._brolyBeamSound = CurTime() + 0.6
					sound.Play("broly/blast3.wav", tr.HitPos, 110, math.random(85, 100), 1)
				end
			end
			util.ScreenShake(mouth, 6, 30, 0.2, 900)
			self:YieldCoroutine(false)
		end
		self:SetNW2Float("BrolyBeamUntil", 0)
		self:BrolyDebug("mouthblast: done")
		self:BrolyPause(0.4)
	end

	------------------------------------------------------------------ nova

	-- Crowd control: a dome of violent energy erupts from him and doubles in size until it detonates.
	ENT.NovaSpawnTime = 0.35 -- seconds into broly_nova when the dome appears

	function ENT:BrolyCrowded()
		return #self:BrolyEnemiesNear(700) >= 2
	end

	function ENT:AbilityNova(enemy)
		self:BrolyPowerFor(3)
		self:EmitSound("Broly.Roar")
		self:EmitSound("Broly.KiCharge")
		self:BrolyGesture("broly_nova")
		local start = CurTime()
		while CurTime() - start < self.NovaSpawnTime do self:YieldCoroutine(false) end
		local nova = ents.Create("broly_nova")
		if IsValid(nova) then
			nova:SetOwner(self)
			nova:SetPos(self:GetPos())
			nova:Spawn()
		end
		while CurTime() - start < 2.6 do self:YieldCoroutine(false) end
	end

	------------------------------------------------------------------ ambush

	-- Vanishes, reappears in the air behind whoever has been attacking him, and crashes down on them
	-- with a double axe-handle smash.
	ENT.AmbushHover = 0.28  -- seconds hanging in the air with fists raised before dropping (broly_hammer)
	ENT.AmbushDamage = 2000

	function ENT:BrolyAmbushTarget()
		local best, bestT
		for ent, t in pairs(self._brolyAttackers) do
			if not self:BrolyCanHurt(ent) or CurTime() - t > 5 then
				self._brolyAttackers[ent] = nil
				continue
			end
			local d = self:GetPos():Distance(ent:GetPos())
			if d > 200 and d < 4000 and (not best or t > bestT) then best, bestT = ent, t end
		end
		return best
	end

	function ENT:BrolyTeleportFX(pos, ghost)
		local fx = EffectData()
		fx:SetOrigin(pos)
		fx:SetAngles(self:GetAngles())
		if ghost then fx:SetEntity(self) end
		util.Effect("broly_teleport", fx, true, true)
	end

	function ENT:AbilityAmbush(enemy)
		local target = self:BrolyAmbushTarget() or enemy
		if not IsValid(target) then return end
		local back = -target:GetForward()
		back.z = 0
		if back:IsZero() then
			back = self:GetPos() - target:GetPos()
			back.z = 0
		end
		back:Normalize()

		local mins, maxs = self:GetCollisionBounds()
		local function clear(pos)
			return not util.TraceHull({start = pos, endpos = pos, mins = mins, maxs = maxs, filter = self}).Hit
		end
		local dest = target:GetPos() + back * 90 + Vector(0, 0, 200)
		if not clear(dest) then
			dest = target:GetPos() + Vector(0, 0, target:OBBMaxs().z + 60)
			if not clear(dest) then return end
		end

		-- vanish ... and reappear
		self:BrolyTeleportFX(self:GetPos(), true)
		self:EmitSound("Broly.KiShot", 90, 60)
		self:SetPos(dest)
		self:SetAngles(Angle(0, (target:GetPos() - dest):Angle().y, 0))
		self:BrolyTeleportFX(dest, false)
		self:BrolyPowerFor(2)
		self:EmitSound("Broly.Grunt")
		self:BrolyGesture("broly_hammer")

		local start = CurTime()
		while CurTime() - start < self.AmbushHover do
			self:SetPos(dest)
			self.loco:SetVelocity(vector_origin)
			if IsValid(target) then self:FaceTowards(target) end
			self:YieldCoroutine(false)
		end
		self.loco:SetVelocity(Vector(0, 0, -1800))
		while not self:IsOnGround() and CurTime() - start < 1.5 do self:YieldCoroutine(false) end

		local pos = self:GetPos()
		if self:BrolyCanHurt(target) and target:GetPos():Distance(pos) < 230 then
			local fx = EffectData()
			fx:SetOrigin(target:WorldSpaceCenter())
			fx:SetNormal(Vector(0, 0, -1))
			fx:SetScale(3)
			util.Effect("broly_impact", fx, true, true)
			self:BrolyDamage(target, self.AmbushDamage, DMG_CLUB, Vector(0, 0, -60000))
			self:BrolyPush(target, self:GetForward() * 300 + Vector(0, 0, 500))
		end
		self:BrolyShockwave(pos, {radius = 380, damage = 700, launch = 700, power = 1.4, dome = 330, hitAir = true})
		BrolyHitStop(0.2, 0.2)
		self:BrolyPause(0.5)
	end

	-- Eraser Cannon: charges a green ki ball in his palm, trembling, then hurls it. It homes in a little
	-- and detonates in a huge energy dome that also catches airborne targets.
	ENT.EraserReleaseTime = 1.17 -- seconds into "broly_eraser" when the ball leaves his hand (ERASER_RELEASE)

	function ENT:AbilityEraser(enemy)
		self:BrolyPowerFor(2.5)
		self:EmitSound("Broly.KiCharge")
		self:BrolyGesture("broly_eraser")
		local orb = ents.Create("proj_broly_eraser")
		if not IsValid(orb) then return end
		orb:SetOwner(self)
		orb:SetPos(self:BrolyHandPos("ValveBiped.Bip01_R_Hand"))
		orb:Spawn()
		local start = CurTime()
		while CurTime() - start < self.EraserReleaseTime do
			if IsValid(enemy) then self:FaceTowards(enemy) end
			self:YieldCoroutine(false)
		end
		if not IsValid(orb) then return end
		if not IsValid(enemy) then orb:Remove() return end
		local dist = orb:GetPos():Distance(enemy:WorldSpaceCenter())
		local aim = enemy:WorldSpaceCenter() + enemy:GetVelocity() * (dist / orb.Speed) * 0.7
		orb:Launch(aim - orb:GetPos(), enemy)
		self:EmitSound("Broly.Yell")
		self:EmitSound("Broly.Blast")
		util.ScreenShake(orb:GetPos(), 12, 40, 0.5, 900)
		self:BrolyPause(0.6)
	end

	-- Grab (the movie scene): he catches the target by the head, hoists them overhead trembling with
	-- rage, lets go, and smashes them out of the air with a full-power haymaker.
	ENT.GrabCloseTime = 0.40   -- seconds into "broly_grab" when the hand closes (tools/anim_broly.py GRAB_HIT)
	ENT.GrabLiftTime = 1.60    -- length of "broly_grab"
	ENT.StrikeHitTime = 0.34   -- seconds into "broly_strike" when the fist connects (STRIKE_HIT)
	ENT.HoldDamage = 100       -- per squeeze tick while held
	ENT.StrikeDamage = 1500

	function ENT:BrolyGrabStart(ent)
		self._brolyGrab = {ent = ent, untilT = CurTime() + 2.5, nextHurt = CurTime() + 0.3}
		if ent:IsPlayer() then ent:SetMoveType(MOVETYPE_NONE) end
		self:EmitSound("Flesh.ImpactHard", 85, 70)
		util.ScreenShake(ent:GetPos(), 10, 40, 0.4, 400)
	end

	-- Where a grabbed victim hangs: head in his hand, pushed out in front so the hulls don't overlap.
	function ENT:BrolyGrabHoldPos(ent, hand)
		local fwd = self:GetForward()
		fwd.z = 0
		fwd:Normalize()
		local origin = self:GetPos()
		local flat = Vector(hand.x - origin.x, hand.y - origin.y, 0)
		local reach = self:OBBMaxs().x + ent:OBBMaxs().x + 4
		local along = flat:Dot(fwd)
		if along < reach then flat = flat + fwd * (reach - along) end
		local pos = origin + flat
		pos.z = hand.z - ent:OBBMaxs().z + 6
		return pos
	end

	-- A spot in front of Broly where the victim's hull fits.
	function ENT:BrolyClearSpot(ent)
		local mins, maxs = ent:OBBMins(), ent:OBBMaxs()
		local fwd = self:GetForward()
		fwd.z = 0
		fwd:Normalize()
		for _, extra in ipairs({8, 24, 48, 80}) do
			local pos = self:GetPos() + fwd * (self:OBBMaxs().x + maxs.x + extra) + Vector(0, 0, 8)
			local tr = util.TraceHull({start = pos, endpos = pos, mins = mins, maxs = maxs, filter = {ent}})
			if not tr.Hit then return pos end
		end
		return self:GetPos() + Vector(0, 0, self:OBBMaxs().z + 8) -- on top of his head as a last resort
	end

	function ENT:BrolyGrabUpdate()
		local g = self._brolyGrab
		if not g then return end
		local ent = g.ent
		if not IsValid(ent) or (ent:IsPlayer() and not ent:Alive()) or CurTime() > g.untilT then
			self:BrolyGrabRelease()
			return
		end
		local hand = self:BrolyHandPos("ValveBiped.Bip01_R_Hand")
		ent:SetPos(self:BrolyGrabHoldPos(ent, hand))
		if ent:IsPlayer() then ent:SetLocalVelocity(vector_origin) end
		if CurTime() > g.nextHurt then
			g.nextHurt = CurTime() + 0.3
			local dmg = DamageInfo()
			dmg:SetDamage(self.HoldDamage)
			dmg:SetAttacker(self)
			dmg:SetInflictor(self)
			dmg:SetDamageType(DMG_CLUB)
			ent:TakeDamageInfo(dmg)
			if ent:IsPlayer() then ent:ViewPunch(Angle(math.random(-6, 6), math.random(-6, 6), 0)) end
			util.ScreenShake(hand, 6, 30, 0.3, 400)
		end
	end

	-- Lets go. toss = optional velocity given to the victim (the mid-air drop before the strike).
	function ENT:BrolyGrabRelease(toss)
		local g = self._brolyGrab
		if not g then return end
		self._brolyGrab = nil
		local ent = g.ent
		if not IsValid(ent) then return end
		if ent:IsPlayer() then ent:SetMoveType(MOVETYPE_WALK) end
		local pos = ent:GetPos()
		local tr = util.TraceHull({start = pos, endpos = pos, mins = ent:OBBMins(), maxs = ent:OBBMaxs(), filter = {ent}})
		if tr.Hit then ent:SetPos(self:BrolyClearSpot(ent)) end
		if toss and (ent:IsPlayer() or ent:IsNPC()) then ent:SetVelocity(toss) end
	end

	-- The haymaker that ends the grab.
	function ENT:BrolyMegaStrike(victim)
		local fwd = self:GetForward()
		local vel = fwd * 1900 + Vector(0, 0, 380)
		local pos = victim:WorldSpaceCenter()
		if victim:IsPlayer() then victim:SetLocalVelocity(vector_origin) end
		if victim:IsPlayer() or victim:IsNPC() then victim:SetVelocity(vel) end

		local dmg = DamageInfo()
		dmg:SetDamage(self.StrikeDamage)
		dmg:SetAttacker(self)
		dmg:SetInflictor(self)
		dmg:SetDamageType(DMG_CLUB)
		dmg:SetDamagePosition(pos)
		dmg:SetDamageForce(vel * 80)
		victim:TakeDamageInfo(dmg)

		local fx = EffectData()
		fx:SetOrigin(pos)
		fx:SetNormal(fwd)
		fx:SetScale(3.5)
		util.Effect("broly_impact", fx, true, true)
		util.ScreenShake(pos, 40, 80, 1.2, 2500)
		util.ScreenShake(pos, 15, 5, 2.5, 2500)
		BrolyFlash(pos, 1500, 0.9)
		BrolyHitStop(0.3, 0.15)
		self:EmitSound("Broly.Blast")
		self:EmitSound("Broly.Explosion")
		self:EmitSound("Physics.ImpactHard", 100, 50)
		self:EmitSound("Broly.Roar")
	end

	function ENT:AbilityGrab(enemy)
		local hand = "ValveBiped.Bip01_R_Hand"
		self:FaceTowards(enemy)
		self:BrolyPowerFor(4)
		self:EmitSound("Broly.Grunt")
		self:BrolyGesture("broly_grab")
		local start = CurTime()

		-- reach: lunge in while the hand comes forward
		while CurTime() - start < self.GrabCloseTime do
			if IsValid(enemy) then
				self:FaceTowards(enemy)
				self.loco:Approach(enemy:GetPos(), 1)
			end
			self:YieldCoroutine(false)
		end
		if not IsValid(enemy) then return end
		local fist = self:BrolyHandPos(hand)
		local to = enemy:GetPos() - self:GetPos()
		local caught = enemy:NearestPoint(fist):Distance(fist) < 60
			or (to:Length2D() < 130 and self:GetForward():Dot(to:GetNormalized()) > 0.5)
		if not caught then
			self:BrolyPause(0.6) -- whiffed; the empty-handed lift plays out
			return
		end

		-- catch and hoist overhead
		self:BrolyGrabStart(enemy)
		self:EmitSound("Broly.Yell")
		while CurTime() - start < self.GrabLiftTime and self._brolyGrab do
			self:YieldCoroutine(false)
		end
		if not self._brolyGrab then return end

		-- let go mid-air, wind up, smash
		local victim = self._brolyGrab.ent
		local fwd = self:GetForward()
		self:BrolyGesture("broly_strike")
		local sstart = CurTime()
		self:BrolyGrabRelease(Vector(0, 0, 220) + fwd * 40)
		while CurTime() - sstart < self.StrikeHitTime do
			self:YieldCoroutine(false)
		end
		local alive = IsValid(victim) and (not victim:IsPlayer() or victim:Alive())
		if alive and victim:WorldSpaceCenter():Distance(self:BrolyHandPos(hand)) < 170 then
			self:BrolyMegaStrike(victim)
		else
			self:EmitSound("WeaponFrag.Throw", 85, 60)
		end
		self:BrolyPause(0.66)
	end

end

-- DO NOT TOUCH --
AddCSLuaFile()
DrGBase.AddNextbot(ENT)
