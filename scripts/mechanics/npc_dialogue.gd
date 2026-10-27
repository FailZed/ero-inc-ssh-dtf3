extends "res://scripts/mechanics/core/module.gd"
## Contextual authored conversations and autonomous invitations; no UI or network dependency.

func enabled() -> bool:
	return sim.services.npc_agency.enabled()

func rules() -> Dictionary:
	return definition("dialogue_rules", "simulation")

func _now() -> int:
	return int(sim.state.clock.total_minutes)

func initialize(npc: Dictionary) -> void:
	npc.mind.dialogue = {"version": 1, "turn": 0, "node": "end", "channel": "face",
		"utterance": {}, "recent": [], "history": [], "topics": {}, "expires": 0,
		"last_initiative": -1440, "quiet_until": 0, "pending": {}}
	if not sim.state.social.has("dialogue"): sim.state.social.dialogue = {"serial": 0, "next_contact": 0}

func voice(npc: Dictionary) -> String:
	var p = sim.services.npc_personalities
	var scores := {
		"direct": (1 - p.f(npc, "gentleness")) * 0.4 + (1 - p.f(npc, "patience")) * 0.3 + p.f(npc, "sincerity") * 0.3,
		"warm": p.f(npc, "sentimentality") * 0.4 + p.f(npc, "gentleness") * 0.3 + p.v(npc, "benevolence") * 0.3,
		"reserved": (1 - p.f(npc, "sociability")) * 0.6 + (1 - p.f(npc, "social_boldness")) * 0.3 + p.f(npc, "prudence") * 0.1,
		"playful": p.f(npc, "liveliness") * 0.5 + p.f(npc, "creativity") * 0.3 + p.f(npc, "flexibility") * 0.2,
		"practical": p.f(npc, "diligence") * 0.45 + p.f(npc, "organization") * 0.35 + p.f(npc, "prudence") * 0.2,
		"reflective": p.f(npc, "inquisitiveness") * 0.4 + p.f(npc, "aesthetic_appreciation") * 0.3 + (1 - p.f(npc, "liveliness")) * 0.3,
		"outgoing": p.f(npc, "sociability") * 0.5 + p.f(npc, "social_boldness") * 0.3 + p.f(npc, "liveliness") * 0.2}
	var winner := "reserved"
	var best := -1.0
	for id in scores:
		var value := float(scores[id]) + posmod((str(npc.id) + str(id)).hash(), 31) / 1000.0
		if value > best:
			best = value
			winner = str(id)
	return winner

func memory(npc: Dictionary) -> String:
	var bond: Dictionary = sim.services.npc_relationships.view(str(npc.id), "player")
	if float(bond.grievance) > 0:
		if bond.acknowledged: return "repair" if not bond.good_days.is_empty() else "acknowledged"
		for i in range(npc.memories.size() - 1, -1, -1):
			var item: Dictionary = npc.memories[i]
			if str(item.data.get("actor", "player")) != "player": continue
			var types := {"crime": "crime", "violence": "violence", "promise_broken": "promise", "appointment_missed": "missed"}
			if types.has(item.kind): return str(types[item.kind])
		for i in range(npc.mind.history.size() - 1, -1, -1):
			var item: Dictionary = npc.mind.history[i]
			if item.kind == "experience" and item.data.get("other", "") == "player" and item.data.get("kind", "") == "witnessed_harm": return "witness"
		return "harm"
	for i in range(npc.mind.history.size() - 1, -1, -1):
		var item: Dictionary = npc.mind.history[i]
		if _now() - int(item.minute) > 2880: continue
		if item.kind == "experience" and item.data.get("other", "") == "player" and item.data.get("kind", "") == "supported": return "help"
	for i in range(npc.memories.size() - 1, -1, -1):
		if npc.memories[i].kind == "gift" and _now() - int(npc.memories[i].minute) <= 2880: return "gift"
	return "none"

