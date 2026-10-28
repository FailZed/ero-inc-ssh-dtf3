extends "res://scripts/mechanics/core/module.gd"
## Fictional work and self-directed progression. Every mutation uses the shared transaction.
const Check = preload("res://scripts/mechanics/core/livelihood_validation.gd")
const Challenges = preload("res://scripts/mechanics/work_challenges.gd")
const Schedule = preload("res://scripts/mechanics/work_schedule.gd")
const HOME := ["bedroom","bathroom","kitchen","apartment_hall"]

static func defaults() -> Dictionary:
	return {"version":2,"careers":{},"workdays":{},"pending":{},"serial":1,"orders":{},"goals":{},"active_goal":"","upgrades":{},"totals":{"shifts":0,"earnings":0,"good_games":0,"illicit":0,"deliveries":0,"upgrades":0},"streak":0,"streak_day":-1,"log":[]}

func initialize() -> void:
	if not sim.state.has("livelihood"): sim.state.livelihood = defaults()

func rules() -> Dictionary:
	return sim.catalog.livelihood_rules

func career(id: String) -> Dictionary:
	var job: Dictionary = rules().jobs[id]
	var skill: int = sim.services.growth.level(str(job.skill))
	var xp := int(sim.state.livelihood.careers.get(id,{}).get("xp",0))
	var level := 1
	for index in range(1,5):
		if skill < int(rules().promotion.skill_levels[index]): break
		if job.kind != "shift" and xp < int(rules().promotion.experience[index]): break
		level = index+1
	return {"level":level,"xp":xp,"automatic":job.kind == "shift","skill":skill,"next_skill":int(rules().promotion.skill_levels[mini(level,4)]),"next_xp":int(rules().promotion.experience[mini(level,4)])}

func skill_rank(id: String) -> int:
	var skill: int = sim.services.growth.level(id)
	var rank := 1
	for threshold in rules().promotion.skill_levels.slice(1):
		if skill >= int(threshold): rank += 1
	return rank

func study_conflicts(id: String) -> Array:
	var job: Dictionary = rules().jobs[id]
	var start := int(sim.state.clock.total_minutes)
	var location := str(sim.state.world.location)
	if location != job.location and not (location in HOME and job.location in HOME):
		var journey: Dictionary = sim.services.world.route_from(location,str(job.location),start,false)
		if journey.ok: start += int(journey.data.minutes)
		location = str(job.location)
	return Schedule.conflicts(sim,location,int(job.minutes),start)

func home_level(id: String) -> int:
	return int(sim.state.livelihood.upgrades.get(str(sim.state.housing.residence),{}).get(id,0))

func wage(id: String, quality: float) -> int:
	var job: Dictionary = rules().jobs[id]
	var bonus := 1.0 + 0.08*(int(career(id).level)-1)
	if sim.state.world.flags.get("qualified_"+str(job.skill),false): bonus += 0.10
	if job.location in HOME: bonus += 0.05*home_level("workspace")
	return roundi(float(job.pay)*bonus*(0.45+0.85*quality))

func risk(id: String) -> float:
	var job: Dictionary = rules().jobs[id]
	if float(job.risk) <= 0: return 0.0
	var pressure := 0.8+0.4*float(sim.services.preferences.rule("npc_tactics",0.5))
	var skill: String = sim.services.growth.job_skill(id)
	return clampf(float(job.risk)*pressure+float(sim.state.world.heat)*0.003-float(sim.state.player.skills.get(skill,0))*0.0008,0.05,0.90)

func blocked(id: String, skip_classes: bool = false) -> String:
	if not rules().jobs.has(id): return "unknown_livelihood_job"
	if not sim.state.livelihood.pending.is_empty(): return "finish_work_session"
	var job: Dictionary = rules().jobs[id]
	if float(job.risk) > 0 and "crime" in sim.state.preferences.disabled_tags: return "content_disabled"
	if sim.services.growth.level(str(job.skill)) < int(job.min_skill): return "work_skill_required"
	var at_home: bool = sim.state.world.location in HOME and job.location in HOME
	if sim.state.world.location != job.location and not at_home: return "wrong_workplace"
	var now := int(sim.state.clock.minute_of_day)
	if now < int(job.hours[0]) or now+int(job.minutes) > int(job.hours[1]): return "work_hours"
	if not skip_classes and not study_conflicts(id).is_empty(): return "work_conflicts_study"
	if int(sim.state.livelihood.workdays.get(_day_key(id),0)) >= 2: return "work_daily_limit"
	if int(sim.state.livelihood.workdays.get(_day_key("minutes"),0))+int(job.minutes) > 600: return "work_daily_limit"
	if float(sim.state.player.needs.energy) < float(job.energy)*sim.multiplier("resource_cost"): return "insufficient_energy"
	if int(sim.state.economy.cash) < int(job.get("fee",0)): return "insufficient_funds"
	if job.has("equipment") and not job.equipment in sim.state.world.equipment: return "missing_work_equipment"
	return ""

