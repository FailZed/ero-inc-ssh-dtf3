extends "res://scripts/mechanics/family_lifecycle.gd"
## Keep birth metadata in the same transaction, before Family imports the result.
func tick(minute: int) -> void:
	var count: int = sim.state.healthcare.family.size()
	super.tick(minute)
	if not sim.services.has("reproduction"): return
	for index in range(count, sim.state.healthcare.family.size()):
		sim.services.reproduction.on_birth(index)