func context(npc: Dictionary) -> Dictionary:
	var mood := "neutral"
	if float(npc.needs.energy) < 25: mood = "tired"
	elif float(npc.needs.satiety) < 25: mood = "hungry"
	elif npc.mind.emotion.id in ["angry", "hurt"]: mood = "angry"
	elif npc.mind.emotion.id in ["tense", "sad"]: mood = "anxious"
	elif float(npc.needs.social) < 30: mood = "lonely"
	elif npc.mind.emotion.id in ["inspired", "confident"]: mood = "inspired"
	elif npc.mind.emotion.id in ["happy", "grateful"]: mood = "happy"
	var aspiration: Dictionary = npc.mind.aspiration
	var action := ""
	if not aspiration.completed: action = str(sim.catalog.agency_aspirations[aspiration.id].stages[int(aspiration.stage)].action)
	var interest := "arts"
	for key in npc.psychology.interests:
		if float(npc.psychology.interests[key]) > float(npc.psychology.interests[interest]): interest = str(key)
	var value := "security"
	for key in npc.psychology.values:
		if float(npc.psychology.values[key]) > float(npc.psychology.values[value]): value = str(key)
	return {"voice": voice(npc), "mood": mood, "memory": memory(npc), "goal": str(aspiration.id),
		"step": action, "completed": aspiration.completed, "interest": interest, "value": value}

func _pick(npc: Dictionary, pool_id: String) -> Dictionary:
	var variants: Array = definition("dialogue_pools", pool_id).get("variants", [])
	if variants.is_empty(): return {"id": "", "ru": ""}
	var available: Array = []
	for item in variants:
		if not str(item.id) in npc.mind.dialogue.recent: available.append(item)
	if available.is_empty():
		var last := ""
		for id in npc.mind.dialogue.recent:
			if str(id).begins_with(pool_id + "."): last = str(id)
		for item in variants:
			if item.id != last or variants.size() == 1: available.append(item)
	var index := posmod((str(npc.id) + pool_id + str(int(npc.mind.dialogue.turn))).hash(), available.size())
	return available[index]

func _variables(npc: Dictionary, ctx: Dictionary) -> Dictionary:
	var pool := "plan." + str(ctx.step)
	if not sim.catalog.dialogue_pools.has(pool): pool = "plan.generic"
	var goal := str(definition("dialogue_goals", str(ctx.goal)).intent)
	var plan := str(_pick(npc, pool).ru).format({"goal": goal})
	if ctx.completed: plan = str(_pick(npc, "goal.completed").ru)
	var bio: Dictionary = npc.biography
	var lexicon: Dictionary = sim.catalog.dialogue_biography
	var fact := _news(npc)
	var subject := str(fact.get("subject", ""))
	var source := str(fact.get("source", ""))
	var news := str(fact.get("value", ""))
	if fact.get("topic", "") == "achievement": news = str(int(fact.value))
	if fact.get("topic", "") == "occupation": news = str(lexicon.occupations.get(news, lexicon.roles.get(news, "занимается своими делами")))
	return {"goal": goal, "plan": plan, "value": str(definition("dialogue_values", str(ctx.value)).text),
		"home": str(lexicon.homes.get(npc.home, "в своём районе")), "origin": str(lexicon.origins.get(bio.origin, "этого города")),
		"siblings": str(int(bio.family.get("siblings", 0))), "subject": str(sim.state.social.npcs.get(subject, {}).get("name", "знакомого человека")),
		"source": str(sim.state.social.npcs.get(source, {}).get("name", "собеседник")), "news": news,
		"certainty": "Это известный мне проверенный факт." if fact.get("verified", false) else "Это пока не проверено; я могу ошибаться."}

func _news(npc: Dictionary) -> Dictionary:
	for field in ["knowledge", "claims"]:
		for fact in npc.mind[field]:
			if fact.topic in ["occupation", "achievement"] and fact.subject != npc.id and sim.state.social.npcs.has(fact.subject) and _now() < int(fact.expires): return fact
	return {}

func _is_partner(npc: Dictionary) -> bool:
	var ids := [str(npc.id), "player"]
	ids.sort()
	return sim.state.social.relationships.get("%s|%s" % [ids[0], ids[1]], {}).get("status", "") == "partner"

