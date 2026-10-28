extends "res://scripts/mechanics/core/module.gd"
## Resolve a minute's competing intents once, after all domain clocks have ticked.
const Calendar = preload("res://scripts/mechanics/npc_calendar.gd")
const H = preload("res://scripts/mechanics/core/human_validation.gd")
var calendar
var _requests: Array = []

func _init(simulation) -> void:
	super(simulation)
	calendar = Calendar.new(simulation)

func now() -> int:
	return int(sim.state.clock.total_minutes)

func submit(owner: String, id: String, kind: String, destination: String, minutes: int, priority: int, payload: Dictionary = {}) -> bool:
	if not sim.state.social.npcs.has(id): return false
	var npc: Dictionary = sim.state.social.npcs[id]
	var route: Dictionary = sim.services.npc_agency._route(npc,str(npc.location),destination,-1,priority>=100)
	if route.is_empty(): return false
	var total := int(route.minutes)+minutes
	if not calendar.conflict(id,destination,total,priority,int(payload.get("appointment",-1)),int(payload.get("schedule_start",-1))).is_empty(): return false
	var finish := now()+int(route.minutes) if owner=="agency" else now()+total
	if priority<100 and not calendar.site_open(destination,now()+int(route.minutes),finish,id): return false
	_requests.append({"owner":owner,"id":id,"kind":kind,"destination":destination,"minutes":minutes,"priority":priority,
		"route":route,"origin":str(npc.location),"payload":payload.duplicate(true),"actors":[id]})
	return true

func submit_pair(a: String, b: String, action: String = "") -> bool:
	if a==b or not sim.state.social.npcs.has(a) or not sim.state.social.npcs.has(b): return false
	_requests.append({"owner":"encounter" if action.is_empty() else "social","id":a,"kind":action,"actors":[a,b],"priority":40,"payload":{"other":b}})
	return true

func clear() -> void:
	_requests.clear()

func active_owner(id: String) -> Dictionary:
	if sim.services.has("adult_health"):
		var job: Dictionary = sim.state.adult_health.records.get(id,{}).get("selfcare",{})
		if not job.is_empty(): return {"owner":"adult_health","priority":100 if job.operation=="emergency" else 60,"due":int(job.due),"destination":str(job.destination)}
	if sim.services.has("pregnancy_wellbeing"):
		var job: Dictionary = sim.state.pregnancy_wellbeing.records.get(id,{}).get("selfcare",{})
		if not job.is_empty(): return {"owner":"pregnancy","priority":65,"due":int(job.due),"destination":str(job.destination)}
	if sim.services.has("npc_reproduction"):
		var job: Dictionary = sim.state.npc_reproduction.jobs.get(id,{})
		if not job.is_empty(): return {"owner":"reproduction","priority":85 if job.kind in ["terminate","emergency"] else 75 if job.kind=="prenatal_care" else 55,"due":int(job.due),"destination":str(job.destination)}
		for session in sim.state.npc_reproduction.sessions.values():
			if id in [session.a,session.b]: return {"owner":"encounter","priority":40,"due":int(session.reserved_until)-1,"destination":str(session.venue)}
	if sim.services.has("family"):
		for member in sim.state.family.members.values():
			if member.task.get("caregiver","")==id: return {"owner":"family","priority":65,"due":int(member.task.due),"destination":str(member.home)}
	for meeting in sim.state.social.appointments:
		if meeting.npc==id and not meeting.get("journey",{}).is_empty(): return {"owner":"appointment","priority":80,"due":int(meeting.minute)+30,"destination":str(meeting.location)}
	return {}

