extends "res://scripts/mechanics/institutions.gd"
## Members make their own choices; the player convenes the vote.
func execute(operation: String, args: Dictionary) -> Dictionary:
	if operation == "hold_vote": return _hold_vote(str(args.get("id", "")))
	if operation == "vote": return Rules.fail("npc_ballot_private")
	if operation == "resolve_election":
		var group: Dictionary = sim.state.organizations.get(str(args.get("id", "")), {})
		if not group.is_empty() and not group.election.is_empty() and group.election.status == "active" and group.election.votes.size() < group.members.size(): return Rules.fail("voting_incomplete")
	return super.execute(operation, args)

func _available(npc: Dictionary) -> bool:
	return float(npc.health) > 10.0 and not str(npc.activity) in ["sleep", "recover", "eat"] and not npc.decision.get("committed", false)

func _hold_vote(id: String) -> Dictionary:
	var group: Dictionary = sim.state.organizations.get(id, {})
	if group.is_empty(): return Rules.fail("unknown_organization")
	if group.election.is_empty() or group.election.status != "active": return Rules.fail("no_active_election")
	var available := false
	for voter in group.members:
		if not group.election.votes.has(voter) and _available(sim.state.social.npcs[voter]): available = true
	if not available: return Rules.fail("voters_busy")
	var elapsed: Dictionary = sim.advance(30)
	if not elapsed.ok: return elapsed
	var voters: Array = group.members.keys()
	voters.sort()
	var candidates: Array = group.election.candidates.duplicate()
	candidates.sort()
	var cast := 0
	for voter in voters:
		if group.election.votes.has(voter) or not _available(sim.state.social.npcs[voter]): continue
		var best := ""
		var best_score := -INF
		for candidate in candidates:
			var person: Dictionary = sim.state.social.npcs[candidate]
			var bond: Dictionary = sim.services.npc_relationships.view(str(voter), str(candidate))
			var score := float(bond.respect) * 0.4 + float(bond.trust) * 0.3 + float(bond.affection) * 0.1
			score += float(person.stats.charisma) + float(person.traits.responsibility) * 0.08
			if group.policies.focus == "research": score += float(person.stats.intellect)
			elif group.policies.focus == "publicity": score += float(person.stats.authority)
			elif group.policies.focus == "festival": score += float(person.skills.get("journalism", 0)) * 0.05
			if voter == candidate: score += float(person.traits.bravery) * 0.04
			score += sim.rng.randf_range(-3.0, 3.0)
			if score > best_score: best_score = score; best = str(candidate)
		var voted := super.execute("vote", {"id":id, "npc":str(voter), "candidate":best})
		if not voted.ok: return voted
		cast += 1
	if group.election.votes.size() == group.members.size():
		var resolved := super.execute("resolve_election", {"id":id})
		if not resolved.ok: return resolved
	return Rules.ok({"cast":cast, "pending":group.members.size() - group.election.votes.size(), "winner":str(group.election.winner)})

func productivity(group: Dictionary, npc_id: String) -> float:
	var npc: Dictionary = sim.state.social.npcs[npc_id]
	if float(npc.health) <= 10.0: return 0.0
	var wellbeing := minf(float(npc.needs.energy), float(npc.needs.satiety))
	return super.productivity(group, npc_id) * clampf(wellbeing / 40.0, 0.25, 1.0)
