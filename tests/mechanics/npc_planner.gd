extends RefCounted
const Fixture = preload("res://tests/mechanics/adult_health.gd")
const Sim = preload("res://scripts/mechanics/autonomous_reproductive_simulation.gd")
var t

func _init(runner) -> void:
	t = runner

func fresh():
	var sim = Fixture.new(t).fresh()
	sim.state.npc_reproduction.enabled = false
	var npc: Dictionary = sim.state.social.npcs.male
	npc.pinned_until = 0
	npc.location = "bedroom"
	npc.activity = "rest"
	npc.schedule = []
	npc.needs.energy = 100.0
	return sim

func advance(sim, minutes: int) -> void:
	var result: Dictionary = sim.command("clock","advance",{"minutes":minutes})
	t._check(result.ok,"planner clock commits: "+str(result.get("error","")))

func birth(sim) -> Dictionary:
	sim.state.healthcare.family.append({"parent":"male","partner":"female","minute":int(sim.state.clock.total_minutes),"care":0,"status":"dependent"})
	sim.services.family.initialize()
	var member: Dictionary = sim.state.family.members.family_1
	member.needs.food = 20.0
	member.assignments.food = "male"
	return member

func run() -> void:
	_competing_requests()
	_return_travel()
	_mandatory_departure()
	_meetings_and_restore()
	_urgent_meeting()
	_night_emergency()
	_unavailable_meeting()
	_calendar_edges()
	_discarded_requests()

func _competing_requests() -> void:
	var sim = fresh()
	var member := birth(sim)
	sim.services.adult_health.record("male").soiled = true
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(sim.export_snapshot()))
	var clone = Sim.new(0,Fixture.new(t).config())
	t._check(clone.restore_snapshot(snapshot).ok,"competing-task fixture restores current world")
	var balance := int(sim.state.social.npcs.male.money)
	sim.services.adult_health.care.consider("male")
	sim.services.family._autonomy(member)
	t._check(member.task.is_empty() and sim.services.adult_health.record("male").selfcare.is_empty() and sim.state.social.npcs.male.money==balance,"submitting competing intents grants no result and spends no resources")
	sim.services.npc_planner.resolve()
	clone.services.family._autonomy(clone.state.family.members.family_1)
	clone.services.adult_health.care.consider("male")
	clone.services.npc_planner.resolve()
	t._check(not member.task.is_empty() and sim.services.adult_health.record("male").selfcare.is_empty(),"family need wins against routine personal cleanup")
	t._check(JSON.parse_string(JSON.stringify(sim.export_snapshot()))==JSON.parse_string(JSON.stringify(clone.export_snapshot())),"task winner and money are independent of producer submission order")
	t._check(sim.services.adult_health.record("male").soiled,"losing cleanup cannot silently succeed")
	t._check(sim.validate_state(sim.state).ok,"one winner leaves consistent reservations")

func _return_travel() -> void:
	var sim = fresh()
	var npc: Dictionary = sim.state.social.npcs.male
	var out: Dictionary = sim.services.npc_agency._route(npc,"bedroom","clinic")
	var back: Dictionary = sim.services.npc_agency._route(npc,"clinic","global_map")
	var total := int(out.minutes)+30
	var begin := int(sim.state.clock.minute_of_day)+total+int(back.minutes)-1
	npc.schedule = [{"activity":"study","location":"global_map","hours":[begin,begin+60],"weekdays":[int(sim.state.clock.weekday)]}]
	var before: Dictionary = sim.export_snapshot()
	var reason: String = sim.services.npc_planner.calendar.conflict("male","clinic",total)
	t._check(reason=="obligation_travel_conflict","clinic visit includes the route to the next mandatory class")
	t._check(before==sim.export_snapshot(),"calendar and route forecasts are pure")
	npc.schedule[0].hours[0] += 1
	t._check(sim.services.npc_planner.calendar.conflict("male","clinic",total).is_empty(),"exact arrival at obligation boundary is allowed")
	sim.catalog.locations.global_map.hours = [begin,begin+120]
	t._check(sim.services.npc_planner.calendar.conflict("male","clinic",total).is_empty(),"future return route uses opening hours at the future obligation")

