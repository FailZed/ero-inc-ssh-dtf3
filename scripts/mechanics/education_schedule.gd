extends RefCounted
## One timetable for enrolment, attendance and work forecasts.
const SUBJECTS := {
	"computing":{"title":"Основы программирования","skill":"computing","days":[2,4],"hours":[600,660]},
	"physics":{"title":"Прикладная физика","skill":"study","days":[2,4],"hours":[660,720]},
	"statistics":{"title":"Генетическая статистика","skill":"study","days":[3,5],"hours":[600,660]},
	"genetics":{"title":"Генная инженерия","skill":"study","days":[3,5],"hours":[660,720]},
	"bioengineering":{"title":"Биоинженерия","skill":"study","days":[2,4],"hours":[720,780]},
	"behavior":{"title":"Поведенческая биология","skill":"study","days":[3,5],"hours":[720,780]}
}
const SPORTS := {"running":"Бег", "strength":"Силовая подготовка", "combat":"Самооборона"}
const LATE_MINUTES := 15

static func defaults() -> Dictionary:
	return {"enrolled":true,"subjects":["computing","physics","statistics"]}

static func valid_plan(plan: Variant) -> bool:
	if not plan is Dictionary or plan.size() != 2 or not plan.get("enrolled") is bool or not plan.get("subjects") is Array: return false
	if not plan.enrolled: return plan.subjects.is_empty()
	return valid_subjects(plan.subjects)

static func valid_subjects(subjects: Array) -> bool:
	if subjects.size() < 2 or subjects.size() > 4: return false
	var unique := {}
	for id in subjects:
		if not id is String or not SUBJECTS.has(id) or unique.has(id): return false
		unique[id] = true
	return true

static func apply_plan(state: Dictionary, enrolled: bool, subjects: Array) -> void:
	state.world.flags.student_enrolled = enrolled
	for id in SUBJECTS: state.world.flags["subject_"+id] = enrolled and id in subjects

static func lessons(venues: Dictionary) -> Dictionary:
	var enrolled := {"path":"world.flags.student_enrolled","value":true}
	var result := {"common_day":{"location":str(venues["common_day"]),"hours":[600,660],"weekdays":[1],"minutes":60,"skill":"study","xp":15,"grade":2,"absence_penalty":1,"requirements":enrolled}}
	for id in SUBJECTS:
		var entry: Dictionary = SUBJECTS[id]
		result["computing_class" if id == "computing" else id+"_class"] = {"location":str(venues["computing_class" if id == "computing" else id+"_class"]),"hours":entry.hours,"weekdays":entry.days,"minutes":60,"skill":entry.skill,"xp":20,"grade":3,"absence_penalty":1,"requirements":{"all":[enrolled,{"path":"world.flags.subject_"+id,"value":true}]}}
	return result

static func slot(lesson: Dictionary, day_index: int) -> Dictionary:
	var begins := day_index*1440+int(lesson.hours[0])
	var closes := day_index*1440+int(lesson.hours[1])
	if closes <= begins: closes += 1440
	return {"start":begins,"end":closes,"deadline":mini(begins+LATE_MINUTES,closes-1)}

static func attendance(lesson: Dictionary, clock: Dictionary) -> Dictionary:
	var window := slot(lesson,int(clock.day_index))
	var now := int(clock.total_minutes)
	var late := maxi(0,now-int(window.start))
	var duration := mini(int(lesson.get("minutes",60)),maxi(0,int(window.end)-now))
	var fraction := float(duration)/maxi(1,int(lesson.get("minutes",60)))
	return {"allowed":now >= int(window.start) and now <= int(window.deadline),"late_minutes":late,"minutes":duration,
		"xp":floori(int(lesson.get("xp",10))*fraction),"grade":snappedf(float(lesson.get("grade",1))*fraction,0.01)}

static func forecast(lesson: Dictionary, day_index: int, arrival: int) -> Dictionary:
	var window := slot(lesson,day_index)
	window.arrival = arrival
	window.late_minutes = maxi(0,arrival-int(window.start))
	window.can_attend = arrival <= int(window.deadline)
	window.consequence = "late" if window.can_attend else "absence"
	return window
