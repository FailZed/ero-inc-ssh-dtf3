extends "res://scripts/mechanics/core/module.gd"
## Visual descriptors and owned outfits. No dependency on portrait assets.

func initialize_npc(npc: Dictionary, template: Dictionary) -> void:
	npc.wardrobe = template.get("wardrobe", ["casual", "work", "training"]).duplicate()
	npc.equipped = {}
	npc.outfit = ""
	for outfit_id in npc.wardrobe:
		for item in definition("outfits", str(outfit_id)).get("items", []):
			npc.inventory[item] = maxi(1, int(npc.inventory.get(item, 0)))
	dress_for_context(npc)

func execute(operation: String, args: Dictionary) -> Dictionary:
	var target := str(args.get("target", "player"))
	var actor: Dictionary = sim.state.player if target == "player" else sim.state.social.npcs.get(target, {})
	if actor.is_empty(): return Rules.fail("unknown_appearance_target")
	match operation:
		"customize":
			for key in args.get("features", {}):
				if str(key) in ["pregnancy_stage", "outfit"]: return Rules.fail("reserved_appearance_feature")
			if args.get("features", {}).has("gender") and not args.features.gender in ["male", "female", "nonbinary"]: return Rules.fail("invalid_appearance_gender")
			if args.get("features", {}).has("morphology") and not args.features.morphology in ["human", "semi_furry", "furry"]: return Rules.fail("invalid_appearance_morphology")
			if args.get("features", {}).has("has_tail") and not args.features.has_tail is bool: return Rules.fail("invalid_appearance_tail")
			actor.appearance.merge(args.get("features", {}).duplicate(true), true)
			if target != "player" and args.get("features", {}).has("gender"): actor.gender = str(args.features.gender)
		"outfit":
			var outfit_id := str(args.get("id", ""))
			var result := _wear(actor, outfit_id, target == "player")
			if not result.ok: return result
		"equip":
			if target == "player": return sim.services.inventory.execute("equip", args)
			var item := str(args.get("id", ""))
			var spec := definition("items", item)
			if not spec.has("slot") or int(actor.inventory.get(item, 0)) < 1: return Rules.fail("item_not_equippable")
			if not _requirements(actor, item): return Rules.fail("equipment_requirements")
			if spec.get("slot", "") == "weapon": actor.weapon = item
			else: actor.equipped[str(spec.slot)] = item
			actor.outfit = ""
		"unequip":
			if target == "player": return sim.services.inventory.execute("unequip", args)
			var slot := str(args.get("slot", ""))
			if slot == "weapon": actor.weapon = ""
			else: actor.equipped.erase(slot)
			actor.outfit = ""
		_: return Rules.fail("unknown_operation")
	emit_event("appearance_changed", {"target": target})
	return Rules.ok({"descriptor": descriptor(target)})

func _wear(actor: Dictionary, outfit_id: String, player: bool = false) -> Dictionary:
	var spec := definition("outfits", outfit_id)
	if spec.is_empty(): return Rules.fail("unknown_outfit")
	var items: Dictionary = sim.state.inventory.items if player else actor.inventory
	var equipped: Dictionary = sim.state.inventory.equipped if player else actor.equipped
	for item in spec.items:
		if int(items.get(item, 0)) < 1: return Rules.fail("outfit_item_not_owned")
		if not _requirements(actor, item): return Rules.fail("equipment_requirements")
	# All ownership and requirements are checked before changing a slot.
	for slot in equipped.keys():
		if definition("items", str(equipped[slot])).get("category", "") == "clothing": equipped.erase(slot)
	for item in spec.items: equipped[str(definition("items", item).slot)] = item
	if not player: actor.outfit = outfit_id
	return Rules.ok()

func _requirements(actor: Dictionary, item: String) -> bool:
	var context: Dictionary = sim.state.duplicate()
	context.player = actor
	return Rules.check(context, definition("items", item).get("requirements", {}))

func dress_for_context(npc: Dictionary) -> void:
	for outfit_id in npc.wardrobe:
		var spec := definition("outfits", str(outfit_id))
		if not str(npc.activity) in spec.get("activities", [npc.activity]): continue
		if not npc.location in spec.get("locations", [npc.location]): continue
		if not str(sim.state.world.weather) in spec.get("weather", [sim.state.world.weather]): continue
		if _wear(npc, str(outfit_id)).ok: return
	# A missing/stolen piece must not be conjured back into the wardrobe.
	for outfit_id in npc.wardrobe:
		if _wear(npc, str(outfit_id)).ok: return

func descriptor(target: String = "player") -> Dictionary:
	var actor: Dictionary = sim.state.player if target == "player" else sim.state.social.npcs.get(target, {})
	if actor.is_empty(): return {}
	var result: Dictionary = actor.appearance.duplicate(true)
	result.morphology = str(result.get("morphology", "human"))
	# A semi-furry keeps a human face/skin; a furry needs its own muzzle/fur art.
	result.anatomy = {"face": "muzzle" if result.morphology == "furry" else "human", "covering": "fur" if result.morphology == "furry" else "skin", "animal_ears": result.morphology != "human", "tail": bool(result.get("has_tail", result.morphology == "furry")) and result.morphology != "human"}
	if target != "player": result.gender = actor.gender
	result.equipment = {}
	var equipped: Dictionary = sim.state.inventory.equipped if target == "player" else actor.equipped.duplicate()
	if target != "player" and not str(actor.weapon).is_empty(): equipped.weapon = actor.weapon
	for slot in equipped:
		var item := str(equipped[slot])
		result.equipment[slot] = {"item": item, "visual": definition("items", item).get("visual", item)}
	return result
