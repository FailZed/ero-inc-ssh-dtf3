extends RefCounted
## Optional domain runtime. No autoload, UI, Dialogic or donor dependency.
## Mutate through command(); services expose read queries for presenters.

signal committed(module_id: String, operation: String, result: Dictionary)
signal domain_event(event: Dictionary)
signal state_restored

const Rules = preload("res://scripts/mechanics/core/rules.gd")
const Validation = preload("res://scripts/mechanics/core/validation.gd")
const calendar = preload("res://scripts/mechanics/core/calendar.gd")
const MODULES := {
	"education": preload("res://scripts/mechanics/education.gd"),
	"character": preload("res://scripts/mechanics/character.gd"),
	"inventory": preload("res://scripts/mechanics/inventory.gd"),
	"world": preload("res://scripts/mechanics/world.gd"),
	"economy": preload("res://scripts/mechanics/economy.gd"),
	"housing": preload("res://scripts/mechanics/housing.gd"),
	"preferences": preload("res://scripts/mechanics/preferences.gd"),
	"social": preload("res://scripts/mechanics/social.gd"),
	"organizations": preload("res://scripts/mechanics/organizations.gd"),
	"lifecycle": preload("res://scripts/mechanics/lifecycle.gd"),
	"encounters": preload("res://scripts/mechanics/encounters.gd"),
	"actions": preload("res://scripts/mechanics/actions.gd"),
	"events": preload("res://scripts/mechanics/events.gd"),
	"health": preload("res://scripts/mechanics/health.gd"),
	"combat": preload("res://scripts/mechanics/combat.gd"),
	"careers": preload("res://scripts/mechanics/careers.gd"),
	"security": preload("res://scripts/mechanics/security.gd"),
	"social_rules": preload("res://scripts/mechanics/social_rules.gd"),
	"institutions": preload("res://scripts/mechanics/institutions.gd"),
	"interior": preload("res://scripts/mechanics/interior.gd"),
	"activities": preload("res://scripts/mechanics/activities.gd"),
	"appearance": preload("res://scripts/mechanics/appearance.gd"),
	"population": preload("res://scripts/mechanics/population.gd"),
	"npc_behavior": preload("res://scripts/mechanics/npc_behavior.gd"),
}
const SCHEMA := 2
var state: Dictionary = {}
var catalog: Dictionary = {}
var services: Dictionary = {}
var rng := RandomNumberGenerator.new()
var pending_events: Array = []
var _busy := false
var resting := false
var configuration_error := ""
var _initial_seed := 1

func _init(random_seed: int = 1, extensions: Dictionary = {}) -> void:
	catalog = _load_catalog()
	for group in extensions:
		if catalog.has(group) and catalog[group] is Dictionary and extensions[group] is Dictionary:
			catalog[group].merge(extensions[group].duplicate(true), true)
	configuration_error = Validation.catalog_error(catalog)
	if not configuration_error.is_empty():
		catalog = _load_catalog()
	_initial_seed = random_seed
	rng.seed = random_seed
	for id in MODULES:
		services[id] = MODULES[id].new(self)
	reset()

func _load_catalog() -> Dictionary:
	var result: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/mechanics/base.json"))
	for file in ["advanced", "parity", "balance"]:
		var additions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/mechanics/%s.json" % file))
		for group in additions:
			if not result.has(group): result[group] = {}
			result[group].merge(additions[group], true)
	return result

