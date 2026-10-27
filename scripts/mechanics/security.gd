extends "res://scripts/mechanics/core/module.gd"
## Entirely fictional theft, witnesses and police consequences inside the sim.

func execute(operation: String, args: Dictionary) -> Dictionary:
	if operation == "begin_burglary": return _begin_burglary(args)
	if operation == "pay_fine":
		var amount := int(sim.state.security.fine)
		if amount <= 0: return Rules.fail("no_fine")
		if sim.state.economy.cash < amount: return Rules.fail("insufficient_funds")
		sim.state.economy.cash -= amount
		sim.state.security.fine = 0
		sim.state.world.heat = 0.0
		return Rules.ok()
	if operation == "serve_sentence":
		if sim.state.security.fine <= 0: return Rules.fail("no_sentence")
		var duration := mini(1440, 60 + int(sim.state.security.fine))
		sim.state.security.fine = 0
		sim.state.world.heat = 0.0
		return sim.advance(duration)
	if not operation in ["steal", "burglary"]: return Rules.fail("unknown_operation")
	var id := str(args.get("npc", ""))
	if not sim.state.social.npcs.has(id): return Rules.fail("unknown_npc")
	var npc: Dictionary = sim.state.social.npcs[id]
	var item := str(args.get("item", ""))
	if not item.is_empty() and int(npc.inventory.get(item, 0)) < 1: return Rules.fail("target_item_missing")
	if operation == "steal" and npc.location != sim.state.world.location: return Rules.fail("npc_not_present")
	if operation == "burglary":
		if npc.home != sim.state.world.location: return Rules.fail("wrong_target_home")
		var tool: Dictionary = sim.services.inventory.change("lockpick", -1)
		if not tool.ok: return tool
	var witnesses := 0
	for other_id in sim.state.social.npcs:
		if other_id != id and sim.state.social.npcs[other_id].location == sim.state.world.location: witnesses += 1
	var chance := clampf(0.25 + sim.services.character.effective_stat("cunning") * 0.025 + sim.state.player.skills.get("stealth", 0) * 0.002 - witnesses * 0.06 - sim.state.world.heat * 0.003, 0.03, 0.95)
	var success: bool = sim.rng.randf() < chance
	var taken := 0
	if success:
		if not item.is_empty():
			if int(npc.inventory.get(item, 0)) < 1: return Rules.fail("target_item_missing")
			var added: Dictionary = sim.services.inventory.change(item, 1)
			if not added.ok: return added
			npc.inventory[item] -= 1
			if npc.inventory[item] == 0: npc.inventory.erase(item)
			if str(npc.get("weapon", "")) == item and not npc.inventory.has(item): npc.weapon = ""
			_clear_unowned_equipment(npc)
		else:
			taken = mini(int(npc.money), sim.rng.randi_range(5, 40))
			npc.money -= taken
			sim.state.economy.cash += taken
	else:
		sim.state.world.heat = minf(100.0, float(sim.state.world.heat) + 15.0 + witnesses * 5.0)
		sim.state.security.fine += 20 + witnesses * 10
		if sim.state.world.heat >= 60.0: emit_event("wanted", {"fine": sim.state.security.fine})
		sim.services.social.change_relationship(id, "player", {"trust": -20, "affinity": -10})
		sim.services.social.remember(id, "crime", {"caught": true, "witnesses": witnesses})
	sim.state.security.incidents.append({"operation": operation, "target": id, "success": success, "minute": sim.state.clock.total_minutes})
	while sim.state.security.incidents.size() > 64: sim.state.security.incidents.pop_front()
	var result: Dictionary = sim.services.character.execute("train", {"skill": "stealth", "xp": 4 if success else 1})
	if not result.ok: return result
	result = sim.advance(10 if operation == "steal" else 30)
	if not result.ok: return result
	return Rules.ok({"success": success, "chance": chance, "witnesses": witnesses, "money": taken})

func _begin_burglary(args: Dictionary) -> Dictionary:
	var npc := str(args.get("npc", ""))
	if not sim.state.social.npcs.has(npc): return Rules.fail("unknown_npc")
	if sim.state.social.npcs[npc].home != sim.state.world.location: return Rules.fail("wrong_target_home")
	var item := str(args.get("item", ""))
	if not item.is_empty():
		if int(sim.state.social.npcs[npc].inventory.get(item, 0)) < 1: return Rules.fail("target_item_missing")
		if sim.services.inventory.weight() + float(definition("items", item).get("weight", 0)) - float(definition("items", "lockpick").get("weight", 0)) > sim.services.inventory.capacity(): return Rules.fail("inventory_capacity")
	var removed: Dictionary = sim.services.inventory.change("lockpick", -1)
	if not removed.ok: return removed
	var result: Dictionary = sim.services.encounters.execute("game_start", {"type": "lockpick", "limit": 5})
	if not result.ok: return result
	sim.state.encounters.game.context = {"kind": "burglary", "npc": npc, "item": item, "resolved": false}
	return Rules.ok()

func resolve_burglary(context: Dictionary, status: String) -> void:
	if context.resolved: return
	context.resolved = true
	var npc: Dictionary = sim.state.social.npcs[context.npc]
	if status == "won":
		if str(context.item).is_empty():
			var taken := mini(30, int(npc.money))
			npc.money -= taken
			sim.state.economy.cash += taken
		else:
			var added: Dictionary = sim.services.inventory.change(str(context.item), 1)
			if added.ok:
				npc.inventory[context.item] -= 1
				if npc.inventory[context.item] == 0: npc.inventory.erase(context.item)
				if str(npc.get("weapon", "")) == str(context.item) and not npc.inventory.has(context.item): npc.weapon = ""
				_clear_unowned_equipment(npc)
	else:
		sim.state.security.fine += 50
		sim.state.world.heat = minf(100.0, float(sim.state.world.heat) + 30.0)
		sim.services.social.change_relationship(str(context.npc), "player", {"trust": -20})
		if sim.services.has("npc_agency") and sim.services.npc_agency.enabled(): sim.services.social.remember(str(context.npc), "crime", {"caught": true, "actor": "player"})
	sim.services.character.execute("train", {"skill": "stealth", "xp": 5 if status == "won" else 1})
	sim.advance(15)
	emit_event("burglary_resolved", {"npc": context.npc, "success": status == "won"})

func _clear_unowned_equipment(npc: Dictionary) -> void:
	for slot in npc.equipped.keys():
		if int(npc.inventory.get(npc.equipped[slot], 0)) < 1:
			npc.equipped.erase(slot)
			npc.outfit = ""