func interrupt(id: String, reason: String) -> void:
	if sim.services.has("adult_health"): sim.services.adult_health.care.cancel(id)
	if sim.services.has("pregnancy_wellbeing"):
		var record: Dictionary = sim.state.pregnancy_wellbeing.records.get(id,{})
		if not record.get("selfcare",{}).is_empty(): sim.services.pregnancy_wellbeing.care.cancel(id,record)
	if sim.services.has("npc_reproduction"):
		var manager = sim.services.npc_reproduction
		for key in sim.state.npc_reproduction.sessions.keys():
			if id in [sim.state.npc_reproduction.sessions[key].a,sim.state.npc_reproduction.sessions[key].b]: manager.encounters.finish(str(key),"interrupted",reason)
		if sim.state.npc_reproduction.jobs.has(id): manager.jobs.finish(id,false,reason)
	if sim.services.has("family"):
		for member in sim.state.family.members.values():
			if member.task.get("caregiver","")!=id: continue
			sim.services.family._release_caregiver(member.task)
			member.task = {}
			sim.services.family._log("care_interrupted",str(member.id),{"reason":reason})
	for meeting in sim.state.social.appointments:
		if meeting.npc!=id or meeting.get("journey",{}).is_empty(): continue
		_release_meeting(meeting)
		meeting.status = "cancelled"
		meeting.reason = reason
		emit_event("appointment_cancelled",meeting)
	var npc: Dictionary = sim.state.social.npcs[id]
	if npc.has("mind"): sim.services.npc_agency._cancel(npc,reason)

func resolve(minute: int = -1) -> void:
	if minute<0: minute = now()
	_appointments()
	_commitments()
	# Known urgent physiology can interrupt another executor between decision steps.
	if sim.services.has("adult_health") and sim.services.adult_health.enabled() and sim.services.npc_agency.enabled():
		for id in sim.state.adult_health.records:
			if id=="player": continue
			var record: Dictionary = sim.state.adult_health.records[id]
			var erection: Dictionary = record.erection
			var urgent: bool = (erection.persistent and int(erection.until)>now() and now()-int(erection.started)>=int(sim.services.adult_health.config().rules.erection_urgent_minutes)) or int(record.symptoms.get("acute_pelvic_pain",0))>=80
			if urgent and active_owner(str(id)).get("priority",0)<100: sim.services.adult_health.care.consider(str(id))
	_requests.sort_custom(func(a,b):
		if a.priority!=b.priority: return int(a.priority)>int(b.priority)
		var first := str(a.owner)+":"+str(a.id)+":"+str(a.kind)
		var second := str(b.owner)+":"+str(b.id)+":"+str(b.kind)
		return first<second)
	var selected := {}
	for request in _requests:
		var occupied := false
		for id in request.actors:
			if selected.has(id): occupied = true
		if occupied: continue
		if _dispatch(request):
			for id in request.actors: selected[id] = true
	_requests.clear()
	sim.services.social.settle_appointments(minute)
	for meeting in sim.state.social.appointments:
		if meeting.status!="pending" and not meeting.get("journey",{}).is_empty(): _release_meeting(meeting)
	var agency = sim.services.npc_agency
	if not agency.enabled() or minute%int(agency.rules().decision_minutes)!=0: return
	agency._build_index()
	for id in agency._ids():
		var npc: Dictionary = sim.state.social.npcs[id]
		if npc.mind.active.is_empty() and int(npc.pinned_until)<=minute: agency._choose(npc)

func _dispatch(request: Dictionary) -> bool:
	var id := str(request.id)
	var npc: Dictionary = sim.state.social.npcs[id]
	if request.owner in ["encounter","social"]:
		var other := str(request.payload.other)
		if not active_owner(id).is_empty() or not active_owner(other).is_empty(): return false
		if request.owner=="encounter": return sim.services.npc_reproduction.encounters.start(id,other)
		if int(npc.pinned_until)>now() or int(sim.state.social.npcs[other].pinned_until)>now(): return false
		sim.services.npc_agency._start(npc,str(request.kind),str(npc.location),other,"relationship_intention")
		return true
	if npc.location!=request.origin: return false
	var owner := active_owner(id)
	if int(request.priority)>=100:
		if int(owner.get("priority",0))>=100: return false
		if owner.is_empty() and int(npc.pinned_until)>now(): return false
		interrupt(id,"adult_health_urgent_care")
	elif not owner.is_empty(): return false
	if int(npc.pinned_until)>now(): return false
	var total := int(request.route.minutes)+int(request.minutes)
	if not calendar.conflict(id,str(request.destination),total,int(request.priority),int(request.payload.get("appointment",-1)),int(request.payload.get("schedule_start",-1))).is_empty(): return false
	var success := false
	match str(request.owner):
		"adult_health": success = sim.services.adult_health.care.start(request)
		"pregnancy": success = sim.services.pregnancy_wellbeing.care.start(request)
		"reproduction": success = sim.services.npc_reproduction.jobs.start(request)
		"family": success = sim.services.family.start_care(request)
		"appointment": success = _start_meeting(request)
		"agency":
			sim.services.npc_agency._cancel(npc,"scheduled_departure")
			sim.services.npc_agency._start(npc,str(request.kind),str(request.destination),"","schedule")
			success = not npc.mind.active.is_empty()
	if success and npc.has("mind"):
		npc.mind.decision = {"action":str(request.kind),"reason":"obligation","minute":now(),"scores":[],
			"owner":str(request.owner),"priority":int(request.priority),"destination":str(request.destination),"due":now()+total}
	return success

