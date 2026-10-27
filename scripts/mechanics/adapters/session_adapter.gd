extends Node
## Opt-in bridge. Add explicitly after choosing the new world's integration point.
## Save slots are deliberately not intercepted. Persist export_snapshot separately
## when the main game's save integration is designed.

signal integration_error(reason: String)
signal domain_event(event: Dictionary)
const Simulation = preload("res://scripts/mechanics/simulation.gd")
var simulation
var _session
var _locations
var _syncing := false
var _previous_time_mode := "realtime"

func attach(session: Node, locations: Node, random_seed: int = 1, extensions: Dictionary = {}) -> void:
	detach()
	_session = session
	_locations = locations
	_previous_time_mode = session.get_game_time_mode()
	simulation = Simulation.new(random_seed, extensions)
	simulation.reset(session.get_character_profile())
	simulation.state.clock = Simulation.calendar.snapshot(int(session.get_game_time_snapshot().total_minutes))
	_on_location_changed(str(locations.current_location_id))
	session.game_time_advanced.connect(_on_time_advanced)
	session.game_time_reset.connect(_on_time_reset)
	session.player_profile_changed.connect(_on_profile_changed)
	locations.location_changed.connect(_on_location_changed)
	simulation.domain_event.connect(domain_event.emit)
	session.set_game_time_mode("actions")

func detach() -> void:
	if is_instance_valid(_session):
		if _session.game_time_advanced.is_connected(_on_time_advanced): _session.game_time_advanced.disconnect(_on_time_advanced)
		if _session.game_time_reset.is_connected(_on_time_reset): _session.game_time_reset.disconnect(_on_time_reset)
		if _session.player_profile_changed.is_connected(_on_profile_changed): _session.player_profile_changed.disconnect(_on_profile_changed)
		_session.set_game_time_mode(_previous_time_mode)
	if is_instance_valid(_locations) and _locations.location_changed.is_connected(_on_location_changed):
		_locations.location_changed.disconnect(_on_location_changed)
	_session = null
	_locations = null

func _exit_tree() -> void:
	detach()

func execute(module_id: String, operation: String, args: Dictionary = {}) -> Dictionary:
	if simulation == null or not is_instance_valid(_session): return {"ok": false, "error": "adapter_detached"}
	var previous := int(simulation.state.clock.total_minutes)
	var result: Dictionary = simulation.command(module_id, operation, args)
	if result.ok:
		_syncing = true
		_session.advance_game_time(int(simulation.state.clock.total_minutes) - previous)
		_syncing = false
	return result

func restore_snapshot(snapshot: Dictionary) -> Dictionary:
	if simulation == null or not is_instance_valid(_session): return {"ok": false, "error": "adapter_detached"}
	var result: Dictionary = simulation.restore_snapshot(snapshot)
	if result.ok:
		_syncing = true
		_session.set_game_time_total_minutes(int(simulation.state.clock.total_minutes))
		_syncing = false
	return result

func _on_time_advanced(previous: int, current: int) -> void:
	if _syncing: return
	var remaining := current - previous
	while remaining > 0:
		var step := mini(remaining, int(simulation.catalog.settings.max_advance_minutes))
		var result: Dictionary = simulation.command("clock", "advance", {"minutes": step})
		if not result.ok:
			integration_error.emit(str(result.error))
			return
		remaining -= step

func _on_time_reset(snapshot: Dictionary) -> void:
	if _syncing: return
	# A new game or a legacy load has no simulation snapshot. The integration
	# owner should call restore_snapshot afterwards for new-format game saves.
	simulation.reset(_session.get_character_profile())
	simulation.state.clock = Simulation.calendar.snapshot(int(snapshot.total_minutes))
	_on_location_changed(str(_locations.current_location_id))

func _on_profile_changed(profile: Dictionary) -> void:
	# Character creation changes identity and its five base attributes. Runtime
	# progression remains in simulation; don't overwrite it on UI refresh.
	simulation.state.player.name = str(profile.get("full_name", simulation.state.player.name))
	simulation.state.player.appearance = profile.get("appearance", {}).duplicate(true)
	for stat in profile.get("stats", {}):
		if simulation.state.player.stats.has(stat): simulation.state.player.stats[stat] = profile.stats[stat]

func _on_location_changed(id: String) -> void:
	var canonical := "global_map" if id == "street_exit" else id
	if simulation != null and simulation.catalog.locations.has(canonical):
		simulation.state.world.previous_location = simulation.state.world.location
		simulation.state.world.location = canonical
