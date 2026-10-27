extends "res://scripts/mechanics/core/module.gd"
const Formulas = preload("res://scripts/mechanics/core/formulas.gd")

func execute(operation: String, args: Dictionary) -> Dictionary:
	var player: Dictionary = sim.state.player
	match operation:
		"train":
			var skill := str(args.get("skill", ""))
			var amount := int(args.get("xp", 0))
			if not sim.catalog.skills.has(skill) or amount <= 0:
				return Rules.fail("invalid_skill_or_xp")
			player.skills[skill] = int(player.skills.get(skill, 0)) + amount
			_add_xp(amount)
		"gain_xp":
			if int(args.get("amount", 0)) <= 0:
				return Rules.fail("invalid_xp")
			_add_xp(int(args.amount))
		"allocate":
			var stat := str(args.get("stat", ""))
			if not player.stats.has(stat) or int(player.points) <= 0:
				return Rules.fail("no_points_or_unknown_stat")
			if float(player.stats[stat]) >= float(sim.catalog.settings.stat_cap):
				return Rules.fail("stat_cap")
			player.stats[stat] += 1
			player.points -= 1
		"perk":
			var id := str(args.get("id", ""))
			var perk := definition("perks", id)
			if perk.is_empty() or id in player.perks or player.points < int(perk.get("cost", 1)):
				return Rules.fail("perk_unavailable")
			if not Rules.check(sim.state, perk.get("requirements", {})):
				return Rules.fail("perk_requirements")
			player.points -= int(perk.get("cost", 1))
			player.perks.append(id)
		"effect":
			return add_effect(str(args.get("id", "")))
		"rest":
			var minutes := int(args.get("minutes", 60))
			if minutes <= 0 or minutes > 720:
				return Rules.fail("invalid_rest_duration")
			sim.resting = true
			var result: Dictionary = sim.advance(minutes)
			sim.resting = false
			if not result.ok: return result
		"treat":
			var part := str(args.get("part", "body"))
			if not player.injuries.has(part): return Rules.fail("no_injury")
			return sim.services.health.execute("treat", {"target": "player", "id": "clinic"})
		"substance":
			var id := str(args.get("id", ""))
			var substance := definition("substances", id)
			if substance.is_empty(): return Rules.fail("unknown_substance")
			var addiction: Dictionary = player.addictions.get(id, {"exposure": 0.0, "last_use": 0})
			addiction.exposure = minf(100.0, float(addiction.exposure) + float(substance.get("exposure", 10)))
			addiction.last_use = sim.state.clock.total_minutes
			player.addictions[id] = addiction
			if substance.has("effect"): return add_effect(str(substance.effect))
		_:
			return Rules.fail("unknown_operation")
	return Rules.ok({"level": player.level})

func adjust_need(id: String, delta: float) -> void:
	if sim.state.player.needs.has(id):
		# Fixed precision prevents JSON round-trips from changing later simulation ticks.
		sim.state.player.needs[id] = snappedf(clampf(float(sim.state.player.needs[id]) + delta, 0.0, 100.0), 0.000001)

func add_effect(id: String) -> Dictionary:
	var effect := definition("effects", id)
	if effect.is_empty(): return Rules.fail("unknown_effect")
	var expires := int(sim.state.clock.total_minutes) + int(effect.get("minutes", 60))
	sim.state.player.effects[id] = {"expires": expires}
	return Rules.ok({"expires": expires})

func effective_stat(id: String) -> float:
	var player: Dictionary = sim.state.player
	var value := float(player.stats.get(id, 0))
	var multiplier := 1.0
	for effect_id in player.effects:
		var effect := definition("effects", effect_id)
		value += float(effect.get("stats", {}).get(id, 0))
		multiplier *= float(effect.get("multipliers", {}).get(id, 1.0))
	for perk_id in player.perks:
		value += float(definition("perks", perk_id).get("stats", {}).get(id, 0))
	for item_id in sim.state.inventory.equipped.values():
		value += float(definition("items", str(item_id)).get("stats", {}).get(id, 0))
	var mood_mod := 0.8 if float(player.needs.mood) < 25 else 1.0
	return clampf(value * multiplier * mood_mod * sim.services.health.stat_multiplier("player", id), 0.0, float(sim.catalog.settings.stat_cap) * 2.0)

