extends "res://scripts/mechanics/core/module.gd"
const Context = preload("res://scripts/mechanics/npc_reproductive_context.gd")

func _now() -> int:
	return int(sim.state.clock.total_minutes)

func _manager():
	return sim.services.npc_reproduction

func schedule(id: String, kind: String, destination: String, minutes: int, payload: Dictionary = {}) -> bool:
	var jobs: Dictionary = sim.state.npc_reproduction.jobs
	if jobs.has(id) or jobs.size()>=int(_manager().rules().max_jobs): return false
	if not Context.available(sim,id,0,0,true).is_empty(): return false
	var npc: Dictionary = sim.state.social.npcs[id]
	var route: Dictionary = sim.services.npc_agency._route(npc,str(npc.location),destination)
	if route.is_empty(): return false
	if kind=="buy":
		var shop: Dictionary=sim.catalog.shops.get(str(payload.get("shop","")),{})
		var clock: Dictionary = sim.calendar.snapshot(_now()+int(route.minutes)+minutes)
		var hours: Array = shop.get("hours",[0,0])
		if not int(clock.weekday) in shop.get("weekdays",[1,2,3,4,5,6,7]) or not Rules.in_window(int(clock.minute_of_day),int(hours[0]),int(hours[1])): return false
	var priority := 85 if kind in ["terminate","emergency"] else 75 if kind=="prenatal_care" else 55
	return sim.services.npc_planner.submit("reproduction",id,kind,destination,minutes,priority,payload)

func start(request: Dictionary) -> bool:
	var id := str(request.id)
	var kind := str(request.kind)
	var destination := str(request.destination)
	var payload: Dictionary = request.payload
	var jobs: Dictionary = sim.state.npc_reproduction.jobs
	if jobs.has(id) or jobs.size()>=int(_manager().rules().max_jobs): return false
	var npc: Dictionary = sim.state.social.npcs[id]
	var route: Dictionary = request.route
	if int(npc.money)<int(route.cost): return false
	var saved_pin:=int(npc.pinned_until)
	var saved_activity:=str(npc.activity)
	sim.services.npc_agency._cancel(npc,"personal_errand")
	npc.money-=int(route.cost)
	var due:=_now()+int(route.minutes)+int(request.minutes)
	jobs[id]={"id":_manager().next_id("npc_job_"),"npc":id,"kind":kind,"destination":destination,
		"origin":str(npc.location),"created":_now(),"arrival":_now()+int(route.minutes),"due":due,
		"phase":"travel" if int(route.minutes)>0 else "action","previous_pin":saved_pin,"previous_activity":saved_activity,
		"reserved_until":due+1,"payload":payload.duplicate(true)}
	npc.pinned_until=due+1
	npc.activity="personal_travel" if int(route.minutes)>0 else "personal_errand"
	npc.decision={"reason":"personal_errand","committed":false}
	_manager().log_event("job_started",{"npc":id,"kind":kind,"job":jobs[id].id,"destination":destination})
	return true

func buy(id: String, item: String, quantity: int) -> bool:
	var npc: Dictionary=sim.state.social.npcs[id]
	var choices: Array=[]
	for shop_id in sim.catalog.shops:
		var shop: Dictionary=sim.catalog.shops[shop_id]
		var stock: Dictionary=sim.state.economy.shop_stock.get(shop_id,shop.get("stock",{}))
		if int(stock.get(item,0))<quantity: continue
		var price:=maxi(0,int(round(float(sim.catalog.items[item].price)*float(shop.get("price_multiplier",1)))))
		if int(npc.money)<price*quantity: continue
		var destination:=str(shop.get("location",""))
		var route: Dictionary=sim.services.npc_agency._route(npc,str(npc.location),destination)
		if route.is_empty() or int(npc.money)<price*quantity+int(route.cost): continue
		choices.append({"id":shop_id,"destination":destination,"minutes":int(route.minutes),"price":price})
	choices.sort_custom(func(a,b): return a.minutes<b.minutes if a.minutes!=b.minutes else str(a.id)<str(b.id))
	for choice in choices:
		if schedule(id,"buy",str(choice.destination),int(_manager().rules().shop_minutes),{"item":item,"quantity":quantity,"shop":choice.id}): return true
	return false

