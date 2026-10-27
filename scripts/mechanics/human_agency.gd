extends "res://scripts/mechanics/npc_agency.gd"

func execute(operation: String, args: Dictionary) -> Dictionary:
	if operation == "enable" and not enabled(): sim.state.social.dialogue = {"serial": 0, "next_contact": 0}
	return super.execute(operation, args)

func initialize_npc(npc: Dictionary) -> void:
	if not enabled() or npc.has("mind"): return
	sim.services.npc_personalities.initialize_character(npc)
	super.initialize_npc(npc)

func _relation(a: String, b: String) -> Dictionary:
	var bond: Dictionary = sim.services.npc_relationships.view(a, b)
	return {"trust": bond.trust, "affinity": bond.affection, "attraction": bond.interest}

func _experience(npc: Dictionary, kind: String, other: String = "") -> void:
	super._experience(npc, kind, other)
	if not other.is_empty() and kind in ["betrayed", "misled", "conflict"]:
		sim.services.npc_relationships.harm(str(npc.id), other, 40 if kind == "betrayed" else (25 if kind == "misled" else 10), kind)

func record_social_experience(npc: Dictionary, kind: String, other: String) -> void:
	# The relationship service has already recorded the harm; avoid applying it twice.
	super._experience(npc, kind, other)

func observe(id: String, kind: String, data: Dictionary) -> void:
	super.observe(id, kind, data)
	if enabled() and kind == "violence": _experience(sim.state.social.npcs[id], "conflict", "player")
	if enabled() and kind == "crime":
		for other in sim.state.social.npcs.values():
			if other.id == id or other.location != sim.state.world.location or other.activity == "sleep": continue
			var concern: float = 3.0 + sim.services.npc_personalities.f(other, "fairness") * 7.0
			record_social_experience(other, "witnessed_harm", "player")
			sim.services.npc_relationships.harm(str(other.id), "player", concern, "witnessed_crime")
	if enabled() and kind in ["promise_broken", "appointment_missed"]:
		sim.services.npc_relationships.harm(id, "player", 15, kind)

func _social_outcome(npc: Dictionary, active: Dictionary) -> bool:
	var id := str(active.partner)
	var other: Dictionary = sim.state.social.npcs.get(id, {})
	if not _partner_valid(npc, id) or other.mind.active.get("partner", "") != npc.id:
		_cancel(npc, "partner_unavailable")
		return false
	var reason: String = sim.services.npc_personalities.blocked(npc, str(active.action), id)
	if not reason.is_empty():
		_cancel(npc, reason)
		return false
	other.mind.active = {}
	var result: Dictionary = sim.services.npc_relationships.resolve(str(npc.id), id, str(active.action))
	npc.mind.last_social = _now()
	other.mind.last_social = _now()
	if result.accepted and active.action != "dispute":
		_experience(npc, "friendship", id)
		_experience(other, "supported" if active.action in ["support", "cooperate"] else "friendship", str(npc.id))
		other.needs.social = minf(100, float(other.needs.social) + 20)
	elif not result.accepted:
		_experience(npc, "rejected", id)
	_log(npc, "social_outcome", {"other": id, "action": active.action, "accepted": result.accepted, "reason": result.reason})
	return bool(result.accepted)