func _commitments() -> void:
	if not sim.services.npc_agency.enabled(): return
	if now()%int(sim.services.npc_agency.rules().decision_minutes)!=0: return
	for id in sim.services.npc_agency._ids():
		var npc: Dictionary = sim.state.social.npcs[id]
		if int(npc.pinned_until)>now() or not npc.has("mind") or not active_owner(str(id)).is_empty(): continue
		if npc.mind.active.get("reason","")=="schedule": continue
		var upcoming: Array = calendar.windows(str(id))
		for window in upcoming:
			if window.kind!="schedule" or int(window.start)<=now(): continue
			var route: Dictionary = sim.services.npc_agency._route(npc,str(npc.location),str(window.location))
			if route.is_empty() or int(route.minutes)==0 or int(window.start)-now()>int(route.minutes): continue
			if not sim.services.npc_agency._urgent(npc).is_empty(): break
			submit("agency",str(id),str(window.action),str(window.location),mini(60,int(window.end)-int(window.start)),70,{"schedule_start":int(window.start)})
			break

func _appointments() -> void:
	for index in range(sim.state.social.appointments.size()):
		var meeting: Dictionary = sim.state.social.appointments[index]
		var npc: Dictionary = sim.state.social.npcs[meeting.npc]
		var journey: Dictionary = meeting.get("journey",{})
		if not journey.is_empty():
			if int(npc.pinned_until)!=int(journey.pin) or npc.location!=(journey.origin if journey.phase=="travel" else meeting.location): _release_meeting(meeting); continue
			if journey.phase=="travel" and now()>=int(journey.arrival): npc.location = meeting.location; npc.activity = "appointment"; journey.phase = "waiting"
			if meeting.status!="pending" or now()>=int(meeting.minute)+30: _release_meeting(meeting)
			continue
		if meeting.status!="pending" or int(meeting.minute)<now() or not npc.has("mind") or not sim.services.npc_agency.enabled(): continue
		var route: Dictionary = sim.services.npc_agency._route(npc,str(npc.location),str(meeting.location))
		if route.is_empty() or int(meeting.minute)-now()>int(route.minutes): continue
		submit("appointment",str(meeting.npc),"appointment",str(meeting.location),maxi(1,int(meeting.minute)+30-now()-int(route.minutes)),80,{"appointment":index})

func _start_meeting(request: Dictionary) -> bool:
	var meeting: Dictionary = sim.state.social.appointments[int(request.payload.appointment)]
	var npc: Dictionary = sim.state.social.npcs[request.id]
	if meeting.status!="pending" or int(npc.money)<int(request.route.cost): return false
	if now()+int(request.route.minutes)>int(meeting.minute): return false
	var pin := int(meeting.minute)+31
	var previous := int(npc.pinned_until)
	sim.services.npc_agency._cancel(npc,"appointment")
	npc.money -= int(request.route.cost)
	npc.pinned_until = pin
	npc.activity = "appointment_travel" if int(request.route.minutes)>0 else "appointment"
	meeting.journey = {"origin":str(npc.location),"arrival":now()+int(request.route.minutes),"pin":pin,"previous_pin":previous,"phase":"travel" if int(request.route.minutes)>0 else "waiting"}
	return true

