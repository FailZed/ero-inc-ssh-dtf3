extends SceneTree
var checks := 0
var failures: Array[String] = []
var gameplay

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, text: String) -> void:
	checks += 1
	if not value: failures.append(text); printerr("FAIL: ",text)

func fresh():
	var sim = gameplay.make_simulation()
	sim.state.clock = sim.calendar.snapshot(480)
	sim.state.economy.cash = 5000
	sim.state.world.location = "north_shops"
	sim.state.housing = {"residence":"apartment","properties":{"apartment":{"owned":false,"equipment":{},"tenants":[],"next_bill":45000,"arrears":0,"rent_income":0,"tenant_arrears":{},"original_homes":{},"layout":{}}}}
	return sim

func normal(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))

func solve(sim, wrong: bool = false) -> bool:
	return preload("res://tests/gameplay/work_driver.gd").finish(sim,wrong)

func run() -> void:
	gameplay = root.get_node("Gameplay")
	root.get_node("GameSession").pause_autosave_runtime()
	var sim = fresh()
	check(sim.configuration_error.is_empty(),"work catalog validates against actual city and inventory")
	var before: Dictionary = sim.export_snapshot()
	var board: Array = sim.services.livelihood.board()
	check(board.size() == 3 and before == sim.export_snapshot(),"daily board preview does not spend RNG or mutate state")
	for id in sim.catalog.livelihood_rules.jobs:
		sim = fresh()
		var job: Dictionary = sim.catalog.livelihood_rules.jobs[id]
		sim.state.world.location = job.location
		sim.state.clock = sim.calendar.snapshot(int(job.hours[0]))
		sim.state.world.equipment = ["computer","camera"]
		sim.state.player.skills[job.skill] = 10*int(job.min_skill)*int(job.min_skill)
		var start := int(sim.state.clock.total_minutes)
		var result: Dictionary = sim.command("livelihood","work",{"id":id})
		check(result.ok,"job has actual playable entry: "+id+" "+str(result.get("error","")))
		check(int(sim.state.clock.total_minutes) == start+int(job.minutes),"job uses shared world time: "+id)
		if not sim.state.livelihood.pending.is_empty(): check(solve(sim),"all interactive rounds are playable: "+id)
		check(sim.state.livelihood.totals.shifts == 1 and sim.validate_state(sim.state).ok,"job resolves once into valid persistent result: "+id)
	_test_session()
	_test_orders()
	_test_goals_and_home()
	_test_career_and_difficulty()
	_test_risk_and_limits()
	_test_current_snapshot()
	await _test_ui()
	print("LIVELIHOOD_RESULT ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures,"audio":AudioServer.get_driver_name()}))
	quit(0 if failures.is_empty() else 1)

func _test_session() -> void:
	var sim = fresh()
	sim.state.world.location = "riverside_cafe"
	check(sim.command("livelihood","work",{"id":"cafe_orders"}).ok,"interactive shift can begin")
	var p: Dictionary = sim.state.livelihood.pending
	var saved: Dictionary = sim.export_snapshot()
	check(not sim.command("world","journey",{"id":"city_park"}).ok and saved == sim.export_snapshot(),"active work cannot be escaped through world command")
	var replay = fresh()
	check(replay.restore_snapshot(normal(saved)).ok,"pending mini-game restores after JSON")
	check(solve(sim) and solve(replay) and normal(sim.export_snapshot()) == normal(replay.export_snapshot()),"same restored work yields same payment, career and RNG")
	saved = sim.export_snapshot()
	check(not sim.command("livelihood","cancel",{"token":p.token}).ok and saved == sim.export_snapshot(),"finished work cannot collect a second payment")
	var bad := saved.duplicate(true)
	bad.state.livelihood.careers.cafe_orders.xp = 999
	check(not sim.restore_snapshot(bad).ok and saved == sim.export_snapshot(),"corrupt career rejected without mutation")
	sim = fresh()
	sim.state.world.location = "riverside_cafe"
	sim.command("livelihood","work",{"id":"cafe_orders"})
	p = sim.state.livelihood.pending
	sim.command("livelihood","input",{"token":p.token,"round":0,"action":"ready"})
	saved = sim.export_snapshot()
	check(not sim.command("livelihood","input",{"token":p.token,"round":1,"choice":0,"elapsed_ms":300}).ok and saved == sim.export_snapshot(),"stale mini-game round is atomic")
	check(sim.command("livelihood","input",{"token":p.token,"round":0,"elapsed_ms":30000}).ok and sim.state.livelihood.pending.is_empty(),"timeout resolves unfinished work with low quality")

func _test_orders() -> void:
	var sim = fresh()
	var offer: Dictionary = sim.services.livelihood.board()[0]
	check(sim.command("livelihood","take_order",{"id":offer.id}).ok,"real daily order can be accepted")
	var before: Dictionary = sim.export_snapshot()
	check(not sim.command("livelihood","deliver",{"id":offer.id}).ok and before == sim.export_snapshot(),"order without actual goods cannot pay")
	sim.command("inventory","add",{"id":offer.item,"quantity":int(offer.quantity)})
	check(sim.command("livelihood","deliver",{"id":offer.id}).ok and sim.state.livelihood.totals.deliveries == 1 and not sim.state.inventory.items.has(offer.item),"delivery consumes inventory and pays once")
	before = sim.export_snapshot()
	check(not sim.command("livelihood","deliver",{"id":offer.id}).ok and before == sim.export_snapshot(),"completed order rejects duplicate payout")
	var next: Dictionary = sim.services.livelihood.board()[1]
	sim.command("livelihood","take_order",{"id":next.id})
	var due: Array = preload("res://scripts/gameplay/action_policy.gd").commitments(sim.state,int(next.deadline))
	check(due.any(func(entry): return entry.kind == "local_order"),"local order deadlines participate in shared action planning")
	sim.command("clock","advance",{"minutes":int(next.deadline)-int(sim.state.clock.total_minutes)})
	check(sim.state.livelihood.orders[next.id].status == "expired","orders expire through shared clock")
	var old_board: Array = sim.services.livelihood.board()
	sim.command("clock","advance",{"minutes":1440})
	check(old_board[0].id != sim.services.livelihood.board()[0].id,"next day creates fresh order IDs")

func _test_goals_and_home() -> void:
	var sim = fresh()
	sim.state.world.location = "bedroom"
	check(sim.command("livelihood","choose_goal",{"id":"own_place"}).ok,"player chooses an optional life goal")
	check(sim.command("livelihood","upgrade",{"id":"restful_bed"}).ok,"home upgrade costs actual money and time")
	sim.command("livelihood","upgrade",{"id":"restful_bed"})
	sim.command("livelihood","upgrade",{"id":"shower_filter"})
	check(sim.services.livelihood.goal_view("own_place").ready,"real home purchases advance life aspiration")
	check(sim.command("livelihood","claim_goal",{"id":"own_place"}).ok,"life goal grants XP once")
	var before: Dictionary = sim.export_snapshot()
	check(not sim.command("livelihood","claim_goal",{"id":"own_place"}).ok and before == sim.export_snapshot(),"life aspiration cannot farm repeat XP")
	sim.state.player.needs.rested = 0.0
	check(sim.command("needs","sleep",{"minutes":180}).ok and float(sim.state.player.needs.rested) >= 60,"bed upgrade changes actual sleep recovery")
	before = sim.export_snapshot()
	check(not sim.command("livelihood","upgrade",{"id":"restful_bed"}).ok and before == sim.export_snapshot(),"maximum home upgrade cannot charge money again")

func _test_risk_and_limits() -> void:
	var sim = fresh()
	sim.state.world.location = "north_alleys"
	sim.state.clock = sim.calendar.snapshot(1080)
	sim.command("preferences","content_tag",{"id":"crime","enabled":false})
	var before: Dictionary = sim.export_snapshot()
	var result: Dictionary = sim.command("livelihood","work",{"id":"underground_courier"})
	check(not result.ok and result.error == "content_disabled" and before == sim.export_snapshot(),"crime filter blocks illicit work before time, fee or RNG")
	var caught := 0
	for seed_value in range(1,21):
		sim = fresh()
		sim.rng.seed = seed_value
		sim.state.world.location = "north_alleys"
		sim.state.clock = sim.calendar.snapshot(1080)
		sim.state.world.heat = 100.0
		result = sim.command("livelihood","work",{"id":"underground_courier"})
		if result.ok and result.data.caught:
			caught += 1
			check(result.data.pay == 0 and sim.state.security.fine >= 100,"caught illicit work creates fine and confiscates pay")
			break
	check(caught > 0,"fictional criminal risk can produce actual consequences")
	sim = fresh()
	sim.command("livelihood","work",{"id":"shop_assistant"})
	sim.state.player.needs.energy = 100.0
	sim.command("livelihood","work",{"id":"shop_assistant"})
	sim.state.player.needs.energy = 100.0
	before = sim.export_snapshot()
	result = sim.command("livelihood","work",{"id":"shop_assistant"})
	check(not result.ok and result.error == "work_daily_limit" and before == sim.export_snapshot(),"daily work cap cannot be bypassed by repeated input")

func _test_career_and_difficulty() -> void:
	var sim = fresh()
	var first_pay: int = sim.services.livelihood.wage("shop_assistant",0.65)
	sim.command("livelihood","choose_goal",{"id":"steady_life"})
	for day in range(3):
		sim.state.clock = sim.calendar.snapshot(day*1440+800)
		for need in sim.state.player.needs: sim.state.player.needs[need] = 100.0
		check(sim.command("livelihood","work",{"id":"shop_assistant"}).ok,"career progresses through actual shift on day "+str(day))
	check(sim.services.livelihood.career("shop_assistant").level == 1,"automatic shifts alone cannot bypass the skill requirement")
	sim.state.player.skills.sales = 40
	check(sim.services.livelihood.career("shop_assistant").level == 2 and sim.services.livelihood.wage("shop_assistant",0.65) > first_pay,"skill progression alone raises automatic work salary")
	check(sim.state.livelihood.streak == 3 and not sim.services.livelihood.goal_view("steady_life").ready,"day streak persists while bank requirement still matters")
	sim.command("economy","deposit",{"amount":250})
	check(sim.services.livelihood.goal_view("steady_life").ready,"actual bank deposit completes independent life goal")
	var easy = fresh()
	var hard = fresh()
	easy.command("preferences","difficulty",{"id":"easy"})
	hard.command("preferences","difficulty",{"id":"hard"})
	easy.command("livelihood","work",{"id":"shop_assistant"})
	hard.command("livelihood","work",{"id":"shop_assistant"})
	check(float(hard.state.player.needs.energy) < float(easy.state.player.needs.energy),"sandbox difficulty affects new work costs through shared rules")

func _test_current_snapshot() -> void:
	var sim = fresh()
	var snapshot: Dictionary = sim.export_snapshot()
	var original := snapshot.duplicate(true)
	var restored = fresh()
	check(restored.restore_snapshot(snapshot).ok and original == snapshot,"current work snapshot restores without changing the input")
	snapshot.main_schema = 6
	check(not restored.restore_snapshot(snapshot).ok,"outdated main schema is unsupported")

func _test_ui() -> void:
	var original = gameplay.simulation
	gameplay.simulation = fresh()
	var window = load("res://scripts/ui/gameplay/livelihood_window.gd").new()
	root.add_child(window)
	await process_frame
	check(window._body.find_children("*","Button",true,false).filter(func(node): return node.has_meta("job_id")).size() == 33,"work UI renders all current jobs")
	for page in ["orders","goals","home"]:
		window.page = page
		window._refresh()
		check(window._body.get_child_count() > 1,"work UI has actual page: "+page)
	window.queue_free()
	await process_frame
	gameplay.simulation = original
