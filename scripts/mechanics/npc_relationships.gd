extends "res://scripts/mechanics/core/module.gd"
## Directed bonds, bounded social memory, observable actions and mutual agreements.
const SCALES := ["trust", "affection", "respect", "comfort", "closeness", "interest", "grievance", "care_balance"]
const ACTION_ALIASES := {"talk": "connect", "listen": "support", "offer_help": "cooperate", "share_interest": "connect", "flirt": "court", "reconcile": "apologize"}

func enabled() -> bool:
	return sim.services.npc_agency.enabled()

func _now() -> int:
	return int(sim.state.clock.total_minutes)

func rules() -> Dictionary:
	return definition("human_social_rules", "simulation")

func _npc(id: String) -> Dictionary:
	return sim.state.social.npcs.get(id, {})

func _new_bond() -> Dictionary:
	return {"trust": 0.0, "affection": 0.0, "respect": 0.0, "comfort": 0.0,
		"closeness": 0.0, "interest": 0.0, "grievance": 0.0, "care_balance": 0.0,
		"acknowledged": false, "good_days": [], "consent": false,
		"last_contact": _now(), "updated_day": int(sim.state.clock.day_index),
		"gain_day": -1, "gain_used": 0.0, "recent": {}, "known_interests": {}, "known_values": {}}

func view(from: String, toward: String) -> Dictionary:
	var npc := _npc(from)
	var result: Dictionary = npc.get("mind", {}).get("bonds", {}).get(toward, _new_bond()).duplicate(true)
	result.stage = "stranger"
	if float(result.closeness) > 0: result.stage = "acquaintance"
	if float(result.affection) >= 25 and float(result.trust) >= 20 and float(result.closeness) >= 15: result.stage = "friend"
	if float(result.trust) >= 50 and float(result.closeness) >= 50: result.stage = "close_friend"
	if float(result.grievance) >= 20: result.stage = "strained"
	return result

func _bond(from: String, toward: String) -> Dictionary:
	if from == "player": return {}
	var bonds: Dictionary = _npc(from).mind.bonds
	if not bonds.has(toward):
		if bonds.size() >= int(rules().bond_limit):
			var weakest := ""
			var score := INF
			for id in bonds:
				if bonds[id].consent: continue
				var strength := float(bonds[id].closeness) + float(bonds[id].grievance)
				if strength < score:
					score = strength
					weakest = str(id)
			if weakest.is_empty(): return {}
			bonds.erase(weakest)
			_project(from, weakest)
		bonds[toward] = _new_bond()
	return bonds[toward]

func _change(bond: Dictionary, changes: Dictionary) -> void:
	if bond.is_empty(): return
	for key in changes:
		var low := -100.0 if key in ["trust", "affection", "respect", "comfort", "care_balance"] else 0.0
		bond[key] = snappedf(clampf(float(bond[key]) + float(changes[key]), low, 100), 0.001)

func common_interests(a: Dictionary, b: Dictionary) -> float:
	if not a.has("psychology") or not b.has("psychology"): return 0.0
	var best := 0.0
	for key in sim.catalog.human_interests:
		best = maxf(best, minf(float(a.psychology.interests[key]), float(b.psychology.interests[key])) / 100.0)
	return best

func value_alignment(a: Dictionary, b: Dictionary) -> float:
	if not a.has("psychology") or not b.has("psychology"): return 0.5
	var difference := 0.0
	for key in sim.catalog.human_values: difference += absf(float(a.psychology.values[key]) - float(b.psychology.values[key])) / 100.0
	return 1.0 - difference / sim.catalog.human_values.size()

func known_interests(a: Dictionary, b: Dictionary) -> float:
	var known: Dictionary = view(str(a.id), str(b.id)).known_interests
	var best := 0.0
	for key in known: best = maxf(best, minf(float(a.psychology.interests[key]), float(known[key])) / 100)
	return best

func known_alignment(a: Dictionary, b: Dictionary) -> float:
	var known: Dictionary = view(str(a.id), str(b.id)).known_values
	if known.is_empty(): return 0.5
	var difference := 0.0
	for key in known: difference += absf(float(a.psychology.values[key]) - float(known[key])) / 100
	return 1 - difference / known.size()

func _disclose(listener: Dictionary, speaker: String, field: String) -> void:
	if speaker == "player" or listener.is_empty(): return
	var source: Dictionary = _npc(speaker).psychology[field]
	var known: Dictionary = listener["known_" + field]
	var selected := ""
	var best := -1.0
	for key in source:
		if not known.has(key) and float(source[key]) > best:
			selected = str(key)
			best = float(source[key])
	if not selected.is_empty(): known[selected] = source[selected]

