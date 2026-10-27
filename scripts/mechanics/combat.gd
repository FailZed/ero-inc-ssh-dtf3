extends "res://scripts/mechanics/core/module.gd"
const Formulas = preload("res://scripts/mechanics/core/formulas.gd")

func execute(operation: String, args: Dictionary) -> Dictionary:
	if operation == "start": return start(str(args.get("npc", "")))
	if operation == "action": return action(args)
	return Rules.fail("unknown_operation")

func start(id: String) -> Dictionary:
	if not sim.state.social.npcs.has(id): return Rules.fail("unknown_npc")
	var npc: Dictionary = sim.state.social.npcs[id]
	if npc.location != sim.state.world.location: return Rules.fail("npc_not_present")
	if sim.services.health.hp("player") <= 0.0 or float(npc.health) <= 0.0: return Rules.fail("combatant_incapacitated")
	sim.state.encounters.combat = {"npc": id, "status": "active", "ap": 4, "turn": 1,
		"player_hp": sim.services.health.hp("player"), "npc_hp": float(npc.health), "guard": false,
		"injuries": npc.injuries.duplicate(true), "log": [], "stamina": {"player": 100.0, "npc": 100.0},
		"stances": {"player": "balanced", "npc": str(npc.get("combat_style", "balanced"))},
		"statuses": {"player": {}, "npc": {}}, "last_target": "body", "rewarded": false}
	return Rules.ok()

func weapon(id: String) -> Dictionary:
	var item_id := str(sim.state.inventory.equipped.get("weapon", "")) if id == "player" else str(sim.state.social.npcs[id].get("weapon", ""))
	return definition("weapons", str(definition("items", item_id).get("weapon", "unarmed")))

func stat(id: String, key: String) -> float:
	if id == "player": return sim.services.character.effective_stat(key)
	return float(sim.state.social.npcs[id].stats.get(key, 5)) * sim.services.health.stat_multiplier(id, key)

func forecast(move_id: String, part: String = "body", attacker: String = "player", power: float = 1.0) -> Dictionary:
	var move := definition("combat_moves", move_id)
	if move.is_empty() or not part in ["head", "body", "arms", "legs"]: return Rules.fail("invalid_move_or_part")
	if not is_finite(power) or power < 0.5 or power > 1.5: return Rules.fail("invalid_attack_power")
	var combat: Dictionary = sim.state.encounters.combat
	if combat.is_empty(): return Rules.fail("no_active_combat")
	if attacker != "player" and attacker != str(combat.npc): return Rules.fail("invalid_attacker")
	var defender := str(combat.npc) if attacker == "player" else "player"
	var attack_weapon := weapon(attacker)
	if not str(attack_weapon.get("class", "unarmed")) in move.get("weapons", ["unarmed", "knuckles", "blade", "blunt"]): return Rules.fail("move_requires_weapon")
	var actor_key := "player" if attacker == "player" else "npc"
	var defender_key := "player" if defender == "player" else "npc"
	var stance := str(combat.stances[actor_key])
	var model := Formulas.combat(stat(attacker, "strength"), stat(attacker, "agility"), stat(defender, "agility"), stat(attacker, "luck"), move, float(attack_weapon.get("damage", 0)), power, definition("formula_rules", "combat"))
	var accuracy := float(model.accuracy) - (0.15 if part == "head" else 0.0) - (power - 1.0) * 0.15
	accuracy += float(sim.services.preferences.rule("combat_accuracy" if attacker == "player" else "enemy_accuracy", 0.0))
	var experience: float = sim.state.player.skills.get("fighting", 0) if defender == "player" else sim.state.social.npcs[defender].skills.get("fighting", 0)
	accuracy *= 1.0 - Formulas.auto_defence(experience)
	if combat.statuses[defender_key].has("exposed"): accuracy = minf(0.97, accuracy + 0.15)
	var injury_penalty: float = sim.services.health.stat_multiplier(attacker, "strength")
	var damage := float(model.damage)
	damage *= 1.35 if part == "head" else (0.8 if part in ["arms", "legs"] else 1.0)
	if stance == "aggressive":
		damage *= 1.2
		accuracy -= 0.08
	elif stance == "defensive": damage *= 0.85
	return Rules.ok({"accuracy": clampf(accuracy, 0.05, 0.97), "damage": maxf(0.0, damage),
		"critical": float(model.critical), "knockdown": float(model.knockdown), "auto_defence": Formulas.auto_defence(experience),
		"ap": int(move.get("ap", 2)), "stamina": float(move.get("stamina", 8)) * power,
		"injury_multiplier": injury_penalty})

