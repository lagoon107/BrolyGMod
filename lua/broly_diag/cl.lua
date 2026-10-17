local n, info = 0, {}
for _, e in ipairs(ents.GetAll()) do
	if e:GetClass() == "npc_broly" or e.IsBrolyBoss then
		n = n + 1
		info[#info + 1] = tostring(e) .. " flag=" .. tostring(e.IsBrolyBoss) .. " dormant=" .. tostring(e:IsDormant())
			.. " powered=" .. tostring(e:GetNW2Bool("BrolyPowered")) .. " beam=" .. tostring(e:GetNW2Float("BrolyBeamUntil", 0))
	end
end
local t = hook.GetTable()
print("[BrolyDiag] cl ents", n, table.concat(info, " | "))
print("[BrolyDiag] hooks think", t.Think and t.Think.BrolyFX_Aura, "draw", t.PostDrawTranslucentRenderables and t.PostDrawTranslucentRenderables.BrolyFX_Draw, "lockon", t.Think and t.Think.BrolyLockOn_Input)
print("[BrolyDiag] findbyclass", #ents.FindByClass("npc_broly"), "time", CurTime())
