extends "res://scripts/mechanics/core/module.gd"

func weight() -> float:
	var result := 0.0
	for id in sim.state.inventory.items:
		result += float(definition("items", id).get("weight", 0.0)) * int(sim.state.inventory.items[id])
	return result

func change(id: String, quantity: int) -> Dictionary:
	var item := definition("items", id)
	if item.is_empty() or quantity == 0: return Rules.fail("invalid_item_or_quantity")
	var inventory: Dictionary = sim.state.inventory
	var next := int(inventory.items.get(id, 0)) + quantity
	if next < 0: return Rules.fail("insufficient_items")
	if quantity > 0 and weight() + quantity * float(item.get("weight", 0.0)) > capacity() + 0.00001:
		return Rules.fail("inventory_capacity")
	if next == 0:
		inventory.items.erase(id)
		for slot in inventory.equipped.keys():
			if inventory.equipped[slot] == id: inventory.equipped.erase(slot)
	else:
		inventory.items[id] = next
	return Rules.ok({"quantity": next})

func capacity() -> float:
	return float(sim.catalog.settings.base_capacity) + sim.services.character.effective_stat("strength") * 0.5

func execute(operation: String, args: Dictionary) -> Dictionary:
	var id := str(args.get("id", ""))
	var item := definition("items", id)
	var quantity := int(args.get("quantity", 1))
	match operation:
		"add": return change(id, quantity) if quantity > 0 else Rules.fail("invalid_quantity")
		"remove": return change(id, -quantity) if quantity > 0 else Rules.fail("invalid_quantity")
		"equip":
			if item.is_empty() or int(sim.state.inventory.items.get(id, 0)) <= 0 or not item.has("slot"):
				return Rules.fail("item_not_equippable")
			if not Rules.check(sim.state, item.get("requirements", {})): return Rules.fail("equipment_requirements")
			sim.state.inventory.equipped[str(item.slot)] = id
		"unequip":
			sim.state.inventory.equipped.erase(str(args.get("slot", "")))
		"use":
			if not item.has("restore") and not item.has("effect"): return Rules.fail("item_not_usable")
			var removed := change(id, -1)
			if not removed.ok: return removed
			for need in item.get("restore", {}):
				sim.services.character.adjust_need(need, float(item.restore[need]))
			if item.has("effect"):
				var result: Dictionary = sim.services.character.add_effect(str(item.effect))
				if not result.ok: return result
		"craft": return _craft(id)
		"buy", "sell": return _trade(operation, id, quantity, str(args.get("shop", "")))
		_:
			return Rules.fail("unknown_operation")
	return Rules.ok()

func _trade(operation: String, id: String, quantity: int, shop_id: String) -> Dictionary:
	var shop := definition("shops", shop_id)
	var item := definition("items", id)
	if shop.is_empty() or item.is_empty() or quantity <= 0 or not shop.get("stock", {}).has(id):
		return Rules.fail("invalid_trade")
	if shop.has("location") and shop.location != sim.state.world.location: return Rules.fail("wrong_location")
	if not sim.services.world.is_open(shop): return Rules.fail("shop_closed")
	if not sim.state.economy.shop_stock.has(shop_id): sim.state.economy.shop_stock[shop_id] = shop.stock.duplicate(true)
	var stock: Dictionary = sim.state.economy.shop_stock[shop_id]
	var unit_price := maxi(0, int(round(float(item.get("price", 0)) * float(shop.get("price_multiplier", 1.0)))))
	if operation == "buy":
		if int(stock[id]) < quantity: return Rules.fail("out_of_stock")
		if int(sim.state.economy.cash) < unit_price * quantity: return Rules.fail("insufficient_funds")
		var added := change(id, quantity)
		if not added.ok: return added
		sim.state.economy.cash -= unit_price * quantity
		stock[id] -= quantity
	else:
		var removed := change(id, -quantity)
		if not removed.ok: return removed
		unit_price = int(floor(unit_price * float(shop.get("sell_ratio", 0.5))))
		sim.state.economy.cash += unit_price * quantity
		stock[id] += quantity
	return Rules.ok({"total": unit_price * quantity})

func _craft(id: String) -> Dictionary:
	var recipe := definition("recipes", id)
	if recipe.is_empty(): return Rules.fail("unknown_recipe")
	if not Rules.check(sim.state, recipe.get("requirements", {})): return Rules.fail("recipe_requirements")
	for equipment in recipe.get("equipment", []):
		if not equipment in sim.state.world.equipment: return Rules.fail("missing_equipment")
	for ingredient in recipe.get("ingredients", {}):
		if int(sim.state.inventory.items.get(ingredient, 0)) < int(recipe.ingredients[ingredient]):
			return Rules.fail("missing_ingredients")
	for ingredient in recipe.get("ingredients", {}):
		var removed := change(ingredient, -int(recipe.ingredients[ingredient]))
		if not removed.ok: return removed
	var skill_value := int(sim.state.player.skills.get(str(recipe.get("skill", "cooking")), 0))
	var chance := clampf(float(recipe.get("success_chance", 0.65 + skill_value * 0.005)), 0.0, 1.0)
	var crafted: bool = sim.rng.randf() < chance
	if crafted:
		for output in recipe.get("outputs", {}):
			var added := change(output, int(recipe.outputs[output]))
			if not added.ok: return added
	var result: Dictionary = sim.advance(int(recipe.get("minutes", 10)))
	if not result.ok: return result
	if recipe.has("skill"):
		result = sim.services.character.execute("train", {"skill": recipe.skill, "xp": maxi(1, int(recipe.get("xp", 5)) if crafted else int(recipe.get("xp", 5)) / 2)})
		if not result.ok: return result
	emit_event("craft_completed", {"id": id, "crafted": crafted})
	return Rules.ok({"crafted": crafted, "chance": chance})

func tick(minute: int) -> void:
	if minute % 1440 != 0: return
	for shop_id in sim.state.economy.shop_stock:
		var shop := definition("shops", str(shop_id))
		for item in shop.get("stock", {}):
			if definition("items", str(item)).get("category", "") in ["food", "ingredient", "medicine", "medical"]:
				sim.state.economy.shop_stock[shop_id][item] = maxi(int(shop.stock[item]), int(sim.state.economy.shop_stock[shop_id].get(item, 0)))