func _release_meeting(meeting: Dictionary) -> void:
	var npc: Dictionary = sim.state.social.npcs[meeting.npc]
	var journey: Dictionary = meeting.journey
	if int(npc.pinned_until)==int(journey.pin): npc.pinned_until = int(journey.previous_pin)
	if npc.activity in ["appointment","appointment_travel"]: npc.activity = "rest"
	meeting.erase("journey")

func execute(operation: String, args: Dictionary) -> Dictionary:
	if operation!="inspect": return Rules.fail("unknown_operation")
	var id := str(args.get("id",""))
	if not sim.state.social.npcs.has(id): return Rules.fail("unknown_npc")
	return Rules.ok({"calendar":calendar.windows(id),"active":active_owner(id)})

static func state_error(state: Dictionary, catalog: Dictionary) -> String:
	var reserved := {}
	for domain in ["adult_health","pregnancy_wellbeing"]:
		var area: Variant = state.get(domain,{})
		if not area is Dictionary or not area.get("records",{}) is Dictionary: return "invalid_npc_planner_domain"
		for id in area.get("records",{}):
			var record: Variant = area.records[id]
			if not record is Dictionary or not record.get("selfcare",{}) is Dictionary: return "invalid_npc_planner_domain"
			if id!="player" and not record.get("selfcare",{}).is_empty():
				if reserved.has(id): return "conflicting_npc_obligations"
				reserved[id] = true
	var family_area: Variant = state.get("family",{})
	if not family_area is Dictionary: return "invalid_npc_planner_domain"
	var family: Variant = family_area.get("members",{})
	if not family is Dictionary: return "invalid_npc_planner_domain"
	for member in family.values():
		if not member is Dictionary or not member.get("task",{}) is Dictionary: return "invalid_npc_planner_domain"
		var caregiver := str(member.get("task",{}).get("caregiver","player"))
		if caregiver=="player": continue
		if reserved.has(caregiver): return "conflicting_npc_obligations"
		reserved[caregiver] = true
	var autonomy: Variant = state.get("npc_reproduction",{})
	if not autonomy is Dictionary: return "invalid_npc_planner_domain"
	for field in ["jobs","sessions"]:
		if not autonomy.get(field,{}) is Dictionary: return "invalid_npc_planner_domain"
		for key in autonomy.get(field,{}):
			var job: Variant = autonomy[field][key]
			if not job is Dictionary: return "invalid_npc_planner_domain"
			var ids: Array = [str(key)] if field=="jobs" else [str(job.get("a","")),str(job.get("b",""))]
			for id in ids:
				if reserved.has(id): return "conflicting_npc_obligations"
				reserved[id] = true
	for meeting in state.social.appointments:
		if not meeting.has("journey"): continue
		var j: Variant = meeting.journey
		if not j is Dictionary or not j.get("origin") is String or not catalog.locations.has(j.origin) or not j.get("phase") in ["travel","waiting"]: return "invalid_appointment_journey"
		for key in ["arrival","pin","previous_pin"]:
			if not H.integer(j.get(key),0,2147483647): return "invalid_appointment_journey"
		if int(j.pin)!=int(meeting.minute)+31 or int(state.social.npcs[meeting.npc].pinned_until)!=int(j.pin) or reserved.has(meeting.npc): return "inconsistent_appointment_reservation"
		if meeting.status!="pending" or int(j.arrival)>int(meeting.minute): return "invalid_appointment_journey"
		var npc: Dictionary = state.social.npcs[meeting.npc]
		if npc.location!=(j.origin if j.phase=="travel" else meeting.location): return "inconsistent_appointment_location"
		reserved[meeting.npc] = true
	for id in reserved:
		if not state.social.npcs.has(id): return "unknown_npc_obligation_actor"
		if not state.social.npcs[id].get("mind",{}).get("active",{}).is_empty(): return "conflicting_npc_obligations"
	return ""
