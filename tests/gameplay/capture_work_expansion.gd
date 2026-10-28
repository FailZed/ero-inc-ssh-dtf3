extends SceneTree
var directory := OS.get_environment("EROINC_ARTIFACTS").path_join("captures/work_expansion") if not OS.get_environment("EROINC_ARTIFACTS").is_empty() else "user://captures/work_expansion"
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
	RenderingServer.force_draw()
	check(root.get_texture().get_image().save_png(directory.path_join(name+".png")) == OK,"capture "+name)

func button(prefix: String) -> Button:
	for node in window.find_children("*","Button",true,false):
		if node.text.begins_with(prefix) and not node.disabled: return node
	return null

func tagged(key: String, value: Variant) -> Button:
	for node in window.find_children("*","Button",true,false):
		if node.has_meta(key) and node.get_meta(key) == value: return node
	return null

func select_job(id: String) -> void:
	var entry := tagged("job_id",id)
	check(entry != null,"real job selector entry: "+id)
	if entry != null: entry.grab_focus(); entry.pressed.emit()
	await settle()

func click(prefix: String) -> void:
	var target := button(prefix)
	check(target != null,"visible button: "+prefix)
	if target != null: target.pressed.emit()
	await settle()

func choice(index: int) -> void:
	await create_timer(0.20).timeout
	var target := tagged("work_choice",index)
	check(target != null and not target.disabled,"native challenge choice: "+str(index))
	if target != null and not target.disabled: target.pressed.emit()
	await settle()

