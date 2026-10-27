extends "res://scripts/mechanics/core/module.gd"
## Bounded autonomous decisions. No player actor, wallet, inventory or modal scene is used.
const Context = preload("res://scripts/mechanics/npc_reproductive_context.gd")
const Encounters = preload("res://scripts/mechanics/npc_private_encounters.gd")
const Jobs = preload("res://scripts/mechanics/npc_reproductive_jobs.gd")
const Check = preload("res://scripts/mechanics/core/npc_reproductive_validation.gd")
var encounters
var jobs

static func defaults() -> Dictionary:
	return {"version":1,"enabled":true,"sessions":{},"jobs":{},"routines":{},"policies":{},"decisions":{},
		"cooldowns":{},"next_id":1,"next_scan":0,"next_health":0,"cursor":0,"history":[]}

static func policy_defaults() -> Dictionary:
	return {"enabled":true,"preferred_method":"auto","pregnancy_decision":"auto","parenthood":"auto","procedure":"none","emergency":true}

func _init(simulation) -> void:
	super(simulation)
	encounters=Encounters.new(simulation)
	jobs=Jobs.new(simulation)

func rules() -> Dictionary:
	return definition("npc_reproduction_rules","simulation")

func _now() -> int:
	return int(sim.state.clock.total_minutes)

func enabled() -> bool:
	return sim.state.npc_reproduction.enabled and sim.services.npc_agency.enabled()

func policy(id: String) -> Dictionary:
	return sim.state.npc_reproduction.policies.get(id,policy_defaults()).duplicate(true)

func next_id(prefix: String) -> String:
	var id:=prefix+str(int(sim.state.npc_reproduction.next_id))
	sim.state.npc_reproduction.next_id+=1
	return id

func log_event(kind: String, data: Dictionary) -> void:
	sim.state.npc_reproduction.history.append({"kind":kind,"minute":_now(),"data":data.duplicate(true)})
	while sim.state.npc_reproduction.history.size()>int(rules().history_limit): sim.state.npc_reproduction.history.pop_front()
	emit_event("npc_reproduction_"+kind,data)

func execute(operation: String, args: Dictionary) -> Dictionary:
	match operation:
		"inspect": return Rules.ok(sim.state.npc_reproduction.duplicate(true))
		"enable", "disable":
			sim.state.npc_reproduction.enabled=operation=="enable"
			recheck()
			return Rules.ok()
		"configure":
			var id:=str(args.get("id",""))
			if not sim.state.social.npcs.has(id) or not args.get("values") is Dictionary: return Rules.fail("invalid_npc_reproductive_policy")
			var result:=policy(id)
			for key in args.values:
				if not result.has(key): return Rules.fail("invalid_npc_reproductive_policy")
				result[key]=args.values[key]
			if not Check.policy_error(result).is_empty(): return Rules.fail("invalid_npc_reproductive_policy")
			sim.state.npc_reproduction.policies[id]=result
			recheck()
			return Rules.ok()
	return Rules.fail("unknown_operation")

func busy(id: String) -> bool:
	if sim.state.npc_reproduction.jobs.has(id): return true
	for session in sim.state.npc_reproduction.sessions.values():
		if id in [session.a,session.b]: return true
	return false

func _free(id: String, minutes: int = 0, medical: bool = false) -> bool:
	return policy(id).enabled and not busy(id) and Context.available(sim,id,minutes,0,medical).is_empty()

func recheck() -> void:
	if not enabled():
		for id in sim.state.npc_reproduction.sessions.keys(): encounters.finish(str(id),"interrupted","autonomy_disabled")
		for id in sim.state.npc_reproduction.jobs.keys(): jobs.finish(str(id),false,"autonomy_disabled")
		sim.state.npc_reproduction.routines.clear()
		return
	for id in sim.state.npc_reproduction.sessions.keys():
		var s: Dictionary=sim.state.npc_reproduction.sessions[id]
		if not policy(str(s.a)).enabled or not policy(str(s.b)).enabled: encounters.finish(str(id),"interrupted","autonomy_disabled")
	for id in sim.state.npc_reproduction.jobs.keys():
		if not policy(str(id)).enabled: jobs.finish(str(id),false,"autonomy_disabled")
	for id in sim.state.npc_reproduction.routines.keys():
		var r: Dictionary=sim.services.reproduction.view(str(id))
		if not policy(str(id)).enabled or r.method!="pill" or preferred_method(str(id),r)!="pill" or not r.pregnancy.is_empty(): sim.state.npc_reproduction.routines.erase(id)
	encounters.recheck()
	jobs.recheck()