func _mandatory_departure() -> void:
	var sim = fresh()
	var npc: Dictionary = sim.state.social.npcs.male
	var route: Dictionary = sim.services.npc_agency._route(npc,"bedroom","global_map")
	var start := int(sim.state.clock.total_minutes)+int(route.minutes)+15
	npc.schedule = [{"activity":"study","location":"global_map","hours":[start,start+60],"weekdays":[int(sim.state.clock.weekday)]}]
	sim.catalog.locations.global_map.hours = [start,start+60]
	advance(sim,15)
	t._check(npc.location=="bedroom" and npc.mind.active.get("phase","")=="travel" and npc.mind.active.get("reason","")=="schedule","NPC departs for a mandatory class before it begins")
	advance(sim,int(route.minutes))
	t._check(npc.location=="global_map" and npc.mind.active.get("action","")=="study","NPC reaches a mandatory class at its actual scheduled start")
	var before: Dictionary = sim.export_snapshot()
	var view: Dictionary = sim.services.npc_planner.execute("inspect",{"id":"male"}).data
	t._check(not view.calendar.is_empty() and before==sim.export_snapshot(),"obligation inspection exposes calendar without changing the world")
	before = sim.export_snapshot()
	sim.services.npc_agency.evaluate(npc)
	t._check(before==sim.export_snapshot(),"batched decision forecasts preserve world state and RNG")

func meeting_fixture():
	var sim = fresh()
	var due := int(sim.state.clock.total_minutes)+45
	t._check(sim.command("social","appointment",{"id":"male","minute":due,"location":"global_map"}).ok,"book a future NPC meeting")
	sim.state.world.location = "global_map"
	return sim

func _meetings_and_restore() -> void:
	var sim = meeting_fixture()
	advance(sim,30)
	var meeting: Dictionary = sim.state.social.appointments[0]
	t._check(sim.state.social.npcs.male.location=="bedroom" and meeting.get("journey",{}).get("phase","")=="travel","scheduled meeting begins a real journey without teleporting")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(sim.export_snapshot()))
	var clone = Sim.new(0,Fixture.new(t).config())
	t._check(clone.restore_snapshot(snapshot).ok,"in-flight meeting reservation survives JSON restoration")
	advance(sim,15)
	advance(clone,15)
	t._check(sim.state.social.npcs.male.location=="global_map" and sim.state.social.appointments[0].status=="met","meeting settles only after both participants actually arrive")
	t._check(not sim.state.social.appointments[0].has("journey"),"completed meeting releases its reservation once")
	t._check(JSON.parse_string(JSON.stringify(sim.export_snapshot()))==JSON.parse_string(JSON.stringify(clone.export_snapshot())),"travel, meeting, relationship effects and RNG replay identically")
	for corrupt in ["arrival","pin","location","duplicate","owner"]:
		var bad: Dictionary = snapshot.duplicate(true)
		var j: Dictionary = bad.state.social.appointments[0].journey
		match corrupt:
			"arrival": j.arrival = -1
			"pin": j.pin += 1
			"location": j.phase = "waiting"
			"duplicate": bad.state.social.appointments.append(bad.state.social.appointments[0].duplicate(true))
			"owner": bad.state.adult_health.records.male.selfcare = {"operation":"rest","args":{},"origin":"bedroom","destination":"bedroom","arrival":int(snapshot.state.clock.total_minutes),"due":int(j.pin)-1,"phase":"action","pin":int(j.pin),"previous_pin":0}
		var before: Dictionary = clone.export_snapshot()
		t._check(not clone.restore_snapshot(bad).ok and before==clone.export_snapshot(),"corrupt or conflicting meeting reservation rejects atomically: "+corrupt)

