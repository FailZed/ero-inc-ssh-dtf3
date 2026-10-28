extends "res://scripts/mechanics/core/module.gd"
const TRAITS := ["bravery", "responsibility", "sociability", "romantic", "loyalty", "cunning"]
const MORPHOLOGIES := ["human", "semi_furry", "furry"]

static func defaults() -> Dictionary:
	return {"count": 36, "age_min": 18, "age_max": 45, "female_ratio": 0.5, "semi_furry_ratio": 0.25, "furry_ratio": 0.15, "stat_min": 3, "stat_max": 12,
		"trait_spread": 30, "bravery": 50, "responsibility": 60, "sociability": 55, "romantic": 50, "loyalty": 65, "cunning": 45, "activity_mode": "mixed"}

static func valid(config: Variant) -> bool:
	if not config is Dictionary: return false
	var limits := {"count": [1, 200], "age_min": [18, 80], "age_max": [18, 80], "female_ratio": [0, 1], "semi_furry_ratio": [0, 1], "furry_ratio": [0, 1], "stat_min": [1, 100], "stat_max": [1, 100], "trait_spread": [0, 100]}
	for key in TRAITS: limits[key] = [0, 100]
	for key in config:
		if key == "activity_mode":
			if not config[key] in ["mixed", "work", "study"]: return false
		elif limits.has(key):
			var value: Variant = config[key]
			if not (value is int or value is float) or not is_finite(float(value)): return false
			if float(value) < limits[key][0] or float(value) > limits[key][1]: return false
			if not key.ends_with("_ratio") and float(value) != int(value): return false
		else: return false
	var merged := defaults()
	merged.merge(config, true)
	return merged.age_min <= merged.age_max and merged.stat_min <= merged.stat_max and float(merged.semi_furry_ratio) + float(merged.furry_ratio) <= 1.0

## Largest remainders keep a small population's total exact. Ties use the order above.
static func morphology_counts(config: Dictionary) -> Dictionary:
	var merged := defaults()
	merged.merge(config, true)
	var ratios: Array[float] = [1.0 - float(merged.semi_furry_ratio) - float(merged.furry_ratio), float(merged.semi_furry_ratio), float(merged.furry_ratio)]
	var counts := {}
	var remainders: Array[float] = []
	var remaining := int(merged.count)
	for i in range(MORPHOLOGIES.size()):
		var exact := float(merged.count) * ratios[i]
		counts[MORPHOLOGIES[i]] = int(floor(exact))
		remaining -= int(counts[MORPHOLOGIES[i]])
		remainders.append(exact - floor(exact))
	while remaining > 0:
		var index := remainders.find(remainders.max())
		counts[MORPHOLOGIES[index]] += 1
		remainders[index] = -1.0
		remaining -= 1
	return counts

func _shuffle(values: Array) -> void:
	for i in range(values.size() - 1, 0, -1):
		var j: int = sim.rng.randi_range(0, i)
		var temporary: Variant = values[i]
		values[i] = values[j]
		values[j] = temporary

func execute(operation: String, args: Dictionary) -> Dictionary:
	match operation:
		"configure":
			if not valid(args.get("values", {})): return Rules.fail("invalid_population_settings")
			var config := defaults()
			config.merge(args.get("values", {}), true)
			sim.state.population.settings = config
		"generate":
			var config := defaults()
			config.merge(sim.state.population.settings, true)
			return sim.generate_population(config)
		_: return Rules.fail("unknown_operation")
	return Rules.ok()

func generate_batch(config: Dictionary, finalize_batch: bool = true) -> Dictionary:
	if not valid(config): return Rules.fail("invalid_population_settings")
	if sim.state.social.npcs.size() + int(config.count) > 500: return Rules.fail("population_limit")
	var genders: Array = []
	var women := int(round(float(config.count) * float(config.female_ratio)))
	for i in range(int(config.count)): genders.append("female" if i < women else "male")
	_shuffle(genders)
	var counts := morphology_counts(config)
	var morphologies: Array = []
	for morphology in MORPHOLOGIES:
		for i in range(int(counts[morphology])): morphologies.append(morphology)
	_shuffle(morphologies)
	var created: Array = []
	for gender in genders:
		var template := definition("npc_templates", "resident").duplicate(true)
		var interests: Array = sim.catalog.get("preference_sets", {}).keys()
		interests.sort()
		if not interests.is_empty():
			template.preferences = definition("preference_sets", str(interests[sim.rng.randi_range(0, interests.size() - 1)])).categories.duplicate()
		template.gender = gender
		template.stat_min = config.stat_min
		template.stat_max = config.stat_max
		template.traits = {}
		for trait_id in TRAITS:
			template.traits[trait_id] = clampi(int(config[trait_id]) + sim.rng.randi_range(-int(config.trait_spread), int(config.trait_spread)), 0, 100)
		var worker: bool = config.activity_mode == "work" or (config.activity_mode == "mixed" and sim.rng.randf() < 0.6)
		template.role = "worker" if worker else "learner"
		template.occupation = "employed" if worker else "student"
		template.education = "vocational" if worker else "general"
		template.cohort = template.role
		template.activities = ["paid_work", "socialize"] if worker else ["read", "train", "socialize"]
		template.schedule = [{"location": sim.location_role("trade") if worker else sim.location_role("study"), "activity": "work" if worker else "study", "hours": [480, 960], "weekdays": [1, 2, 3, 4, 5]}, {"location": sim.location_role("trade"), "activity": "walk", "hours": [960, 1200]}]
		var id := "resident_%06d" % int(sim.state.social.next_npc_id)
		var names := ["Марина Ветрова", "Алина Соколова", "Ирина Белова", "Вера Орлова"] if gender == "female" else ["Александр Ветров", "Михаил Соколов", "Илья Белов", "Артём Орлов"]
		var result: Dictionary = sim.services.social.generate_from_template(id, {"name": names[sim.rng.randi_range(0, names.size() - 1)], "age": sim.rng.randi_range(int(config.age_min), int(config.age_max)), "appearance": {"morphology": morphologies[created.size()], "gender": gender, "body_type": "slim", "face_id": "soft", "hair_style": "long" if gender == "female" else "short", "hair_color": "dark"}}, template)
		if not result.ok: return result
		created.append(id)
	if finalize_batch: return finish_batch(created, counts)
	return Rules.ok({"ids": created, "count": created.size(), "morphologies": counts})

func finish_batch(created: Array, counts: Dictionary) -> Dictionary:
	sim.state.population.batches += 1
	emit_event("population_generated", {"ids":created.duplicate()})
	return Rules.ok({"ids":created.duplicate(),"count":created.size(),"morphologies":counts.duplicate(true)})
