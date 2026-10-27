extends "res://scripts/mechanics/world.gd"
const City = preload("res://scripts/gameplay/city_layout.gd")

func routes_for(id: String) -> Dictionary:
	var routes: Dictionary = definition("locations", id).get("routes", {}).duplicate(true)
	var home := City.home(sim.state)
	if id == "apartment_hall":
		if home != "student_home":
			routes.erase("global_map")
			routes.erase("student_home")
		routes[home] = {"minutes":1}
	if id == "student_home": routes.erase("apartment_hall")
	if id == home and (not sim.state.housing.residence.is_empty() or not (sim.state.world.flags.get("chapter_one_complete", false) or sim.state.world.flags.get("student_home_lost",false))):
		routes.apartment_hall = {"minutes":1}
	return routes

func availability(id: String) -> Dictionary:
	if id in City.ROOMS and sim.state.housing.residence.is_empty() and (sim.state.world.flags.get("chapter_one_complete", false) or sim.state.world.flags.get("student_home_lost",false)): return Rules.fail("no_current_home")
	return super.availability(id)

func route(destination: String) -> Dictionary:
	return route_from(str(sim.state.world.location),destination,int(sim.state.clock.total_minutes))

func route_from(start: String, destination: String, departure: int, check_open: bool = true) -> Dictionary:
	if not sim.catalog.locations.has(destination): return Rules.fail("unknown_location")
	if not sim.catalog.locations.has(start): return Rules.fail("unknown_location")
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
			if not Rules.check(sim.state, edge.get("requirements", {})): continue
			var total := int(current.minutes) + int(edge.get("minutes",5))
			if best.has(next) and int(best[next]) <= total: continue
			var place: Dictionary = sim.catalog.locations[next]
			var arrival: Dictionary = sim.calendar.snapshot(departure+total)
			var hours: Array = place.get("hours", [0,0])
			var valid_day := false
			for weekday in place.get("weekdays",[1,2,3,4,5,6,7]):
				if int(weekday) == int(arrival.weekday): valid_day = true
			if check_open and (not valid_day or not Rules.in_window(int(arrival.minute_of_day),int(hours[0]),int(hours[1]))): continue
			if not Rules.check(sim.state,place.get("requirements",{})): continue
			if next in City.ROOMS and not availability(str(next)).ok: continue
			best[next] = total
			var path: Array = current.path.duplicate()
			path.append(str(next))
			queue.append({"id":str(next),"minutes":total,"path":path})
	return Rules.fail("city_route_unavailable")

func execute(operation: String, args: Dictionary) -> Dictionary:
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
	var available := availability(id)
	if not available.ok: return available
	var routes := routes_for(str(sim.state.world.location))
	if not routes.has(id): return Rules.fail("no_route")
	var edge: Dictionary = routes[id]
	if not Rules.check(sim.state,edge.get("requirements",{})): return Rules.fail("route_requirements")
	var cost := int(edge.get("cost",0))
	if cost < 0 or int(sim.state.economy.cash) < cost: return Rules.fail("travel_funds")
	sim.state.economy.cash -= cost
	var elapsed: Dictionary = sim.advance(int(edge.get("minutes",5)))
	if not elapsed.ok: return elapsed
	available = availability(id)
	if not available.ok: return available
	var world: Dictionary = sim.state.world
	world.previous_location = world.location
	world.location = id
	world.visits[id] = int(world.visits.get(id,0)) + 1
	emit_event("location_changed", {"id":id})
	return Rules.ok()

func tick(minute: int) -> void:
	var previous := str(sim.state.world.weather)
	super.tick(minute)
	if sim.state.world.weather == "snow": sim.state.world.temperature = -4 + (minute / 60) % 4
	if previous != sim.state.world.weather: emit_event("weather_changed", {"weather":sim.state.world.weather})
