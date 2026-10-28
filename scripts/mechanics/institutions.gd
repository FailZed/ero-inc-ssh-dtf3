extends "res://scripts/mechanics/core/module.gd"
const ClubWork = preload("res://scripts/mechanics/club_work.gd")
var attendance

func _init(simulation) -> void:
	super(simulation)
	attendance = ClubWork.new(simulation)

func initialize_group(group: Dictionary) -> void:
	group.policies = {"focus": "balanced", "wage": 0}
	group.morale = 100.0
	group.authority = 10.0
	group.equipment = []
	group.campaigns = {}
	group.election = {}
	group.work = ClubWork.defaults()

func execute(operation: String, args: Dictionary) -> Dictionary:
	var id := str(args.get("id", ""))
	if not sim.state.organizations.has(id): return Rules.fail("unknown_organization")
	var group: Dictionary = sim.state.organizations[id]
	if operation == "inspect": return Rules.ok(group.work.duplicate(true))
	if operation == "schedule":
		var hour: Variant = args.get("hour",18)
		var days: Variant = args.get("weekdays",[1,2,3,4,5])
		var location := str(args.get("location",group.work.location))
		if not (hour is int or hour is float) or int(hour) != hour or hour < 6 or hour > 20 or not days is Array or days.is_empty() or not sim.catalog.locations.has(location): return Rules.fail("invalid_club_schedule")
		for day in days:
			if not (day is int or day is float) or int(day) != day or day < 1 or day > 7: return Rules.fail("invalid_club_schedule")
		for npc in group.work.sessions.keys(): attendance.cancel(group,str(npc),"rescheduled")
		group.work.hour = hour
		group.work.weekdays = days.duplicate()
		group.work.location = location
		return Rules.ok(group.work.duplicate(true))
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
	var group: Dictionary = sim.state.organizations[id]
	for npc in group.work.sessions.keys():
		if not group.members.has(npc): attendance.cancel(group,str(npc),"membership_changed")
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
	for id in sim.state.organizations:
		var group: Dictionary = sim.state.organizations[id]
		attendance.tick_group(str(id),group,minute)
		if minute % 1440 != 0: continue
		group.authority = clampf(float(group.authority)+(float(group.cleanliness)-50.0)*0.01,0,100)
