extends "res://scripts/mechanics/core/module.gd"
## HEXACO-inspired facets and original game behavior; no fixed personality categories.
const FACT_LIMIT := 16
const CLAIM_LIMIT := 8

func generation_choices(template: Dictionary) -> Array:
	return template.get("personalities", ["calm"]).duplicate()

func enabled() -> bool:
	return sim.services.has("npc_agency") and sim.services.npc_agency.enabled()

func choose_goal(npc: Dictionary, preferred: String, exclude: String = "") -> String:
	var weights: Dictionary = profile(npc).get("goals", {}).duplicate()
	if weights.is_empty(): return "community" if preferred == "relationship" and "romance" in sim.state.preferences.disabled_tags else preferred
	if not preferred.is_empty(): weights[preferred] = float(weights.get(preferred, 0)) + 2.0
	if npc.biography.role != "worker":
		weights["mastery"] = float(weights.get("mastery", 0)) + float(weights.get("career", 0))
		weights.erase("career")
	if "romance" in sim.state.preferences.disabled_tags: weights.erase("relationship")
	weights.erase(exclude)
	var ids: Array = weights.keys()
	ids.sort()
	var total := 0.0
	for id in ids: total += float(weights[id])
	if total <= 0: return "wellbeing"
	var roll: float = sim.rng.randf() * total
	for id in ids:
		roll -= float(weights[id])
		if roll < 0: return str(id)
	return str(ids.back())

func age(npc: Dictionary, minute: int) -> void:
	for field in ["knowledge", "claims"]:
		for i in range(npc.mind[field].size() - 1, -1, -1):
			if minute >= int(npc.mind[field][i].expires): npc.mind[field].remove_at(i)
	for id in npc.mind.declined_until.keys():
		if minute >= int(npc.mind.declined_until[id]): npc.mind.declined_until.erase(id)

func conversation_bias(npc: Dictionary, action: String) -> float:
	var equivalent := {"listen": "support", "share_interest": "connect", "flirt": "court", "talk": "connect"}
	return float(profile(npc).get("response", {}).get(str(equivalent.get(action, action)), 0))

func public_achievements(npc: Dictionary) -> int:
	return int(npc.mind.completed_actions.get("publish", 0))

func _unchecked(npc: Dictionary) -> Dictionary:
	for field in ["claims", "knowledge"]:
		for item in npc.mind[field]:
			if item.topic == "achievement" and not item.checked: return item
	return {}

func _news(npc: Dictionary, receiver: String = "") -> Dictionary:
	for field in ["knowledge", "claims"]:
		for item in npc.mind[field]:
			if item.subject != npc.id and item.subject != receiver: return item
	return {}

func _fact(subject: String, source: String, topic: String, value: Variant, verified: bool, truth: Variant) -> Dictionary:
	var now := int(sim.state.clock.total_minutes)
	return {"subject": subject, "source": source, "relay": source, "topic": topic,
		"value": value, "reference": truth, "verified": verified, "checked": verified,
		"confidence": 1.0 if verified else 0.5, "minute": now, "expires": now + 10080}

func _store(npc: Dictionary, field: String, fact: Dictionary, limit: int) -> void:
	var entries: Array = npc.mind[field]
	for i in range(entries.size() - 1, -1, -1):
		if entries[i].subject == fact.subject and entries[i].topic == fact.topic and entries[i].source == fact.source: entries.remove_at(i)
	entries.append(fact.duplicate(true))
	while entries.size() > limit: entries.pop_front()

func learn(npc: Dictionary, other: Dictionary) -> void:
	# A direct conversation discloses a public occupation, not private experiences.
	_store(npc, "knowledge", _fact(str(other.id), str(other.id), "occupation", str(other.biography.role), true, str(other.biography.role)), FACT_LIMIT)

func social_failure(npc: Dictionary, other: Dictionary, action: String) -> void:
	if action != "court": return
	if not npc.mind.declined_until.has(str(other.id)) and npc.mind.declined_until.size() >= FACT_LIMIT: npc.mind.declined_until.erase(npc.mind.declined_until.keys()[0])
	npc.mind.declined_until[str(other.id)] = int(sim.state.clock.total_minutes) + 1440

func initialize_character(npc: Dictionary) -> void:
	if npc.has("psychology"): return
	var facets := {}
	var generation := definition("human_generation", "population")
	var spread := int(generation.get("spread", 30))
	for key in sim.catalog.human_dimensions:
		var domain: Dictionary = sim.catalog.human_dimensions[key]
		var center: int = clampi(int(generation.get(key, 50)) + sim.rng.randi_range(-spread, spread), 0, 100)
		for facet in domain.facets: facets[facet] = clampi(center + sim.rng.randi_range(-mini(25, spread), mini(25, spread)), 0, 100)
	var values := {}
	var interests := {}
	for key in sim.catalog.human_values: values[key] = sim.rng.randi_range(0, 100)
	for key in sim.catalog.human_interests: interests[key] = sim.rng.randi_range(0, 100)
	npc.psychology = {"version": 1, "facets": facets, "values": values, "interests": interests}

