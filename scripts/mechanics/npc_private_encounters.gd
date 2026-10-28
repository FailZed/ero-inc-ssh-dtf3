extends "res://scripts/mechanics/core/module.gd"
const Context = preload("res://scripts/mechanics/npc_reproductive_context.gd")

func _now() -> int:
	return int(sim.state.clock.total_minutes)

func _manager():
	return sim.services.npc_reproduction

func start(a: String, b: String) -> bool:
	var rules: Dictionary = _manager().rules()
	if sim.state.npc_reproduction.sessions.size() >= int(rules.max_sessions): return false
	var key := Context.pair_key(a,b)
	if int(sim.state.npc_reproduction.cooldowns.get(key,0)) > _now(): return false
	if not Context.pair_blocked(sim,a,b,0).is_empty(): return false
	var first: Dictionary = sim.state.social.npcs[a]
	var second: Dictionary = sim.state.social.npcs[b]
	if first.location != second.location: return false
	var venue := str(first.home)
	if not sim.catalog.locations.has(venue) or sim.catalog.locations[venue].get("public",false): return false
	var routes := {}
	var travel := 0
	for id in [a,b]:
		var npc: Dictionary = sim.state.social.npcs[id]
		var route: Dictionary = sim.services.npc_agency._route(npc,str(npc.location),venue,-1,false,venue)
		if route.is_empty(): return false
		routes[id] = route
		travel = maxi(travel,int(route.minutes))
	var duration := travel + int(sim.catalog.reproduction_rules.simulation.session_minutes) + int(rules.stage_minutes)*6 + 2
	if not Context.pair_blocked(sim,a,b,duration).is_empty(): return false
	for actor_id in [a,b]:
		if not sim.services.npc_planner.calendar.conflict(str(actor_id),venue,duration).is_empty(): return false
	var id: String = _manager().next_id("npc_encounter_")
	var pin := _now()+duration+1
	var saved := {}
	for actor_id in [a,b]:
		var npc: Dictionary = sim.state.social.npcs[actor_id]
		saved[actor_id] = {"pin":int(npc.pinned_until),"activity":str(npc.activity),"origin":str(npc.location),"arrival":_now()+int(routes[actor_id].minutes),"arrived":int(routes[actor_id].minutes)==0}
		sim.services.npc_agency._cancel(npc,"private_invitation")
		npc.money -= int(routes[actor_id].cost)
		npc.pinned_until = pin
		npc.activity = "private_travel" if int(routes[actor_id].minutes)>0 else "private_time"
		npc.decision = {"reason":"private_invitation","committed":false}
	sim.state.npc_reproduction.sessions[id] = {"id":id,"a":a,"b":b,"venue":venue,"scope":"npc_home:"+a,
		"stage":"travelling" if travel>0 else "invitation","revision":1,"created":_now(),"next_step":_now()+maxi(travel,int(rules.stage_minutes)),
		"reserved_until":pin,"saved":saved,"protection":"","barrier_owner":"","potential_conception":false,
		"intended":false,"resolved":false,"exposure":"","due":0}
	_manager().log_event("encounter_started",{"session":id,"a":a,"b":b,"venue":venue})
	_request(sim.state.npc_reproduction.sessions[id])
	return true

func _request(s: Dictionary) -> void:
	if not sim.catalog.intimacy_stages.has(s.stage): return
	emit_event("npc_intimacy_scene_requested",{"session":s.id,"revision":s.revision,"stage":s.stage,
		"hook":sim.catalog.intimacy_stages[s.stage].hook,"participants":[s.a,s.b],"scope":s.scope})

func _stage(s: Dictionary, stage: String, duration: int = -1) -> void:
	s.stage = stage
	s.revision += 1
	s.next_step = _now() + (int(_manager().rules().stage_minutes) if duration<0 else duration)
	_request(s)

func _protection(s: Dictionary) -> String:
	var a: Dictionary = sim.services.reproduction.view(str(s.a))
	var b: Dictionary = sim.services.reproduction.view(str(s.b))
	var pairing: Dictionary = sim.services.reproduction.risk(str(s.a),str(s.b))
	var pregnant: bool = not a.pregnancy.is_empty() or not b.pregnancy.is_empty()
	s.potential_conception = not str(pairing.target).is_empty() and not pregnant and not "pregnancy" in sim.state.preferences.disabled_tags
	s.intended = s.potential_conception and a.desire=="want" and b.desire=="want"
	if not s.potential_conception: return "non_reproductive"
	var required: bool = a.requires_protection or b.requires_protection
	var method: bool = not str(pairing.target).is_empty() and sim.services.reproduction.view(str(pairing.target)).method_active
	if s.intended and not required: return "unprotected"
	if method: return "regular_method"
	for id in [s.a,s.b]:
		if int(sim.state.social.npcs[id].inventory.get("barrier_protection",0)) > 0:
			s.barrier_owner = id
			return "barrier"
	if required: return "non_reproductive"
	# The same explicit boundaries apply; neither actor is forced to abandon required protection.
	return "unprotected"

