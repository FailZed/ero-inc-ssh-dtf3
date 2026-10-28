extends SceneTree
const Education = preload("res://scripts/mechanics/education_schedule.gd")
const Setup = preload("res://scripts/mechanics/setup_config.gd")
const Schedule = preload("res://scripts/mechanics/work_schedule.gd")
var gameplay
var session
var dialogic
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures.append(text); printerr("FAIL: ",text)

func fresh(minute: int = 600, day: int = 1, enrolled: bool = true):
	var sim = gameplay.make_simulation()
	sim.state.clock = sim.calendar.snapshot(day*1440+minute)
	sim.state.world.location = "training_center"
	Education.apply_plan(sim.state,enrolled,["computing","physics"] if enrolled else [])
	return sim

func run() -> void:
	if AudioServer.get_driver_name() != "Dummy": quit(2); return
	gameplay = root.get_node("Gameplay")
	session = root.get_node("GameSession")
	dialogic = root.get_node("Dialogic")
	session.pause_autosave_runtime()
	var original: Dictionary = dialogic.VAR.var_storage.duplicate(true)
	_test_configuration()
	_test_attendance()
	_test_work_forecast()
	_test_state_validation()
	_test_sandbox()
	await _test_setup_ui()
	dialogic.VAR.var_storage = original
	session._sync_game_time_from_dialogic()
	session._sync_character_profile_from_dialogic()
	print("EDUCATION_WORK_RESULT ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures,"audio":AudioServer.get_driver_name()}))
	quit(0 if failures.is_empty() else 1)

func _test_configuration() -> void:
	var config := Setup.defaults()
	config.mode = "sandbox"
	check(Setup.validate(config).ok and config.sandbox.education.subjects.size() == 3,"sandbox has an explicit moderate default study load")
	for subjects in [[],["computing"],["computing","computing"],["computing","unknown"],["computing","physics","statistics","genetics","behavior"],[1,"physics"]]:
		config.sandbox.education = {"enrolled":true,"subjects":subjects}
		check(not Setup.validate(config).ok,"invalid study selection rejected: "+str(subjects))
	config.sandbox.education = {"enrolled":false,"subjects":[]}
	check(Setup.validate(config).ok,"nonstudent open-world setup is valid")
	config.sandbox.education.subjects = ["physics"]
	check(not Setup.validate(config).ok,"nonstudent cannot carry hidden selected lessons")
	config.sandbox.education = {"enrolled":true,"subjects":["computing","physics"]}
	check(Setup.validate(config).ok,"two selected subjects are valid")
	config.sandbox.education.subjects = ["computing","physics","statistics","genetics"]
	check(Setup.validate(config).ok,"four selected subjects are valid")

func _test_attendance() -> void:
	for minute in [599,600,601,615,616,650,660]:
		var sim = fresh(minute)
		var before: Dictionary = sim.export_snapshot()
		var result: Dictionary = sim.command("world","lesson",{"id":"common_day"})
		var allowed: bool = minute >= 600 and minute <= 615
		check(result.ok == allowed,"attendance boundary at %d matches the 15-minute admission policy" % minute)
		if allowed:
			check(sim.state.clock.minute_of_day == 660,"late attendance still ends at 11:00: %d" % minute)
			check(int(result.data.minutes) == 660-minute and int(result.data.late_minutes) == minute-600,"actual lesson reports remaining duration and lateness")
			check(sim.state.world.education.absences == 0 and sim.state.world.education.attended == ["common_day:1"],"attendance prevents a closing-time absence")
			check(int(sim.state.player.skills.study) == int(result.data.xp) and int(result.data.xp) == floori(15.0*(660-minute)/60),"late skill reward follows actual participation")
			check(is_equal_approx(float(sim.state.world.education.grade),snappedf(2.0*(660-minute)/60,0.01)),"late academic reward follows actual participation without a one-minute rounding cliff")
		else:
			check(before == sim.export_snapshot(),"rejected entry does not mutate time, reward, RNG or attendance")
	var sim = fresh(616)
	check(sim.command("clock","advance",{"minutes":44}).ok and sim.state.world.education.absences == 1,"absence is recorded at the scheduled end, not the admission deadline")
	check(sim.command("clock","advance",{"minutes":1}).ok and sim.state.world.education.absences == 1,"absence is never counted twice")
	var saved: Dictionary = sim.export_snapshot()
	check(not sim.command("world","lesson",{"id":"common_day"}).ok and saved == sim.export_snapshot(),"a missed class cannot be rescued after closure")
	sim = fresh(615,2)
	check(sim.command("world","lesson",{"id":"computing_class"}).ok and sim.state.clock.minute_of_day == 660,"late first subject finishes before the next class")
	check(sim.command("world","lesson",{"id":"physics_class"}).ok and sim.state.clock.minute_of_day == 720,"consecutive selected classes can both be attended")
	check(sim.state.world.education.absences == 0,"back-to-back lessons do not create phantom absences")
	sim = fresh(650)
	sim.state.world.education.expelled = true
	check(sim.command("clock","advance",{"minutes":10}).ok and sim.state.world.education.absences == 0,"expelled student accrues no new class obligations")
	check(sim.command("world","lesson",{"id":"common_day"}).get("error","") == "education_expelled","expulsion still blocks attendance")

func _test_work_forecast() -> void:
	for arrival in [599,600,601,615,616,650,660]:
		var sim = fresh(540)
		var conflicts := Schedule.conflicts(sim,"training_center",arrival-540)
		check(conflicts.is_empty() == (arrival <= 600),"work arriving on time needs no exception: %d" % arrival)
		if not conflicts.is_empty():
			var forecast: Dictionary = conflicts[0]
			check(forecast.arrival == 1440+arrival and forecast.deadline == 1440+615,"forecast exposes actual arrival and admission deadline")
			check(forecast.can_attend == (arrival <= 615),"forecast distinguishes reduced late attendance from unavoidable absence")
			var actual: Dictionary = Education.attendance(sim.catalog.lessons.common_day,sim.calendar.snapshot(forecast.arrival))
			check(actual.allowed == forecast.can_attend,"forecast admission agrees with actual class entry")
	var sim = fresh(540)
	sim.state.world.location = "city_park"
	var conflicts: Array = sim.services.livelihood.study_conflicts("race_marshal")
	check(conflicts.size() == 1 and not conflicts[0].overlap and conflicts[0].commute > 0,"commute alone produces an explicit late-arrival warning")
	check(conflicts[0].can_attend and conflicts[0].consequence == "late","short commute predicts lateness rather than pretending class is already missed")
	var before: Dictionary = sim.export_snapshot()
	check(sim.command("livelihood","work",{"id":"race_marshal","interactive":false}).get("error","") == "work_conflicts_study" and before == sim.export_snapshot(),"late work requires an explicit decision before changing the world")
	check(sim.command("livelihood","work",{"id":"race_marshal","interactive":false,"skip_classes":true}).ok,"player can deliberately accept the late work forecast")
	check(sim.command("world","journey",{"id":"training_center"}).ok,"predicted campus journey is actually traversable")
	var result: Dictionary = sim.command("world","lesson",{"id":"common_day"})
	check(result.ok and result.data.late_minutes == conflicts[0].late_minutes and sim.state.world.education.absences == 0,"real work, return journey and attendance match the forecast")
	sim = fresh(540)
	sim.state.world.location = "north_shops"
	check(sim.command("livelihood","work",{"id":"shop_assistant","interactive":false,"skip_classes":true}).ok and sim.state.world.education.absences == 1,"a longer deliberate shift causes one real absence")
	sim = fresh(540,2)
	Education.apply_plan(sim.state,true,["physics","genetics"])
	check(Schedule.conflicts(sim,"training_center",90).is_empty(),"unselected morning subject does not block work")
	sim = fresh(540)
	sim.state.world.education.attended.append("common_day:1")
	check(Schedule.conflicts(sim,"training_center",120).is_empty(),"attended lessons do not block another shift")
	sim.state.world.education.attended.clear()
	sim.state.world.education.expelled = true
	check(Schedule.conflicts(sim,"training_center",120).is_empty(),"expelled student has no forecast class obligation")
	sim = fresh(540,1,false)
	check(Schedule.conflicts(sim,"training_center",480).is_empty(),"nonstudent has no hidden work conflicts")
	sim.state.world.location = "bedroom"
	check(sim.command("world","homework").get("error","") == "education_not_enrolled","nonstudent cannot farm academic rewards through homework")
	var replay = fresh()
	check(replay.restore_snapshot(JSON.parse_string(JSON.stringify(sim.export_snapshot()))).ok and not replay.state.world.flags.student_enrolled,"nonstudent state persists through exact current snapshot")

func _test_sandbox() -> void:
	for enrolled in [true,false]:
		var config := Setup.defaults()
		config.mode = "sandbox"
		config.population.count = 2
		config.sandbox.education = {"enrolled":enrolled,"subjects":["physics","genetics"] if enrolled else []}
		gameplay._pending_configuration = config.duplicate(true)
		dialogic.clear(DialogicGameHandler.ClearFlags.FULL_CLEAR)
		session.reset_game_time()
		session.reset_character_profile()
		check(gameplay.phase == "story" and gameplay.story_flags.modal == "creator","education setting does not bypass the mirror")
		var profile: Dictionary = session.get_character_profile()
		profile.identity.full_name = "Тестовый студент" if enrolled else "Тестовый житель"
		var created: bool = session.apply_character_profile_v2(profile)
		var opened: Dictionary = gameplay.open_sandbox()
		check(created and opened.ok,"configured sandbox opens after mirror: "+str(opened))
		if not opened.ok: continue
		var sim = gameplay.simulation
		check(sim.state.world.flags.student_enrolled == enrolled,"sandbox applies chosen education status")
		for id in Education.SUBJECTS:
			check(sim.state.world.flags["subject_"+id] == (enrolled and id in ["physics","genetics"]),"sandbox activates only explicitly selected subject: "+id)
		check(not gameplay.apply_curriculum(["computing","statistics"],"running"),"story curriculum signal cannot overwrite sandbox choices")
		var stored: Dictionary = dialogic.VAR.var_storage.World.duplicate(true)
		gameplay._on_time_reset(session.get_game_time_snapshot())
		check(gameplay.restore_error.is_empty() and gameplay.configuration.sandbox.education == config.sandbox.education and gameplay.simulation.state.world.flags == stored.gameplay.state.world.flags,"checkpoint restores setup and actual enrollment together")
		if not enrolled:
			check(gameplay.execute("clock","advance",{"minutes":2*1440}).ok and gameplay.simulation.state.world.education.absences == 0,"nonstudent lives through scheduled weekdays without hidden absences")

func _test_state_validation() -> void:
	var sim = fresh()
	var saved: Dictionary = sim.export_snapshot()
	for change in [{"student_enrolled":"yes"},{"subject_physics":null},{"student_enrolled":false}]:
		var bad: Dictionary = saved.duplicate(true)
		bad.state.world.flags.merge(change,true)
		check(not sim.restore_snapshot(bad).ok and sim.export_snapshot() == saved,"invalid education state rejects atomically: "+str(change))
	var old: Dictionary = saved.duplicate(true)
	old.main_schema = 8
	check(sim.restore_snapshot(old).get("error","") == "unsupported_main_schema" and sim.export_snapshot() == saved,"previous main schema is rejected without a migration")
	gameplay.simulation = sim
	gameplay.configuration = Setup.defaults()
	gameplay.phase = "story"
	check(gameplay.apply_curriculum(["computing","physics"],"running") and sim.state.world.flags.student_enrolled,"authored story curriculum still uses the same selected-subject rules")
	saved = sim.export_snapshot()
	check(not gameplay.apply_curriculum(["computing","computing"],"running") and sim.export_snapshot() == saved,"invalid story curriculum cannot mutate a valid plan")

func _test_setup_ui() -> void:
	var setup = load("res://scripts/ui/gameplay/world_setup.gd").new()
	setup.configuration.mode = "sandbox"
	setup.page = 1
	root.add_child(setup)
	await process_frame
	check(setup._subject_checks.size() == 6,"all six subjects are reachable before sandbox starts")
	setup._subject_checks.statistics.button_pressed = false
	setup._subject_checks.physics.button_pressed = false
	check(setup._next.disabled,"real start control blocks a student with fewer than two subjects")
	setup._go_back()
	check(setup.page == 0 and not setup._next.disabled,"incomplete study plan does not trap Back navigation on the population page")
	setup._go_next()
	check(setup.page == 1 and setup._next.disabled,"returning to study settings preserves the incomplete selection for correction")
	setup._subject_checks.physics.button_pressed = true
	check(not setup._next.disabled,"restoring a valid subject selection enables start")
	setup._subject_checks.statistics.button_pressed = true
	setup._subject_checks.genetics.button_pressed = true
	check(setup._subject_checks.behavior.disabled and setup._subject_checks.bioengineering.disabled,"real controls enforce the four-subject maximum")
	var toggle: CheckBox = setup._body.find_children("*","CheckBox",true,false).filter(func(node): return node.has_meta("education_enrolled"))[0]
	toggle.button_pressed = false
	await process_frame
	check(not setup._next.disabled and not setup.configuration.sandbox.education.enrolled and setup.configuration.sandbox.education.subjects.is_empty(),"real student toggle clears hidden subject obligations")
	setup.queue_free()
	await process_frame
