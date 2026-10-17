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

-- broly_ability <leap|slam|barrage|eraser|grab>: every Broly uses that ability next (ignores range/cooldown)
concommand.Add("broly_ability", function(ply, _, args)
	if IsValid(ply) and not ply:IsAdmin() then return end
	local name = args[1]
	for _, broly in ipairs(ents.FindByClass("npc_broly")) do
		if not broly.BrolyAbilities[name] then print("[Broly] unknown ability", name) return end
		broly._brolyForce = name
		print("[Broly] forcing ability", name, "on", broly)
	end
end, function(cmd) return {cmd .. " leap", cmd .. " slam", cmd .. " barrage", cmd .. " eraser", cmd .. " grab"} end)

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
