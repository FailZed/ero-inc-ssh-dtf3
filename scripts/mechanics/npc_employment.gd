extends RefCounted
## Occupation is durable; rank is derived from its skill, never from generic work XP.
const Progress = preload("res://scripts/mechanics/core/career_progress.gd")
const Rules = preload("res://scripts/mechanics/core/rules.gd")
const Calendar = preload("res://scripts/mechanics/core/calendar.gd")
const INTERESTS := {
	"mind":["books","science","puzzles"],"technical":["technology","games"],
	"creative":["art","music","books"],"social":["friends","social","music"],
	"body":["sport","fitness","dance"],"craft":["cooking","nature","food"]}

static func from_player_jobs(catalog: Dictionary) -> Dictionary:
	var result := {}
	for id in catalog.livelihood_rules.jobs:
		var job: Dictionary = catalog.livelihood_rules.jobs[id]
		# Criminal work needs an NPC law/risk model; do not silently mint risk-free income.
		if float(job.risk) > 0: continue
		var quality := 0.65 if job.kind == "shift" else 0.55
		result[id] = {"title":job.title,"skill":job.skill,"location":"home" if job.has("home_room_kind") else job.location,
			"hours":job.hours.duplicate(),"minutes":int(job.minutes),"pay":roundi(float(job.pay)*(0.45+0.85*quality)),"min_skill":int(job.min_skill),
			"weekdays":job.get("weekdays",[1,2,3,4,5,6,7]).duplicate(),"interests":INTERESTS.get(str(catalog.skills[job.skill].category),[]).duplicate()}
	return result

static func initialize(npc: Dictionary, catalog: Dictionary, day: int) -> void:
	if npc.has("employment_plan"):
		var plan: Dictionary = npc.employment_plan
		var job: Dictionary = catalog.npc_jobs[plan.job]
		npc.skills[job.skill] = 10*int(plan.skill_level)*int(plan.skill_level)
		npc.mind.employment = {"job":str(plan.job),"day":day,"minutes_today":0,"paid_minutes":0,"earnings":0}
		return
	var chosen := ""
	var best := -INF
	var starting_level := 4 if int(npc.age)>=30 else 2 if int(npc.age)>=23 else 1
	var seed_skill: bool = npc.skills.is_empty()
	if npc.biography.role == "worker":
		var ids: Array = catalog.npc_jobs.keys()
		ids.sort()
		for id in ids:
			var job: Dictionary = catalog.npc_jobs[id]
			var raw := float(npc.skills.get(job.skill,0))
			if seed_skill: raw = 10.0*starting_level*starting_level
			if Progress.skill_level(raw) < int(job.min_skill): continue
			if not fits_schedule(npc,job): continue
			var affinity := 0.0
			for interest in npc.preferences:
				if interest in job.interests: affinity += 8.0
			var score := Progress.skill_level(raw)*50.0+raw*0.05+affinity
			# Stable tie-break only; learned skills and interests dominate the choice.
			score += float((str(npc.id)+":"+str(id)).hash() & 0x7fffffff)/2147483647.0
			if score > best: best = score; chosen = str(id)
	npc.mind.employment = {"job":chosen,"day":day,"minutes_today":0,"paid_minutes":0,"earnings":0}
	if chosen.is_empty(): return
	var spec: Dictionary = catalog.npc_jobs[chosen]
	if seed_skill: npc.skills[spec.skill] = 10*starting_level*starting_level
	for entry in npc.schedule:
		if entry.get("activity","") != "work": continue
		entry.location = location(npc,spec)
		if spec.hours[0] == spec.hours[1]: continue
		var window := work_window(entry,spec)
		entry.hours = window
		entry.weekdays = shared_days(entry.get("weekdays",[1,2,3,4,5,6,7]),spec.weekdays)

static func shared_days(first: Array, second: Array) -> Array:
	var result: Array = []
	for day in first:
		if second.any(func(other): return int(other)==int(day)) and not int(day) in result: result.append(int(day))
	return result

static func work_window(entry: Dictionary, job: Dictionary) -> Array:
	var start := maxi(int(entry.hours[0]),int(job.hours[0]))
	var end := mini(int(entry.hours[1]),int(job.hours[1]))
	return [start,mini(end,start+int(job.minutes))]

static func fits_schedule(npc: Dictionary, job: Dictionary) -> bool:
	if job.hours[0] == job.hours[1]: return true
	for entry in npc.schedule:
		if entry.get("activity","") != "work": continue
		var window := work_window(entry,job)
		if int(window[1])-int(window[0]) < int(job.minutes): return false
		var days := shared_days(entry.get("weekdays",[1,2,3,4,5,6,7]),job.weekdays)
		if days.is_empty(): return false
		for other in npc.schedule:
			if other.get("activity","") == "work" or not other.get("mandatory",other.get("activity","")=="study"): continue
			if shared_days(days,other.get("weekdays",[1,2,3,4,5,6,7])).is_empty(): continue
			if int(window[0]) < int(other.hours[1]) and int(window[1]) > int(other.hours[0]): return false
	return true

