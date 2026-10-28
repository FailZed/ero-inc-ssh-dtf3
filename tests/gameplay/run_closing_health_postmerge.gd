extends "res://tests/gameplay/closing_health.gd"
## Postmerge acceptance extends the reviewed boundary probe with actual care completion.

func _complete_care() -> void:
	var sim = fresh()
	if sim==null: return
	urgent(sim)
	command(sim,"clock","advance",{"minutes":1})
	var job: Dictionary = sim.services.adult_health.record("worker").selfcare
	check(job.get("operation","")=="emergency","postmerge: emergency really starts")
	if not job.is_empty():
		command(sim,"clock","advance",{"minutes":int(job.due)-int(sim.state.clock.total_minutes)})
		check(not sim.services.adult_health.view("worker").urgent and sim.services.adult_health.record("worker").selfcare.is_empty(),"postmerge: urgent care actually completes and resolves the acute state")
		check(sim.state.adult_health.history.filter(func(entry): return entry.kind=="care" and entry.data.get("target","")=="worker" and entry.data.get("operation","")=="emergency").size()==1,"postmerge: emergency outcome occurs once")
		check(sim.validate_state(sim.state).ok,"postmerge: completed urgent care retains valid state")
	sim = fresh()
	if sim==null: return
	var npc: Dictionary = sim.state.social.npcs.worker
	npc.location = str(npc.home)
	command(sim,"institutions","schedule",{"id":"creative_collective","location":str(npc.home),"hour":18,"weekdays":[1,2,3,4,5,6,7]})
	sim.state.healthcare.family.append({"parent":"worker","partner":"","minute":int(sim.state.clock.total_minutes),"care":0,"status":"dependent"})
	sim.services.family.initialize()
	var member: Dictionary = sim.state.family.members.family_1
	member.needs.food = 20.0
	check(sim.services.npc_planner.submit("family","worker","feed",str(npc.location),20,65,{"member":"family_1","need":"food"}),"postmerge: actual family care submits")
	sim.services.npc_planner.resolve()
	check(member.task.get("caregiver","")=="worker","postmerge: present guardian starts feeding")
	var budget := int(sim.state.organizations.creative_collective.budget)
	command(sim,"clock","advance",{"minutes":20})
	check(member.task.is_empty() and float(member.needs.food)==75 and float(member.bonds.get("worker",0))==2,"postmerge: twenty-minute feeding actually completes after the hourly need decay")
	check(sim.state.organizations.creative_collective.work.sessions.is_empty() and int(sim.state.organizations.creative_collective.budget)==budget,"postmerge: club never takes the guardian or reserves pay during feeding")
	check(member.assignments.food=="worker" and sim.state.family.history.filter(func(entry): return entry.kind=="care" and entry.member=="family_1").size()==1,"postmerge: care result occurs once with original responsibility")
	check(sim.validate_state(sim.state).ok,"postmerge: completed family care retains valid state")

func _initialize() -> void:
	_urgent_start()
	_urgent_interrupt()
	_routine_preserved()
	_family_preserved()
	_travel_and_completion()
	_complete_care()
	print("CLOSING_HEALTH_POSTMERGE_RESULT ",JSON.stringify({"checks":checks,"failed":failures}))
	quit(1 if failures else 0)
