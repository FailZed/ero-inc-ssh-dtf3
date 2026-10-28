extends SceneTree
const Banks = preload("res://scripts/mechanics/work_task_banks.gd")
const Challenges = preload("res://scripts/mechanics/work_challenges.gd")
const Driver = preload("res://tests/gameplay/work_driver.gd")
var gameplay
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures.append(text); printerr("FAIL: ",text)

func fresh(id: String, raw: int = 0, xp: int = 0):
	var sim = gameplay.make_simulation()
	var job: Dictionary = sim.catalog.livelihood_rules.jobs[id]
	sim.state.clock = sim.calendar.snapshot(int(job.hours[0]))
	sim.state.world.location = job.location
	sim.state.world.equipment = ["computer","camera"]
	sim.state.economy.cash = 5000
	sim.state.player.skills[job.skill] = maxi(raw,10*int(job.min_skill)*int(job.min_skill))
	sim.state.livelihood.careers[id] = {"xp":xp}
	return sim

func bank_jobs() -> Array: return gameplay.make_simulation().catalog.work_task_banks.keys()

func normalized(value: Dictionary) -> Dictionary: return JSON.parse_string(JSON.stringify(value))
func prompts(sim) -> Array: return sim.state.livelihood.pending.tasks.map(func(task): return str(task.prompt))

func start(sim, id: String) -> bool:
	var result: Dictionary = sim.command("livelihood","work",{"id":id,"interactive":true})
	check(result.ok,"bank-backed shift starts: "+id+" "+str(result.get("error","")))
	return result.ok

