extends "res://scripts/mechanics/core/module.gd"
## Private self-care and clinic actions submitted to the shared NPC planner.
const Access = preload("res://scripts/mechanics/care_access.gd")

func health():
	return sim.services.adult_health

func now() -> int:
	return int(sim.state.clock.total_minutes)

func location(id: String) -> String:
	return str(sim.state.world.location) if id=="player" else str(health().actor(id).location)

func private_facility(id: String) -> bool:
	return Access.sanitary(sim,id)

func price(operation: String) -> int:
	return int(health().config().actions.get(operation,{}).get("cost",0))

func blocked(id: String, operation: String, args: Dictionary, completion: bool = false) -> String:
	var r: Dictionary = health().record(id)
	if r.is_empty(): return "adult_health_adults_only"
	if not health().config().actions.has(operation): return "unknown_operation"
	var place := location(id)
	var clinic := Access.clinic(sim)
	if operation in ["change_product","cleanup"] and not private_facility(id): return "toilet_required"
	if operation in ["consult","screen","followup","vaccinate","treat","treat_lesions","care_review","emergency"]:
		if place!=clinic: return "clinic_required"
		if operation!="emergency":
			var clinical: String = Access.clinic_blocked(sim,id,int(health().config().actions[operation].minutes),completion)
			if not clinical.is_empty(): return clinical
	if operation=="buy_products":
		if not Access.supplies_available(sim,id): return "hygiene_supplies_shop_required"
		if not health().capabilities(id).menstruates: return "menstrual_capability_required"
		if int(r.cycle.supplies.get(str(args.get("product","pad")),0))>90: return "supplies_limit"
	if operation in ["buy_products","change_product"]:
		var product := str(args.get("product","pad"))
		if not health().config().cycle.products.has(product): return "unknown_menstrual_product"
		if operation=="change_product" and int(r.cycle.supplies.get(product,0))<=0: return "missing_menstrual_product"
	if operation=="consult" and now()<int(r.consult_after): return "care_already_provided"
	if operation=="followup" and not r.screening.followup: return "diagnosis_required"
	if operation=="screen":
		if not health().capabilities(id).has_cervix: return "cervical_screening_not_applicable"
		if int(health().actor(id).age)<int(health().config().hpv.screening_min_age): return "screening_age_required"
		if now()<int(r.screening.next): return "screening_cooldown"
	if operation=="vaccinate":
		if int(r.vaccine.doses)>=3: return "vaccination_complete"
		if now()<int(r.vaccine.next_dose): return "vaccination_not_due"
		var age := int(health().actor(id).age)
		if age>45: return "vaccination_age_review_required"
		if age>=27 and int(r.get("last_consult",-10080))<0: return "vaccination_consult_required"
		if health().pregnant(id): return "vaccination_deferred_pregnancy"
	if operation=="treat":
		var condition: Dictionary = r.conditions.get(str(args.get("condition","")),{})
		if condition.is_empty() or condition.status!="active" or not condition.known: return "diagnosis_required"
		if int(condition.treatment_until)>0: return "treatment_in_progress"
	if operation=="care_step":
		if not Access.sanitary(sim,id): return "care_private_place_required"
		var reason: String = health().plans.step_blocked(id,str(args.get("condition","")),0 if completion else int(health().config().actions.care_step.minutes))
		if not reason.is_empty(): return reason
	if operation=="care_review":
		var course: Dictionary = r.conditions.get(str(args.get("condition","")),{}).get("course",{})
		if course.is_empty() or not (course.review_required or course.review_pending): return "care_review_not_required"
	if operation=="treat_lesions":
		var lesions := false
		for infection in r.hpv.values():
			if infection.known and infection.status=="active" and int(infection.lesions_at)>0 and now()>=int(infection.lesions_at) and not infection.lesions_treated: lesions = true
		if not lesions: return "diagnosed_lesions_required"
	if operation=="emergency" and not health().view(id).urgent: return "no_urgent_health_problem"
	var money := int(sim.state.economy.cash) if id=="player" else int(health().actor(id).money)
	return "insufficient_funds" if money<price(operation) else ""

func apply(id: String, operation: String) -> void:
	var r: Dictionary = health().record(id)
	if r.is_empty(): return
	if operation=="cleanup": r.soiled = false; health().adjust(id,"hygiene",35)
	if operation=="rest":
		r.relief_until = now()+180
		health().adjust(id,"energy",5)
		if float(r.desire.frustration)>0:
			r.desire.frustration = maxf(0,float(r.desire.frustration)-5)
			health().adjust(id,"mood",2)
		if not r.erection.persistent:
			r.erection.until = 0
			r.erection.difficulty_until = 0
	if operation=="emergency":
		r.erection.until = 0
		r.erection.persistent = false
		r.erection.painful = false
		r.relief_until = now()+720
		health().infections.consult(id)
	health()._refresh(id)