func initialize_mind(npc: Dictionary) -> void:
	npc.mind.knowledge = []
	npc.mind.claims = []
	npc.mind.declined_until = {}
	npc.mind.bonds = {}
	npc.mind.boundaries = {"contact": true, "romance": true, "gossip": true}
	sim.services.npc_dialogue.initialize(npc)

func f(npc: Dictionary, key: String) -> float:
	return float(npc.psychology.facets.get(key, 50)) / 100.0

func v(npc: Dictionary, key: String) -> float:
	return float(npc.psychology.values.get(key, 50)) / 100.0

func centered(npc: Dictionary, key: String) -> float:
	return f(npc, key) - 0.5

func profile(npc: Dictionary) -> Dictionary:
	var p := {
		"label": "Многомерный характер", "school": false,
		"social_decay": 0.4 + f(npc, "sociability") * 1.1,
		"familiarity": 0.7 - f(npc, "social_boldness") * 0.8,
		"credulity": 0.75 - f(npc, "prudence") * 0.35 - f(npc, "inquisitiveness") * 0.25,
		"negative_gain": 0.65 + f(npc, "anxiety") * 0.5 + (1 - f(npc, "social_self_esteem")) * 0.25,
		"memory_duration": 0.7 + f(npc, "sentimentality") * 0.5 + (1 - f(npc, "forgivingness")) * 0.4,
		"fear_gain": 0.5 + f(npc, "fearfulness"), "acceptance": centered(npc, "sociability") * 0.12,
		"response": {"support": centered(npc, "dependence") * 0.2, "joke": centered(npc, "liveliness") * 0.16,
			"boast": -centered(npc, "modesty") * 0.12, "share_values": centered(npc, "unconventionality") * 0.12},
		"goals": {"career": 0.5 + v(npc, "achievement") * 3 + f(npc, "diligence"),
			"mastery": 0.5 + f(npc, "inquisitiveness") * 2 + f(npc, "perfectionism"),
			"creativity": 0.5 + f(npc, "creativity") * 2 + f(npc, "aesthetic_appreciation"),
			"community": 0.5 + v(npc, "benevolence") * 2 + f(npc, "sociability"),
			"wellbeing": 0.5 + v(npc, "security") * 2 + v(npc, "autonomy"),
			"relationship": 0.5 + f(npc, "sentimentality") * 2 + f(npc, "dependence")}, "biases": {}}
	var b: Dictionary = p.biases
	b.connect = centered(npc, "sociability") * 0.30 + centered(npc, "social_boldness") * 0.14
	b.visit = centered(npc, "social_boldness") * 0.3
	b.joke = centered(npc, "liveliness") * 0.32
	b.boast = -centered(npc, "modesty") * 0.25 - centered(npc, "greed_avoidance") * 0.1
	b.deceive = -centered(npc, "sincerity") * 0.38 - centered(npc, "fairness") * 0.26 - centered(npc, "prudence") * 0.1 - 0.10
	b.gossip = centered(npc, "sociability") * 0.16 - centered(npc, "prudence") * 0.1
	b.verify = centered(npc, "inquisitiveness") * 0.22 + centered(npc, "prudence") * 0.18
	b.support = centered(npc, "sentimentality") * 0.15 + (v(npc, "benevolence") - 0.5) * 0.25
	b.cooperate = centered(npc, "fairness") * 0.12 + centered(npc, "diligence") * 0.12 + (v(npc, "benevolence") - 0.5) * 0.15
	b.apologize = centered(npc, "sincerity") * 0.18 + centered(npc, "flexibility") * 0.16
	b.reconcile = centered(npc, "forgivingness") * 0.18 + centered(npc, "gentleness") * 0.14
	b.dispute = -centered(npc, "patience") * 0.28 - centered(npc, "gentleness") * 0.16
	b.practice = centered(npc, "diligence") * 0.12 + centered(npc, "perfectionism") * 0.12
	b.work = centered(npc, "organization") * 0.10 + centered(npc, "diligence") * 0.14
	b.create = centered(npc, "creativity") * 0.22 + centered(npc, "aesthetic_appreciation") * 0.12
	b.publish = centered(npc, "social_self_esteem") * 0.16
	b.wash = centered(npc, "organization") * 0.08
	b.walk = -centered(npc, "fearfulness") * 0.08
	b.share_values = centered(npc, "unconventionality") * 0.16 + centered(npc, "sentimentality") * 0.12
	b.court = centered(npc, "social_boldness") * 0.18 + centered(npc, "sentimentality") * 0.08
	return p

func bias(npc: Dictionary, action: String) -> float:
	var result := float(profile(npc).biases.get(action, 0))
	if action == "apologize":
		for other in npc.mind.bonds:
			var bond: Dictionary = sim.services.npc_relationships.view(str(other), str(npc.id))
			if float(bond.grievance) > 0 and not bond.acknowledged: result += 0.10
	return result