func run() -> void:
	if AudioServer.get_driver_name()!="Dummy": quit(2); return
	gameplay = root.get_node("Gameplay")
	root.get_node("GameSession").pause_autosave_runtime()
	var sim = fresh("tutor")
	check(sim.configuration_error.is_empty(),"bank catalog is valid")
	var total := 0
	for id in sim.catalog.work_task_banks:
		var job: Dictionary = sim.catalog.livelihood_rules.jobs[id]
		check(not job.has("tasks") and job.task_bank==id and Banks.job_error(job,sim.catalog).is_empty(),"authored work uses the sole bank representation: "+id)
		var banks: Array = sim.catalog.work_task_banks[id]
		check(banks.size()==3 and banks.map(func(entry): return int(entry.min_rank))==[1,3,5] and banks.all(func(entry): return entry.tasks.size()==10),"every profession has three career banks of ten tasks: "+id)
		for bank in banks: total += bank.tasks.size()
	check(total==510 and sim.catalog.work_task_banks.size()==17,"seventeen professions have 510 authored tasks without duplicate flat catalogs")
	_test_tiers()
	_test_rotation()
	_test_saves()
	_test_invalid_data()
	await _test_ui()
	print("WORK_BANKS_RESULT ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures,"audio":AudioServer.get_driver_name()}))
	quit(0 if failures.is_empty() else 1)

func _test_tiers() -> void:
	for id in bank_jobs():
		for gate in [{"raw":0,"xp":0,"bank":"foundation"},{"raw":160,"xp":180,"bank":"professional"},{"raw":640,"xp":600,"bank":"expert"},{"raw":40,"xp":60,"bank":"foundation"},{"raw":360,"xp":360,"bank":"professional"},{"raw":159,"xp":180,"bank":"foundation"},{"raw":160,"xp":179,"bank":"foundation"},{"raw":639,"xp":600,"bank":"professional"},{"raw":640,"xp":599,"bank":"professional"},{"raw":1000,"xp":0,"bank":"foundation"},{"raw":0,"xp":600,"bank":"foundation"}]:
			var sim = fresh(id,gate.raw,gate.xp)
			var before: Dictionary = sim.export_snapshot()
			var info := Banks.info(sim,id)
			check(info.id==gate.bank and info.count==10,"bank follows both skill and career experience: "+id+" "+gate.bank)
			check(before==sim.export_snapshot(),"bank preview never consumes state or RNG")
			if not start(sim,id): continue
			var bank := Banks.bank(sim.catalog.livelihood_rules.jobs[id],sim.catalog,Banks.rank(sim.state,sim.catalog,id))
			var available: Array = bank.tasks.map(func(task): return str(task.prompt))
			check(prompts(sim).size()==5 and prompts(sim).all(func(prompt): return prompt in available),"shift freezes five questions from its eligible tier")
			check(Driver.finish(sim,true) and sim.state.livelihood.log[-1].quality==0,"wrong choices remain failures in every bank tier")
	for id in ["tutor","security_auditor","dance_assistant"]:
		for difficulty in ["easy","normal","hard"]:
			var sim = fresh(id,1000,600)
			sim.command("preferences","difficulty",{"id":difficulty})
			if not start(sim,id): continue
			var p: Dictionary = sim.state.livelihood.pending
			check(int(p.assistance.duration_ms)<=60000 and int(p.assistance.rounds)==5,"expert reading budget preserves time cap and five decisions: "+id+" "+difficulty)
			if sim.catalog.livelihood_rules.jobs[id].kind=="reasoning":
				check(p.tasks.all(func(task): return task.options.size()==4 and (int(task.excluded)<0 or int(task.excluded)!=int(task.answer))),"skill help cannot choose the answer: "+id+" "+difficulty)
			else:
				check(p.tasks.all(func(task): return task.options.size()==3 and task.order.size()==3) and p.selection.is_empty(),"skill help leaves three required sequence choices: "+difficulty)

func _test_rotation() -> void:
	for id in bank_jobs():
		var sim = fresh(id)
		if not start(sim,id): continue
		var first := prompts(sim)
		check(Driver.finish(sim),"first bank shift completes: "+id)
		if not start(sim,id): continue
		var second := prompts(sim)
		check(not second.any(func(prompt): return prompt in first),"two same-day shifts deal disjoint halves of a ten-task bank: "+id)
		check(Driver.finish(sim),"second bank shift completes: "+id)
		var next = fresh(id)
		next.state.clock = next.calendar.snapshot(1440+int(next.catalog.livelihood_rules.jobs[id].hours[0]))
		if not start(next,id): continue
		check(prompts(next)!=first and not prompts(next).all(func(prompt): return prompt in first),"next day's opening set rotates rather than repeating yesterday's first set")

func _test_saves() -> void:
	for id in bank_jobs():
		var sim = fresh(id,160,180)
		if not start(sim,id): continue
		check(sim.command("livelihood","input",Driver.answer(sim)).ok,"bank task accepts a real partial answer")
		var saved: Dictionary = normalized(sim.export_snapshot())
		var replay = fresh(id,160,180)
		check(replay.restore_snapshot(saved).ok,"unfinished tiered bank restores: "+id)
		check(Driver.finish(sim) and Driver.finish(replay) and normalized(sim.export_snapshot())==normalized(replay.export_snapshot()),"frozen bank content, order, wage and RNG agree after restore")
		var bad: Dictionary = saved.duplicate(true)
		bad.state.livelihood.pending.tasks[1] = bad.state.livelihood.pending.tasks[0].duplicate(true)
		var before: Dictionary = replay.export_snapshot()
		check(not replay.restore_snapshot(bad).ok and before==replay.export_snapshot(),"duplicate frozen question rejects atomically")
	for id in bank_jobs():
		var sim = fresh(id)
		if not start(sim,id): continue
		var saved: Dictionary = sim.export_snapshot()
		var expert: Dictionary = sim.catalog.work_task_banks[id][2].tasks[0]
		var bad := saved.duplicate(true)
		var injected: Dictionary = {"prompt":expert.prompt}
		if expert.has("answer"):
			injected.merge({"options":expert.options.duplicate(),"answer":int(expert.answer),"explanation":expert.explanation,"excluded":-1})
		else:
			injected.merge({"options":expert.steps.duplicate(),"order":[0,1,2]})
		bad.state.livelihood.pending.tasks[0] = injected
		check(not sim.restore_snapshot(bad).ok and sim.export_snapshot()==saved,"locked expert content rejects atomically: "+id)

func _test_invalid_data() -> void:
	var sim = fresh("tutor")
	var job: Dictionary = sim.catalog.livelihood_rules.jobs.tutor
	var old := job.duplicate(true)
	old.tasks = []
	check(Challenges.catalog_error(old,sim.catalog)=="superseded_work_task_field","superseded flat task data has no compatibility path")
	var invalid: Dictionary = sim.catalog.duplicate(true)
	invalid.work_task_banks.tutor[1].min_rank = 1
	check(not Banks.job_error(job,invalid).is_empty(),"ambiguous tier gates reject")
	invalid = sim.catalog.duplicate(true)
	invalid.work_task_banks.tutor[1].tasks[0].prompt = invalid.work_task_banks.tutor[0].tasks[0].prompt
	check(not Banks.job_error(job,invalid).is_empty(),"cross-tier prompt collisions reject")
	invalid = sim.catalog.duplicate(true)
	invalid.work_task_banks.tutor[2].time_factor = 10
	check(not Banks.job_error(job,invalid).is_empty(),"bank cannot silently disable the challenge clock")

func _test_ui() -> void:
	var original = gameplay.simulation
	gameplay.simulation = fresh("tutor",160,180)
	var window = load("res://scripts/ui/gameplay/livelihood_window.gd").new()
	window._selected_job = "tutor"
	root.add_child(window)
	await process_frame
	check(window._body.find_children("*","Label",true,false).any(func(node): return node.get_meta("work_task_bank","")=="professional" and node.text.contains("5 из 10")),"actual job card names the unlocked bank and its pool size")
	window.queue_free()
	gameplay.simulation = original
