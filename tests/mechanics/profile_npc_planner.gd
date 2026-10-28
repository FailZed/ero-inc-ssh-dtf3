extends SceneTree
const Sim = preload("res://scripts/mechanics/npc_life_simulation.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var sim = Sim.new(128,{"settings":{"start_minutes":480}})
	sim.command("npc_agency","enable")
	sim.command("population","configure",{"values":{"count":100}})
	sim.command("population","generate")
	var actors: Array = sim.state.social.npcs.values()
	var started := Time.get_ticks_usec()
	for repeat in range(3):
		for npc in actors: sim.services.npc_agency.evaluate(npc)
	var evaluate := Time.get_ticks_usec()-started
	started = Time.get_ticks_usec()
	for repeat in range(3):
		for npc in actors: sim.services.npc_planner.calendar.windows(str(npc.id))
	var windows := Time.get_ticks_usec()-started
	started = Time.get_ticks_usec()
	for repeat in range(3):
		for npc in actors: sim.services.npc_planner.calendar.conflict(str(npc.id),str(npc.home),30)
	var conflicts := Time.get_ticks_usec()-started
	print("NPC_PLANNER_PROFILE ",JSON.stringify({"npcs":100,"queries":300,"evaluate_us":evaluate,"windows_us":windows,"conflicts_us":conflicts}))
	quit()