func perform(id: String, operation: String, args: Dictionary, elapse: bool = true) -> Dictionary:
	var reason := blocked(id,operation,args,not elapse)
	if not reason.is_empty(): return Rules.fail(reason)
	var minutes := int(health().config().actions[operation].minutes)
	if elapse:
		var elapsed: Dictionary = sim.advance(minutes)
		if not elapsed.ok: return elapsed
	var r: Dictionary = health().record(id)
	if id=="player": sim.state.economy.cash -= price(operation)
	else: health().actor(id).money -= price(operation)
	match operation:
		"buy_products":
			var product := str(args.get("product","pad"))
			r.cycle.supplies[product] += 1 if product=="cup" else 6
		"change_product":
			var changed: Dictionary = health().cycle.change(id,str(args.get("product","pad")))
			if not changed.ok: return changed
		"consult": health().infections.consult(id)
		"screen": health().infections.screen(id)
		"followup":
			r.screening.followup = false
			r.screening.result = "under_observation"
			r.screening.next = sim.calendar.add_months(now(),3)
		"vaccinate":
			r.vaccine.doses += 1
			r.vaccine.next_dose = sim.calendar.add_months(now(),2 if int(r.vaccine.doses)==1 else 4) if int(r.vaccine.doses)<3 else 0
		"treat":
			var key := str(args.condition)
			health().plans.begin(id,key)
		"care_step": health().plans.perform_step(id,str(args.condition))
		"care_review": health().plans.review(id,str(args.condition))
		"treat_lesions":
			for infection in r.hpv.values():
				if infection.known: infection.lesions_treated = true; infection.last_result = "no_lesions" if infection.last_result=="lesions" else infection.last_result
		_: apply(id,operation)
	health()._refresh(id)
	health().log_event("care",{"target":id,"operation":operation})
	return Rules.ok({"minutes":minutes})

func execute(operation: String, args: Dictionary) -> Dictionary:
	return perform("player",operation,args)

