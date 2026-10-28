extends "res://scripts/mechanics/core/module.gd"
## Original, opt-in life simulation. All durable decisions live in the snapshot.
const Utility = preload("res://scripts/mechanics/core/utility_ai.gd")
const Employment = preload("res://scripts/mechanics/npc_employment.gd")
const FLAG := "npc_agency_enabled"
var _by_location: Dictionary = {}

func enabled() -> bool:
	return bool(sim.state.world.flags.get(FLAG, false))

func rules() -> Dictionary:
	return definition("agency_rules", "simulation")

func execute(operation: String, args: Dictionary) -> Dictionary:
	if operation == "enable":
		if enabled(): return Rules.ok()
		sim.state.world.flags[FLAG] = true
		for npc in sim.state.social.npcs.values(): initialize_npc(npc)
		_build_index()
		for id in _ids(): _choose(sim.state.social.npcs[id])
		return Rules.ok()
	if not enabled(): return Rules.fail("npc_agency_disabled")
	var id := str(args.get("id", ""))
	if not sim.state.social.npcs.has(id): return Rules.fail("unknown_npc")
	var npc: Dictionary = sim.state.social.npcs[id]
	match operation:
		"inspect": return Rules.ok(inspect(id))
		"set_aspiration":
			var goal := str(args.get("goal", ""))
			if not sim.catalog.agency_aspirations.has(goal): return Rules.fail("unknown_aspiration")
			if goal == "relationship" and "romance" in sim.state.preferences.disabled_tags: return Rules.fail("content_disabled")
			if goal == "career" and npc.biography.role != "worker": return Rules.fail("aspiration_role")
			if npc.mind.aspiration.id == goal: return Rules.ok()
			npc.mind.aspiration = _aspiration(goal)
			npc.mind.last_progress = _now()
			_cancel(npc, "new_goal")
			_build_index()
			_choose(npc)
		"experience":
			var kind := str(args.get("kind", ""))
			var other := str(args.get("other", ""))
			if not sim.catalog.agency_experiences.has(kind): return Rules.fail("unknown_experience")
			if not other.is_empty() and other != "player" and (other == id or not sim.state.social.npcs.has(other)): return Rules.fail("unknown_relationship_target")
			_experience(npc, kind, other)
		"encourage":
			if npc.location != sim.state.world.location: return Rules.fail("npc_not_present")
			var available: Dictionary = sim.services.social_rules.availability(id, true)
			if not available.ok: return available
			if float(sim.services.social.relationship(id, "player").trust) < 10: return Rules.fail("insufficient_trust")
			if int(npc.mind.get("encouraged_day", -1)) == int(sim.state.clock.day_index): return Rules.fail("encouragement_daily_limit")
			npc.mind.encouraged_day = int(sim.state.clock.day_index)
			_experience(npc, "supported", "player")
			_log(npc, "encouraged", {"goal": npc.mind.aspiration.id})
			return sim.advance(5)
		_: return Rules.fail("unknown_operation")
	return Rules.ok()

func _now() -> int:
	return int(sim.state.clock.total_minutes)

func _ids() -> Array:
	var ids: Array = sim.state.social.npcs.keys()
	ids.sort()
	return ids

func _aspiration(id: String) -> Dictionary:
	return {"id": id, "stage": 0, "progress": 0, "completed": false, "milestones": 0}

func initialize_npc(npc: Dictionary) -> void:
	if not enabled() or npc.has("mind"): return
	var goal := str(npc.biography.goal)
	if not sim.catalog.agency_aspirations.has(goal): goal = "wellbeing"
	if goal == "career" and npc.biography.role != "worker": goal = "mastery"
	goal = sim.services.npc_personalities.choose_goal(npc, goal)
	npc.needs.merge({"hygiene": 85.0, "social": 70.0, "fun": 75.0})
	npc.mind = {"version": 2, "aspiration": _aspiration(goal), "active": {},
		"updated_at": _now(), "last_progress": _now(), "last_social": -1440,
		"moodlets": [], "sentiments": {}, "fears": {}, "wants": [], "history": [],
		"recent_actions": [], "completed_actions": {}, "satisfaction": 0,
		"want_day": -1, "fulfilled_today": [], "emotion": {"id": "content", "strength": 0.0},
		"decision": {}, "skill_remainders": {}, "income_remainder": 0.0,
		"completed_at": 0, "aspiration_history": []}
	Employment.initialize(npc,sim.catalog,int(sim.state.clock.day_index))
	sim.services.npc_personalities.initialize_mind(npc)
	_refresh_wants(npc)

func _action_spec(npc: Dictionary, id: String) -> Dictionary:
	return Employment.action(npc,id,sim.catalog,sim.state.clock)

func action_minutes(npc: Dictionary, id: String) -> int:
	var duration := int(sim.catalog.agency_actions[id].minutes)
	if id != "work": return duration
	return mini(duration,Employment.available_minutes(npc,sim.catalog,sim.state.clock))

