extends "res://scripts/mechanics/npc_personalities.gd"
var profile_us := 0
var profile_calls := 0

func profile(npc: Dictionary) -> Dictionary:
	var start := Time.get_ticks_usec()
	var result := super.profile(npc)
	profile_us += Time.get_ticks_usec()-start
	profile_calls += 1
	return result
