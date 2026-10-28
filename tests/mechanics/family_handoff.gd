extends RefCounted
const Fixture = preload("res://tests/mechanics/adult_health.gd")
const Sim = preload("res://scripts/mechanics/autonomous_reproductive_simulation.gd")
var t

func _init(runner) -> void: t = runner

func fresh(player_parent: bool = true):
	var sim = Fixture.new(t).fresh()
	sim.state.npc_reproduction.enabled = false
	sim.state.clock = sim.calendar.snapshot(481)
	sim.state.healthcare.family.append({"parent":"male","partner":"player" if player_parent else "female","minute":480,"care":0,"status":"dependent"})
	sim.services.family.initialize()
	var member: Dictionary = sim.state.family.members.family_1
	member.needs.food = 20.0
	member.assignments.food = "player" if player_parent else "female"
	sim.state.world.location = "global_map"
	for id in ["male","female"]:
		var npc: Dictionary = sim.state.social.npcs[id]
		sim.services.npc_agency._cancel(npc,"handoff_fixture")
		npc.pinned_until = 0
		npc.activity = "rest"
		for need in npc.needs: npc.needs[need] = 100.0
	return sim

func member(sim) -> Dictionary: return sim.state.family.members.family_1
func same(a: Variant, b: Variant) -> bool: return JSON.parse_string(JSON.stringify(a))==JSON.parse_string(JSON.stringify(b))

func reject(sim, args: Dictionary, reason: String) -> void:
	var before: Dictionary = sim.export_snapshot()
	var result: Dictionary = sim.command("family","delegate",args)
	t._check(not result.ok and result.get("error","")==reason and before==sim.export_snapshot(),"temporary care refusal is atomic: "+reason)

func advance(sim, minutes: int) -> void:
	t._check(sim.command("clock","advance",{"minutes":minutes}).ok,"delegated care progresses through the shared clock")

func run() -> void:
	_actual_task_and_replay()
	_helper_guards()
	_schedule_and_travel()
	_medical_priority()
	_autonomous_cover()
	_late_revalidation()

func _actual_task_and_replay() -> void:
	var sim = fresh()
	var before: Dictionary = sim.export_snapshot()
	var options: Array = sim.services.family.care_options("family_1","food")
	t._check(options.size()==1 and options[0].caregiver=="male" and options[0].available,"only the second actual guardian is offered for a temporary food duty")
	t._check(before==sim.export_snapshot(),"reading care alternatives preserves world, money, reservations and RNG")
	var money := int(sim.state.economy.cash)
	var energy := float(sim.state.social.npcs.male.needs.energy)
	var minute := int(sim.state.clock.total_minutes)
	t._check(sim.command("family","delegate",{"id":"family_1","need":"food","caregiver":"male"}).ok,"player can request one actual care task from a present co-guardian")
	t._check(member(sim).assignments.food=="player" and member(sim).task.caregiver=="male","temporary coverage preserves the permanent responsible guardian")
	t._check(sim.state.clock.total_minutes==minute and member(sim).needs.food==20.0,"request alone grants no completed care or elapsed care time")
	t._check(sim.state.economy.cash==money-3 and sim.state.family.spent==3 and sim.state.social.npcs.male.needs.energy==energy-3,"actual start spends existing household supplies and helper energy once")
	t._check(member(sim).task.due==minute+20 and sim.state.social.npcs.male.location==member(sim).home,"helper reserves twenty real minutes at the child's actual home")
	reject(sim,{"id":"family_1","need":"food","caregiver":"male"},"family_care_in_progress")
	reject(sim,{"id":"family_1","need":"attention","caregiver":"male"},"family_care_in_progress")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(sim.export_snapshot()))
	var clone = Sim.new(1,Fixture.new(t).config())
	t._check(clone.restore_snapshot(snapshot).ok,"temporary handoff saves through the existing family task schema")
	advance(sim,19)
	advance(clone,19)
	t._check(member(sim).needs.food==20 and not member(sim).task.is_empty(),"nineteen minutes grant no early care outcome")
	advance(sim,1)
	advance(clone,1)
	t._check(member(sim).task.is_empty() and member(sim).needs.food==80 and member(sim).bonds.male==2,"completed care restores one need and records the real caregiver bond once")
	t._check(member(sim).assignments.food=="player" and same(sim.export_snapshot(),clone.export_snapshot()),"completion and future simulation replay identically without reassignment")
	t._check(sim.state.family.history.filter(func(e): return e.kind=="care_handoff").size()==1,"one accepted temporary handoff records one bounded history event")

