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

-- Stats --
ENT.SpawnHealth = 3000
ENT.MinPhysDamage = 50

-- AI --
ENT.RangeAttackRange = 0
ENT.MeleeAttackRange = 80
ENT.ReachEnemyRange = 60
ENT.AvoidEnemyRange = 0

-- Relationships --
ENT.DefaultRelationship = D_HT
ENT.Factions = {"FACTION_BROLY"}

-- Detection --
ENT.EyeBone = "ValveBiped.Bip01_Head1"
ENT.EyeOffset = Vector(6, 0, 3)

-- Locomotion / movement --
ENT.MaxYawRate = 300
ENT.UseWalkframes = false
ENT.WalkSpeed = 120
ENT.RunSpeed = 280

-- Animations (ValveBiped player animations, via the proportions trick in the model) --
ENT.IdleAnimation = ACT_HL2MP_IDLE_FIST
ENT.WalkAnimation = ACT_HL2MP_WALK_FIST
ENT.RunAnimation = ACT_HL2MP_RUN_FIST
ENT.JumpAnimation = ACT_HL2MP_JUMP_FIST

-- Sounds --
ENT.OnDamageSounds = {}
ENT.OnDeathSounds = {}

-- Attacks --
-- Each attack: a sequence, its playback rate, when (cycle) the hit lands, and the hit itself.
-- hand = bone the impact VFX spawns from; impact = VFX scale; shake = {amplitude, frequency, duration, radius}
ENT.BrolyAttacks = {
	jab_left = {
		seq = "range_fists_l", gesture = true, rate = 1, hit = 0.25,
		damage = 20, range = 90, angle = 70, force = Vector(300, 0, 50), recover = 0.35,
		hand = "ValveBiped.Bip01_L_Hand", impact = 1, shake = {6, 40, 0.3, 500}
	},
	jab_right = {
		seq = "range_fists_r", gesture = true, rate = 1, hit = 0.25,
		damage = 20, range = 90, angle = 70, force = Vector(300, 0, 50), recover = 0.35,
		hand = "ValveBiped.Bip01_R_Hand", impact = 1, shake = {6, 40, 0.3, 500}
	},
	heavy = {
		seq = "seq_meleeattack01", rate = 0.8, hit = 0.45,
		damage = 55, range = 110, angle = 90, force = Vector(450, 0, 200), recover = 0.2,
		hand = "ValveBiped.Bip01_R_Hand", impact = 2.2, shake = {20, 60, 0.8, 900}
	}
}

if SERVER then

	function ENT:CustomInitialize()
		self:SetDefaultRelationship(D_HT)
		self._brolyCombo = 0
	end

	-- Hit feedback: VFX where the fist meets the target, screen shake, and a heavier thud on big hits.
	function ENT:BrolyImpact(atk, ent)
		local bone = self:LookupBone(atk.hand)
		local fist = bone and self:GetBonePosition(bone) or self:WorldSpaceCenter()
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
		self:Wait(atk.recover)
	end

	function ENT:OnMeleeAttack(enemy)
		-- jab, jab, heavy
		self._brolyCombo = (self._brolyCombo % 3) + 1
		if self._brolyCombo == 1 then self:BrolyAttack("jab_left")
		elseif self._brolyCombo == 2 then self:BrolyAttack("jab_right")
		else self:BrolyAttack("heavy") end
	end

	function ENT:OnIdle()
		self:AddPatrolPos(self:RandomPos(1000))
	end

end

-- DO NOT TOUCH --
AddCSLuaFile()
DrGBase.AddNextbot(ENT)
