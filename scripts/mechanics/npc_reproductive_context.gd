extends RefCounted
## Shared, read-only guards for NPC meetings and timed personal errands.
const Rules = preload("res://scripts/mechanics/core/rules.gd")

static func pair_key(a: String, b: String) -> String:
	var ids := [a,b]
	ids.sort()
	return "%s|%s" % [ids[0],ids[1]]

static func schedule_free(sim, npc: Dictionary, minutes: int) -> bool:
	if minutes < 0 or minutes > 480: return false
	var context: Dictionary = sim.services.npc_behavior.context(npc)
	var now:=int(sim.state.clock.total_minutes)
	for appointment in sim.state.social.appointments:
		if appointment.npc==npc.id and appointment.status=="pending" and int(appointment.minute)>=now and int(appointment.minute)<=now+minutes: return false
	for offset in range(minutes+1):
		context.clock = sim.calendar.snapshot(int(sim.state.clock.total_minutes)+offset)
		for entry in npc.schedule:
			if not entry.get("mandatory", entry.get("activity", "") in ["work","study"]): continue
			if not int(context.clock.weekday) in entry.get("weekdays",[1,2,3,4,5,6,7]): continue
			var hours: Array = entry.get("hours",[0,0])
			if Rules.in_window(int(context.clock.minute_of_day),int(hours[0]),int(hours[1])) and Rules.check(context,entry.get("requirements",{})): return false
	return true

static func available(sim, id: String, minutes: int, pin: int = 0, medical: bool = false) -> String:
	var npc: Dictionary = sim.state.social.npcs.get(id,{})
	var now := int(sim.state.clock.total_minutes)
	if id == "player" or npc.is_empty() or not npc.has("mind"): return "npc_agency_required"
	if int(npc.age) < 18: return "adults_only"
	if float(npc.health) < 30 or float(npc.needs.energy) < 15 or float(npc.needs.satiety) < 20: return "npc_needs_recovery"
	if int(npc.pinned_until) > now and int(npc.pinned_until) != pin: return "npc_busy"
	var active: Dictionary = npc.mind.active
	if pin == 0 and (npc.decision.get("committed",false) or not str(active.get("partner", "")).is_empty() or active.get("phase", "") == "travel"): return "npc_busy"
	var record: Dictionary = sim.state.healthcare.records.get(id,{})
	if float(record.get("intoxication",0)) >= 30 or int(record.get("unconscious_until",0)) > now: return "participant_unavailable"
	if not medical and int(sim.services.reproduction.view(id).recovery_until) > now: return "reproductive_recovery"
	if not schedule_free(sim,npc,minutes): return "schedule_conflict"
	return ""

static func pair_blocked(sim, a: String, b: String, minutes: int, pin: int = 0) -> String:
	if a == b or a == "player" or b == "player": return "invalid_npc_pair"
	if "romance" in sim.state.preferences.disabled_tags: return "content_disabled"
	for pair in [[a,b],[b,a]]:
		var health_reason: String = sim.services.adult_health.intimate_blocked(str(pair[0]))
		if not health_reason.is_empty(): return health_reason
		var reason := available(sim,str(pair[0]),minutes,pin)
		if not reason.is_empty(): return reason
		reason = str(sim.services.npc_relationships.blocked(str(pair[0]),str(pair[1]),"court"))
		if not reason.is_empty(): return reason
		var bond: Dictionary = sim.services.npc_relationships.view(str(pair[0]),str(pair[1]))
		var rules: Dictionary = sim.catalog.reproduction_rules.simulation
		if float(bond.trust) < float(rules.minimum_trust) or float(bond.comfort) < float(rules.minimum_comfort) or float(bond.interest) < float(rules.minimum_interest): return "intimacy_declined"
	var key := pair_key(a,b)
	for other_key in sim.state.social.relationships:
		if other_key == key or sim.state.social.relationships[other_key].status != "partner": continue
		var ids: PackedStringArray = str(other_key).split("|")
		if a in ids or b in ids: return "existing_relationship"
	return ""
