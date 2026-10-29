extends SceneTree
## Reproducible seven-day sandbox workload probe. No save slots or UI scenes.
const Setup = preload("res://scripts/mechanics/setup_config.gd")

var gameplay
var session
var dialogic
var failures: Array[String] = []
var totals: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _act(module_id: String, operation: String, args: Dictionary, category: String) -> bool:
	var sim = gameplay.simulation
	var before := int(sim.state.clock.total_minutes)
	var cash := int(sim.state.economy.cash)
	var bank := int(sim.state.economy.bank)
	var result: Dictionary = gameplay.execute(module_id,operation,args)
	if not result.ok:
		failures.append("%s.%s %s at %d: %s" % [module_id,operation,JSON.stringify(args),before,str(result.get("error",""))])
		return false
	totals.minutes[category] = int(totals.minutes.get(category,0))+int(sim.state.clock.total_minutes)-before
	var cash_delta := int(sim.state.economy.cash)-cash
	if cash_delta > 0: totals.cash_income += cash_delta
	else: totals.cash_spent -= cash_delta
	totals.bank_change += int(sim.state.economy.bank)-bank
	totals.actions[category] = int(totals.actions.get(category,0))+1
	return true

func _journey(id: String) -> bool:
	if str(gameplay.simulation.state.world.location) == id: return true
	return _act("world","journey",{"id":id},"travel")

func _wait_until(minute: int) -> bool:
	var now := int(gameplay.simulation.state.clock.total_minutes)
	if minute < now: return false
	if minute == now: return true
	return _act("clock","advance",{"minutes":minute-now},"free")

func _care(morning: bool) -> bool:
	var sim = gameplay.simulation
	if not _journey(sim.player_home_room("kitchen")): return false
	if not _act("needs","drink",{},"care"): return false
	if float(sim.state.player.needs.satiety) < 70 and int(sim.state.inventory.items.get("meal",0)) > 0:
		if not _act("inventory","use",{"id":"meal"},"care"): return false
	if not _journey(sim.player_home_room("bathroom")): return false
	if not _act("needs","toilet",{},"care"): return false
	if morning and float(sim.state.player.needs.hygiene) < 75:
		if not _act("world","shower",{},"care"): return false
	return _journey(sim.player_home_room("bedroom"))

func _start_case(kind: String, start_cash: int) -> bool:
	var config: Dictionary = Setup.defaults()
	config.mode = "sandbox"
	config.seed = 1729
	config.population.count = 1
	config.sandbox.start_cash = start_cash
	config.sandbox.education = {"enrolled":kind == "student","subjects":["physics","genetics"] if kind == "student" else []}
	config.content.pregnancy = false
	if not Setup.validate(config).ok:
		failures.append("setup rejected for "+kind)
		return false
	gameplay._pending_configuration = config
	dialogic.clear(DialogicGameHandler.ClearFlags.FULL_CLEAR)
	session.reset_game_time()
	session.reset_character_profile()
	session.pause_autosave_runtime()
	var profile: Dictionary = session.get_character_profile()
	profile.identity.full_name = "Баланс: "+kind
	if not session.apply_character_profile_v2(profile):
		failures.append("profile rejected for "+kind)
		return false
	gameplay._on_profile_changed(session.get_character_profile())
	var opened: Dictionary = gameplay.open_sandbox()
	if not opened.ok:
		failures.append("sandbox rejected for %s: %s" % [kind,str(opened.get("error",""))])
		return false
	return true

func _supply(kind: String) -> bool:
	var sim = gameplay.simulation
	if not _journey(str(sim.catalog.shops.market.location)): return false
	if not _act("inventory","buy",{"id":"meal","quantity":12,"shop":"market"},"setup"): return false
	if kind == "computer":
		if not _act("inventory","buy",{"id":"computer","shop":"market"},"setup"): return false
	if not _journey(sim.player_home_room("bedroom")): return false
	if kind == "computer":
		if not _act("world","install",{"id":"computer"},"setup"): return false
		if not _act("economy","buy_asset",{"id":"studio"},"setup"): return false
	return true

