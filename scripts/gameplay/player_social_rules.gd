extends "res://scripts/mechanics/human_social_rules.gd"
## Shared leisure uses the same people, directed bonds and world clock as dialogue.

func availability(id: String, long_visit: bool = false) -> Dictionary:
	if sim.services.has("family"):
		for member in sim.state.family.members.values():
			if not member.task.is_empty() and str(member.task.caregiver) == id: return Rules.fail("npc_caring_for_family")
	return super.availability(id, long_visit)

func guest_availability(id: String) -> Dictionary:
	var npc: Dictionary = sim.state.social.npcs.get(id, {})
	if npc.is_empty(): return Rules.fail("invalid_guest")
	if npc.location != sim.state.world.location: return Rules.fail("guest_not_present")
	var reason: String = sim.services.npc_relationships.blocked("player", id, "connect")
	if not reason.is_empty(): return Rules.fail(reason)
	var available := availability(id, true)
	if not available.ok: return available
	if npc.decision.get("committed", false) or not str(npc.get("mind", {}).get("active", {}).get("partner", "")).is_empty(): return Rules.fail("npc_busy")
	if float(npc.needs.energy) < 20 or float(npc.needs.satiety) < 15: return Rules.fail("npc_needs_recovery")
	if _has_commitment(npc): return Rules.fail("guest_schedule_conflict")
	if float(sim.services.npc_relationships.view(id, "player").trust) < 10: return Rules.fail("guest_trust")
	return Rules.ok()

func _has_commitment(npc: Dictionary) -> bool:
	var now := int(sim.state.clock.total_minutes)
	for meeting in sim.state.social.appointments:
		if meeting.npc == npc.id and meeting.status == "pending" and int(meeting.minute) < now + 90 and int(meeting.minute) + 30 > now: return true
	var context: Dictionary = sim.services.npc_behavior.context(npc)
	# Look through the whole visit, including midnight and short work windows.
	for offset in range(90):
		var clock: Dictionary = sim.calendar.snapshot(now + offset)
		context.clock = clock
		for entry in npc.schedule:
			if not entry.get("mandatory", entry.get("activity", "") in ["work", "study"]): continue
			var hours: Array = entry.get("hours", [0, 0])
			if int(clock.weekday) in entry.get("weekdays", [1,2,3,4,5,6,7]) and Rules.in_window(int(clock.minute_of_day), int(hours[0]), int(hours[1])) and Rules.check(context, entry.get("requirements", {})): return true
	return false

func _gathering(args: Dictionary) -> Dictionary:
	var guests: Array = args.get("candidates", [])
	if guests.size() < 2 or guests.size() > 6: return Rules.fail("invalid_gathering_size")
	var key := "gathering:%d" % sim.state.clock.day_index
	if sim.state.counters.has(key): return Rules.fail("gathering_daily_limit")
	var unique := {}
	for id in guests:
		if unique.has(id): return Rules.fail("invalid_guest")
		unique[id] = true
		var available := guest_availability(str(id))
		if not available.ok: return available
	if float(sim.state.player.needs.energy) < 10: return Rules.fail("insufficient_energy")
	var food: Dictionary = sim.services.inventory.change("meal", -guests.size())
	if not food.ok: return food
	sim.state.counters[key] = 1
	sim.services.character.adjust_need("energy", -10)
	var pins := {}
	for id in guests:
		var npc: Dictionary = sim.state.social.npcs[id]
		pins[id] = int(npc.pinned_until)
		sim.services.npc_agency._cancel(npc, "shared_leisure")
		npc.pinned_until = maxi(int(npc.pinned_until), int(sim.state.clock.total_minutes) + 91)
		npc.activity = "socialize"
	var elapsed: Dictionary = sim.advance(90)
	if not elapsed.ok: return elapsed
	for id in guests:
		var npc: Dictionary = sim.state.social.npcs[id]
		npc.pinned_until = int(pins[id])
		npc.needs.satiety = minf(100, float(npc.needs.satiety) + 35)
		npc.needs.social = minf(100, float(npc.needs.social) + 35)
		npc.needs.fun = minf(100, float(npc.needs.fun) + 20)
		sim.services.social.change_relationship(str(id), "player", {"affinity":5, "trust":2})
		sim.services.social.remember(str(id), "gathering", {"participants":guests.duplicate()})
		sim.services.npc_agency.record_social_experience(npc, "friendship", "player")
	for id in guests:
		for other in guests:
			if id != other: sim.services.social.change_relationship(str(id), str(other), {"affinity":3, "trust":1})
	sim.services.character.adjust_need("mood", 10)
	emit_event("gathering_completed", {"participants":guests.duplicate()})
	return Rules.ok({"participants":guests.duplicate()})
