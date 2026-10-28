extends RefCounted
const Fixture = preload("res://tests/mechanics/adult_health.gd")
var t

func _init(runner) -> void: t = runner

func fresh(minute: int = 600):
	var sim = Fixture.new(t).fresh()
	sim.state.npc_reproduction.enabled = false
	sim.state.clock = sim.calendar.snapshot(minute)
	sim.catalog.locations.clinic.hours = [480,1200]
	sim.state.world.location = "clinic"
	for need in sim.state.player.needs: sim.state.player.needs[need] = 100.0
	return sim

func reject(sim, module: String, operation: String, args: Dictionary, reason: String) -> void:
	var before: Dictionary = sim.export_snapshot()
	var result: Dictionary = sim.command(module,operation,args)
	t._check(not result.ok and result.get("error","")==reason and before==sim.export_snapshot(),"clinical refusal preserves state, time, funds and RNG: "+reason)

func pregnant(sim, id: String = "player") -> void:
	if id=="player": Fixture.new(t).female(sim)
	t._check(sim.command("lifecycle","start",{"id":"pregnancy","target":id}).ok,"clinical fixture has an actual active pregnancy")

func pregnant_job(sim) -> String:
	# Author a valid already-established pregnancy for the medical appointment fixture.
	var repro = sim.services.reproduction
	var id: String = repro._id("exposure_")
	var now := int(sim.state.clock.total_minutes)
	var exposure := {"id":id,"target":"female","partner":"male","session":"clinical_fixture","minute":now,"resolve_at":now+1,"chance":1.0,"roll":0.0,"emergency":false,"intended":true,"status":"pending","protection":"unprotected"}
	sim.state.reproduction.exposures[id] = exposure
	repro._conceive(exposure)
	var pregnancy: Dictionary = repro.pregnancy("female")
	pregnancy.known = true
	pregnancy.decision = "continue"
	t._check(not pregnancy.is_empty(),"NPC appointment refers to an actual reproductive pregnancy record")
	return str(pregnancy.id)

func run() -> void:
	_visit_windows()
	_prenatal_presence()
	_prenatal_completion()
	_npc_visit()
	_npc_boundary()
	_clinic_role()

func _visit_windows() -> void:
	var sim = fresh(1195)
	reject(sim,"adult_health","consult",{},"clinic_visit_window")
	sim = fresh(1170)
	var money := int(sim.state.economy.cash)
	t._check(sim.command("adult_health","consult").ok,"thirty-minute appointment may finish exactly when the service closes")
	t._check(sim.state.clock.total_minutes==1200 and sim.state.economy.cash==money-25,"valid boundary visit spends exactly thirty minutes and one fee")
	sim = fresh(1200)
	reject(sim,"adult_health","consult",{},"location_closed")
	reject(sim,"adult_health","emergency",{},"no_urgent_health_problem")
	var health = sim.services.adult_health
	health.start_erection("player",true,true)
	health.record("player").erection.started = int(sim.state.clock.total_minutes)-240
	money = int(sim.state.economy.cash)
	t._check(sim.command("adult_health","emergency").ok and sim.state.economy.cash==money,"confirmed urgent care inside clinic retains its night exception without an ordinary fee")
	t._check(not health.view().urgent,"completed emergency care has its actual clinical outcome")

func _prenatal_presence() -> void:
	var sim = fresh()
	pregnant(sim)
	sim.state.world.location = "bedroom"
	reject(sim,"health","prenatal_care",{},"clinic_required")
	sim.state.world.location = "clinic"
	var minute := int(sim.state.clock.total_minutes)
	var money := int(sim.state.economy.cash)
	t._check(sim.command("health","prenatal_care").ok,"present patient completes a valid prenatal visit")
	t._check(sim.state.clock.total_minutes==minute+30 and sim.state.economy.cash==money-30 and sim.state.conditions["player:pregnancy"].care==10,"prenatal visit grants care only after its full duration and charges once")
	reject(sim,"health","prenatal_care",{},"care_already_provided")
	sim = fresh()
	pregnant(sim,"female")
	reject(sim,"health","prenatal_care",{"target":"female"},"clinic_required")
	sim.state.social.npcs.female.location = "clinic"
	sim.state.world.location = "bedroom"
	reject(sim,"health","prenatal_care",{"target":"female"},"care_payer_not_present")
	sim.state.world.location = "clinic"
	money = int(sim.state.economy.cash)
	var npc_money := int(sim.state.social.npcs.female.money)
	t._check(sim.command("health","prenatal_care",{"target":"female"}).ok,"a present companion may pay for the actual present patient's visit")
	t._check(sim.state.economy.cash==money-30 and sim.state.social.npcs.female.money==npc_money,"the declared payer funds the visit exactly once")

