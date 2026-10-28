extends "res://scripts/mechanics/core/module.gd"
## Reserved travel/work sessions. Production and pay follow actual attendance.
const Check = preload("res://scripts/mechanics/core/validation.gd")

static func defaults(location: String) -> Dictionary:
	return {"location":location,"hour":18,"weekdays":[1,2,3,4,5],"sessions":{},"minutes":{},"day":-1,"history":[]}

func _log(group: Dictionary, npc: String, worked: int, paid: int, reason: String) -> void:
	group.work.history.append({"npc":npc,"minute":sim.state.clock.total_minutes,"worked":worked,"paid":paid,"reason":reason})
	while group.work.history.size() > 20: group.work.history.pop_front()

func _route(npc: Dictionary, destination: String) -> Dictionary:
	var queue: Array = [{"id":str(npc.location),"minutes":0,"cost":0}]
	var labels := {str(npc.location):[{"minutes":0,"cost":0}]}
	var context: Dictionary = sim.services.npc_behavior.context(npc)
	while not queue.is_empty():
		queue.sort_custom(func(a,b): return int(a.minutes) < int(b.minutes) if a.minutes != b.minutes else int(a.cost) < int(b.cost))
		var current: Dictionary = queue.pop_front()
		if current.id == destination: return current
		for id in definition("locations",str(current.id)).get("routes",{}):
			var edge: Dictionary = definition("locations",str(current.id)).routes[id]
			var duration := int(current.minutes)+int(edge.get("minutes",0))
			var cost := int(current.cost)+int(edge.get("cost",0))
			if cost > int(npc.money) or not _open_at(str(id),int(sim.state.clock.total_minutes)+duration,str(npc.id)): continue
			context.clock = sim.calendar.snapshot(int(sim.state.clock.total_minutes)+duration)
			if not Rules.check(context,edge.get("requirements",{})) or not Rules.check(context,definition("locations",str(id)).get("requirements",{})): continue
			if not labels.has(id): labels[id] = []
			var dominated := false
			for label in labels[id]:
				if int(label.minutes) <= duration and int(label.cost) <= cost: dominated = true
			if dominated: continue
			labels[id].append({"minutes":duration,"cost":cost})
			queue.append({"id":str(id),"minutes":duration,"cost":cost})
	return {}

func _weekday(days: Array, day: int) -> bool:
	for value in days:
		if int(value) == day: return true
	return false

func _open_at(location: String, minute: int, actor_id: String) -> bool:
	return sim.services.world.actor_availability(location,actor_id,minute).ok

func _care_reserved(npc: Dictionary) -> bool:
	var id := str(npc.id)
	if sim.services.has("npc_planner") and not sim.services.npc_planner.active_owner(id).is_empty(): return true
	return sim.services.has("adult_health") and sim.services.adult_health.enabled() and sim.services.adult_health.view(id).get("urgent",false)

func _free(npc: Dictionary, now: int, end: int) -> bool:
	if _care_reserved(npc): return false
	if npc.health <= 30 or float(npc.needs.energy) < 30 or float(npc.needs.satiety) < 30: return false
	if int(npc.pinned_until) > now or npc.activity in ["sleep","recover","eat","family_care"]: return false
	var context: Dictionary = sim.services.npc_behavior.context(npc)
	for minute in range(now,end+1):
		var clock: Dictionary = sim.calendar.snapshot(minute)
		context.clock = clock
		for entry in npc.schedule:
			if not entry.get("mandatory",entry.get("activity","") in ["work","study"]): continue
			var hours: Array = entry.get("hours",[0,0])
			if _weekday(entry.get("weekdays",[1,2,3,4,5,6,7]),int(clock.weekday)) and Rules.in_window(int(clock.minute_of_day),int(hours[0]),int(hours[1])) and Rules.check(context,entry.get("requirements",{})): return false
	return true

func cancel(group: Dictionary, id: String, reason: String) -> void:
	if not group.work.sessions.has(id): return
	var session: Dictionary = group.work.sessions[id]
	var npc: Dictionary = sim.state.social.npcs[id]
	var paid := floori(float(session.wage)*int(session.worked)/60.0)
	npc.money += paid
	group.budget += int(session.wage)-paid
	if int(npc.pinned_until) == int(session.ends)+1:
		npc.pinned_until = 0
		if npc.activity in ["club_work","travel"]: npc.activity = "rest"
	if reason == "completed": group.morale = minf(100,float(group.morale)+0.25)
	_log(group,id,int(session.worked),paid,reason)
	group.work.sessions.erase(id)

