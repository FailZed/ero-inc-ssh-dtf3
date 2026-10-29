extends "res://scripts/mechanics/core/module.gd"

func execute(operation: String, args: Dictionary) -> Dictionary:
	var id := str(args.get("id", ""))
	var spec := definition("properties", id)
	if spec.is_empty(): return Rules.fail("unknown_property")
	var housing: Dictionary = sim.state.housing
	if operation == "buy" or operation == "rent":
		if housing.properties.has(id): return Rules.fail("property_already_acquired")
		var price := int(spec.get("price" if operation == "buy" else "monthly_rent", 0))
		if sim.state.economy.cash < price: return Rules.fail("insufficient_funds")
		sim.state.economy.cash -= price
		housing.properties[id] = {"owned": operation == "buy", "equipment": {}, "tenants": [],
			"next_bill": sim.calendar.add_months(int(sim.state.clock.total_minutes), 1), "arrears": 0, "rent_income": 0, "tenant_arrears": {}, "original_homes": {}}
		return Rules.ok()
	if not housing.properties.has(id): return Rules.fail("property_not_acquired")
	var property: Dictionary = housing.properties[id]
	match operation:
		"move_in":
			if property.get("evicted", false): return Rules.fail("property_evicted")
			housing.residence = id
			sim.state.world.previous_location = sim.state.world.location
			sim.state.world.location = str(spec.get("location", "bedroom"))
			_refresh_equipment(property)
		"furnish":
			var item_id := str(args.get("item", ""))
			var item := definition("items", item_id)
			if not item.has("equipment"): return Rules.fail("not_furniture")
			if property.equipment.has(item_id): return Rules.fail("already_furnished")
			if property.equipment.size() >= int(spec.get("furniture_slots", 8)): return Rules.fail("furniture_capacity")
			var removed: Dictionary = sim.services.inventory.change(item_id, -1)
			if not removed.ok: return removed
			property.equipment[item_id] = 1
			if housing.residence == id: _refresh_equipment(property)
		"tenant":
			var npc := str(args.get("npc", ""))
			if not property.owned: return Rules.fail("subletting_unavailable")
			if not sim.state.social.npcs.has(npc) or npc in property.tenants: return Rules.fail("invalid_tenant")
			if property.tenants.size() >= int(spec.get("tenant_capacity", 1)): return Rules.fail("property_full")
			for other in housing.properties.values():
				if npc in other.tenants: return Rules.fail("tenant_already_housed")
			property.tenants.append(npc)
			property.original_homes[npc] = sim.state.social.npcs[npc].home
			sim.state.social.npcs[npc].home = str(spec.get("location", "bedroom"))
		"remove_tenant":
			var npc := str(args.get("npc", ""))
			if not npc in property.tenants: return Rules.fail("not_a_tenant")
			var person: Dictionary = sim.state.social.npcs[npc]
			var original := str(property.original_homes.get(npc, person.home))
			# A tenancy change is not a journey. The current task finishes or is
			# interrupted by its existing owner before agency plans a route home.
			person.home = original
			property.original_homes.erase(npc)
			property.tenants.erase(npc)
			property.tenant_arrears.erase(npc)
		"pay_arrears":
			if property.arrears <= 0: return Rules.fail("no_rent_arrears")
			if sim.state.economy.cash < property.arrears: return Rules.fail("insufficient_funds")
			sim.state.economy.cash -= int(property.arrears)
			property.arrears = 0
			if property.get("evicted", false): property.next_bill = sim.calendar.add_months(int(sim.state.clock.total_minutes), 1)
			property.evicted = false
		"sell", "end_lease":
			if not property.tenants.is_empty(): return Rules.fail("property_has_tenants")
			if operation == "sell" and not property.owned: return Rules.fail("property_not_owned")
			if operation == "end_lease" and property.owned: return Rules.fail("property_not_rented")
			if property.arrears > 0: return Rules.fail("unpaid_rent")
			var returned_weight := 0.0
			for item_id in property.equipment:
				var quantity := int(property.equipment[item_id])
				var item := definition("items", str(item_id))
				if item.is_empty() or quantity <= 0: return Rules.fail("invalid_furniture")
				returned_weight += quantity * float(item.get("weight", 0.0))
			if sim.services.inventory.weight() + returned_weight > sim.services.inventory.capacity() + 0.00001:
				return Rules.fail("inventory_capacity")
			for item_id in property.equipment:
				var returned: Dictionary = sim.services.inventory.change(str(item_id), int(property.equipment[item_id]))
				if not returned.ok: return returned
			if operation == "sell": sim.state.economy.cash += int(spec.get("price", 0) * float(spec.get("sell_ratio", 0.7)))
			housing.properties.erase(id)
			if housing.residence == id:
				housing.residence = ""
				sim.state.world.equipment.clear()
		"invite":
			if housing.residence != id: return Rules.fail("not_current_residence")
			return sim.services.social.execute("invite", {"id": args.get("npc", ""), "minutes": args.get("minutes", 60)})
		_:
			return Rules.fail("unknown_operation")
	return Rules.ok()

func _refresh_equipment(property: Dictionary) -> void:
	sim.state.world.equipment.clear()
	for item_id in property.equipment:
		var equipment := str(definition("items", item_id).get("equipment", ""))
		if not equipment.is_empty(): sim.state.world.equipment.append(equipment)

func tick(minute: int) -> void:
	for id in sim.state.housing.properties:
		var property: Dictionary = sim.state.housing.properties[id]
		if property.get("evicted", false): continue
		if minute < int(property.next_bill): continue
		var spec := definition("properties", id)
		if property.owned:
			for npc_id in property.tenants:
				var tenant: Dictionary = sim.state.social.npcs[npc_id]
				var due := int(spec.get("tenant_rent", 0))
				var paid := mini(int(tenant.money), due)
				tenant.money -= paid
				sim.state.economy.bank += paid
				property.rent_income += paid
				property.tenant_arrears[npc_id] = int(property.tenant_arrears.get(npc_id, 0)) + due - paid
				if paid < due: emit_event("tenant_rent_unpaid", {"id": id, "npc": npc_id})
		else:
			var due := int(spec.get("monthly_rent", 0))
			if not sim.services.preferences.rule("rent_enabled", true): due = 0
			if sim.state.economy.cash >= due: sim.state.economy.cash -= due
			else:
				property.arrears += due
				emit_event("rent_overdue", {"id": id, "arrears": property.arrears})
			if due > 0 and property.arrears >= due * int(definition("formula_rules", "survival").get("eviction_months", 2)) and sim.services.preferences.rule("eviction_enabled", false):
				if sim.state.housing.residence == id:
					sim.state.housing.residence = ""
					sim.state.world.equipment.clear()
					sim.state.world.location = str(sim.catalog.settings.start_location)
				property.evicted = true
				emit_event("housing_evicted", {"id": id, "arrears": property.arrears})
		property.next_bill = sim.calendar.add_months(int(property.next_bill), 1)