func tick(minute: int) -> void:
	if not enabled():
		if not sim.state.npc_reproduction.sessions.is_empty() or not sim.state.npc_reproduction.jobs.is_empty(): recheck()
		return
	jobs.tick(minute)
	_routines(minute)
	encounters.tick(minute)
	if minute>=int(sim.state.npc_reproduction.next_health):
		sim.state.npc_reproduction.next_health=minute+int(rules().health_minutes)
		_pregnancies()
		_maintenance()
		_care()
		_support()
	if minute>=int(sim.state.npc_reproduction.next_scan):
		sim.state.npc_reproduction.next_scan=minute+int(rules().scan_minutes)
		_meetings()
	sim.services.child_support.synchronize()

func _ids() -> Array:
	var ids: Array=sim.state.social.npcs.keys()
	ids.sort()
	return ids

func _romantic_context(id: String) -> bool:
	var npc: Dictionary=sim.state.social.npcs[id]
	for other in npc.mind.bonds:
		if other!="player" and float(npc.mind.bonds[other].interest)>=20: return true
	return false

func preferred_method(id: String, r: Dictionary) -> String:
	var preferred:=str(policy(id).preferred_method)
	if preferred=="auto":
		preferred="pill" if (r.method=="pill" and r.desire!="want") or (r.desire=="avoid" and r.can_gestate and sim.services.npc_personalities.f(sim.state.social.npcs[id],"prudence")>=0.6) else "barrier"
	return preferred

func remember_dose(id: String) -> void:
	var r: Dictionary=sim.services.reproduction.view(id)
	if r.method!="pill" or int(r.last_dose)<0 or preferred_method(id,r)!="pill": return
	sim.state.npc_reproduction.routines[id]={"due":int(r.last_dose)+1440,"next_try":int(r.last_dose)+1440}

func _routines(minute: int) -> void:
	for id in sim.state.npc_reproduction.routines.keys():
		var r: Dictionary=sim.services.reproduction.view(str(id))
		if not policy(str(id)).enabled or r.method!="pill" or preferred_method(str(id),r)!="pill" or not r.pregnancy.is_empty():
			sim.state.npc_reproduction.routines.erase(id)
			continue
		var routine: Dictionary=sim.state.npc_reproduction.routines[id]
		if minute<int(routine.next_try): continue
		var npc: Dictionary=sim.state.social.npcs[id]
		# A one-minute personal routine may occur during ordinary work; sleep or missing supplies cause a real lapse.
		routine.next_try=minute+int(rules().health_minutes)
		if npc.activity in ["sleep","recover"] or float(npc.health)<30 or int(npc.inventory.get("contraceptive_pill",0))<1 or int(npc.money)<int(sim.catalog.contraceptive_methods.pill.cost): continue
		var result: Dictionary=sim.services.reproduction._contraception(str(id),"pill",false)
		if result.ok:
			remember_dose(str(id))
			log_event("daily_contraception",{"npc":id})

func _meetings() -> void:
	if "romance" in sim.state.preferences.disabled_tags: return
	var hour:=int(sim.state.clock.hour)
	if hour<int(rules().opening_hour) or hour>=int(rules().closing_hour): return
	var ids:=_ids()
	if ids.is_empty(): return
	var start:=int(sim.state.npc_reproduction.cursor)%ids.size()
	var visited: Dictionary={}
	for offset in range(mini(ids.size(),int(rules().actor_budget))):
		var a:=str(ids[(start+offset)%ids.size()])
		if not _free(a): continue
		var first: Dictionary=sim.state.social.npcs[a]
		var known: Array=first.mind.bonds.keys()
		known.sort()
		var checked:=0
		for candidate in known:
			var b:=str(candidate)
			if b=="player" or not sim.state.social.npcs.has(b): continue
			if checked>=int(rules().pair_candidates): break
			checked+=1
			var key:=Context.pair_key(a,b)
			if visited.has(key): continue
			visited[key]=true
			if int(sim.state.npc_reproduction.cooldowns.get(key,0))>_now() or not _free(b): continue
			var second: Dictionary=sim.state.social.npcs[b]
			if first.location!=second.location: continue
			if not sim.services.social_rules.compatibility(a,b).data.mutual_attraction: continue
			var incoming: Dictionary=sim.services.npc_relationships.view(a,b)
			var outgoing: Dictionary=sim.services.npc_relationships.view(b,a)
			if minf(float(incoming.trust),float(outgoing.trust))<float(rules().courtship_trust): continue
			var relationship: Dictionary=sim.state.social.relationships.get(key,{})
			if relationship.get("status","")!="partner":
				var action:="invite_relationship" if sim.services.npc_relationships._ready(incoming) and sim.services.npc_relationships._ready(outgoing) else "court"
				var duration:=int(sim.catalog.agency_actions[action].minutes)
				if not _free(a,duration) or not _free(b,duration): continue
				if not str(sim.services.npc_relationships.forecast(a,b,action).blocked).is_empty(): continue
				sim.services.npc_agency._start(first,action,str(first.location),b,"relationship_intention")
				log_event("courtship_started",{"a":a,"b":b,"action":action})
				break
			if not Context.pair_blocked(sim,a,b,0).is_empty(): continue
			if sim.rng.randf()>float(rules().initiative_chance): continue
			if encounters.start(a,b): break
	sim.state.npc_reproduction.cursor=(start+int(rules().actor_budget))%ids.size()