func _speak(npc: Dictionary, node: String, pool: String, extra: String = "") -> Dictionary:
	var d: Dictionary = npc.mind.dialogue
	var ctx := context(npc)
	var variables := _variables(npc, ctx)
	var parts: Array = [_pick(npc, pool)]
	if not extra.is_empty(): parts.append(_pick(npc, extra))
	var texts: Array[String] = []
	var ids: Array = []
	for part in parts:
		if str(part.id).is_empty(): continue
		texts.append(str(part.get("ru", "")).format(variables))
		ids.append(str(part.id))
		d.recent.append(str(part.id))
	while d.recent.size() > int(rules().recent_lines): d.recent.pop_front()
	d.turn = int(d.turn) + 1
	d.node = node
	d.expires = _now() + int(rules().session_duration)
	d.topics[node] = int(d.topics.get(node, 0)) + 1
	var expression := "concern" if ctx.mood in ["anxious", "tired"] else "angry" if ctx.mood == "angry" else "smile" if ctx.mood in ["happy", "inspired"] else "attentive"
	d.utterance = {"ids": ids, "text": " ".join(texts), "speaker": str(npc.id), "minute": _now(), "topic": node,
		"voice": ctx.voice, "mood": ctx.mood, "memory": ctx.memory, "expression": expression}
	if node in ["day","feelings"] and sim.services.has("pregnancy_wellbeing"):
		var concern: Dictionary = sim.services.pregnancy_wellbeing.conversation_line(str(npc.id),node=="feelings")
		if not concern.is_empty():
			d.utterance.text += " " + str(concern.text)
			d.utterance.wellbeing_line = concern.id
			d.utterance.expression = "concern" if concern.symptom!="comfortable" else "smile"
	if node in ["day","feelings"] and sim.services.has("adult_health"):
		var health_line: Dictionary = sim.services.adult_health.conversation_line(str(npc.id),node=="feelings")
		if not health_line.is_empty():
			d.utterance.text += " "+str(health_line.text)
			d.utterance.adult_health_line = health_line.id
			d.utterance.expression = "concern"
	d.history.append(d.utterance.duplicate(true))
	while d.history.size() > int(rules().history_limit): d.history.pop_front()
	return present(str(npc.id))

func _topic(npc: Dictionary, node: String) -> Dictionary:
	var ctx := context(npc)
	match node:
		"root":
			var extra := "memory." + str(ctx.memory) if ctx.memory != "none" else ("mood." + str(ctx.mood) if ctx.mood != "neutral" else "")
			var strained: bool = ctx.memory in ["crime", "violence", "promise", "missed", "witness", "harm", "acknowledged", "repair"]
			return _speak(npc, node, ("strained." if strained else "greeting.") + str(ctx.voice), extra)
		"day": return _speak(npc, node, "mood." + str(ctx.mood))
		"goal":
			var pool := "goal." + str(ctx.goal) + "." + str(ctx.voice)
			if not sim.catalog.dialogue_pools.has(pool): pool = "goal." + str(ctx.goal)
			return _speak(npc, node, "goal.completed" if ctx.completed else pool, "mood." + str(ctx.mood) if ctx.mood in ["angry", "anxious", "tired", "hungry"] else "")
		"plan": return _speak(npc, node, "goal.completed" if ctx.completed else ("plan." + str(ctx.step) if sim.catalog.dialogue_pools.has("plan." + str(ctx.step)) else "plan.generic"))
		"interests": return _speak(npc, node, "interest." + str(ctx.interest), "voice." + str(ctx.voice))
		"feelings":
			var bond: Dictionary = sim.services.npc_relationships.view(str(npc.id), "player")
			if ctx.memory != "none": return _speak(npc, node, "memory." + str(ctx.memory))
			return _speak(npc, node, "feelings.close" if float(bond.trust) >= 40 and float(bond.closeness) >= 25 else "feelings.positive" if float(bond.affection) >= 10 else "feelings.distant")
	if sim.catalog.dialogue_nodes.has(node) and node != "end":
		return _speak(npc, node, _topic_pool(npc, node, ctx))
	return _speak(npc, "end", "goodbye")

