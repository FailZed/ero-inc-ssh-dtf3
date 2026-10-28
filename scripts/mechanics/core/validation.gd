extends RefCounted
## Structural validation at the data boundary, before mutating a live session.
const Rules = preload("res://scripts/mechanics/core/rules.gd")
const Advanced = preload("res://scripts/mechanics/core/advanced_validation.gd")
const Agency = preload("res://scripts/mechanics/core/agency_validation.gd")
const Human = preload("res://scripts/mechanics/core/human_validation.gd")
const Dialogue = preload("res://scripts/mechanics/core/dialogue_validation.gd")

static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func fields(value: Variant, schema: Dictionary) -> bool:
	if not value is Dictionary: return false
	for key in schema:
		if not value.has(key): return false
		var item: Variant = value[key]
		match schema[key]:
			"d": if not item is Dictionary: return false
			"a": if not item is Array: return false
			"s": if not item is String: return false
			"n": if not number(item): return false
			"b": if not item is bool: return false
	return true

static func command_args(module_id: String, args: Dictionary) -> bool:
	if not Advanced.command_args(args): return false
	for key in args:
		var value: Variant = args[key]
		if key in ["id", "stat", "skill", "shop", "template", "name", "other", "text", "location", "action", "part", "type", "target", "slot", "npc", "task", "role", "project"]:
			if not value is String: return false
		elif key in ["age", "xp", "amount", "quantity", "minute", "minutes", "stake", "limit"]:
			if not number(value) or float(value) != int(value): return false
		elif key in ["incoming", "heavy", "enabled"]:
			if not value is bool: return false
		elif key in ["changes", "appearance"]:
			if not value is Dictionary: return false
		elif key == "value" and module_id == "encounters":
			if not number(value): return false
	if args.has("changes"):
		for key in args.changes:
			if key == "status":
				if not args.changes[key] is String: return false
			elif not number(args.changes[key]): return false
	return true

