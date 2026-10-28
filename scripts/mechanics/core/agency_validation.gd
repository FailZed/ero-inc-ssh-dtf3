extends RefCounted
## Optional extension validation; the production simulation keeps its old catalog/hash.
const Employment = preload("res://scripts/mechanics/npc_employment.gd")
const NEEDS := ["energy", "satiety", "hygiene", "social", "fun"]
const TRAITS := ["bravery", "responsibility", "sociability", "romantic", "loyalty", "cunning"]
const Personalities = preload("res://scripts/mechanics/core/personality_validation.gd")

static func number(value: Variant, low: float = 0.0, high: float = 1e12) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high

static func integer(value: Variant, low: int = 0, high: int = 2147483647) -> bool:
	return number(value, low, high) and float(value) == int(value)

static func shape(value: Variant, schema: Dictionary) -> bool:
	if not value is Dictionary: return false
	for key in schema:
		var item: Variant = value.get(key)
		match schema[key]:
			"d": if not item is Dictionary: return false
			"a": if not item is Array: return false
			"s": if not item is String: return false
			"n": if not number(item, -1e12): return false
			"b": if not item is bool: return false
	return true

static func catalog_error(catalog: Dictionary) -> String:
	if not catalog.has("agency_rules"): return ""
	for group in ["agency_rules", "agency_actions", "agency_aspirations", "agency_experiences"]:
		if not catalog.get(group) is Dictionary or catalog[group].is_empty(): return "invalid_agency_group"
	var rules: Variant = catalog.agency_rules.get("simulation")
	if not shape(rules, {"need_decay": "d"}): return "invalid_agency_rules"
	var limits := {"decision_minutes": [5, 60], "history_limit": [1, 128], "sentiment_limit": [1, 64],
		"moodlet_limit": [1, 32], "want_limit": [1, 5], "partner_candidates": [2, 32],
		"travel_minimum": [5, 120], "want_duration": [60, 10080], "stagnation_minutes": [60, 43200]}
	for key in limits:
		if not integer(rules.get(key), int(limits[key][0]), int(limits[key][1])): return "invalid_agency_rule:" + key
	if 60 % int(rules.decision_minutes) != 0 or int(rules.travel_minimum) % int(rules.decision_minutes) != 0: return "invalid_agency_cadence"
	if not number(rules.get("hysteresis"), 0, 0.2) or not number(rules.get("critical_need"), 1, 40): return "invalid_agency_scoring"
	for need in NEEDS:
		if not number(rules.need_decay.get(need), 0, 20): return "invalid_agency_decay"
	for id in catalog.agency_actions:
		var action: Variant = catalog.agency_actions[id]
		if not shape(action, {"label": "s", "destination": "s", "restore": "d", "traits": "d", "emotion": "s"}): return "invalid_agency_action"
		if not integer(action.get("minutes"), 5, 240) or int(action.minutes) % int(rules.decision_minutes) != 0: return "invalid_agency_duration"
		if not number(action.get("base"), 0, 1): return "invalid_agency_weight"
		if action.destination != "home" and not catalog.locations.has(action.destination): return "invalid_agency_location"
		for need in action.restore:
			if not need in NEEDS or not number(action.restore[need], 0, 100): return "invalid_agency_restore"
		for trait_id in action.traits:
			if not trait_id in TRAITS or not number(action.traits[trait_id], 0, 1): return "invalid_agency_trait"
		for key in ["cost", "income", "health", "xp"]:
			if action.has(key) and not integer(action[key], 0, 1000): return "invalid_agency_reward"
		if action.has("skill") and not catalog.skills.has(action.skill): return "invalid_agency_skill"
		if not action.get("requires_skill", {}) is Dictionary: return "invalid_agency_prerequisite"
		for skill in action.get("requires_skill", {}):
			if not catalog.skills.has(skill) or not integer(action.requires_skill[skill], 0, 10000): return "invalid_agency_prerequisite"
		for key in ["social", "negative_sentiment", "mutual_attraction"]:
			if action.has(key) and not action[key] is bool: return "invalid_agency_action_flag"
		for field in ["trait_min", "trait_max"]:
			if not action.get(field, {}) is Dictionary: return "invalid_agency_trait_filter"
			for trait_id in action.get(field, {}):
				if not trait_id in TRAITS or not number(action[field][trait_id], 0, 100): return "invalid_agency_trait_filter"
		if not action.get("roles", []) is Array or not action.get("weather", []) is Array or not action.get("tags", []) is Array: return "invalid_agency_action_filter"
	for aspiration in catalog.agency_aspirations.values():
		if not shape(aspiration, {"label": "s", "stages": "a"}) or aspiration.stages.is_empty() or aspiration.stages.size() > 12: return "invalid_aspiration"
		for stage in aspiration.stages:
			if not shape(stage, {"action": "s"}) or not catalog.agency_actions.has(stage.action) or not integer(stage.get("minutes"), 1, 43200): return "invalid_aspiration_stage"
	for experience in catalog.agency_experiences.values():
		if not shape(experience, {"emotion": "s"}) or not number(experience.get("strength"), 0, 100) or not integer(experience.get("duration"), 1, 43200) or not number(experience.get("sentiment"), -100, 100): return "invalid_agency_experience"
	var work_error := Employment.catalog_error(catalog)
	return work_error if not work_error.is_empty() else Personalities.catalog_error(catalog)