func reset(profile: Dictionary = {}) -> void:
	rng.seed = _initial_seed
	var attributes: Dictionary = catalog.attributes.duplicate(true)
	var profile_stats: Dictionary = profile.get("stats", profile.get("attributes", {}))
	for id in attributes:
		if profile_stats.has(id): attributes[id] = clampf(float(profile_stats[id]), 0.0, float(catalog.settings.stat_cap))
	state = {
		"clock": calendar.snapshot(int(catalog.settings.start_minutes)),
		"player": {"name": str(profile.get("full_name", "Alex River")), "age": int(profile.get("age", 23)), "stats": attributes,
			"appearance": profile.get("appearance", {}).duplicate(true), "skills": {}, "xp": 0, "level": 1,
			"points": 0, "needs": {"energy": 100.0, "satiety": 100.0, "health": 100.0, "hygiene": 100.0, "mood": 70.0},
			"effects": {}, "perks": [], "injuries": {}, "addictions": {}, "training": {}},
		"inventory": {"items": {}, "equipped": {}},
		"economy": {"cash": int(catalog.settings.start_cash), "bank": 0, "debt": 0,
			"assets": {}, "job_counts": {}, "projects": {}, "shop_stock": {}, "channel": {"followers": 0}},
		"world": {"location": str(catalog.settings.start_location), "previous_location": "", "flags": {},
			"weather": "clear", "temperature": 22, "cleanliness": 100.0, "heat": 0.0,
			"equipment": [], "visits": {}, "unlocked": [], "education": preload("res://scripts/mechanics/education.gd").defaults()},
		"social": {"npcs": {}, "relationships": {}, "contacts": [], "messages": [], "appointments": [], "promises": {}, "next_npc_id": 1, "next_message_id": 1},
		"organizations": {}, "journal": {"quests": {}, "achievements": [], "fired": {}, "cooldowns": {}, "ready_events": []},
		"encounters": {"combat": {}, "game": {}}, "conditions": {}, "counters": {},
		"housing": {"properties": {}, "residence": ""},
		"preferences": {"difficulty": "normal", "custom": {}, "disabled_tags": catalog.settings.disabled_tags.duplicate()},
		"healthcare": {"records": {}, "family": []},
		"careers": {"contracts": {}, "professions": {}, "workdays": {}, "streams": [], "publications": {}},
		"security": {"fine": 0, "incidents": []},
		"population": {"settings": {}, "batches": 0},
	}
	pending_events.clear()
	state_restored.emit()

func command(module_id: String, operation: String, args: Dictionary = {}) -> Dictionary:
	if _busy: return Rules.fail("reentrant_command")
	if not configuration_error.is_empty(): return Rules.fail("invalid_catalog:" + configuration_error)
	if not Validation.command_args(module_id, args): return Rules.fail("invalid_arguments")
	var unconscious_until := int(state.healthcare.records.get("player", {}).get("unconscious_until", 0))
	if int(state.clock.total_minutes) < unconscious_until and not allowed_during_recovery(module_id, operation):
		return Rules.fail("recover_from_exhaustion")
	if module_id != "clock" and not services.has(module_id): return Rules.fail("unknown_module")
	var combat: Dictionary = state.encounters.combat
	var game: Dictionary = state.encounters.game
	if not combat.is_empty() and combat.status == "active" and not ((module_id == "encounters" and operation == "combat_action") or (module_id == "combat" and operation == "action")):
		return Rules.fail("finish_active_combat")
	if not game.is_empty() and game.status == "active" and not (module_id == "encounters" and operation in ["game_input", "cancel_game"]):
		return Rules.fail("finish_active_game")
	var before := state.duplicate(true)
	var rng_before := rng.state
	_busy = true
	pending_events.clear()
	var result := before_command(module_id, operation, args)
	if result.ok:
		if module_id == "clock":
			result = advance(int(args.get("minutes", 0))) if operation == "advance" else Rules.fail("unknown_operation")
		else:
			result = services[module_id].execute(operation, args)
	if result.ok: result = after_command(module_id, operation, args, result, before)
	if result.ok:
		services.events.observe(module_id,operation,args,result)
		services.events.poll()
		var valid := validate_state(state)
		if not valid.ok: result = valid
	if not result.ok:
		state = before
		rng.state = rng_before
		pending_events.clear()
		rollback_command()
	var emitted := pending_events.duplicate(true)
	pending_events.clear()
	finish_command()
	# Remain locked during notifications: observers enqueue their next action.
	if result.ok:
		committed.emit(module_id, operation, result.duplicate(true))
		for event in emitted: domain_event.emit(event)
	_busy = false
	return result

func before_command(_module_id: String, _operation: String, _args: Dictionary) -> Dictionary:
	return Rules.ok()

func allowed_during_recovery(module_id: String, operation: String) -> bool:
	return module_id == "clock" or (module_id == "character" and operation == "rest")

func after_command(_module_id: String, _operation: String, _args: Dictionary, result: Dictionary, _before: Dictionary) -> Dictionary:
	return result