func _day_key(id: String) -> String:
	return "%d:%s" % [int(sim.state.clock.day_index),id]

func execute(operation: String, args: Dictionary) -> Dictionary:
	var id := str(args.get("id",""))
	match operation:
		"work": return _work(id,args)
		"input", "cancel": return _input(operation,args)
		"take_order": return _take_order(id)
		"deliver": return _deliver(id)
		"choose_goal":
			if not rules().aspirations.has(id): return Rules.fail("unknown_life_goal")
			if rules().aspirations[id].get("crime",false) and "crime" in sim.state.preferences.disabled_tags: return Rules.fail("content_disabled")
			var saved: Dictionary = sim.state.livelihood.goals.get(id,{})
			if saved.get("claimed",false): return Rules.fail("life_goal_claimed")
			if saved.is_empty(): sim.state.livelihood.goals[id] = {"baseline":int(sim.state.livelihood.totals[rules().aspirations[id].metric]),"claimed":false}
			sim.state.livelihood.active_goal = id
			return Rules.ok()
		"claim_goal":
			var view := goal_view(id)
			if not view.get("ready",false): return Rules.fail("life_goal_not_ready")
			sim.state.livelihood.goals[id].claimed = true
			sim.state.livelihood.active_goal = ""
			return sim.services.character.execute("gain_xp",{"amount":int(rules().aspirations[id].xp)})
		"upgrade": return _upgrade(id)
	return Rules.fail("unknown_operation")

func _work(id: String, args: Dictionary) -> Dictionary:
	if not args.get("interactive",true) is bool or not args.get("skip_classes",false) is bool: return Rules.fail("invalid_arguments")
	var reason := blocked(id,bool(args.get("skip_classes",false)))
	if not reason.is_empty(): return Rules.fail(reason)
	var job: Dictionary = rules().jobs[id]
	var started := int(sim.state.clock.total_minutes)
	var absences := int(sim.state.world.education.absences)
	var day_key := _day_key(id)
	var minute_key := _day_key("minutes")
	sim.state.livelihood.workdays[day_key] = int(sim.state.livelihood.workdays.get(day_key,0))+1
	sim.state.livelihood.workdays[minute_key] = int(sim.state.livelihood.workdays.get(minute_key,0))+int(job.minutes)
	sim.state.economy.cash -= int(job.get("fee",0))
	sim.services.character.adjust_need("energy",-float(job.energy)*sim.multiplier("resource_cost"))
	var advanced: Dictionary = sim.advance(int(job.minutes))
	if not advanced.ok: return advanced
	var interactive: bool = job.kind != "shift" and args.get("interactive",true)
	var session := {"id":id,"token":"work_%d" % int(sim.state.livelihood.serial),"started":started,"round":0,"correct":0,"elapsed":0,"last":0,"preview":job.kind == "memory","interactive":interactive,"tasks":[],"selection":[],"missed_classes":int(sim.state.world.education.absences)-absences}
	sim.state.livelihood.serial += 1
	if not interactive: return _finish(session,0.65 if job.kind == "shift" else 0.55,false)
	session.assistance = sim.services.growth.work_assistance(id)
	session.tasks = Challenges.build(sim,job,session.assistance)
	sim.state.livelihood.pending = session
	return Rules.ok({"interactive":true})