static func location(npc: Dictionary, job: Dictionary) -> String:
	return str(npc.home) if job.location == "home" else str(job.location)

static func profile(npc: Dictionary, catalog: Dictionary) -> Dictionary:
	return catalog.npc_jobs.get(npc.mind.employment.job,{})

static func rank(npc: Dictionary, catalog: Dictionary) -> int:
	var job := profile(npc,catalog)
	return 0 if job.is_empty() else Progress.rank(float(npc.skills.get(job.skill,0)),gates(catalog))

static func gates(catalog: Dictionary) -> Array:
	return catalog.livelihood_rules.promotion.skill_levels if catalog.has("livelihood_rules") else Progress.SKILL_GATES

static func remaining(npc: Dictionary, catalog: Dictionary, clock: Dictionary) -> int:
	var job := profile(npc,catalog)
	if job.is_empty(): return 0
	var used := int(npc.mind.employment.minutes_today) if int(npc.mind.employment.day) == int(clock.day_index) else 0
	return maxi(0,daily_limit(npc,catalog)-used)

static func daily_limit(npc: Dictionary, catalog: Dictionary) -> int:
	var job := profile(npc,catalog)
	if job.is_empty(): return 0
	var limit := mini(600,2*int(job.minutes))
	if npc.has("employment_plan"):
		for day in range(1,8):
			var scheduled := 0
			for entry in npc.schedule:
				if entry.get("activity","")=="work" and entry.get("weekdays",[1,2,3,4,5,6,7]).any(func(value): return int(value)==day): scheduled += int(entry.hours[1])-int(entry.hours[0])
			limit = maxi(limit,scheduled)
	return mini(600,limit)

static func assignment_error(plan: Variant, catalog: Dictionary, npc: Dictionary) -> String:
	if not plan is Dictionary or plan.size()!=3 or not plan.get("job") is String or not plan.get("workplace") is String: return "invalid_employment_assignment"
	if not catalog.get("npc_jobs",{}).has(plan.job): return "unknown_employment_job"
	var job: Dictionary = catalog.npc_jobs[plan.job]
	if not catalog.skills.has(job.skill): return "unknown_employment_skill"
	var level: Variant = plan.get("skill_level")
	if not (level is int or level is float) or not is_finite(float(level)) or float(level)!=int(level) or int(level)<int(job.min_skill) or int(level)>10: return "employment_skill_required"
	if npc.biography.role!="worker" or int(npc.age)<18: return "employment_worker_required"
	if str(plan.workplace)!=location(npc,job) or not catalog.locations.has(plan.workplace): return "employment_workplace_conflict"
	if not npc.get("schedule") is Array: return "invalid_employment_schedule"
	for entry in npc.schedule:
		if not entry is Dictionary or not entry.get("hours") is Array or entry.hours.size()!=2 or not entry.get("weekdays",[]) is Array: return "invalid_employment_schedule"
		for hour in entry.hours:
			if not (hour is int or hour is float) or not is_finite(float(hour)) or float(hour)!=int(hour) or int(hour)<0 or int(hour)>1440: return "invalid_employment_hours"
		for day in entry.get("weekdays",[1,2,3,4,5,6,7]):
			if not (day is int or day is float) or not is_finite(float(day)) or float(day)!=int(day) or int(day)<1 or int(day)>7: return "invalid_employment_days"
	var shifts: Array = npc.schedule.filter(func(entry): return entry.get("activity","")=="work")
	if shifts.is_empty(): return "employment_schedule_required"
	var site: Dictionary = catalog.locations[plan.workplace]
	for entry in shifts:
		if entry.get("location","")!=plan.workplace or not entry.get("mandatory",true): return "employment_schedule_conflict"
		if not entry.get("hours") is Array or entry.hours.size()!=2: return "invalid_employment_hours"
		for hour in entry.hours:
			if not (hour is int or hour is float) or not is_finite(float(hour)) or float(hour)!=int(hour) or int(hour)<0 or int(hour)>1440: return "invalid_employment_hours"
		if int(entry.hours[1])<=int(entry.hours[0]): return "invalid_employment_hours"
		if job.hours[0]!=job.hours[1] and (int(entry.hours[0])<int(job.hours[0]) or int(entry.hours[1])>int(job.hours[1])): return "employment_hours_conflict"
		var site_hours: Array = site.get("hours",[0,0])
		if not Rules.in_window(int(entry.hours[0]),int(site_hours[0]),int(site_hours[1])) or not Rules.in_window(int(entry.hours[1])-1,int(site_hours[0]),int(site_hours[1])): return "employment_site_closed"
		var days: Variant = entry.get("weekdays")
		if not days is Array or days.is_empty(): return "invalid_employment_days"
		var unique: Array = []
		for day in days:
			if not (day is int or day is float) or not is_finite(float(day)) or float(day)!=int(day) or int(day)<1 or int(day)>7 or int(day) in unique: return "invalid_employment_days"
			unique.append(int(day))
			if shared_days([day],job.weekdays).is_empty() or shared_days([day],site.get("weekdays",[1,2,3,4,5,6,7])).is_empty(): return "employment_days_conflict"
	for day in range(1,8):
		var entries: Array = npc.schedule.filter(func(entry): return entry.get("mandatory",entry.get("activity","") in ["work","study"]) and not shared_days([day],entry.get("weekdays",[1,2,3,4,5,6,7])).is_empty())
		entries.sort_custom(func(a,b): return int(a.hours[0])<int(b.hours[0]))
		var total := 0
		for index in range(entries.size()):
			var entry: Dictionary = entries[index]
			if entry.get("activity","")=="work": total += int(entry.hours[1])-int(entry.hours[0])
			if index>0:
				var previous: Dictionary = entries[index-1]
				if entry.get("activity","")!="work" and previous.get("activity","")!="work": continue
				var gap := 0 if entry.get("location",npc.home)==previous.get("location",npc.home) else 15
				if int(previous.hours[1])+gap>int(entry.hours[0]): return "employment_schedule_conflict"
		if total>600: return "employment_day_too_long"
	return ""

