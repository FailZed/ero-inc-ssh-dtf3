extends RefCounted
var t
func _init(runner) -> void:
	t = runner

func _action(shell, module_id: String, operation: String, action_id: String = "") -> Button:
	for button in shell._body.find_children("*", "Button", true, false):
		var data: Dictionary = button.get_meta("gameplay_action", {})
		if data.get("module", "") == module_id and data.get("operation", "") == operation and (action_id.is_empty() or data.get("args", {}).get("action", data.get("args", {}).get("id", "")) == action_id): return button
	return null

func run() -> void:
	var initial_checks := int(t.checks)
	var invalid = load("res://scripts/gameplay/main_simulation.gd").new(1, {"digital_operations":{"bad":{"label":"Incomplete"}}})
	t.check(not invalid.configuration_error.is_empty() and not invalid.command("clock","advance",{"minutes":1}).ok, "main city setup preserves extended catalog validation errors")
	var original: Dictionary = t.dialogic.VAR.var_storage.World.duplicate(true)
	t.session.pause_autosave_runtime()
	t.fresh_world()
	t.gameplay.complete_chapter_one()
	var sim = t.gameplay.simulation
	sim.state.economy.cash = 1000
	sim.state.world.location = "bedroom"
	sim.state.world.equipment = ["computer", "stove"]
	sim.state.player.skills.computing = 150
	sim.services.careers.synchronize()
	# The fixture represents a completed birth supplied by the existing lifecycle.
	sim.state.healthcare.family.append({"parent":"asuka", "partner":"player", "minute":sim.state.clock.total_minutes,"care":20,"status":"dependent"})
	sim.services.family.initialize()
	sim.state.family.members.family_1.needs.food = 20.0
	t.gameplay._checkpoint()
	var scene := Control.new()
	t.root.add_child(scene)
	var shell = load("res://scripts/ui/gameplay/gameplay_shell.gd").new()
	scene.add_child(shell)
	await t.process_frame
	var before: Dictionary = sim.export_snapshot()
	shell.open_panel("family")
	t.check(before == sim.export_snapshot(), "family window previews do not mutate the real family or RNG")
	var button := _action(shell, "family", "care", "feed")
	t.check(button != null and not button.disabled, "actual family UI offers a playable feeding action")
	var minute := int(sim.state.clock.total_minutes)
	if button != null and not button.disabled: button.pressed.emit()
	t.check(sim.state.family.members.family_1.needs.food > 70 and int(sim.state.clock.total_minutes) == minute + 20, "actual family button advances common clock and restores child's need")
	t.check(int(t.session.get_game_time_snapshot().total_minutes) == int(sim.state.clock.total_minutes), "family care and GameSession clocks stay synchronized")
	shell.open_panel("digital")
	button = _action(shell, "digital", "scan", "training")
	t.check(button != null and not button.disabled, "main UI offers legal digital training")
	if button != null and not button.disabled: button.pressed.emit()
	t.check(not sim.state.digital.pending.is_empty(), "main digital button creates a real prepared report")
	shell.open_panel("digital")
	button = _action(shell, "digital", "resolve", "training")
	t.check(button != null and not button.disabled, "prepared operation has a real resolution button")
	if button != null and not button.disabled: button.pressed.emit()
	t.check(sim.state.digital.pending.is_empty() and sim.state.digital.history.size() == 1, "main digital operation records exactly one outcome")
	sim.command("character", "gain_xp", {"amount":100})
	sim.command("events", "claim_achievement", {"id":"first_level"})
	before = sim.export_snapshot()
	shell.open_panel("collection")
	await t.process_frame
	t.check(before == sim.export_snapshot(), "opening real gallery neither marks entries seen nor advances gameplay")
	var view_button: Button
	for item in shell._body.find_children("*", "Button", true, false):
		if item.text == "ПОСМОТРЕТЬ": view_button = item; break
	t.check(view_button != null, "gallery displays an unlocked playable entry")
	if view_button != null: view_button.pressed.emit()
	await t.process_frame
	t.check(not sim.state.collection.seen.is_empty(), "viewing from main gallery persists seen state")
	var textures: Array = shell._body.find_children("*", "TextureRect", true, false)
	t.check(not textures.is_empty(), "gallery renders an actual local image")
	var snapshot: Dictionary = sim.export_snapshot()
	var restored = t.gameplay.make_simulation()
	t.check(restored.restore_snapshot(JSON.parse_string(JSON.stringify(snapshot))).ok, "new family, digital history and gallery fit the main snapshot")
	t.check(JSON.parse_string(JSON.stringify(restored.export_snapshot())) == JSON.parse_string(JSON.stringify(snapshot)), "main snapshot retains all new systems exactly")
	# Previous main schemas are unsupported.
	var legacy := snapshot.duplicate(true)
	legacy.main_schema = 3
	legacy.catalog_hash = "unsupported-catalog"
	legacy.state.erase("family")
	legacy.state.erase("digital")
	legacy.state.erase("collection")
	legacy.state.player.skills.erase("cybersecurity")
	legacy.state.healthcare.family = []
	legacy.state.journal.ready_events = []
	t.check(not restored.restore_snapshot(legacy).ok, "outdated main catalog is rejected")
	t.check(not legacy.state.has("family"), "loading previous main schema does not rewrite the supplied snapshot")
	scene.queue_free()
	await t.process_frame
	t.dialogic.VAR.var_storage.World = original
	t.session._sync_game_time_from_dialogic()
	print("REMAINING_UI_RESULT ", JSON.stringify({"checks":int(t.checks)-initial_checks,"main_ui":true}))
