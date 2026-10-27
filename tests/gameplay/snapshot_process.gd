extends SceneTree
## Write a controlled fixture, quit, then restore and continue it in another process.
func _initialize() -> void:
	call_deferred("_run")

func _normalized(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))

func _run() -> void:
	var writing := ""
	var reading := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--write="): writing = arg.trim_prefix("--write=")
		if arg.begins_with("--read="): reading = arg.trim_prefix("--read=")
	var sim = root.get_node("Gameplay").make_simulation()
	if not writing.is_empty():
		sim.state.clock = sim.calendar.snapshot(9 * 60)
		sim.state.world.equipment = ["computer"]
		sim.command("npc_agency", "enable")
		for id in ["fixture_a", "fixture_b"]:
			if not sim.command("social", "generate", {"id":id,"template":"resident"}).ok: _finish(false, "write"); return
			var actor: Dictionary = sim.state.social.npcs[id]
			sim.services.npc_agency._cancel(actor, "cross_process_fixture")
			actor.schedule = []
			actor.activity = "idle"
			actor.decision = {"committed":false}
			actor.pinned_until = int(sim.state.clock.total_minutes)+2000
			actor.location = sim.state.world.location
			sim.services.npc_relationships._bond(id, "player").trust = 20.0
		var preparation := [
			["organizations","create",{"id":"creative_collective"}],
			["organizations","recruit",{"id":"creative_collective","npc":"fixture_a"}],
			["organizations","recruit",{"id":"creative_collective","npc":"fixture_b"}],
			["institutions","election",{"id":"creative_collective","candidates":["fixture_a","fixture_b"]}],
			["inventory","add",{"id":"book"}], ["inventory","add",{"id":"meal","quantity":2}],
			["social_rules","promise",{"id":"fixture_a","promise":"complete_project"}],
			["actions","perform",{"id":"read"}], ["economy","project",{"id":"website_order","minutes":60}],
			["social_rules","gathering",{"candidates":["fixture_a","fixture_b"]}],
			["economy","deposit",{"amount":50}],
			["world","travel",{"id":"apartment_hall"}], ["world","travel",{"id":"global_map"}],
			["character","substance",{"id":"stimulant"}],
			["world","travel",{"id":"apartment_hall"}], ["world","travel",{"id":"bedroom"}],
			["combat","start",{"npc":"fixture_a"}],
			["combat","action",{"action":"attack","move":"jab"}]]
		for action in preparation:
			if not sim.command(action[0], action[1], action[2]).ok: _finish(false, "write"); return
		var snapshot: Dictionary = sim.export_snapshot()
		var continuation := {"action":"recover"}
		if not sim.command("combat", "action", continuation).ok: _finish(false, "write"); return
		var city = root.get_node("Gameplay").make_simulation()
		city.state.clock = city.calendar.snapshot(1440+720)
		city.state.world.location = "north_beach"
		city.state.world.weather = "snow"
		city.state.world.temperature = -2
		var city_snapshot: Dictionary = city.export_snapshot()
		if not city.command("world","journey",{"id":"city_park"}).ok: _finish(false,"write"); return
		var file := FileAccess.open(writing, FileAccess.WRITE)
		if file == null: _finish(false, "write"); return
		file.store_string(JSON.stringify({"snapshot":snapshot,"continuation":continuation,"expected":_normalized(sim.export_snapshot()),"city_snapshot":city_snapshot,"city_expected":_normalized(city.export_snapshot())}))
		file.flush()
		file.close()
		_finish(true, "write")
	elif not reading.is_empty():
		var packet: Variant = JSON.parse_string(FileAccess.get_file_as_string(reading))
		if not packet is Dictionary: _finish(false, "read"); return
		if not sim.restore_snapshot(packet.get("snapshot", {})).ok: _finish(false, "read"); return
		if not sim.command("combat", "action", packet.get("continuation", {})).ok: _finish(false, "read"); return
		var city = root.get_node("Gameplay").make_simulation()
		if not city.restore_snapshot(packet.get("city_snapshot",{})).ok or not city.command("world","journey",{"id":"city_park"}).ok: _finish(false,"read"); return
		_finish(_normalized(sim.export_snapshot()) == packet.get("expected", {}) and _normalized(city.export_snapshot()) == packet.get("city_expected",{}), "read")
	else: _finish(false, "missing_path")

func _finish(ok: bool, mode: String) -> void:
	print("SNAPSHOT_PROCESS_RESULT ", JSON.stringify({"mode":mode,"ok":ok}))
	quit(0 if ok else 1)
