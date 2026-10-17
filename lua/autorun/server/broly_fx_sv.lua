-- Server helpers for Broly's screen-space effects.
util.AddNetworkString("BrolyFlash")

-- Flashes the screen of every player within radius of pos (closer = stronger).
function BrolyFlash(pos, radius, strength, col)
	col = col or Color(170, 255, 120)
	for _, ply in ipairs(player.GetAll()) do
		local dist = ply:GetPos():Distance(pos)
		if dist > radius then continue end
		net.Start("BrolyFlash")
		net.WriteFloat(strength * (1 - dist / radius * 0.7))
		net.WriteColor(col, false)
		net.Send(ply)
	end
end

-- Brief slow-motion "hit stop" for big hits. Singleplayer only, toggle with broly_hitstop 0.
local hitstop = CreateConVar("broly_hitstop", "1", FCVAR_ARCHIVE, "Brief slow motion on Broly's biggest hits (singleplayer)")
function BrolyHitStop(duration, scale)
	if not hitstop:GetBool() or not game.SinglePlayer() then return end
	game.SetTimeScale(scale)
	timer.Create("BrolyHitStop", duration * scale, 1, function() game.SetTimeScale(1) end)
end
