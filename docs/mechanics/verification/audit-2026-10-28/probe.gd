extends SceneTree
const Driver = preload("res://tests/gameplay/work_driver.gd")
var gameplay

func _initialize() -> void:
	call_deferred("run")

func fresh():
	var sim = gameplay.make_simulation()
	sim.state.clock = sim.calendar.snapshot(2240)
	sim.state.economy.cash = 5000
	sim.state.world.location = "bedroom"
	sim.state.world.equipment = ["stove","computer","camera"]
	return sim

func run() -> void:
	root.get_node("GameSession").pause_autosave_runtime()
	gameplay = root.get_node("Gameplay")
	var sim = fresh()
	var inventory := {"services":sim.services.keys(),"catalog":{}}
	for group in ["skills","items","recipes","properties","lessons","actions","training_programs","combat_moves","weapons","contracts","professions","stream_topics","publications","family_actions","family_stages","npc_story_arcs","agency_actions","agency_aspirations","dialogue_nodes","dialogue_pools","reproductive_procedures","contraceptive_methods"]:
		inventory.catalog[group] = sim.catalog.get(group,{}).size()
	var work: Dictionary = sim.catalog.livelihood_rules
	inventory.work = {"jobs":work.jobs.size(),"goals":work.aspirations.size(),"order_templates":work.orders.size(),"home_upgrades":work.upgrades.size()}
	var observations: Array = []
	sim = fresh()
	sim.state.clock = sim.calendar.snapshot(2090)
	sim.state.world.location = "training_center"
	var result: Dictionary = sim.command("world","lesson",{"id":"common_day"})
	observations.append({"id":"late_lesson","arrival":"10:50","scheduled":"10:00-11:00","result":result,"grade":sim.state.world.education.grade,"absences":sim.state.world.education.absences,"end":sim.state.clock.time_text,"study_skill":sim.state.player.skills.get("study",0)})
	sim = fresh()
	sim.state.clock = sim.calendar.snapshot(1980)
	sim.state.world.location = "city_park"
	observations.append({"id":"commute_guard","job":"race_marshal","start":"09:00","work_ends":"10:00","conflicts":sim.services.livelihood.study_conflicts("race_marshal"),"result":sim.command("livelihood","work",{"id":"race_marshal"})})
	sim = fresh()
	var before: Dictionary = sim.state.inventory.items.duplicate(true)
	result = sim.command("livelihood","work",{"id":"craft_workshop"})
	var completed: bool = result.ok and Driver.finish(sim)
	observations.append({"id":"craft_job_outputs","completed":completed,"inventory_before":before,"inventory_after":sim.state.inventory.items.duplicate(true),"cash":sim.state.economy.cash,"craft_skill":sim.state.player.skills.get("crafting",0)})
	var pools: Dictionary = {}
	for id in work.jobs:
		if work.jobs[id].has("tasks"): pools[id] = work.jobs[id].tasks.size()
	observations.append({"id":"authored_pools","tasks_per_job":pools,"rounds":5})
	var timings: Array = []
	for count in [20,100]:
		sim = fresh()
		var configured: Dictionary = sim.command("population","configure",{"values":{"count":count}})
		var generated: Dictionary = sim.command("population","generate")
		var enabled: Dictionary = sim.command("npc_agency","enable")
		var started := Time.get_ticks_msec()
		result = sim.command("clock","advance",{"minutes":60})
		timings.append({"npcs":count,"setup_ok":configured.ok and generated.ok and enabled.ok,"minutes":60,"milliseconds":Time.get_ticks_msec()-started,"advance_ok":result.ok})
	var output := {"date":"2026-10-28","audio":AudioServer.get_driver_name(),"inventory":inventory,"observations":observations,"timings":timings,"user_save_slots_modified":false}
	var file := FileAccess.open("E:/GoDot/.research/school-0.981/audit-2026-10-28/probe.json",FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(output,"\t")); file.close()
	print("MECHANICS_AUDIT_PROBE ",JSON.stringify(output))
	quit(0 if file != null and AudioServer.get_driver_name()=="Dummy" else 1)