func _topic_pool(npc: Dictionary, node: String, ctx: Dictionary) -> String:
	var p = sim.services.npc_personalities
	var bond: Dictionary = sim.services.npc_relationships.view(str(npc.id), "player")
	match node:
		"work": return "topic.work." + (str(npc.biography.role) if npc.biography.role in ["worker", "learner"] else "other")
		"study": return "topic.study." + ("learner" if npc.biography.role == "learner" else "other")
		"money": return "topic.money.low" if float(npc.money) < 15 else "topic.money.stable"
		"fears":
			for fear in ["rejection", "stagnation", "poverty"]:
				var feeling: Dictionary = npc.mind.fears.get(fear, {})
				if float(feeling.get("strength", 0)) > 0 and _now() < int(feeling.get("expires", 0)): return "topic.fears." + fear
			return "topic.fears.general"
		"news":
			var fact := _news(npc)
			return "topic.news.none" if fact.is_empty() else "topic.news." + str(fact.topic)
		"romance":
			if float(bond.grievance) > 0: return "memory." + str(ctx.memory)
			var mutual: bool = sim.services.social_rules.compatibility(str(npc.id), "player").data.mutual_attraction
			return "topic.romance.partner" if _is_partner(npc) else "topic.romance.interested" if mutual and float(bond.interest) >= 10 else "topic.romance.distant"
		"attraction":
			var mutual: bool = sim.services.social_rules.compatibility(str(npc.id), "player").data.mutual_attraction
			return "topic.attraction.yes" if mutual and float(bond.interest) >= 10 and float(bond.grievance) < 10 else "topic.attraction.no"
		"expectations": return "topic.expectations.autonomy" if p.v(npc, "autonomy") >= 0.65 else "topic.expectations.security" if p.v(npc, "security") >= 0.65 else "topic.expectations.care"
		"jealousy": return "topic.jealousy.anxious" if p.f(npc, "anxiety") >= 0.65 and float(bond.closeness) >= 15 else "topic.jealousy.calm"
		"desire", "boundaries":
			if node == "boundaries" and not npc.mind.boundaries.romance: return "topic.boundaries.closed"
			return "topic." + node + (".reserved" if ctx.voice in ["reserved", "reflective"] else ".warm" if ctx.voice == "warm" else ".direct")
		"intimacy": return "topic.intimacy.slow" if p.f(npc, "prudence") >= 0.65 or ctx.mood in ["tired", "anxious", "angry"] else "topic.intimacy.ready"
	return "topic." + node

func _choice_blocked(npc: Dictionary, spec: Dictionary) -> String:
	for tag in spec.get("tags", []):
		if tag in sim.state.preferences.disabled_tags: return "content_disabled"
	if "adult" in spec.get("tags", []) and (int(npc.age) < 18 or int(sim.state.player.get("age", 0)) < 18): return "adults_only"
	var bond: Dictionary = sim.services.npc_relationships.view(str(npc.id), "player")
	for key in ["trust", "closeness", "interest"]:
		if float(bond[key]) < float(spec.get("min_" + key, -100 if key == "trust" else 0)): return "insufficient_closeness"
	if spec.get("gossip", false) and not npc.mind.boundaries.gossip: return "gossip_boundary"
	if spec.get("mutual", false):
		var blocked: String = sim.services.npc_relationships.blocked("player", str(npc.id), "court")
		if not blocked.is_empty(): return blocked
	if spec.get("private", false) and npc.mind.dialogue.channel == "face":
		for other in sim.state.social.npcs.values():
			if other.id != npc.id and other.location == npc.location and other.activity != "sleep": return "private_conversation_required"
	return ""

func availability(npc: Dictionary, channel: String = "face") -> String:
	if not npc.mind.boundaries.contact: return "contact_boundary"
	if channel == "message":
		if not str(npc.id) in sim.state.social.contacts: return "missing_contact"
		if npc.activity == "sleep": return "npc_sleeping"
		if npc.activity in ["eat", "recover"] or npc.decision.get("committed", false): return "npc_busy"
		return ""
	if npc.location != sim.state.world.location: return "npc_not_present"
	if not str(npc.mind.active.get("partner", "")).is_empty(): return "npc_busy"
	var available: Dictionary = sim.services.social_rules.availability(str(npc.id), true)
	return "" if available.ok else str(available.error)

