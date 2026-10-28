extends SceneTree
const Simulation = preload("res://scripts/gameplay/main_simulation.gd")
const Presentation = preload("res://scripts/gameplay/presentation.gd")
const Social = preload("res://scripts/gameplay/social_presentation.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, description: String) -> void:
	checks += 1
	if not value: failures.append(description); printerr("FAIL: ",description)

func fixture(seed: int = 42):
	return preload("res://tests/gameplay/companion_fixture.gd").fixture(seed)

func accepted_fixture():
	return preload("res://tests/gameplay/companion_fixture.gd").accepted_fixture()

func _run() -> void:
	root.get_node("GameSession").pause_autosave_runtime()
	var sim = fixture()
	check(sim.configuration_error.is_empty(),"catalog valid")
	check(sim.validate_state(sim.state).ok,"new companion state validates")
	var before: Dictionary = sim.export_snapshot()
	check(sim.services.companion.preview("friend","hand").blocked.is_empty(),"friend eligible")
	check(sim.export_snapshot()==before,"preview consumes no time or RNG")
	var npc: Dictionary = sim.state.social.npcs.friend
	npc.location = "global_map"
	before = sim.export_snapshot()
	check(not sim.command("companion","offer",{"id":"friend","gesture":"hand"}).ok,"remote offer rejected")
	check(before==sim.export_snapshot(),"rejected offer atomic")
	npc = sim.state.social.npcs.friend
	npc.location = sim.state.world.location
	npc.mind.boundaries.contact = false
	check(sim.services.companion.preview("friend","hand").blocked=="contact_boundary","contact boundary respected")
	npc.mind.boundaries.contact = true
	npc.mind.boundaries.romance = false
	check(sim.services.companion.preview("friend","face").blocked=="romantic_boundary","romantic boundary respected")
	npc.health = 5
	check(sim.services.companion.preview("friend","hand").blocked=="npc_needs_recovery","health respected")
	sim = accepted_fixture()
	var token: int = sim.state.companion.active.token
	before = sim.export_snapshot()
	check(not sim.command("clock","advance",{"minutes":60}).ok,"active moment blocks unrelated time skip")
	check(before==sim.export_snapshot(),"blocked time skip atomic")
	check(not sim.command("companion","finish",{"token":token,"zone":"face","duration":1.0}).ok,"unagreed zone rejected")
	check(before==sim.export_snapshot(),"unagreed gesture atomic")
	check(not sim.command("companion","finish",{"token":token,"zone":"hand_l","duration":NAN}).ok,"nonfinite gesture rejected")
	var restored = fixture()
	check(restored.restore_snapshot(JSON.parse_string(JSON.stringify(before))).ok,"active moment restores from JSON")
	check(JSON.parse_string(JSON.stringify(restored.state.companion.active))==JSON.parse_string(JSON.stringify(sim.state.companion.active)),"restored consent names same NPC and gesture")
	var old_trust: float = sim.services.npc_relationships.view("friend","player").trust
	var result: Dictionary = sim.command("companion","finish",{"token":token,"zone":"hand_l","duration":1.0})
	check(result.ok and result.data.get("completed",false),"approved hand gesture completes")
	check(sim.state.clock.total_minutes==606,"offer and completion advance six minutes once")
	check(float(sim.services.npc_relationships.view("friend","player").trust)>old_trust,"directed trust changes")
	check(sim.state.social.npcs.friend.mind.history.any(func(entry):return entry.kind=="companion" and entry.data.outcome=="completed"),"NPC remembers actual gesture")
	check(Social.history(sim,"friend").any(func(entry):return "приятный момент" in entry.text),"memory shown in social history")
	before = sim.export_snapshot()
	check(not sim.command("companion","finish",{"token":token,"zone":"hand_l","duration":1.0}).ok,"reward cannot be repeated")
	check(before==sim.export_snapshot(),"repeated finish atomic")
	check(sim.services.companion.preview("friend","hand").blocked=="companion_cooldown","repetition has a cooldown")
	var replay: Dictionary = restored.command("companion","finish",{"token":token,"zone":"hand_l","duration":1.0})
	check(JSON.parse_string(JSON.stringify(replay))==JSON.parse_string(JSON.stringify(result)) and JSON.parse_string(JSON.stringify(restored.export_snapshot()))==JSON.parse_string(JSON.stringify(sim.export_snapshot())),"restored continuation deterministic")
	sim = accepted_fixture()
	token = sim.state.companion.active.token
	old_trust = sim.services.npc_relationships.view("friend","player").trust
	check(sim.command("npc_relationships","boundary",{"id":"friend","boundary":"contact","allowed":false}).ok,"boundary can be revoked mid-interaction")
	result = sim.command("companion","finish",{"token":token,"zone":"hand_l","duration":1.0})
	check(result.ok and result.data.get("cancelled",false),"revocation interrupts without reward")
	check(float(sim.services.npc_relationships.view("friend","player").trust)==old_trust,"revocation has no relationship penalty")
	sim = accepted_fixture()
	token = sim.state.companion.active.token
	before = sim.services.npc_relationships.view("friend","player")
	check(sim.command("companion","cancel",{"token":token}).ok,"cancel allowed")
	check(before==sim.services.npc_relationships.view("friend","player") and sim.state.companion.active.is_empty(),"cancel clears session without relationship changes")
	var broken: Dictionary = sim.export_snapshot()
	broken.state.companion.active = {"token":999,"npc":"friend","gesture":"hand","offered_at":600}
	check(not sim.restore_snapshot(broken).ok,"tampered session rejected")
	await _ui_checks()
	print("COMPANION_RESULT ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)

func _ui_checks() -> void:
	var game = root.get_node("Gameplay")
	var original = game.simulation
	var original_phase: String = game.phase
	var session = root.get_node("GameSession")
	game.restore_error = "unsupported_main_schema"
	check(session.save_slot("user_0_0") == ERR_INVALID_DATA,"incompatible state cannot overwrite a manual save")
	check(session.perform_autosave() == ERR_INVALID_DATA,"incompatible state cannot overwrite an autosave")
	game.restore_error = ""
	game.simulation = accepted_fixture()
	game.phase = "free_roam"
	var window = load("res://scripts/ui/gameplay/companion_window.gd").new()
	window.npc_id = "friend"
	root.add_child(window)
	await process_frame
	check(not window._session.is_empty(),"UI resumes saved consent")
	check(is_instance_valid(window.puppet) and window.puppet.bank.definitions.size()==106,"Live2D renders inside NPC interaction")
	if is_instance_valid(window.puppet):
		check(window.puppet.profile.zones.size() == 2 and window.puppet.profile.zones.all(func(zone):return zone.id in ["hand_l","hand_r"]),"only agreed zones are interactive")
	window._complete_keyboard()
	check(game.simulation.state.companion.active.is_empty(),"keyboard completes same world action")
	window._close_moment()
	await process_frame
	game.simulation = accepted_fixture()
	window = load("res://scripts/ui/gameplay/companion_window.gd").new()
	window.npc_id = "friend"
	root.add_child(window)
	for i in range(4): await process_frame
	var point: Variant = _hand_point(window.puppet)
	check(point != null,"accepted hand gesture has a real mesh hit target")
	if point != null:
		check(window.puppet.begin_grab(point),"pointer starts agreed gesture")
		window.puppet._process(0.8)
		window.puppet.release_grab()
		check(game.simulation.state.companion.active.is_empty(),"pointer release commits the same gameplay action")
		check(game.simulation.state.clock.total_minutes == 606,"pointer gesture advances time once")
	window._close_moment()
	await process_frame
	game.simulation = original
	game.phase = original_phase

func _hand_point(view: Control) -> Variant:
	for id: String in view._zone_meshes.get("hand_l",[]):
		var mesh: MeshInstance2D = view.model.get_node_or_null(NodePath(id))
		if mesh == null or not mesh.visible: continue
		var box: AABB = mesh.mesh.custom_aabb
		for x in range(1,10):
			for y in range(1,10):
				var local := Vector2(box.position.x+box.size.x*x/10.0,box.position.y+box.size.y*y/10.0)
				var point: Vector2 = view.get_global_transform().affine_inverse()*mesh.to_global(local)
				if view.hit_test(point).get("id") == "hand_l": return point
	return null
