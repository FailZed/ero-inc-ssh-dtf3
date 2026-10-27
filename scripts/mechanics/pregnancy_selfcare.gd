extends "res://scripts/mechanics/core/module.gd"
## Short NPC breaks use real route time and shared reservations, never teleporting.

func service():
	return sim.services.pregnancy_wellbeing

func _now() -> int:
	return int(sim.state.clock.total_minutes)

func toilet_available(id: String) -> bool:
	var subject: Dictionary = service().actor(id)
	var location := str(sim.state.world.location) if id=="player" else str(subject.get("location",""))
	return bool(sim.catalog.locations.get(location,{}).get("toilet",false)) or location in service().config().rules.toilet_locations or (id!="player" and location==subject.get("home",""))

func apply(id: String, kind: String) -> void:
	var record: Dictionary = sim.state.pregnancy_wellbeing.records.get(id,{})
	if record.is_empty(): return
	match kind:
		"toilet":
			record.bladder = 100.0
			service()._adjust(id,"bladder",100)
		"cleanup":
			record.soiled = false
			service()._adjust(id,"hygiene",35)
		"rest":
			record.relief_until = maxi(int(record.relief_until),_now()+180)
			service()._adjust(id,"energy",8)
			service()._adjust(id,"rested",5)
		"supplies":
			var cost := int(service().config().rules.supplies_cost)
			if id!="player" and int(service().actor(id).money)>=cost and int(record.supplies)<=96:
				service().actor(id).money -= cost
				record.supplies += 3
	service()._refresh(id,record)

func execute(operation: String, args: Dictionary) -> Dictionary:
	var id := str(args.get("target","player"))
	if id!="player" and operation!="support": return Rules.fail("patient_decision_required")
	var status: Dictionary = service().view(id)
	if status.is_empty() or (not status.active and not status.soiled): return Rules.fail("no_pregnancy_discomfort")
	var record: Dictionary = sim.state.pregnancy_wellbeing.records[id]
	if operation=="support":
		if id=="player": return Rules.fail("unknown_patient")
		var npc: Dictionary = service().actor(id)
		if npc.location!=sim.state.world.location: return Rules.fail("npc_not_present")
		if npc.has("mind") and not npc.mind.boundaries.contact: return Rules.fail("contact_boundary")
		if npc.has("mind"):
			var blocked: String = sim.services.npc_dialogue.availability(npc,"face")
			if not blocked.is_empty(): return Rules.fail(blocked)
		if _now()-int(record.last_support)<1440: return Rules.fail("support_cooldown")
		var pin := int(npc.pinned_until)
		if npc.has("mind"): sim.services.npc_agency._cancel(npc,"pregnancy_support")
		npc.pinned_until = _now()+6
		var reserved := int(npc.pinned_until)
		var elapsed: Dictionary = sim.advance(5)
		if not elapsed.ok: return elapsed
		if int(npc.pinned_until)==reserved: npc.pinned_until = pin
		record.last_support = _now()
		record.relief_until = maxi(int(record.relief_until),_now()+180)
		service()._adjust(id,"mood",5)
		if npc.has("mind"): sim.services.npc_agency._experience(npc,"supported","player")
		service()._log("support",{"target":id,"listener":"player","text":"Спасибо. Мне легче, когда можно попросить о небольшом перерыве и помощи."})
		return Rules.ok({"minutes":5})
	if operation=="supplies":
		if not sim.state.world.location in ["clinic","global_map","market"]: return Rules.fail("hygiene_supplies_shop_required")
		var cost := int(service().config().rules.supplies_cost)
		if int(sim.state.economy.cash)<cost: return Rules.fail("insufficient_funds")
		if int(record.supplies)>96: return Rules.fail("supplies_limit")
		sim.state.economy.cash -= cost
		record.supplies += 3
		return sim.advance(5)
	if operation=="checkup":
		if sim.state.world.location!="clinic": return Rules.fail("clinic_required")
		var result: Dictionary = sim.services.health.prenatal_care(id,"player")
		if result.ok: record.relief_until = _now()+720; service()._refresh(id,record)
		return result
	if not operation in ["toilet","cleanup","rest"]: return Rules.fail("unknown_operation")
	if operation in ["toilet","cleanup"] and not toilet_available(id): return Rules.fail("toilet_required")
	var minutes := 15 if operation=="rest" else 10 if operation=="cleanup" else 5
	var result: Dictionary = sim.advance(minutes)
	if not result.ok: return result
	apply(id,operation)
	service()._log("selfcare",{"target":id,"action":operation})
	return Rules.ok({"minutes":minutes})