func recheck() -> void:
	for id in sim.state.npc_reproduction.jobs.keys():
		var job: Dictionary=sim.state.npc_reproduction.jobs[id]
		var npc: Dictionary=sim.state.social.npcs[id]
		var reason:=Context.available(sim,str(id),maxi(0,int(job.due)-_now()),int(job.reserved_until),true)
		var expected:=str(job.origin) if job.phase=="travel" else str(job.destination)
		if npc.location!=expected or int(npc.pinned_until)!=int(job.reserved_until): reason="participant_moved"
		if _now()>int(job.due): reason="job_expired"
		if not reason.is_empty(): finish(str(id),false,reason)

func tick(minute: int) -> void:
	recheck()
	for id in sim.state.npc_reproduction.jobs.keys():
		var job: Dictionary=sim.state.npc_reproduction.jobs[id]
		if job.phase=="travel" and minute>=int(job.arrival):
			sim.state.social.npcs[id].location=job.destination
			sim.state.social.npcs[id].activity="personal_errand"
			job.phase="action"
		if minute<int(job.due): continue
		var copy:=job.duplicate(true)
		# A failed nested completion rolls back its own mutations, not the world's elapsed time.
		var before: Dictionary=sim.state.duplicate(true)
		var rng_before: int=sim.rng.state
		var event_count: int=sim.pending_events.size()
		var result:=_complete(copy)
		if not result.ok:
			sim.state=before
			sim.rng.state=rng_before
			sim.pending_events.resize(event_count)
		finish(str(id),bool(result.ok),str(result.get("error","")))

func _complete(job: Dictionary) -> Dictionary:
	var id:=str(job.npc)
	var payload: Dictionary=job.payload
	var repro=sim.services.reproduction
	if payload.has("pregnancy") and repro.pregnancy(id).get("id","")!=payload.pregnancy: return Rules.fail("stale_pregnancy_job")
	match str(job.kind):
		"buy":
			var shop: Dictionary=sim.catalog.shops[payload.shop]
			if str(shop.get("location",""))!=str(job.destination) or not sim.services.world.is_open(shop): return Rules.fail("shop_closed")
			if not sim.state.economy.shop_stock.has(payload.shop): sim.state.economy.shop_stock[payload.shop]=shop.stock.duplicate(true)
			var stock: Dictionary=sim.state.economy.shop_stock[payload.shop]
			var quantity:=int(payload.quantity)
			var price:=maxi(0,int(round(float(sim.catalog.items[payload.item].price)*float(shop.get("price_multiplier",1)))))
			var npc: Dictionary=sim.state.social.npcs[id]
			if int(stock.get(payload.item,0))<quantity: return Rules.fail("out_of_stock")
			if int(npc.money)<price*quantity: return Rules.fail("insufficient_funds")
			npc.money-=price*quantity
			stock[payload.item]-=quantity
			npc.inventory[payload.item]=int(npc.inventory.get(payload.item,0))+quantity
			_manager().log_event("supply_bought",{"npc":id,"item":payload.item,"quantity":quantity,"cost":price*quantity})
			return Rules.ok()
		"contraception": return repro._contraception(id,str(payload.method),false)
		"emergency": return repro._emergency(id,false)
		"test": return repro._test(id,false)
		"terminate": return repro._decision(id,"terminate",true,false)
		"procedure": return repro._procedure(id,str(payload.procedure),true,false)
		"prenatal_care": return sim.services.health.prenatal_care(id,id,false)
		"support_case": return sim.services.child_support.execute("file_enforcement",{"id":payload.obligation,"actor":id})
		"visit_family": return Rules.ok()
	return Rules.fail("unknown_npc_reproductive_job")

func finish(id: String, success: bool, reason: String) -> void:
	var job: Dictionary=sim.state.npc_reproduction.jobs[id]
	if success and job.kind=="contraception" and job.payload.get("method","")=="pill": _manager().remember_dose(id)
	if success and job.kind=="terminate" and sim.state.npc_reproduction.decisions.has(str(job.payload.get("pregnancy",""))):
		sim.state.npc_reproduction.decisions[job.payload.pregnancy].applied=true
	var npc: Dictionary=sim.state.social.npcs[id]
	if int(npc.pinned_until)==int(job.reserved_until): npc.pinned_until=int(job.previous_pin)
	if npc.activity in ["personal_errand","personal_travel"]: npc.activity=str(job.previous_activity)
	npc.decision={"reason":"personal_errand_completed" if success else reason,"committed":false}
	_manager().log_event("job_completed" if success else "job_interrupted",{"npc":id,"kind":job.kind,"job":job.id,"reason":reason})
	sim.state.npc_reproduction.jobs.erase(id)