func action(args: Dictionary) -> Dictionary:
	var combat: Dictionary = sim.state.encounters.combat
	if combat.is_empty() or combat.status != "active": return Rules.fail("no_active_combat")
	var action_id := str(args.get("action", "attack"))
	match action_id:
		"attack":
			var move := str(args.get("move", "heavy" if bool(args.get("heavy", false)) else "jab"))
			var part := str(args.get("part", "body"))
			var power := float(args.get("power", 1.0))
			if power < 0.5 or power > 1.5: return Rules.fail("invalid_attack_power")
			var preview := forecast(move, part, "player", power)
			if not preview.ok: return preview
			if int(combat.ap) < int(preview.data.ap): return Rules.fail("insufficient_action_points")
			if float(combat.stamina.player) < float(preview.data.stamina): return Rules.fail("insufficient_stamina")
			combat.ap -= int(preview.data.ap)
			_strike("player", str(combat.npc), move, part, power)
		"guard":
			if not str(args.get("part", "body")) in ["head", "body", "arms", "legs"]: return Rules.fail("invalid_guard_part")
			if combat.ap < 1: return Rules.fail("insufficient_action_points")
			combat.ap -= 1
			combat.guard = true
			combat.statuses.player.guard_part = str(args.get("part", "body"))
		"stance":
			var stance := str(args.get("id", "balanced"))
			if not stance in ["balanced", "defensive", "aggressive"]: return Rules.fail("unknown_stance")
			if stance == combat.stances.player: return Rules.fail("stance_already_active")
			if combat.ap < 1: return Rules.fail("insufficient_action_points")
			combat.ap -= 1
			combat.stances.player = stance
		"recover":
			combat.stamina.player = minf(100.0, float(combat.stamina.player) + 25.0)
			combat.ap = 0
		"intimidate":
			if combat.ap < 4: return Rules.fail("insufficient_action_points")
			combat.ap = 0
			var chance := clampf(0.2 + (stat("player", "authority") - stat(str(combat.npc), "authority")) * 0.025 + (100.0 - float(combat.npc_hp)) * 0.005, 0.05, 0.85)
			if sim.rng.randf() < chance: combat.status = "surrendered"
		"escape":
			if sim.rng.randf() < clampf(0.5 + (stat("player", "agility") - stat(str(combat.npc), "agility")) * 0.03, 0.1, 0.9): combat.status = "escaped"
			else: combat.ap = 0
		"end_turn": combat.ap = 0
		_: return Rules.fail("unknown_combat_action")
	_update_outcome()
	if combat.status == "active" and combat.ap <= 0: _enemy_turn()
	_update_outcome()
	return Rules.ok({"status": combat.status, "ap": combat.ap})

func _strike(attacker: String, defender: String, move_id: String, part: String, power: float = 1.0) -> void:
	var combat: Dictionary = sim.state.encounters.combat
	var actor_key := "player" if attacker == "player" else "npc"
	var defender_key := "player" if defender == "player" else "npc"
	var move := definition("combat_moves", move_id)
	var prediction: Dictionary = forecast(move_id, part, attacker, power).data
	combat.stamina[actor_key] -= float(prediction.stamina)
	combat.statuses[defender_key].erase("exposed")
	var hit: bool = sim.rng.randf() < float(prediction.accuracy)
	var damage := 0.0
	var critical := false
	if hit:
		critical = sim.rng.randf() < float(prediction.critical)
		damage = float(prediction.damage) * (1.7 if critical else 1.0)
		var defence := stat(defender, "endurance") * 0.12 + float(weapon(defender).get("defence", 0))
		if combat.stances[defender_key] == "defensive": defence += 2.0
		damage = maxf(0.5, damage - defence)
		if defender_key == "player" and combat.guard:
			damage *= 0.3 if combat.statuses.player.get("guard_part", "body") == part else 0.6
		var bleed := float(move.get("bleeding", 0.0)) + float(weapon(attacker).get("bleeding", 0.0))
		sim.services.health.injure(defender, part, damage, bleed)
		if sim.rng.randf() < float(prediction.knockdown):
			combat.statuses[defender_key].knockdown = 1
		if move.get("special", "") == "feint": combat.statuses[defender_key].exposed = 1
		if move.get("special", "") == "disarm":
			if defender == "player": sim.state.inventory.equipped.erase("weapon")
			else: sim.state.social.npcs[defender].weapon = ""
	combat.log.append({"actor": actor_key, "move": move_id, "part": part, "hit": hit, "damage": damage, "critical": critical})
	combat.player_hp = sim.services.health.hp("player")
	combat.npc_hp = sim.services.health.hp(str(combat.npc))
	combat.injuries = sim.state.social.npcs[combat.npc].injuries.duplicate(true)
	combat.last_target = part