func _helper_guards() -> void:
	var sim = fresh()
	var args := {"id":"family_1","need":"food","caregiver":"male"}
	reject(sim,{"id":"family_1","need":"food","caregiver":"female"},"family_helper_not_guardian")
	reject(sim,{"id":"family_1","need":"health","caregiver":"male"},"invalid_care_assignment")
	reject(sim,{"id":"family_1","need":"food","caregiver":"player"},"family_helper_is_primary")
	sim.state.social.npcs.male.location = "global_map"
	reject(sim,args,"family_helper_not_home")
	sim.state.social.npcs.male.location = "bedroom"
	sim.state.social.npcs.male.health = 20
	reject(sim,args,"family_helper_unwell")
	sim.state.social.npcs.male.health = 100
	sim.state.social.npcs.male.needs.energy = 10
	reject(sim,args,"family_helper_unwell")
	sim.state.social.npcs.male.needs.energy = 100
	sim.state.social.npcs.male.pinned_until = int(sim.state.clock.total_minutes)+60
	reject(sim,args,"family_helper_busy")
	sim.state.social.npcs.male.pinned_until = 0
	sim.state.social.npcs.male.activity = "sleep"
	reject(sim,args,"family_helper_busy")
	sim.state.social.npcs.male.activity = "rest"
	sim.state.economy.cash = 0
	reject(sim,args,"insufficient_funds")
	sim.state.economy.cash = 100
	member(sim).needs.food = 90
	reject(sim,args,"family_care_not_due")
	member(sim).needs.food = 20
	member(sim).guardians = ["player"]
	reject(sim,args,"family_helper_not_guardian")
	t._check(sim.services.family.care_options("family_1","food").is_empty(),"a former guardian is absent from the offered alternatives")

func _schedule_and_travel() -> void:
	var sim = fresh()
	var minute := int(sim.state.clock.minute_of_day)
	sim.state.social.npcs.male.schedule = [{"activity":"study","location":"global_map","hours":[minute+5,minute+65],"weekdays":[int(sim.state.clock.weekday)]}]
	reject(sim,{"id":"family_1","need":"food","caregiver":"male"},"family_helper_schedule")
	var route: Dictionary = sim.services.npc_agency._route(sim.state.social.npcs.male,"bedroom","global_map")
	sim.state.social.npcs.male.schedule[0].hours = [minute+20+int(route.minutes)-1,minute+120]
	reject(sim,{"id":"family_1","need":"food","caregiver":"male"},"family_helper_schedule")
	sim.state.social.npcs.male.schedule[0].hours[0] += 1
	var before: Dictionary = sim.export_snapshot()
	t._check(sim.services.family.care_options("family_1","food")[0].available and before==sim.export_snapshot(),"exact arrival at the next obligation is allowed by the real route forecast")
	sim.state.social.npcs.male.schedule[0].activity = "work"
	sim.state.social.npcs.male.schedule[0].hours[0] = minute+5
	reject(sim,{"id":"family_1","need":"food","caregiver":"male"},"family_helper_schedule")