func tick_group(id: String, group: Dictionary, minute: int) -> void:
	var work: Dictionary = group.work
	if int(work.day) != int(sim.state.clock.day_index):
		work.day = int(sim.state.clock.day_index)
		work.minutes.clear()
	var participants: Array = work.sessions.keys()
	participants.sort()
	for npc_id in participants:
		var npc: Dictionary = sim.state.social.npcs[npc_id]
		var session: Dictionary = work.sessions[npc_id]
		if _care_reserved(npc):
			cancel(group,str(npc_id),"care_priority")
			continue
		if not group.members.has(npc_id) or group.members[npc_id].task != session.task or int(npc.pinned_until) != int(session.ends)+1 or float(npc.health) <= 30 or minf(float(npc.needs.energy),float(npc.needs.satiety)) < 15:
			cancel(group,str(npc_id),"interrupted")
			continue
		if session.phase == "travel":
			if npc.activity != "travel" or npc.location != session.origin:
				cancel(group,str(npc_id),"travel_interrupted")
				continue
			if minute < int(session.arrival): continue
			if not _open_at(str(work.location),minute,str(npc_id)):
				cancel(group,str(npc_id),"location_closed")
				continue
			npc.location = str(work.location)
			npc.activity = "club_work"
			session.phase = "work"
			continue
		if npc.location != work.location or npc.activity != "club_work":
			cancel(group,str(npc_id),"left_workplace")
			continue
		session.worked += 1
		work.minutes[npc_id] = int(work.minutes.get(npc_id,0))+1
		npc.needs.energy = maxf(0,float(npc.needs.energy)-0.06)
		var effort: float = (1.0+float(npc.stats.get("intellect",5))/10.0)*sim.services.institutions.productivity(group,str(npc_id))/60.0
		contribute(id,group,str(session.task),effort)
		if int(session.worked) >= 60:
			cancel(group,str(npc_id),"completed")
			emit_event("club_shift_completed",{"id":id,"npc":str(npc_id),"minutes":60})
	var clock: Dictionary = sim.state.clock
	if minute % 30 != 0 or not _weekday(work.weekdays,int(clock.weekday)) or int(clock.hour) < int(work.hour) or int(clock.hour) >= int(work.hour)+2: return
	var ids: Array = group.members.keys()
	ids.sort()
	for npc_id in ids:
		if work.sessions.has(npc_id) or int(work.minutes.get(npc_id,0)) >= 120 or group.members[npc_id].task == "idle": continue
		var npc: Dictionary = sim.state.social.npcs[npc_id]
		var route := _route(npc,str(work.location))
		if route.is_empty(): continue
		var arrival := minute+int(route.minutes)
		var ending := arrival+60
		if not _open_at(str(work.location),arrival,str(npc_id)) or not _open_at(str(work.location),ending-1,str(npc_id)): continue
		if not preload("res://scripts/mechanics/core/service_window.gd").is_open(sim,definition("locations",str(work.location)),arrival,ending): continue
		if int(sim.calendar.snapshot(ending).minute_of_day) > (int(work.hour)+2)*60 or not _free(npc,minute,ending): continue
		var wage := int(group.policies.wage)
		if int(group.budget) < wage:
			if int(work.get("unpaid_day",-1)) != int(clock.day_index):
				work.unpaid_day = int(clock.day_index)
				group.morale = maxf(0,float(group.morale)-5)
				emit_event("club_wages_unpaid",{"id":id,"required":wage})
			continue
		if npc.has("mind") and sim.services.has("npc_agency"): sim.services.npc_agency._cancel(npc,"club_shift")
		npc.money -= int(route.cost)
		group.budget -= wage
		work.sessions[npc_id] = {"origin":str(npc.location),"arrival":arrival,"ends":ending,"phase":"travel","task":str(group.members[npc_id].task),"worked":0,"wage":wage}
		npc.pinned_until = ending+1
		npc.activity = "travel"
		if arrival == minute:
			work.sessions[npc_id].phase = "work"
			npc.activity = "club_work"

