extends "res://scripts/mechanics/autonomous_reproductive_simulation.gd"
## Authored two-house fixture using exactly the agreed main-city semantic API.
## It verifies consumers independently; it does not stand in for the city graph.

func player_home_room(kind: String) -> String:
	return str(catalog.properties.get(str(state.housing.residence),{}).get("rooms",{}).get(kind,""))

func is_player_home_location(id: String) -> bool:
	var property := str(state.housing.residence)
	return not property.is_empty() and catalog.locations.get(id,{}).get("residence_property_id","")==property