func finish_command() -> void:
	pass

func advance(minutes: int) -> Dictionary:
	# Internal to a transaction; external callers use command("clock", "advance").
	if not _busy: return Rules.fail("use_clock_command")
	if minutes < 0 or minutes > int(catalog.settings.max_advance_minutes): return Rules.fail("invalid_time_delta")
	for step in range(minutes):
		var minute := int(state.clock.total_minutes) + 1
		state.clock = calendar.snapshot(minute)
		for id in services: services[id].tick(minute)
		after_minute(minute)
	return Rules.ok({"clock": state.clock.duplicate(true)})

func after_minute(minute: int) -> void:
	services.social.settle_appointments(minute)

func apply_effects(effects: Array) -> Dictionary:
	for effect in effects:
		var result := Rules.ok()
		match str(effect.get("kind", "")):
			"need": services.character.adjust_need(str(effect.id), float(effect.get("amount", 0)))
			"xp": result = services.character.execute("gain_xp", {"amount": effect.get("amount", 0)})
			"skill": result = services.character.execute("train", {"skill": effect.id, "xp": effect.get("amount", 0)})
			"money":
				var amount := int(effect.get("amount", 0))
				if state.economy.cash + amount < 0: return Rules.fail("insufficient_funds")
				state.economy.cash += amount
			"item": result = services.inventory.change(str(effect.id), int(effect.get("amount", 1)))
			"effect": result = services.character.add_effect(str(effect.id))
			"flag": result = services.world.execute("flag", effect)
			"unlock": result = services.world.execute("unlock", effect)
			"condition": result = services.lifecycle.execute("start", effect)
			"command":
				var module_id := str(effect.get("module", ""))
				var arguments: Variant = effect.get("args", {})
				if module_id in ["actions", "events"] or not services.has(module_id) or not arguments is Dictionary:
					return Rules.fail("invalid_effect_command")
				if not Validation.command_args(module_id, arguments): return Rules.fail("invalid_effect_arguments")
				result = services[module_id].execute(str(effect.get("operation", "")), arguments)
			_:
				return Rules.fail("unknown_effect_kind")
		if not result.ok: return result
	return Rules.ok()

func multiplier(id: String) -> float:
	var result := float(services.preferences.rule(id, 1.0))
	for perk in state.player.perks: result *= float(catalog.perks[perk].get("multipliers", {}).get(id, 1.0))
	return result

func location_role(id: String) -> String:
	return str(catalog.get("location_roles", {}).get(id, ""))

func player_home_room(kind: String) -> String:
	return str(catalog.settings.get("home_rooms", {}).get(kind, ""))

func player_home() -> String:
	return player_home_room("bedroom")

func room_kind(id: String) -> String:
	for kind in catalog.settings.get("home_rooms", {}):
		if catalog.settings.home_rooms[kind] == id: return str(kind)
	return str(catalog.locations.get(id, {}).get("room_kind", ""))

func is_player_home_location(id: String) -> bool:
	return id in catalog.settings.get("home_rooms", {}).values()

func actor_home(id: String = "player") -> String:
	return player_home() if id == "player" else str(state.social.npcs.get(id, {}).get("home", ""))

func is_actor_home_location(id: String, location: String) -> bool:
	if id == "player": return is_player_home_location(location)
	var home := actor_home(id)
	var home_entry: Dictionary = catalog.locations.get(home,{})
	var entry: Dictionary = catalog.locations.get(location,{})
	if home_entry.get("kind","")=="private_residence" and home_entry.get("owner_actor_id","")!=id: return false
	if entry.get("kind","")=="private_residence" and entry.get("owner_actor_id","")!=id: return false
	if location == home: return not home.is_empty()
	var property_id := str(home_entry.get("residence_property_id",""))
	return not property_id.is_empty() and entry.get("kind","")=="private_room" and entry.get("residence_property_id") == property_id

func prepare_npc_template(_id: String, _args: Dictionary, template: Dictionary) -> Dictionary:
	return Rules.ok(template.duplicate(true))

func generate_population(config: Dictionary) -> Dictionary:
	return services.population.generate_batch(config)

func rollback_command() -> void:
	pass

