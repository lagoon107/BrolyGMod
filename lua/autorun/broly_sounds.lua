-- Broly sound scripts. Clips are cut from sound_src/ by tools/slice_sounds.py into sound/broly/.

local function Add(name, files, level, pitch, volume, channel)
	local wav = {}
	for i, f in ipairs(files) do wav[i] = "broly/" .. f .. ".wav" end
	sound.Add({
		name = name,
		channel = channel or CHAN_AUTO,
		level = level,
		pitch = pitch or 100,
		volume = volume or 1,
		sound = #wav == 1 and wav[1] or wav
	})
end

-- voice (CHAN_VOICE so a new line cuts off the previous one)
Add("Broly.Scream",     {"scream_full"},  140, 100, 1, CHAN_VOICE)
Add("Broly.RoarWindup", {"roar_windup"},  130, 100, 1, CHAN_VOICE)
Add("Broly.Roar",       {"roar"},         140, 100, 1, CHAN_VOICE)
Add("Broly.Yell",       {"yell"},         130, {97, 103}, 1, CHAN_VOICE)
Add("Broly.Grunt",      {"grunt1", "grunt2", "grunt3", "grunt4"}, 95, {94, 106}, 0.9, CHAN_VOICE)
Add("Broly.DeathRoar",  {"roar"},         140, 80, 1, CHAN_VOICE)

-- ki
Add("Broly.KiCharge",   {"ki_charge"},    100, {98, 104}, 0.9, CHAN_WEAPON)
Add("Broly.KiShot",     {"ki_shot1", "ki_shot2"}, 90, {105, 125}, 0.7)
Add("Broly.KiHit",      {"ki_hit"},       90, {95, 115}, 0.8)
Add("Broly.Blast",      {"blast1", "blast2", "blast4"}, 120, {95, 105}, 1)
Add("Broly.Explosion",  {"blast3", "blast5"}, 125, {90, 100}, 1)
