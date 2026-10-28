extends RefCounted
const V = preload("res://scripts/mechanics/core/validation.gd")
static func integer(value: Variant, low: int = 0, high: int = 100000000) -> bool:
	return V.number(value) and value >= low and value <= high and int(value) == value
static func bounded(value: Variant, low: float, high: float) -> bool:
	return V.number(value) and value >= low and value <= high

static func catalog_error(catalog: Dictionary) -> String:
	var r: Variant = catalog.get("computer_rules")
	if not V.fields(r,{"tracks":"d","upgrades":"d","specializations":"d","projects":"d","project_choices":"d","hack_choices":"d","hack_scenarios":"a","formats":"d","stream_choices":"d","stream_events":"a","lessons":"d","sponsors":"d"}): return "invalid_computer_catalog"
	for id in ["programmer","hacker","streamer"]:
		if not V.fields(r.tracks.get(id),{"label":"s","skill":"s"}) or not catalog.skills.has(r.tracks[id].skill): return "invalid_computer_track"
	for id in ["processor","network","studio"]:
		if not V.fields(r.upgrades.get(id),{"label":"s","cost":"n","max_level":"n","description":"s"}): return "invalid_computer_upgrade"
		if not integer(r.upgrades[id].cost,1,10000) or not integer(r.upgrades[id].max_level,1,3): return "invalid_computer_upgrade"
	for spec in r.specializations.values():
		if not V.fields(spec,{"label":"s","track":"s","description":"s"}) or not r.tracks.has(spec.track): return "invalid_computer_specialization"
	if r.projects.size() < 3: return "invalid_computer_projects"
	for p in r.projects.values():
		if not V.fields(p,{"label":"s","kind":"s","skill":"n","pay":"n","deadline":"n","brief":"s"}) or not p.kind in ["web","tools"]: return "invalid_computer_project_catalog"
		if not integer(p.skill,0,10000) or not integer(p.pay,1,1000) or not integer(p.deadline,240,10080): return "invalid_computer_project_catalog"
	for stage in ["design","build","test"]:
		if not r.project_choices.get(stage) is Dictionary or r.project_choices[stage].size() < 2: return "invalid_computer_project_choices"
		for c in r.project_choices[stage].values():
			if not V.fields(c,{"label":"s","minutes":"n","quality":"n","bugs":"n"}) or not integer(c.minutes,10,120) or not bounded(c.quality,0,30) or not integer(c.bugs,-3,3): return "invalid_computer_project_choices"
	if r.hack_scenarios.size() != 3 or r.stream_events.is_empty(): return "invalid_computer_scenarios"
	for choice in ["careful","balanced","fast"]:
		var c: Variant = r.hack_choices.get(choice)
		if not V.fields(c,{"label":"s","minutes":"n","intel":"n","pressure":"n"}) or not integer(c.minutes,1,60) or not integer(c.intel,0,2) or not integer(c.pressure,-1,3): return "invalid_computer_hack_choice"
	for spec in r.hack_scenarios:
		if not V.fields(spec,{"id":"s","text":"s"}): return "invalid_computer_scenarios"
	for spec in r.stream_events:
		if not V.fields(spec,{"id":"s","text":"s","best":"s"}) or not r.stream_choices.has(spec.best): return "invalid_computer_scenarios"
	for spec in r.stream_choices.values():
		if not V.fields(spec,{"label":"s","quality":"n","engagement":"n"}) or not bounded(spec.quality,-5,5) or not bounded(spec.engagement,-5,5): return "invalid_computer_stream_choices"
	for spec in r.formats.values():
		if not V.fields(spec,{"label":"s","description":"s"}): return "invalid_computer_format"
	for spec in r.lessons.values():
		if not V.fields(spec,{"label":"s","track":"s","skill":"s"}) or not r.tracks.has(spec.track) or not catalog.skills.has(spec.skill): return "invalid_computer_lesson"
	for spec in r.sponsors.values():
		if not V.fields(spec,{"label":"s","followers":"n","pay":"n","quality":"n"}) or not integer(spec.followers,1) or not integer(spec.pay,1,1000) or not bounded(spec.quality,0,100): return "invalid_computer_sponsor"
	return ""

