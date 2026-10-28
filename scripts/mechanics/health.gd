extends "res://scripts/mechanics/core/module.gd"
const Access = preload("res://scripts/mechanics/care_access.gd")
## Fictional game health rules. No real-world dosing or medical advice.
const PARTS := ["head", "body", "arms", "legs"]

func actor(id: String) -> Dictionary:
	return sim.state.player if id == "player" else sim.state.social.npcs.get(id, {})

func record(id: String) -> Dictionary:
	if not sim.state.healthcare.records.has(id):
		sim.state.healthcare.records[id] = {"bleeding": 0.0, "intoxication": 0.0, "infection": 0.0,
			"treatments": {}, "scars": {}, "care_until": 0, "low_energy_minutes": 0, "collapsed": false}
	return sim.state.healthcare.records[id]

func hp(id: String) -> float:
	var subject := actor(id)
	return float(subject.needs.health if id == "player" else subject.health)

func set_hp(id: String, value: float) -> void:
	if id == "player": sim.state.player.needs.health = clampf(value, 0.0, 100.0)
	else: sim.state.social.npcs[id].health = clampf(value, 0.0, 100.0)

func injure(id: String, part: String, damage: float, bleeding: float = 0.0) -> void:
	var subject := actor(id)
	var wound_damage: float = damage * float(sim.services.preferences.rule("injury_damage", 1.0)) if id == "player" else damage
	if wound_damage > 0: subject.injuries[part] = clampf(float(subject.injuries.get(part, 0.0)) + wound_damage, 0.0, 100.0)
	set_hp(id, hp(id) - damage)
	var medical := record(id)
	medical.bleeding = clampf(float(medical.bleeding) + bleeding, 0.0, 5.0)
	if float(subject.injuries.get(part, 0)) >= 60.0: medical.scars[part] = true

func stat_multiplier(id: String, stat: String) -> float:
	var subject := actor(id)
	var loss := 0.0
	if stat in ["strength", "agility", "endurance"]:
		var part := "legs" if stat == "agility" else ("arms" if stat == "strength" else "body")
		loss += float(subject.injuries.get(part, 0.0)) * 0.005
	if stat in ["intellect", "erudition", "cunning"]: loss += float(subject.injuries.get("head", 0.0)) * 0.004
	var medical: Dictionary = sim.state.healthcare.records.get(id, {})
	loss += float(medical.get("intoxication", 0.0)) * 0.003
	var modifier := 1.0
	for condition in sim.state.conditions.values():
		if condition.target == id and condition.status == "active":
			modifier *= float(definition("conditions", str(condition.id)).get("stat_multipliers", {}).get(stat, 1.0))
	return clampf((1.0 - loss) * modifier, 0.2, 1.0)

func execute(operation: String, args: Dictionary) -> Dictionary:
	var id := str(args.get("target", "player"))
	if actor(id).is_empty(): return Rules.fail("unknown_patient")
	var medical := record(id)
	match operation:
		"diagnose": return Rules.ok({"health": hp(id), "injuries": actor(id).injuries.duplicate(true), "medical": medical.duplicate(true)})
		"treat":
			var treatment_id := str(args.get("id", "bandage"))
			var treatment := definition("treatments", treatment_id)
			if treatment.is_empty(): return Rules.fail("unknown_treatment")
			if int(medical.treatments.get(treatment_id, 0)) > int(sim.state.clock.total_minutes): return Rules.fail("treatment_cooldown")
			var cost := int(treatment.get("cost", 0))
			if sim.state.economy.cash < cost: return Rules.fail("insufficient_funds")
			if treatment.has("item"):
				var removed: Dictionary = sim.services.inventory.change(str(treatment.item), -1)
				if not removed.ok: return removed
			sim.state.economy.cash -= cost
			medical.bleeding = maxf(0.0, float(medical.bleeding) - float(treatment.get("stop_bleeding", 0)))
			medical.infection = maxf(0.0, float(medical.infection) - float(treatment.get("infection", 0)))
			for part in actor(id).injuries.keys():
				actor(id).injuries[part] = maxf(0.0, float(actor(id).injuries[part]) - float(treatment.get("repair", 0)))
				if actor(id).injuries[part] <= 0.0: actor(id).injuries.erase(part)
			set_hp(id, hp(id) + float(treatment.get("restore", 0)))
			medical.care_until = maxi(int(medical.care_until), int(sim.state.clock.total_minutes) + int(treatment.get("care_minutes", 0)))
			medical.treatments[treatment_id] = int(sim.state.clock.total_minutes) + int(treatment.get("cooldown", 60))
			return sim.advance(int(treatment.get("minutes", 5)))
		"intoxicate":
			var amount := float(args.get("amount", 0))
			if amount <= 0.0 or amount > 100.0: return Rules.fail("invalid_intoxication")
			medical.intoxication = minf(100.0, float(medical.intoxication) + amount)
		"prenatal_care":
			return prenatal_care(id,"player")
		_:
			return Rules.fail("unknown_operation")
	return Rules.ok()