func _prenatal_completion() -> void:
	var sim = fresh(1195)
	pregnant(sim)
	reject(sim,"health","prenatal_care",{},"clinic_visit_window")
	reject(sim,"pregnancy_wellbeing","checkup",{},"clinic_visit_window")
	sim = fresh(1170)
	pregnant(sim)
	t._check(sim.command("pregnancy_wellbeing","checkup").ok,"pregnancy wellbeing checkup uses the same complete clinical window")
	t._check(sim.state.clock.total_minutes==1200 and sim.state.conditions["player:pregnancy"].next_care==2640,"prenatal cooldown starts at completed care, not before the examination")
	sim = fresh(600)
	pregnant(sim)
	sim.catalog.locations.clinic.weekdays = [2]
	t._check(int(sim.state.clock.weekday)!=2,"closed weekday fixture differs from the service day")
	reject(sim,"health","prenatal_care",{},"location_closed")

func _npc_boundary() -> void:
	var sim = fresh(1170)
	sim.state.npc_reproduction.enabled = true
	var pregnancy_id := pregnant_job(sim)
	var npc: Dictionary = sim.state.social.npcs.female
	npc.location = "clinic"
	npc.pinned_until = 0
	for need in npc.needs: npc.needs[need] = 100.0
	t._check(sim.services.npc_reproduction.jobs.schedule("female","prenatal_care","clinic",30,{"pregnancy":pregnancy_id}),"NPC and player share the exact completion-at-closing boundary")
	sim.services.npc_planner.resolve()
	t._check(sim.command("clock","advance",{"minutes":30}).ok,"NPC boundary examination consumes its full time")
	t._check(sim.state.social.npcs.female.money==1970 and sim.state.conditions["female:pregnancy"].care==10,"NPC examination finishing at closing charges and completes exactly once")

func _npc_visit() -> void:
	var sim = fresh()
	sim.state.npc_reproduction.enabled = true
	var pregnancy_id := pregnant_job(sim)
	var npc: Dictionary = sim.state.social.npcs.female
	npc.pinned_until = 0
	for need in npc.needs: npc.needs[need] = 100.0
	var money := int(npc.money)
	var player_money := int(sim.state.economy.cash)
	var route: Dictionary = sim.services.npc_agency._route(npc,str(npc.location),"clinic")
	t._check(sim.services.npc_reproduction.jobs.schedule("female","prenatal_care","clinic",30,{"pregnancy":pregnancy_id}),"NPC prenatal visit reserves a real route and examination")
	sim.services.npc_planner.resolve()
	t._check(npc.location=="bedroom" and sim.state.conditions["female:pregnancy"].care==0,"booking never teleports or grants prepaid clinical results")
	var arrived: Dictionary = sim.command("clock","advance",{"minutes":int(route.minutes)})
	t._check(arrived.ok,"NPC actually arrives before examination")
	reject(sim,"health","prenatal_care",{"target":"female"},"clinical_visit_in_progress")
	t._check(sim.command("clock","advance",{"minutes":30}).ok,"shared time completes the NPC's actual prenatal visit")
	t._check(sim.state.social.npcs.female.location=="clinic" and sim.state.social.npcs.female.money==money-int(route.cost)-30 and sim.state.conditions["female:pregnancy"].care==10,"completed NPC visit uses its own funds and actual presence")
	t._check(sim.state.economy.cash==player_money and sim.state.npc_reproduction.jobs.is_empty(),"NPC completion does not spend player funds or leave a repeated job")

func _clinic_role() -> void:
	var sim = fresh()
	sim.catalog.locations.care_suite = sim.catalog.locations.clinic.duplicate(true)
	sim.catalog.location_roles.clinic = "care_suite"
	reject(sim,"adult_health","consult",{},"clinic_required")
	sim.state.world.location = "care_suite"
	t._check(sim.command("adult_health","consult").ok,"clinical action uses the location declared by the catalog role")
	pregnant(sim)
	t._check(sim.command("health","prenatal_care").ok,"prenatal care uses that same declared clinical location")
