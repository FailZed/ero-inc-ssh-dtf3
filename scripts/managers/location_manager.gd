extends Node
## Presentation location mirror. Simulation owns every journey and access decision.
signal location_changed(location_id: String)
signal travel_blocked(location_id: String, reason: String)
var current_location_id := ""
var previous_location_id := ""

func go_to(location_id: String) -> Error:
	var result: Dictionary = Gameplay.execute("world","journey",{"id":location_id})
	if not result.ok:
		travel_blocked.emit(location_id,str(result.error))
		return ERR_UNAVAILABLE
	return OK

func can_go_to(location_id: String) -> Dictionary:
	if Gameplay.phase != "free_roam": return {"ok":false,"error":"story_locked"}
	return Gameplay.simulation.services.world.route(location_id)

func get_location(location_id: String) -> Dictionary:
	if Gameplay.simulation == null: return {}
	return Gameplay.simulation.catalog.locations.get(location_id,{}).duplicate(true)

func get_locations() -> Dictionary:
	if Gameplay.simulation == null: return {}
	return Gameplay.simulation.catalog.locations.duplicate(true)

func get_current_location() -> Dictionary:
	return get_location(current_location_id)

func get_parent_location() -> Dictionary:
	return get_location(previous_location_id)

func can_go_back() -> bool:
	return not previous_location_id.is_empty() and can_go_to(previous_location_id).ok

func go_back() -> void:
	if can_go_back(): go_to(previous_location_id)