func run() -> void:
	if AudioServer.get_driver_name() != "Dummy": quit(2); return
	DirAccess.make_dir_recursive_absolute(directory)
	DisplayServer.window_set_size(Vector2i(1366,768))
	gameplay = root.get_node("Gameplay")
	var session = root.get_node("GameSession")
	session.pause_autosave_runtime()
	var config := preload("res://scripts/mechanics/setup_config.gd").defaults()
	config.mode = "sandbox"
	config.difficulty = "normal"
	config.population.count = 8
	check(gameplay.begin_new_game(config) == OK,"real silent sandbox start")
	for i in range(12): await process_frame
	session.pause_autosave_runtime()
	current_scene._character_creation_modal._confirm.pressed.emit()
	await settle()
	session.pause_autosave_runtime()
	var sim = gameplay.simulation
	check(gameplay.phase == "free_roam","mirror confirmation enters the actual open world: "+str(gameplay.phase))
	var shell = current_scene._gameplay_shell
	shell.open_panel("work")
	var entry: Button
	for node in shell._body.find_children("*","Button",true,false):
		if node.get_meta("livelihood_entry","") == "jobs": entry = node; break
	check(entry != null,"new jobs reachable through actual work screen")
	if entry == null: finish(); return
	entry.pressed.emit()
	await settle()
	window = shell.get_child(-1)
	check(window._body.find_children("*","Button",true,false).filter(func(node): return node.has_meta("job_id")).size() == 35,"native selector contains thirty-five jobs")
	await select_job("tutor")
	await capture("jobs-and-promotion")
	# Controlled test fixture: demonstrate the skill filter and actual comparison task.
	sim.state.clock = sim.calendar.snapshot(900)
	sim.state.world.location = "bedroom"
	sim.state.world.equipment.append("camera")
	sim.state.player.needs.energy = 100.0
	var filter: OptionButton = window._body.find_children("*","OptionButton",true,false)[0]
	var filter_index: int = ["all"].size()+sim.catalog.skills.keys().find("photography")
	filter.select(filter_index)
	filter.item_selected.emit(filter_index)
	await settle()
	check(window._selected_job == "photo_reviewer","actual filter finds a job for the selected skill")
	await capture("skill-filter")
	await click("РАБОТАТЬ С МИНИ-ИГРОЙ")
	check(not sim.state.livelihood.pending.is_empty(),"native comparison start creates the actual task: "+str(window._status.text))
	if sim.state.livelihood.pending.is_empty(): finish(); return
	await capture("comparison")
	await choice(int(sim.state.livelihood.pending.tasks[0].answer))
	check(sim.state.livelihood.pending.correct == 1,"native difference button scores the actual changed cell")
	await click("ПРЕРВАТЬ")
	filter = window._body.find_children("*","OptionButton",true,false)[0]
	filter.select(0)
	filter.item_selected.emit(0)
	await settle()
	sim.state.player.skills.music = 640
	sim.state.player.needs.energy = 100
	await select_job("music_arranger")
	await click("РАБОТАТЬ С МИНИ-ИГРОЙ")
	if sim.state.livelihood.pending.is_empty(): finish(); return
	await capture("sequence")
	await choice(int(sim.state.livelihood.pending.tasks[0].order[0]))
	check(sim.state.livelihood.pending.selection.size() == 1,"native sequence stores a partial ordered choice")
	await capture("sequence-partial")
	await create_timer(0.20).timeout
	await click("ОТМЕНИТЬ")
	check(sim.state.livelihood.pending.selection.is_empty(),"native sequence undo works")
	for step in range(15):
		var p: Dictionary = sim.state.livelihood.pending
		if p.is_empty(): break
		await choice(int(p.tasks[int(p.round)].order[p.selection.size()]))
	check(sim.state.livelihood.pending.is_empty() and sim.state.livelihood.log[-1].quality == 1.0,"native sequence completes all five rounds")
	check(sim.state.livelihood.careers.music_arranger.xp == 55,"native good result receives skill-gated career acceleration")
	await capture("career-quality-reward")
	sim.state.player.skills.journalism = 1000
	sim.state.player.skills.discipline = 1000
	sim.state.player.needs.energy = 100
	await select_job("fact_checker")
	await click("РАБОТАТЬ С МИНИ-ИГРОЙ")
	if sim.state.livelihood.pending.is_empty(): finish(); return
	check(window._body.find_children("*","Button",true,false).filter(func(node): return node.has_meta("work_choice")).size() == 3,"expert reasoning keeps three visible alternatives")
	await capture("reasoning")
	var task: Dictionary = sim.state.livelihood.pending.tasks[0]
	for index in range(4):
		if index != int(task.answer) and index != int(task.excluded): await choice(index); break
	check(sim.state.livelihood.pending.correct == 0 and not window._status.text.is_empty(),"native wrong answer is scored and explained")
	await capture("reasoning-feedback")
	await click("ПРЕРВАТЬ")
	# Move the controlled world forward to Monday; no clock rewinds or user saves.
	sim.state.clock = sim.calendar.snapshot(1440+540)
	sim.state.world.location = "north_shops"
	sim.state.player.needs.energy = 100
	sim.state.player.skills.sales = 640
	await select_job("shop_assistant")
	var ordinary := button("СМЕНА")
	check(ordinary == null,"ordinary shift button is disabled by the real Monday class")
	var skip: CheckBox
	for candidate in window._body.find_children("*","CheckBox",true,false):
		if candidate.get_meta("focus_id","") == "skip_classes": skip = candidate; break
	check(skip != null,"intentional study skip has a visible explicit control")
	var scroll: ScrollContainer = window._body.get_parent()
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	await capture("study-conflict")
	if skip != null: skip.button_pressed = true
	await settle()
	await click("СМЕНА")
	check(sim.state.world.education.absences == 1,"native explicit skip changes actual attendance")
	await capture("study-skip-receipt")
	window._close()
	await settle()
	sim.state.clock = sim.calendar.snapshot(2880+540)
	sim.state.world.flags.subject_computing = true
	sim.state.world.location = "bedroom"
	sim.state.player.needs.energy = 100
	sim.services.careers.synchronize()
	shell._screen_state.work_tab = "jobs"
	shell.open_panel("work")
	await settle()
	var general: Button
	for candidate in shell._body.find_children("*","Button",true,false):
		var action: Dictionary = candidate.get_meta("gameplay_action",{})
		if action.get("module","") == "careers" and action.get("operation","") == "shift" and action.get("args",{}).get("id","") == "digital": general = candidate; break
	check(general != null and not general.disabled and general.get_meta("study_conflict",false),"general career conflict remains reachable through its actual action button")
	if general != null and not general.disabled: general.pressed.emit()
	await settle()
	window = shell.get_child(-1)
	check(window.has_signal("confirmed"),"general automatic work opens a real study-conflict decision")
	await capture("general-work-conflict")
	window.queue_free()
	finish()

func finish() -> void:
	print("WORK_EXPANSION_NATIVE_RESULT ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures,"audio":AudioServer.get_driver_name(),"size":[1366,768],"directory":directory}))
	quit(0 if failures.is_empty() else 1)