func employment_view(id: String) -> Dictionary:
	var npc: Dictionary = sim.state.social.npcs.get(id,{})
	return Employment.view(npc,sim.catalog,sim.state.clock) if npc.has("mind") else {}

func inspect(id: String) -> Dictionary:
	var npc: Dictionary = sim.state.social.npcs.get(id, {})
	if not npc.has("mind"): return {}
	_build_index()
	return {"id": id, "needs": npc.needs.duplicate(true), "mind": npc.mind.duplicate(true),
		"employment":employment_view(id),"calendar":sim.services.npc_planner.calendar.windows(id),"obligation":sim.services.npc_planner.active_owner(id),
		"personality": sim.services.npc_personalities.describe(npc),
		"plan": _agenda(npc), "candidates": evaluate(npc), "location": npc.location, "activity": npc.activity}

func conversation_bias(id: String, action: String = "") -> float:
	if not enabled(): return 0.0
	var npc: Dictionary = sim.state.social.npcs.get(id, {})
	if not npc.has("mind"): return 0.0
	return clampf(_sentiment(npc, "player") * 0.002 + sim.services.npc_personalities.conversation_bias(npc, action), -0.25, 0.20)

func observe(id: String, kind: String, data: Dictionary) -> void:
	if not enabled(): return
	var npc: Dictionary = sim.state.social.npcs[id]
	initialize_npc(npc)
	match kind:
		"gift", "apology": _experience(npc, "supported", "player")
		"crime", "betrayal": _experience(npc, "betrayed", str(data.get("actor", "player")))
		"promise_broken", "appointment_missed": _experience(npc, "rejected", "player")
		"listen", "share_interest":
			if data.get("accepted", false): _experience(npc, "supported", "player")
		"offer_help":
			if data.get("accepted", false): _experience(npc, "supported", "player")
		"joke":
			if data.get("accepted", false): _experience(npc, "amused", "player")
		"flirt":
			if data.get("accepted", false): _experience(npc, "romantic_interest", "player")

func _build_index() -> void:
	_by_location.clear()
	for id in _ids():
		var npc: Dictionary = sim.state.social.npcs[id]
		var location := str(npc.location)
		if not _by_location.has(location): _by_location[location] = []
		_by_location[location].append(id)

func tick(minute: int) -> void:
	if not enabled() or minute % int(rules().decision_minutes) != 0: return
	var ids := _ids()
	for id in ids:
		var npc: Dictionary = sim.state.social.npcs[id]
		initialize_npc(npc)
		_age(npc, minute)
	_build_index()
	# Settle completed work before making the next decisions. Recipients never pay twice.
	for id in ids:
		var npc: Dictionary = sim.state.social.npcs[id]
		var active: Dictionary = npc.mind.active
		if int(npc.pinned_until) > minute:
			_cancel(npc, "external_commitment")
			continue
		var content_blocked := false
		if not active.is_empty():
			for tag in definition("agency_actions", str(active.action)).get("tags", []):
				if tag in sim.state.preferences.disabled_tags: content_blocked = true
		if content_blocked:
			_cancel(npc, "content_disabled")
			continue
		if not active.is_empty() and active.get("phase", "") != "receiving" and minute >= int(active.due): _finish(npc)
		active = npc.mind.active
		var urgent := _urgent(npc)
		var schedule := _commitment(npc)
		if not active.is_empty() and not urgent.is_empty() and active.action != urgent:
			_cancel(npc, "urgent_need")
		elif not active.is_empty() and not schedule.is_empty() and active.action != schedule.activity:
			_cancel(npc, "schedule")
		active = npc.mind.active