static func catalog_error(catalog: Dictionary) -> String:
	for group in catalog:
		if not catalog[group] is Dictionary: return "invalid_group:" + str(group)
	var settings: Dictionary = catalog.settings
	for key in ["stat_cap", "xp_base", "points_per_level", "base_capacity", "rest_per_minute", "memory_limit", "max_advance_minutes"]:
		if not number(settings.get(key)) or float(settings[key]) <= 0.0: return "invalid_setting:" + key
	for key in ["start_minutes", "start_cash", "xp_growth", "xp_multiplier", "treatment_cost", "credit_limit", "weekly_interest", "weekly_debt_interest"]:
		if not number(settings.get(key)) or float(settings[key]) < 0.0: return "invalid_setting:" + key
	if not settings.get("weather_types") is Array or settings.weather_types.is_empty(): return "invalid_weather"
	if not settings.get("disabled_tags") is Array or not settings.get("need_decay_per_hour") is Dictionary: return "invalid_settings"
	if not catalog.locations.has(str(settings.get("start_location", ""))): return "unknown_start_location"
	for key in settings.need_decay_per_hour:
		if not key in ["energy", "satiety", "health", "hygiene", "mood"] or not number(settings.need_decay_per_hour[key]) or float(settings.need_decay_per_hour[key]) < 0.0: return "invalid_need_decay"
	for group in ["effects", "perks", "substances", "items", "recipes", "shops", "locations", "jobs", "assets", "properties", "projects", "lessons", "npc_templates", "npc_activities", "interactions", "organizations", "group_projects", "actions", "quests", "events", "achievements", "conditions"]:
		for id in catalog[group]:
			var entry: Variant = catalog[group][id]
			if not entry is Dictionary: return "invalid_definition:%s.%s" % [group, id]
			for key in ["minutes", "price", "weight", "energy", "pay", "xp", "cost", "effort", "deadline_minutes", "duration", "cooldown", "daily_limit", "capacity", "max_level", "daily_income", "daily_expense", "monthly_rent", "tenant_rent", "tenant_capacity", "furniture_slots"]:
				if entry.has(key) and (not number(entry[key]) or float(entry[key]) < 0.0): return "negative_or_invalid:%s.%s.%s" % [group, id, key]
			if entry.has("hours"):
				if not entry.hours is Array or entry.hours.size() != 2: return "invalid_hours"
				for hour in entry.hours:
					if not number(hour) or float(hour) < 0 or float(hour) >= 1440: return "invalid_hours"
			if entry.has("weekdays"):
				if not entry.weekdays is Array: return "invalid_weekdays"
				for weekday in entry.weekdays:
					if not number(weekday) or int(weekday) < 1 or int(weekday) > 7: return "invalid_weekdays"
			for field in ["effects", "rewards"]:
				if not entry.get(field, []) is Array: return "invalid_effects"
				for effect in entry.get(field, []):
					if not effect is Dictionary or not effect.get("kind") is String: return "invalid_effect"
	for quest in catalog.quests.values():
		if not quest.get("objectives") is Dictionary or quest.objectives.is_empty() or not quest.get("bindings",{}) is Dictionary: return "invalid_quest_definition"
		for objective in quest.objectives:
			if (not number(quest.objectives[objective]) or quest.objectives[objective] < 1 or quest.objectives[objective] > 1000000 or int(quest.objectives[objective]) != quest.objectives[objective]): return "invalid_quest_objective"
		for objective in quest.get("bindings",{}):
			if not quest.objectives.has(objective) or not quest.bindings[objective] is Array or quest.bindings[objective].is_empty(): return "invalid_quest_binding"
			for binding in quest.bindings[objective]:
				if not fields(binding,{"module":"s","operation":"s"}) or not binding.get("args",{}) is Dictionary or not binding.get("result",{}) is Dictionary: return "invalid_quest_binding"
				if not binding.get("different_days",false) is bool or not binding.get("unique_arg","") is String: return "invalid_quest_binding"
	for id in catalog.actions:
		var action: Dictionary = catalog.actions[id]
		if not action.get("costs", {}) is Dictionary: return "invalid_costs"
		for path in action.get("costs", {}):
			if not path in ["economy.cash", "economy.bank", "player.needs.energy", "player.needs.satiety", "player.needs.health", "player.needs.hygiene", "player.needs.mood"]: return "invalid_cost_path"
			if not number(action.costs[path]) or float(action.costs[path]) < 0.0: return "negative_cost"
	for id in catalog.recipes:
		var recipe: Dictionary = catalog.recipes[id]
		for field in ["ingredients", "outputs"]:
			if not recipe.get(field) is Dictionary: return "invalid_recipe"
			for item in recipe[field]:
				if not catalog.items.has(item) or not number(recipe[field][item]) or int(recipe[field][item]) <= 0: return "invalid_recipe_item"
	for id in catalog.locations:
		for destination in catalog.locations[id].get("routes", {}):
			var route: Variant = catalog.locations[id].routes[destination]
			if not catalog.locations.has(destination) or not route is Dictionary: return "invalid_route"
			for key in ["minutes", "cost"]:
				if not number(route.get(key, 0)) or float(route.get(key, 0)) < 0.0: return "invalid_route_cost"
	var advanced_error := Advanced.catalog_error(catalog)
	if not advanced_error.is_empty(): return advanced_error
	var agency_error := Agency.catalog_error(catalog)
	if not agency_error.is_empty(): return agency_error
	var human_error := Human.catalog_error(catalog)
	return human_error if not human_error.is_empty() else Dialogue.catalog_error(catalog)

