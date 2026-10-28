extends "res://scripts/mechanics/core/module.gd"
## Subject-specific learning. World owns travel and attendance windows.
const Check = preload("res://scripts/mechanics/core/validation.gd")

static func defaults() -> Dictionary:
	return {"grade":0,"absences":0,"homework":false,"attended":[],"missed":[],"courses":{},"certificates":{},"history":[]}

func available() -> Array:
	var result: Array = []
	for id in sim.catalog.lessons:
		if Rules.check(sim.state,definition("lessons",str(id)).get("requirements",{})): result.append(str(id))
	result.sort()
	return result

func _record(id: String) -> Dictionary:
	return {"attendance":0,"assignments":0,"mastery":0.0,"homework_day":-1,"project":0,"approach":"","assessed_day":-1,"result":""} if not sim.state.world.education.courses.has(id) else sim.state.world.education.courses[id]

func view(id: String) -> Dictionary:
	var record := _record(id).duplicate(true)
	record.id = id
	record.selected = id in available()
	record.next_assignment = int(record.assessed_day) < 0 and int(record.homework_day) != int(sim.state.clock.day_index)
	record.can_assess = int(record.attendance) >= 3 and int(record.assignments) >= 2 and int(record.project) >= 3 and int(record.assessed_day) < 0
	record.certificate = int(sim.state.world.education.certificates.get(id,0))
	record.skill = str(definition("lessons",id).get("skill","study"))
	return record

func _store(id: String, record: Dictionary) -> void:
	sim.state.world.education.courses[id] = record

func attend(id: String, missed: bool = false) -> void:
	var record := _record(id)
	if missed: record.mastery = maxf(0,float(record.mastery)-2)
	else:
		record.attendance += 1
		record.mastery = minf(100,float(record.mastery)+8)
	_store(id,record)

func execute(operation: String, args: Dictionary) -> Dictionary:
	if operation == "inspect":
		var courses: Array = []
		for id in available(): courses.append(view(str(id)))
		return Rules.ok({"courses":courses,"history":sim.state.world.education.history.duplicate(true)})
	if not operation in ["homework","practice","project","assess","next_term"]: return Rules.fail("unknown_operation")
	var id := str(args.get("id",""))
	if id.is_empty():
		for candidate in available():
			if int(_record(str(candidate)).homework_day) != int(sim.state.clock.day_index): id = str(candidate); break
		if id.is_empty(): return Rules.fail("homework_already_submitted")
	if not id in available(): return Rules.fail("lesson_not_selected")
	var record := _record(id)
	var education: Dictionary = sim.state.world.education
	var skill := str(definition("lessons",id).get("skill","study"))
	if operation == "next_term":
		if int(record.assessed_day) < 0 or int(sim.state.clock.day_index)-int(record.assessed_day) < 7: return Rules.fail("next_term_not_ready")
		education.courses.erase(id)
		return Rules.ok({"id":id,"description":"Открыт следующий учебный модуль. Сертификаты сохраняются."})
	if int(record.assessed_day) >= 0: return Rules.fail("course_already_assessed")
	var minutes := 45
	var energy := 3.0
	var xp := 5
	if operation == "homework" and int(record.homework_day) == int(sim.state.clock.day_index): return Rules.fail("homework_already_submitted")
	if operation == "practice":
		if int(record.get("practice_day",-1)) == int(sim.state.clock.day_index): return Rules.fail("study_practice_limit")
		minutes = 30
		xp = 8
	if operation == "project":
		if int(record.project) >= 3: return Rules.fail("study_project_complete")
		var approach := str(args.get("approach",record.approach if not str(record.approach).is_empty() else "applied"))
		if not approach in ["applied","research","presentation"]: return Rules.fail("invalid_study_approach")
		if not str(record.approach).is_empty() and approach != record.approach: return Rules.fail("study_approach_locked")
		if int(record.get("project_day",-1)) == int(sim.state.clock.day_index): return Rules.fail("study_project_daily_limit")
		record.approach = approach
		minutes = 60
		energy = 6
		xp = 12
	if operation == "assess":
		if education.get("expelled",false): return Rules.fail("education_expelled")
		if not view(id).can_assess: return Rules.fail("study_assessment_requirements")
		if sim.state.world.location != definition("lessons",id).get("location",""): return Rules.fail("wrong_location")
		minutes = 60
		energy = 8
		xp = 20
	elif sim.state.world.location not in ["bedroom","kitchen","apartment_hall","bathroom","training_center"]:
		return Rules.fail("study_workspace_required")
	if float(sim.state.player.needs.energy) < energy: return Rules.fail("insufficient_energy")
	sim.services.character.adjust_need("energy",-energy)
	# Store before time advances; all writes are covered by Simulation's transaction.
	_store(id,record)
	var elapsed: Dictionary = sim.advance(minutes)
	if not elapsed.ok: return elapsed
	var day := int(sim.state.clock.day_index)
	match operation:
		"homework":
			record.homework_day = day
			record.assignments += 1
			record.mastery = minf(100,float(record.mastery)+6)
			education.homework = true
			education.grade += 2
		"practice":
			record.practice_day = day
			record.mastery = minf(100,float(record.mastery)+4)
		"project":
			record.project += 1
			record.project_day = day
			record.mastery = minf(100,float(record.mastery)+10)
			var specialty := {"applied":skill,"research":"study","presentation":"journalism"}
			sim.services.character.execute("train",{"skill":specialty[record.approach],"xp":8})
		"assess":
			var quality := minf(100,float(record.mastery)+minf(15,float(sim.state.player.skills.get(skill,0))*0.05))
			record.result = "distinction" if quality >= 85 else "passed"
			record.assessed_day = day
			education.certificates[id] = int(education.certificates.get(id,0))+1
			education.grade += 5 if quality >= 85 else 3
			sim.state.economy.cash += 60 if quality >= 85 else 30
			sim.state.world.flags["qualified_"+skill] = true
			education.history.append({"id":id,"day":day,"result":record.result,"approach":record.approach})
			while education.history.size() > 24: education.history.pop_front()
			emit_event("education_certificate",{"id":id,"result":record.result,"skill":skill})
	var trained: Dictionary = sim.services.character.execute("train",{"skill":skill,"xp":xp})
	if not trained.ok: return trained
	return Rules.ok({"id":id,"operation":operation,"course":view(id),"description":_description(operation,record)})

