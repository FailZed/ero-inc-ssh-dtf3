extends "res://scripts/mechanics/social_rules.gd"

func autonomy() -> void:
	# HumanAgency already simulates actual meetings. No free daily relationship points.
	if not sim.services.npc_agency.enabled(): super.autonomy()

func compatibility(a: String, b: String) -> Dictionary:
	var first := _actor(a)
	var second := _actor(b)
	if first.is_empty() or second.is_empty() or a == b: return Rules.fail("unknown_relationship_target")
	var mutual: bool = str(second.gender) in first.attracted_to and str(first.gender) in second.attracted_to
	var score := 20.0
	if first.has("psychology") and second.has("psychology"):
		score += sim.services.npc_relationships.known_interests(first, second) * 35
		score += sim.services.npc_relationships.known_alignment(first, second) * 30
	return Rules.ok({"mutual_attraction": mutual, "score": score})

func conversation_forecast(id: String, action_id: String) -> Dictionary:
	if not sim.services.npc_agency.enabled(): return super.conversation_forecast(id, action_id)
	var aliases: Dictionary = sim.services.npc_relationships.ACTION_ALIASES
	var action := str(aliases.get(action_id, action_id))
	var result: Dictionary = sim.services.npc_relationships.forecast("player", id, action)
	return Rules.ok({"chance": result.chance, "blocked": result.blocked})

func execute(operation: String, args: Dictionary) -> Dictionary:
	if sim.services.npc_agency.enabled():
		if operation == "biography":
			var npc: Dictionary = sim.state.social.npcs.get(str(args.get("id", "")), {})
			if not npc.has("mind"): return Rules.fail("unknown_npc")
			return Rules.ok({"biography": npc.biography.duplicate(true), "personality": sim.services.npc_personalities.describe(npc), "description": describe(str(npc.id))})
		if operation in ["date", "ask_history", "promise", "fulfill"]:
			var reason: String = sim.services.npc_relationships.blocked("player", str(args.get("id", "")), "court" if operation == "date" else "connect")
			if not reason.is_empty(): return Rules.fail(reason)
		if operation == "apologize": return sim.services.npc_relationships.execute("interact", {"id": args.get("id", ""), "action": "apologize"})
		if operation == "partner": return sim.services.npc_relationships.execute("interact", {"id": args.get("id", ""), "action": "invite_relationship"})
		if operation == "breakup": return sim.services.npc_relationships.execute("separate", args)
	return super.execute(operation, args)

func describe(id: String) -> String:
	if not sim.services.npc_agency.enabled(): return super.describe(id)
	var npc: Dictionary = sim.state.social.npcs.get(id, {})
	if not npc.has("mind"): return ""
	var info: Dictionary = sim.services.npc_personalities.describe(npc)
	var tendencies: Array[String] = []
	for key in info.dimensions:
		var value := float(info.dimensions[key])
		if value >= 65 or value <= 35:
			tendencies.append("%s: %s" % [definition("human_dimensions", str(key)).label, "выражена сильнее" if value >= 65 else "выражена слабее"])
	return "%s, %d. %s. Текущая цель: %s." % [npc.name, int(npc.age), "; ".join(tendencies) if not tendencies.is_empty() else "Качества сочетаются без резко выраженной доминанты", definition("agency_aspirations", str(npc.mind.aspiration.id)).label]