func _enemy_turn() -> void:
	var combat: Dictionary = sim.state.encounters.combat
	var npc_id := str(combat.npc)
	combat.npc_ap = 0
	if int(combat.statuses.npc.get("knockdown", 0)) > 0:
		combat.statuses.npc.erase("knockdown")
		combat.log.append({"actor": "npc", "action": "stand_up"})
	elif float(combat.stamina.npc) < 15.0:
		combat.stamina.npc = minf(100.0, float(combat.stamina.npc) + 30.0)
		combat.log.append({"actor": "npc", "action": "recover"})
	else:
		var npc_ap := 4
		combat.npc_ap = npc_ap
		while npc_ap > 0 and combat.status == "active":
			var selection := _enemy_move(npc_id, npc_ap)
			if selection.is_empty(): break
			npc_ap -= int(definition("combat_moves", selection).get("ap", 2))
			combat.npc_ap = npc_ap
			_strike(npc_id, "player", selection, _enemy_target(npc_id, selection))
			_update_outcome()
	combat.guard = false
	combat.turn += 1
	combat.ap = 4
	combat.stamina.player = minf(100.0, float(combat.stamina.player) + 8.0)
	combat.stamina.npc = minf(100.0, float(combat.stamina.npc) + 5.0)
	if int(combat.statuses.player.get("knockdown", 0)) > 0:
		combat.ap = 2
		combat.statuses.player.erase("knockdown")

func _enemy_move(npc_id: String, available_ap: int) -> String:
		var candidates: Array = []
		var total_weight := 0.0
		var best_weight := -1.0
		var best_move := ""
		for id in sim.catalog.combat_moves:
			var possible := forecast(str(id), "body", npc_id)
			if not possible.ok or int(possible.data.ap) > available_ap or float(possible.data.stamina) > float(sim.state.encounters.combat.stamina.npc): continue
			var move := definition("combat_moves", str(id))
			if move.get("special", "") == "disarm" and weapon("player").get("class", "unarmed") == "unarmed": continue
			var utility := maxf(0.1, float(possible.data.damage) * float(possible.data.accuracy) / int(possible.data.ap))
			var combat: Dictionary = sim.state.encounters.combat
			var traits: Dictionary = sim.state.social.npcs[npc_id].traits
			utility *= 1.0 + (float(traits.bravery) if int(possible.data.ap) >= 3 else float(traits.responsibility)) / 100.0
			if move.get("special", "") == "feint": utility *= 3.0 if combat.guard else 0.2
			if combat.stances.npc == "defensive": utility *= float(possible.data.accuracy)
			if utility > best_weight:
				best_weight = utility
				best_move = str(id)
			total_weight += utility
			candidates.append([id, total_weight])
		var move_id := ""
		if sim.rng.randf() < float(sim.services.preferences.rule("npc_tactics", 0.5)): return best_move
		var roll: float = sim.rng.randf() * total_weight
		for candidate in candidates:
			if roll < float(candidate[1]):
				move_id = str(candidate[0])
				break
		return move_id

func _enemy_target(npc_id: String, move: String = "jab") -> String:
	var traits: Dictionary = sim.state.social.npcs[npc_id].get("traits", {})
	var weights := {"head": 2.0 + float(traits.get("bravery", 50)) / 50.0,
		"body": 4.0 + float(traits.get("responsibility", 50)) / 50.0, "arms": 2.0, "legs": 2.0 + float(traits.get("cunning", 50)) / 50.0}
	var total := 0.0
	var best_part := "body"
	var best_value := -1.0
	for part in weights:
		var combat: Dictionary = sim.state.encounters.combat
		if combat.guard and part == str(combat.statuses.player.get("guard_part", "body")):
			var experience := float(sim.state.social.npcs[npc_id].skills.get("fighting", 0))
			weights[part] *= 1.0 - Formulas.target_switch(experience)
		weights[part] += float(sim.state.player.injuries.get(part, 0.0)) / 50.0
		var prediction: Dictionary = forecast(move, str(part), npc_id).data
		var expected := float(prediction.damage) * float(prediction.accuracy)
		if combat.guard: expected *= 0.3 if part == str(combat.statuses.player.get("guard_part", "body")) else 0.6
		if expected > best_value:
			best_value = expected
			best_part = str(part)
		total += float(weights[part])
	if sim.rng.randf() < float(sim.services.preferences.rule("npc_tactics", 0.5)): return best_part
	var roll: float = sim.rng.randf() * total
	for part in weights:
		roll -= float(weights[part])
		if roll <= 0.0: return part
	return "body"

func _update_outcome() -> void:
	var combat: Dictionary = sim.state.encounters.combat
	if combat.npc_hp <= 0.0: combat.status = "won"
	elif combat.player_hp <= 0.0: combat.status = "lost"
	if combat.status == "active" or combat.rewarded: return
	combat.rewarded = true
	var npc: Dictionary = sim.state.social.npcs[combat.npc]
	npc.skills.fighting = int(npc.skills.get("fighting", 0)) + 5
	sim.services.social.change_relationship(str(combat.npc), "player", {"fear": 10 if combat.status in ["won", "surrendered"] else -2, "affinity": -5})
	if sim.services.has("npc_agency") and sim.services.npc_agency.enabled():
		sim.services.social.remember(str(combat.npc), "violence", {"actor": "player", "status": combat.status})
	if combat.status == "won": sim.services.character.execute("train", {"skill": "fighting", "xp": 15})
	emit_event("combat_finished", {"status": combat.status, "npc": combat.npc})
