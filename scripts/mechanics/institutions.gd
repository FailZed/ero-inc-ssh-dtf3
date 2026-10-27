extends "res://scripts/mechanics/core/module.gd"

func initialize_group(group: Dictionary) -> void:
	group.policies = {"focus": "balanced", "wage": 0}
	group.morale = 100.0
	group.authority = 10.0
	group.equipment = []
	group.campaigns = {}
	group.election = {}

func execute(operation: String, args: Dictionary) -> Dictionary:
	var id := str(args.get("id", ""))
	if not sim.state.organizations.has(id): return Rules.fail("unknown_organization")
	var group: Dictionary = sim.state.organizations[id]
	match operation:
		"policy":
			var focus := str(args.get("focus", "balanced"))
			var wage := int(args.get("wage", 0))
			if not focus in ["balanced", "research", "publicity", "festival"] or wage < 0 or wage > 100: return Rules.fail("invalid_policy")
			group.policies = {"focus": focus, "wage": wage}
		"install":
			var item := str(args.get("item", ""))
			if not definition("items", item).has("equipment") or item in group.equipment: return Rules.fail("invalid_club_equipment")
			var removed: Dictionary = sim.services.inventory.change(item, -1)
			if not removed.ok: return removed
			group.equipment.append(item)
		"campaign":
			var campaign_id := str(args.get("campaign", ""))
			var campaign := definition("campaigns", campaign_id)
			if campaign.is_empty() or group.campaigns.has(campaign_id): return Rules.fail("campaign_unavailable")
			if group.budget < int(campaign.get("cost", 0)): return Rules.fail("organization_funds")
			group.budget -= int(campaign.get("cost", 0))
			group.campaigns[campaign_id] = {"stage": 0, "progress": 0.0, "status": "active", "claimed": false}
		"claim_campaign":
			var campaign_id := str(args.get("campaign", ""))
			if not group.campaigns.has(campaign_id): return Rules.fail("unknown_campaign")
			var progress: Dictionary = group.campaigns[campaign_id]
			if progress.status != "completed" or progress.claimed: return Rules.fail("campaign_reward_unavailable")
			var spec := definition("campaigns", campaign_id)
			group.budget += int(spec.get("reward", 0))
			group.reputation += float(spec.get("reputation", 0))
			progress.claimed = true
		"election":
			if not group.election.is_empty() and group.election.status == "active": return Rules.fail("election_active")
			var candidates: Array = args.get("candidates", [])
			if candidates.size() < 2: return Rules.fail("insufficient_candidates")
			var unique := {}
			for candidate in candidates:
				if not candidate is String or not group.members.has(candidate) or unique.has(candidate): return Rules.fail("invalid_candidate")
				unique[candidate] = true
			group.election = {"candidates": candidates.duplicate(), "votes": {}, "status": "active", "winner": ""}
		"vote":
			var voter := str(args.get("npc", ""))
			var candidate := str(args.get("candidate", ""))
			if group.election.is_empty() or group.election.status != "active": return Rules.fail("no_active_election")
			if not group.members.has(voter) or not candidate in group.election.candidates: return Rules.fail("invalid_vote")
			if group.election.votes.has(voter): return Rules.fail("already_voted")
			group.election.votes[voter] = candidate
		"resolve_election":
			if group.election.is_empty() or group.election.status != "active": return Rules.fail("no_active_election")
			var totals := {}
			for candidate in group.election.candidates: totals[candidate] = 0
			for vote in group.election.votes.values(): totals[vote] += 1
			var ordered: Array = group.election.candidates.duplicate()
			ordered.sort()
			var winner := str(ordered[0])
			for candidate in ordered:
				if int(totals[candidate]) > int(totals[winner]): winner = str(candidate)
			group.election.winner = winner
			group.election.status = "completed"
			for member in group.members: group.members[member].role = "leader" if member == winner else "member"
			emit_event("club_election_finished", {"id": id, "winner": winner})
		_: return Rules.fail("unknown_operation")
	return Rules.ok()

func roster_changed(id: String) -> void:
	var election: Dictionary = sim.state.organizations[id].election
	if not election.is_empty() and election.status == "active":
		election.status = "cancelled"
		emit_event("club_election_cancelled", {"id": id, "reason": "membership_changed"})

func productivity(group: Dictionary, npc_id: String) -> float:
	var npc: Dictionary = sim.state.social.npcs[npc_id]
	if npc.health <= 0: return 0.0
	var result := clampf(float(group.get("morale", 100)) / 100.0, 0.1, 1.2)
	result *= 1.0 + group.get("equipment", []).size() * 0.1
	result *= clampf(float(npc.traits.get("responsibility", 50)) / 100.0 + 0.5, 0.5, 1.5)
	return result

func tick(minute: int) -> void:
	if minute % 1440 != 0: return
	for id in sim.state.organizations:
		var group: Dictionary = sim.state.organizations[id]
		var wages: int = int(group.policies.wage) * group.members.size()
		if group.budget >= wages:
			group.budget -= wages
			for npc in group.members: sim.state.social.npcs[npc].money += int(group.policies.wage)
			group.morale = minf(100.0, float(group.morale) + 1.0)
		else:
			group.morale = maxf(0.0, float(group.morale) - 15.0)
			emit_event("club_wages_unpaid", {"id": id, "required": wages})
		group.authority = clampf(float(group.authority) + (float(group.cleanliness) - 50.0) * 0.01, 0.0, 100.0)
		for campaign_id in group.campaigns:
			var progress: Dictionary = group.campaigns[campaign_id]
			if progress.status != "active": continue
			var campaign := definition("campaigns", campaign_id)
			var stages: Array = campaign.get("stages", [])
			var effort := 0.0
			for npc in group.members:
				if group.members[npc].task != "idle": effort += productivity(group, str(npc))
			if group.policies.focus == campaign.get("focus", "festival"): effort *= 1.25
			progress.progress += effort
			while int(progress.stage) < stages.size() and float(progress.progress) >= float(stages[int(progress.stage)].effort):
				progress.progress -= float(stages[int(progress.stage)].effort)
				progress.stage += 1
				emit_event("club_campaign_stage", {"id": id, "campaign": campaign_id, "stage": progress.stage})
			if int(progress.stage) >= stages.size(): progress.status = "completed"
