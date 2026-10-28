extends RefCounted
const Fixture = preload("res://tests/mechanics/adult_health.gd")
const Sim = preload("res://scripts/mechanics/autonomous_reproductive_simulation.gd")
var t

func _init(runner) -> void:
	t = runner

func fresh():
	var sim = Fixture.new(t).fresh()
	sim.state.npc_reproduction.enabled = false
	for id in ["male","female"]:
		for partner in ["player","female" if id=="male" else "male"]:
			var bond: Dictionary = sim.services.npc_relationships._bond(id,partner)
			bond.merge({"trust":75.0,"comfort":65.0,"interest":70.0,"closeness":60.0},true)
		var npc: Dictionary = sim.state.social.npcs[id]
		npc.needs.energy = 100.0
		npc.needs.mood = 100.0
		sim.services.adult_health.record(id).desire.intent = "want_intimacy"
	sim.services.adult_health.synchronize()
	return sim

func run() -> void:
	_directed_desire()
	_setback_and_support()
	_npc_support_action()
	_clinic_guards()
	_urgent_priorities()
	_anatomy()
	_long_run()

func _directed_desire() -> void:
	var sim = fresh()
	var relations = sim.services.adult_health.relationships
	var close: Dictionary = relations.desire_for("male","female")
	var bond: Dictionary = sim.services.npc_relationships._bond("male","player")
	bond.merge({"trust":20.0,"comfort":20.0,"interest":20.0,"affection":90.0},true)
	var weak: Dictionary = relations.desire_for("male","player")
	t._check(close.libido==weak.libido and close.score>weak.score,"one libido yields different wishes toward different partners")
	t._check(weak.affection==90 and weak.attraction==20,"affection and attraction remain separate considerations")
	var before: Dictionary = sim.export_snapshot()
	for index in range(20): relations.desire_for("male","female"); sim.services.adult_health.readiness("male","female")
	t._check(before==sim.export_snapshot(),"partner desire and readiness queries consume neither state nor RNG")
	sim.services.adult_health.record("male").desire.intent = "not_now"
	t._check(sim.services.adult_health.intimate_blocked("male","female")=="adult_health_no_desire","explicit refusal overrides high partner desire")
	t._check(sim.services.adult_health.relationships.desire_for("player","male").get("affection")==null,"NPC affection never invents player feelings")
	sim.services.adult_health.record("female").symptoms.urinary_burning = 90
	t._check(relations.distress("female","male")==0,"AI support scoring cannot read undisclosed private symptoms")

func force_failure(sim) -> void:
	var health = sim.services.adult_health
	health.record("male").erection.difficulty_until = int(sim.state.clock.total_minutes)+180
	t._check(not health.try_intimacy("male","female"),"fixture physiological difficulty interrupts a wanted encounter")

func _setback_and_support() -> void:
	var sim = fresh()
	var health = sim.services.adult_health
	var before: Dictionary = sim.services.npc_relationships.view("male","female")
	force_failure(sim)
	t._check(before==sim.services.npc_relationships.view("male","female"),"physiological failure creates no blame, grievance or lost trust")
	t._check(sim.state.social.npcs.male.mind.moodlets.any(func(m): return m.key=="health_setback:female"),"setback persists in NPC emotional memory")
	var worry: float = health.relationships.worry("male","female")
	t._check(worry>0 and health.relationships.worry("male","player")==0,"remembered anxiety concerns the actual partner")
	t._check(health.conversation_line("male",true,"female").symptom=="remembered_setback","private conversation acknowledges remembered setback")
	t._check(health.conversation_line("male",false,"female").get("symptom","")!="remembered_setback","public remarks do not disclose a private failure")
	health.record("male").desire.frustration = 30.0
	health.relationships.support("player","male")
	t._check(health.relationships.worry("male","female")==worry,"third-party support cannot rewrite the partner-specific experience")
	var mood := float(sim.state.social.npcs.male.needs.mood)
	var effort := float(sim.state.social.npcs.female.needs.energy)
	var frustration := float(health.record("male").desire.frustration)
	sim.services.npc_relationships.resolve("female","male","cooperate")
	t._check(health.relationships.worry("male","female")==0,"accepted support from actual partner restores confidence")
	t._check(health.record("male").desire.frustration<frustration and sim.state.social.npcs.male.needs.mood>=mood,"NPC support relieves frustration and mood")
	t._check(sim.state.social.npcs.female.needs.energy==effort-2,"support spends the helper's own energy")
	var snapshot: Dictionary = sim.export_snapshot()
	health.relationships.support("female","male")
	t._check(snapshot==sim.export_snapshot(),"repeated immediate support cannot farm health benefits")
	t._check(sim.validate_state(sim.state).ok,"emotional memories remain valid snapshot state")
	var clone = Sim.new(0,Fixture.new(t).config())
	t._check(clone.restore_snapshot(JSON.parse_string(JSON.stringify(snapshot))).ok,"partner-specific memory survives current-schema JSON restore")
	t._check(clone.services.adult_health.relationships.desire_for("male","female")==health.relationships.desire_for("male","female"),"restored confidence yields the same directed desire")
	for corrupt in ["partner","time","loss"]:
		var bad: Dictionary = snapshot.duplicate(true)
		var memory: Dictionary = bad.state.social.npcs.male.memories.filter(func(m): return m.kind=="health_setback")[0]
		match corrupt:
			"partner": memory.data.partner = "unknown"
			"time": memory.minute = -1
			"loss": memory.data.mood_loss = -100
		t._check(not clone.restore_snapshot(bad).ok and JSON.parse_string(JSON.stringify(clone.export_snapshot()))==JSON.parse_string(JSON.stringify(snapshot)),"corrupt emotional memory rejects atomically: "+corrupt)

