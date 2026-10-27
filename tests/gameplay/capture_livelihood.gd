extends SceneTree
var directory := "E:/GoDot/.research/school-0.981/livelihood-2026-10-27/captures"
var gameplay
var window
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures.append(text); printerr("FAIL: ",text)

func capture(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory.path_join(name+".png")) == OK,"capture "+name)

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
	check(gameplay.begin_new_game(config) == OK,"real sandbox start")
	for i in range(12): await process_frame
	session.pause_autosave_runtime()
	current_scene._character_creation_modal._confirm.pressed.emit()
	for i in range(5): await process_frame
	session.pause_autosave_runtime()
	var shell = current_scene._gameplay_shell
	shell.open_panel("work")
	var entry: Button
	for candidate in shell._body.find_children("*","Button",true,false):
		if candidate.get_meta("livelihood_entry","") == "jobs": entry = candidate; break
	check(entry != null,"new work entry is reachable through actual money screen")
	if entry == null: quit(1); return
	if entry != null: entry.pressed.emit()
	await process_frame
	window = shell.get_child(-1)
	check(window.has_method("_jobs"),"main work button opens actual work window")
	await capture("jobs")
	for page in ["orders","goals","home"]:
		window.page = page
		window._refresh()
		await capture(page)
	window.page = "jobs"
	window._selected_job = "unlicensed_stall"
	window._refresh()
	await process_frame
	var scroll: ScrollContainer = window._body.get_parent()
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	await capture("illicit-jobs")
	check(gameplay.execute("world","journey",{"id":"riverside_cafe"}).ok,"actual travel to cafe workplace")
	window._selected_job = "cafe_orders"
	window._refresh()
	await process_frame
	var start := button("РАБОТАТЬ С МИНИ-ИГРОЙ")
	check(start != null,"present workplace enables mini-game button")
	if start != null: start.pressed.emit()
	await process_frame
	await capture("memory-preview")
	var ready := button("ЗАПОМНИЛ")
	check(ready != null,"memory preview has actual ready button")
	if ready != null: ready.pressed.emit()
	await process_frame
	window._toggle_pause()
	var paused: int = window._elapsed()
	await create_timer(0.25).timeout
	check(window._elapsed() == paused,"paused mini-game clock is frozen")
	await capture("work-pause")
	window._toggle_pause()
	await capture("memory-play")
	for i in range(5):
		await create_timer(0.22).timeout
		var p: Dictionary = gameplay.simulation.state.livelihood.pending
		if p.is_empty(): break
		var answer: String = gameplay.simulation.catalog.livelihood_rules.jobs[p.id].choices[int(p.tasks[int(p.round)].answer)]
		var answer_button := button(answer)
		check(answer_button != null,"visible correct answer "+str(i))
		if answer_button != null: answer_button.pressed.emit()
		await process_frame
	check(gameplay.simulation.state.livelihood.pending.is_empty() and gameplay.simulation.state.livelihood.totals.good_games == 1,"real native buttons complete work and issue quality reward")
	await capture("work-paid")
	check(gameplay.execute("world","journey",{"id":"north_shops"}).ok,"travel to technical workplace")
	# Controlled rendering fixture: demonstrate the second career tier.
	gameplay.simulation.state.player.skills.handiness = 40
	check(gameplay.execute("livelihood","work",{"id":"repair_bench"}).ok,"technical mini-game can start after career gate")
	await capture("focus-play")
	var cancel := button("ПРЕРВАТЬ")
	check(cancel != null,"technical job has visible cancellation")
	if cancel != null: cancel.pressed.emit()
	await process_frame
	window._close()
	await process_frame
	shell.open_panel("work")
	check(not shell._body.find_children("*","Button",true,false).is_empty(),"current work and money screen remains available")
	print("LIVELIHOOD_NATIVE_RESULT ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures,"audio":AudioServer.get_driver_name(),"size":[1366,768],"directory":directory}))
	quit(0 if failures.is_empty() else 1)
