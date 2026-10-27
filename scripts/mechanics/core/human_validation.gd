extends RefCounted
const FACETS := ["sincerity", "fairness", "greed_avoidance", "modesty", "fearfulness", "anxiety", "dependence", "sentimentality", "social_self_esteem", "social_boldness", "sociability", "liveliness", "forgivingness", "gentleness", "flexibility", "patience", "organization", "diligence", "perfectionism", "prudence", "aesthetic_appreciation", "inquisitiveness", "creativity", "unconventionality"]
const VALUES := ["security", "benevolence", "achievement", "autonomy"]
const INTERESTS := ["arts", "science", "sport", "nature", "games", "community"]
const Rules = preload("res://scripts/mechanics/core/rules.gd")

static func number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high

static func integer(value: Variant, low: int, high: int) -> bool:
	return number(value, low, high) and float(value) == int(value)

static func vector(value: Variant, keys: Array) -> bool:
	if not value is Dictionary or value.size() != keys.size(): return false
	for key in keys:
		if not number(value.get(key), 0, 100): return false
	return true

static func catalog_error(catalog: Dictionary) -> String:
	if not catalog.has("human_dimensions"): return ""
	var generation: Variant = catalog.get("human_generation", {}).get("population")
	if not generation is Dictionary or generation.size() != 7: return "invalid_human_generation"
	for key in ["honesty", "emotionality", "extraversion", "agreeableness", "conscientiousness", "openness", "spread"]:
		if not integer(generation.get(key), 0, 100): return "invalid_human_generation"
	if not catalog.human_dimensions is Dictionary or catalog.human_dimensions.size() != 6: return "invalid_human_dimensions"
	var found: Array = []
	for domain in catalog.human_dimensions.values():
		if not domain is Dictionary or not domain.get("label") is String or not domain.get("facets") is Array or domain.facets.size() != 4: return "invalid_human_domain"
		for facet in domain.facets:
			if not facet in FACETS or facet in found: return "invalid_human_facet"
			found.append(facet)
	for group in ["human_values", "human_interests", "human_social_rules"]:
		if not catalog.get(group) is Dictionary: return "missing_human_catalog"
	if catalog.human_values.keys().size() != VALUES.size() or catalog.human_interests.keys().size() != INTERESTS.size(): return "invalid_human_vocabulary"
	for key in VALUES:
		if not catalog.human_values.has(key): return "invalid_human_value"
	for key in INTERESTS:
		if not catalog.human_interests.has(key): return "invalid_human_interest"
	var rules: Variant = catalog.human_social_rules.get("simulation")
	if not rules is Dictionary: return "invalid_human_social_rules"
	for key in ["bond_limit", "daily_gain_budget", "repeat_minutes", "repair_days", "neglect_days"]:
		var bounds: Array = {"bond_limit": [2, 64], "daily_gain_budget": [1, 20], "repeat_minutes": [60, 1440], "repair_days": [2, 5], "neglect_days": [1, 14]}[key]
		if not integer(rules.get(key), int(bounds[0]), int(bounds[1])): return "invalid_human_social_rule"
	return ""

static func state_error(state: Dictionary, catalog: Dictionary) -> String:
	if not catalog.has("human_dimensions"): return ""
	var enabled: bool = state.world.flags.get("npc_agency_enabled", false)
	var now := int(state.clock.total_minutes)
	var day := int(state.clock.day_index)
	for npc in state.social.npcs.values():
		if not enabled: continue
		var p: Variant = npc.get("psychology")
		if not p is Dictionary or p.get("version") != 1: return "invalid_human_personality"
		for field in ["facets", "values", "interests"]:
			if not vector(p.get(field), {"facets": FACETS, "values": VALUES, "interests": INTERESTS}[field]): return "invalid_human_" + field
		if not npc.has("mind"): return "missing_human_mind"
		var boundaries: Variant = npc.mind.get("boundaries")
		if not boundaries is Dictionary or boundaries.size() != 3: return "invalid_human_boundaries"
		for key in ["contact", "romance", "gossip"]:
			if not boundaries.get(key) is bool: return "invalid_human_boundary"
		var bonds: Variant = npc.mind.get("bonds")
		if not bonds is Dictionary or bonds.size() > int(catalog.human_social_rules.simulation.bond_limit): return "invalid_human_bonds"
		for id in bonds:
			if id == npc.id or (id != "player" and not state.social.npcs.has(id)): return "invalid_human_bond_target"
			var bond: Variant = bonds[id]
			if not bond is Dictionary: return "invalid_human_bond"
			for key in ["trust", "affection", "respect", "comfort", "closeness", "interest", "grievance", "care_balance"]:
				if not number(bond.get(key), -100 if key in ["trust", "affection", "respect", "comfort", "care_balance"] else 0, 100): return "invalid_human_bond_scale"
			for key in ["acknowledged", "consent"]:
				if not bond.get(key) is bool: return "invalid_human_agreement"
			if not integer(bond.get("last_contact"), 0, now) or not integer(bond.get("updated_day"), 0, day) or not integer(bond.get("gain_day"), -1, day): return "invalid_human_bond_time"
			if not number(bond.get("gain_used"), 0, float(catalog.human_social_rules.simulation.daily_gain_budget)): return "invalid_human_gain_budget"
			for field in ["interests", "values"]:
				var known: Variant = bond.get("known_" + field)
				if not known is Dictionary: return "invalid_human_disclosure"
				for topic in known:
					if not catalog["human_" + field].has(topic) or not number(known[topic], 0, 100): return "invalid_human_disclosure"
			if not bond.get("recent") is Dictionary or bond.recent.size() > catalog.agency_actions.size() + 2: return "invalid_human_recency"
			for action in bond.recent:
				if not catalog.agency_actions.has(action) and not action in ["legacy", "romantic_decline"]: return "invalid_human_recent_action"
				if not integer(bond.recent[action], 0, now): return "invalid_human_recency_time"
			if not bond.get("good_days") is Array or bond.good_days.size() > int(catalog.human_social_rules.simulation.repair_days): return "invalid_human_repair"
			var previous := -1
			for repair_day in bond.good_days:
				if not integer(repair_day, previous + 1, day): return "invalid_human_repair_day"
				previous = int(repair_day)
	for key in state.social.relationships:
		if state.social.relationships[key].status != "partner": continue
		var ids := str(key).split("|")
		for i in range(2):
			if ids[i] == "player": continue
			var bond: Dictionary = state.social.npcs[ids[i]].get("mind", {}).get("bonds", {}).get(ids[1 - i], {})
			if not bond.get("consent", false): return "missing_human_partner_consent"
	return ""
