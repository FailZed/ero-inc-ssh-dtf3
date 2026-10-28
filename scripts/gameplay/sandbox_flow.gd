extends RefCounted
## Separate open-world entry. No chapter rewards, authored cast or plot timeline.
static func begin(gameplay) -> Dictionary:
	var sim = gameplay.simulation
	if sim.state.world.flags.get("sandbox_started", false): return {"ok":false,"error":"sandbox_already_started"}
	if not GameSession.player_character_created: return {"ok":false,"error":"character_creation_required"}
	gameplay._syncing = true
	GameSession.set_game_time_total_minutes(480)
	gameplay._syncing = false
	sim.state.clock = sim.calendar.snapshot(480)
	sim.state.player.name = GameSession.get_character_profile().full_name
	sim.state.player.age = int(gameplay.configuration.profile.age)
	sim.state.player.points = maxi(0, gameplay.creation_budget() - gameplay._creation_spent())
	sim.state.economy.cash = int(gameplay.configuration.get("sandbox", {}).get("start_cash", 250))
	sim.state.world.location = "bedroom"
	sim.state.housing = {"residence":"apartment", "properties":{"apartment":{
		"owned":false, "equipment":{"stove":1}, "tenants":[], "next_bill":sim.calendar.add_months(480, 1),
		"arrears":0, "rent_income":0, "tenant_arrears":{}, "original_homes":{}, "layout":{}}}}
	sim.state.world.equipment = ["stove"]
	for item in [["meal",3], ["book",1], ["grain",2], ["vegetable",2]]:
		var given: Dictionary = sim.command("inventory","add",{"id":item[0],"quantity":item[1]})
		if not given.ok: return given
	var education: Dictionary = gameplay.configuration.sandbox.education
	preload("res://scripts/mechanics/education_schedule.gd").apply_plan(sim.state,education.enrolled,education.subjects)
	sim.state.world.flags.city_story_home = false
	sim.state.world.flags.sandbox = true
	sim.state.world.flags.sandbox_started = true
	gameplay.story_flags = {"sandbox":true,"modal":""}
	gameplay._start_npc_life()
	if not gameplay.restore_error.is_empty(): return {"ok":false,"error":gameplay.restore_error}
	gameplay.phase = "free_roam"
	LocationManager.current_location_id = "bedroom"
	gameplay._checkpoint()
	gameplay.phase_changed.emit("free_roam")
	gameplay.changed.emit()
	gameplay.notification.emit("Город открыт. Следите за собой, обустраивайте дом и знакомьтесь с жителями.")
	return {"ok":true,"data":{}}
