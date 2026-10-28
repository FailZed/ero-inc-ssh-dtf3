extends SceneTree
var directory := OS.get_environment("EROINC_ARTIFACTS").path_join("captures/growth") if not OS.get_environment("EROINC_ARTIFACTS").is_empty() else "user://captures/growth"
var gameplay
var window
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures.append(text); printerr("FAIL: ",text)

func settle() -> void:
	for i in range(4): await process_frame

func capture(name: String) -> void:
	await settle()
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory.path_join(name+".png")) == OK,"capture "+name)

func tagged(key: String, value: String) -> Button:
	for node in window.find_children("*","Button",true,false):
		if node.get_meta(key,"") == value: return node
	return null

func button(text: String) -> Button:
	for node in window.find_children("*","Button",true,false):
		if node.text.begins_with(text) and not node.disabled: return node
	return null

func run() -> void:
	if AudioServer.get_driver_name() != "Dummy": quit(2); return
	DirAccess.make_dir_recursive_absolute(directory)
	DisplayServer.window_set_size(Vector2i(1366,768))
	gameplay = root.get_node("Gameplay")
	var session = root.get_node("GameSession")
	session.pause_autosave_runtime()
	var config := preload("res://scripts/mechanics/setup_config.gd").defaults()
	config.mode = "sandbox"
	config.difficulty = "hard"
	config.population.count = 8
	config.needs = {"bladder":false,"social":false}
	check(gameplay.begin_new_game(config) == OK,"real sandbox starts with pre-game need choices")
	for i in range(12): await process_frame
	session.pause_autosave_runtime()
	current_scene._character_creation_modal._confirm.pressed.emit()
	await settle()
	session.pause_autosave_runtime()
	var sim = gameplay.simulation
	check(not sim.services.growth.enabled("bladder") and not sim.services.growth.enabled("social"),"pre-game need choices reach actual world")
	var shell = current_scene._gameplay_shell
	shell.open_panel("profile")
	var entry: Button
	for candidate in shell._body.find_children("*","Button",true,false):
		if candidate.get_meta("growth_entry","") == "skills": entry = candidate; break
	check(entry != null,"practice is reachable through actual profile")
	if entry == null: quit(1); return
	entry.pressed.emit()
	await settle()
	window = shell.get_child(-1)
	check(window.has_method("_skills"),"profile opens current skill window")
	await capture("skills")
	var practice := tagged("practice_id","study")
	check(practice != null and not practice.disabled,"study practice is available at home")
	var score := int(sim.state.player.skills.get("study",0))
	var started := int(sim.state.clock.total_minutes)
	if practice != null and not practice.disabled: practice.pressed.emit()
	await settle()
	check(int(sim.state.player.skills.study) == score+8 and int(sim.state.clock.total_minutes) == started+30,"native practice trains skill and advances shared clock")
	window.category = "body"
	window._refresh()
	await capture("physical-skills")
	# Controlled test fixture for displaying and buying all three habit tiers.
	sim.state.player.skills.fitness = 150
	sim.state.player.points = 6
	window.page = "habits"
	window._refresh()
	await settle()
	for rank in range(3):
		var buy := tagged("habit_id","hydration")
		check(buy != null and not buy.disabled,"native habit purchase is available: "+str(rank+1))
		if buy != null and not buy.disabled: buy.pressed.emit()
		await settle()
	check(sim.state.growth.habits.get("hydration",0) == 3 and sim.state.player.points == 0,"native habit purchases consume 1+2+3 points")
	await capture("habits")
	window.page = "needs"
	window._refresh()
	await settle()
	var water := tagged("need_id","hydration") as CheckBox
	check(water != null and water.button_pressed,"native need settings show current enabled state")
	if water != null:
		water.button_pressed = false
	await settle()
	check(not sim.services.growth.enabled("hydration"),"native checkbox disables hydration")
	await capture("needs")
	window.queue_free()
	await settle()
	shell.open_panel("place")
	await capture("hud-hidden-needs")
	# Fixture supplies low starting needs to demonstrate automatic workplace care.
	sim.state.clock = sim.calendar.snapshot(600)
	sim.state.world.location = "north_shops"
	sim.state.player.needs.satiety = 10.0
	sim.state.player.needs.rested = 80.0
	check(gameplay.execute("livelihood","work",{"id":"shop_assistant","interactive":false}).ok,"automatic shop shift completes")
	check(sim.state.player.needs.satiety > 10 and sim.state.player.needs.rested < 80,"automatic shift feeds character while preserving fatigue")
	shell.open_panel("health")
	await settle()
	for grid in shell._body.find_children("*","GridContainer",true,false):
		if grid.get_meta("need_meters",false):
			check(grid.get_child_count() == 7,"health screen hides three disabled needs")
			for meter in grid.get_children(): check(meter.size.x >= 250,"health meter uses available column width")
	await capture("after-auto-shift")
	shell.open_panel("place")
	sim.state.world.location = "riverside_cafe"
	sim.state.player.needs.energy = 100.0
	sim.state.player.skills.cooking = 1000
	sim.state.player.skills.discipline = 1000
	var changed: Dictionary = gameplay.execute("preferences","difficulty",{"id":"easy"})
	check(changed.ok,"select easy assistance profile: "+str(changed.get("error","")))
	var work: Dictionary = gameplay.execute("livelihood","work",{"id":"cafe_orders"})
	check(work.ok,"expert interactive job starts: "+str(work.get("error","")))
	if not work.ok:
		finish()
		return
	shell._open_livelihood()
	await settle()
	window = shell.get_child(-1)
	check(sim.state.livelihood.pending.assistance.rounds == 3,"expert memory task retains three rounds")
	await capture("expert-memory-preview")
	var ready := button("ЗАПОМНИЛ")
	check(ready != null,"expert preview has a real start button")
	if ready != null: ready.pressed.emit()
	await settle()
	await capture("expert-memory-play")
	for i in range(3):
		await create_timer(0.22).timeout
		var p: Dictionary = sim.state.livelihood.pending
		if p.is_empty(): break
		var wrong: String = sim.catalog.livelihood_rules.jobs[p.id].choices[(int(p.tasks[int(p.round)].answer)+1)%5]
		var answer := button(wrong)
		check(answer != null,"incorrect answer remains selectable by expert")
		if answer != null: answer.pressed.emit()
		await settle()
	check(sim.state.livelihood.pending.is_empty() and sim.state.livelihood.log[-1].quality == 0,"expert assistance does not turn incorrect inputs into success")
	await capture("expert-work-paid")
	finish()

func finish() -> void:
	print("GROWTH_NATIVE_RESULT ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures,"audio":AudioServer.get_driver_name(),"size":[1366,768],"directory":directory}))
	quit(0 if failures.is_empty() else 1)
