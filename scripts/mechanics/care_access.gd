extends RefCounted
## Shared clinical presence and complete service interval, including NPC completion.
const ServiceWindow = preload("res://scripts/mechanics/core/service_window.gd")

static func clinic(sim) -> String:
	return str(sim.catalog.get("location_roles",{}).get("clinic",""))

static func sanitary(sim, id: String) -> bool:
	var place := location(sim,id)
	var entry: Dictionary = sim.catalog.locations.get(place,{})
	if entry.get("kind","") in ["private_room","private_residence"]: return sim.is_actor_home_location(id,place)
	return sim.is_actor_home_location(id,place) or sim.room_kind(place)=="bathroom" or bool(entry.get("toilet",false)) or "sanitary_private" in entry.get("facilities",[]) or place==clinic(sim)

static func supplies_available(sim, id: String) -> bool:
	var place := location(sim,id)
	return "supplies" in sim.catalog.locations.get(place,{}).get("facilities",[]) or place in [clinic(sim),str(sim.catalog.get("location_roles",{}).get("supply_shop",""))]

static func location(sim, id: String) -> String:
	return str(sim.state.world.location) if id=="player" else str(sim.state.social.npcs.get(id,{}).get("location",""))

static func clinic_blocked(sim, patient: String, minutes: int, completion: bool = false, payer: String = "") -> String:
	var site := clinic(sim)
	var place: Dictionary = sim.catalog.locations.get(site,{})
	if place.is_empty(): return "clinic_unavailable"
	if location(sim,patient)!=site: return "clinic_required"
	if not payer.is_empty() and payer!=patient and location(sim,payer)!=site: return "care_payer_not_present"
	var now := int(sim.state.clock.total_minutes)
	var begins := now-minutes if completion else now
	if not sim.services.world.is_open_at(place,begins): return "location_closed"
	if not ServiceWindow.is_open(sim,place,begins,begins+minutes): return "clinic_visit_window"
	return ""