func _medical_priority() -> void:
	var sim = fresh()
	var health = sim.services.adult_health
	health.start_erection("male",true,true)
	health.record("male").erection.started = int(sim.state.clock.total_minutes)-240
	reject(sim,{"id":"family_1","need":"food","caregiver":"male"},"family_helper_unwell")
	sim = fresh()
	health = sim.services.adult_health
	health.infections.onset("male","urinary_infection")
	health._refresh("male")
	health.care.consider("male")
	sim.services.npc_planner.resolve()
	t._check(not health.record("male").selfcare.is_empty(),"medical-priority fixture reserves an actual clinic journey")
	reject(sim,{"id":"family_1","need":"food","caregiver":"male"},"family_helper_busy")

func _autonomous_cover() -> void:
	var sim = fresh(false)
	var primary: Dictionary = sim.state.social.npcs.female
	primary.health = 20
	var cash := int(sim.state.economy.cash)
	var helper_cash := int(sim.state.social.npcs.male.money)
	sim.services.family._autonomy(member(sim))
	t._check(member(sim).task.is_empty() and sim.state.social.npcs.male.money==helper_cash,"proposing autonomous cover does not spend money or perform care")
	sim.services.npc_planner.resolve()
	t._check(member(sim).task.get("caregiver","")=="male" and member(sim).assignments.food=="female","an available second NPC guardian covers an unwell primary without replacing the assignment")
	t._check(sim.state.social.npcs.male.money==helper_cash-3 and sim.state.economy.cash==cash,"NPC-only household care uses the actual helper's funds")
	advance(sim,20)
	t._check(member(sim).needs.food==80 and primary.health==20 and sim.state.economy.cash==cash,"care helps the child after real time without healing the primary or spending player money")
	sim = fresh()
	sim.services.family._autonomy(member(sim))
	sim.services.npc_planner.resolve()
	t._check(member(sim).task.get("caregiver","")=="male","NPC co-guardian can cover a player who is away from home")
	sim = fresh()
	sim.state.world.location = "bedroom"
	sim.services.family._autonomy(member(sim))
	sim.services.npc_planner.resolve()
	t._check(member(sim).task.is_empty(),"an available player retains their own assigned duty until they request help")

func _late_revalidation() -> void:
	var sim = fresh()
	sim.services.family._autonomy(member(sim))
	sim.state.social.npcs.male.location = "global_map"
	var before: Dictionary = sim.export_snapshot()
	sim.services.npc_planner.resolve()
	t._check(member(sim).task.is_empty() and before==sim.export_snapshot(),"helper departure between proposal and dispatch grants no task, cost or outcome")
	sim = fresh()
	sim.services.family._autonomy(member(sim))
	sim.state.social.npcs.male.health = 20
	before = sim.export_snapshot()
	sim.services.npc_planner.resolve()
	t._check(member(sim).task.is_empty() and before==sim.export_snapshot(),"helper illness arising before dispatch is rechecked before any care cost")
	sim = fresh()
	t._check(sim.command("family","delegate",{"id":"family_1","need":"food","caregiver":"male"}).ok,"interruption fixture starts actual delegated care")
	advance(sim,5)
	sim.services.npc_planner.interrupt("male","urgent_medical_care")
	var money := int(sim.state.economy.cash)
	sim.state.social.npcs.male.location = "clinic"
	advance(sim,15)
	t._check(member(sim).task.is_empty() and member(sim).needs.food==20 and member(sim).assignments.food=="player","interrupted care grants no remote benefit and preserves the original responsibility")
	t._check(sim.state.economy.cash==money and member(sim).bonds.is_empty(),"interruption neither refunds already used supplies nor creates an unearned bond")
	sim = fresh()
	t._check(sim.command("family","delegate",{"id":"family_1","need":"food","caregiver":"male"}).ok,"completion-boundary medical fixture starts existing care")
	advance(sim,19)
	var health = sim.services.adult_health
	health.start_erection("male",true,true)
	health.record("male").erection.started = int(sim.state.clock.total_minutes)-240
	advance(sim,1)
	t._check(member(sim).needs.food==20 and member(sim).bonds.is_empty(),"urgent illness at the completion boundary prevents an unperformed care outcome")
