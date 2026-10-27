extends RefCounted
const Simulation = preload("res://scripts/mechanics/simulation.gd")
const Population = preload("res://scripts/mechanics/population.gd")
const Preferences = preload("res://scripts/mechanics/preferences.gd")
const Rules = preload("res://scripts/mechanics/core/rules.gd")
const STATS := ["strength", "agility", "charisma", "intellect", "luck", "endurance", "erudition", "authority", "cunning"]

static func defaults() -> Dictionary:
	return {"seed": 2026, "mode": "story", "difficulty": "normal", "custom": {}, "needs":{}, "population": Population.defaults(),
		"sandbox": {"start_cash":250}, "personality": personality_defaults(), "content": {"romance": true, "adult": true, "pregnancy":true},
		"profile": {"full_name": "Алекс Ривер", "age": 23, "stats": {"strength": 8, "agility": 7, "charisma": 9, "intellect": 8, "luck": 5, "endurance": 6, "erudition": 7, "authority": 5, "cunning": 5},
			"appearance": {"gender": "male", "body_type": "slim", "face_id": "soft", "hair_style": "short", "hair_color": "dark", "censorship_enabled": true}}}

static func personality_defaults() -> Dictionary:
	return {"honesty": 50, "emotionality": 50, "extraversion": 50, "agreeableness": 50, "conscientiousness": 50, "openness": 50, "spread": 30}

static func point_budget(config: Dictionary) -> int:
	if config.get("difficulty", "") == "custom": return int(config.get("custom", {}).get("initial_points", 30))
	return int({"easy": 40, "normal": 30, "hard": 20}.get(config.get("difficulty", "normal"), 30))

static func remaining_points(config: Dictionary) -> int:
	var spent := 0
	for value in config.get("profile", {}).get("stats", {}).values(): spent += int(value) - 5
	return point_budget(config) - spent

static func validate(config: Variant) -> Dictionary:
	if not config is Dictionary: return Rules.fail("invalid_setup")
	if not config.get("mode", "story") in ["story", "sandbox"]: return Rules.fail("invalid_game_mode")
	var sandbox: Variant = config.get("sandbox", {"start_cash":250})
	if not sandbox is Dictionary or not sandbox.get("start_cash") is int or int(sandbox.start_cash) < 100 or int(sandbox.start_cash) > 1000: return Rules.fail("invalid_sandbox_settings")
	if not config.get("seed") is int or int(config.seed) < 0 or int(config.seed) > 2147483647: return Rules.fail("invalid_world_seed")
	if not config.get("difficulty") in ["easy", "normal", "hard", "custom"] or not Preferences.validate_values(config.get("custom")): return Rules.fail("invalid_difficulty")
	var content: Variant = config.get("content", {})
	var needs: Variant = config.get("needs",{})
	if not needs is Dictionary: return Rules.fail("invalid_need_settings")
	for id in needs:
		if not id in ["hydration","satiety","hygiene","bladder","rested","fun","social"] or not needs[id] is bool: return Rules.fail("invalid_need_settings")
	if not content is Dictionary: return Rules.fail("invalid_content_settings")
	for key in content:
		if not key in ["romance", "adult", "pregnancy"] or not content[key] is bool: return Rules.fail("invalid_content_settings")
	if not Population.valid(config.get("population")): return Rules.fail("invalid_population_settings")
	var personality: Variant = config.get("personality", personality_defaults())
	if not personality is Dictionary or personality.size() != personality_defaults().size(): return Rules.fail("invalid_personality_settings")
	for key in personality_defaults():
		var value: Variant = personality.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0 or float(value) > 100 or float(value) != int(value): return Rules.fail("invalid_personality_settings")
	var profile: Variant = config.get("profile")
	if not profile is Dictionary or not profile.get("full_name") is String or profile.full_name.strip_edges().is_empty() or profile.full_name.length() > 48: return Rules.fail("invalid_character_name")
	if not profile.get("age") is int or profile.age < 18 or profile.age > 80: return Rules.fail("invalid_character_age")
	if not profile.get("stats") is Dictionary or profile.stats.size() != STATS.size(): return Rules.fail("invalid_starting_stats")
	for key in STATS:
		if not profile.stats.get(key) is int or int(profile.stats[key]) < 5 or int(profile.stats[key]) > 30: return Rules.fail("invalid_starting_stats")
	if not profile.get("appearance") is Dictionary: return Rules.fail("invalid_appearance")
	var options := {"gender": ["male", "female", "nonbinary"], "body_type": ["slim", "athletic"], "face_id": ["soft", "sharp"], "hair_style": ["short", "long"], "hair_color": ["dark", "light"]}
	for key in options:
		if not profile.appearance.get(key) in options[key]: return Rules.fail("invalid_appearance_option:" + key)
	if remaining_points(config) < 0: return Rules.fail("starting_budget_exceeded")
	return Rules.ok({"remaining_points": remaining_points(config)})

static func build(config: Dictionary, count_override: int = 0) -> Dictionary:
	var checked := validate(config)
	if not checked.ok: return checked
	var simulation = Simulation.new(int(config.seed), {"settings": {"start_minutes": 1920}})
	var profile: Dictionary = config.profile.duplicate(true)
	profile.full_name = str(profile.full_name).strip_edges()
	simulation.reset(profile)
	simulation.state.player.age = profile.age
	simulation.state.player.points = int(checked.data.remaining_points)
	var result: Dictionary = simulation.command("preferences", "customize", {"values": config.custom}) if config.difficulty == "custom" else simulation.command("preferences", "difficulty", {"id": config.difficulty})
	if not result.ok: return result
	for tag in config.get("content", {}):
		result = simulation.command("preferences", "content_tag", {"id": tag, "enabled": config.content[tag]})
		if not result.ok: return result
	var population: Dictionary = config.population.duplicate(true)
	if count_override > 0: population.count = count_override
	result = simulation.command("population", "configure", {"values": population})
	if not result.ok: return result
	result = simulation.command("population", "generate")
	if not result.ok: return result
	return Rules.ok({"simulation": simulation, "profile": profile, "population": result.data})