func contribute(id: String, group: Dictionary, task: String, effort: float) -> void:
	var active: Array = []
	for campaign in group.campaigns:
		if group.campaigns[campaign].status == "active": active.append(campaign)
	active.sort()
	# Half the effort supports the current common campaign; it is never copied to every campaign.
	if not active.is_empty():
		var campaign_id := str(active[0])
		var spec := definition("campaigns",campaign_id)
		var progress: Dictionary = group.campaigns[campaign_id]
		progress.progress += effort*0.5*(1.25 if group.policies.focus == spec.get("focus","") else 1.0)
		effort *= 0.5
		while int(progress.stage) < spec.stages.size() and progress.progress >= float(spec.stages[int(progress.stage)].effort):
			progress.progress -= float(spec.stages[int(progress.stage)].effort)
			progress.stage += 1
			emit_event("club_campaign_stage",{"id":id,"campaign":campaign_id,"stage":progress.stage})
		if int(progress.stage) >= spec.stages.size(): progress.status = "completed"
	match task:
		"clean": group.cleanliness = minf(100,float(group.cleanliness)+effort*5)
		"fundraise":
			group.work.fund_credit = float(group.work.get("fund_credit",0))+effort*10
			var earned := floori(group.work.fund_credit)
			group.budget += earned
			group.work.fund_credit -= earned
		"article":
			group.work.article_credit = float(group.work.get("article_credit",0))+effort
			var articles := floori(group.work.article_credit)
			group.articles += articles
			group.work.article_credit -= articles
			group.reputation += effort
		_:
			if group.projects.has(task) and not group.projects[task].completed:
				var progress: Dictionary = group.projects[task]
				var spec := definition("group_projects",task)
				progress.progress += effort
				if progress.progress >= float(spec.effort):
					progress.completed = true
					group.reputation += float(spec.get("reputation",10))
					group.budget += int(spec.get("reward",0))
					emit_event("group_project_completed",{"organization":id,"project":task})

static func state_error(state: Dictionary, catalog: Dictionary) -> String:
	for group in state.organizations.values():
		var work: Variant = group.get("work")
		if not Check.fields(work,{"location":"s","hour":"n","weekdays":"a","sessions":"d","minutes":"d","day":"n","history":"a"}): return "invalid_club_work"
		if not catalog.locations.has(work.location) or int(work.hour) != work.hour or work.hour < 6 or work.hour > 20 or work.history.size() > 20 or work.weekdays.is_empty(): return "invalid_club_work"
		if int(work.day) != work.day or work.day < -1 or work.day > int(state.clock.total_minutes)/1440: return "invalid_club_day"
		for credit in ["fund_credit","article_credit"]:
			if not Check.number(work.get(credit,0)) or float(work.get(credit,0)) < 0 or float(work.get(credit,0)) >= 1: return "invalid_club_credit"
		for npc in work.minutes:
			if not state.social.npcs.has(npc) or not Check.number(work.minutes[npc]) or int(work.minutes[npc]) != work.minutes[npc] or work.minutes[npc] < 0 or work.minutes[npc] > 120: return "invalid_club_minutes"
		for entry in work.history:
			if not Check.fields(entry,{"npc":"s","minute":"n","worked":"n","paid":"n","reason":"s"}): return "invalid_club_history"
			if not state.social.npcs.has(entry.npc) or entry.minute < 0 or entry.minute > state.clock.total_minutes or int(entry.minute) != entry.minute or entry.worked < 0 or entry.worked > 60 or int(entry.worked) != entry.worked or entry.paid < 0 or entry.paid > 100 or int(entry.paid) != entry.paid: return "invalid_club_history"
		for day in work.weekdays:
			if not Check.number(day) or int(day) != day or day < 1 or day > 7: return "invalid_club_schedule"
		for npc in work.sessions:
			var session: Variant = work.sessions[npc]
			if not group.members.has(npc) or not Check.fields(session,{"origin":"s","arrival":"n","ends":"n","phase":"s","task":"s","worked":"n","wage":"n"}): return "invalid_club_session"
			if not catalog.locations.has(session.origin) or not session.phase in ["travel","work"] or session.ends != session.arrival+60 or session.worked < 0 or session.worked >= 60 or int(session.worked) != session.worked or session.wage < 0 or session.wage > 100 or int(session.wage) != session.wage or session.arrival < 0 or int(session.arrival) != session.arrival or session.arrival > int(state.clock.total_minutes)+1440: return "invalid_club_session"
	return ""