func blocked(actor: String, target: String, action: String) -> String:
	if actor == target or _npc(target).is_empty(): return "unknown_relationship_target"
	var npc := _npc(target)
	if not npc.has("mind"): return "npc_agency_disabled"
	if not npc.mind.boundaries.contact: return "contact_boundary"
	var spec := definition("agency_actions", action)
	for tag in spec.get("tags", []):
		if tag in sim.state.preferences.disabled_tags: return "content_disabled"
	var incoming := view(target, actor)
	if action in ["court", "invite_relationship"]:
		if not npc.mind.boundaries.romance: return "romantic_boundary"
		if "romance" in sim.state.preferences.disabled_tags: return "content_disabled"
		if actor != "player" and not _npc(actor).mind.boundaries.romance: return "romantic_boundary"
		if not sim.services.social_rules.compatibility(actor, target).data.mutual_attraction: return "incompatible_attraction"
		if float(incoming.grievance) >= 10 or float(incoming.comfort) < -10: return "unresolved_harm"
		var sender := _npc(actor)
		if sender.has("mind") and int(sender.mind.declined_until.get(target, 0)) > _now(): return "romantic_boundary"
		if int(incoming.recent.get("romantic_decline", -1440)) + 1440 > _now(): return "romantic_boundary"
	if action == "gossip" and not npc.mind.boundaries.gossip: return "gossip_boundary"
	if action == "share_values" and (float(incoming.trust) < 12 or float(incoming.comfort) < 0): return "insufficient_closeness"
	if action in ["apologize", "reconcile"] and (float(incoming.grievance) <= 0 or incoming.acknowledged): return "no_unacknowledged_harm"
	if action == "invite_relationship":
		if sim.services.social._has_partner(actor) or sim.services.social._has_partner(target): return "existing_relationship"
		var ids := [actor, target]
		ids.sort()
		var shared: Dictionary = sim.state.social.relationships.get("%s|%s" % [ids[0], ids[1]], {})
		if int(shared.get("separated_until", 0)) > _now(): return "relationship_cooldown"
		if not _ready(incoming): return "relationship_not_ready"
		if actor != "player" and not _ready(view(actor, target)): return "relationship_not_ready"
	return ""

func _ready(bond: Dictionary) -> bool:
	return float(bond.trust) >= 35 and float(bond.interest) >= 30 and float(bond.closeness) >= 30 and float(bond.grievance) < 10

func response_bias(actor: String, target: String, action: String) -> float:
	var npc := _npc(target)
	var p = sim.services.npc_personalities
	var incoming := view(target, actor)
	var result: float = (p.f(npc, "sociability") - 0.5) * 0.16
	result += float(incoming.trust) * 0.002 + float(incoming.comfort) * 0.001 - float(incoming.grievance) * 0.004
	if actor != "player": result += (known_alignment(npc, _npc(actor)) - 0.5) * 0.10
	if action == "support": result += (p.f(npc, "dependence") - 0.5) * 0.14 + (1 - float(npc.needs.mood) / 100) * 0.12
	if action == "joke": result += (p.f(npc, "liveliness") - 0.5) * 0.12
	if action == "deceive": result += (float(p.profile(npc).credulity) - 0.5) * 0.25
	if action in ["apologize", "reconcile"]: result += (p.f(npc, "forgivingness") - 0.5) * 0.18
	return clampf(result, -0.50, 0.30)

func forecast(actor: String, target: String, action: String) -> Dictionary:
	var reason := blocked(actor, target, action)
	var npc := _npc(target)
	if npc.is_empty(): return {"blocked": reason, "chance": 0.0}
	var chance := clampf(0.65 + response_bias(actor, target, action), 0.05, 0.95)
	if action in ["cooperate", "apologize", "reconcile", "dispute"]: chance = 1.0
	return {"blocked": reason, "chance": chance if reason.is_empty() else 0.0}

func _gain(bond: Dictionary, action: String, desired: float = 3.0) -> float:
	var day := int(sim.state.clock.day_index)
	if int(bond.gain_day) != day:
		bond.gain_day = day
		bond.gain_used = 0.0
	var repeated: bool = _now() - int(bond.recent.get(action, -10080)) < int(rules().repeat_minutes)
	var gain := 0.0 if repeated else minf(desired, maxf(0, float(rules().daily_gain_budget) - float(bond.gain_used)))
	bond.gain_used = snappedf(float(bond.gain_used) + gain, 0.001)
	bond.recent[action] = _now()
	return gain

func harm(victim: String, actor: String, severity: float, reason: String) -> void:
	if victim == "player" or victim == actor or (actor != "player" and _npc(actor).is_empty()): return
	var bond := _bond(victim, actor)
	_change(bond, {"trust": -severity * 0.8, "affection": -severity * 0.35, "respect": -severity * 0.45,
		"comfort": -severity * 0.7, "grievance": severity, "closeness": -severity * 0.15})
	bond.acknowledged = false
	bond.good_days = []
	bond.consent = false
	bond.last_contact = _now()
	_project(victim, actor)
	emit_event("npc_social_harm", {"victim": victim, "actor": actor, "reason": reason, "severity": severity})