func _input(operation: String, args: Dictionary) -> Dictionary:
	var session: Dictionary = sim.state.livelihood.pending
	if session.is_empty(): return Rules.fail("no_work_session")
	if args.get("token","") != session.token: return Rules.fail("stale_work_input")
	var rounds := int(session.assistance.rounds)
	if operation == "cancel": return _finish(session,float(session.correct)/rounds,true)
	if not Check.integer(args.get("round"),0,rounds-1) or int(args.round) != int(session.round): return Rules.fail("stale_work_input")
	if session.preview:
		if args.get("action","") != "ready": return Rules.fail("work_memorize_first")
		session.preview = false
		return Rules.ok()
	if not Check.integer(args.get("elapsed_ms"),0,600000) or int(args.elapsed_ms) < int(session.elapsed): return Rules.fail("invalid_work_clock")
	var elapsed := int(args.elapsed_ms)
	if elapsed >= int(session.assistance.duration_ms): return _finish(session,float(session.correct)/rounds,false)
	if elapsed-int(session.last) < 160: return Rules.fail("input_debounce")
	var job: Dictionary = rules().jobs[session.id]
	var answer := Challenges.submit(session,job,args)
	if not answer.ok: return Rules.fail(str(answer.error))
	session.elapsed = elapsed
	session.last = elapsed
	if not answer.complete: return Rules.ok({"selection":session.selection.duplicate()})
	session.round += 1
	if answer.correct: session.correct += 1
	if session.round >= rounds:
		var finished := _finish(session,float(session.correct)/rounds,false)
		finished.data.feedback = answer.feedback
		return finished
	return Rules.ok({"correct":answer.correct,"feedback":answer.feedback})

func _finish(session: Dictionary, quality: float, cancelled: bool) -> Dictionary:
	var job: Dictionary = rules().jobs[session.id]
	var paid := wage(session.id,quality)
	if cancelled: paid = roundi(paid*0.4)
	var caught: bool = float(job.risk) > 0 and sim.rng.randf() < risk(session.id)
	if float(job.risk) > 0:
		sim.state.world.heat = minf(100,float(sim.state.world.heat)+(22.0 if caught else 5.0))
		if caught:
			paid = 0
			sim.state.security.fine += int(job.get("fine",100))
			sim.services.character.adjust_need("mood",-8)
			sim.state.security.incidents.append({"operation":"illicit_work","target":"","success":false,"minute":int(sim.state.clock.total_minutes)})
			while sim.state.security.incidents.size() > 64: sim.state.security.incidents.pop_front()
		elif not cancelled: sim.state.livelihood.totals.illicit += 1
	sim.state.economy.cash += paid
	sim.state.livelihood.totals.earnings += paid
	if not cancelled: sim.state.livelihood.totals.shifts += 1
	if job.kind != "shift" and quality >= 0.8 and not cancelled: sim.state.livelihood.totals.good_games += 1
	var before := career(str(session.id))
	var accelerated := false
	var gained := 0
	if job.kind != "shift" and not caught and not cancelled:
		gained = 18+roundi(quality*12) if session.interactive else 12
		accelerated = session.interactive and quality >= 0.8 and int(before.level) < 5 and int(before.skill) >= int(before.next_skill)
		if accelerated: gained += int(rules().promotion.quality_bonus)
		sim.state.livelihood.careers[session.id] = {"xp":mini(600,int(before.xp)+gained)}
	var skill: String = sim.services.growth.job_skill(str(session.id))
	sim.services.character.execute("train",{"skill":skill,"xp":1 if cancelled else 2+roundi(quality*3)})
	var after := career(str(session.id))
	if int(after.level) > int(before.level): emit_event("work_promoted",{"job":session.id,"level":after.level})
	if not cancelled: _attendance()
	_note({"kind":"work","id":session.id,"minute":int(sim.state.clock.total_minutes),"pay":paid,"quality":quality,"caught":caught,"cancelled":cancelled})
	sim.state.livelihood.pending = {}
	emit_event("work_paid",{"title":job.title,"pay":paid,"caught":caught})
	return Rules.ok({"completed":not cancelled,"pay":paid,"quality":quality,"caught":caught,"career_xp":gained,"accelerated":accelerated,"level":after.level,"missed_classes":session.missed_classes})

func _attendance() -> void:
	var day := int(sim.state.clock.day_index)
	if int(sim.state.livelihood.streak_day) == day: return
	sim.state.livelihood.streak = mini(7,int(sim.state.livelihood.streak)+1) if int(sim.state.livelihood.streak_day) == day-1 else 1
	sim.state.livelihood.streak_day = day
	sim.services.character.execute("gain_xp",{"amount":2*int(sim.state.livelihood.streak)})

func board() -> Array:
	var result: Array = []
	var ids: Array = rules().orders.keys()
	var day := int(sim.state.clock.day_index)
	for slot in range(3):
		var type: String = ids[posmod(int(sim._initial_seed)+day*31+slot*7,ids.size())]
		var offer: Dictionary = rules().orders[type].duplicate(true)
		offer.id = "%d_%d" % [day,slot]
		offer.type = type
		offer.deadline = day*1440+1380
		result.append(offer)
	return result

