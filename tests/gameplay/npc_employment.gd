extends SceneTree
const Employment = preload("res://scripts/mechanics/npc_employment.gd")
const Progress = preload("res://scripts/mechanics/core/career_progress.gd")
var gameplay
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures.append(text); printerr("FAIL: ",text)

func fresh(job: String = "shop_assistant", raw: int = 0, schedule: Array = [], role: String = "worker"):
	var sim = gameplay.make_simulation()
	# Isolate wage/rank tests from autonomous preventive-care appointments.
	sim.state.preferences.disabled_tags.append("adult")
	sim.catalog.npc_jobs = {job:sim.catalog.npc_jobs[job].duplicate(true)}
	sim.catalog.npc_templates.employment_fixture = {"age":25,"home":"bedroom","money":100,"role":role,"personalities":["calm"],"origins":["local"],"goals":["career"],"preferences":[],"schedule":schedule.duplicate(true),"activities":["read"]}
	sim.state.clock = sim.calendar.snapshot(1440+maxi(480,int(sim.catalog.npc_jobs[job].hours[0])))
	var generated: Dictionary = sim.command("social","generate",{"id":"worker","template":"employment_fixture"})
	check(generated.ok,"worker fixture generates")
	var npc: Dictionary = sim.state.social.npcs.worker
	npc.skills[str(sim.catalog.npc_jobs[job].skill)] = raw
	check(sim.command("npc_agency","enable").ok,"current occupation initializes: "+job)
	sim.services.npc_agency._cancel(npc,"test_fixture")
	npc.location = Employment.location(npc,sim.catalog.npc_jobs[job])
	return sim

func start(sim) -> void:
	var npc: Dictionary = sim.state.social.npcs.worker
	sim.services.npc_agency._cancel(npc,"next_test_chunk")
	sim.services.npc_agency._start(npc,"work",Employment.location(npc,Employment.profile(npc,sim.catalog)) if not Employment.profile(npc,sim.catalog).is_empty() else str(npc.location),"","test")

func advance(sim, minutes: int) -> void:
	var result: Dictionary = sim.command("clock","advance",{"minutes":minutes})
	check(result.ok,"shared clock advances NPC work: "+str(result.get("error","")))

func normalized(value: Dictionary) -> Dictionary: return JSON.parse_string(JSON.stringify(value))

