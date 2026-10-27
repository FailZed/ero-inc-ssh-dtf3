extends "res://scripts/mechanics/core/module.gd"

func attribute_threshold(value: float) -> int:
	var rules := definition("balance_rules", "progression")
	var progress := maxf(0, value - 10)
	return int(rules.get("attribute_base", 100)) + int(progress * float(rules.get("attribute_linear", 12)) + progress * progress * float(rules.get("attribute_quadratic", 0.2)))

func execute(operation: String, args: Dictionary) -> Dictionary:
	if operation != "practice": return Rules.fail("unknown_operation")
	var id := str(args.get("id", ""))
	var program := definition("training_programs", id)
	if program.is_empty(): return Rules.fail("unknown_training")
	if not Rules.check(sim.state, program.get("requirements", {})): return Rules.fail("training_requirements")
	if program.has("location") and program.location != sim.state.world.location: return Rules.fail("wrong_location")
	var key := "training:%s:%d" % [id, sim.state.clock.day_index]
	if int(sim.state.counters.get(key, 0)) >= int(program.get("daily_limit", 3)): return Rules.fail("overtraining_limit")
	var energy: float = float(program.get("energy", 5)) * sim.multiplier("resource_cost")
	var cost := int(program.get("cost", 0))
	if sim.state.player.needs.energy < energy: return Rules.fail("insufficient_energy")
	if sim.state.economy.cash < cost: return Rules.fail("insufficient_funds")
	sim.services.character.adjust_need("energy", -energy)
	sim.state.economy.cash -= cost
	sim.state.counters[key] = int(sim.state.counters.get(key, 0)) + 1
	for stat in program.get("attributes", {}):
		if float(sim.state.player.stats[stat]) >= float(sim.catalog.settings.stat_cap): continue
		var xp := int(program.attributes[stat])
		sim.state.player.training[stat] = int(sim.state.player.training.get(stat, 0)) + xp
		while int(sim.state.player.training[stat]) >= attribute_threshold(float(sim.state.player.stats[stat])) and float(sim.state.player.stats[stat]) < float(sim.catalog.settings.stat_cap):
			sim.state.player.training[stat] -= attribute_threshold(float(sim.state.player.stats[stat]))
			sim.state.player.stats[stat] += 1
			emit_event("attribute_trained", {"id": stat, "value": sim.state.player.stats[stat]})
		if float(sim.state.player.stats[stat]) >= float(sim.catalog.settings.stat_cap): sim.state.player.training[stat] = 0
	for skill in program.get("skills", {}):
		var result: Dictionary = sim.services.character.execute("train", {"skill": skill, "xp": int(program.skills[skill])})
		if not result.ok: return result
	if program.has("effect"):
		var result: Dictionary = sim.services.character.add_effect(str(program.effect))
		if not result.ok: return result
	if id == "cinema": sim.services.character.adjust_need("mood", 12)
	return sim.advance(int(program.get("minutes", 30)))
