extends RefCounted
const Fixture = preload("res://tests/mechanics/adult_health.gd")
const Sim = preload("res://scripts/mechanics/autonomous_reproductive_simulation.gd")
var t

func _init(runner) -> void:
	t = runner

func fresh():
	var sim = Fixture.new(t).fresh()
	sim.state.npc_reproduction.enabled = false
	return sim

func advance_to(sim, until: int) -> void:
	while int(sim.state.clock.total_minutes)<until:
		var result: Dictionary = sim.command("clock","advance",{"minutes":mini(1440,until-int(sim.state.clock.total_minutes))})
		t._check(result.ok,"care-plan shared clock commits: "+str(result.get("error","")))
		if not result.ok: return

func start(sim, id: String = "player") -> void:
	var health = sim.services.adult_health
	health.infections.onset(id,"contact_irritation")
	if id=="player":
		sim.state.world.location = "clinic"
		t._check(sim.command("adult_health","consult").ok,"provider diagnoses condition before a course")
		t._check(sim.command("adult_health","treat",{"condition":"contact_irritation"}).ok,"provider begins a real care plan")
	else:
		sim.state.social.npcs[id].location = "clinic"
		t._check(sim.command("clock","advance",{"minutes":int(health.config().actions.consult.minutes)}).ok,"NPC consultation fixture consumes its actual interval")
		t._check(health.care.perform(id,"consult",{},false).ok,"NPC provider evaluates symptoms")
		t._check(sim.command("clock","advance",{"minutes":int(health.config().actions.treat.minutes)}).ok,"NPC prescription fixture consumes its actual interval")
		t._check(health.care.perform(id,"treat",{"condition":"contact_irritation"},false).ok,"NPC pays for its own prescribed plan")

func reject(sim, operation: String, args: Dictionary, reason: String) -> void:
	var before: Dictionary = sim.export_snapshot()
	var result: Dictionary = sim.command("adult_health",operation,args)
	t._check(not result.ok and result.get("error","")==reason and before==sim.export_snapshot(),"care refusal is atomic: "+reason)

func course(sim, id: String = "player") -> Dictionary:
	return sim.services.adult_health.record(id).conditions.contact_irritation.course

func run() -> void:
	_completed_care()
	_missed_care()
	_window_edges()
	_calendar_and_reminders()
	_npc_care_and_replay()
	_low_funds_care()
	_corrupt_state()

func _completed_care() -> void:
	var sim = fresh()
	var health = sim.services.adult_health
	start(sim)
	var plan := course(sim)
	t._check(plan.required==3 and plan.completed==1 and plan.supplies==2,"clinic course includes its first care step and finite remaining supplies")
	reject(sim,"care_step",{"condition":"contact_irritation"},"care_step_not_due")
	reject(sim,"treat",{"condition":"contact_irritation"},"treatment_in_progress")
	var before: Dictionary = sim.export_snapshot()
	health.plans.view("player")
	health.view()
	t._check(before==sim.export_snapshot(),"care calendar queries do not advance state or RNG")
	while int(course(sim).completed)<int(course(sim).required):
		advance_to(sim,int(course(sim).next_due))
		sim.state.world.location = "global_map"
		reject(sim,"care_step",{"condition":"contact_irritation"},"care_private_place_required")
		sim.state.world.location = "bedroom"
		var supplies := int(course(sim).supplies)
		var minute := int(sim.state.clock.total_minutes)
		t._check(sim.command("adult_health","care_step",{"condition":"contact_irritation"}).ok,"player performs due care at home")
		t._check(sim.state.clock.total_minutes==minute+3 and course(sim).supplies==supplies-1,"care spends its actual duration and one supply unit")
		if int(course(sim).completed)<int(course(sim).required): reject(sim,"care_step",{"condition":"contact_irritation"},"care_step_not_due")
	t._check(health.record("player").conditions.contact_irritation.status=="active","completed steps still respect minimum course duration")
	advance_to(sim,int(course(sim).finish_after)+15)
	t._check(health.record("player").conditions.contact_irritation.status=="resolved" and course(sim).review_pending,"adherent course completes and schedules observation")
	t._check(health.plans.view("player").any(func(item): return item.id=="review:contact_irritation" and item.status=="upcoming"),"personal calendar contains the actual follow-up date")

