extends "res://scripts/mechanics/core/module.gd"
## Pure calendar projection shared by every NPC task executor.

func now() -> int:
	return int(sim.state.clock.total_minutes)

func windows(id: String, horizon: int = 1440) -> Array:
	var npc: Dictionary = sim.state.social.npcs.get(id,{})
	if npc.is_empty(): return []
	var result: Array = []
	var first := now()-posmod(now(),1440)
	for day in range(0,ceili(horizon/1440.0)+1):
		var start := first+day*1440
		var clock: Dictionary = sim.calendar.snapshot(start)
		for entry in npc.schedule:
			var action := str(entry.get("activity","rest"))
			if not entry.get("mandatory",action in ["work","study"]) or not entry.get("weekdays",[1,2,3,4,5,6,7]).any(func(day): return int(day)==int(clock.weekday)): continue
			var hours: Array = entry.get("hours",[0,0])
			var ranges: Array = [[0,1440]] if hours[0]==hours[1] else [[int(hours[0]),int(hours[1])]] if hours[0]<hours[1] else [[0,int(hours[1])],[int(hours[0]),1440]]
			for span in ranges:
				var begin := start+int(span[0])
				var end := start+int(span[1])
				if end<=now() or begin>now()+horizon: continue
				var context: Dictionary = sim.state.duplicate()
				context.player = npc
				context.npc = npc
				context.clock = sim.calendar.snapshot(maxi(now(),begin))
				if not Rules.check(context,entry.get("requirements",{})): continue
				if action == "work" and npc.has("mind") and not str(npc.mind.employment.job).is_empty() and preload("res://scripts/mechanics/npc_employment.gd").remaining(npc,sim.catalog,context.clock)<=0: continue
				result.append({"kind":"schedule","action":action,"start":begin,"end":end,"location":str(entry.get("location",npc.home)),"priority":70})
	for index in range(sim.state.social.appointments.size()):
		var meeting: Dictionary = sim.state.social.appointments[index]
		if meeting.npc!=id or meeting.status!="pending" or int(meeting.minute)+30<=now() or int(meeting.minute)>now()+horizon: continue
		result.append({"kind":"appointment","action":"appointment","start":int(meeting.minute),"end":int(meeting.minute)+30,"location":str(meeting.location),"priority":80,"index":index})
	result.sort_custom(func(a,b): return int(a.start)<int(b.start) if a.start!=b.start else int(a.priority)>int(b.priority))
	return result

func conflict(id: String, destination: String, minutes: int, priority: int = 50, ignore_appointment: int = -1, ignore_schedule: int = -1, forecast: Dictionary = {}) -> String:
	if minutes<0 or minutes>1440: return "invalid_time_delta"
	if priority>=100: return ""
	var npc: Dictionary = sim.state.social.npcs[id]
	var end := now()+minutes
	var agenda: Array = forecast.windows if forecast.has("windows") else windows(id)
	var routes: Dictionary = forecast.get("routes",{})
	for window in agenda:
		if window.kind=="appointment" and int(window.index)==ignore_appointment: continue
		if window.kind=="schedule" and int(window.start)==ignore_schedule: continue
		if end>int(window.start) and now()<int(window.end): return "schedule_conflict"
		if int(window.start)<end: continue
		var key := destination+":"+str(window.location)+":"+str(int(window.start))
		if not routes.has(key): routes[key] = sim.services.npc_agency._route(npc,destination,str(window.location),int(window.start))
		var route: Dictionary = routes[key]
		if route.is_empty(): return "obligation_unreachable"
		if end+int(route.minutes)>int(window.start): return "obligation_travel_conflict"
	return ""

func site_open(destination: String, arrival: int, finish: int, actor_id: String = "player") -> bool:
	var place: Dictionary = sim.catalog.locations.get(destination,{})
	if not preload("res://scripts/mechanics/core/service_window.gd").is_open(sim,place,arrival,finish): return false
	for minute in [arrival,maxi(arrival,finish-1)]:
		if not sim.services.world.actor_availability(destination,actor_id,int(minute)).ok: return false
	return true

