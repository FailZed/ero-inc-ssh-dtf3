extends SceneTree
var gameplay

func _initialize() -> void: call_deferred("run")
func normalized(value: Dictionary) -> Dictionary: return JSON.parse_string(JSON.stringify(value))

func continue_work(sim) -> bool:
	if not sim.command("clock","advance",{"minutes":30}).ok: return false
	sim.services.npc_agency._cancel(sim.state.social.npcs.worker,"fixture_end")
	return sim.services.npc_agency.employment_view("worker").rank==2

func run() -> void:
	gameplay = root.get_node("Gameplay")
	root.get_node("GameSession").pause_autosave_runtime()
	if AudioServer.get_driver_name()!="Dummy": finish(false,"audio"); return
	var mode := ""
	var path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--write="): mode = "write"; path = argument.trim_prefix("--write=")
		if argument.begins_with("--read="): mode = "read"; path = argument.trim_prefix("--read=")
	var sim = gameplay.make_simulation()
	if mode=="write":
		sim.state.preferences.disabled_tags.append("adult")
		sim.state.clock = sim.calendar.snapshot(1440+540)
		if not sim.command("social","generate",{"id":"worker","name":"Тестовый работник","age":25}).ok: finish(false,"generate"); return
		var npc: Dictionary = sim.state.social.npcs.worker
		npc.biography.role = "worker"
		npc.schedule = []
		npc.skills.sales = 39
		if not sim.command("npc_agency","enable").ok: finish(false,"enable"); return
		if npc.mind.employment.job!="shop_assistant": finish(false,"occupation"); return
		sim.services.npc_agency._cancel(npc,"fixture_start")
		npc.location = "north_shops"
		sim.services.npc_agency._start(npc,"work","north_shops","","fixture")
		if not sim.command("clock","advance",{"minutes":30}).ok: finish(false,"partial"); return
		var saved: Dictionary = normalized(sim.export_snapshot())
		if not continue_work(sim): finish(false,"continuation"); return
		var file := FileAccess.open(path,FileAccess.WRITE)
		if file==null: finish(false,"fixture"); return
		file.store_string(JSON.stringify({"saved":saved,"expected":normalized(sim.export_snapshot())}))
		file.close()
		finish(true,"write")
	elif mode=="read":
		var packet: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not packet is Dictionary or not sim.restore_snapshot(packet.saved).ok: finish(false,"restore"); return
		var view: Dictionary = sim.services.npc_agency.employment_view("worker")
		if view.rank!=1 or sim.state.social.npcs.worker.mind.active.phase!="action": finish(false,"partial_state"); return
		finish(continue_work(sim) and normalized(sim.export_snapshot())==packet.expected,"read")
	else: finish(false,"arguments")

func finish(ok: bool, stage: String) -> void:
	print("NPC_EMPLOYMENT_SNAPSHOT_RESULT ",JSON.stringify({"ok":ok,"stage":stage,"audio":AudioServer.get_driver_name()}))
	quit(0 if ok else 1)