func _response(p: Dictionary) -> void:
	if p.partner_response!="unasked": return
	var id:=str(p.partner)
	var npc: Dictionary=sim.state.social.npcs.get(id,{})
	if not npc.has("mind") or not npc.mind.boundaries.contact or not policy(id).enabled: return
	var preference: Dictionary=sim.services.reproduction.view(id)
	var own_policy:=policy(id)
	var support: bool=own_policy.parenthood=="retain"
	if own_policy.parenthood=="auto":
		support=preference.desire!="avoid" or (sim.services.npc_personalities.f(npc,"fairness")+sim.services.npc_personalities.f(npc,"sentimentality"))*0.5>=0.6
	sim.services.reproduction._response(str(p.target),id,"support" if support else "decline_parenthood")

func _pregnancies() -> void:
	for pregnancy_id in sim.state.reproduction.pregnancies.keys():
		var p: Dictionary=sim.state.reproduction.pregnancies[pregnancy_id]
		if p.status!="active" or not p.known or "player" in [p.target,p.partner] or not policy(str(p.target)).enabled: continue
		_response(p)
		if _now()<int(p.detected_at)+int(rules().decision_delay): continue
		var target:=str(p.target)
		var preference: Dictionary=sim.services.reproduction.view(target)
		var own_policy:=policy(target)
		if not sim.state.npc_reproduction.decisions.has(pregnancy_id):
			var decision:=str(own_policy.pregnancy_decision)
			if decision=="auto": decision="terminate" if preference.desire=="avoid" else "continue"
			var care:="relinquish" if own_policy.parenthood=="decline" else "retain"
			if decision=="adoption" and p.partner_response=="support":
				decision="continue"
				care="relinquish"
			sim.state.npc_reproduction.decisions[pregnancy_id]={"decision":decision,"care":care,"created":_now(),"next_try":_now(),"applied":false}
			log_event("pregnancy_choice",{"pregnancy":pregnancy_id,"target":target,"decision":decision,"care":care})
		var plan: Dictionary=sim.state.npc_reproduction.decisions[pregnancy_id]
		p.gestator_parenthood=plan.care
		if p.decision!="undecided":
			plan.applied=true
			if p.decision=="continue": _prenatal(p)
			continue
		if plan.decision=="terminate":
			if _now()-int(p.started)>=int(sim.catalog.reproduction_rules.simulation.termination_limit_days)*1440:
				plan.decision="continue" if p.partner_response=="support" else "adoption"
				plan.care="relinquish"
				p.gestator_parenthood=plan.care
			elif _now()>=int(plan.next_try) and _free(target,0,true):
				plan.next_try=_now()+int(rules().job_retry_minutes)
				if int(sim.state.social.npcs[target].money)>=int(sim.catalog.reproduction_rules.simulation.termination_cost):
					jobs.schedule(target,"terminate","clinic",int(sim.catalog.reproduction_rules.simulation.termination_minutes),{"pregnancy":pregnancy_id})
				continue
		if plan.decision!="terminate":
			var result: Dictionary=sim.services.reproduction._decision(target,str(plan.decision),true,false)
			plan.applied=result.ok

func _prenatal(p: Dictionary) -> void:
	var id:=str(p.target)
	var c: Dictionary=sim.state.conditions.get(id+":pregnancy",{})
	if int(c.get("next_care",0))>_now() or not _free(id,0,true) or int(sim.state.social.npcs[id].money)<30: return
	jobs.schedule(id,"prenatal_care","clinic",30,{"pregnancy":p.id})