func describe(npc: Dictionary) -> Dictionary:
	var dimensions := {}
	for key in sim.catalog.human_dimensions:
		var sum := 0.0
		for facet in sim.catalog.human_dimensions[key].facets: sum += f(npc, facet) * 100
		dimensions[key] = sum / 4.0
	return {"model": "HEXACO-inspired game model", "legacy_id": npc.personality,
		"dimensions": dimensions, "facets": npc.psychology.facets.duplicate(),
		"values": npc.psychology.values.duplicate(), "interests": npc.psychology.interests.duplicate(),
		"boundaries": npc.mind.boundaries.duplicate(), "action_biases": profile(npc).biases}

func execute(operation: String, args: Dictionary) -> Dictionary:
	if not enabled(): return Rules.fail("npc_agency_disabled")
	var npc: Dictionary = sim.state.social.npcs.get(str(args.get("id", "")), {})
	if not npc.has("mind"): return Rules.fail("unknown_npc")
	if operation == "inspect": return Rules.ok(describe(npc))
	if operation != "configure": return Rules.fail("use_continuous_personality_configuration")
	for field in ["facets", "values", "interests"]:
		if not args.get(field, {}) is Dictionary: return Rules.fail("invalid_human_profile")
		for key in args.get(field, {}):
			var value: Variant = args[field][key]
			if not npc.psychology[field].has(key) or not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0 or float(value) > 100: return Rules.fail("invalid_human_profile")
	for field in ["facets", "values", "interests"]: npc.psychology[field].merge(args.get(field, {}), true)
	sim.services.npc_agency._cancel(npc, "personality_configured")
	sim.services.npc_agency._build_index()
	return Rules.ok(describe(npc))

func blocked(npc: Dictionary, action: String, partner: String = "") -> String:
	var reason := ""
	if action == "boast" and public_achievements(npc) < 1: reason = "no_public_achievement"
	if action == "gossip" and _news(npc, partner).is_empty(): reason = "no_known_news"
	if action == "verify" and _unchecked(npc).is_empty(): reason = "nothing_to_verify"
	if action == "court" and int(npc.mind.declined_until.get(partner, 0)) > int(sim.state.clock.total_minutes): reason = "romantic_boundary"
	if not reason.is_empty() or partner.is_empty(): return reason
	return sim.services.npc_relationships.blocked(str(npc.id), partner, action)

func partner_bias(npc: Dictionary, other: Dictionary, relation: Dictionary) -> float:
	var view: Dictionary = sim.services.npc_relationships.view(str(npc.id), str(other.id))
	var result := float(profile(npc).familiarity) * clampf(float(relation.get("trust", 0)), -50, 50)
	result += float(view.respect) * 0.25 + float(view.closeness) * 0.25 - float(view.grievance) * 0.6
	result += sim.services.npc_relationships.known_interests(npc, other) * 12
	if float(view.care_balance) > 15: result -= (float(view.care_balance) - 15) * v(npc, "autonomy")
	return result

func social_bias(npc: Dictionary, other: Dictionary, action: String) -> float:
	return sim.services.npc_relationships.response_bias(str(npc.id), str(other.id), action)

func complete_solo(npc: Dictionary, action: String) -> bool:
	if action != "verify": return true
	var claim := _unchecked(npc)
	if claim.is_empty(): return false
	claim.checked = true
	claim.verified = claim.value == claim.reference
	claim.confidence = 1.0 if claim.verified else 0.0
	if not claim.verified:
		sim.services.npc_agency._experience(npc, "misled", str(claim.source))
		sim.services.npc_agency._log(npc, "deception_exposed", {"source": claim.source, "subject": claim.subject})
	return true

func social_success(npc: Dictionary, other: Dictionary, action: String) -> void:
	learn(npc, other)
	learn(other, npc)
	match action:
		"joke":
			sim.services.npc_agency._experience(other, "amused", str(npc.id))
			other.needs.fun = minf(100, float(other.needs.fun) + 20)
		"boast":
			var amount := public_achievements(npc)
			_store(other, "knowledge", _fact(str(npc.id), str(npc.id), "achievement", amount, true, amount), FACT_LIMIT)
			sim.services.npc_agency._experience(npc, "admired", str(other.id))
		"gossip":
			var news := _news(npc, str(other.id)).duplicate(true)
			if not news.is_empty():
				news.relay = str(npc.id)
				_store(other, "knowledge", news, FACT_LIMIT)
				sim.services.npc_agency._log(npc, "gossip", {"other": other.id, "subject": news.subject, "verified": news.verified})
		"deceive":
			var actual := public_achievements(npc)
			var claim := _fact(str(npc.id), str(npc.id), "achievement", actual + 2, false, actual)
			claim.confidence = float(profile(other).get("credulity", 0.5))
			_store(other, "claims", claim, CLAIM_LIMIT)
			sim.services.npc_agency._log(npc, "claim_made", {"other": other.id, "verified": false})
		"court":
			sim.services.npc_agency._experience(npc, "romantic_interest", str(other.id))
			sim.services.npc_agency._experience(other, "romantic_interest", str(npc.id))
