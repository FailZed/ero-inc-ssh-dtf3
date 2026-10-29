extends "res://scripts/mechanics/core/module.gd"
const Education = preload("res://scripts/mechanics/education_schedule.gd")

func is_open(entry: Dictionary) -> bool:
	return _open_at_clock(entry,sim.state.clock)

func is_open_at(entry: Dictionary, minute: int) -> bool:
	return _open_at_clock(entry,sim.calendar.snapshot(minute))

func _open_at_clock(entry: Dictionary, clock: Dictionary) -> bool:
	var window: Array = entry.get("hours", [0, 0])
	var valid_day := false
	for weekday in entry.get("weekdays", [1, 2, 3, 4, 5, 6, 7]):
		if int(weekday) == int(clock.weekday): valid_day = true
	return valid_day and Rules.in_window(int(clock.minute_of_day), int(window[0]), int(window[1]))

func availability(id: String) -> Dictionary:
	var location := definition("locations", id)
	if location.is_empty(): return Rules.fail("unknown_location")
	if not is_open(location): return Rules.fail("location_closed")
	if not Rules.check(sim.state, location.get("requirements", {})): return Rules.fail("location_requirements")
	return Rules.ok(location.duplicate(true))

func actor_availability(id: String, actor_id: String, minute: int, ignore_hours: bool = false, _invited_destination: String = "") -> Dictionary:
	var location := definition("locations",id)
	if location.is_empty(): return Rules.fail("unknown_location")
	if not ignore_hours and not is_open_at(location,minute): return Rules.fail("location_closed")
	# Rules.check only reads nested state. Copy the root so the arrival clock stays
	# local without cloning every NPC and domain for each route edge.
	var context: Dictionary = sim.state.duplicate() if actor_id == "player" else sim.services.npc_behavior.context(sim.state.social.npcs[actor_id])
	context.clock = sim.calendar.snapshot(minute)
	return Rules.ok(location.duplicate(true)) if Rules.check(context,location.get("requirements",{})) else Rules.fail("location_requirements")

func execute(operation: String, args: Dictionary) -> Dictionary:
	var world: Dictionary = sim.state.world
	match operation:
		"travel":
			var id := str(args.get("id", ""))
			var available := availability(id)
			if not available.ok: return available
			var source := definition("locations", str(world.location))
			if not source.get("routes", {}).has(id): return Rules.fail("no_route")
			var route: Dictionary = source.routes[id]
			if not Rules.check(sim.state, route.get("requirements", {})): return Rules.fail("route_requirements")
			var cost := int(route.get("cost", 0))
			if cost < 0 or sim.state.economy.cash < cost: return Rules.fail("travel_funds")
			sim.state.economy.cash -= cost
			var result: Dictionary = sim.advance(int(route.get("minutes", 5)))
			if not result.ok: return result
			# Arrival hours matter, too. The outer command rolls back a failed trip.
			available = availability(id)
			if not available.ok: return available
			world.previous_location = world.location
			world.location = id
			world.visits[id] = int(world.visits.get(id, 0)) + 1
			emit_event("location_changed", {"id": id})
		"clean":
			var result: Dictionary = sim.advance(30)
			if not result.ok: return result
			world.cleanliness = minf(100.0, float(world.cleanliness) + 40.0)
			sim.services.character.adjust_need("energy", -5.0)
		"shower":
			var result: Dictionary = sim.advance(15)
			if not result.ok: return result
			sim.services.character.adjust_need("hygiene", 80.0)
		"install":
			var id := str(args.get("id", ""))
			var item := definition("items", id)
			if not item.has("equipment"): return Rules.fail("not_equipment")
			if item.equipment in world.equipment: return Rules.fail("already_installed")
			var removed: Dictionary = sim.services.inventory.change(id, -1)
			if not removed.ok: return removed
			world.equipment.append(str(item.equipment))
		"lesson": return _lesson(str(args.get("id", "")))
		"appeal":
			if not world.education.get("expelled", false) or not world.education.homework: return Rules.fail("appeal_requirements")
			var cost := int(definition("formula_rules", "discipline").get("appeal_cost", 50))
			if sim.state.economy.cash < cost: return Rules.fail("insufficient_funds")
			sim.state.economy.cash -= cost
			world.education.expelled = false
			world.education.warned = false
			world.education.absences = 0
			world.education.grade = maxf(0.0,float(world.education.grade))
			emit_event("education_reinstated", {})
			return sim.advance(30)
		"homework": return sim.services.education.execute("homework",args)
		"flag":
			var id := str(args.get("id", ""))
			if id.is_empty(): return Rules.fail("invalid_flag")
			world.flags[id] = args.get("value", true)
		"unlock":
			var id := str(args.get("id", ""))
			if id.is_empty(): return Rules.fail("invalid_unlock")
			if not id in world.unlocked: world.unlocked.append(id)
		_:
			return Rules.fail("unknown_operation")
	return Rules.ok()