func _age(npc: Dictionary, minute: int) -> void:
	var mind: Dictionary = npc.mind
	var hours := maxf(0.0, (minute - int(mind.updated_at)) / 60.0)
	for need in rules().need_decay:
		var decay := float(rules().need_decay[need])
		if need == "social": decay *= float(sim.services.npc_personalities.profile(npc).social_decay)
		# Fixed decimal units make JSON restore independent of float print precision.
		var units := int(round(float(npc.needs[need]) * 10000.0)) - int(round(decay * hours * 10000.0))
		npc.needs[need] = clampi(units, 0, 1000000) / 10000.0
	npc.fatigue = maxf(0.0, float(npc.fatigue) - hours * 10.0)
	mind.updated_at = minute
	sim.services.npc_personalities.age(npc, minute)
	if mind.aspiration.id == "relationship" and "romance" in sim.state.preferences.disabled_tags:
		mind.aspiration = _aspiration("community")
		mind.last_progress = minute
		_log(npc, "new_aspiration", {"goal": "community", "reason": "content_filter"})
	if mind.aspiration.completed and minute - int(mind.completed_at) >= 1440:
		mind.aspiration_history.append(mind.aspiration.duplicate(true))
		while mind.aspiration_history.size() > 5: mind.aspiration_history.pop_front()
		var choices: Array = sim.catalog.agency_aspirations.keys()
		choices.sort()
		choices.erase(str(mind.aspiration.id))
		if npc.biography.role != "worker": choices.erase("career")
		var index := (int(npc.id.hash()) & 0x7fffffff) % choices.size()
		var next_goal := str(choices[index])
		next_goal = sim.services.npc_personalities.choose_goal(npc, next_goal, str(mind.aspiration.id))
		mind.aspiration = _aspiration(next_goal)
		mind.last_progress = minute
		_log(npc, "new_aspiration", {"goal": mind.aspiration.id})
	for i in range(mind.moodlets.size() - 1, -1, -1):
		if minute >= int(mind.moodlets[i].expires): mind.moodlets.remove_at(i)
	for other in mind.sentiments.keys():
		if minute >= int(mind.sentiments[other].expires): mind.sentiments.erase(other)
	for fear in mind.fears.keys():
		if minute >= int(mind.fears[fear].expires): mind.fears.erase(fear)
	for i in range(mind.wants.size() - 1, -1, -1):
		if minute >= int(mind.wants[i].expires): mind.wants.remove_at(i)
	_refresh_wants(npc)
	if not mind.aspiration.completed and minute - int(mind.last_progress) >= int(rules().stagnation_minutes) and not mind.fears.has("stagnation"):
		mind.fears.stagnation = {"strength": 20.0, "expires": minute + 1440}
		_experience(npc, "setback")
	if float(npc.money) < 10 and not mind.fears.has("poverty"):
		mind.fears.poverty = {"strength": 20.0, "expires": minute + 1440}
	_emotion(npc)

func _emotion(npc: Dictionary) -> void:
	var dominant := "content"
	var strength := 0.0
	for moodlet in npc.mind.moodlets:
		var remaining := clampf((int(moodlet.expires) - _now()) / float(moodlet.duration), 0, 1)
		var value := float(moodlet.strength) * remaining
		if value > strength:
			strength = value
			dominant = str(moodlet.emotion)
	if float(npc.needs.social) < 25 and strength < 18:
		dominant = "lonely"
		strength = 18.0
	if float(npc.needs.energy) < 20 and strength < 25:
		dominant = "exhausted"
		strength = 25.0
	npc.mind.emotion = {"id": dominant, "strength": strength}

func _experience(npc: Dictionary, kind: String, other: String = "") -> void:
	var spec := definition("agency_experiences", kind)
	if spec.is_empty(): return
	var profile: Dictionary = sim.services.npc_personalities.profile(npc)
	var positive: bool = str(spec.emotion) in ["grateful", "happy", "confident", "content"]
	var gain := 1.0 if positive else float(profile.negative_gain)
	var duration := maxi(1, int(round(float(spec.duration) * float(profile.memory_duration))))
	var strength := minf(100, float(spec.strength) * gain)
	var moodlets: Array = npc.mind.moodlets
	# Repeated events refresh a moodlet instead of multiplying its strength forever.
	var key := kind + ":" + other
	for i in range(moodlets.size() - 1, -1, -1):
		if moodlets[i].key == key: moodlets.remove_at(i)
	moodlets.append({"key": key, "emotion": spec.emotion, "strength": strength,
		"duration": duration, "expires": _now() + duration})
	while moodlets.size() > int(rules().moodlet_limit): moodlets.pop_front()
	if not other.is_empty() and other != npc.id and (other == "player" or sim.state.social.npcs.has(other)) and float(spec.sentiment) != 0:
		var sentiments: Dictionary = npc.mind.sentiments
		var value := clampf(_sentiment(npc, other) + float(spec.sentiment) * gain, -100, 100)
		if not sentiments.has(other) and sentiments.size() >= int(rules().sentiment_limit): sentiments.erase(sentiments.keys()[0])
		sentiments[other] = {"value": value, "expires": _now() + int(round(10080 * float(profile.memory_duration))), "kind": kind}
	if spec.has("fear"): npc.mind.fears[str(spec.fear)] = {"strength": minf(100, 25.0 * float(profile.fear_gain)), "expires": _now() + 2880}
	npc.needs.mood = clampf(float(npc.needs.mood) + strength * (0.25 if positive else -0.25), 0, 100)
	_emotion(npc)
	_log(npc, "experience", {"kind": kind, "other": other})

func _sentiment(npc: Dictionary, other: String) -> float:
	var entry: Dictionary = npc.mind.sentiments.get(other, {})
	if entry.is_empty() or _now() >= int(entry.expires): return 0.0
	return float(entry.value)

func _log(npc: Dictionary, kind: String, data: Dictionary) -> void:
	var record := {"kind": kind, "minute": _now(), "data": data.duplicate(true)}
	npc.mind.history.append(record)
	while npc.mind.history.size() > int(rules().history_limit): npc.mind.history.pop_front()
	# Routine details remain inspectable per NPC; presenters receive meaningful changes.
	if not kind in ["intent", "action_completed", "work_paid"]: emit_event("npc_life_" + kind, {"npc": npc.id, "details": data})

