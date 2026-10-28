extends SceneTree
## Narrow merge boundary: optional club attendance versus existing care executors.
const Main = preload("res://scripts/gameplay/main_simulation.gd")
var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL ",label)

func command(sim, module: String, operation: String, args: Dictionary = {}) -> Dictionary:
	var result: Dictionary = sim.command(module,operation,args)
	check(result.ok,module+"/"+operation+": "+str(result.get("error","")))
	return result

func fresh():
	var sim = Main.new(2027,{"settings":{"start_minutes":2519,"start_cash":5000},"npc_templates":{"closing_worker":{"age":32,"gender":"male","home":"bedroom","money":2000,"schedule":[],"activities":[]}}})
	check(sim.configuration_error.is_empty(),"combined candidate configuration: "+sim.configuration_error)
	if not sim.configuration_error.is_empty(): return null
	command(sim,"npc_agency","enable")
	command(sim,"social","generate",{"id":"worker","template":"closing_worker"})
	var npc: Dictionary = sim.state.social.npcs.worker
	sim.services.npc_agency._cancel(npc,"closing_fixture")
	npc.pinned_until = 0
	npc.location = "clinic"
	sim.state.world.location = "clinic"
	npc.schedule = []
	npc.activity = "rest"
	for need in npc.needs: npc.needs[need] = 100.0
	var record: Dictionary = sim.services.adult_health.record("worker")
	record.vaccine.doses = 3
	record.hpv = {}
	command(sim,"social","relationship",{"id":"worker","changes":{"trust":60,"affinity":60}})
	command(sim,"organizations","create",{"id":"creative_collective"})
	command(sim,"organizations","recruit",{"id":"creative_collective","npc":"worker"})
	command(sim,"organizations","assign",{"id":"creative_collective","npc":"worker","task":"clean"})
	command(sim,"institutions","policy",{"id":"creative_collective","wage":60})
	command(sim,"institutions","schedule",{"id":"creative_collective","location":"clinic","hour":18,"weekdays":[1,2,3,4,5,6,7]})
	sim.state.organizations.creative_collective.cleanliness = 50.0
	check(sim.validate_state(sim.state).ok,"authored fixture is a valid combined domain state")
	return sim

func urgent(sim) -> void:
	var health = sim.services.adult_health
	check(health.start_erection("worker",true,true),"adult urgent physiology begins through its existing API")
	health.record("worker").erection.started = int(sim.state.clock.total_minutes)-240
	check(health.view("worker").urgent and sim.validate_state(sim.state).ok,"confirmed urgent state has a valid original clinical record")

func _urgent_start() -> void:
	var sim = fresh()
	if sim==null: return
	urgent(sim)
	var group: Dictionary = sim.state.organizations.creative_collective
	var budget := int(group.budget)
	var money := int(sim.state.social.npcs.worker.money)
	command(sim,"clock","advance",{"minutes":1})
	check(group.work.sessions.is_empty() and int(group.budget)==budget,"urgent NPC never enters or funds an optional club shift")
	check(sim.services.npc_planner.active_owner("worker").get("priority",0)==100,"urgent care receives the reservation in the same minute")
	check(int(sim.state.social.npcs.worker.money)==money,"declined club start cannot pay an unworked wage")

func _urgent_interrupt() -> void:
	var sim = fresh()
	if sim==null: return
	var group: Dictionary = sim.state.organizations.creative_collective
	var budget := int(group.budget)
	var money := int(sim.state.social.npcs.worker.money)
	command(sim,"clock","advance",{"minutes":1})
	check(group.work.sessions.has("worker"),"healthy NPC actually starts the reserved shift")
	command(sim,"clock","advance",{"minutes":7})
	check(int(group.work.sessions.get("worker",{}).get("worked",-1))==7,"seven attended minutes are recorded before illness")
	var cleanliness := float(group.cleanliness)
	urgent(sim)
	command(sim,"clock","advance",{"minutes":1})
	check(group.work.sessions.is_empty(),"new urgent physiology interrupts the existing club shift immediately")
	check(group.work.history.size()==1 and int(group.work.history[0].worked)==7 and int(group.work.history[0].paid)==7,"interruption pays only seven real minutes once")
	check(int(group.budget)==budget-7 and int(sim.state.social.npcs.worker.money)==money+7,"unused wage reservation is refunded")
	check(float(group.cleanliness)==cleanliness,"urgent minute grants no additional production")
	check(sim.services.npc_planner.active_owner("worker").get("priority",0)==100,"interruption releases the club pin for urgent care that same minute")
	var pin := int(sim.state.social.npcs.worker.pinned_until)
	sim.services.institutions.attendance.cancel(group,"worker","rescheduled")
	check(int(sim.state.social.npcs.worker.pinned_until)==pin and group.work.history.size()==1,"late club cancellation cannot release the new medical reservation or pay twice")
	check(sim.validate_state(sim.state).ok,"urgent interruption leaves valid combined state")

