extends "res://scripts/mechanics/core/module.gd"

const TOGGLES := ["satiety_enabled", "rent_enabled", "education_failure", "starvation_attrition", "exhaustion_enabled", "eviction_enabled"]
const RANGES := {"minigame_floor":[0.55,0.90], "skill_help_cap":[0.0,0.40], "xp": [0.5, 2.0], "need_decay": [0.25, 2.0], "resource_cost": [0.5, 2.0], "relation_gain": [0.5, 2.0], "dialogue_fatigue": [0.5, 2.0], "interaction_bonus": [-0.25, 0.25], "injury_damage": [0.0, 2.0], "injury_recovery": [0.5, 4.0], "initial_points": [10, 60], "combat_accuracy": [-0.2, 0.3], "enemy_accuracy": [-0.15, 0.15], "npc_tactics": [0, 1]}

static func validate_values(values: Variant) -> bool:
	if not values is Dictionary: return false
	for key in values:
		if key in TOGGLES:
			if not values[key] is bool: return false
		elif RANGES.has(key):
			if not (values[key] is int or values[key] is float) or not is_finite(float(values[key])): return false
			if float(values[key]) < RANGES[key][0] or float(values[key]) > RANGES[key][1]: return false
			if key == "initial_points" and float(values[key]) != int(values[key]): return false
		else: return false
	return true

func rule(key: String, fallback: Variant = 1.0) -> Variant:
	if sim.state.preferences.difficulty == "custom" and sim.state.preferences.custom.has(key): return sim.state.preferences.custom[key]
	return sim.catalog.difficulties[str(sim.state.preferences.difficulty)].get(key, fallback)

func execute(operation: String, args: Dictionary) -> Dictionary:
	match operation:
		"customize":
			var values: Variant = args.get("values", {})
			if not validate_values(values): return Rules.fail("invalid_difficulty_values")
			sim.state.preferences.custom.merge(values, true)
			sim.state.preferences.difficulty = "custom"
		"difficulty":
			var id := str(args.get("id", "normal"))
			if not sim.catalog.difficulties.has(id): return Rules.fail("unknown_difficulty")
			sim.state.preferences.difficulty = id
		"content_tag":
			var id := str(args.get("id", ""))
			if id.is_empty(): return Rules.fail("invalid_content_tag")
			if bool(args.get("enabled", true)):
				sim.state.preferences.disabled_tags.erase(id)
			elif not id in sim.state.preferences.disabled_tags:
				sim.state.preferences.disabled_tags.append(id)
		_:
			return Rules.fail("unknown_operation")
	return Rules.ok()