static func blocked(npc: Dictionary, catalog: Dictionary, clock: Dictionary) -> String:
	var job := profile(npc,catalog)
	if job.is_empty(): return "not_employed"
	if not job.weekdays.any(func(day): return int(day)==int(clock.weekday)) or not Rules.in_window(int(clock.minute_of_day),int(job.hours[0]),int(job.hours[1])): return "work_hours"
	if remaining(npc,catalog,clock) <= 0: return "work_daily_limit"
	if npc.has("employment_plan") and available_minutes(npc,catalog,clock)<=0: return "outside_authored_shift"
	return ""

static func available_minutes(npc: Dictionary, catalog: Dictionary, clock: Dictionary) -> int:
	var job := profile(npc,catalog)
	if job.is_empty(): return 0
	var minutes := remaining(npc,catalog,clock)
	if job.hours[0]!=job.hours[1]: minutes = mini(minutes,maxi(0,int(job.hours[1])-int(clock.minute_of_day)))
	if npc.has("employment_plan"):
		var shift_left := 0
		for entry in npc.schedule:
			if entry.get("activity","")!="work" or shared_days([clock.weekday],entry.weekdays).is_empty(): continue
			if Rules.in_window(int(clock.minute_of_day),int(entry.hours[0]),int(entry.hours[1])): shift_left = maxi(shift_left,int(entry.hours[1])-int(clock.minute_of_day))
		minutes = mini(minutes,shift_left)
	return minutes

static func action(npc: Dictionary, id: String, catalog: Dictionary, clock: Dictionary) -> Dictionary:
	var result: Dictionary = catalog.agency_actions[id]
	if not id in ["work","practice"]: return result
	var job := profile(npc,catalog)
	if job.is_empty(): return result
	result = result.duplicate(true)
	result.skill = str(job.skill)
	if id == "work":
		result.xp = 2
		result.destination = location(npc,job)
		result.income = float(job.pay)*60.0/int(job.minutes)*Progress.pay_factor(rank(npc,catalog))
	return result

static func catalog_error(catalog: Dictionary) -> String:
	var jobs: Variant = catalog.get("npc_jobs")
	if not jobs is Dictionary or jobs.is_empty(): return "missing_npc_jobs"
	for job in jobs.values():
		if not job is Dictionary: return "invalid_npc_job"
		for field in ["title","skill","location"]:
			if not job.get(field) is String or str(job[field]).is_empty(): return "invalid_npc_job"
		if not catalog.skills.has(job.skill) or (job.location != "home" and not catalog.locations.has(job.location)): return "invalid_npc_job_reference"
		for field in ["minutes","pay","min_skill"]:
			var value: Variant = job.get(field)
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) != int(value): return "invalid_npc_job_number"
		if int(job.minutes)<15 or int(job.minutes)>480 or int(job.minutes)%15!=0 or int(job.pay)<1 or int(job.pay)>10000 or int(job.min_skill)<0 or int(job.min_skill)>10: return "invalid_npc_job_number"
		if not job.get("hours") is Array or job.hours.size()!=2: return "invalid_npc_job_hours"
		for hour in job.hours:
			if not (hour is int or hour is float) or not is_finite(float(hour)) or float(hour)!=int(hour) or int(hour)<0 or int(hour)>1440: return "invalid_npc_job_hours"
		if int(job.hours[1])<int(job.hours[0]): return "overnight_npc_job_not_supported"
		if not job.get("weekdays") is Array or job.weekdays.is_empty() or not job.get("interests") is Array: return "invalid_npc_job_days"
		for day in job.weekdays:
			if not (day is int or day is float) or float(day)!=int(day) or int(day)<1 or int(day)>7: return "invalid_npc_job_days"
		for interest in job.interests:
			if not interest is String: return "invalid_npc_job_interest"
	return ""

