extends SceneTree
const Driver = preload("res://tests/gameplay/work_driver.gd")
var gameplay

func _initialize() -> void: call_deferred("run")
func normalized(value: Dictionary) -> Dictionary: return JSON.parse_string(JSON.stringify(value))

func fresh(id: String):
	var sim = gameplay.make_simulation()
	var job: Dictionary = sim.catalog.livelihood_rules.jobs[id]
	sim.state.clock = sim.calendar.snapshot(int(job.hours[0]))
	sim.state.world.location = job.location
	sim.state.world.equipment = ["computer","camera"]
	sim.state.economy.cash = 5000
	sim.state.player.skills[job.skill] = 640
	sim.state.livelihood.careers[id] = {"xp":600}
	return sim

func run() -> void:
	gameplay = root.get_node("Gameplay")
	root.get_node("GameSession").pause_autosave_runtime()
	if AudioServer.get_driver_name()!="Dummy": finish(false,"audio"); return
	var mode := ""
	var path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--write="): mode = "write"; path = argument.trim_prefix("--write=")
		if argument.begins_with("--read="): mode = "read"; path = argument.trim_prefix("--read=")
	if mode=="write":
		var cases: Array = []
		for id in gameplay.make_simulation().catalog.work_task_banks:
			var sim = fresh(id)
			if not sim.command("livelihood","work",{"id":id,"interactive":true}).ok: finish(false,"start"); return
			if not sim.command("livelihood","input",Driver.answer(sim)).ok: finish(false,"partial"); return
			var saved := normalized(sim.export_snapshot())
			if not Driver.finish(sim): finish(false,"continuation"); return
			cases.append({"id":id,"saved":saved,"expected":normalized(sim.export_snapshot())})
		var file := FileAccess.open(path,FileAccess.WRITE)
		if file==null: finish(false,"fixture"); return
		file.store_string(JSON.stringify(cases))
		file.close()
		finish(true,"write")
	elif mode=="read":
		var cases: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not cases is Array or cases.size()!=17: finish(false,"fixture"); return
		for item in cases:
			var sim = fresh(str(item.id))
			if not sim.restore_snapshot(item.saved).ok or not Driver.finish(sim) or normalized(sim.export_snapshot())!=item.expected: finish(false,"replay_"+str(item.id)); return
		finish(true,"read")
	else: finish(false,"arguments")

func finish(ok: bool, stage: String) -> void:
	print("WORK_BANKS_SNAPSHOT_RESULT ",JSON.stringify({"ok":ok,"stage":stage,"cases":17,"audio":AudioServer.get_driver_name()}))
	quit(0 if ok else 1)