func _student_day() -> bool:
	var sim = gameplay.simulation
	var lessons: Array = []
	for id in sim.services.education.available():
		var spec: Dictionary = sim.catalog.lessons[id]
		if int(sim.state.clock.weekday) in spec.weekdays: lessons.append(str(id))
	lessons.sort_custom(func(a: String,b: String): return int(sim.catalog.lessons[a].hours[0]) < int(sim.catalog.lessons[b].hours[0]))
	for id in lessons:
		var spec: Dictionary = sim.catalog.lessons[id]
		var departure: Dictionary = sim.services.world.route(str(spec.location))
		if not departure.ok:
			failures.append("no route to lesson "+id)
			return false
		var start := int(sim.state.clock.day_index)*1440+int(spec.hours[0])
		if not _wait_until(maxi(int(sim.state.clock.total_minutes),start-int(departure.data.minutes))): return false
		if not _journey(str(spec.location)) or not _wait_until(start): return false
		if not _act("world","lesson",{"id":id},"study"): return false
		if not _journey(sim.player_home_room("bedroom")): return false
		if not _act("education","homework",{"id":id},"study"): return false
	var day := int(sim.state.clock.day_index)
	if day in [2,4,6]:
		if not _act("education","project",{"id":"physics_class","approach":"applied"},"study"): return false
	return true

func _work_day(kind: String) -> bool:
	var sim = gameplay.simulation
	if kind == "worker":
		var job: Dictionary = sim.catalog.livelihood_rules.jobs.shop_assistant
		if not _journey(str(job.location)): return false
		if not _act("livelihood","work",{"id":"shop_assistant","interactive":false},"work"): return false
		return _journey(sim.player_home_room("bedroom"))
	for shift in range(2):
		if not _act("livelihood","work",{"id":"junior_developer","interactive":false},"work"): return false
	return true

func _case(kind: String, start_cash: int) -> Dictionary:
	totals = {"minutes":{},"actions":{},"cash_income":0,"cash_spent":0,"bank_change":0}
	if not _start_case(kind,start_cash): return {}
	var sim = gameplay.simulation
	var initial_budget: Dictionary = sim.services.planning.budget(7)
	var monthly_budget: Dictionary = sim.services.planning.budget(30)
	if not _supply(kind): return {}
	for index in range(7):
		var day := int(sim.state.clock.day_index)
		if not _care(true): return {}
		if kind == "student":
			if not _student_day(): return {}
		else:
			if not _work_day(kind): return {}
		if not _wait_until(day*1440+1320): return {}
		if not _care(false): return {}
		for leisure in range(2):
			if float(sim.state.player.needs.fun) >= 85: break
			if not _act("needs","leisure",{},"care"): return {}
		if not _wait_until((day+1)*1440): return {}
		if not _act("needs","sleep",{"minutes":480},"sleep"): return {}
	var measured := totals.duplicate(true)
	measured.kind = kind
	measured.seed = 1729
	measured.start_cash = start_cash
	measured.end_cash = int(sim.state.economy.cash)
	measured.end_bank = int(sim.state.economy.bank)
	measured.end_debt = int(sim.state.economy.debt)
	measured.end_needs = sim.state.player.needs.duplicate(true)
	measured.initial_scheduled = initial_budget.scheduled_expenses
	measured.initial_30_day_scheduled = monthly_budget.scheduled_expenses
	measured.initial_asset_net = initial_budget.asset_net_income
	measured.end_grade = float(sim.state.world.education.grade)
	measured.attended = sim.state.world.education.attended.size()
	measured.absences = int(sim.state.world.education.absences)
	measured.work_shifts = int(sim.state.livelihood.totals.shifts)
	measured.work_earnings = int(sim.state.livelihood.totals.earnings)
	measured.asset_owned = sim.state.economy.assets.has("studio")
	measured.end_minute = int(sim.state.clock.total_minutes)
	return measured

func _run() -> void:
	gameplay = root.get_node("Gameplay")
	session = root.get_node("GameSession")
	dialogic = root.get_node("Dialogic")
	session.pause_autosave_runtime()
	var results: Array = []
	for spec in [{"kind":"student","cash":1000},{"kind":"student","cash":250},{"kind":"worker","cash":1000},{"kind":"computer","cash":1000}]:
		var outcome := _case(str(spec.kind),int(spec.cash))
		if not outcome.is_empty(): results.append(outcome)
		if not failures.is_empty(): break
	print("SANDBOX_BALANCE_7D ",JSON.stringify({"results":results,"failures":failures}))
	quit(0 if failures.is_empty() and results.size() == 4 else 1)
