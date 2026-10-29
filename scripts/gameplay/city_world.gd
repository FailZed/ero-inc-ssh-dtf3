extends "res://scripts/mechanics/world.gd"
const City = preload("res://scripts/gameplay/city_layout.gd")
const Graph = preload("res://scripts/gameplay/city_graph.gd")
const Employment = preload("res://scripts/mechanics/npc_employment.gd")

func routes_for(id: String) -> Dictionary:
	return definition("locations",id).get("routes",{}).duplicate(true)

func _open_at_clock(entry: Dictionary, clock: Dictionary) -> bool:
	if entry.has("access_policy_id"):
		var graph: Dictionary = sim.catalog.city_graph
		var policy: Dictionary = graph.access_policies[entry.access_policy_id]
		return Graph.service_open(graph,str(policy.service_id),int(clock.minute_of_day),int(clock.weekday)) if policy.kind == "service" else true
	return super._open_at_clock(entry,clock)

func _home_transit_rooms(property_id: String) -> Array:
	var rooms: Dictionary = Graph.home_unit(sim.catalog.city_graph,property_id).get("room_ids",{})
	var result: Array = []
	for kind in ["hall","stairs"]:
		if rooms.has(kind): result.append(str(rooms[kind]))
	return result

func _player_invitation_transit(destination: String) -> Array:
	if not sim.is_player_home_location(destination): return []
	return _home_transit_rooms(City.active_property(sim.state))

func actor_context(id: String, minute: int, urgent: bool = false) -> Dictionary:
	var clock: Dictionary = sim.calendar.snapshot(minute)
	var actor := {"id":id,"residence_id":"","story_location_ids":[],"activity_location_ids":[],"duty_location_ids":[],"urgent_location_ids":[],"invited_location_ids":[]}
	if id == "player":
		actor.residence_id = City.active_property(sim.state)
		if sim.state.world.flags.get("city_story_home",false):
			actor.story_location_ids = sim.catalog.city_graph.home_units.apartment.room_ids.values()
		for lesson in sim.catalog.lessons.values():
			if Rules.check(sim.state,lesson.get("requirements",{})): actor.activity_location_ids.append(str(lesson.location))
		for spec in sim.catalog.skills.values():
			for destination in spec.get("locations",[]):
				if sim.catalog.locations.has(destination): actor.activity_location_ids.append(str(destination))
		for job in sim.catalog.livelihood_rules.jobs.values():
			if sim.services.has("growth") and sim.services.growth.level(str(job.skill)) < int(job.min_skill): continue
			if int(clock.minute_of_day)+15 < int(job.hours[0]) or int(clock.minute_of_day) >= int(job.hours[1]): continue
			actor.duty_location_ids.append(str(job.location))
		if sim.services.adult_health.view("player").get("urgent",false): actor.urgent_location_ids.append("clinic")
	else:
		if not sim.state.social.npcs.has(id): return actor
		var npc: Dictionary = sim.state.social.npcs[id]
		for block in npc.schedule:
			var valid_day := false
			for day in block.get("weekdays",[1,2,3,4,5,6,7]):
				if int(day) == int(clock.weekday): valid_day = true
			if not valid_day: continue
			var starts := int(block.hours[0])-15
			var ends := int(block.hours[1])
			if int(clock.minute_of_day) < starts or int(clock.minute_of_day) >= ends: continue
			if block.get("activity") == "work": actor.duty_location_ids.append(str(block.location))
			else: actor.activity_location_ids.append(str(block.location))
		if npc.has("mind") and not npc.mind.get("active",{}).is_empty():
			var active: Dictionary = npc.mind.active
			if active.get("action") == "work": actor.duty_location_ids.append(str(active.destination))
			else: actor.activity_location_ids.append(str(active.get("destination",npc.home)))
		if urgent: actor.urgent_location_ids.append("clinic")
	if id != "player":
		for property_id in sim.state.housing.properties:
			if id in sim.state.housing.properties[property_id].get("tenants",[]):
				actor.invited_location_ids.append_array(Graph.home_unit(sim.catalog.city_graph,str(property_id)).get("room_ids",{}).values())
		# Someone already inside a residence can use its hall (and stairs) to
		# leave, even after a tenancy or invitation ends. This grants no bedroom.
		var current := str(sim.state.social.npcs[id].location)
		for property_id in sim.catalog.city_graph.home_units:
			var rooms: Dictionary = Graph.home_unit(sim.catalog.city_graph,str(property_id)).get("room_ids",{})
			if current in rooms.values():
				actor.invited_location_ids.append_array(_home_transit_rooms(str(property_id)))
				break
	for session in sim.state.get("npc_reproduction",{}).get("sessions",{}).values():
		if id in [session.a,session.b]: actor.invited_location_ids.append(str(session.venue))
	for appointment in sim.state.social.appointments:
		if appointment.npc == id and appointment.status == "pending" and sim.is_player_home_location(str(appointment.location)):
			actor.invited_location_ids.append(str(appointment.location))
			actor.invited_location_ids.append_array(_player_invitation_transit(str(appointment.location)))
	for member in sim.state.get("family",{}).get("members",{}).values():
		if id in member.get("guardians",member.parents): actor.invited_location_ids.append(str(member.home))
	return actor

