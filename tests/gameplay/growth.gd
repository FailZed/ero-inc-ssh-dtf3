extends SceneTree
var gameplay
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, text: String) -> void:
	checks += 1
	if not value: failures.append(text); printerr("FAIL: ",text)

func fresh():
	var sim = gameplay.make_simulation()
	sim.state.clock = sim.calendar.snapshot(480)
	sim.state.world.location = "bedroom"
	sim.state.world.equipment = ["computer","stove","camera"]
	sim.state.economy.cash = 5000
	sim.state.player.points = 20
	sim.state.housing = {"residence":"apartment","properties":{"apartment":{"owned":false,"equipment":{},"tenants":[],"next_bill":45000,"arrears":0,"rent_income":0,"tenant_arrears":{},"original_homes":{},"layout":{}}}}
	return sim

func normal(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))

func run() -> void:
	gameplay = root.get_node("Gameplay")
	root.get_node("GameSession").pause_autosave_runtime()
	var sim = fresh()
	check(sim.configuration_error.is_empty() and sim.catalog.skills.size() == 30,"current catalog contains thirty valid skill practices")
	for id in sim.catalog.skills:
		sim = fresh()
		var spec: Dictionary = sim.catalog.skills[id]
		sim.state.world.location = spec.locations[0]
		var started := int(sim.state.clock.total_minutes)
		var result: Dictionary = sim.command("growth","practice",{"id":id})
		check(result.ok and int(sim.state.player.skills.get(id,0)) == int(spec.xp) and int(sim.state.clock.total_minutes) == started+int(spec.minutes),"real practice route trains skill: "+id+" "+str(result.get("error","")))
	_test_assistance()
	_test_needs()
	_test_habits()
	_test_work_care()
	_test_current_snapshots()
	await _test_ui()
	print("GROWTH_RESULT ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures,"audio":AudioServer.get_driver_name()}))
	quit(0 if failures.is_empty() else 1)

func _test_assistance() -> void:
	var best: Dictionary = {}
	for difficulty in ["easy","normal","hard"]:
		var sim = fresh()
		sim.command("preferences","difficulty",{"id":difficulty})
		var zero: Dictionary = sim.services.growth.work_assistance("cafe_orders")
		for id in sim.catalog.skills: sim.state.player.skills[id] = 1000000
		var high: Dictionary = sim.services.growth.work_assistance("cafe_orders")
		best[difficulty] = high
		check(high.help > zero.help and high.duration_ms > zero.duration_ms,"skill gives bounded help on "+difficulty)
		check(high.rounds >= 3 and high.rounds <= 5 and high.window <= 0.23 and high.duration_ms <= 60000,"maximum skill still leaves a challenge on "+difficulty)
		check(high.help <= sim.catalog.growth_rules.profiles[difficulty].help_cap,"profile caps skill assistance on "+difficulty)
	check(best.easy.help > best.normal.help and best.normal.help > best.hard.help,"difficulty sets distinct help ceilings")
	check(best.easy.rounds == 3 and best.normal.rounds >= 4 and best.hard.rounds == 5,"memory minimum challenge follows selected difficulty")
	var sim = fresh()
	sim.command("preferences","customize",{"values":{"minigame_floor":0.90,"skill_help_cap":0.40}})
	for id in sim.catalog.skills: sim.state.player.skills[id] = 1000000
	check(sim.services.growth.work_assistance("cafe_orders").help <= 0.100001,"custom minimum difficulty limits contradictory maximum help")
	sim = fresh()
	sim.state.world.location = "riverside_cafe"
	for id in sim.catalog.skills: sim.state.player.skills[id] = 1000000
	sim.command("preferences","difficulty",{"id":"easy"})
	check(sim.command("livelihood","work",{"id":"cafe_orders"}).ok,"expert can start the adapted memory game")
	var p: Dictionary = sim.state.livelihood.pending
	sim.command("livelihood","input",{"token":p.token,"round":0,"action":"ready"})
	var rounds := int(p.assistance.rounds)
	for i in range(rounds):
		p = sim.state.livelihood.pending
		sim.command("livelihood","input",{"token":p.token,"round":i,"choice":(int(p.tasks[i].answer)+1)%5,"elapsed_ms":300*(i+1)})
	check(sim.state.livelihood.totals.good_games == 0 and sim.state.livelihood.log[-1].quality == 0,"maximum skill does not correct wrong answers or grant perfect quality")
	sim = fresh()
	sim.state.player.skills.fitness = 1000000
	sim.state.player.stats.strength = 100
	sim.command("encounters","game_start",{"type":"strength"})
	sim.command("encounters","game_input",{"value":1.0})
	check(sim.state.encounters.game.status == "active","strong expert cannot win the strength game in one input")
	sim.command("encounters","game_input",{"value":1.0})
	check(sim.state.encounters.game.status == "active","strength game preserves its three-input minimum")
	sim.command("encounters","game_input",{"value":1.0})
	check(sim.state.encounters.game.status == "won","strength game remains reachable after assistance cap")
	sim = fresh()
	sim.state.player.skills.athletics = 1000000
	sim.command("encounters","game_start",{"type":"reaction"})
	var target := float(sim.state.encounters.game.target)
	sim.command("encounters","game_input",{"value":0.0 if target > 0.5 else 1.0})
	check(sim.state.encounters.game.status == "lost","expert can still miss the reaction target")

func _test_needs() -> void:
	var sim = fresh()
	sim.command("social","generate",{"id":"neighbor","age":23})
	var npc: Dictionary = sim.state.social.npcs.neighbor.duplicate(true)
	for id in sim.services.growth.NEED_IDS:
		sim.state.player.needs[id] = 0.0
		check(sim.command("growth","need_toggle",{"id":id,"enabled":false}).ok,"player can disable need: "+id)
		sim.services.character.adjust_need(id,-100)
		check(sim.state.player.needs[id] == 100 and not sim.state.player.need_warnings[id],"disabled need is neutral and cannot drain: "+id)
	check(npc == sim.state.social.npcs.neighbor,"need settings only affect the protagonist")
	var health := float(sim.state.player.needs.health)
	check(sim.command("clock","advance",{"minutes":600}).ok and sim.state.player.needs.health >= health,"disabled needs cannot cause damage through the clock")
	check(sim.services.needs.condition().warnings.is_empty() and sim.services.needs.condition().disabled_needs.size() == 7,"disabled needs leave no warnings and identify all hidden HUD fields")
	check(sim.command("growth","need_toggle",{"id":"hydration","enabled":true}).ok,"need can be re-enabled")
	sim.command("clock","advance",{"minutes":60})
	check(float(sim.state.player.needs.hydration) < 100,"re-enabled need resumes real decay")
	var before: Dictionary = sim.export_snapshot()
	check(not sim.command("growth","need_toggle",{"id":"health","enabled":false}).ok and before == sim.export_snapshot(),"health is preserved as a core resource")

func _test_habits() -> void:
	var sim = fresh()
	var before: Dictionary = sim.export_snapshot()
	check(not sim.command("growth","habit",{"id":"hydration"}).ok and before == sim.export_snapshot(),"habit requires actual related practice")
	sim.state.player.skills.fitness = 150
	sim.state.player.points = 6
	for i in range(3): check(sim.command("growth","habit",{"id":"hydration"}).ok,"habit has a purchasable rank "+str(i+1))
	check(sim.state.player.points == 0,"habit ranks consume one, two and three progression points")
	var control = fresh()
	sim.command("clock","advance",{"minutes":60})
	control.command("clock","advance",{"minutes":60})
	check(sim.state.player.needs.hydration > control.state.player.needs.hydration,"habit reduces actual need drain")
	sim.state.player.needs.hydration = 0.0
	control.state.player.needs.hydration = 0.0
	check(sim.services.needs.recovery_factor() > control.services.needs.recovery_factor() and sim.services.needs.mood_target() > control.services.needs.mood_target(),"habit also softens need penalties")
	before = sim.export_snapshot()
	check(not sim.command("growth","habit",{"id":"hydration"}).ok and before == sim.export_snapshot(),"habit cannot exceed the third rank")

func _test_work_care() -> void:
	var automatic = fresh()
	var interactive = fresh()
	for sim in [automatic,interactive]:
		for id in ["satiety","hydration","bladder","social"]: sim.state.player.needs[id] = 10.0
	automatic.state.world.location = "north_shops"
	interactive.state.world.location = "riverside_cafe"
	check(automatic.command("livelihood","work",{"id":"shop_assistant"}).ok,"automatic shift remains available")
	check(interactive.command("livelihood","work",{"id":"cafe_orders"}).ok,"interactive shift remains available")
	for id in ["satiety","hydration","bladder","social"]:
		check(float(automatic.state.player.needs[id]) > float(interactive.state.player.needs[id])+20,"automatic workplace care fulfils need: "+id)
	check(automatic.state.player.needs.energy < 100 and automatic.state.player.needs.rested < 100,"workplace care does not turn work into sleep or stamina regeneration")
	var sim = fresh()
	sim.state.world.location = "global_map"
	sim.state.player.needs.hydration = 10.0
	check(sim.command("careers","shift",{"id":"retail"}).ok and sim.state.player.needs.hydration > 50,"ordinary career shifts use the same workplace care")

func _test_current_snapshots() -> void:
	var sim = fresh()
	sim.state.world.location = "riverside_cafe"
	for id in sim.catalog.skills: sim.state.player.skills[id] = 1000
	sim.command("livelihood","work",{"id":"cafe_orders"})
	var saved: Dictionary = normal(sim.export_snapshot())
	var replay = fresh()
	check(replay.restore_snapshot(saved).ok and normal(replay.export_snapshot()) == saved,"current snapshot preserves exact frozen skill assistance")
	var bad := saved.duplicate(true)
	bad.state.growth.habits.hydration = 8
	check(not replay.restore_snapshot(bad).ok and normal(replay.export_snapshot()) == saved,"corrupt habit rank rejected atomically")
	bad = saved.duplicate(true)
	bad.main_schema = 6
	check(not replay.restore_snapshot(bad).ok,"earlier main schema is deliberately unsupported")

func _test_ui() -> void:
	var original = gameplay.simulation
	gameplay.simulation = fresh()
	var window = load("res://scripts/ui/gameplay/growth_window.gd").new()
	root.add_child(window)
	await process_frame
	check(window._body.find_children("*","Button",true,false).size() >= 30,"skill UI exposes practice for all thirty skills")
	window.page = "needs"
	window._refresh()
	check(window._body.find_children("*","CheckBox",true,false).size() == 7,"settings expose seven independent needs")
	for id in gameplay.simulation.services.growth.NEED_IDS: gameplay.simulation.command("growth","need_toggle",{"id":id,"enabled":false})
	var hud = load("res://scripts/ui/gameplay/player_hud.gd").new()
	root.add_child(hud)
	hud.present(gameplay.simulation.state.player,gameplay.simulation.services.needs.condition())
	check(not hud._needs_row.visible and hud._health.row.visible and hud._energy.row.visible,"HUD hides all disabled daily needs and retains core resources")
	window.page = "habits"
	window._refresh()
	check(window._body.find_children("*","Button",true,false).filter(func(node): return node.has_meta("habit_id")).size() == 7,"habit progression exposes the seven actual purchase controls")
	hud.queue_free()
	window.queue_free()
	await process_frame
	gameplay.simulation = original