func present(id: String) -> Dictionary:
	var npc: Dictionary = sim.state.social.npcs.get(id, {})
	if not npc.has("mind"): return {}
	var d: Dictionary = npc.mind.dialogue
	if d.utterance.is_empty(): return {}
	var choices: Array = []
	var ids: Array = definition("dialogue_nodes", str(d.node)).get("choices", []).duplicate()
	if d.node != "end" and d.node != "initiative":
		if d.node != "root": ids.append("back")
		ids.append("leave")
	for key in ids:
		var spec := definition("dialogue_choices", str(key))
		var blocked := _choice_blocked(npc, spec)
		if blocked == "content_disabled" or blocked == "adults_only": continue
		var action := str(spec.action)
		if blocked.is_empty() and d.channel == "message" and not action.is_empty(): blocked = "npc_not_present"
		elif blocked.is_empty() and not action.is_empty():
			blocked = sim.services.npc_relationships.blocked("player", id, action)
		if key == "apologize" and blocked == "no_unacknowledged_harm": continue
		if key == "court" and "romance" in sim.state.preferences.disabled_tags: continue
		if key == "accept" and blocked.is_empty(): blocked = _offer_valid(npc, str(d.pending.get("token", "")))
		if not key in ["leave", "decline", "stop"] and blocked.is_empty(): blocked = availability(npc, str(d.channel))
		choices.append({"id": key, "text": str(definition("dialogue_labels", str(spec.label)).ru), "blocked": blocked, "minutes": int(spec.minutes)})
	return {"utterance": d.utterance.duplicate(true), "choices": choices, "node": d.node, "channel": d.channel, "turn": d.turn}

func _advance_talk(npc: Dictionary, minutes: int) -> Dictionary:
	if minutes == 0: return Rules.ok()
	if npc.mind.dialogue.channel == "message": return sim.advance(minutes)
	sim.services.npc_agency._cancel(npc, "conversation")
	var pinned := int(npc.pinned_until)
	npc.pinned_until = maxi(pinned, _now() + minutes + 1)
	var result: Dictionary = sim.advance(minutes)
	npc.pinned_until = pinned
	return result

func execute(operation: String, args: Dictionary) -> Dictionary:
	if not enabled(): return Rules.fail("npc_agency_disabled")
	var npc: Dictionary = sim.state.social.npcs.get(str(args.get("id", "")), {})
	if not npc.has("mind"): return Rules.fail("unknown_npc")
	var d: Dictionary = npc.mind.dialogue
	match operation:
		"inspect": return Rules.ok(present(str(npc.id)))
		"close":
			d.node = "end"
			d.expires = 0
			return Rules.ok()
		"decline": return _decline(npc, str(args.get("initiative", "")), bool(args.get("stop", false)))
		"open":
			var channel := str(args.get("channel", "face"))
			if not channel in ["face", "message"]: return Rules.fail("invalid_dialogue_channel")
			d.channel = channel
			var token := str(args.get("initiative", ""))
			if not token.is_empty():
				var offered := _offer_valid(npc, token)
				if not offered.is_empty(): return Rules.fail(offered)
				d.channel = str(d.pending.channel)
				d.node = "initiative"
				d.utterance = d.pending.utterance.duplicate(true)
				d.expires = _now() + int(rules().session_duration)
				return Rules.ok(present(str(npc.id)))
			var reason := availability(npc, channel)
			if not reason.is_empty():
				if channel == "message" or reason == "npc_not_present": return Rules.fail(reason)
				var pool := "busy.boundary" if reason == "contact_boundary" else "gone" if reason == "npc_not_present" else "busy.social" if not str(npc.mind.active.get("partner", "")).is_empty() else "busy." + str(npc.activity)
				if not sim.catalog.dialogue_pools.has(pool): pool = "busy.generic"
				return Rules.ok(_speak(npc, "end", pool))
			return Rules.ok(_topic(npc, "root"))
		"choose":
			var key := str(args.get("choice", ""))
			if _now() >= int(d.expires): return Rules.fail("dialogue_expired")
			var available := present(str(npc.id))
			if int(args.get("turn", -1)) != int(d.turn): return Rules.fail("stale_dialogue_turn")
			var selected := {}
			for choice in available.get("choices", []):
				if choice.id == key: selected = choice
			if selected.is_empty(): return Rules.fail("unknown_dialogue_choice")
			if not str(selected.blocked).is_empty(): return Rules.fail(str(selected.blocked))
			if key in ["decline", "stop"]: return _decline(npc, str(d.pending.get("token", "")), key == "stop")
			var destination := str(definition("dialogue_choices", key).to)
			if key == "accept":
				var invalid := _offer_valid(npc, str(d.pending.get("token", "")))
				if not invalid.is_empty(): return Rules.fail(invalid)
				destination = "feelings" if d.pending.kind == "concern" else "romance" if d.pending.kind == "romance" else "day" if d.pending.kind in ["lonely", "gratitude"] else "goal"
				d.pending = {}
			var spec := definition("dialogue_choices", key)
			var action := str(spec.action)
			if not action.is_empty():
				var before: Dictionary = sim.services.npc_relationships.view(str(npc.id), "player")
				var result: Dictionary = sim.services.npc_relationships.execute("interact", {"id": str(npc.id), "action": action})
				if not result.ok: return result
				var repeated: bool = _now() - int(before.recent.get(action, -10080)) < 180 or float(before.gain_used) >= 8 and int(before.gain_day) == int(sim.state.clock.day_index)
				var pool := "answer.decline" if not result.data.accepted else "answer.repeat" if repeated else "answer.help" if action == "cooperate" else "answer.support" if action == "support" else "answer." + action
				var reply := _speak(npc, "answer", pool, "voice." + voice(npc) if result.data.accepted and not repeated else "")
				reply.accepted = bool(result.data.accepted)
				return Rules.ok(reply)
			var elapsed := _advance_talk(npc, int(spec.minutes))
			if not elapsed.ok: return elapsed
			var condition := _choice_blocked(npc, spec)
			if not condition.is_empty(): return Rules.fail(condition)
			if d.channel == "message": _message(npc, str(selected.text), "player_reply", false)
			var reply := _topic(npc, destination)
			if d.channel == "message": _message(npc, str(reply.utterance.text), "npc_reply")
			return Rules.ok(reply)
	return Rules.fail("unknown_operation")