static func state_error(state: Dictionary, catalog: Dictionary) -> String:
	var c: Variant = state.get("computer")
	if not V.fields(c,{"version":"n","tracks":"d","specializations":"d","upgrades":"d","projects":"d","portfolio":"a","hack":"d","broadcast":"d","broadcasts":"a","lessons":"d","history":"a","serial":"n","sponsor_until":"n"}): return "invalid_computer_state"
	var r: Dictionary = catalog.computer_rules
	var now := int(state.clock.total_minutes)
	if c.version != 1 or not integer(c.serial) or not integer(c.sponsor_until) or c.portfolio.size() > 24 or c.broadcasts.size() > 48 or c.history.size() > 32 or c.projects.size() > 30: return "invalid_computer_state"
	if c.tracks.size() != 3: return "invalid_computer_tracks"
	for id in r.tracks:
		if not integer(c.tracks.get(id),0,100000): return "invalid_computer_tracks"
	for track in c.specializations:
		if not r.tracks.has(track) or not c.specializations[track] is String or not r.specializations.has(c.specializations[track]) or r.specializations[c.specializations[track]].track != track: return "invalid_computer_specialization"
	for id in c.upgrades:
		if not r.upgrades.has(id) or not integer(c.upgrades[id],1,int(r.upgrades[id].max_level)): return "invalid_computer_upgrade"
	var active := 0
	for id in c.projects:
		var p: Variant = c.projects[id]
		if not id is String or id.split(":").size() != 2 or not id.get_slice(":",0).is_valid_int() or not id.get_slice(":",1).is_valid_int(): return "invalid_computer_project"
		if not integer(int(id.get_slice(":",0)),0,now/1440) or not integer(int(id.get_slice(":",1)),0,2): return "invalid_computer_project"
		if not V.fields(p,{"type":"s","step":"n","quality":"n","bugs":"n","deadline":"n","status":"s","revisions":"n","paid":"n","choices":"a"}) or not r.projects.has(p.type): return "invalid_computer_project"
		if not integer(p.step,0,3) or not bounded(p.quality,0,100) or not integer(p.bugs,0,6) or not integer(p.revisions,0,2) or not integer(p.deadline) or not integer(p.paid,0,2000) or p.choices.size() != int(p.step): return "invalid_computer_project"
		for i in range(p.choices.size()):
			if not p.choices[i] is String or not r.project_choices[["design","build","test"][i]].has(p.choices[i]): return "invalid_computer_project"
		if not p.status in ["active","delivered","expired","abandoned"]: return "invalid_computer_project"
		if p.status == "active":
			active += 1
			if int(p.deadline) <= now: return "invalid_computer_project_deadline"
		if p.status == "delivered" and (int(p.step) != 3 or p.quality < 60 or p.bugs > 1 or p.paid <= 0): return "invalid_computer_project_delivery"
		if p.status != "delivered" and p.paid != 0: return "invalid_computer_project_delivery"
	if active > 3: return "invalid_computer_project_capacity"
	for entry in c.portfolio:
		if not V.fields(entry,{"id":"s","type":"s","quality":"n","minute":"n","pay":"n"}) or not r.projects.has(entry.type) or not bounded(entry.quality,60,100) or not integer(entry.minute,0,now) or not integer(entry.pay,1,2000): return "invalid_computer_portfolio"
	for id in c.lessons:
		if not r.lessons.has(id) or not integer(c.lessons[id],0,now/1440): return "invalid_computer_lesson_day"
	for entry in c.history:
		if not V.fields(entry,{"kind":"s","minute":"n","details":"d"}) or not integer(entry.minute,0,now): return "invalid_computer_history"
	if not c.hack.is_empty():
		var h: Dictionary = c.hack
		if not c.broadcast.is_empty() or not V.fields(h,{"id":"s","token":"n","step":"n","intel":"n","pressure":"n","expires":"n"}): return "invalid_computer_hack"
		if not catalog.digital_operations.has(h.id) or not integer(h.step,0,2) or not integer(h.intel,0,6) or not integer(h.pressure,0,9) or not integer(h.expires,now+1): return "invalid_computer_hack"
		if state.digital.pending.get("id") != h.id or state.digital.pending.get("token") != h.token or state.digital.pending.get("expires") != h.expires: return "invalid_computer_hack_report"
	if not c.broadcast.is_empty():
		var b: Dictionary = c.broadcast
		if not V.fields(b,{"token":"n","topic":"s","format":"s","segments":"n","step":"n","quality":"n","engagement":"n","income":"n","followers":"n","started":"n","expires":"n","events":"a","sponsor":"s","quality_sum":"n"}): return "invalid_computer_broadcast"
		if not state.digital.pending.is_empty() or not integer(b.token,1,int(c.serial)) or not catalog.stream_topics.has(b.topic) or not r.formats.has(b.format) or not integer(b.segments,2,6) or not integer(b.step,0,int(b.segments)-1): return "invalid_computer_broadcast"
		if not bounded(b.quality,-10,20) or not bounded(b.engagement,-10,20) or not integer(b.income) or not integer(b.followers) or not integer(b.started,0,now) or b.expires != b.started+480 or int(b.expires) <= now or not bounded(b.quality_sum,0,600): return "invalid_computer_broadcast"
		if b.events.size() != int(b.segments) or (not b.sponsor.is_empty() and not r.sponsors.has(b.sponsor)): return "invalid_computer_broadcast"
		for event in b.events:
			if not integer(event,0,r.stream_events.size()-1): return "invalid_computer_broadcast"
	var unique := {}
	for b in c.broadcasts:
		if not V.fields(b,{"id":"s","topic":"s","minute":"n","minutes":"n","quality":"n","income":"n","followers":"n","completed":"b","highlight":"b"}) or unique.has(b.id): return "invalid_computer_broadcast_history"
		unique[b.id] = true
		if not catalog.stream_topics.has(b.topic) or not integer(b.minute,0,now) or not integer(b.minutes,0,240) or not bounded(b.quality,0,100) or not integer(b.income) or not integer(b.followers) or (b.highlight and not b.completed): return "invalid_computer_broadcast_history"
	return ""
