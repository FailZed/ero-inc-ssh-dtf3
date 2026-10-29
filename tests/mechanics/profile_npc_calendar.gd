extends "res://scripts/mechanics/npc_calendar.gd"
var windows_us := 0
var windows_calls := 0

func windows(id: String, horizon: int = 1440) -> Array:
	var start := Time.get_ticks_usec()
	var result := super.windows(id, horizon)
	windows_us += Time.get_ticks_usec()-start
	windows_calls += 1
	return result