func _offer_valid(npc: Dictionary, token: String) -> String:
	var pending: Dictionary = npc.mind.dialogue.pending
	if pending.is_empty() or token != str(pending.token) or _now() >= int(pending.expires): return "stale_initiative"
	var bond: Dictionary = sim.services.npc_relationships.view(str(npc.id), "player")
	match str(pending.kind):
		"goal":
			if npc.mind.aspiration.completed or npc.mind.aspiration.id != pending.get("goal_id", "") or int(npc.mind.aspiration.stage) != int(pending.get("goal_stage", -1)): return "stale_initiative"
		"gratitude":
			if not memory(npc) in ["help", "gift"]: return "stale_initiative"
		"lonely":
			if float(npc.needs.social) >= 35: return "stale_initiative"
		"concern":
			if float(bond.grievance) < 20 or bond.acknowledged: return "stale_initiative"
		"romance":
			if not sim.services.npc_relationships.blocked("player", str(npc.id), "court").is_empty(): return "stale_initiative"
	return availability(npc, str(pending.channel))

func offers() -> Array:
	var result: Array = []
	if not enabled(): return result
	for npc in sim.state.social.npcs.values():
		var pending: Dictionary = npc.mind.dialogue.pending
		if pending.is_empty() or not _offer_valid(npc, str(pending.token)).is_empty(): continue
		result.append({"id": str(npc.id), "name": str(npc.name), "initiative": pending.token, "channel": pending.channel, "text": pending.utterance.text})
	return result

func _decline(npc: Dictionary, token: String, stop: bool) -> Dictionary:
	var d: Dictionary = npc.mind.dialogue
	if d.pending.is_empty() or str(d.pending.token) != token: return Rules.fail("stale_initiative")
	var remote: bool = d.pending.channel == "message"
	d.pending = {}
	d.quiet_until = _now() + int(rules().stop_cooldown if stop else rules().refusal_cooldown)
	var reply := _speak(npc, "end", "answer.space")
	if remote: _message(npc, str(reply.utterance.text), "npc_reply")
	return Rules.ok(reply)

func _message(npc: Dictionary, text: String, kind: String, incoming: bool = true) -> void:
	sim.state.social.messages.append({"id": sim.state.social.next_message_id, "npc": str(npc.id), "text": text,
		"incoming": incoming, "read": not incoming, "minute": _now(), "kind": kind})
	sim.state.social.next_message_id += 1
	var automatic: Array = []
	for i in range(sim.state.social.messages.size()):
		if sim.state.social.messages[i].get("kind", "") in ["npc_initiative", "npc_reply", "player_reply"]: automatic.append(i)
	while automatic.size() > int(rules().message_limit):
		sim.state.social.messages.remove_at(int(automatic[0]))
		automatic.pop_front()
		for i in range(automatic.size()): automatic[i] = int(automatic[i]) - 1