func _stage(npc: Dictionary) -> Dictionary:
	var aspiration: Dictionary = npc.mind.aspiration
	if aspiration.completed: return {}
	return definition("agency_aspirations", str(aspiration.id)).stages[int(aspiration.stage)]

func _agenda(npc: Dictionary) -> Array:
	var stage := _stage(npc)
	if stage.is_empty(): return []
	var action := str(stage.action)
	var spec := _action_spec(npc,action)
	var agenda: Array = []
	for skill in spec.get("requires_skill", {}):
		if int(npc.skills.get(skill, 0)) < int(spec.requires_skill[skill]):
			agenda.append("create" if skill == "journalism" else "practice")
	if action == "support" and _partner(npc, spec, action).is_empty(): agenda.append("connect")
	if spec.get("social", false) and _partner(npc, spec, action).is_empty(): agenda.push_front("visit")
	agenda.append(action)
	return agenda

func _refresh_wants(npc: Dictionary) -> void:
	var mind: Dictionary = npc.mind
	var day := int(sim.state.clock.day_index)
	if int(mind.want_day) != day:
		mind.want_day = day
		mind.fulfilled_today.clear()
	var desired: Array = []
	var by_need := {"energy": "sleep", "satiety": "eat", "hygiene": "wash", "social": "connect", "fun": "recreation"}
	for need in by_need:
		if float(npc.needs[need]) < 45: desired.append(str(by_need[need]))
	var stage := _stage(npc)
	if not stage.is_empty(): desired.append(str(stage.action))
	for action in desired:
		if mind.wants.size() >= int(rules().want_limit): break
		if action in mind.fulfilled_today: continue
		var exists := false
		for want in mind.wants:
			if want.action == action: exists = true
		if not exists: mind.wants.append({"action": action, "expires": _now() + int(rules().want_duration)})

func _urgent(npc: Dictionary) -> String:
	if float(npc.health) <= 20: return "recover"
	if float(npc.needs.energy) < float(rules().critical_need): return "sleep"
	if float(npc.needs.satiety) < float(rules().critical_need): return "eat"
	if float(npc.needs.hygiene) < 12: return "wash"
	return ""

func _commitment(npc: Dictionary) -> Dictionary:
	# Check obligations independently: the legacy planner can return night sleep first.
	for entry in npc.schedule:
		var action := str(entry.get("activity", "rest"))
		if not bool(entry.get("mandatory", action in ["work", "study"])): continue
		if action == "work" and not Employment.blocked(npc,sim.catalog,sim.state.clock).is_empty(): continue
		if not sim.services.world.is_open(entry) or not Rules.check(sim.services.npc_behavior.context(npc), entry.get("requirements", {})): continue
		var destination := str(entry.get("location", npc.home))
		if not _location_open(npc, destination): continue
		return {"activity": action, "location": destination, "reason": "schedule", "committed": true}
	return {}

func _destination(npc: Dictionary, spec: Dictionary) -> String:
	return str(npc.home) if spec.destination == "home" else str(spec.destination)

func _location_open(npc: Dictionary, location: String, minute: int = -1, ignore_hours: bool = false, invited_destination: String = "") -> bool:
	if minute < 0: minute = _now()
	return sim.services.world.actor_availability(location,str(npc.id),minute,ignore_hours,invited_destination).ok

func _route(npc: Dictionary, start: String, destination: String, minute: int = -1, urgent_destination: bool = false, invited_destination: String = "") -> Dictionary:
	if start == destination: return {"minutes": 0, "cost": 0}
	if minute<0: minute = _now()
	# Preserve time/money alternatives: the fastest intermediate path may be unaffordable later.
	var remaining: Array = [{"node": start, "minutes": 0.0, "cost": 0.0}]
	var labels := {start: [{"minutes": 0.0, "cost": 0.0}]}
	var context: Dictionary = sim.services.npc_behavior.context(npc)
	while not remaining.is_empty():
		remaining.sort_custom(func(a, b): return float(a.minutes) < float(b.minutes) if a.minutes != b.minutes else float(a.cost) < float(b.cost))
		var current: Dictionary = remaining.pop_front()
		if current.node == destination:
			var step := int(rules().decision_minutes)
			return {"minutes": maxi(int(rules().travel_minimum), int(ceil(float(current.minutes) / step)) * step), "cost": int(ceil(float(current.cost)))}
		for next in definition("locations", str(current.node)).get("routes", {}):
			var edge: Dictionary = definition("locations", str(current.node)).routes[next]
			var arrival := minute+maxi(int(rules().travel_minimum),ceili((float(current.minutes)+float(edge.get("minutes",0)))/int(rules().decision_minutes))*int(rules().decision_minutes))
			context.clock = sim.calendar.snapshot(arrival)
			if not _location_open(npc,str(next),arrival,urgent_destination and next==destination,invited_destination) or not Rules.check(context,edge.get("requirements",{})): continue
			var price := float(current.cost) + float(edge.get("cost", 0))
			if price > float(npc.money): continue
			var duration := float(current.minutes) + float(edge.get("minutes", 0))
			if not labels.has(next): labels[next] = []
			var dominated := false
			for label in labels[next]:
				if float(label.minutes) <= duration and float(label.cost) <= price: dominated = true
			if dominated: continue
			for i in range(labels[next].size() - 1, -1, -1):
				if float(labels[next][i].minutes) >= duration and float(labels[next][i].cost) >= price: labels[next].remove_at(i)
			labels[next].append({"minutes": duration, "cost": price})
			remaining.append({"node": next, "minutes": duration, "cost": price})
	return {}

