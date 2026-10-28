extends RefCounted
## Occupancy is [arrival, finish): completion at closing does not occupy that minute.

static func is_open(sim, place: Dictionary, arrival: int, finish: int) -> bool:
	if place.is_empty() or finish<arrival: return false
	for minute in range(arrival,maxi(arrival+1,finish)):
		if not sim.services.world.is_open_at(place,minute): return false
	return true
