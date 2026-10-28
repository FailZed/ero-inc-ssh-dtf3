extends SceneTree
const Driver = preload("res://tests/gameplay/work_driver.gd")
var gameplay
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures.append(text); printerr("FAIL: ",text)

func fresh(id: String = "shop_assistant"):
	var sim = gameplay.make_simulation()
	var job: Dictionary = sim.catalog.livelihood_rules.jobs[id]
	sim.state.world.location = job.location
	sim.state.clock = sim.calendar.snapshot(int(job.hours[0]))
	sim.state.world.equipment = ["computer","camera"]
	sim.state.economy.cash = 5000
	sim.state.player.skills[job.skill] = 10*int(job.min_skill)*int(job.min_skill)
	return sim

func normalized(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))

func run() -> void:
	if AudioServer.get_driver_name() != "Dummy": quit(2); return
	gameplay = root.get_node("Gameplay")
	root.get_node("GameSession").pause_autosave_runtime()
	var sim = fresh()
	var covered: Dictionary = {}
	for job in sim.catalog.livelihood_rules.jobs.values(): covered[job.skill] = true
	check(sim.configuration_error.is_empty() and sim.catalog.livelihood_rules.jobs.size() == 35 and covered.size() == 30,"thirty skills have real work applications in thirty-five jobs")
	for id in sim.catalog.skills: check(covered.has(id),"practical job for "+id)
	_test_careers()
	_test_schedule()
	_test_challenges()
	await _test_ui()
	print("WORK_EXPANSION_RESULT ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures,"audio":AudioServer.get_driver_name()}))
	quit(0 if failures.is_empty() else 1)

func _test_careers() -> void:
	var original_world = fresh()
	var original_snapshot: Dictionary = original_world.export_snapshot()
	var unknown := original_snapshot.duplicate(true)
	unknown.state.careers.professions.unknown = {"level":1,"xp":0,"reputation":0}
	check(not original_world.restore_snapshot(unknown).ok and original_snapshot == original_world.export_snapshot(),"unknown automatic profession is rejected without a runtime error or state mutation")
	unknown = original_snapshot.duplicate(true)
	unknown.state.livelihood.version = 1
	check(not original_world.restore_snapshot(unknown).ok and original_snapshot == original_world.export_snapshot(),"previous work-state format has no compatibility branch")
	var sim = fresh("cafe_orders")
	sim.state.livelihood.careers.cafe_orders = {"xp":600}
	check(sim.services.livelihood.career("cafe_orders").level == 1,"unskilled worker cannot turn experience alone into promotions")
	sim.state.player.skills.cooking = 160
	check(sim.services.livelihood.career("cafe_orders").level == 3,"banked experience is capped by actual skill")
	check(sim.services.livelihood.career("card_host").level == 1,"career experience cannot transfer to a different skill or job")
	sim = fresh()
	var unskilled: int = sim.services.livelihood.wage("shop_assistant",0.65)
	sim.state.player.skills.sales = 640
	check(sim.services.livelihood.career("shop_assistant").level == 5 and sim.services.livelihood.wage("shop_assistant",0.65) > unskilled,"automatic-only job rank and salary rise through skill without grinding shifts")
	check(sim.command("livelihood","work",{"id":"shop_assistant"}).ok and not sim.state.livelihood.careers.has("shop_assistant"),"automatic-only job never stores promotion experience")
	for expert in [false,true]:
		sim = fresh("tutor")
		if expert: sim.state.player.skills.study = 640
		check(sim.command("livelihood","work",{"id":"tutor"}).ok and Driver.finish(sim),"interactive career can complete: expert="+str(expert))
		check(sim.state.livelihood.careers.tutor.xp == (55 if expert else 30),"quality acceleration requires the next skill gate: expert="+str(expert))
	sim = fresh("tutor")
	sim.state.player.skills.study = 640
	check(sim.command("livelihood","work",{"id":"tutor","interactive":false}).ok and sim.state.livelihood.careers.tutor.xp == 12,"automatic option of an interactive job has no quality acceleration")
	sim = fresh("tutor")
	sim.state.player.skills.study = 640
	sim.command("livelihood","work",{"id":"tutor"})
	check(Driver.finish(sim,true) and sim.state.livelihood.careers.tutor.xp == 18,"expert with wrong answers receives no quality acceleration")
	sim = fresh("repair_bench")
	sim.state.player.skills.handiness = 0
	var original: Dictionary = sim.export_snapshot()
	check(sim.command("livelihood","work",{"id":"repair_bench"}).get("error","") == "work_skill_required" and original == sim.export_snapshot(),"specialized work enforces its entry skill atomically")
	sim = fresh()
	sim.state.world.location = "bedroom"
	for day in range(3):
		sim.state.clock = sim.calendar.snapshot(day*1440+800)
		sim.state.player.needs.energy = 100
		check(sim.command("careers","shift",{"id":"digital"}).ok,"general automatic profession obeys current rules")
	check(sim.state.careers.professions.digital.level == 1 and sim.state.careers.professions.digital.xp == 0,"general automatic profession cannot promote by shift experience")
	sim.state.player.skills.computing = 640
	check(sim.command("growth","need_toggle",{"id":"social","enabled":false}).ok and sim.state.careers.professions.digital.level == 5,"general profession rank follows the same skill gates")

func _test_schedule() -> void:
	var sim = fresh()
	sim.state.clock = sim.calendar.snapshot(1440+540)
	var saved: Dictionary = sim.export_snapshot()
	var conflicts: Array = sim.services.livelihood.study_conflicts("shop_assistant")
	check(conflicts.size() == 1 and conflicts[0].id == "common_day" and saved == sim.export_snapshot(),"study preview is pure and uses the real selected timetable")
	var result: Dictionary = sim.command("livelihood","work",{"id":"shop_assistant"})
	check(not result.ok and result.error == "work_conflicts_study" and saved == sim.export_snapshot(),"conflicting work rejects before fee, time, RNG or career changes")
	check(sim.command("livelihood","work",{"id":"shop_assistant","skip_classes":true}).ok and sim.state.world.education.absences == 1,"explicit class skip advances actual attendance and grade consequences")
	sim = fresh("race_marshal")
	sim.state.clock = sim.calendar.snapshot(1440+540)
	conflicts = sim.services.livelihood.study_conflicts("race_marshal")
	check(not conflicts.is_empty() and not conflicts[0].overlap and conflicts[0].commute > 0,"commute alone can make a shift conflict with class arrival")
	sim = fresh()
	sim.state.clock = sim.calendar.snapshot(2880+540)
	check(sim.services.livelihood.study_conflicts("shop_assistant").is_empty(),"unselected optional courses do not block work")
	sim.state.world.flags.subject_computing = true
	conflicts = sim.services.livelihood.study_conflicts("shop_assistant")
	check(conflicts.size() == 1 and conflicts[0].id == "computing_class","selected course blocks the same working window")
	sim.state.world.education.attended.append("computing_class:2")
	check(sim.services.livelihood.study_conflicts("shop_assistant").is_empty(),"already attended course is not counted twice")
	sim.state.world.education.attended.clear()
	sim.state.world.education.expelled = true
	check(sim.services.livelihood.study_conflicts("shop_assistant").is_empty(),"expelled character has no active class commitment")
	sim = fresh()
	sim.state.clock = sim.calendar.snapshot(1440+540)
	sim.state.world.location = "bedroom"
	check(sim.command("careers","shift",{"id":"digital"}).get("error","") == "work_conflicts_study","general career shift uses timetable protection")
	check(sim.command("careers","stream",{"id":"games","minutes":120}).get("error","") == "work_conflicts_study","stream duration participates in timetable protection")
	check(sim.command("careers","shift",{"id":"digital","skip_classes":true}).ok and sim.state.world.education.absences == 1,"general automatic work allows an explicit consequential skip")
	sim = fresh()
	sim.state.clock = sim.calendar.snapshot(1440+800)
	check(sim.services.livelihood.study_conflicts("shop_assistant").is_empty(),"afternoon work remains available after morning lessons")

func _test_challenges() -> void:
	for id in ["tutor","lab_assistant","music_arranger"]:
		var sim = fresh(id)
		check(sim.command("livelihood","work",{"id":id}).ok,"new challenge starts: "+id)
		check(sim.command("livelihood","input",Driver.answer(sim)).ok,"new challenge accepts actual input: "+id)
		var saved: Dictionary = normalized(sim.export_snapshot())
		var replay = fresh(id)
		check(replay.restore_snapshot(saved).ok,"new challenge restores partial round: "+id)
		check(Driver.finish(sim) and Driver.finish(replay) and normalized(sim.export_snapshot()) == normalized(replay.export_snapshot()),"restored task, payment, progression and RNG agree: "+id)
		var wrong = fresh(id)
		wrong.command("livelihood","work",{"id":id})
		check(Driver.finish(wrong,true) and wrong.state.livelihood.log[-1].quality == 0,"wrong inputs remain failures: "+id)
	var sim = fresh("music_arranger")
	sim.command("livelihood","work",{"id":"music_arranger"})
	sim.command("livelihood","input",Driver.answer(sim))
	var p: Dictionary = sim.state.livelihood.pending
	var saved: Dictionary = sim.export_snapshot()
	var duplicate := {"token":p.token,"round":p.round,"elapsed_ms":int(p.last)+300,"choice":int(p.selection[0])}
	check(not sim.command("livelihood","input",duplicate).ok and saved == sim.export_snapshot(),"sequence rejects reused stage without changing the task")
	check(sim.command("livelihood","input",{"token":p.token,"round":p.round,"elapsed_ms":int(p.last)+300,"action":"undo"}).ok and sim.state.livelihood.pending.selection.is_empty(),"sequence can undo the current partial order")
	for difficulty in ["easy","normal","hard"]:
		sim = fresh("tutor")
		sim.command("preferences","difficulty",{"id":difficulty})
		for skill in sim.catalog.skills: sim.state.player.skills[skill] = 1000
		sim.command("livelihood","work",{"id":"tutor"})
		p = sim.state.livelihood.pending
		var visible := 4-(1 if int(p.tasks[0].excluded) >= 0 else 0)
		check(visible == (4 if difficulty == "hard" else 3),"reasoning assistance preserves at least three meaningful choices on "+difficulty)
		check(Driver.finish(sim,true) and sim.state.livelihood.log[-1].quality == 0,"maximum assistance never answers reasoning tasks on "+difficulty)
	sim = fresh("lab_assistant")
	sim.command("livelihood","work",{"id":"lab_assistant"})
	saved = sim.export_snapshot()
	var bad := saved.duplicate(true)
	bad.state.livelihood.pending.tasks[0].candidate = bad.state.livelihood.pending.tasks[0].reference.duplicate()
	check(not sim.restore_snapshot(bad).ok and saved == sim.export_snapshot(),"corrupted comparison task is rejected atomically")
	bad = saved.duplicate(true)
	bad.main_schema = 7
	check(not sim.restore_snapshot(bad).ok and saved == sim.export_snapshot(),"previous gameplay schema has no migration path")
	sim = fresh("tutor")
	sim.command("livelihood","work",{"id":"tutor"})
	saved = sim.export_snapshot()
	bad = saved.duplicate(true)
	bad.state.livelihood.pending.tasks[0].options[0] = {}
	check(not sim.restore_snapshot(bad).ok and saved == sim.export_snapshot(),"malformed saved answer choices reject atomically without sorting mixed types")

func _test_ui() -> void:
	var original = gameplay.simulation
	gameplay.simulation = fresh()
	var window = load("res://scripts/ui/gameplay/livelihood_window.gd").new()
	root.add_child(window)
	await process_frame
	check(window._body.find_children("*","Button",true,false).filter(func(node): return node.has_meta("job_id")).size() == 35,"all jobs are reachable through the actual work selector")
	for id in ["tutor","lab_assistant","music_arranger"]:
		gameplay.simulation = fresh(id)
		gameplay.simulation.command("livelihood","work",{"id":id})
		window._refresh()
		await process_frame
		check(not window._body.find_children("*","Button",true,false).filter(func(node): return node.has_meta("work_choice")).is_empty(),"new challenge has actual player input controls: "+id)
	window.queue_free()
	await process_frame
	gameplay.simulation = original