func _relation(a: String, b: String) -> Dictionary:
	var ids := [a, b]
	ids.sort()
	return sim.state.social.relationships.get("%s|%s" % [ids[0], ids[1]], {})

func _partner(npc: Dictionary, action: Dictionary, action_id: String = "") -> String:
	var location := _destination(npc, action)
	var pool: Array = _by_location.get(location, [])
	var best := -INF
	var winner := ""
	if pool.is_empty(): return winner
	var start := (int(npc.id.hash()) & 0x7fffffff) % pool.size()
	for i in range(mini(pool.size(), int(rules().partner_candidates))):
		var id := str(pool[(start + i) % pool.size()])
		if id == npc.id: continue
		var other: Dictionary = sim.state.social.npcs[id]
		if not other.has("mind") or int(other.pinned_until) > _now() or not _urgent(other).is_empty(): continue
		if other.mind.active.get("phase", "") == "travel": continue
		if other.decision.get("committed", false) or _now() - int(other.mind.last_social) < 60: continue
		if not other.mind.active.is_empty() and (other.mind.active.get("phase", "") == "receiving" or not str(other.mind.active.get("partner", "")).is_empty()): continue
		var relation := _relation(str(npc.id), id)
		if float(relation.get("trust", 0)) < float(action.get("minimum_trust", -100)): continue
		if not sim.services.npc_personalities.blocked(npc, action_id, id).is_empty(): continue
		if action.get("mutual_attraction", false):
			if not sim.services.social_rules.compatibility(str(npc.id), id).data.mutual_attraction: continue
			if not sim.services.npc_personalities.blocked(npc, "court", id).is_empty(): continue
		var sentiment := _sentiment(npc, id)
		if action.get("negative_sentiment", false) and sentiment >= -5: continue
		if not action.get("negative_sentiment", false) and sentiment < -35: continue
		var affinity := float(relation.get("affinity", 0)) + sentiment
		affinity += sim.services.npc_personalities.partner_bias(npc, other, relation)
		affinity += _partner_context_bias(npc,other,action_id)
		if action.get("negative_sentiment", false): affinity = -sentiment
		if action.get("minimum_trust", 0) > 0: affinity += 100 - float(other.needs.mood)
		if affinity > best:
			best = affinity
			winner = id
	return winner

func _partner_context_bias(_npc: Dictionary, _other: Dictionary, _action: String) -> float:
	return 0.0

func evaluate(npc: Dictionary) -> Array:
	var result: Array = []
	var agenda := _agenda(npc)
	var routes := {}
	for id in sim.catalog.agency_actions:
		var spec := _action_spec(npc,str(id))
		var destination := _destination(npc, spec)
		if not routes.has(destination): routes[destination] = _route(npc, str(npc.location), destination)
		var reason := ""
		if not npc.biography.role in spec.get("roles", [npc.biography.role]): reason = "role"
		elif not sim.state.world.weather in spec.get("weather", [sim.state.world.weather]): reason = "weather"
		elif not _location_open(npc, destination): reason = "closed"
		elif routes[destination].is_empty(): reason = "unreachable"
		for skill in spec.get("requires_skill", {}):
			if int(npc.skills.get(skill, 0)) < int(spec.requires_skill[skill]): reason = "skill_prerequisite"
		for trait_id in spec.get("trait_min", {}):
			if float(npc.traits.get(trait_id, 50)) < float(spec.trait_min[trait_id]): reason = "personality"
		for trait_id in spec.get("trait_max", {}):
			if float(npc.traits.get(trait_id, 50)) > float(spec.trait_max[trait_id]): reason = "personality"
		for tag in spec.get("tags", []):
			if tag in sim.state.preferences.disabled_tags: reason = "content_disabled"
		if id == "work" and not Employment.blocked(npc,sim.catalog,sim.state.clock).is_empty(): reason = Employment.blocked(npc,sim.catalog,sim.state.clock)
		var partner := _partner(npc, spec, str(id)) if spec.get("social", false) else ""
		if spec.get("social", false) and partner.is_empty() and reason.is_empty(): reason = "no_available_partner"
		var personality_block: String = sim.services.npc_personalities.blocked(npc, str(id), partner)
		if reason.is_empty() and not personality_block.is_empty(): reason = personality_block
		if id == "visit":
			if npc.location == destination: reason = "already_present"
			elif sim.state.social.npcs.size() < 2: reason = "no_neighbors"
		var pressure := 0.0
		for need in spec.restore: pressure = maxf(pressure, 1.0 - float(npc.needs[need]) / 100.0)
		if id == "visit": pressure = maxf(pressure, 1.0 - float(npc.needs.social) / 100.0)
		var goal := 1.0 if not agenda.is_empty() and agenda[0] == id else 0.0
		var personality := 0.0
		for trait_id in spec.traits: personality += float(npc.traits.get(trait_id, 50)) / 100.0 * float(spec.traits[trait_id])
		var repetitions: int = npc.mind.recent_actions.count(id)
		var novelty: float = 1.0 / (1.0 + repetitions * 0.6)
		var feeling := 0.0
		if spec.get("social", false) and npc.mind.fears.has("rejection"): feeling -= 0.06
		if id in ["practice", "create", "publish"] and npc.mind.emotion.id in ["inspired", "confident", "grateful"]: feeling += 0.06
		if goal > 0 and npc.mind.fears.has("stagnation"): feeling += 0.06
		if id == "work" and npc.mind.fears.has("poverty"): feeling += 0.18
		if id == "dispute" and npc.mind.emotion.id in ["hurt", "angry"]: feeling += 0.18
		var archetype: float = sim.services.npc_personalities.bias(npc, str(id))
		var score := clampf(float(spec.base) + Utility.curve(pressure, "sigmoid") * 0.65 + goal * 0.30 + personality * 0.12 + novelty * 0.04 + feeling + archetype, 0, 1)
		result.append({"id": id, "score": score, "available": reason.is_empty(), "blocked": reason,
			"travel_minutes":int(routes[destination].get("minutes",0)),"travel_cost":int(routes[destination].get("cost",0)),
			"partner": partner, "destination": destination,
			"reasons": {"need": pressure, "goal": goal, "personality": personality, "archetype": archetype, "novelty": novelty, "emotion": feeling}})
	return result