func _npc_support_action() -> void:
	var sim = fresh()
	force_failure(sim)
	for npc in sim.state.social.npcs.values(): npc.pinned_until = 0; npc.activity = "rest"
	var helper: Dictionary = sim.state.social.npcs.female
	var start := int(sim.state.clock.total_minutes)
	var before := float(sim.services.adult_health.record("male").desire.frustration)
	sim.services.npc_agency._start(helper,"cooperate","bedroom","male","health_support_test")
	var duration := int(sim.catalog.agency_actions.cooperate.minutes)
	t._check(sim.command("clock","advance",{"minutes":duration}).ok,"actual timed NPC support completes through shared clock")
	t._check(int(sim.state.clock.total_minutes)==start+duration,"autonomous support spends its full action duration")
	t._check(sim.state.social.npcs.male.memories.any(func(m): return m.kind=="health_support" and m.data.partner=="female"),"NPC-to-NPC completed support reaches health consequences")
	t._check(float(sim.services.adult_health.record("male").desire.frustration)<before,"autonomous support reduces unmet-wish frustration")
	var found := false
	for candidate in sim.services.npc_agency.inspect("female").candidates:
		if candidate.id=="support": found = candidate.reasons.has("health_support")
	t._check(found,"decision inspection explains the health-support consideration")

func _clinic_guards() -> void:
	var sim = fresh()
	sim.services.adult_health.record("player").screening.followup = true
	var before: Dictionary = sim.export_snapshot()
	var result: Dictionary = sim.command("adult_health","followup")
	t._check(not result.ok and result.error=="clinic_required" and before==sim.export_snapshot(),"follow-up outside clinic rejects without money, time or diagnosis changes")
	sim.state.world.location = "clinic"
	sim.catalog.locations.clinic.hours = [0,1]
	before = sim.export_snapshot()
	result = sim.command("adult_health","followup")
	t._check(not result.ok and result.error=="location_closed" and before==sim.export_snapshot(),"follow-up respects clinic opening hours")
	sim = fresh()
	var npc: Dictionary = sim.state.social.npcs.female
	npc.pinned_until = 0
	npc.location = "clinic"
	var health = sim.services.adult_health
	health.infections.onset("female","urinary_infection")
	health._refresh("female")
	var minute := int(sim.state.clock.minute_of_day)
	npc.schedule = [{"activity":"study","location":"global_map","hours":[minute+5,minute+65],"weekdays":[int(sim.state.clock.weekday)]}]
	health.care.consider("female")
	sim.services.npc_planner.resolve()
	t._check(health.record("female").selfcare.is_empty(),"ordinary clinic care does not overlap an imminent mandatory class")
	npc.schedule = []
	sim.catalog.locations.clinic.hours = [minute-1,minute+5]
	health.care.consider("female")
	sim.services.npc_planner.resolve()
	t._check(health.record("female").selfcare.is_empty(),"NPC avoids booking care that would finish after clinic closes")

