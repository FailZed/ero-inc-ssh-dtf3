extends SceneTree
## Pure backend integration; no UI scene, autoload or user save directory is used.
const Main = preload("res://scripts/gameplay/main_simulation.gd")
const Presentation = preload("res://scripts/gameplay/presentation.gd")
const Driver = preload("res://tests/gameplay/work_driver.gd")
var checks := 0
var failures: Array = []
func _initialize() -> void: call_deferred("run")
func check(value: bool, text: String) -> void:
	checks += 1
	if not value: failures.append(text); printerr("FAIL: ",text)
func fresh():
	var sim = Main.new(1729,Presentation.extensions())
	sim.state.clock = sim.calendar.snapshot(480)
	sim.state.economy.cash = 5000
	return sim
func normalized(sim) -> Dictionary: return JSON.parse_string(JSON.stringify(sim.export_snapshot()))
func run() -> void:
	preload("res://tests/gameplay/antagonism.gd").new(self).run()
	preload("res://tests/gameplay/computer.gd").new(self).run()
	_planning()
	_work_and_quests()
	_clubs()
	_stories()
	_family()
	print("MECHANICS_DEPTH_RESULT ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
func _planning() -> void:
	var sim = fresh()
	check(sim.configuration_error.is_empty() and sim.validate_state(sim.state).ok,"main backend accepts deepened mechanics catalog")
	var before: Dictionary = normalized(sim)
	var plan: Array = [{"module":"world","operation":"journey","args":{"id":"kitchen"}},{"module":"needs","operation":"drink","args":{}}]
	var forecast: Dictionary = sim.services.planning.forecast(plan)
	check(forecast.ok and forecast.data.complete and normalized(sim) == before,"forecast simulates on a separate world without touching live RNG")
	var start := int(sim.state.clock.total_minutes)
	for action in plan: check(sim.command(action.module,action.operation,action.args).ok,"forecast steps execute through normal main-game commands")
	check(int(sim.state.clock.total_minutes)-start == int(forecast.data.minutes),"forecast duration matches actual travel and drinking")
	before = normalized(sim)
	forecast = sim.services.planning.forecast([{"module":"digital","operation":"resolve","args":{}},plan[0]])
	check(forecast.ok and not forecast.data.complete and forecast.data.steps.size() == 1 and forecast.data.steps[0].uncertain and normalized(sim) == before,"plan stops before revealing a random digital outcome")
	sim.state.player.needs.hygiene = 25
	sim.state.player.needs.hydration = 20
	sim.state.player.needs.bladder = 15
	before = normalized(sim)
	var routine: Dictionary = sim.services.planning.routine("morning")
	check(routine.ok and routine.data.actions.size() >= 4 and normalized(sim) == before,"morning routine offers bathroom and water actions without executing them")
	check(sim.services.planning.forecast(routine.data.actions).data.complete,"suggested morning routine has valid world commands")
	check(sim.services.planning.priorities().size() >= 3,"planner exposes urgent needs")
	check(sim.command("housing","rent",{"id":"apartment"}).ok,"budget fixture rents actual property")
	sim.state.housing.properties.apartment.next_bill = int(sim.state.clock.total_minutes)+1440
	sim.state.housing.properties.apartment.arrears = 40
	var budget: Dictionary = sim.services.planning.budget(7)
	check(int(budget.scheduled_expenses) == int(sim.catalog.properties.apartment.monthly_rent)+40,"budget includes scheduled rent and existing debt")
	sim.state.housing.properties.apartment.evicted = true
	check(sim.services.planning.budget(7).scheduled_expenses == 40,"eviction does not erase debt from the forecast")
	var replay = fresh()
	check(replay.restore_snapshot(normalized(sim)).ok,"new main schema restores with planning and subject records")
	check(not sim.services.planning.forecast([{"module":"planning","operation":"forecast"}]).ok,"recursive forecasts are rejected")
func _work_and_quests() -> void:
	var sim = fresh()
	check(sim.catalog.quests.size() == 13 and sim.catalog.group_projects.size() == 4,"main catalog includes twelve new cross-system quests and three club projects")
	check(sim.command("events","start_quest",{"id":"reliable_specialist"}).ok,"work quest starts")
	sim.state.world.location = "riverside_cafe"
	var base := int(sim.services.livelihood.wage("cafe_orders",1.0))
	sim.state.world.flags["qualified_"+str(sim.catalog.livelihood_rules.jobs.cafe_orders.skill)] = true
	check(int(sim.services.livelihood.wage("cafe_orders",1.0)) > base,"relevant education qualification increases actual job payment")
	check(sim.command("livelihood","work",{"id":"cafe_orders"}).ok,"interactive work starts")
	check(sim.state.journal.quests.reliable_specialist.objectives.get("shifts",0) == 0,"starting a work mini-game does not count as a finished shift")
	check(Driver.finish(sim),"interactive work can be completed")
	check(sim.state.journal.quests.reliable_specialist.objectives.get("shifts",0) == 1,"completed interactive work counts once toward the quest")
	sim.state.clock = sim.calendar.snapshot(int(sim.state.clock.day_index)*1440+600)
	check(sim.command("livelihood","work",{"id":"cafe_orders"}).ok,"second work session starts")
	var token: String = sim.state.livelihood.pending.token
	check(sim.command("livelihood","cancel",{"token":token}).ok,"second work session cancels")
	check(sim.state.journal.quests.reliable_specialist.objectives.get("shifts",0) == 1,"cancelled shift does not advance the work quest")
	check(sim.command("events","start_quest",{"id":"home_with_purpose"}).ok,"home project quest starts")
	sim.state.world.location = "bedroom"
	sim.state.world.equipment.append("computer")
	check(sim.command("economy","project",{"id":"website_order","minutes":30}).ok,"home project partial work succeeds")
	check(sim.state.journal.quests.home_with_purpose.objectives.get("project",0) == 0,"partial project does not count as a finished result")
	check(sim.command("economy","project",{"id":"website_order","minutes":120}).ok,"home project completes")
	check(sim.state.journal.quests.home_with_purpose.objectives.get("project",0) == 1,"completed project advances linked quest")
func _stories() -> void:
	var sim = fresh()
	check(sim.command("npc_agency","enable").ok,"enable resident autonomy")
	check(sim.command("social","generate",{"id":"resident_depth"}).ok,"story fixture generates adult NPC")
	var npc: Dictionary = sim.state.social.npcs.resident_depth
	npc.mind.aspiration.id = "mastery"
	check(sim.services.npc_stories.arc_for("resident_depth") == "maker","generic personal story follows the NPC's actual aspiration")
	npc.mind.aspiration.id = "community"
	check(sim.services.npc_stories.arc_for("resident_depth") == "neighbor","community aspiration proposes an appropriate personal story")
	# Lock a legal intro record to ensure later personality changes never replace its graph.
	sim.state.npc_stories.arcs.resident_depth = {"arc":"maker","node":"intro","status":"active","started":480,"updated":480,"goal":{},"history":[],"ending":"","rewarded":false}
	check(sim.services.npc_stories.arc_for("resident_depth") == "maker" and sim.validate_state(sim.state).ok,"started personal story remains stable when aspiration changes")
func _family() -> void:
	var sim = fresh()
	sim.state.healthcare.family.append({"parent":"player","partner":"","minute":0,"care":0,"status":"dependent"})
	sim.services.family.initialize()
	var member: Dictionary = sim.state.family.members.family_1
	member.development = 24
	check(sim.command("family","care",{"id":"family_1","action":"play"}).ok,"shared family time develops abilities")
	check(sim.state.family.history.any(func(e): return e.kind == "development" and e.details.threshold == 25),"crossing a development milestone emits one meaningful family event")
	var before: Dictionary = normalized(sim)
	var view: Dictionary = sim.services.family.inspect()
	check(view.members[0].milestones[0].reached and normalized(sim) == before,"family view explains attained milestones without mutating state")
	sim.state.clock = sim.calendar.snapshot(sim.calendar.add_months(0,216)+600)
	sim.services.family._update_stage(member)
	member.needs.food = 20
	var cash := int(sim.state.economy.cash)
	sim.services.family._hour(member)
	check(member.stage == "adult" and member.needs.food > 60 and sim.state.economy.cash == cash-int(sim.catalog.family_actions.feed.cost),"adult family member prepares food independently using real household funds")
	sim.state.economy.cash = 0
	member.needs.food = 20
	sim.services.family._hour(member)
	check(member.needs.food < 20,"independent preparation does not conjure food without funds")

func _clubs() -> void:
	var sim = fresh()
	sim.state.clock = sim.calendar.snapshot(1440+1079)
	check(sim.command("npc_agency","enable").ok,"enable NPC agency for club integration")
	check(sim.command("social","generate",{"id":"club_depth"}).ok,"generate club participant")
	var npc: Dictionary = sim.state.social.npcs.club_depth
	npc.schedule = []
	npc.location = "training_center"
	npc.home = "training_center"
	npc.activity = "rest"
	npc.needs.energy = 100
	npc.needs.satiety = 100
	sim.state.world.location = "training_center"
	npc.biography.goal = "community"
	check(sim.command("organizations","create",{"id":"creative_collective"}).ok,"create club in the main world")
	check(sim.command("organizations","recruit",{"id":"creative_collective","npc":"club_depth"}).ok,"actual invitation accepts a willing member")
	check(sim.command("organizations","assign",{"id":"creative_collective","npc":"club_depth","task":"clean"}).ok,"assign an actual club duty")
	check(sim.command("institutions","policy",{"id":"creative_collective","wage":20}).ok,"set hourly club payment")
	var money := int(npc.money)
	check(sim.command("clock","advance",{"minutes":61}).ok,"NPC agency and club attendance advance together")
	var work: Dictionary = sim.state.organizations.creative_collective.work
	check(work.history.any(func(entry): return entry.reason == "completed" and entry.worked == 60 and entry.paid == 20) and int(npc.money) == money+20,"NPC completes a real club hour while autonomous AI is enabled")
	check(sim.validate_state(sim.state).ok,"club attendance leaves a valid main-game state")