func _choose(npc: Dictionary) -> void:
	var urgent := _urgent(npc)
	var commitment := _commitment(npc)
	var activity := urgent
	var reason := "urgent_need"
	var destination := ""
	var partner := ""
	var scores: Array = []
	if activity.is_empty() and not commitment.is_empty():
		activity = str(commitment.activity)
		destination = str(commitment.location)
		reason = "schedule"
	if activity.is_empty():
		var hour := int(sim.state.clock.minute_of_day) / 60
		if hour >= 22 or hour < 6:
			activity = "sleep"
			reason = "night"
	if activity.is_empty():
		scores = evaluate(npc)
		var choice := Utility.choose(scores, str(npc.activity), float(rules().hysteresis))
		activity = str(choice.get("id", "rest"))
		destination = str(choice.get("destination", npc.home))
		partner = str(choice.get("partner", ""))
		reason = "aspiration" if float(choice.get("reasons", {}).get("goal", 0)) > 0 else "needs_and_personality"
	if not sim.catalog.agency_actions.has(activity): activity = "rest"
	var spec := _action_spec(npc,activity)
	if destination.is_empty(): destination = _destination(npc, spec)
	if not _location_open(npc, destination) or _route(npc, str(npc.location), destination).is_empty():
		activity = "rest"
		destination = str(npc.home)
		partner = ""
		reason = "blocked_fallback"
	npc.mind.decision = {"action": activity, "reason": reason, "minute": _now(), "scores": scores}
	_start(npc, activity, destination, partner, reason)

func _start(npc: Dictionary, action: String, destination: String, partner: String, reason: String) -> void:
	if action == "work":
		var job := Employment.profile(npc,sim.catalog)
		if job.is_empty() or destination != Employment.location(npc,job):
			npc.decision = {"reason":"wrong_workplace","committed":false}
			return
	var route := _route(npc, str(npc.location), destination)
	if route.is_empty():
		npc.activity = "rest"
		npc.decision = {"reason": "unreachable", "committed": false}
		return
	var travel := int(route.minutes)
	if action == "work" and travel == 0 and not Employment.blocked(npc,sim.catalog,sim.state.clock).is_empty():
		npc.activity = "rest"
		npc.decision = {"reason":Employment.blocked(npc,sim.catalog,sim.state.clock),"committed":false}
		return
	if travel > 0: npc.money -= int(route.cost)
	var spec := _action_spec(npc,action)
	var phase := "travel" if travel > 0 else "action"
	var duration := travel if travel > 0 else action_minutes(npc,action)
	if travel == 0 and reason == "schedule":
		for entry in npc.schedule:
			if str(entry.get("activity", "")) != action or not sim.services.world.is_open(entry): continue
			var end := int(entry.get("hours", [0, 0])[1])
			var remaining := (end - int(sim.state.clock.minute_of_day) + 1440) % 1440
			if remaining > 0: duration = mini(duration, remaining)
			break
	npc.mind.active = {"action": action, "phase": phase, "destination": destination,
		"partner": partner, "reason": reason, "started": _now(), "due": _now() + duration}
	npc.activity = "travel" if travel > 0 else action
	npc.decision = {"reason": reason, "committed": reason in ["urgent_need", "schedule", "night"]}
	if travel == 0 and not partner.is_empty():
		var other: Dictionary = sim.state.social.npcs[partner]
		_cancel(other, "social_invitation")
		other.mind.active = {"action": action, "phase": "receiving", "destination": destination,
			"partner": str(npc.id), "reason": "social_invitation", "started": _now(), "due": _now() + duration}
		other.activity = "socialize"
		other.decision = {"reason": "social_invitation", "committed": false}
	sim.services.appearance.dress_for_context(npc)
	_log(npc, "intent", {"action": action, "phase": phase, "reason": reason, "partner": partner})

