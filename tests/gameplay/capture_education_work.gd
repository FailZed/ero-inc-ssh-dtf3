extends SceneTree
const Education = preload("res://scripts/mechanics/education_schedule.gd")
const Schedule = preload("res://scripts/mechanics/work_schedule.gd")
var gameplay
var checks := 0
var failures: Array[String] = []
var directory := "E:/GoDot/.research/school-0.981/education-2026-10-28/captures"

func _initialize() -> void: call_deferred("run")

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures.append(text); printerr("FAIL: ",text)

func settle() -> void:
	for i in range(4): await process_frame
	await RenderingServer.frame_post_draw

func capture(id: String) -> void:
	await settle()
	check(root.get_texture().get_image().save_png(directory+"/"+id+".png") == OK,"capture "+id)

func run() -> void:
	if AudioServer.get_driver_name() != "Dummy": quit(2); return
	DirAccess.make_dir_recursive_absolute(directory)
	DisplayServer.window_set_size(Vector2i(1366,900))
	gameplay = root.get_node("Gameplay")
	var session = root.get_node("GameSession")
	session.pause_autosave_runtime()
	var setup = load("res://scripts/ui/gameplay/world_setup.gd").new()
	setup.configuration.mode = "sandbox"
	setup.page = 1
	root.add_child(setup)
	await settle()
	var toggle: CheckBox = setup._body.find_children("*","CheckBox",true,false).filter(func(node): return node.has_meta("education_enrolled"))[0]
	var scroll: ScrollContainer = setup._body.get_parent()
	scroll.ensure_control_visible(toggle)
	await capture("student-settings")
	check(not setup._next.disabled and setup._subject_checks.size() == 6,"native settings expose valid student setup")
	toggle.button_pressed = false
	await settle()
	var free_toggle: CheckBox = setup._body.find_children("*","CheckBox",true,false).filter(func(node): return node.has_meta("education_enrolled"))[0]
	scroll.ensure_control_visible(free_toggle)
	await capture("nonstudent-settings")
	check(not setup._next.disabled and not setup.configuration.sandbox.education.enrolled,"native nonstudent start stays available")
	setup.queue_free()
	await settle()
	var config := preload("res://scripts/mechanics/setup_config.gd").defaults()
	config.mode = "sandbox"
	config.population.count = 3
	check(gameplay.begin_new_game(config) == OK,"actual silent sandbox entry")
	for i in range(12): await process_frame
	session.pause_autosave_runtime()
	current_scene._character_creation_modal._confirm.pressed.emit()
	await settle()
	session.pause_autosave_runtime()
	var sim = gameplay.simulation
	check(gameplay.phase == "free_roam","actual mirror opens free world")
	var shell = current_scene._gameplay_shell
	# Controlled clock/location fixtures; these are actual game UI, not art references.
	sim.state.clock = sim.calendar.snapshot(1440+540)
	sim.state.world.location = "city_park"
	root.get_node("LocationManager").current_location_id = "city_park"
	var work = load("res://scripts/ui/gameplay/livelihood_window.gd").new()
	work._selected_job = "race_marshal"
	shell.add_child(work)
	await capture("work-with-commute")
	check(work._body.find_children("*","Label",true,false).any(func(node): return node.text.contains("Опоздание на")),"native job details distinguish late arrival")
	work.queue_free()
	await settle()
	for duration in [60,120]:
		var warning = load("res://scripts/ui/gameplay/work_schedule_window.gd").new()
		warning.conflicts = Schedule.conflicts(sim,"city_park",duration)
		shell.add_child(warning)
		await capture("forecast-late" if duration == 60 else "forecast-absence")
		check(warning.find_children("*","Button",true,false).any(func(node): return node.has_meta("confirm_work_skip") and node.get_global_rect().end.y <= root.get_visible_rect().end.y),"native work decision is reachable in viewport coordinates")
		warning.queue_free()
		await settle()
	sim.state.clock = sim.calendar.snapshot(1440+610)
	sim.state.world.location = "training_center"
	root.get_node("LocationManager").current_location_id = "training_center"
	shell._screen_state.activities_tab = "university"
	shell.open_panel("activities")
	await capture("late-lesson")
	check(shell._body.find_children("*","Label",true,false).any(func(node): return node.text.contains("Сейчас: 50 мин")),"native class card shows actual remaining lesson")
	Education.apply_plan(sim.state,false,[])
	shell._refresh()
	await capture("nonstudent-activities")
	check(not shell._body.find_children("*","Button",true,false).any(func(node): return node.get_meta("gameplay_action",{}).get("operation","") == "lesson"),"nonstudent has no hidden class controls")
	print("EDUCATION_NATIVE_RESULT ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures,"audio":AudioServer.get_driver_name(),"captures":7}))
	quit(0 if failures.is_empty() else 1)