func _description(operation: String, record: Dictionary) -> String:
	match operation:
		"homework": return "Задание сдано. Подготовка +6; следующая оценочная работа — завтра."
		"practice": return "Материал закреплён. Практика даёт навык и подготовку, без повторной оценки."
		"project": return "Проект: этап %d из 3. К следующему этапу можно вернуться завтра." % record.project
		"assess": return "Модуль завершён с отличием. Получены сертификат и стипендия." if record.result == "distinction" else "Модуль завершён. Получены сертификат и стипендия."
	return ""

static func state_error(state: Dictionary, catalog: Dictionary) -> String:
	var e: Dictionary = state.world.education
	if not Check.fields(e,{"courses":"d","certificates":"d","history":"a"}) or e.history.size() > 24: return "invalid_education_progress"
	for id in e.courses:
		var c: Variant = e.courses[id]
		if not catalog.lessons.has(id) or not Check.fields(c,{"attendance":"n","assignments":"n","mastery":"n","homework_day":"n","project":"n","approach":"s","assessed_day":"n","result":"s"}): return "invalid_course"
		for key in ["attendance","assignments","project"]:
			if c[key] < 0 or int(c[key]) != c[key]: return "invalid_course"
		if c.mastery < 0 or c.mastery > 100 or c.project > 3 or not c.approach in ["","applied","research","presentation"] or not c.result in ["","passed","distinction"]: return "invalid_course"
		for key in ["homework_day","assessed_day","practice_day","project_day"]:
			var day: Variant = c.get(key,-1)
			if not Check.number(day) or int(day) != day or day < -1 or day > int(state.clock.total_minutes)/1440: return "invalid_course_day"
	for id in e.certificates:
		if not catalog.lessons.has(id) or not Check.number(e.certificates[id]) or e.certificates[id] < 1 or int(e.certificates[id]) != e.certificates[id]: return "invalid_certificate"
	for entry in e.history:
		if not Check.fields(entry,{"id":"s","day":"n","result":"s","approach":"s"}) or not catalog.lessons.has(entry.id): return "invalid_education_history"
		if entry.day < 0 or entry.day > int(state.clock.total_minutes)/1440 or int(entry.day) != entry.day or not entry.result in ["passed","distinction"] or not entry.approach in ["applied","research","presentation"]: return "invalid_education_history"
	return ""