static func state_error(state: Dictionary, catalog: Dictionary) -> String:
	if not catalog.has("agency_rules"): return ""
	var rules: Dictionary = catalog.agency_rules.simulation
	var enabled: Variant = state.world.flags.get("npc_agency_enabled", false)
	if not enabled is bool: return "invalid_agency_enabled"
	for npc in state.social.npcs.values():
		if not npc.has("mind"):
			if enabled: return "missing_npc_mind"
			continue
		var mind: Variant = npc.mind
		if not shape(mind, {"aspiration": "d", "active": "d", "moodlets": "a", "sentiments": "d", "fears": "d", "wants": "a", "history": "a", "recent_actions": "a", "completed_actions": "d", "fulfilled_today": "a", "emotion": "d", "decision": "d", "skill_remainders": "d", "aspiration_history": "a"}): return "invalid_npc_mind"
		if mind.get("version") != 2: return "unsupported_npc_mind"
		for field in ["updated_at", "last_progress", "satisfaction", "completed_at"]:
			if not integer(mind.get(field)): return "invalid_npc_mind_number"
		if mind.has("career_level"): return "superseded_npc_career_field"
		var work_error := Employment.state_error(npc,catalog,state.clock)
		if not work_error.is_empty(): return work_error
		if not integer(mind.get("last_social"), -1440) or not integer(mind.get("want_day"), -1): return "invalid_npc_mind_time"
		if int(mind.updated_at) > int(state.clock.total_minutes) or int(mind.last_progress) > int(state.clock.total_minutes) or int(mind.completed_at) > int(state.clock.total_minutes): return "future_npc_mind"
		if not number(mind.get("income_remainder"), 0, 0.999999): return "invalid_npc_income_remainder"
		for skill in mind.skill_remainders:
			if not catalog.skills.has(skill) or not number(mind.skill_remainders[skill], 0, 0.999999): return "invalid_npc_skill_remainder"
		for need in NEEDS:
			if not number(npc.needs.get(need), 0, 100): return "invalid_agency_need"
		var goal: Dictionary = mind.aspiration
		if not shape(goal, {"id": "s", "completed": "b"}) or not catalog.agency_aspirations.has(goal.id): return "invalid_npc_aspiration"
		var count: int = catalog.agency_aspirations[goal.id].stages.size()
		if not integer(goal.get("stage"), 0, count) or not integer(goal.get("progress")) or not integer(goal.get("milestones"), 0, count): return "invalid_npc_goal_progress"
		if bool(goal.completed) != (int(goal.stage) == count) or int(goal.milestones) != int(goal.stage): return "invalid_npc_goal_stage"
		if not goal.completed and int(goal.progress) >= int(catalog.agency_aspirations[goal.id].stages[int(goal.stage)].minutes): return "invalid_npc_goal_progress"
		if goal.completed and int(goal.progress) != 0: return "invalid_npc_goal_progress"
		if mind.aspiration_history.size() > 5: return "unbounded_npc_goal_history"
		for past in mind.aspiration_history:
			if not shape(past, {"id": "s", "completed": "b"}) or not catalog.agency_aspirations.has(past.id) or not past.completed: return "invalid_npc_goal_history"
			var past_count: int = catalog.agency_aspirations[past.id].stages.size()
			if past.get("stage") != past_count or past.get("milestones") != past_count or past.get("progress") != 0: return "invalid_npc_goal_history"
		if mind.history.size() > int(rules.history_limit) or mind.sentiments.size() > int(rules.sentiment_limit) or mind.wants.size() > int(rules.want_limit) or mind.moodlets.size() > int(rules.moodlet_limit) or mind.recent_actions.size() > 6: return "unbounded_npc_mind"
		for entry in mind.history:
			if not shape(entry, {"kind": "s", "minute": "n", "data": "d"}): return "invalid_npc_history"
		for entry in mind.moodlets:
			if not shape(entry, {"key": "s", "emotion": "s"}) or not number(entry.get("strength"), 0, 100) or not integer(entry.get("duration"), 1) or not integer(entry.get("expires")): return "invalid_npc_moodlet"
		for other in mind.sentiments:
			if other == npc.id or (other != "player" and not state.social.npcs.has(other)): return "invalid_sentiment_target"
			var entry: Variant = mind.sentiments[other]
			if not shape(entry, {"kind": "s"}) or not number(entry.get("value"), -100, 100) or not integer(entry.get("expires")): return "invalid_npc_sentiment"
		for fear in mind.fears.values():
			if not shape(fear, {"strength": "n", "expires": "n"}) or not number(fear.strength, 0, 100) or not integer(fear.expires): return "invalid_npc_fear"
		for want in mind.wants:
			if not shape(want, {"action": "s", "expires": "n"}) or not catalog.agency_actions.has(want.action): return "invalid_npc_want"
		for id in mind.recent_actions + mind.fulfilled_today + mind.completed_actions.keys():
			if not catalog.agency_actions.has(id): return "invalid_npc_action_memory"
		for amount in mind.completed_actions.values():
			if not integer(amount): return "invalid_npc_action_count"
		if not shape(mind.emotion, {"id": "s", "strength": "n"}) or not number(mind.emotion.strength, 0, 100): return "invalid_npc_emotion"
		if mind.active.is_empty(): continue
		var active: Dictionary = mind.active
		if not shape(active, {"action": "s", "phase": "s", "destination": "s", "partner": "s", "reason": "s"}) or not integer(active.get("started")) or not integer(active.get("due")): return "invalid_npc_intent"
		if not catalog.agency_actions.has(active.action) or not active.phase in ["travel", "action", "receiving"] or not catalog.locations.has(active.destination): return "invalid_npc_intent"
		if not active.partner.is_empty() and (active.partner == npc.id or not state.social.npcs.has(active.partner)): return "invalid_npc_intent_partner"
		if int(active.due) <= int(active.started) or int(active.started) > int(state.clock.total_minutes): return "invalid_npc_intent_time"
		if active.phase == "receiving" or (active.phase == "action" and catalog.agency_actions[active.action].get("social", false)):
			if active.partner.is_empty(): return "missing_npc_intent_partner"
			var partner: Dictionary = state.social.npcs[active.partner]
			if not partner.has("mind") or partner.mind.active.get("partner", "") != npc.id or partner.mind.active.get("action", "") != active.action or partner.mind.active.get("due", -1) != active.due: return "asymmetric_npc_intent"
	return Personalities.state_error(state, catalog)