static func state_error(npc: Dictionary, catalog: Dictionary, clock: Dictionary) -> String:
	var work: Variant = npc.mind.get("employment")
	if not work is Dictionary or work.size()!=5 or not work.get("job") is String: return "invalid_npc_employment"
	if npc.has("employment_plan"):
		var error := assignment_error(npc.employment_plan,catalog,npc)
		if not error.is_empty(): return error
		if work.job!=npc.employment_plan.job or Progress.skill_level(float(npc.skills.get(catalog.npc_jobs[work.job].skill,0)))<int(npc.employment_plan.skill_level): return "employment_assignment_conflict"
	for field in ["day","minutes_today","paid_minutes","earnings"]:
		var value: Variant = work.get(field)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value)!=int(value) or float(value)<0 or float(value)>2147483647: return "invalid_npc_employment_number"
	if int(work.day)>int(clock.day_index) or int(work.minutes_today)>600 or int(work.paid_minutes)<int(work.minutes_today): return "invalid_npc_employment_time"
	if work.job.is_empty():
		if npc.mind.active.get("action","")=="work": return "unemployed_npc_work"
		return "" if int(work.paid_minutes)==0 and int(work.earnings)==0 else "unemployed_npc_income"
	if npc.biography.role!="worker" or not catalog.npc_jobs.has(work.job): return "invalid_npc_occupation"
	var job: Dictionary = catalog.npc_jobs[work.job]
	if int(work.minutes_today)>daily_limit(npc,catalog) or Progress.skill_level(float(npc.skills.get(job.skill,0)))<int(job.min_skill): return "invalid_npc_employment_progress"
	var active: Dictionary = npc.mind.active
	if active.get("action","")=="work":
		if active.get("destination","")!=location(npc,job): return "npc_workplace_mismatch"
		if active.get("phase","")=="action":
			var started := int(active.get("started",0))
			var duration := int(active.get("due",0))-started
			var start_clock := Calendar.snapshot(started)
			if duration>60 or duration>available_minutes(npc,catalog,start_clock): return "invalid_npc_work_duration"
			if not blocked(npc,catalog,start_clock).is_empty(): return "invalid_npc_work_start"
			if job.hours[0]!=job.hours[1] and int(start_clock.minute_of_day)+duration>int(job.hours[1]): return "invalid_npc_work_duration"
	return ""

static func settle(npc: Dictionary, active: Dictionary, paid: int, clock: Dictionary) -> void:
	var work: Dictionary = npc.mind.employment
	if int(work.day) != int(clock.day_index): work.day = int(clock.day_index); work.minutes_today = 0
	var minutes := int(active.due)-int(active.started)
	work.minutes_today += maxi(0,int(active.due)-maxi(int(active.started),int(clock.day_index)*1440))
	work.paid_minutes += minutes
	work.earnings += paid

static func view(npc: Dictionary, catalog: Dictionary, clock: Dictionary) -> Dictionary:
	var job := profile(npc,catalog)
	if job.is_empty(): return {}
	var step := rank(npc,catalog)
	return {"id":npc.mind.employment.job,"title":job.title,"skill":job.skill,"skill_level":Progress.skill_level(float(npc.skills.get(job.skill,0))),
		"rank":step,"next_skill":int(gates(catalog)[mini(step,4)]),"location":location(npc,job),"hours":job.hours.duplicate(),"weekdays":job.weekdays.duplicate(),
		"hourly_pay":float(job.pay)*60.0/int(job.minutes)*Progress.pay_factor(step),"minutes_today":int(npc.mind.employment.minutes_today) if int(npc.mind.employment.day)==int(clock.day_index) else 0,
		"daily_limit":daily_limit(npc,catalog),
		"earnings":npc.mind.employment.earnings,"schedule":npc.schedule.filter(func(entry): return entry.get("activity","")=="work").duplicate(true)}