func _take_order(id: String) -> Dictionary:
	if sim.state.livelihood.orders.has(id): return Rules.fail("order_already_taken")
	var active := 0
	for order in sim.state.livelihood.orders.values():
		if order.status == "active": active += 1
	if active >= 2: return Rules.fail("order_capacity")
	for offer in board():
		if offer.id != id: continue
		if int(sim.state.clock.total_minutes)+15 >= int(offer.deadline): return Rules.fail("order_expired")
		offer.status = "active"
		sim.state.livelihood.orders[id] = offer
		return Rules.ok()
	return Rules.fail("stale_order_board")

func _deliver(id: String) -> Dictionary:
	var order: Dictionary = sim.state.livelihood.orders.get(id,{})
	if order.get("status","") != "active": return Rules.fail("order_not_active")
	if sim.state.world.location != "north_shops": return Rules.fail("order_delivery_place")
	if int(sim.state.clock.total_minutes)+15 >= int(order.deadline): return Rules.fail("order_expired")
	var removed: Dictionary = sim.services.inventory.change(str(order.item),-int(order.quantity))
	if not removed.ok: return removed
	var advanced: Dictionary = sim.advance(15)
	if not advanced.ok: return advanced
	order.status = "completed"
	sim.state.economy.cash += int(order.pay)
	sim.state.livelihood.totals.earnings += int(order.pay)
	sim.state.livelihood.totals.deliveries += 1
	_attendance()
	_note({"kind":"delivery","id":id,"minute":int(sim.state.clock.total_minutes),"pay":int(order.pay)})
	return Rules.ok({"pay":int(order.pay)})

func goal_view(id: String) -> Dictionary:
	if not rules().aspirations.has(id): return {}
	var spec: Dictionary = rules().aspirations[id]
	var saved: Dictionary = sim.state.livelihood.goals.get(id,{})
	var count := maxi(0,int(sim.state.livelihood.totals[spec.metric])-int(saved.get("baseline",sim.state.livelihood.totals[spec.metric])))
	return {"count":mini(count,int(spec.count)),"required":int(spec.count),"chosen":not saved.is_empty(),"claimed":saved.get("claimed",false),"ready":not saved.is_empty() and not saved.claimed and count >= int(spec.count) and int(sim.state.economy.bank) >= int(spec.get("bank",0))}

func _upgrade(id: String) -> Dictionary:
	if not rules().upgrades.has(id): return Rules.fail("unknown_home_upgrade")
	var home := str(sim.state.housing.residence)
	if home.is_empty() or not sim.state.world.location in HOME: return Rules.fail("home_required")
	var spec: Dictionary = rules().upgrades[id]
	var level := home_level(id)
	if level >= int(spec.max_level): return Rules.fail("home_upgrade_max")
	var price := int(spec.price)*(level+1)
	if int(sim.state.economy.cash) < price: return Rules.fail("insufficient_funds")
	sim.state.economy.cash -= price
	if not sim.state.livelihood.upgrades.has(home): sim.state.livelihood.upgrades[home] = {}
	sim.state.livelihood.upgrades[home][id] = level+1
	sim.state.livelihood.totals.upgrades += 1
	return sim.advance(30)

func observe(module_id: String, operation: String, args: Dictionary, _result: Dictionary, before: Dictionary) -> void:
	var sleeping: bool = module_id == "needs" and operation == "sleep"
	sleeping = sleeping or (module_id == "character" and operation == "rest" and args.get("kind","sleep" if int(args.get("minutes",60)) >= 120 else "rest") == "sleep")
	if sleeping and int(sim.state.clock.total_minutes)-int(before.clock.total_minutes) >= 180:
		sim.services.character.adjust_need("rested",10*home_level("restful_bed"))
	if module_id == "world" and operation == "shower": sim.services.character.adjust_need("hygiene",10*home_level("shower_filter"))

func tick(minute: int) -> void:
	for order in sim.state.livelihood.orders.values():
		if order.status == "active" and minute >= int(order.deadline):
			order.status = "expired"
			emit_event("local_order_expired",{"title":order.title})
	if minute % 1440 == 0:
		for key in sim.state.livelihood.workdays.keys():
			if int(str(key).get_slice(":",0)) < int(sim.state.clock.day_index)-7: sim.state.livelihood.workdays.erase(key)
		for key in sim.state.livelihood.orders.keys():
			if int(sim.state.livelihood.orders[key].deadline) < minute-10080: sim.state.livelihood.orders.erase(key)

func _note(entry: Dictionary) -> void:
	sim.state.livelihood.log.append(entry)
	while sim.state.livelihood.log.size() > 64: sim.state.livelihood.log.pop_front()