func export_snapshot() -> Dictionary:
	return {"schema": SCHEMA, "catalog_hash": JSON.stringify(catalog).sha256_text(),
		"rng_seed": str(rng.seed), "rng_state": str(rng.state), "state": state.duplicate(true)}

func restore_snapshot(snapshot: Dictionary) -> Dictionary:
	if _busy: return Rules.fail("reentrant_command")
	if int(snapshot.get("schema", -1)) != SCHEMA: return Rules.fail("unsupported_schema")
	if str(snapshot.get("catalog_hash", "")) != JSON.stringify(catalog).sha256_text(): return Rules.fail("catalog_mismatch")
	if not snapshot.get("state") is Dictionary: return Rules.fail("invalid_snapshot")
	if not str(snapshot.get("rng_state", "")).is_valid_int() or not str(snapshot.get("rng_seed", "")).is_valid_int(): return Rules.fail("invalid_rng")
	var candidate: Dictionary = snapshot.state.duplicate(true)
	var result := validate_state(candidate)
	if not result.ok: return result
	state = candidate
	state.clock = calendar.snapshot(int(state.clock.total_minutes))
	rng.seed = int(snapshot.rng_seed)
	rng.state = int(snapshot.rng_state)
	pending_events.clear()
	state_restored.emit()
	return Rules.ok()

func validate_state(candidate: Dictionary) -> Dictionary:
	var structural_error := Validation.state_error(candidate, catalog)
	if not structural_error.is_empty(): return Rules.fail(structural_error)
	var education_error := preload("res://scripts/mechanics/education.gd").state_error(candidate,catalog)
	if not education_error.is_empty(): return Rules.fail(education_error)
	var club_error := preload("res://scripts/mechanics/club_work.gd").state_error(candidate,catalog)
	if not club_error.is_empty(): return Rules.fail(club_error)
	# Check the complete container shape before accessing nested values.
	var shape := {"clock": ["total_minutes"], "player": ["stats", "skills", "needs", "effects", "perks", "injuries", "addictions", "level", "xp", "points"],
		"inventory": ["items", "equipped"], "economy": ["cash", "bank", "debt", "assets", "job_counts", "projects", "shop_stock", "channel"],
		"world": ["location", "equipment", "education", "flags", "unlocked", "heat", "cleanliness", "visits"],
		"social": ["npcs", "relationships", "contacts", "messages", "appointments", "next_npc_id", "next_message_id"],
		"organizations": [], "journal": ["quests", "achievements", "fired", "cooldowns", "ready_events"],
		"encounters": ["combat", "game"], "conditions": [], "counters": []}
	for section in shape:
		if not candidate.get(section) is Dictionary: return Rules.fail("invalid_section:%s" % section)
		for key in shape[section]:
			if not candidate[section].has(key): return Rules.fail("missing_field:%s.%s" % [section, key])
	for path in ["inventory.items", "inventory.equipped", "player.needs", "player.stats", "social.npcs"]:
		if not Rules.read(candidate, path) is Dictionary: return Rules.fail("invalid_container:%s" % path)
	for need in ["energy", "satiety", "health", "hygiene", "mood"]:
		var value: Variant = candidate.player.needs.get(need)
		if not _number(value) or float(value) < 0.0 or float(value) > 100.0: return Rules.fail("invalid_need:%s" % need)
	for stat in catalog.attributes:
		var value: Variant = candidate.player.stats.get(stat)
		if not _number(value) or float(value) < 0.0: return Rules.fail("invalid_stat:%s" % stat)
	for path in ["clock.total_minutes", "economy.cash", "economy.bank", "economy.debt", "player.xp", "player.points", "player.level"]:
		var value: Variant = Rules.read(candidate, path)
		if not _number(value) or float(value) < 0.0: return Rules.fail("invalid_value:%s" % path)
	if not catalog.locations.has(str(candidate.world.location)): return Rules.fail("unknown_location")
	for id in candidate.inventory.items:
		var count: Variant = candidate.inventory.items[id]
		if not catalog.items.has(id) or not _number(count) or int(count) != float(count) or int(count) <= 0: return Rules.fail("invalid_inventory")
	for id in candidate.inventory.equipped.values():
		if not candidate.inventory.items.has(id): return Rules.fail("unowned_equipment")
	return Rules.ok()

func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