func actor_availability(id: String, actor_id: String, minute: int, ignore_hours: bool = false, invited_destination: String = "") -> Dictionary:
	if not sim.catalog.locations.has(id): return Rules.fail("unknown_location")
	var clock: Dictionary = sim.calendar.snapshot(minute)
	var actor := actor_context(actor_id,minute,ignore_hours)
	if not invited_destination.is_empty():
		actor.invited_location_ids.append(invited_destination)
		actor.invited_location_ids.append_array(_player_invitation_transit(invited_destination))
	var access := Graph.can_enter(sim.catalog.city_graph,id,actor,int(clock.minute_of_day),int(clock.weekday))
	if not access.ok and ignore_hours:
		access = Graph.can_enter(sim.catalog.city_graph,id,actor,int(clock.minute_of_day),int(clock.weekday),false)
	if not access.ok: return access
	var context: Dictionary = sim.state if actor_id == "player" else sim.services.npc_behavior.context(sim.state.social.npcs[actor_id])
	if not Rules.check(context,sim.catalog.locations[id].get("requirements",{})): return Rules.fail("location_requirements")
	return Rules.ok(sim.catalog.locations[id].duplicate(true))

func availability(id: String) -> Dictionary:
	return actor_availability(id,"player",int(sim.state.clock.total_minutes))

func route(destination: String) -> Dictionary:
	return route_from(str(sim.state.world.location),destination,int(sim.state.clock.total_minutes))

func route_from(start: String, destination: String, departure: int, check_open: bool = true) -> Dictionary:
	if not sim.catalog.locations.has(destination) or not sim.catalog.locations.has(start): return Rules.fail("unknown_location")
	if start == destination: return Rules.ok({"path":[],"minutes":0})
	var queue: Array = [{"id":start,"minutes":0,"path":[]}]
	var best := {start:0}
	while not queue.is_empty():
		queue.sort_custom(func(a: Dictionary,b: Dictionary): return int(a.minutes) < int(b.minutes) if a.minutes != b.minutes else str(a.id) < str(b.id))
		var current: Dictionary = queue.pop_front()
		if int(current.minutes) > int(best[current.id]): continue
		if current.id == destination: return Rules.ok({"path":current.path,"minutes":int(current.minutes)})
		var neighbors := routes_for(str(current.id))
		for next in neighbors:
			var edge: Dictionary = neighbors[next]
			if not Rules.check(sim.state,edge.get("requirements",{})): continue
			var total := int(current.minutes)+int(edge.get("minutes",5))
			if best.has(next) and int(best[next]) <= total: continue
			if not actor_availability(str(next),"player",departure+total,not check_open).ok: continue
			best[next] = total
			var path: Array = current.path.duplicate()
			path.append(str(next))
			queue.append({"id":str(next),"minutes":total,"path":path})
	return Rules.fail("city_route_unavailable")

func execute(operation: String, args: Dictionary) -> Dictionary:
	if operation in ["homework","appeal"] and not sim.state.world.flags.student_enrolled: return Rules.fail("education_not_enrolled")
	if operation == "journey":
		var planned := route(str(args.get("id","")))
		if not planned.ok: return planned
		for step in planned.data.path:
			var traveled := _travel(str(step))
			if not traveled.ok: return traveled
		return planned
	if operation == "travel": return _travel(str(args.get("id","")))
	return super.execute(operation,args)

func _travel(id: String) -> Dictionary:
	var routes := routes_for(str(sim.state.world.location))
	if not routes.has(id): return Rules.fail("no_route")
	var edge: Dictionary = routes[id]
	if not Rules.check(sim.state,edge.get("requirements",{})): return Rules.fail("route_requirements")
	var arrival := int(sim.state.clock.total_minutes)+int(edge.minutes)
	var available := actor_availability(id,"player",arrival)
	if not available.ok: return available
	var cost := int(edge.get("cost",0))
	if cost < 0 or int(sim.state.economy.cash) < cost: return Rules.fail("travel_funds")
	sim.state.economy.cash -= cost
	var elapsed: Dictionary = sim.advance(int(edge.minutes))
	if not elapsed.ok: return elapsed
	available = availability(id)
	if not available.ok: return available
	var world: Dictionary = sim.state.world
	world.previous_location = world.location
	world.location = id
	world.visits[id] = int(world.visits.get(id,0))+1
	emit_event("location_changed",{"id":id})
	return Rules.ok()

func tick(minute: int) -> void:
	var previous := str(sim.state.world.weather)
	super.tick(minute)
	if sim.state.world.weather == "snow": sim.state.world.temperature = -4 + (minute / 60) % 4
	if previous != sim.state.world.weather: emit_event("weather_changed",{"weather":sim.state.world.weather})