func prenatal_care(id: String, payer: String, elapse: bool = true) -> Dictionary:
	var key:=id+":pregnancy"
	if not sim.state.conditions.has(key) or sim.state.conditions[key].status!="active": return Rules.fail("no_active_pregnancy")
	if int(sim.state.conditions[key].get("next_care",0))>int(sim.state.clock.total_minutes): return Rules.fail("care_already_provided")
	if actor(payer).is_empty(): return Rules.fail("unknown_patient")
	if elapse and sim.state.get("npc_reproduction",{}).get("jobs",{}).has(id): return Rules.fail("clinical_visit_in_progress")
	var clinical: String = Access.clinic_blocked(sim,id,30,not elapse,payer)
	if not clinical.is_empty(): return Rules.fail(clinical)
	var funds := int(sim.state.economy.cash) if payer=="player" else int(actor(payer).money)
	if funds<30: return Rules.fail("insufficient_funds")
	if elapse:
		var elapsed: Dictionary = sim.advance(30)
		if not elapsed.ok: return elapsed
		if location_changed(id,payer): return Rules.fail("care_patient_moved")
		if sim.state.conditions.get(key,{}).get("status","")!="active": return Rules.fail("no_active_pregnancy")
		if int(sim.state.conditions[key].get("next_care",0))>int(sim.state.clock.total_minutes): return Rules.fail("care_already_provided")
	if payer=="player":
		if sim.state.economy.cash<30: return Rules.fail("insufficient_funds")
		sim.state.economy.cash-=30
	else:
		if int(actor(payer).money)<30: return Rules.fail("insufficient_funds")
		actor(payer).money-=30
	sim.state.conditions[key].last_care_day=sim.state.clock.day_index
	sim.state.conditions[key].next_care=int(sim.state.clock.total_minutes)+1440
	sim.state.conditions[key].care=mini(100,int(sim.state.conditions[key].get("care",0))+10)
	return Rules.ok()

func location_changed(patient: String, payer: String) -> bool:
	return Access.location(sim,patient)!=Access.clinic(sim) or Access.location(sim,payer)!=Access.clinic(sim)

func tick(minute: int) -> void:
	for id in sim.state.healthcare.records:
		if actor(id).is_empty(): continue
		var medical: Dictionary = sim.state.healthcare.records[id]
		if float(medical.bleeding) > 0.0: set_hp(id, hp(id) - float(medical.bleeding) / 60.0)
		if minute % 60 == 0:
			medical.intoxication = maxf(0.0, float(medical.intoxication) - 20.0)
			var under_care := minute <= int(medical.care_until)
			if float(medical.bleeding) > 0.0 and not under_care: medical.infection = minf(100.0, float(medical.infection) + 0.2)
			var repair := 4.0 if under_care else 0.1
			if id == "player": repair *= float(sim.services.preferences.rule("injury_recovery", 1.0))
			for part in actor(id).injuries.keys():
				actor(id).injuries[part] = maxf(0.0, float(actor(id).injuries[part]) - repair)
				if actor(id).injuries[part] <= 0.0: actor(id).injuries.erase(part)
			if under_care: set_hp(id, hp(id) + 2.0)
			if float(medical.infection) >= 50.0: set_hp(id, hp(id) - 1.0)
	var player_medical := record("player")
	if sim.state.player.needs.energy <= 5.0:
		player_medical.low_energy_minutes += 1
		if int(player_medical.low_energy_minutes) >= int(definition("formula_rules", "survival").get("collapse_after_minutes", 180)) and not player_medical.collapsed and sim.services.preferences.rule("exhaustion_enabled", false):
			player_medical.collapsed = true
			player_medical.unconscious_until = minute + int(definition("formula_rules", "survival").get("unconscious_minutes", 120))
			emit_event("exhaustion", {"target": "player"})
	else:
		player_medical.low_energy_minutes = 0
		player_medical.collapsed = false
	if int(player_medical.get("unconscious_until", 0)) > minute:
		sim.services.character.adjust_need("energy", 0.3)