func _lesson(id: String) -> Dictionary:
	if sim.state.world.education.get("expelled", false): return Rules.fail("education_expelled")
	var lesson := definition("lessons", id)
	if lesson.is_empty() or not is_open(lesson): return Rules.fail("lesson_unavailable")
	if not Rules.check(sim.state, lesson.get("requirements", {})): return Rules.fail("lesson_not_selected")
	if lesson.get("location", "") != sim.state.world.location: return Rules.fail("wrong_location")
	var key := "%s:%d" % [id, sim.state.clock.day_index]
	if key in sim.state.world.education.attended: return Rules.fail("lesson_already_attended")
	if key in sim.state.world.education.missed: return Rules.fail("lesson_already_missed")
	var attendance := Education.attendance(lesson,sim.state.clock)
	if not attendance.allowed: return Rules.fail("lesson_too_late")
	sim.state.world.education.attended.append(key)
	sim.state.world.education.grade += float(attendance.grade)
	sim.services.education.attend(id)
	var result: Dictionary = sim.services.character.execute("train", {"skill": lesson.get("skill", "study"), "xp": int(attendance.xp)})
	if not result.ok: return result
	result = sim.advance(int(attendance.minutes))
	if not result.ok: return result
	emit_event("lesson_attended",{"id":id,"late_minutes":attendance.late_minutes})
	return Rules.ok(attendance)

func tick(minute: int) -> void:
	var world: Dictionary = sim.state.world
	# Penalize only lesson windows that actually close during this session.
	for id in sim.catalog.lessons:
		if world.education.get("expelled",false): break
		var lesson := definition("lessons", id)
		if not Rules.check(sim.state, lesson.get("requirements", {})): continue
		var weekdays: Array = lesson.get("weekdays", [1, 2, 3, 4, 5])
		var scheduled_day := false
		for weekday in weekdays:
			if int(weekday) == int(sim.state.clock.weekday): scheduled_day = true
		var window: Array = lesson.get("hours", [0, 0])
		var key := "%s:%d" % [id, sim.state.clock.day_index]
		if scheduled_day and int(window[1]) == int(sim.state.clock.minute_of_day) and not key in world.education.attended and not key in world.education.missed:
			world.education.missed.append(key)
			world.education.absences += 1
			world.education.grade -= int(lesson.get("absence_penalty", 1))
			sim.services.education.attend(str(id),true)
			if sim.services.preferences.rule("education_failure", true):
				var discipline := definition("formula_rules", "discipline")
				if world.education.absences >= int(discipline.get("warning_absences", 3)) and not world.education.get("warned", false):
					world.education.warned = true
					emit_event("education_warning", {})
				if world.education.absences >= int(discipline.get("expulsion_absences", 8)) and not world.education.get("expelled", false):
					world.education.expelled = true
					emit_event("education_expulsion", {})
	# Keep one weather state through a substantial part of the day so outdoor
	# plans and rain-dependent encounters do not reverse every hour.
	if minute % 360 == 0:
		var weather: Array = sim.catalog.settings.weather_types
		world.weather = str(weather[sim.rng.randi_range(0, weather.size() - 1)])
		world.temperature = sim.rng.randi_range(10, 20) if world.weather == "rain" else sim.rng.randi_range(20, 30)
	if minute % 60 == 0:
		world.heat = maxf(0.0, float(world.heat) - 1.0)
	if minute % 1440 == 0:
		world.cleanliness = maxf(0.0, float(world.cleanliness) - 5.0)
		world.education.homework = false