func consider(id: String) -> void:
	var r: Dictionary = health().record(id)
	var npc: Dictionary = health().actor(id)
	var status: Dictionary = health().view(id)
	if status.urgent and r.selfcare.get("operation","")=="emergency": return
	if not status.urgent and (not r.selfcare.is_empty() or int(npc.pinned_until)>now()): return
	if not status.urgent and (npc.activity=="sleep" or not str(npc.mind.active.get("partner","")).is_empty()): return
	var operation := ""
	var args := {}
	if not status.urgent:
		var dialogue: Dictionary = npc.mind.get("dialogue",{})
		if dialogue.get("node","end")!="end" and int(dialogue.get("expires",0))>now(): return
		var pending: Dictionary = dialogue.get("pending",{})
		if not pending.is_empty() and int(pending.get("expires",0))>now(): return
	var pregnancy: Dictionary = sim.services.reproduction.pregnancy(id)
	# Existing pregnancy decisions reserve the clinic before routine prevention.
	if health().pregnant(id) and not status.urgent and not pregnancy.get("decision","undecided") in ["continue","adoption"]: return
	var destination := str(npc.location)
	var clinic := Access.clinic(sim)
	var planned: Dictionary = health().plans.next_action(id)
	var supervised := false
	var unassessed := false
	for condition in r.conditions.values():
		if condition.status=="active" and not condition.known: unassessed = true
		if condition.status=="active" and condition.known and not condition.course.is_empty(): supervised = true
	if status.urgent: operation = "emergency"; destination = clinic
	elif r.soiled: operation = "cleanup"
	elif r.cycle.active and (r.cycle.product=="none" or float(r.cycle.fill)>=70 or now()-int(r.cycle.changed)>=int(health().config().cycle.products[r.cycle.product].change_minutes)-30):
		if int(r.cycle.supplies.pad)>0: operation = "change_product"; args.product = "pad"
		else: operation = "buy_products"; args.product = "pad"; destination = str(sim.catalog.location_roles.supply_shop)
	elif not planned.is_empty():
		operation = str(planned.operation)
		if not str(planned.condition).is_empty(): args.condition = str(planned.condition)
		destination = sim.actor_home(id) if operation=="care_step" and not Access.sanitary(sim,id) else str(npc.location) if operation=="care_step" else clinic
	elif now()>=int(r.consult_after) and (not supervised or unassessed or int(r.erection.difficulties)>=3 or int(r.symptoms.get("visible_growths",0))>0) and (status.seek_care or status.symptom_list.any(func(item): return int(item.severity)>=60)): operation = "consult"; destination = clinic
	else:
		for key in r.conditions:
			var c: Dictionary = r.conditions[key]
			if c.known and c.status=="active" and int(c.treatment_until)==0: operation = "treat"; args.condition = key; destination = clinic; break
		if operation.is_empty():
			for infection in r.hpv.values():
				if infection.known and infection.status=="active" and int(infection.lesions_at)>0 and now()>=int(infection.lesions_at) and not infection.lesions_treated:
					operation = "treat_lesions"; destination = clinic; break
		if operation.is_empty() and status.capabilities.has_cervix and int(npc.age)>=int(health().config().hpv.screening_min_age) and now()>=int(r.screening.next) and health().unit(id+":screening_policy")<0.7: operation = "screen"; destination = clinic
		if operation.is_empty() and r.screening.followup: operation = "followup"; destination = clinic
		if operation.is_empty() and int(r.vaccine.doses)<3 and now()>=int(r.vaccine.next_dose) and int(npc.age)<=45 and health().unit(id+":vaccination_policy")<0.65: operation = "vaccinate"; destination = clinic
	if operation.is_empty(): return
	if operation in ["vaccinate","screen"] and npc.decision.get("committed",false): return
	if operation in ["change_product","cleanup"] and not private_facility(id): destination = str(npc.home)
	if destination==clinic and not sim.services.world.is_open(sim.catalog.locations[clinic]) and operation!="emergency": return
	var route: Dictionary = sim.services.npc_agency._route(npc,str(npc.location),destination,-1,bool(status.urgent))
	if route.is_empty() or int(npc.money)<int(route.cost)+price(operation): return
	if operation=="vaccinate" and (health().pregnant(id) or (int(npc.age)>=27 and int(r.get("last_consult",-10080))<0)): return
	sim.services.npc_planner.submit("adult_health",id,operation,destination,int(health().config().actions[operation].minutes),100 if status.urgent else 60,args)

func start(request: Dictionary) -> bool:
	var id := str(request.id)
	var operation := str(request.kind)
	var npc: Dictionary = health().actor(id)
	var r: Dictionary = health().record(id)
	var route: Dictionary = request.route
	if not r.selfcare.is_empty() or int(npc.money)<int(route.cost)+price(operation): return false
	var destination := str(request.destination)
	var arrival := now()+int(route.minutes)
	var due := arrival+int(health().config().actions[operation].minutes)
	var previous_pin := int(npc.pinned_until)
	sim.services.npc_agency._cancel(npc,"adult_health_break")
	npc.money -= int(route.cost)
	r.selfcare = {"operation":operation,"args":request.payload.duplicate(true),"origin":str(npc.location),"destination":destination,"arrival":arrival,"due":due,
		"phase":"travel" if int(route.minutes)>0 else "action","pin":due+1,"previous_pin":previous_pin}
	npc.pinned_until = due+1
	npc.activity = "personal_travel" if int(route.minutes)>0 else "personal_errand"
	npc.decision = {"reason":"adult_health_"+operation,"committed":true}
	return true

func cancel(id: String) -> void:
	var r: Dictionary = health().record(id)
	if r.is_empty() or r.selfcare.is_empty(): return
	var npc: Dictionary = health().actor(id)
	if not npc.is_empty() and int(npc.pinned_until)==int(r.selfcare.pin):
		npc.pinned_until = int(r.selfcare.previous_pin)
		npc.activity = "rest"
		npc.decision = {"reason":"adult_health_break_finished","committed":false}
	r.selfcare = {}

func tick_job(id: String) -> void:
	var r: Dictionary = health().record(id)
	var job: Dictionary = r.selfcare
	if job.is_empty(): return
	var npc: Dictionary = health().actor(id)
	if npc.is_empty() or int(npc.pinned_until)!=int(job.pin): cancel(id); return
	if npc.location!=(job.origin if job.phase=="travel" else job.destination): cancel(id); return
	if job.phase=="travel" and now()>=int(job.arrival): npc.location = job.destination; npc.activity = "personal_errand"; job.phase = "action"
	if now()>=int(job.due):
		perform(id,str(job.operation),job.args,false)
		cancel(id)
