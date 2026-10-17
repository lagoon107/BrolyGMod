-- Server half of the boss bar: a player hitting a boss engages its bar on their screen.
util.AddNetworkString("EldenBossBar_Engage")

hook.Add("EntityTakeDamage", "EldenBossBar_Engage", function(ent, dmg)
	if not ent.IsBrolyBoss then return end
	local attacker = dmg:GetAttacker()
	if not IsValid(attacker) or not attacker:IsPlayer() then return end
	net.Start("EldenBossBar_Engage")
	net.WriteEntity(ent)
	net.Send(attacker)
end)
