extends RefCounted
const Preferences = preload("res://scripts/mechanics/preferences.gd")
const Population = preload("res://scripts/mechanics/population.gd")

static func numeric(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func command_args(args: Dictionary) -> bool:
	if args.has("values") and not args.values is Dictionary: return false
	for key in ["move", "item", "focus", "promise", "campaign", "candidate", "partner", "venue", "topic"]:
		if args.has(key) and not args[key] is String: return false
	for key in ["x", "y", "wage", "elapsed_ms", "duration_ms", "required_reps"]:
		if args.has(key) and (not numeric(args[key]) or float(args[key]) != int(args[key])): return false
	if args.has("power") and not numeric(args.power): return false
	if args.has("features"):
		if not args.features is Dictionary: return false
		for key in args.features:
			if not key is String or not (args.features[key] is String or args.features[key] is bool or numeric(args.features[key])): return false
	if args.has("rotated") and not args.rotated is bool: return false
	if args.has("candidates"):
		if not args.candidates is Array: return false
		for id in args.candidates:
			if not id is String: return false
	return true

static func catalog_error(catalog: Dictionary) -> String:
	for preferences in catalog.get("preference_sets", {}).values():
		if not preferences is Dictionary or not preferences.get("categories") is Array or preferences.categories.is_empty(): return "invalid_preference_set"
		for category in preferences.categories:
			if not category is String: return "invalid_preference_category"
	for date in catalog.get("date_activities", {}).values():
		if not date is Dictionary or not date.get("success") is Dictionary: return "invalid_date_activity"
		for key in ["minutes","cost","energy","mood"]:
			if not numeric(date.get(key)) or float(date[key]) < 0: return "invalid_date_value"
		if int(date.minutes) < 1 or int(date.minutes) > 240 or float(date.minutes) != int(date.minutes): return "invalid_date_duration"
		for field in ["locations","weather","goals"]:
			if not date.get(field, []) is Array: return "invalid_date_context"
		for value in date.success.values():
			if not numeric(value): return "invalid_date_outcome"
	var balance_limits := {
		"progression": {"attribute_base":[1,1000],"attribute_linear":[0,100],"attribute_quadratic":[0,10],"late_level_after":[1,100],"late_level_growth":[0,100]},
		"social": {"charisma_cap":[0,0.5],"charisma_scale":[1,1000],"memory_bias_cap":[0,0.3],"fear_penalty":[0,0.02],"gift_reward_limit":[1,20],"date_cooldown":[60,10080],"date_energy":[0,100]},
		"career": {"pay_growth":[0,1],"pay_cap":[1,10],"skill_scale":[1,10000],"stream_daily_minutes":[15,720],"audience_followers_scale":[0,20],"stream_energy_per_minute":[0.01,1]}}
	for section in catalog.get("balance_rules", {}):
		if not balance_limits.has(section) or not catalog.balance_rules[section] is Dictionary: return "invalid_balance_section"
		for key in catalog.balance_rules[section]:
			var value: Variant = catalog.balance_rules[section][key]
			if not balance_limits[section].has(key) or not numeric(value): return "invalid_balance_rule"
			var limits: Array = balance_limits[section][key]
			if float(value) < float(limits[0]) or float(value) > float(limits[1]): return "invalid_balance_range"
			if key in ["attribute_base","late_level_after","late_level_growth","gift_reward_limit","date_cooldown","stream_daily_minutes"] and float(value) != int(value): return "invalid_balance_integer"
	for difficulty in catalog.difficulties.values():
		if not Preferences.validate_values(difficulty): return "invalid_difficulty_rules"
	for interaction in catalog.interactions.values():
		if not interaction.get("tags", []) is Array or not interaction.get("requires_attraction", false) is bool or not numeric(interaction.get("mood", 0)): return "invalid_interaction_options"
		for tag in interaction.get("tags", []):
			if not tag is String: return "invalid_interaction_tag"
		if not interaction.get("branches", []) is Array: return "invalid_interaction_branches"
		for branch in interaction.get("branches", []):
			if not branch is Dictionary or not branch.get("id") is String or not branch.get("when", {}) is Dictionary: return "invalid_interaction_branch"
			if not numeric(branch.get("chance_bias", 0)) or absf(float(branch.get("chance_bias", 0))) > 1: return "invalid_interaction_bias"
			for outcome in ["success", "failure"]:
				if not branch.get(outcome, {}) is Dictionary: return "invalid_interaction_outcome"
				for value in branch.get(outcome, {}).values():
					if not numeric(value): return "invalid_interaction_outcome"
	for group in ["weapons", "combat_moves", "treatments", "contracts", "professions", "stream_topics", "publications", "campaigns", "personalities", "promises", "furniture", "training_programs", "outfits"]:
		if not catalog.get(group) is Dictionary: return "invalid_advanced_group:" + group
		for id in catalog[group]:
			var spec: Variant = catalog[group][id]
			if not spec is Dictionary: return "invalid_advanced_definition"
			for key in ["ap", "stamina", "damage", "defence", "bleeding", "cost", "minutes", "cooldown", "deadline", "effort", "pay", "xp", "energy", "daily_limit", "level", "sources", "growth", "monetization", "repair", "restore", "stop_bleeding", "infection", "care_minutes"]:
				if spec.has(key) and (not numeric(spec[key]) or float(spec[key]) < 0): return "invalid_advanced_number:" + key
			if group == "combat_moves":
				if int(spec.get("ap", 2)) < 1 or int(spec.get("ap", 2)) > 4: return "invalid_move_ap"
				if not spec.get("weapons", []) is Array: return "invalid_move_weapons"
			if group == "furniture":
				if not spec.get("size") is Array or spec.size.size() != 2: return "invalid_furniture_size"
				for size in spec.size:
					if not numeric(size) or int(size) < 1 or float(size) != int(size): return "invalid_furniture_size"
			if group == "campaigns":
				if not spec.get("stages") is Array or spec.stages.is_empty(): return "invalid_campaign_stages"
				for stage in spec.stages:
					if not stage is Dictionary or not numeric(stage.get("effort")) or float(stage.effort) <= 0: return "invalid_campaign_effort"
			if group == "training_programs":
				for category in ["attributes", "skills"]:
					if not spec.get(category, {}) is Dictionary: return "invalid_training"
					for key in spec.get(category, {}):
						if not catalog[category if category == "skills" else "attributes"].has(key): return "unknown_training_attribute"
						if not numeric(spec[category][key]) or int(spec[category][key]) < 1: return "invalid_training_xp"
			if group == "professions" and spec.has("publication_slots_at"):
				if not spec.publication_slots_at is Array or spec.publication_slots_at.is_empty(): return "invalid_publication_slots"
				var previous := -1
				for level in spec.publication_slots_at:
					if not numeric(level) or float(level) != int(level) or int(level) <= previous: return "invalid_publication_slots"
					previous = int(level)
	for id in catalog.items:
		if catalog.items[id].has("weapon") and not catalog.weapons.has(str(catalog.items[id].weapon)): return "unknown_item_weapon"
	for outfit in catalog.outfits.values():
		if not outfit.get("items") is Array or outfit.items.is_empty(): return "invalid_outfit"
		var slots := {}
		for item in outfit.items:
			if not item is String or not catalog.items.has(item) or not catalog.items[item].has("slot"): return "invalid_outfit_item"
			var slot := str(catalog.items[item].slot)
			if slots.has(slot) or catalog.items[item].get("category", "") != "clothing": return "invalid_outfit_slots"
			slots[slot] = true
		for field in ["activities", "locations", "weather"]:
			if not outfit.get(field, []) is Array: return "invalid_outfit_context"
	for id in catalog.treatments:
		if catalog.treatments[id].has("item") and not catalog.items.has(str(catalog.treatments[id].item)): return "unknown_treatment_item"
	for id in catalog.contracts:
		if not catalog.skills.has(str(catalog.contracts[id].get("skill", "computing"))): return "unknown_contract_skill"
	for id in catalog.stream_topics:
		if not catalog.skills.has(str(catalog.stream_topics[id].get("skill", "computing"))): return "unknown_stream_skill"
	for id in catalog.conditions:
		var condition: Dictionary = catalog.conditions[id]
		if condition.has("duration_months") and (not numeric(condition.duration_months) or int(condition.duration_months) <= 0): return "invalid_condition_months"
		var last_stage := -1.0
		for stage in condition.get("stages", []):
			if not stage is Dictionary: return "invalid_condition_stage"
			if not numeric(stage.get("after_months", stage.get("after", null))): return "invalid_condition_stage_time"
			var offset := float(stage.get("after_months", stage.get("after", 0)))
			if offset < 0.0 or offset < last_stage: return "invalid_condition_stage_order"
			last_stage = offset
	for id in catalog.npc_templates:
		var template: Dictionary = catalog.npc_templates[id]
		if not template.get("weapon", "") is String: return "invalid_npc_weapon"
		if not str(template.get("weapon", "")).is_empty() and not catalog.items.has(str(template.weapon)): return "unknown_npc_weapon"
		if not template.get("traits", {}) is Dictionary or not template.get("inventory", {}) is Dictionary: return "invalid_npc_template"
		if not template.get("wardrobe", []) is Array: return "invalid_npc_wardrobe"
		for outfit in template.get("wardrobe", []):
			if not outfit is String or not catalog.outfits.has(outfit): return "unknown_npc_outfit"
		for field in ["personalities", "origins", "goals"]:
			if template.has(field) and (not template[field] is Array or template[field].is_empty()): return "invalid_npc_choices"
		for value in template.get("traits", {}).values():
			if not numeric(value) or float(value) < 0 or float(value) > 100: return "invalid_npc_template_trait"
		for item in template.get("inventory", {}):
			if not catalog.items.has(item) or not numeric(template.inventory[item]) or int(template.inventory[item]) < 1: return "invalid_npc_template_item"
	return ""

static func state_error(state: Dictionary, catalog: Dictionary) -> String:
	var xp_credit: Variant = state.player.get("xp_credit", 0)
	if not numeric(xp_credit) or float(xp_credit) < 0 or float(xp_credit) >= 1: return "invalid_xp_credit"
	for key in ["growth_credit", "income_credit"]:
		var credit: Variant = state.economy.channel.get(key, 0)
		if not numeric(credit) or float(credit) < 0 or float(credit) >= 1: return "invalid_stream_credit"
	if not state.preferences.get("custom") is Dictionary or not Preferences.validate_values(state.preferences.custom): return "invalid_custom_difficulty"
	if not state.get("population") is Dictionary or not Population.valid(state.population.get("settings")): return "invalid_population"
	for section in ["healthcare", "careers", "security"]:
		if not state.get(section) is Dictionary: return "invalid_advanced_section:" + section
	if not state.healthcare.get("records") is Dictionary or not state.healthcare.get("family") is Array: return "invalid_healthcare"
	if not state.security.get("incidents") is Array or not numeric(state.security.get("fine")) or float(state.security.fine) < 0: return "invalid_security"
	for section in ["contracts", "professions", "workdays", "publications"]:
		if not state.careers.get(section) is Dictionary: return "invalid_careers"
	if not state.careers.get("streams") is Array: return "invalid_streams"
	if not state.player.get("training") is Dictionary or not state.social.get("promises") is Dictionary: return "invalid_training_or_promises"
	for id in state.healthcare.records:
		if id != "player" and not state.social.npcs.has(id): return "unknown_patient"
		var record: Variant = state.healthcare.records[id]
		if not record is Dictionary: return "invalid_patient_record"
		for key in ["bleeding", "intoxication", "infection", "care_until", "low_energy_minutes"]:
			if not numeric(record.get(key)) or float(record[key]) < 0: return "invalid_patient_value"
		if not record.get("treatments") is Dictionary or not record.get("scars") is Dictionary or not record.get("collapsed") is bool: return "invalid_patient_record"
	for id in state.careers.contracts:
		var contract: Variant = state.careers.contracts[id]
		if not catalog.contracts.has(id) or not contract is Dictionary: return "invalid_contract"
		for key in ["progress", "quality", "deadline"]:
			if not numeric(contract.get(key)) or float(contract[key]) < 0: return "invalid_contract_value"
		if not contract.get("claimed") is bool or not contract.get("status") in ["active", "completed", "failed"]: return "invalid_contract_status"
	for npc in state.social.npcs.values():
		if not npc.appearance.get("morphology", "human") in ["human", "semi_furry", "furry"]: return "invalid_npc_morphology"
		if npc.appearance.has("has_tail") and not npc.appearance.has_tail is bool: return "invalid_npc_tail"
		if not npc.get("needs") is Dictionary or not npc.get("decision") is Dictionary: return "invalid_npc_needs"
		for key in ["energy", "satiety", "mood"]:
			if not numeric(npc.needs.get(key)) or float(npc.needs[key]) < 0 or float(npc.needs[key]) > 100: return "invalid_npc_need"
		if not npc.get("traits") is Dictionary or not npc.get("attracted_to") is Array or not npc.get("gender") is String: return "invalid_npc_profile"
		if not npc.get("equipped") is Dictionary or not npc.get("wardrobe") is Array or not npc.get("outfit") is String: return "invalid_npc_wardrobe"
		for slot in npc.equipped:
			var item := str(npc.equipped[slot])
			if int(npc.inventory.get(item, 0)) < 1 or not catalog.items.has(item) or catalog.items[item].get("slot", "") != slot: return "invalid_npc_equipment"
		for value in npc.traits.values():
			if not numeric(value) or float(value) < 0 or float(value) > 100: return "invalid_npc_trait"
	for group in state.organizations.values():
		if not group.get("policies") is Dictionary or not group.get("campaigns") is Dictionary or not group.get("equipment") is Array or not group.get("election") is Dictionary: return "invalid_club_management"
		for campaign_id in group.campaigns:
			if not catalog.campaigns.has(campaign_id): return "unknown_club_campaign"
	var game: Dictionary = state.encounters.game
	if game.get("type", "") in ["timing", "pushups"]:
		for field in ["elapsed_ms", "last_input_ms", "duration_ms", "reps", "required_reps", "phase"]:
			if not numeric(game.get(field)) or float(game[field]) < 0: return "invalid_timed_game_state"
	if game.has("context"):
		if not game.context is Dictionary or not state.social.npcs.has(str(game.context.get("npc", ""))) or not game.context.get("resolved") is bool: return "invalid_game_context"
	return ""