func recheck() -> void:
	for id in sim.state.npc_reproduction.sessions.keys():
		var s: Dictionary = sim.state.npc_reproduction.sessions[id]
		var remaining := maxi(0,int(s.reserved_until)-_now()-1)
		var reason := Context.pair_blocked(sim,str(s.a),str(s.b),remaining,int(s.reserved_until))
		if s.resolved and reason in ["npc_needs_recovery","reproductive_recovery"]: reason = ""
		for actor_id in [s.a,s.b]:
			var npc: Dictionary = sim.state.social.npcs[actor_id]
			var expected := str(s.venue) if s.saved[actor_id].arrived else str(s.saved[actor_id].origin)
			if npc.location != expected or int(npc.pinned_until) != int(s.reserved_until): reason = "participant_moved"
		if _now() >= int(s.reserved_until): reason = "reservation_expired"
		if s.protection=="unprotected" and not s.resolved:
			if sim.services.reproduction.view(str(s.a)).requires_protection or sim.services.reproduction.view(str(s.b)).requires_protection: reason = "protection_required"
		if s.protection=="regular_method" and not s.resolved:
			var pairing: Dictionary = sim.services.reproduction.risk(str(s.a),str(s.b))
			if str(pairing.target).is_empty() or not sim.services.reproduction.view(str(pairing.target)).method_active: reason = "contraception_not_active"
		if not reason.is_empty(): finish(id,"interrupted",reason)

func tick(minute: int) -> void:
	recheck()
	for id in sim.state.npc_reproduction.sessions.keys():
		var s: Dictionary = sim.state.npc_reproduction.sessions[id]
		if s.stage=="travelling":
			for actor_id in [s.a,s.b]:
				if not s.saved[actor_id].arrived and minute>=int(s.saved[actor_id].arrival):
					sim.state.social.npcs[actor_id].location=s.venue
					sim.state.social.npcs[actor_id].activity="private_time"
					s.saved[actor_id].arrived=true
		if minute<int(s.next_step): continue
		match s.stage:
			"travelling": _stage(s,"invitation")
			"invitation": _stage(s,"discussion")
			"discussion":
				s.protection=_protection(s)
				_stage(s,"protection")
			"protection": _stage(s,"ready")
			"ready":
				if not sim.services.adult_health.try_intimacy(str(s.a),str(s.b)):
					finish(id,"interrupted","adult_health_difficulty")
					continue
				if s.protection=="barrier":
					var owner: Dictionary = sim.state.social.npcs[s.barrier_owner]
					if int(owner.inventory.get("barrier_protection",0))<1:
						finish(id,"interrupted","missing_contraception")
						continue
					owner.inventory.barrier_protection-=1
					if owner.inventory.barrier_protection==0: owner.inventory.erase("barrier_protection")
				s.due=minute+int(sim.catalog.reproduction_rules.simulation.session_minutes)
				_stage(s,"active",int(sim.catalog.reproduction_rules.simulation.session_minutes))
			"active":
				sim.services.adult_health.contact(str(s.a),str(s.b),str(s.protection),"npc:"+str(s.id))
				if s.potential_conception and s.protection!="non_reproductive": s.exposure=sim.services.reproduction.expose(str(s.a),str(s.b),str(s.protection),bool(s.intended),str(s.id))
				s.resolved=true
				for pair in [[s.a,s.b],[s.b,s.a]]:
					var npc: Dictionary = sim.state.social.npcs[pair[0]]
					npc.needs.energy=maxf(0,float(npc.needs.energy)-float(sim.catalog.reproduction_rules.simulation.session_energy))
					sim.services.npc_relationships._change(sim.services.npc_relationships._bond(str(pair[0]),str(pair[1])),{"comfort":2,"affection":2})
					sim.services.social.remember(str(pair[0]),"private_time",{"other":pair[1],"session":s.id})
				sim.services.npc_relationships._project(str(s.a),str(s.b))
				_stage(s,"aftercare")
			"aftercare": finish(id,"completed","")

func finish(id: String, status: String, reason: String) -> void:
	var s: Dictionary = sim.state.npc_reproduction.sessions[id]
	for actor_id in [s.a,s.b]:
		var npc: Dictionary = sim.state.social.npcs[actor_id]
		if int(npc.pinned_until)==int(s.reserved_until): npc.pinned_until=int(s.saved[actor_id].pin)
		if npc.activity in ["private_time","private_travel"]: npc.activity=str(s.saved[actor_id].activity)
	sim.state.npc_reproduction.cooldowns[Context.pair_key(str(s.a),str(s.b))]=_now()+int(_manager().rules().pair_cooldown)
	_manager().log_event("encounter_ended",{"session":id,"a":s.a,"b":s.b,"status":status,"reason":reason,"protection":s.protection,"intended":s.intended,"resolved":s.resolved,"exposure":s.exposure})
	sim.state.npc_reproduction.sessions.erase(id)