func _maintenance() -> void:
	for id in _ids():
		id=str(id)
		var npc: Dictionary=sim.state.social.npcs[id]
		if not npc.has("mind") or not _free(id,0,true): continue
		var own_policy:=policy(id)
		var r: Dictionary=sim.services.reproduction.view(id)
		if not r.pregnancy.is_empty(): continue
		if own_policy.procedure!="none" and r.sterilization=="none":
			var spec: Dictionary=sim.catalog.reproductive_procedures[own_policy.procedure]
			if r.get(spec.capability,false) and int(npc.money)>=int(spec.cost)+int(rules().reserve_money):
				if jobs.schedule(id,"procedure","clinic",int(spec.minutes),{"procedure":own_policy.procedure}): continue
		var pending:=false
		for e in sim.state.reproduction.exposures.values():
			if e.target==id and e.partner!="player" and e.status=="pending" and not e.emergency and _now()<int(e.resolve_at): pending=true
		if pending and own_policy.emergency and r.desire=="avoid" and sim.services.npc_personalities.f(npc,"prudence")>=0.5:
			if int(npc.inventory.get("emergency_contraception",0))>0:
				if jobs.schedule(id,"emergency",str(npc.location),1): continue
			elif jobs.buy(id,"emergency_contraception",1): continue
		if not _romantic_context(id): continue
		var preferred:=preferred_method(id,r)
		if r.method!="none" and preferred!=r.method and (own_policy.preferred_method!="auto" or r.desire=="want"):
			var clinical: bool=not sim.catalog.contraceptive_methods[r.method].daily
			if jobs.schedule(id,"contraception","clinic" if clinical else str(npc.location),45 if clinical else 1,{"method":"none"}): continue
		if r.can_gestate and preferred in ["pill","iud","implant"] and r.method in ["none",preferred]:
			var method: Dictionary=sim.catalog.contraceptive_methods[preferred]
			if preferred=="pill":
				if int(npc.inventory.get("contraceptive_pill",0))==0:
					if jobs.buy(id,"contraceptive_pill",int(rules().pill_stock)): continue
				elif r.method!="pill" and (int(r.last_dose)<0 or _now()-int(r.last_dose)>=1440):
					if jobs.schedule(id,"contraception",str(npc.location),1,{"method":preferred}): continue
				elif r.method=="pill" and not sim.state.npc_reproduction.routines.has(id): remember_dose(id)
			elif not r.method_active and int(npc.money)>=int(method.cost)+int(rules().reserve_money):
				if jobs.schedule(id,"contraception","clinic",int(method.minutes),{"method":preferred}): continue
		if (r.requires_protection or preferred=="barrier") and not r.sterile and int(npc.inventory.get("barrier_protection",0))==0:
			jobs.buy(id,"barrier_protection",int(rules().barrier_stock))

func _care() -> void:
	for member in sim.state.family.members.values():
		if "player" in member.parents or member.stage=="adult" or not member.task.is_empty(): continue
		var guardians: Array=member.get("guardians",member.parents)
		if guardians.is_empty(): continue
		var need:=""
		for key in ["food","hygiene","rest","attention"]:
			if float(member.needs[key])<45 and (need.is_empty() or float(member.needs[key])<float(member.needs[need])): need=key
		if need.is_empty(): continue
		var action:=str({"food":"feed","hygiene":"wash","rest":"settle","attention":"play"}[need])
		var duration:=int(sim.catalog.family_actions[action].minutes)
		for id in guardians:
			if not _free(str(id),duration,true) or float(sim.state.social.npcs[id].needs.energy)<25: continue
			if sim.state.social.npcs[id].location==member.home:
				member.assignments[need]=id
				sim.services.family._autonomy(member)
				if not member.task.is_empty(): break
			elif jobs.schedule(str(id),"visit_family",str(member.home),1,{"member":member.id}): break

func _support() -> void:
	for o in sim.state.child_support.obligations.values():
		if "player" in [o.payer,o.recipient] or o.recipient=="public_care" or int(o.arrears)<=0 or o.order or int(o.enforcement_due)>0: continue
		var id:=str(o.recipient)
		if not _free(id,int(rules().paperwork_minutes),true): continue
		if int(sim.state.social.npcs[id].money)<int(sim.catalog.child_support_rules.simulation.filing_cost): continue
		jobs.schedule(id,"support_case",str(sim.state.social.npcs[id].home),int(rules().paperwork_minutes),{"obligation":o.id})
