extends RefCounted
const Rules = preload("res://scripts/mechanics/core/rules.gd")
const Education = preload("res://scripts/mechanics/education_schedule.gd")

static func conflicts(sim, location: String, minutes: int, start: int = -1) -> Array:
	var result: Array = []
	if sim.state.world.education.get("expelled",false) or minutes <= 0: return result
	if start < 0: start = int(sim.state.clock.total_minutes)
	var ending := start+minutes
	var day := int(sim.calendar.snapshot(start).day_index)
	var last_day := int(sim.calendar.snapshot(ending+1440).day_index)
	for day_index in range(day,last_day+1):
		var date: Dictionary = sim.calendar.snapshot(day_index*1440)
		for id in sim.catalog.lessons:
			var lesson: Dictionary = sim.catalog.lessons[id]
			if not Rules.check(sim.state,lesson.get("requirements",{})): continue
			var key := "%s:%d" % [id,day_index]
			if key in sim.state.world.education.attended or key in sim.state.world.education.missed: continue
			var scheduled := false
			for weekday in lesson.get("weekdays",[1,2,3,4,5]):
				if int(weekday) == int(date.weekday): scheduled = true
			if not scheduled: continue
			var window := Education.slot(lesson,day_index)
			var begins := int(window.start)
			var closes := int(window.end)
			if start >= closes: continue
			var journey: Dictionary = sim.services.world.route_from(location,str(lesson.location),ending,false)
			var commute := int(journey.data.minutes) if journey.ok else 1440
			if ending+commute > begins and start < closes:
				var forecast := Education.forecast(lesson,day_index,ending+commute)
				forecast.merge({"id":id,"commute":commute,"overlap":ending > begins})
				result.append(forecast)
	result.sort_custom(func(a: Dictionary,b: Dictionary): return int(a.start) < int(b.start))
	return result