func consider(id: String, record: Dictionary) -> void:
	if not record.selfcare.is_empty(): return
	var npc: Dictionary = service().actor(id)
	if int(npc.pinned_until)>_now(): return
	if npc.activity=="sleep" and float(record.bladder)>=15 and not record.soiled: return
	if not str(npc.mind.active.get("partner","")).is_empty() or npc.mind.active.get("phase","")=="receiving": return
	var kind := "cleanup" if record.soiled else "toilet" if float(record.bladder)<25 else "rest" if float(npc.needs.energy)<35 else ""
	if kind.is_empty() and int(record.accidents)>0 and int(record.supplies)==0 and int(npc.money)>=int(service().config().rules.supplies_cost): kind = "supplies"
	if kind.is_empty(): return
	var destination := str(npc.location)
	if kind in ["toilet","cleanup"] and not toilet_available(id): destination = str(npc.home)
	if kind=="supplies": destination = "clinic"
	var route: Dictionary = sim.services.npc_agency._route(npc,str(npc.location),destination)
	if route.is_empty() or int(npc.money)<int(route.cost)+(int(service().config().rules.supplies_cost) if kind=="supplies" else 0): return
	var duration := 15 if kind=="rest" else 10 if kind=="cleanup" else 5
	var arrival := _now()+int(route.minutes)
	var due := arrival+duration
	var old_pin := int(npc.pinned_until)
	sim.services.npc_agency._cancel(npc,"pregnancy_break")
	npc.money -= int(route.cost)
	record.selfcare = {"kind":kind,"origin":str(npc.location),"destination":destination,"arrival":arrival,"due":due,
		"pin":due+1,"previous_pin":old_pin,"phase":"travel" if int(route.minutes)>0 else "action"}
	npc.pinned_until = due+1
	npc.activity = "personal_travel" if int(route.minutes)>0 else "rest"
	npc.decision = {"reason":"pregnancy_"+kind,"committed":true}
	service()._log("break_started",{"target":id,"action":kind,"destination":destination})

func cancel(id: String, record: Dictionary) -> void:
	var job: Dictionary = record.selfcare
	if job.is_empty(): return
	var npc: Dictionary = service().actor(id)
	if not npc.is_empty() and int(npc.pinned_until)==int(job.pin):
		npc.pinned_until = int(job.previous_pin)
		npc.activity = "rest"
		npc.decision = {"reason":"pregnancy_break_finished","committed":false}
	record.selfcare = {}

func tick_job(id: String, record: Dictionary, minute: int) -> void:
	var job: Dictionary = record.selfcare
	if job.is_empty(): return
	var npc: Dictionary = service().actor(id)
	if npc.is_empty() or int(npc.pinned_until)!=int(job.pin): cancel(id,record); return
	var expected := str(job.origin) if job.phase=="travel" else str(job.destination)
	if npc.location!=expected: cancel(id,record); return
	if job.phase=="travel" and minute>=int(job.arrival):
		npc.location = str(job.destination)
		npc.activity = "rest"
		job.phase = "action"
	if minute>=int(job.due):
		apply(id,str(job.kind))
		service()._log("selfcare",{"target":id,"action":job.kind})
		cancel(id,record)