func _add_xp(amount: int) -> void:
	var player: Dictionary = sim.state.player
	var multiplier: float = xp_multiplier()
	var luck_chance := maxf(0.0, effective_stat("luck") - 20.0) * 0.0005
	var exact := amount * multiplier + float(player.get("xp_credit", 0))
	var gained := int(floor(exact + 0.000000001))
	player.xp_credit = maxf(0, exact - gained)
	if luck_chance > 0 and sim.rng.randf() < luck_chance: gained *= 2
	player.xp += gained
	while player.xp >= xp_threshold(int(player.level)):
		player.xp -= xp_threshold(int(player.level))
		player.level += 1
		player.points += int(sim.catalog.settings.points_per_level)
		emit_event("level_up", {"level": player.level})

func xp_multiplier() -> float:
	var player: Dictionary = sim.state.player
	var multiplier: float = float(sim.catalog.settings.xp_multiplier) * sim.multiplier("xp")
	multiplier *= Formulas.mood_xp(float(player.needs.mood)) * (1.0 + maxf(0.0, effective_stat("intellect") - 5.0) * 0.01)
	for id in player.perks:
		multiplier *= float(definition("perks", id).get("xp_multiplier", 1.0))
	return multiplier

func xp_threshold(level: int) -> int:
	var rules := definition("balance_rules", "progression")
	var late := maxi(0, level - int(rules.get("late_level_after", 8)))
	return maxi(1, int(sim.catalog.settings.xp_base) + (level - 1) * int(sim.catalog.settings.xp_growth) + late * late * int(rules.get("late_level_growth", 3)))

func need_decay_per_minute(id: String) -> float:
	return float(sim.catalog.settings.need_decay_per_hour.get(id, 0.0)) * sim.multiplier("need_decay") / 60.0

func rest_energy_per_minute() -> float:
	return float(sim.catalog.settings.rest_per_minute)

func tick(minute: int) -> void:
	var player: Dictionary = sim.state.player
	for need in sim.catalog.settings.need_decay_per_hour:
		if need == "satiety" and not sim.services.preferences.rule("satiety_enabled", true): continue
		adjust_need(str(need), -need_decay_per_minute(str(need)))
	if sim.resting:
		adjust_need("energy", rest_energy_per_minute())
		adjust_need("health", 0.02)
		if float(player.needs.satiety) >= 20: adjust_need("mood", 0.0015)
	if float(player.needs.energy) >= 20 and float(player.needs.satiety) >= 20:
		adjust_need("mood", (60.0 - float(player.needs.mood)) * 0.00005)
	if float(player.needs.satiety) <= 0.0 and sim.services.preferences.rule("satiety_enabled", true):
		adjust_need("health", -0.05)
		if minute % 1440 == 0 and sim.services.preferences.rule("starvation_attrition", false):
			for stat in ["strength", "agility", "endurance"]: player.stats[stat] = maxf(1.0, float(player.stats[stat]) - 0.25)
			emit_event("starvation_attrition", {})
	if float(player.needs.energy) < 20.0 or float(player.needs.satiety) < 20.0:
		adjust_need("mood", -0.01)
	for id in player.effects.keys():
		if int(player.effects[id].expires) <= minute:
			player.effects.erase(id)
			emit_event("effect_expired", {"id": id})
	if minute % 60 == 0:
		for id in player.addictions:
			var addiction: Dictionary = player.addictions[id]
			var substance := definition("substances", id)
			if minute - int(addiction.last_use) >= int(substance.get("withdrawal_after", 1440)):
				if float(addiction.exposure) >= 50.0:
					adjust_need("energy", -float(substance.get("withdrawal_cost", 1)))
				addiction.exposure = maxf(0.0, float(addiction.exposure) - 1.0)