func _repair(bond: Dictionary, action: String) -> bool:
	if not action in ["support", "cooperate"] or not bond.acknowledged or float(bond.grievance) <= 0: return false
	var day := int(sim.state.clock.day_index)
	if day in bond.good_days: return false
	bond.good_days.append(day)
	while bond.good_days.size() > int(rules().repair_days): bond.good_days.pop_front()
	_change(bond, {"grievance": -6, "comfort": 3})
	# Even after three reliable days the damage is not erased or trust reset.
	return true

func resolve(actor: String, target: String, action: String) -> Dictionary:
	var info := forecast(actor, target, action)
	if not str(info.blocked).is_empty(): return {"accepted": false, "reason": info.blocked}
	var accepted: bool = sim.rng.randf() < float(info.chance)
	var incoming := _bond(target, actor)
	var outgoing := _bond(actor, target)
	if action == "dispute":
		harm(target, actor, 12, "dispute")
		sim.services.npc_agency.record_social_experience(_npc(target), "conflict", actor)
		if actor != "player": harm(actor, target, 6, "conflict")
		if actor != "player": sim.services.npc_agency.record_social_experience(_npc(actor), "conflict", target)
	elif accepted:
		if action in ["apologize", "reconcile"]:
			incoming.acknowledged = true
			_change(incoming, {"comfort": 2})
		elif action == "invite_relationship":
			incoming.consent = true
			if not outgoing.is_empty(): outgoing.consent = true
			var shared: Dictionary = sim.services.social.relationship(actor, target)
			shared.status = "partner"
			emit_event("npc_relationship_formed", {"a": actor, "b": target, "mutual_agreement": true})
		else:
			var gain := _gain(incoming, action, 4.0 if action == "cooperate" else 3.0)
			var bond_gain := gain * (0.6 if float(incoming.grievance) > 0 else 1.0)
			var trust_gain := 0.0 if float(incoming.grievance) > 0 else gain * 0.5
			if action == "deceive": trust_gain = 0.0
			_change(incoming, {"affection": bond_gain, "comfort": bond_gain, "closeness": gain * 0.6, "trust": trust_gain, "respect": gain * 0.25})
			if not outgoing.is_empty():
				var reciprocated := _gain(outgoing, action, 2.0)
				_change(outgoing, {"affection": reciprocated * 0.6, "comfort": reciprocated, "closeness": reciprocated * 0.5})
			if action in ["support", "cooperate"] and gain > 0:
				_change(incoming, {"care_balance": -gain})
				_change(outgoing, {"care_balance": gain})
				if _repair(incoming, action): _change(incoming, {"trust": gain * 0.5})
			if action == "share_values" and actor != "player":
				_disclose(incoming, actor, "values")
				_disclose(outgoing, target, "values")
				var alignment := known_alignment(_npc(target), _npc(actor))
				_change(incoming, {"respect": gain * (alignment - 0.5), "closeness": gain * 0.5})
			if action in ["connect", "joke", "cooperate", "support"]:
				_disclose(incoming, actor, "interests")
				_disclose(outgoing, target, "interests")
			if action == "court":
				_change(incoming, {"interest": gain * 1.4})
				_change(outgoing, {"interest": gain * 1.2})
			if actor != "player": sim.services.npc_personalities.social_success(_npc(actor), _npc(target), action)
	else:
		# A refusal does not make the recipient dislike the initiator automatically.
		if action in ["court", "invite_relationship"]:
			incoming.recent.romantic_decline = _now()
			if actor != "player": sim.services.npc_personalities.social_failure(_npc(actor), _npc(target), "court")
	if not incoming.is_empty(): incoming.last_contact = _now()
	if not outgoing.is_empty(): outgoing.last_contact = _now()
	_project(actor, target)
	emit_event("npc_social_outcome", {"actor": actor, "target": target, "action": action, "accepted": accepted})
	return {"accepted": accepted, "chance": info.chance, "reason": "accepted" if accepted else "declined"}

func _project(a: String, b: String) -> void:
	# Shared legacy values are a conservative projection, never the source of NPC feelings.
	var first := view(a, b) if a != "player" else view(b, a)
	var second := view(b, a) if b != "player" else first
	var relation: Dictionary = sim.services.social.relationship(a, b)
	relation.trust = minf(float(first.trust), float(second.trust))
	relation.affinity = minf(float(first.affection), float(second.affection))
	relation.attraction = minf(float(first.interest), float(second.interest))
	relation.fear = maxf(0, -minf(float(first.comfort), float(second.comfort)))
	if relation.status == "partner":
		if not first.consent or not second.consent:
			relation.status = "separated"
			relation.separated_until = _now() + 10080
			emit_event("npc_relationship_separated", {"a": a, "b": b})
	elif relation.status != "separated":
		relation.status = "friend" if first.stage in ["friend", "close_friend"] and second.stage in ["friend", "close_friend"] else "acquaintance"

