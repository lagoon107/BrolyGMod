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

-- Sounds --
ENT.OnDamageSounds = {}
ENT.OnDeathSounds = {}

-- Melee attacks --
-- Each attack: a sequence, its playback rate, when (cycle) the hit lands, and the hit itself.
-- hand = bone the impact VFX spawns from; impact = VFX scale; shake = {amplitude, frequency, duration, radius}
ENT.BrolyAttacks = {
	jab_left = {
		seq = "range_fists_l", gesture = true, rate = 1, hit = 0.25,
		damage = 25, range = 90, angle = 70, force = Vector(300, 0, 50), recover = 0.3,
		hand = "ValveBiped.Bip01_L_Hand", impact = 1, shake = {6, 40, 0.3, 500}
	},
	jab_right = {
		seq = "range_fists_r", gesture = true, rate = 1, hit = 0.25,
		damage = 25, range = 90, angle = 70, force = Vector(300, 0, 50), recover = 0.3,
		hand = "ValveBiped.Bip01_R_Hand", impact = 1, shake = {6, 40, 0.3, 500}
	},
	heavy = {
		seq = "seq_meleeattack01", rate = 0.8, hit = 0.45,
		damage = 60, range = 110, angle = 90, force = Vector(450, 0, 200), recover = 0.2,
		hand = "ValveBiped.Bip01_R_Hand", impact = 2.2, shake = {20, 60, 0.8, 900}
	}
}

-- Abilities --
-- cooldown (s), distance window to the enemy, weight for the random pick
ENT.BrolyAbilities = {
	leap    = {cooldown = 3.5, min = 1100, max = 4500, weight = 6},
	slam    = {cooldown = 8,   min = 250,  max = 900,  weight = 4},
	barrage = {cooldown = 11,  min = 500,  max = 2800, weight = 3},
	grab    = {cooldown = 12,  min = 0,    max = 110,  weight = 0}, -- picked from melee, see OnMeleeAttack
}
ENT.GrabChance = 0.4
ENT.AbilityGap = 1.0 -- minimum seconds between any two abilities

