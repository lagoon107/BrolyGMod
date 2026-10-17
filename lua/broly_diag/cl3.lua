hook.Remove("PostDrawTranslucentRenderables", "BrolyDiagSprite")
local t = hook.GetTable()
for _, fn in ipairs({t.Think.BrolyFX_Aura, t.PostDrawTranslucentRenderables.BrolyFX_Draw}) do
	local info = debug.getinfo(fn, "S")
	print("[BrolyDiag] fn", info.short_src, info.linedefined)
	for i = 1, 30 do
		local name, val = debug.getupvalue(fn, i)
		if not name then break end
		if name == "state" then
			print("[BrolyDiag]   state entries", table.Count(val))
			for e, st in pairs(val) do print("[BrolyDiag]     ", e, "arcs", #st.arcs, "emitter", st.emitter) end
		else
			print("[BrolyDiag]   upvalue", name, type(val) == "table" and "table" or tostring(val))
		end
	end
end