func run() -> void:
	if AudioServer.get_driver_name()!="Dummy": quit(2); return
	gameplay = root.get_node("Gameplay")
	root.get_node("GameSession").pause_autosave_runtime()
	var sim = gameplay.make_simulation()
	check(sim.configuration_error.is_empty() and sim.catalog.npc_jobs.size()==30,"main occupations come from the thirty legal player jobs")
	check(not sim.catalog.npc_jobs.has("underground_courier") and not sim.catalog.npc_jobs.has("shadow_commission"),"criminal jobs are not simulated as risk-free background income")
	_test_skills_and_pay()
	_test_partial_work()
	_test_schedule()
	_test_budget()
	_test_generation()
	_test_authored_assignment()
	_test_research_rules()
	_test_snapshots()
	await _test_ui()
	print("NPC_EMPLOYMENT_RESULT ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures,"audio":AudioServer.get_driver_name()}))
	quit(0 if failures.is_empty() else 1)

func _test_skills_and_pay() -> void:
	for id in ["shop_assistant","park_gardener","fact_checker","repair_bench"]:
		var raw := 40 if id=="repair_bench" else 0
		var sim = fresh(id,raw)
		var npc: Dictionary = sim.state.social.npcs.worker
		var skill: String = sim.catalog.npc_jobs[id].skill
		npc.skills.computing = 1000
		var rank := Employment.rank(npc,sim.catalog)
		check(rank==(2 if raw==40 else 1),"unrelated programming never promotes "+id)
		var hourly := float(sim.services.npc_agency.employment_view("worker").hourly_pay)
		var cash := int(npc.money)
		start(sim)
		advance(sim,60)
		check(npc.skills[skill]==raw+2 and npc.skills.computing==1000,"productive work trains its own skill: "+id)
		check(int(npc.money)-cash==floori(hourly+0.000001) and npc.mind.employment.paid_minutes==60,"hourly payment follows the occupation and actual minutes: "+id)
		check(not npc.mind.has("career_level") and npc.mind.version==2,"superseded generic career field is absent")
	for raw in [0,39,40,159,160,359,360,639,640,1000]:
		var sim = fresh("shop_assistant",raw)
		sim.state.player.skills.sales = raw
		check(Employment.rank(sim.state.social.npcs.worker,sim.catalog)==sim.services.livelihood.skill_rank("sales"),"NPC and player share skill gates at raw "+str(raw))
	var sim = fresh("shop_assistant",39)
	var npc: Dictionary = sim.state.social.npcs.worker
	var hourly: float = sim.services.npc_agency.employment_view("worker").hourly_pay
	start(sim)
	advance(sim,60)
	check(Employment.rank(npc,sim.catalog)==2 and npc.mind.employment.earnings==floori(hourly),"skill gained during a chunk promotes the next chunk without retroactive higher pay")
	check(npc.mind.history.any(func(entry): return entry.kind=="career_progress"),"real skill promotion records a meaningful history event")
	sim = fresh("shop_assistant",36)
	npc = sim.state.social.npcs.worker
	sim.services.npc_agency._start(npc,"practice",str(npc.home),"","test")
	advance(sim,90)
	check(int(npc.skills.sales)>=40 and Employment.rank(npc,sim.catalog)>=2,"professional practice develops the skill needed for promotion")
	sim = fresh("repair_bench",0)
	check(sim.state.social.npcs.worker.mind.employment.job.is_empty(),"an unqualified NPC cannot enter a skilled profession")

func _test_partial_work() -> void:
	var sim = fresh()
	var npc: Dictionary = sim.state.social.npcs.worker
	var hourly: float = sim.services.npc_agency.employment_view("worker").hourly_pay
	start(sim)
	advance(sim,30)
	sim.services.npc_agency._cancel(npc,"family_or_health_interrupt")
	check(npc.mind.employment.paid_minutes==30 and npc.money==100+floori(hourly*0.5+0.000001),"interruption pays thirty productive minutes, never the full hour")
	check(npc.skills.sales==1 and npc.mind.employment.minutes_today==30,"interrupted work conserves training and day budget")
	var saved: Dictionary = sim.export_snapshot()
	sim.services.npc_agency._cancel(npc,"repeat")
	check(saved==sim.export_snapshot(),"a settled interruption cannot pay twice")
	sim = fresh()
	npc = sim.state.social.npcs.worker
	start(sim)
	advance(sim,15)
	sim.services.npc_planner.interrupt("worker","required_care")
	check(npc.mind.employment.paid_minutes==15 and npc.mind.active.is_empty(),"shared planner interruption preserves fifteen paid minutes for a care appointment")
	sim = fresh("park_gardener")
	npc = sim.state.social.npcs.worker
	npc.location = "bedroom"
	sim.services.npc_agency._start(npc,"work","bedroom","","wrong_place_test")
	check(npc.mind.active.is_empty(),"work cannot begin at an unrelated location")
	start(sim)
	check(npc.mind.active.phase=="travel","distant workplace starts a real commute")
	advance(sim,15)
	sim.services.npc_agency._cancel(npc,"travel_interrupted")
	check(npc.mind.employment.paid_minutes==0 and npc.mind.employment.earnings==0,"travel cannot mint work income or skill")

func _test_schedule() -> void:
	var schedule := [{"activity":"work","location":"global_map","hours":[540,1020],"weekdays":[1,3,5],"mandatory":true}]
	var sim = fresh("shop_assistant",0,JSON.parse_string(JSON.stringify(schedule)))
	var npc: Dictionary = sim.state.social.npcs.worker
	check(npc.schedule[0].location=="north_shops" and npc.schedule[0].hours==[540,720] and npc.schedule[0].weekdays==[1,3,5],"job binds workplace and actual shift while preserving chosen working days")
	var windows: Array = sim.services.npc_planner.calendar.windows("worker")
	check(windows.any(func(window): return window.action=="work" and window.location=="north_shops" and window.start==1440+540),"shared NPC planner sees the actual occupation window")
	sim = fresh("park_gardener",0,[{"activity":"study","location":"training_center","hours":[480,600],"weekdays":[1,2,3,4,5],"mandatory":true},{"activity":"work","location":"global_map","hours":[480,1020],"weekdays":[1,2,3,4,5],"mandatory":true}])
	check(sim.state.social.npcs.worker.mind.employment.job.is_empty(),"job placement cannot overwrite an overlapping mandatory study block")
	sim = fresh("park_gardener")
	npc = sim.state.social.npcs.worker
	sim.state.clock = sim.calendar.snapshot(1440+590)
	start(sim)
	check(npc.mind.active.due==1440+600,"free work clips the last chunk to employer closing time")
	advance(sim,10)
	check(npc.mind.employment.paid_minutes==10,"closing-time chunk pays only ten actual minutes")
	sim = fresh("shop_assistant",0,[],"student")
	check(sim.services.npc_agency.employment_view("worker").is_empty() and Employment.blocked(sim.state.social.npcs.worker,sim.catalog,sim.state.clock)=="not_employed","student is not silently forced into a worker occupation")

func _test_budget() -> void:
	var sim = fresh()
	var npc: Dictionary = sim.state.social.npcs.worker
	for i in range(6): start(sim); advance(sim,60)
	check(npc.mind.employment.minutes_today==360 and Employment.rank(npc,sim.catalog)==1,"six paid hours do not replace the required skill gate")
	start(sim)
	check(npc.mind.active.is_empty() and Employment.blocked(npc,sim.catalog,sim.state.clock)=="work_daily_limit","day budget blocks extra work after two full shifts")
	npc.schedule = [{"activity":"work","location":"north_shops","hours":[480,1200],"weekdays":[1,2,3,4,5],"mandatory":true}]
	var windows: Array = sim.services.npc_planner.calendar.windows("worker")
	check(not windows.any(func(window): return window.action=="work" and int(window.start)<2880),"exhausted work budget releases the rest of today's mandatory window")
	check(windows.any(func(window): return window.action=="work" and int(window.start)>=2880),"tomorrow's work obligation remains after today's budget is spent")
	check(Employment.remaining(npc,sim.catalog,sim.calendar.snapshot(2880+480))==360,"work budget renews on the next calendar day")
	sim = fresh()
	npc = sim.state.social.npcs.worker
	Employment.settle(npc,{"started":1379,"due":1439},0,sim.calendar.snapshot(1440))
	check(npc.mind.employment.minutes_today==0 and npc.mind.employment.paid_minutes==60,"late settlement after midnight never produces negative work minutes today")

func _test_research_rules() -> void:
	var sim = preload("res://scripts/mechanics/npc_life_simulation.gd").new(42,{"settings":{"start_minutes":480}})
	check(sim.command("social","generate",{"id":"worker"}).ok,"research worker generates")
	var npc: Dictionary = sim.state.social.npcs.worker
	npc.biography.role = "worker"
	npc.schedule = []
	npc.skills.study = 0
	check(sim.command("npc_agency","enable").ok,"research occupation initializes from JSON data")
	sim.services.npc_agency._cancel(npc,"fixture")
	check(npc.mind.employment.job=="reporter" and Employment.blocked(npc,sim.catalog,sim.state.clock).is_empty(),"JSON weekday numbers preserve the standalone worker's actual availability")
	npc.location = "global_map"
	sim.services.npc_agency._start(npc,"work","global_map","","test")
	advance(sim,60)
	check(npc.skills.get("journalism",0)==2 and npc.mind.employment.earnings==12,"standalone work trains the selected profession rather than programming")

func authored_world():
	var sim = gameplay.make_simulation()
	sim.state.preferences.disabled_tags.append("adult")
	sim.state.clock = sim.calendar.snapshot(1440+540)
	sim.catalog.npc_templates.authored_fixture = {"age":40,"home":"bedroom","money":100,"role":"worker","preferences":["books"],"schedule":[{"activity":"work","location":"riverside_cafe","hours":[600,1080],"weekdays":[1,2,3,4,5],"mandatory":true}]}
	return sim

func _test_authored_assignment() -> void:
	var plan := {"job":"cafe_orders","skill_level":2,"workplace":"riverside_cafe"}
	var sim = authored_world()
	var generated: Dictionary = sim.command("social","generate",{"id":"authored","template":"authored_fixture","employment":JSON.parse_string(JSON.stringify(plan))})
	check(generated.ok,"authored job accepts integral JSON skill levels at generation")
	check(sim.command("npc_agency","enable").ok,"authored job initializes through the normal agency")
	var npc: Dictionary = sim.state.social.npcs.authored
	check(npc.mind.employment.job=="cafe_orders" and npc.skills.cooking==40,"explicit profession and starting skill override random preference-based selection")
	check(npc.schedule[0].hours==[600,1080] and npc.schedule[0].location=="riverside_cafe" and Employment.daily_limit(npc,sim.catalog)==480,"authored full-time shift remains intact rather than being shortened to a player gig")
	npc.skills.cooking = 44
	var saved: Dictionary = normalized(sim.export_snapshot())
	var replay = authored_world()
	check(replay.restore_snapshot(saved).ok and replay.state.social.npcs.authored.skills.cooking==44 and replay.state.social.npcs.authored.mind.employment.job=="cafe_orders","authored occupation and learned skill survive restore without resetting to starting proficiency")
	var bad: Dictionary = saved.duplicate(true)
	bad.state.social.npcs.authored.mind.employment.job = "shop_assistant"
	check(not replay.restore_snapshot(bad).ok,"snapshot cannot replace an authored occupation with another valid random job")
	check(Employment.blocked(npc,sim.catalog,sim.calendar.snapshot(1440+540))=="outside_authored_shift","authored employee cannot silently work before the declared shift")
	check(Employment.blocked(npc,sim.catalog,sim.calendar.snapshot(6*1440+720))=="outside_authored_shift","authored employee cannot silently add a Saturday shift")
	check(Employment.available_minutes(npc,sim.catalog,sim.calendar.snapshot(1440+1070))==10,"authored shift closing clips a chunk even when the employer remains open")
	for change in [{"job":"missing"},{"job":"repair_bench","skill_level":1,"workplace":"north_shops"},{"skill_level":-1},{"skill_level":2.5},{"skill_level":11},{"workplace":"north_shops"},{"career_level":5}]:
		var world = authored_world()
		var assignment: Dictionary = plan.duplicate(true)
		assignment.merge(change,true)
		var before: Dictionary = world.export_snapshot()
		var result: Dictionary = world.command("social","generate",{"id":"rejected","template":"authored_fixture","employment":assignment})
		check(not result.ok and before==world.export_snapshot(),"contradictory authored assignment rejects before NPC/RNG changes: "+str(change))
	for schedule in [[],[{"activity":"work","location":"north_shops","hours":[600,1080],"weekdays":[1]}],[{"activity":"work","location":"riverside_cafe","hours":[300,600],"weekdays":[1]}],[{"activity":"work","location":"riverside_cafe","hours":[600,1080],"weekdays":[0]}],[{"activity":"work","location":"riverside_cafe","hours":[540,1200],"weekdays":[1]}],[{"activity":"work","location":"riverside_cafe","hours":[600,1080],"weekdays":[1]},{"activity":"study","location":"training_center","hours":[660,720],"weekdays":[1]}]]:
		var world = authored_world()
		world.catalog.npc_templates.authored_fixture.schedule = schedule
		var before: Dictionary = world.export_snapshot()
		var result: Dictionary = world.command("social","generate",{"id":"rejected","template":"authored_fixture","employment":plan})
		check(not result.ok and before==world.export_snapshot(),"authored job rejects conflicting/missing/overlong work schedule: "+str(schedule))
	sim = authored_world()
	sim.catalog.npc_templates.authored_fixture.employment = plan.duplicate(true)
	check(sim.command("social","generate",{"id":"authored","template":"authored_fixture"}).ok and sim.command("npc_agency","enable").ok and sim.state.social.npcs.authored.mind.employment.job=="cafe_orders","template employment uses the same explicit contract as generation arguments")
	sim = authored_world()
	sim.catalog.npc_templates.authored_fixture.employment = plan.duplicate(true)
	check(sim.command("social","generate",{"id":"authored","template":"authored_fixture","employment":JSON.parse_string(JSON.stringify(plan))}).ok,"semantically equal JSON and typed assignments are not falsely treated as conflicting")

func _test_generation() -> void:
	for age in [18,25,40]:
		var sim = fresh("shop_assistant")
		var npc: Dictionary = sim.state.social.npcs.worker
		npc.skills.clear()
		npc.age = age
		Employment.initialize(npc,sim.catalog,int(sim.state.clock.day_index))
		check(Progress.skill_level(float(npc.skills.sales))==(1 if age==18 else 2 if age==25 else 4),"generated adult receives bounded starting professional experience at age "+str(age))
		var before: Dictionary = sim.export_snapshot()
		sim.services.npc_agency.initialize_npc(npc)
		check(before==sim.export_snapshot(),"reinitializing a mind never grants starting experience twice")

func _test_snapshots() -> void:
	var sim = fresh()
	start(sim)
	advance(sim,30)
	var saved: Dictionary = normalized(sim.export_snapshot())
	var replay = fresh()
	check(replay.restore_snapshot(saved).ok,"unfinished work restores occupation, timer and budget")
	advance(sim,30)
	advance(replay,30)
	check(normalized(sim.export_snapshot())==normalized(replay.export_snapshot()),"continued work conserves pay, training, NPC decisions and RNG after restore")
	for change in [{"job":"missing"},{"job":""},{"minutes_today":601},{"paid_minutes":-1},{"earnings":"free"}]:
		var bad: Dictionary = saved.duplicate(true)
		bad.state.social.npcs.worker.mind.employment.merge(change,true)
		var before: Dictionary = replay.export_snapshot()
		check(not replay.restore_snapshot(bad).ok and replay.export_snapshot()==before,"corrupt occupation rejects atomically: "+str(change))
	var old: Dictionary = saved.duplicate(true)
	old.state.social.npcs.worker.mind.version = 1
	check(not replay.restore_snapshot(old).ok,"previous NPC mind format has no migration")
	old = saved.duplicate(true)
	old.state.social.npcs.worker.mind.career_level = 10
	check(not replay.restore_snapshot(old).ok,"superseded career cache is rejected")

func _test_ui() -> void:
	var original = gameplay.simulation
	var sim = fresh("park_gardener",160,[{"activity":"work","location":"global_map","hours":[360,600],"weekdays":[1,2,3,4,5]}])
	gameplay.simulation = sim
	var panel := VBoxContainer.new()
	root.add_child(panel)
	var before: Dictionary = sim.export_snapshot()
	preload("res://scripts/ui/gameplay/social_status.gd").employment(panel,sim,"worker")
	await process_frame
	check(panel.find_children("*","Label",true,false).any(func(node): return node.get_meta("npc_occupation","")=="park_gardener"),"real NPC details expose profession and rank")
	check(panel.find_children("*","Label",true,false).any(func(node): return node.text.contains("06:00–07:30")),"real NPC details expose the occupation schedule")
	check(before==sim.export_snapshot(),"reading career information leaves state and RNG unchanged")
	panel.queue_free()
	gameplay.simulation = original
