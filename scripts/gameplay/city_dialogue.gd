extends "res://scripts/mechanics/npc_dialogue.gd"
const City = preload("res://scripts/gameplay/city_layout.gd")

func local_initiative(npc: Dictionary) -> bool:
	return npc.location == sim.state.world.location and (not City.point(str(npc.location)).is_empty() or npc.location == "residential_district")
