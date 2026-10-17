local hits = {think = 0, draw = 0, diag = 0}
local t = hook.GetTable()
local origThink, origDraw = t.Think.BrolyFX_Aura, t.PostDrawTranslucentRenderables.BrolyFX_Draw
hook.Add("Think", "BrolyFX_Aura", function(...) hits.think = hits.think + 1 return origThink(...) end)
hook.Add("PostDrawTranslucentRenderables", "BrolyFX_Draw", function(...) hits.draw = hits.draw + 1 return origDraw(...) end)
local mat = Material("sprites/light_glow02_add")
hook.Add("PostDrawTranslucentRenderables", "BrolyDiagSprite", function()
	hits.diag = hits.diag + 1
	for _, e in ipairs(ents.GetAll()) do
		if e.IsBrolyBoss then render.SetMaterial(mat) render.DrawSprite(e:WorldSpaceCenter() + Vector(0, 0, 80), 300, 300, Color(255, 0, 255)) end
	end
end)
print("[BrolyDiag] Think hooks:", table.Count(t.Think), "PDTR hooks:", table.Count(t.PostDrawTranslucentRenderables))
for k in pairs(t.PostDrawTranslucentRenderables) do print("[BrolyDiag]   pdtr", k) end
timer.Simple(1, function()
	print("[BrolyDiag] calls in 1s: think", hits.think, "draw", hits.draw, "diag", hits.diag)
	hook.Add("Think", "BrolyFX_Aura", origThink)
	hook.Add("PostDrawTranslucentRenderables", "BrolyFX_Draw", origDraw)
end)