func _routine_preserved() -> void:
	var sim = fresh()
	if sim==null: return
	check(sim.services.npc_planner.submit("adult_health","worker","consult","clinic",30,60),"ordinary care submits through the real planner")
	sim.services.npc_planner.resolve()
	check(sim.services.npc_planner.active_owner("worker").get("owner","")=="adult_health","ordinary care owns the NPC before club hours")
	var pin := int(sim.state.social.npcs.worker.pinned_until)
	command(sim,"clock","advance",{"minutes":1})
	var group: Dictionary = sim.state.organizations.creative_collective
	check(group.work.sessions.is_empty() and int(sim.state.social.npcs.worker.pinned_until)==pin,"club entry preserves an actual existing medical task and its pin")
	sim.services.institutions.attendance.cancel(group,"worker","rescheduled")
	check(sim.services.npc_planner.active_owner("worker").get("owner","")=="adult_health" and int(sim.state.social.npcs.worker.pinned_until)==pin,"club cancellation does not cancel another executor")

func _family_preserved() -> void:
	var sim = fresh()
	if sim==null: return
	var npc: Dictionary = sim.state.social.npcs.worker
	npc.location = str(npc.home)
	command(sim,"institutions","schedule",{"id":"creative_collective","location":str(npc.home),"hour":18,"weekdays":[1,2,3,4,5,6,7]})
	sim.state.healthcare.family.append({"parent":"worker","partner":"","minute":int(sim.state.clock.total_minutes),"care":0,"status":"dependent"})
	sim.services.family.initialize()
	var member: Dictionary = sim.state.family.members.family_1
	member.needs.food = 20.0
	check(sim.services.npc_planner.submit("family","worker","feed",str(npc.location),20,65,{"member":"family_1","need":"food"}),"family feeding submits an existing real household task")
	sim.services.npc_planner.resolve()
	check(member.task.get("caregiver","")=="worker","present actual guardian owns the care task")
	var pin := int(npc.pinned_until)
	command(sim,"clock","advance",{"minutes":1})
	check(sim.state.organizations.creative_collective.work.sessions.is_empty() and member.task.get("caregiver","")=="worker" and int(npc.pinned_until)==pin,"optional club entry preserves family care and its pin")
	check(float(member.needs.food)<=20 and float(member.bonds.get("worker",0))==0 and not member.recent.has("feed"),"blocking the club does not complete care early")
	check(sim.validate_state(sim.state).ok,"family boundary retains a valid combined state")

func _travel_and_completion() -> void:
	var sim = fresh()
	if sim==null: return
	var npc: Dictionary = sim.state.social.npcs.worker
	npc.location = sim.location_role("study")
	var group: Dictionary = sim.state.organizations.creative_collective
	command(sim,"clock","advance",{"minutes":1})
	check(group.work.sessions.get("worker",{}).get("phase","")=="travel","club reserves a real nonzero city journey")
	var origin := str(npc.location)
	urgent(sim)
	command(sim,"clock","advance",{"minutes":1})
	check(group.work.sessions.is_empty() and group.work.history.size()==1 and group.work.history[0].worked==0 and group.work.history[0].paid==0,"urgent travel cancellation grants neither attendance nor pay")
	check(npc.location==origin and sim.services.npc_planner.active_owner("worker").get("priority",0)==100,"urgent travel interruption retains the actual origin and begins medical travel")
	sim = fresh()
	if sim==null: return
	group = sim.state.organizations.creative_collective
	var money := int(sim.state.social.npcs.worker.money)
	command(sim,"clock","advance",{"minutes":60})
	check(int(group.work.sessions.get("worker",{}).get("worked",-1))==59,"last-minute boundary has fifty-nine attended minutes")
	urgent(sim)
	command(sim,"clock","advance",{"minutes":1})
	check(group.work.sessions.is_empty() and group.work.history.size()==1 and group.work.history[0].reason=="care_priority" and group.work.history[0].worked==59 and group.work.history[0].paid==59,"illness before the final minute prevents false completed-shift credit")
	check(int(sim.state.social.npcs.worker.money)==money+59 and sim.services.npc_planner.active_owner("worker").get("priority",0)==100,"final-minute interruption settles partial wage and releases medical reservation")
	sim = fresh()
	if sim==null: return
	group = sim.state.organizations.creative_collective
	money = int(sim.state.social.npcs.worker.money)
	command(sim,"clock","advance",{"minutes":61})
	check(group.work.history.size()==1 and group.work.history[0].reason=="completed" and group.work.history[0].worked==60 and group.work.history[0].paid==60,"healthy control still completes one actual shift")
	check(int(sim.state.social.npcs.worker.money)==money+60 and sim.validate_state(sim.state).ok,"healthy completed shift pays once and retains valid state")

func _initialize() -> void:
	_urgent_start()
	_urgent_interrupt()
	_routine_preserved()
	_family_preserved()
	_travel_and_completion()
	print("CLOSING_HEALTH_RESULT ",JSON.stringify({"checks":checks,"failed":failures}))
	quit(1 if failures else 0)
