-- Dev helpers for testing Broly. Usage (console): broly_spawn
concommand.Add("broly_spawn", function(ply)
	if IsValid(ply) and not ply:IsAdmin() then return end
	ply = IsValid(ply) and ply or Entity(1)
	if not IsValid(ply) then return end

	local fwd = ply:GetForward()
	fwd.z = 0
	fwd:Normalize()
	local broly = ents.Create("npc_broly")
	if not IsValid(broly) then print("[Broly] npc_broly missing (is DrGBase installed?)") return end
	broly:SetPos(ply:GetPos() + fwd * 250)
	broly:SetAngles(Angle(0, (-fwd):Angle().y, 0))
	broly:Spawn()
	undo.Create("Broly")
	undo.AddEntity(broly)
	undo.SetPlayer(ply)
	undo.Finish()
	print("[Broly] spawned", broly, broly:GetModel(), "seq:", broly:GetSequenceName(broly:GetSequence()))
end)

-- broly_ability <name>: every Broly uses that ability next (ignores range/cooldown/conditions)
concommand.Add("broly_ability", function(ply, _, args)
	if IsValid(ply) and not ply:IsAdmin() then return end
	local name = args[1]
	for _, broly in ipairs(ents.FindByClass("npc_broly")) do
		if not broly.BrolyAbilities[name] then print("[Broly] unknown ability", name) return end
		broly._brolyForce = name
		print("[Broly] forcing ability", name, "on", broly)
	end
end, function(cmd)
	local out = {}
	for _, n in ipairs({"leap", "slam", "barrage", "eraser", "mouthblast", "nova", "ambush", "grab"}) do out[#out + 1] = cmd .. " " .. n end
	return out
end)

-- broly_targets [class] [count] [distance]: a row of NPCs in front of you for Broly to fight
-- (pair with ai_ignoreplayers 1 to watch from the side)
concommand.Add("broly_targets", function(ply, _, args)
	if IsValid(ply) and not ply:IsAdmin() then return end
	ply = IsValid(ply) and ply or Entity(1)
	local class = args[1] or "npc_combine_s"
	local count = tonumber(args[2]) or 4
	local dist = tonumber(args[3]) or 900
	local fwd = ply:GetForward()
	fwd.z = 0
	fwd:Normalize()
	local right = fwd:Cross(Vector(0, 0, 1))
	for i = 1, count do
		local npc = ents.Create(class)
		if not IsValid(npc) then print("[Broly] can't create", class) return end
		local pos = ply:GetPos() + fwd * dist + right * (i - (count + 1) / 2) * 120
		local ground = util.TraceLine({start = pos + Vector(0, 0, 300), endpos = pos - Vector(0, 0, 2000), mask = MASK_SOLID,
			filter = function(e) return not (e:IsNPC() or e:IsPlayer() or e:IsNextBot()) end})
		npc:SetPos(ground.HitPos + Vector(0, 0, 10))
		npc:SetAngles(Angle(0, (-fwd):Angle().y, 0))
		if class == "npc_combine_s" or class == "npc_metropolice" or class == "npc_citizen" then
			npc:SetKeyValue("additionalequipment", class == "npc_metropolice" and "weapon_pistol" or "weapon_ar2")
		end
		npc:Spawn()
		npc:Activate()
		undo.Create("Broly target")
		undo.AddEntity(npc)
		undo.SetPlayer(ply)
		undo.Finish()
	end
	print("[Broly] spawned", count, class)
end)

-- broly_info: what each Broly is targeting and how he sees nearby NPCs
concommand.Add("broly_info", function(ply)
	if IsValid(ply) and not ply:IsAdmin() then return end
	for _, b in ipairs(ents.FindByClass("npc_broly")) do
		print("[Broly] info", b, "enemy", b:GetEnemy(), "omni", b:IsOmniscient(), "hp", b:Health(),
			"pos", b:GetPos(), "eye", b:EyePos())
		for _, e in ipairs(ents.FindInSphere(b:GetPos(), 5000)) do
			if e:IsNPC() or (e:IsNextBot() and e ~= b) then
				print("   ", e, "rel", b:GetRelationship(e), "dist", math.Round(b:GetPos():Distance(e:GetPos())),
					"visible", b:Visible(e), "spotted", b.HasSpotted and b:HasSpotted(e), "npc->broly", e.Disposition and e:Disposition(b))
				local tr = util.TraceLine({start = b:EyePos(), endpos = e:WorldSpaceCenter(), filter = b})
				print("       pos", e:GetPos(), "trace hit", tr.Entity, tr.HitWorld and "WORLD" or "", "frac", math.Round(tr.Fraction, 2))
			end
		end
	end
end)

-- broly_hurt [amount]: damages every Broly as if the calling player hit him
concommand.Add("broly_hurt", function(ply, _, args)
	if IsValid(ply) and not ply:IsAdmin() then return end
	ply = IsValid(ply) and ply or Entity(1)
	for _, broly in ipairs(ents.FindByClass("npc_broly")) do
		local dmg = DamageInfo()
		dmg:SetDamage(tonumber(args[1]) or 250)
		dmg:SetAttacker(ply)
		dmg:SetInflictor(ply)
		dmg:SetDamageType(DMG_CLUB)
		broly:TakeDamageInfo(dmg)
		print("[Broly] hurt", broly, "hp:", broly:Health())
	end
end)

-- Agent bridge (singleplayer only): lines written to data/broly_cmd.txt get run, then the file is cleared.
-- Lets tests drive the game without keyboard focus. "lua <code>" runs server Lua, "cl <cmd>" runs a
-- command on the local player's client, anything else is a server console command.
if game.SinglePlayer() then
	timer.Create("BrolyDevBridge", 0.5, 0, function()
		local txt = file.Read("broly_cmd.txt", "DATA")
		if not txt or txt == "" then return end
		file.Write("broly_cmd.txt", "")
		for line in txt:gmatch("[^\r\n]+") do
			print("[Broly] bridge>", line)
			local code, cl = line:match("^lua (.+)"), line:match("^cl (.+)")
			if code then
				RunString(code, "BrolyDevBridge")
			elseif cl then
				if IsValid(Entity(1)) then Entity(1):ConCommand(cl) end
			else
				game.ConsoleCommand(line .. "\n")
			end
		end
	end)
end