func legacy_change(a: String, b: String, changes: Dictionary) -> void:
	var recipient := b if a == "player" else a
	var actor := a if a == "player" else b
	var bond := _bond(recipient, actor)
	var trust := float(changes.get("trust", 0))
	var affinity := float(changes.get("affinity", 0))
	# Gifts and broad legacy rewards cannot buy back trust after harm.
	var gain := _gain(bond, "legacy", maxf(0, affinity)) if affinity > 0 or trust > 0 else 0.0
	_change(bond, {"affection": affinity if affinity < 0 else gain,
		"trust": trust if trust < 0 else (minf(trust, gain * 0.25) if float(bond.grievance) == 0 else 0.0)})
	_project(a, b)

func execute(operation: String, args: Dictionary) -> Dictionary:
	if not enabled(): return Rules.fail("npc_agency_disabled")
	var id := str(args.get("id", ""))
	var other := str(args.get("other", "player"))
	var npc := _npc(id)
	if npc.is_empty() or id == other or (other != "player" and _npc(other).is_empty()): return Rules.fail("unknown_relationship_target")
	match operation:
		"inspect": return Rules.ok({"outgoing": view(id, other), "incoming": view(other, id) if other != "player" else {}, "boundaries": npc.mind.boundaries.duplicate()})
		"boundary":
			var key := str(args.get("boundary", ""))
			if not npc.mind.boundaries.has(key) or not args.get("allowed") is bool: return Rules.fail("invalid_boundary")
			npc.mind.boundaries[key] = args.allowed
			var active_action := str(npc.mind.active.get("action", ""))
			if not args.allowed and (key == "contact" or (key == "romance" and active_action in ["court", "invite_relationship"]) or (key == "gossip" and active_action == "gossip")):
				sim.services.npc_agency._cancel(npc, "boundary_changed")
			return Rules.ok()
		"separate":
			var relation: Dictionary = sim.services.social.relationship(id, other)
			if relation.status != "partner": return Rules.fail("not_in_relationship")
			_bond(id, other).consent = false
			_project(id, other)
			return Rules.ok()
		"interact":
			if other != "player": return Rules.fail("use_npc_autonomy")
			var action := str(args.get("action", "connect"))
			action = str(ACTION_ALIASES.get(action, action))
			var spec := definition("agency_actions", action)
			if not spec.get("social", false): return Rules.fail("unknown_social_action")
			var reason := blocked("player", id, action)
			if not reason.is_empty(): return Rules.fail(reason)
			if npc.location != sim.state.world.location: return Rules.fail("npc_not_present")
			var available: Dictionary = sim.services.social_rules.availability(id, true)
			if not available.ok: return available
			if npc.mind.active.get("phase", "") == "receiving" or not str(npc.mind.active.get("partner", "")).is_empty(): return Rules.fail("npc_busy")
			sim.services.npc_agency._cancel(npc, "player_conversation")
			var pinned := int(npc.pinned_until)
			npc.pinned_until = maxi(pinned, _now() + int(spec.minutes) + 1)
			var elapsed: Dictionary = sim.advance(int(spec.minutes))
			if not elapsed.ok: return elapsed
			npc.pinned_until = pinned
			var result := resolve("player", id, action)
			npc.mind.last_social = _now()
			if result.accepted and action != "dispute":
				var experience := "supported" if action in ["support", "cooperate"] else ("romantic_interest" if action in ["court", "invite_relationship"] else "friendship")
				sim.services.npc_agency.record_social_experience(npc, experience, "player")
				npc.needs.social = minf(100, float(npc.needs.social) + 20)
			return Rules.ok(result)
	return Rules.fail("unknown_operation")

func tick(minute: int) -> void:
	if not enabled() or minute % 1440 != 0: return
	var day := int(sim.state.clock.day_index)
	for npc in sim.state.social.npcs.values():
		for id in npc.mind.bonds:
			var bond: Dictionary = npc.mind.bonds[id]
			if int(bond.updated_day) == day: continue
			bond.updated_day = day
			if minute - int(bond.last_contact) > int(rules().neglect_days) * 1440:
				var dependence: float = sim.services.npc_personalities.f(npc, "dependence")
				_change(bond, {"closeness": -(0.25 + dependence), "care_balance": -signf(float(bond.care_balance)) * minf(1, absf(float(bond.care_balance)))})
			_project(str(npc.id), str(id))