func _cancel(npc: Dictionary, reason: String) -> void:
	var active: Dictionary = npc.mind.active
	if active.is_empty(): return
	if active.get("action","")=="work" and active.get("phase","")=="action" and _now()>int(active.started):
		var worked: Dictionary = active.duplicate(true)
		worked.due = mini(_now(),int(active.due))
		_productive(npc,"work",_action_spec(npc,"work"),worked)
		_progress(npc,"work",int(worked.due)-int(worked.started))
	var other: Dictionary = sim.state.social.npcs.get(str(active.get("partner", "")), {})
	if other.has("mind") and other.mind.active.get("partner", "") == npc.id:
		other.mind.active = {}
		other.decision = {"reason": reason, "committed": false}
	npc.mind.active = {}
	npc.decision = {"reason": reason, "committed": false}
	_log(npc, "interrupted", {"action": active.action, "reason": reason})

func _finish(npc: Dictionary) -> void:
	var active: Dictionary = npc.mind.active.duplicate(true)
	var action := str(active.action)
	var spec := _action_spec(npc,action)
	if active.phase == "travel":
		npc.location = active.destination
		npc.mind.active = {}
		var partner := str(active.partner)
		if not _location_open(npc, str(active.destination)) or (spec.get("social", false) and not _partner_valid(npc, partner)):
			_log(npc, "blocked", {"action": action, "reason": "destination_changed"})
			return
		_start(npc, action, str(active.destination), partner, str(active.reason))
		return
	if npc.location != active.destination:
		_cancel(npc, "location_changed")
		return
	if not sim.services.npc_personalities.complete_solo(npc, action):
		_cancel(npc, "missing_information")
		return
	if spec.get("social", false) and not _social_outcome(npc, active):
		npc.mind.active = {}
		return
	if action=="joke" and sim.services.has("pregnancy_wellbeing"):
		sim.services.pregnancy_wellbeing.stress(str(npc.id),"laughter")
		sim.services.pregnancy_wellbeing.stress(str(active.get("partner","")),"laughter")
	if action == "eat":
		if int(npc.inventory.get("meal", 0)) > 0:
			npc.inventory.meal -= 1
			if npc.inventory.meal == 0: npc.inventory.erase("meal")
		elif float(npc.money) >= float(spec.cost): npc.money -= int(spec.cost)
		else:
			# Explicit subsistence fallback; no money is minted.
			npc.needs.satiety = minf(100, float(npc.needs.satiety) + 20)
			npc.mind.active = {}
			_log(npc, "community_meal", {})
			return
	for need in spec.restore: npc.needs[need] = clampf(float(npc.needs[need]) + float(spec.restore[need]), 0, 100)
	var productive_minutes := int(active.due) - int(active.started)
	_productive(npc,action,spec,active)
	npc.mind.completed_actions[action] = int(npc.mind.completed_actions.get(action, 0)) + 1
	npc.mind.recent_actions.append(action)
	while npc.mind.recent_actions.size() > 6: npc.mind.recent_actions.pop_front()
	_progress(npc, action, productive_minutes)
	for i in range(npc.mind.wants.size() - 1, -1, -1):
		if npc.mind.wants[i].action != action: continue
		if not action in npc.mind.fulfilled_today:
			npc.mind.satisfaction += 2
			npc.mind.fulfilled_today.append(action)
			npc.mind.fears.erase("stagnation")
		npc.mind.wants.remove_at(i)
	npc.mind.active = {}
	npc.decision = {"reason": "completed", "committed": false}
	_log(npc, "action_completed", {"action": action, "minutes": productive_minutes})

