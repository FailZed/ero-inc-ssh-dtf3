extends RefCounted
const SCHOOL_IDS := ["weak", "aggressive", "haughty", "reliable", "humorous", "naive", "sociable", "reclusive", "gossip", "deceitful", "uninhibited"]

static func number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high

static func catalog_error(catalog: Dictionary) -> String:
	if not catalog.has("agency_personalities"): return ""
	if not catalog.get("school_personality_map") is Dictionary or catalog.school_personality_map.size() != SCHOOL_IDS.size(): return "incomplete_school_personality_map"
	var found: Array = []
	for entry in catalog.school_personality_map.values():
		if not entry is Dictionary or not entry.get("id") in SCHOOL_IDS or entry.id in found: return "invalid_school_personality_map"
		found.append(entry.id)
	for id in SCHOOL_IDS:
		if not catalog.agency_personalities.has(id): return "missing_school_personality:" + id
	for id in catalog.agency_personalities:
		var spec: Variant = catalog.agency_personalities[id]
		if not spec is Dictionary or not spec.get("label") is String or not spec.get("school") is bool: return "invalid_personality_profile"
		if spec.school != (id in SCHOOL_IDS): return "invalid_personality_origin"
		for field in ["biases", "response", "goals"]:
			if not spec.get(field) is Dictionary: return "invalid_personality_field"
		for field in ["biases", "response"]:
			for action in spec[field]:
				if not catalog.agency_actions.has(action) or not number(spec[field][action], -0.4, 0.4): return "invalid_personality_action"
		for goal in spec.goals:
			if not catalog.agency_aspirations.has(goal) or not number(spec.goals[goal], 0.01, 10): return "invalid_personality_goal"
		for field in ["social_decay", "negative_gain", "memory_duration", "fear_gain"]:
			if not number(spec.get(field), 0.25, 2): return "invalid_personality_scale"
		if not number(spec.get("familiarity"), -1, 1) or not number(spec.get("credulity"), 0, 1) or not number(spec.get("acceptance"), -0.2, 0.2): return "invalid_personality_reaction"
		if not catalog.personalities.has(id): return "missing_personality_conversation"
	for template in catalog.npc_templates.values():
		for field in ["personalities", "agency_personality_pool"]:
			if not template.get(field, []) is Array: return "invalid_personality_pool"
			for id in template.get(field, []):
				if not id is String or not catalog.agency_personalities.has(id): return "unknown_personality_in_template"
	return ""

static func state_error(state: Dictionary, catalog: Dictionary) -> String:
	if not catalog.has("agency_personalities") and not catalog.has("human_dimensions"): return ""
	for npc in state.social.npcs.values():
		if catalog.has("agency_personalities") and (not npc.get("personality") is String or not catalog.agency_personalities.has(npc.personality)): return "unknown_npc_personality"
		if not npc.has("mind"): continue
		for field in ["knowledge", "claims"]:
			if not npc.mind.get(field) is Array or npc.mind[field].size() > (16 if field == "knowledge" else 8): return "invalid_personality_knowledge"
			for fact in npc.mind[field]:
				if not fact is Dictionary: return "invalid_personality_fact"
				for actor in ["subject", "source", "relay"]:
					if not fact.get(actor) is String or not state.social.npcs.has(fact[actor]): return "unknown_fact_actor"
				if not fact.get("verified") is bool or not fact.get("checked") is bool: return "invalid_fact_verification"
				if fact.verified and not fact.checked: return "invalid_fact_verification"
				if not number(fact.get("confidence"), 0, 1): return "invalid_fact_confidence"
				for time in ["minute", "expires"]:
					if not number(fact.get(time), 0, 2147483647) or float(fact[time]) != int(fact[time]): return "invalid_fact_time"
				if int(fact.minute) > int(state.clock.total_minutes) or int(fact.expires) <= int(fact.minute): return "invalid_fact_time"
				if fact.get("topic") == "occupation":
					if not fact.get("value") is String or not fact.get("reference") is String: return "invalid_public_occupation"
				elif fact.get("topic") == "achievement":
					for key in ["value", "reference"]:
						if not number(fact.get(key), 0, 1000000) or float(fact[key]) != int(fact[key]): return "invalid_achievement_claim"
				else: return "invalid_fact_topic"
		if not npc.mind.get("declined_until") is Dictionary or npc.mind.declined_until.size() > 16: return "invalid_romantic_boundaries"
		for other in npc.mind.declined_until:
			if other == npc.id or not state.social.npcs.has(other) or not number(npc.mind.declined_until[other], 0, 2147483647): return "invalid_romantic_boundary"
	return ""
