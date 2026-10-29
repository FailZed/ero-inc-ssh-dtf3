extends SceneTree
## Boundary setups and ordinary actions through the actual sandbox autoload.
const Setup = preload("res://scripts/mechanics/setup_config.gd")
const Appearance = preload("res://scripts/characters/protagonist_appearance.gd")
var checks := 0
var failures: Array[String] = []
var gameplay
var session
var dialogic

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		printerr("FAIL: ", description)

func _run() -> void:
	gameplay = root.get_node("Gameplay")
	session = root.get_node("GameSession")
	dialogic = root.get_node("Dialogic")
	session.pause_autosave_runtime()
	for spec: Dictionary in [
		{"count":1,"difficulty":"easy","cash":100,"enrolled":false},
		{"count":8,"difficulty":"hard","cash":250,"enrolled":true},
		{"count":50,"difficulty":"normal","cash":1000,"enrolled":false},
		{"count":200,"difficulty":"custom","cash":100,"enrolled":true}]:
		check(_case(spec), "configuration completed: " + JSON.stringify(spec))
	print("SANDBOX_CONFIGURATIONS_RESULT ", JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)

func _case(spec: Dictionary) -> bool:
	var label := str(spec.count) + "/" + str(spec.difficulty)
	var config: Dictionary = Setup.defaults()
	config.mode = "sandbox"
	config.population.count = spec.count
	config.difficulty = spec.difficulty
	config.sandbox.start_cash = spec.cash
	config.sandbox.education = {"enrolled":spec.enrolled,"subjects":["physics","genetics"] if spec.enrolled else []}
	config.content.pregnancy = false
	if spec.difficulty == "custom": config.custom = {"initial_points":10}
	for stat: String in Setup.STATS: config.profile.stats[stat] = 5
	check(Setup.validate(config).ok, label + ": valid configuration")
	gameplay._pending_configuration = config
	dialogic.clear(DialogicGameHandler.ClearFlags.FULL_CLEAR)
	session.reset_game_time()
	session.reset_character_profile()
	session.pause_autosave_runtime()
	var profile: Dictionary = session.get_character_profile()
	profile.identity.full_name = "Проверка песочницы"
	profile.appearance.live2d = Appearance.normalize_appearance({"shape":{"ParamAssSize":0.4},"outfit":"dress"})
	for stat: String in Setup.STATS: profile.stats[stat] = 5
	check(session.apply_character_profile_v2(profile), label + ": mirror profile accepted")
	var accepted: Dictionary = session.get_character_profile()
	var invalid: Dictionary = accepted.duplicate(true)
	invalid.appearance.live2d.shape.ParamAssSize = 2.0
	check(not session.apply_character_profile_v2(invalid) and session.get_character_profile() == accepted, label + ": invalid GG edit is atomic")
	gameplay._on_profile_changed(session.get_character_profile())
	var started: Dictionary = gameplay.open_sandbox()
	check(started.ok, label + ": opens sandbox " + str(started.get("error","")))
	if not started.ok: return false
	var sim = gameplay.simulation
	check(sim.state.social.npcs.size() == spec.count, label + ": exact population count")
	check(sim.state.economy.cash == spec.cash, label + ": selected cash")
	check(bool(sim.state.world.flags.student_enrolled) == bool(spec.enrolled), label + ": enrollment preserved")
	check(sim.state.journal.quests.is_empty() and dialogic.current_timeline == null, label + ": no forced story")
	check(int(sim.state.clock.total_minutes) == 480 and gameplay.restore_error.is_empty(), label + ": clean 08:00 start")
	var before: Dictionary = sim.export_snapshot()
	check(not gameplay.execute("world","journey",{"id":"missing_sandbox_destination"}).ok and sim.export_snapshot() == before, label + ": invalid travel is atomic")
	for action: Array in [
		["world","journey",{"id":"kitchen"}],
		["needs","drink",{}],
		["world","journey",{"id":"bathroom"}],
		["needs","toilet",{}],
		["world","journey",{"id":"bedroom"}],
		["needs","sleep",{"minutes":30}],
		["world","journey",{"id":"city_park"}]]:
		var result: Dictionary = gameplay.execute(action[0],action[1],action[2])
		check(result.ok, label + ": " + str(action) + " " + str(result.get("error","")))
	check(sim.state.world.location == "city_park" and root.get_node("LocationManager").current_location_id == "city_park", label + ": location synchronized")
	check(int(sim.state.clock.total_minutes) > 480 and int(session.get_game_time_snapshot().total_minutes) == int(sim.state.clock.total_minutes), label + ": shared clock advances once")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(sim.export_snapshot()))
	var restored = gameplay.make_simulation()
	check(restored.restore_snapshot(snapshot).ok, label + ": action state restores")
	check(JSON.parse_string(JSON.stringify(restored.export_snapshot())) == snapshot, label + ": restore preserves population and resources")
	check(JSON.parse_string(JSON.stringify(restored.state.player.appearance.live2d)) == JSON.parse_string(JSON.stringify(profile.appearance.live2d)), label + ": GG shape and outfit survive restore")
	var corrupt: Dictionary = snapshot.duplicate(true)
	corrupt.state.player.appearance.live2d.model_id = "unknown"
	check(not restored.restore_snapshot(corrupt).ok and JSON.parse_string(JSON.stringify(restored.export_snapshot())) == snapshot, label + ": invalid GG snapshot is atomic")
	return true