static func state_error(state: Dictionary, catalog: Dictionary) -> String:
	var schemas := {
		"clock": {"total_minutes": "n"},
		"player": {"name": "s", "appearance": "d", "stats": "d", "skills": "d", "needs": "d", "effects": "d", "perks": "a", "injuries": "d", "addictions": "d", "level": "n", "xp": "n", "points": "n"},
		"inventory": {"items": "d", "equipped": "d"},
		"economy": {"cash": "n", "bank": "n", "debt": "n", "assets": "d", "job_counts": "d", "projects": "d", "shop_stock": "d", "channel": "d"},
		"world": {"location": "s", "previous_location": "s", "equipment": "a", "education": "d", "flags": "d", "unlocked": "a", "heat": "n", "cleanliness": "n", "visits": "d"},
		"social": {"npcs": "d", "relationships": "d", "contacts": "a", "messages": "a", "appointments": "a", "next_npc_id": "n", "next_message_id": "n"},
		"organizations": {}, "journal": {"quests": "d", "achievements": "a", "fired": "d", "cooldowns": "d", "ready_events": "a"},
		"encounters": {"combat": "d", "game": "d"}, "conditions": {}, "counters": {},
		"housing": {"properties": "d", "residence": "s"}, "preferences": {"difficulty": "s", "disabled_tags": "a"}}
	for section in schemas:
		if not fields(state.get(section), schemas[section]): return "invalid_section:" + str(section)
	if not Human.integer(state.player.get("age"), 18, 120): return "invalid_player_age"
	var advanced_error := Advanced.state_error(state, catalog)
	if not advanced_error.is_empty(): return advanced_error
	if not fields(state.world.education, {"grade": "n", "absences": "n", "homework": "b", "attended": "a", "missed": "a"}): return "invalid_education"
	if not fields(state.economy.channel, {"followers": "n"}): return "invalid_channel"
	if not catalog.difficulties.has(state.preferences.difficulty): return "invalid_difficulty"
	if not state.housing.residence.is_empty() and not state.housing.properties.has(state.housing.residence): return "invalid_residence"
	for id in state.housing.properties:
		var property: Variant = state.housing.properties[id]
		if not catalog.properties.has(id) or not fields(property, {"owned": "b", "equipment": "d", "tenants": "a", "next_bill": "n", "arrears": "n", "rent_income": "n", "tenant_arrears": "d"}): return "invalid_property"
		for npc in property.tenants:
			if not state.social.npcs.has(npc): return "invalid_tenant"
	for key in state.player.effects:
		if not catalog.effects.has(key) or not fields(state.player.effects[key], {"expires": "n"}): return "invalid_effect"
	for key in state.player.addictions:
		if not catalog.substances.has(key) or not fields(state.player.addictions[key], {"exposure": "n", "last_use": "n"}): return "invalid_addiction"
	for perk in state.player.perks:
		if not catalog.perks.has(perk): return "invalid_perk"
	for id in state.social.npcs:
		var npc: Variant = state.social.npcs[id]
		if not fields(npc, {"id": "s", "name": "s", "age": "n", "stats": "d", "skills": "d", "appearance": "d", "preferences": "a", "money": "n", "inventory": "d", "health": "n", "injuries": "d", "home": "s", "location": "s", "schedule": "a", "activity": "s", "activities": "a", "biography": "d", "fatigue": "n", "pinned_until": "n", "memories": "a"}): return "invalid_npc"
		if npc.id != id or not catalog.locations.has(npc.home) or not catalog.locations.has(npc.location): return "invalid_npc_location"
		if float(npc.health) < 0.0 or float(npc.health) > 100.0 or float(npc.money) < 0.0 or float(npc.age) < 18.0: return "invalid_npc_values"
		for section in ["stats", "skills", "inventory", "injuries"]:
			for value in npc[section].values():
				if not number(value) or float(value) < 0.0: return "invalid_npc_number"
		for schedule in npc.schedule:
			if not schedule is Dictionary: return "invalid_schedule"
	for contact in state.social.contacts:
		if not state.social.npcs.has(contact): return "invalid_contact"
	for appointment in state.social.appointments:
		if not fields(appointment, {"npc": "s", "minute": "n", "location": "s", "status": "s"}): return "invalid_appointment"
		if not state.social.npcs.has(appointment.npc) or not catalog.locations.has(appointment.location): return "invalid_appointment_target"
	for message in state.social.messages:
		if not fields(message, {"id": "n", "npc": "s", "text": "s", "incoming": "b", "read": "b", "minute": "n"}): return "invalid_message"
	for relation in state.social.relationships.values():
		if not fields(relation, {"affinity": "n", "trust": "n", "fear": "n", "attraction": "n", "status": "s"}): return "invalid_relationship"
	for id in state.economy.assets:
		if not catalog.assets.has(id) or not fields(state.economy.assets[id], {"level": "n", "invested": "n"}): return "invalid_asset"
	for id in state.economy.projects:
		if not catalog.projects.has(id) or not fields(state.economy.projects[id], {"progress": "n", "completed": "b"}): return "invalid_project"
	for id in state.organizations:
		var group: Variant = state.organizations[id]
		if not catalog.organizations.has(id) or not fields(group, {"members": "d", "budget": "n", "reputation": "n", "cleanliness": "n", "projects": "d", "articles": "n"}): return "invalid_organization"
		for npc in group.members:
			if not state.social.npcs.has(npc) or not fields(group.members[npc], {"role": "s", "task": "s"}): return "invalid_member"
		for project in group.projects:
			if not catalog.group_projects.has(project) or not fields(group.projects[project], {"progress": "n", "completed": "b"}): return "invalid_group_project"
	for id in state.journal.quests:
		if not catalog.quests.has(id) or not fields(state.journal.quests[id], {"status": "s", "objectives": "d", "claimed": "b", "deadline": "n"}): return "invalid_quest"
	for id in state.journal.quests:
		var progress: Dictionary = state.journal.quests[id]
		if not progress.get("seen",{}) is Dictionary: return "invalid_quest_seen"
		for objective in progress.get("seen",{}):
			var values: Variant = progress.seen[objective]
			if not catalog.quests[id].objectives.has(objective) or not values is Array or values.size() > int(catalog.quests[id].objectives[objective]): return "invalid_quest_seen"
			var unique := {}
			for value in values:
				if not value is String or value.is_empty() or unique.has(value): return "invalid_quest_seen"
				unique[value] = true
	for condition in state.conditions.values():
		if not fields(condition, {"id": "s", "target": "s", "started": "n", "stage": "n", "status": "s"}) or not catalog.conditions.has(condition.id): return "invalid_condition"
	var combat: Dictionary = state.encounters.combat
	if not combat.is_empty():
		if not fields(combat, {"npc": "s", "status": "s", "ap": "n", "player_hp": "n", "npc_hp": "n", "guard": "b", "turn": "n", "injuries": "d", "log": "a", "phase": "s", "revision": "n", "npc_ap": "n"}) or not state.social.npcs.has(combat.npc): return "invalid_combat"
		if not combat.phase in ["attack", "defence", "finished"]: return "invalid_combat_phase"
		for key in ["revision", "npc_ap", "ap", "turn"]:
			if float(combat[key]) != int(combat[key]) or int(combat[key]) < 0: return "invalid_combat_counter"
		if combat.ap > 4 or combat.npc_ap > 4 or combat.turn < 1: return "invalid_combat_counter"
		if combat.status == "active":
			if combat.phase == "finished" or (combat.phase == "defence" and (combat.ap != 0 or combat.npc_ap <= 0)) or (combat.phase == "attack" and (combat.npc_ap != 0 or combat.ap <= 0)): return "invalid_combat_phase"
		elif combat.phase != "finished" or combat.npc_ap != 0: return "invalid_combat_phase"
	var game: Dictionary = state.encounters.game
	if not game.is_empty():
		if not fields(game, {"type": "s", "status": "s", "stake": "n", "progress": "n", "attempts": "n", "limit": "n", "target": "n"}): return "invalid_game"
		match str(game.type):
			"blackjack":
				if not fields(game, {"deck": "a", "hand": "a", "dealer": "a"}): return "invalid_deck"
				if game.deck.size() + game.hand.size() + game.dealer.size() != 52 or game.hand.size() < 2 or game.dealer.size() < 2: return "invalid_deck_size"
				for rank in game.deck + game.hand + game.dealer:
					if not number(rank) or int(rank) < 1 or int(rank) > 13: return "invalid_card"
			"lockpick":
				if not fields(game, {"pins": "a", "pin": "n"}) or game.pins.size() != 3: return "invalid_lock"
				if int(game.pin) < 0 or (game.status == "active" and int(game.pin) >= game.pins.size()): return "invalid_lock_progress"
				for pin in game.pins:
					if not number(pin) or int(pin) < 0 or int(pin) > 2: return "invalid_pin"
			"guess": if not number(game.get("secret")): return "invalid_guess_game"
			"reaction", "strength", "timing", "pushups": pass
			_: return "unknown_game"
	var agency_error := Agency.state_error(state, catalog)
	if not agency_error.is_empty(): return agency_error
	var human_error := Human.state_error(state, catalog)
	return human_error if not human_error.is_empty() else Dialogue.state_error(state, catalog)