func _urgent_meeting() -> void:
	var sim = meeting_fixture()
	advance(sim,30)
	var health = sim.services.adult_health
	var bond: Dictionary = sim.services.npc_relationships.view("male","player")
	health.start_erection("male",true,true)
	health.record("male").erection.started = int(sim.state.clock.total_minutes)-240
	advance(sim,1)
	t._check(sim.state.social.appointments[0].status=="cancelled" and not sim.state.social.appointments[0].has("journey"),"urgent care cancels a known meeting reservation")
	t._check(health.record("male").selfcare.get("operation","")=="emergency","urgent care acquires its own reservation after cancellation")
	var after: Dictionary = sim.services.npc_relationships.view("male","player")
	t._check(after.trust==bond.trust and after.grievance==bond.grievance,"medical cancellation does not blame the player")
	t._check(sim.validate_state(sim.state).ok,"urgent meeting interruption leaves no conflicting owner")
	sim = fresh()
	health = sim.services.adult_health
	sim.state.social.npcs.male.pinned_until = 99999
	health.start_erection("male",true,true)
	health.record("male").erection.started = int(sim.state.clock.total_minutes)-240
	advance(sim,1)
	t._check(sim.state.social.npcs.male.pinned_until==99999 and health.record("male").selfcare.is_empty(),"planner preserves an unknown scripted reservation")

func _unavailable_meeting() -> void:
	var sim = meeting_fixture()
	sim.state.social.npcs.male.pinned_until = 99999
	var before: Dictionary = sim.services.npc_relationships.view("male","player")
	advance(sim,75)
	var meeting: Dictionary = sim.state.social.appointments[0]
	t._check(meeting.status=="missed" and meeting.get("reason","")=="npc_unavailable","NPC who cannot travel is identified as unavailable")
	t._check(sim.services.npc_relationships.view("male","player").trust==before.trust,"NPC lateness does not impose a player trust penalty")

func _night_emergency() -> void:
	var sim = fresh()
	sim.state.clock = sim.calendar.snapshot(23*60)
	sim.catalog.locations.clinic.hours = [540,1020]
	var health = sim.services.adult_health
	health.start_erection("male",true,true)
	health.record("male").erection.started = int(sim.state.clock.total_minutes)-240
	advance(sim,1)
	t._check(not sim.services.world.is_open(sim.catalog.locations.clinic) and health.record("male").selfcare.get("operation","")=="emergency","urgent route reaches a clinic outside its ordinary opening hours")
	advance(sim,90)
	t._check(not health.view("male").urgent and sim.state.social.npcs.male.location=="clinic","night emergency consumes actual travel and treatment time")

func _calendar_edges() -> void:
	var sim = fresh()
	var npc: Dictionary = sim.state.social.npcs.male
	npc.schedule = [{"activity":"study","location":"global_map","hours":[1320,120],"weekdays":[1,2,3,4,5,6,7]}]
	var windows: Array = sim.services.npc_planner.calendar.windows("male")
	t._check(windows.any(func(w): return w.start==1320 and w.end==1440) and windows.any(func(w): return w.start==1440 and w.end==1560),"calendar splits an overnight obligation across actual calendar days")
	sim.state.social.appointments.append({"npc":"male","minute":540,"location":"bedroom","status":"pending"})
	t._check(sim.services.npc_planner.calendar.conflict("male","bedroom",60).is_empty(),"task ending exactly at meeting start does not overlap it")
	t._check(sim.services.npc_planner.calendar.conflict("male","bedroom",61)=="schedule_conflict","one-minute overlap with meeting is rejected")

func _discarded_requests() -> void:
	var sim = fresh()
	sim.services.adult_health.record("male").soiled = true
	sim.services.adult_health.care.consider("male")
	var result: Dictionary = sim.command("adult_health","desire",{"intent":"invalid"})
	t._check(not result.ok,"fixture action fails before committing")
	sim.services.npc_planner.resolve()
	t._check(sim.services.adult_health.record("male").selfcare.is_empty(),"a rolled-back command cannot leave a deferred task to execute later")