if SERVER then

	function ENT:CustomInitialize()
		self:SetDefaultRelationship(D_HT)
		self._brolyCombo = 0
		self._brolyCooldowns = {}
		self._brolyNextAbility = 0
		self:CallOnRemove("BrolyReleaseGrab", function(self) self:BrolyGrabRelease(false) end)
	end

	function ENT:CustomThink()
		self:BrolyGrabUpdate()
		return 0
	end

	function ENT:OnNewEnemy()
		self:SetOmniscient(true) -- always knows where you are once the fight starts
	end

	-- Damage resistance: small arms barely scratch him, explosives are the way.
	function ENT:OnTakeDamage(dmg)
		self:SpotEntity(dmg:GetAttacker())
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
		local function onCycle(self, cycle)
			if not hitDone and cycle >= atk.hit then
				hitDone = true
				self:Attack({
					damage = atk.damage, range = atk.range, angle = atk.angle,
					type = DMG_CLUB, force = atk.force, push = true,
					viewpunch = Angle(atk.damage * 0.5, math.random(-10, 10), 0)
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

	function ENT:BrolyUseAbility(name, enemy)
		self._brolyCooldowns[name] = CurTime() + self.BrolyAbilities[name].cooldown
		self[({leap = "AbilityLeap", slam = "AbilitySlam", barrage = "AbilityBarrage", grab = "AbilityGrab"})[name]](self, enemy)
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
			local inRange = dist >= ab.min and dist <= ab.max
			if name == "leap" and above and dist > 200 then inRange = true end
			if name ~= "leap" and not visible then inRange = false end
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

	-- Damages and launches everything grounded within radius. Jumping dodges it.
	function ENT:BrolyShockwave(pos, radius, damage, launch, power)
		local fx = EffectData()
		fx:SetOrigin(pos)
		fx:SetScale(radius)
		fx:SetMagnitude(power)
		util.Effect("broly_shockwave", fx, true, true)
		util.ScreenShake(pos, 25 * power, 50, 1.2 * power, radius * 3)
		self:EmitSound("ambient/explosions/explode_" .. math.random(1, 4) .. ".wav", 95, math.random(85, 100))
		self:EmitSound("Physics.ImpactHard", 95, 60)

		for _, ent in ipairs(ents.FindInSphere(pos, radius)) do
			if ent == self or not IsValid(ent) or ent.IsDrGProjectile or ent.IsBrolyBoss then continue end
			local isChar = ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot()
			local phys = ent:GetPhysicsObject()
			if not isChar and not (IsValid(phys) and ent:GetMoveType() == MOVETYPE_VPHYSICS) then continue end
			if isChar and (not ent:IsOnGround() or (ent:IsPlayer() and not ent:Alive())) then continue end

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
		self:EmitSound("Weapon_Crowbar.Single", 85, 50)
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
		self:BrolyShockwave(self:GetPos(), 220, 15, 300, 0.5)
		self:BrolyPause(0.2)
	end

	-- Ground slam: big crouch windup, high leap onto the player, shockwave that launches anything grounded.
	function ENT:AbilitySlam(enemy)
		self:FaceTowards(enemy)
		self:EmitSound("npc/zombie_poison/pz_warn1.wav", 90, 60)
		self:PlaySequenceAndWait("jump_land", 0.5) -- slow, readable windup
		local target = enemy:GetPos() + enemy:GetVelocity() * 0.3
		if not self:BrolyLeapTo(target, 1.02, enemy) then return end
		self:BrolyShockwave(self:GetPos(), 450, 65, 650, 1)
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
		self:EmitSound("weapons/physcannon/energy_sing_flyby" .. math.random(2) .. ".wav", 80, math.random(130, 150), 0.6)
	end

	function ENT:AbilityBarrage(enemy)
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

	-- Grab & throw: lunges, catches the target by the head, squeezes, then hurls them.
	function ENT:BrolyGrabStart(ent)
		self._brolyGrab = {ent = ent, untilT = CurTime() + 2, nextHurt = CurTime() + 0.3}
		if ent:IsPlayer() then ent:SetMoveType(MOVETYPE_NONE) end
		self:EmitSound("Flesh.ImpactHard", 85, 70)
	end

	-- Where a grabbed victim hangs: in front of Broly, clear of both hulls, head at hand height.
	function ENT:BrolyGrabHoldPos(ent, hand)
		local fwd = self:GetForward()
		fwd.z = 0
		fwd:Normalize()
		local reach = self:OBBMaxs().x + ent:OBBMaxs().x + 8
		local pos = self:GetPos() + fwd * reach
		pos.z = hand.z - ent:OBBMaxs().z + 8
		return pos
	end

	-- A spot in front of Broly where the victim's hull fits, for the release.
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
			self:BrolyGrabRelease(false)
			return
		end
		local hand = self:BrolyHandPos("ValveBiped.Bip01_R_Hand")
		ent:SetPos(self:BrolyGrabHoldPos(ent, hand))
		if ent:IsPlayer() then ent:SetLocalVelocity(vector_origin) end
		if CurTime() > g.nextHurt then
			g.nextHurt = CurTime() + 0.3
			local dmg = DamageInfo()
			dmg:SetDamage(6)
			dmg:SetAttacker(self)
			dmg:SetInflictor(self)
			dmg:SetDamageType(DMG_CLUB)
			ent:TakeDamageInfo(dmg)
			if ent:IsPlayer() then ent:ViewPunch(Angle(math.random(-6, 6), math.random(-6, 6), 0)) end
			util.ScreenShake(hand, 5, 30, 0.3, 300)
		end
	end

	function ENT:BrolyGrabRelease(throw)
		local g = self._brolyGrab
		if not g then return end
		self._brolyGrab = nil
		local ent = g.ent
		if not IsValid(ent) then return end
		if ent:IsPlayer() then ent:SetMoveType(MOVETYPE_WALK) end
		ent:SetPos(self:BrolyClearSpot(ent))
		if not throw then return end

		local vel = self:GetForward() * 1400 + Vector(0, 0, 450)
		if ent:IsPlayer() or ent:IsNPC() then ent:SetVelocity(vel) end
		local dmg = DamageInfo()
		dmg:SetDamage(40)
		dmg:SetAttacker(self)
		dmg:SetInflictor(self)
		dmg:SetDamageType(DMG_CLUB)
		dmg:SetDamageForce(vel * 60)
		ent:TakeDamageInfo(dmg)
		self:BrolyImpact(self.BrolyAttacks.heavy, ent)
	end

	function ENT:AbilityGrab(enemy)
		self:FaceTowards(enemy)
		self:AddGestureSequence(self:LookupSequence("range_melee_shove_1hand"), true)
		self:BrolyPause(0.25, enemy)
		if not IsValid(enemy) then return end
		local to = enemy:GetPos() - self:GetPos()
		if to:Length2D() > 130 or self:GetForward():Dot(to:GetNormalized()) < 0.5 then
			self:BrolyPause(0.4) -- whiffed
			return
		end
		self:BrolyGrabStart(enemy)
		self:BrolyPause(1.0)
		if not self._brolyGrab then return end
		self:AddGestureSequence(self:LookupSequence("gesture_item_throw"), true)
		self:BrolyPause(0.3)
		self:BrolyGrabRelease(true)
		self:BrolyPause(0.5)
	end

end

-- DO NOT TOUCH --
AddCSLuaFile()
DrGBase.AddNextbot(ENT)