func _missed_care() -> void:
	var sim = fresh()
	var health = sim.services.adult_health
	start(sim)
	var expected := int(course(sim).finish_after)
	advance_to(sim,expected+15)
	t._check(health.record("player").conditions.contact_irritation.status=="active","elapsed time alone cannot complete an unattended course")
	t._check(course(sim).completed==1 and course(sim).supplies==2 and course(sim).missed==2,"missed care is counted without consuming unperformed supplies")
	t._check(course(sim).review_required and int(course(sim).finish_after)>expected,"repeated misses pause the plan for a provider review")
	sim.state.world.location = "bedroom"
	reject(sim,"care_step",{"condition":"contact_irritation"},"care_plan_review_required")
	reject(sim,"care_review",{"condition":"contact_irritation"},"clinic_required")
	sim.state.world.location = "clinic"
	var cash := int(sim.state.economy.cash)
	t._check(sim.command("adult_health","care_review",{"condition":"contact_irritation"}).ok,"provider reviews a disrupted plan")
	t._check(not course(sim).review_required and course(sim).missed==2 and sim.state.economy.cash==cash-15,"review resumes remaining care and retains actual miss history")
	t._check(sim.command("adult_health","care_step",{"condition":"contact_irritation"}).ok,"reviewed plan supports its next actual care action")

func _calendar_and_reminders() -> void:
	var sim = fresh()
	var health = sim.services.adult_health
	start(sim)
	advance_to(sim,int(course(sim).next_due))
	var reminders: int = sim.state.adult_health.history.filter(func(e): return e.kind=="care_reminder" and e.data.target=="player").size()
	health.plans.tick_actor("player")
	t._check(sim.state.adult_health.history.filter(func(e): return e.kind=="care_reminder" and e.data.target=="player").size()==reminders,"reminders do not repeat on every tick")
	var due := int(course(sim).next_due)
	t._check(sim.command("adult_health","snooze_care",{"id":"course:contact_irritation"}).ok and int(course(sim).next_due)==due,"snooze changes notification time without moving the actual care deadline")
	advance_to(sim,int(sim.state.clock.total_minutes)+120)
	t._check(sim.state.adult_health.history.filter(func(e): return e.kind=="care_reminder" and e.data.target=="player").size()==reminders+1,"snoozed reminder returns after two actual game hours")
	reject(sim,"snooze_care",{"id":"unknown"},"care_reminder_unavailable")
	health.infections.acquire("male","high_risk","private_fixture")
	t._check(health.plans.view("male").is_empty(),"hidden infection cannot create a disclosed calendar diagnosis")
	Fixture.new(t).female(sim)
	sim.state.world.location = "clinic"
	t._check(sim.command("adult_health","vaccinate").ok,"first actual vaccination creates its next calendar entry")
	t._check(health.plans.view("player").any(func(item): return item.id=="vaccine" and item.status=="upcoming"),"next vaccine step uses the existing real date")
	t._check(sim.command("lifecycle","start",{"id":"pregnancy","target":"player"}).ok,"pregnancy state begins for deferral fixture")
	t._check(health.plans.view("player").any(func(item): return item.id=="vaccine" and item.status=="deferred"),"calendar distinguishes medically deferred care from overdue care")