func _productive(npc: Dictionary, action: String, spec: Dictionary, active: Dictionary) -> void:
	var fraction := (int(active.due)-int(active.started)) / float(spec.minutes)
	var rank_before := Employment.rank(npc,sim.catalog)
	if spec.has("skill"):
		var skill := str(spec.skill)
		var growth := float(npc.mind.skill_remainders.get(skill, 0)) + int(spec.get("xp", 0)) * fraction
		npc.skills[skill] = int(npc.skills.get(skill, 0)) + int(floor(growth + 0.000001))
		npc.mind.skill_remainders[skill] = maxf(0.0, growth - floor(growth + 0.000001))
	var income := float(npc.mind.income_remainder) + float(spec.get("income", 0)) * fraction
	var paid := int(floor(income + 0.000001))
	npc.money += paid
	npc.mind.income_remainder = maxf(0.0, income - floor(income + 0.000001))
	if float(npc.money) >= 50: npc.mind.fears.erase("poverty")
	npc.health = minf(100, float(npc.health) + float(spec.get("health", 0)))
	if action == "work":
		Employment.settle(npc,active,paid,sim.state.clock)
		_log(npc,"work_paid",{"job":npc.mind.employment.job,"minutes":int(active.due)-int(active.started),"paid":paid})
	var rank_after := Employment.rank(npc,sim.catalog)
	if rank_after > rank_before:
		_log(npc,"career_progress",{"job":npc.mind.employment.job,"level":rank_after,"skill":Employment.profile(npc,sim.catalog).skill})

func _partner_valid(npc: Dictionary, id: String) -> bool:
	var other: Dictionary = sim.state.social.npcs.get(id, {})
	if other.is_empty() or not other.has("mind"): return false
	if not str(other.mind.active.get("partner", "")).is_empty() and other.mind.active.partner != npc.id: return false
	return other.location == npc.location and int(other.pinned_until) <= _now() and _urgent(other).is_empty() and not other.decision.get("committed", false)

func _social_outcome(npc: Dictionary, active: Dictionary) -> bool:
	var id := str(active.partner)
	var spec := definition("agency_actions", str(active.action))
	if spec.get("mutual_attraction", false) and not sim.services.social_rules.compatibility(str(npc.id), id).data.mutual_attraction:
		_cancel(npc, "incompatible_attraction")
		return false
	if not sim.services.npc_personalities.blocked(npc, str(active.action), id).is_empty():
		_cancel(npc, "context_changed")
		return false
	if not _partner_valid(npc, id):
		_cancel(npc, "partner_unavailable")
		_log(npc, "blocked", {"action": active.action, "reason": "partner_unavailable"})
		return false
	var other: Dictionary = sim.state.social.npcs[id]
	if other.mind.active.get("partner", "") != npc.id:
		_log(npc, "blocked", {"action": active.action, "reason": "partner_busy"})
		return false
	other.mind.active = {}
	if active.action == "dispute":
		sim.services.social.change_relationship(str(npc.id), id, {"affinity": -5, "trust": -4})
		_experience(npc, "conflict", id)
		_experience(other, "conflict", str(npc.id))
		npc.mind.last_social = _now()
		other.mind.last_social = _now()
		_log(npc, "conflict", {"other": id})
		return true
	var sentiment := _sentiment(npc, id)
	var chance := clampf(0.65 + float(npc.traits.sociability) * 0.002 + sentiment * 0.002, 0.15, 0.95)
	if active.action == "reconcile": chance = clampf(0.60 + float(npc.traits.loyalty) * 0.003 + sentiment * 0.002, 0.15, 0.95)
	chance = clampf(chance + sim.services.npc_personalities.social_bias(npc, other, str(active.action)), 0.05, 0.95)
	var accepted: bool = sim.rng.randf() < chance
	npc.mind.last_social = _now()
	other.mind.last_social = _now()
	if accepted:
		sim.services.npc_personalities.social_success(npc, other, str(active.action))
		sim.services.social.change_relationship(str(npc.id), id, {"affinity": 4, "trust": 5 if active.action == "support" else 3})
		_experience(npc, "friendship", id)
		_experience(other, "supported" if active.action == "support" else "friendship", str(npc.id))
		other.needs.social = minf(100, float(other.needs.social) + 25)
		npc.mind.fears.erase("rejection")
		if active.action == "reconcile":
			npc.mind.sentiments.erase(id)
			other.mind.sentiments.erase(str(npc.id))
	else:
		sim.services.npc_personalities.social_failure(npc, other, str(active.action))
		_experience(npc, "rejected", id)
		sim.services.social.change_relationship(str(npc.id), id, {"affinity": -1})
	_log(npc, "social_outcome", {"other": id, "action": active.action, "accepted": accepted})
	return accepted

func _progress(npc: Dictionary, action: String, minutes: int) -> void:
	var stage := _stage(npc)
	if stage.is_empty() or stage.action != action: return
	var aspiration: Dictionary = npc.mind.aspiration
	aspiration.progress += minutes
	npc.mind.last_progress = _now()
	npc.mind.fears.erase("stagnation")
	if int(aspiration.progress) < int(stage.minutes): return
	aspiration.progress = 0
	aspiration.stage += 1
	aspiration.milestones += 1
	npc.mind.satisfaction += 10
	aspiration.completed = int(aspiration.stage) >= definition("agency_aspirations", str(aspiration.id)).stages.size()
	if aspiration.completed: npc.mind.completed_at = _now()
	_experience(npc, "achievement")
	_log(npc, "milestone", {"goal": aspiration.id, "stage": aspiration.stage, "completed": aspiration.completed})
