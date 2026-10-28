extends "res://scripts/mechanics/human_agency.gd"
## Keep each NPC's existing utility decisions; give city outings actual destinations.
func _destination(npc: Dictionary, spec: Dictionary) -> String:
	if spec.destination != sim.location_role("trade"): return super._destination(npc,spec)
	var weather := str(sim.state.world.weather)
	if spec == definition("agency_actions","walk"):
		var places := ["city_park","south_promenade","north_beach"]
		return str(places[(int(str(npc.id).hash())+int(sim.state.clock.day_index)) % places.size()])
	if spec.get("social",false) or spec == definition("agency_actions","visit"):
		if npc.location == sim.state.world.location: return str(npc.location)
		# A shared meeting place gives independently chosen outings a chance to intersect.
		if weather in ["rain","snow"] or int(sim.state.clock.hour) >= 18: return "riverside_cafe"
		return "city_park" if int(sim.state.clock.hour) >= 11 else "riverside_cafe"
	return super._destination(npc,spec)