func local_initiative(npc: Dictionary) -> bool:
	return npc.location == sim.state.world.location and npc.location in ["global_map", "training_center", "residential_district"]

func tick(minute: int) -> void:
	if not enabled() or minute % 15 != 0: return
	var occupied := false
	for npc in sim.state.social.npcs.values():
		var d: Dictionary = npc.mind.dialogue
		if not d.pending.is_empty():
			if not _offer_valid(npc, str(d.pending.token)).is_empty(): d.pending = {}
			else: occupied = true
	if occupied or minute < int(sim.state.social.dialogue.next_contact): return
	var hour := int(sim.state.clock.minute_of_day) / 60
	if hour < 7 or hour >= 22: return
	if not sim.state.encounters.combat.is_empty() and sim.state.encounters.combat.status == "active": return
	if not sim.state.encounters.game.is_empty() and sim.state.encounters.game.status == "active": return
	var best := -1.0
	var winner := ""
	var reason := "goal"
	var channel := "face"
	var ids: Array = sim.state.social.npcs.keys()
	ids.sort()
	for id in ids:
		var npc: Dictionary = sim.state.social.npcs[id]
		var d: Dictionary = npc.mind.dialogue
		if minute < int(d.quiet_until) or minute - int(d.last_initiative) < int(rules().npc_cooldown): continue
		if d.node != "end" and minute < int(d.expires): continue
		if not npc.mind.boundaries.contact or npc.decision.get("committed", false) or int(npc.pinned_until) > minute: continue
		if npc.activity in ["sleep", "eat", "recover", "travel"] or not str(npc.mind.active.get("partner", "")).is_empty(): continue
		var local: bool = local_initiative(npc)
		if not local and not str(id) in sim.state.social.contacts: continue
		var p = sim.services.npc_personalities
		var bond: Dictionary = sim.services.npc_relationships.view(str(id), "player")
		if not local and float(bond.trust) < 4: continue
		if local and not str(id) in sim.state.social.contacts and p.f(npc, "social_boldness") < 0.6: continue
		var kind := "goal"
		var score: float = p.f(npc, "sociability") * 0.5 + p.f(npc, "social_boldness") * 0.3
		if float(bond.grievance) >= 20 and not bond.acknowledged:
			kind = "concern"
			score += 3.0
		elif memory(npc) in ["help", "gift"]:
			kind = "gratitude"
			score += 2.0
		elif float(npc.needs.social) < 35:
			kind = "lonely"
			score += 1.0
		elif npc.mind.aspiration.id == "relationship" and npc.mind.boundaries.romance and not "romance" in sim.state.preferences.disabled_tags and float(bond.trust) >= 35 and float(bond.interest) >= 30 and float(bond.closeness) >= 30 and sim.services.npc_relationships.blocked("player", str(id), "court").is_empty():
			kind = "romance"
			score += 0.5
		if kind == "goal" and npc.mind.aspiration.completed: continue
		if score > best:
			best = score
			winner = str(id)
			reason = kind
			channel = "face" if local else "message"
	if winner.is_empty(): return
	var npc: Dictionary = sim.state.social.npcs[winner]
	var d: Dictionary = npc.mind.dialogue
	var previous: Dictionary = {"node": d.node, "utterance": d.utterance.duplicate(true), "expires": d.expires}
	var pool := "initiative.message" if channel == "message" and reason == "goal" else "initiative." + reason
	_speak(npc, "initiative", pool)
	sim.state.social.dialogue.serial = int(sim.state.social.dialogue.serial) + 1
	d.pending = {"token": winner + ":" + str(sim.state.social.dialogue.serial), "kind": reason, "channel": channel,
		"created": minute, "expires": minute + int(rules().offer_duration), "utterance": d.utterance.duplicate(true)}
	if reason == "goal":
		d.pending.goal_id = str(npc.mind.aspiration.id)
		d.pending.goal_stage = int(npc.mind.aspiration.stage)
	d.node = previous.node
	d.utterance = previous.utterance
	d.expires = previous.expires
	d.last_initiative = minute
	sim.state.social.dialogue.next_contact = minute + int(rules().global_cooldown)
	if channel == "message": _message(npc, str(d.pending.utterance.text), "npc_initiative")
	emit_event("npc_initiative", {"npc": winner, "channel": channel, "kind": reason, "text": d.pending.utterance.text})