func _window_edges() -> void:
	var sim = fresh()
	start(sim)
	var health = sim.services.adult_health
	var end := int(course(sim).next_due)+int(health.plans.rules().window_minutes)
	advance_to(sim,end-3)
	sim.state.world.location = "bedroom"
	t._check(sim.command("adult_health","care_step",{"condition":"contact_irritation"}).ok,"care may finish exactly at its allowed window boundary")
	t._check(course(sim).completed==2 and course(sim).missed==0,"a care action in progress is not falsely marked missed at completion")
	end = int(course(sim).next_due)+int(health.plans.rules().window_minutes)
	advance_to(sim,end-2)
	reject(sim,"care_step",{"condition":"contact_irritation"},"care_window_closing")
	advance_to(sim,end+15)
	t._check(course(sim).missed==1 and course(sim).completed==2,"care not performed before the boundary becomes an actual missed step")
	var symptoms: Dictionary = health.record("player").symptoms
	symptoms.clear()
	symptoms["period_cramps"] = 25
	symptoms[StringName("genital_irritation")] = 25
	var ordered: Array = health.view().symptom_list
	t._check(ordered.size()==2 and str(ordered[0].id)=="genital_irritation","equal symptom severity sorts String and StringName identifiers consistently")

	# A delayed catch-up must retain the same inclusive boundary as per-minute ticks.
	sim = fresh()
	start(sim)
	health = sim.services.adult_health
	var second_boundary := int(course(sim).next_due)+int(health.plans.rules().window_minutes)+int(health.plans.rules().interval_minutes)
	sim.state.clock = sim.calendar.snapshot(second_boundary)
	health.plans.tick_actor("player")
	t._check(course(sim).missed==1 and not course(sim).review_required,"catch-up at the second inclusive window counts only the fully expired first step")
	t._check(sim.validate_state(sim.state).ok,"catch-up retains a valid course and reminder state")

func _npc_care_and_replay() -> void:
	var sim = fresh()
	start(sim,"male")
	var npc: Dictionary = sim.state.social.npcs.male
	npc.pinned_until = 0
	npc.activity = "rest"
	var cash := int(sim.state.economy.cash)
	var finish := int(course(sim,"male").finish_after)
	advance_to(sim,int(sim.state.clock.total_minutes)+1800)
	t._check(course(sim,"male").completed>=2,"NPC executes due home care through its planner without player action")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(sim.export_snapshot()))
	var clone = Sim.new(0,Fixture.new(t).config())
	t._check(clone.restore_snapshot(snapshot).ok,"unfinished NPC care and reminders survive JSON restoration")
	advance_to(sim,finish+120)
	advance_to(clone,finish+120)
	t._check(sim.services.adult_health.record("male").conditions.contact_irritation.status=="resolved","autonomous NPC completes an actually followed care plan")
	t._check(sim.state.economy.cash==cash,"NPC care never spends player money")
	t._check(JSON.parse_string(JSON.stringify(sim.export_snapshot()))==JSON.parse_string(JSON.stringify(clone.export_snapshot())),"care, supplies, clinical travel and future RNG replay identically")

func _corrupt_state() -> void:
	var sim = fresh()
	start(sim)
	var snapshot: Dictionary = sim.export_snapshot()
	for invalid in ["progress","supplies","time","review","notice","schema"]:
		var bad: Dictionary = snapshot.duplicate(true)
		var plan: Dictionary = bad.state.adult_health.records.player.conditions.contact_irritation.course
		match invalid:
			"progress": plan.completed = 99
			"supplies": plan.supplies += 1
			"time": plan.last_performed = int(bad.state.clock.total_minutes)+1
			"review": plan.review_required = true
			"notice": bad.state.adult_health.records.player.care_notices.unknown = {"last":0,"snoozed_until":0}
			"schema": bad.state.adult_health.version = 1
		t._check(not sim.restore_snapshot(bad).ok and snapshot==sim.export_snapshot(),"corrupt or obsolete care state rejects atomically: "+invalid)

func _low_funds_care() -> void:
	var sim = fresh()
	start(sim,"female")
	var health = sim.services.adult_health
	var npc: Dictionary = sim.state.social.npcs.female
	var record: Dictionary = health.record("female")
	sim.state.clock = sim.calendar.snapshot(int(record.conditions.contact_irritation.course.next_due))
	npc.money = 0
	npc.pinned_until = 0
	npc.activity = "rest"
	record.screening.followup = true
	record.screening.last = 480
	health.synchronize()
	health.care.consider("female")
	sim.services.npc_planner.resolve()
	t._check(record.selfcare.get("operation","")=="care_step","unaffordable older clinic visit does not block already funded home care")