func _urgent_priorities() -> void:
	var sim = fresh()
	var health = sim.services.adult_health
	var npc: Dictionary = sim.state.social.npcs.male
	npc.pinned_until = 0
	npc.activity = "sleep"
	t._check(health.start_erection("male",true,true),"authored urgent state starts")
	health.record("male").erection.started = int(sim.state.clock.total_minutes)-240
	health.care.consider("male")
	sim.services.npc_planner.resolve()
	t._check(health.record("male").selfcare.get("operation","")=="emergency","urgent care interrupts ordinary sleep")
	t._check(sim.command("clock","advance",{"minutes":120}).ok and not health.view("male").urgent,"NPC reaches clinic and receives real urgent care")
	sim = fresh()
	health = sim.services.adult_health
	npc = sim.state.social.npcs.male
	npc.pinned_until = 0
	npc.location = "clinic"
	health.infections.onset("male","contact_irritation")
	health.record("male").conditions.contact_irritation.severity = 80
	health._refresh("male")
	health.care.consider("male")
	sim.services.npc_planner.resolve()
	t._check(not health.record("male").selfcare.is_empty(),"routine care owns an identified reservation")
	health.start_erection("male",true,true)
	health.record("male").erection.started = int(sim.state.clock.total_minutes)-240
	health.care.consider("male")
	sim.services.npc_planner.resolve()
	t._check(health.record("male").selfcare.get("operation","")=="emergency" and sim.validate_state(sim.state).ok,"urgent care replaces routine reservation without orphan jobs")
	sim = fresh()
	health = sim.services.adult_health
	npc = sim.state.social.npcs.male
	npc.pinned_until = 0
	t._check(sim.services.npc_reproduction.jobs.schedule("male","visit_family","bedroom",60),"ordinary reproductive job reserves real NPC time")
	sim.services.npc_planner.resolve()
	health.start_erection("male",true,true)
	health.record("male").erection.started = int(sim.state.clock.total_minutes)-240
	health.care.consider("male")
	sim.services.npc_planner.resolve()
	t._check(not sim.state.npc_reproduction.jobs.has("male") and health.record("male").selfcare.get("operation","")=="emergency","urgent care releases another identified job owner before reserving time")
	sim = fresh()
	health = sim.services.adult_health
	npc = sim.state.social.npcs.male
	npc.pinned_until = 0
	sim.state.healthcare.family.append({"parent":"male","partner":"female","minute":int(sim.state.clock.total_minutes),"care":0,"status":"dependent"})
	sim.services.family.initialize()
	var member: Dictionary = sim.state.family.members.family_1
	member.needs.food = 20.0
	member.assignments.food = "male"
	sim.services.family._autonomy(member)
	sim.services.npc_planner.resolve()
	t._check(member.task.get("caregiver","")=="male","family care owns a timed reservation before emergency")
	health.start_erection("male",true,true)
	health.record("male").erection.started = int(sim.state.clock.total_minutes)-240
	health.care.consider("male")
	sim.services.npc_planner.resolve()
	t._check(member.task.is_empty() and member.needs.food==20 and health.record("male").selfcare.get("operation","")=="emergency","emergency interrupts family care without granting unperformed feeding")

func _anatomy() -> void:
	var sim = fresh()
	var health = sim.services.adult_health
	var libido := int(health.record("male").desire.libido)
	health.start_erection("male")
	t._check(health.record("male").desire.libido==libido,"ordinary involuntary reaction is not scored as illness or libido loss")
	sim.state.social.npcs.male.appearance.has_penis = false
	health.synchronize()
	var state: Dictionary = health.view("male")
	t._check(state.erection.until==0 and not state.symptoms.has("spontaneous_erection"),"capability change clears an incompatible active physiology episode")

func _long_run() -> void:
	var sim = fresh()
	force_failure(sim)
	for npc in sim.state.social.npcs.values(): npc.pinned_until = 0; npc.activity = "rest"
	var initial := int(sim.state.clock.total_minutes)
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(sim.export_snapshot()))
	var replay = Sim.new(0,Fixture.new(t).config())
	t._check(replay.restore_snapshot(snapshot).ok,"long-run branch restores emotional and health state")
	for day in range(8):
		var first: Dictionary = sim.command("clock","advance",{"minutes":1440})
		var second: Dictionary = replay.command("clock","advance",{"minutes":1440})
		t._check(first.ok and second.ok,"long-run daily health, social and clinic invariants: "+str(day+1))
	t._check(int(sim.state.clock.total_minutes)==initial+8*1440,"long-run audit advances eight actual game days")
	t._check(JSON.parse_string(JSON.stringify(sim.export_snapshot()))==JSON.parse_string(JSON.stringify(replay.export_snapshot())),"eight-day health and emotional trajectories reproduce after JSON restore")
	t._check(sim.services.adult_health.relationships.worry("male","female")==0,"old setback anxiety fades instead of becoming a permanent penalty")
	t._check(sim.state.adult_health.history.size()<=128 and sim.state.social.npcs.male.memories.size()<=int(sim.catalog.settings.memory_limit),"long-run emotional and clinical histories remain bounded")
