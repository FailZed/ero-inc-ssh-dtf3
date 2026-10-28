extends "res://scripts/mechanics/core/module.gd"
## Fictional care routines and confidential reminders, not medication instructions.

func health():
	return sim.services.adult_health

func now() -> int:
	return int(sim.state.clock.total_minutes)

func rules() -> Dictionary:
	return health().config().care_plans

func begin(id: String, key: String) -> void:
	var condition: Dictionary = health().record(id).conditions[key]
	var duration := int(health().config().conditions[key].treatment_minutes)
	var required := maxi(1,ceili(duration/float(rules().interval_minutes)))
	condition.course = {"started":now(),"required":required,"completed":1,"supplies":required-1,
		"missed":0,"missed_since_review":0,"last_performed":now(),
		"next_due":now()+int(rules().interval_minutes) if required>1 else 0,
		"finish_after":now()+duration,"starting_severity":int(condition.severity),
		"review_required":false,"review_pending":false}
	condition.treatment_until = int(condition.course.finish_after)
	condition.review_at = int(condition.course.finish_after)+int(rules().review_delay_minutes)

func step_blocked(id: String, key: String, minutes: int = 0) -> String:
	var condition: Dictionary = health().record(id).conditions.get(key,{})
	var course: Dictionary = condition.get("course",{})
	if condition.get("status","")!="active" or course.is_empty(): return "care_plan_required"
	if course.review_required: return "care_plan_review_required"
	if int(course.completed)>=int(course.required): return "care_course_waiting"
	if now()<int(course.next_due): return "care_step_not_due"
	if now()+minutes>int(course.next_due)+int(rules().window_minutes): return "care_window_closing"
	if int(course.supplies)<1: return "care_supplies_missing"
	return ""

func perform_step(id: String, key: String) -> void:
	var c: Dictionary = health().record(id).conditions[key]
	var course: Dictionary = c.course
	course.completed += 1
	course.supplies -= 1
	course.last_performed = now()
	course.next_due = now()+int(rules().interval_minutes) if int(course.completed)<int(course.required) else 0
	c.severity = maxi(5,roundi(int(course.starting_severity)*(1.0-0.8*float(course.completed)/int(course.required))))
	health().adjust(id,"energy",-1)
	health().log_event("care_step",{"target":id,"condition":key,"text":"Выполнен очередной пункт согласованного плана ухода."})

func review(id: String, key: String) -> void:
	var c: Dictionary = health().record(id).conditions[key]
	var course: Dictionary = c.course
	course.review_required = false
	course.review_pending = false
	course.missed_since_review = 0
	if c.status=="active" and int(course.completed)<int(course.required):
		course.next_due = now()
		course.finish_after = maxi(int(course.finish_after),now()+(int(course.required)-int(course.completed))*int(rules().interval_minutes))
		c.treatment_until = int(course.finish_after)
		c.review_at = int(course.finish_after)+int(rules().review_delay_minutes)
	else: c.review_at = 0
	health().log_event("care_review",{"target":id,"condition":key,"text":"Врач уточнил план ухода с учётом выполненных и пропущенных действий."})

func tick_actor(id: String) -> void:
	var r: Dictionary = health().record(id)
	for key in r.conditions:
		var c: Dictionary = r.conditions[key]
		var course: Dictionary = c.course
		if c.status!="active" or course.is_empty(): continue
		if int(course.completed)>=int(course.required):
			if now()>=int(course.finish_after):
				c.status = "resolved"
				course.review_pending = true
				c.review_at = now()+int(rules().review_delay_minutes)
				health().log_event("treatment_finished",{"target":id,"condition":key,"text":"План ухода выполнен, самочувствие улучшилось. Повторный осмотр отмечен в личном календаре."})
			continue
		if course.review_required or now()<=int(course.next_due)+int(rules().window_minutes): continue
		var missed := mini(int(rules().misses_before_review)-int(course.missed_since_review),1+floori((now()-int(course.next_due)-int(rules().window_minutes)-1)/float(rules().interval_minutes)))
		course.missed += missed
		course.missed_since_review += missed
		course.next_due += missed*int(rules().interval_minutes)
		course.finish_after += missed*int(rules().interval_minutes)
		c.treatment_until = int(course.finish_after)
		c.review_at = int(course.finish_after)+int(rules().review_delay_minutes)
		if int(course.missed_since_review)>=int(rules().misses_before_review): course.review_required = true; course.review_pending = true; c.review_at = now()
		health().adjust(id,"mood",-1)
		health().log_event("care_missed",{"target":id,"condition":key,"text":"Пропущен пункт плана ухода. Завершение курса отложено."})
	for item in view(id):
		if item.operation.is_empty() or item.status in ["upcoming","deferred","waiting"]: continue
		var notice: Dictionary = r.care_notices.get(item.id,{"last":-10080,"snoozed_until":0})
		if now()<int(notice.snoozed_until) or (int(notice.snoozed_until)==0 and now()-int(notice.last)<int(rules().reminder_minutes)): continue
		r.care_notices[item.id] = {"last":now(),"snoozed_until":0}
		health().log_event("care_reminder",{"target":id,"task":item.id,"text":"Личный план здоровья: "+str(item.label)+"."})

func _item(id: String, label: String, operation: String, due: int, condition: String = "", status: String = "") -> Dictionary:
	return {"id":id,"label":label,"operation":operation,"due":due,"condition":condition,
		"status":status if not status.is_empty() else "upcoming" if due>now() else "overdue" if now()-due>=int(rules().interval_minutes) else "ready"}

func view(id: String) -> Array:
	var r: Dictionary = health().record(id)
	if r.is_empty() or not health().enabled(): return []
	var result: Array = []
	for key in r.conditions:
		var c: Dictionary = r.conditions[key]
		if not c.known: continue
		var label := str(health().config().conditions[key].label)
		var course: Dictionary = c.course
		if course.is_empty():
			if c.status=="active": result.append(_item("course:"+str(key),"Начать назначенный уход: "+label,"treat",now(),str(key)))
			continue
		if course.review_required or (course.review_pending and c.status=="resolved"):
			result.append(_item("review:"+str(key),"Повторный осмотр: "+label,"care_review",int(c.review_at),str(key),"paused" if course.review_required else ""))
		elif c.status=="active":
			var waiting := int(course.completed)>=int(course.required)
			var item := _item("course:"+str(key),"Уход по назначению: "+label,"" if waiting else "care_step",int(course.finish_after) if waiting else int(course.next_due),str(key),"waiting" if waiting else "")
			item.completed = int(course.completed)
			item.required = int(course.required)
			item.supplies = int(course.supplies)
			result.append(item)
	if r.screening.followup: result.append(_item("followup","Уточняющий осмотр после скрининга","followup",maxi(0,int(r.screening.last))))
	elif int(r.screening.last)>=0: result.append(_item("screen","Плановый скрининг","screen",int(r.screening.next)))
	if int(r.vaccine.doses)>0 and int(r.vaccine.doses)<3:
		result.append(_item("vaccine","Следующий этап вакцинации","vaccinate",int(r.vaccine.next_dose),"","deferred" if health().pregnant(id) else ""))
	result.sort_custom(func(a,b): return int(a.due)<int(b.due) if a.due!=b.due else str(a.id)<str(b.id))
	return result

func next_action(id: String) -> Dictionary:
	for item in view(id):
		if item.operation.is_empty() or not item.status in ["ready","overdue","paused"]: continue
		if id!="player" and int(health().actor(id).money)<health().care.price(str(item.operation)): continue
		return item
	return {}

func snooze(id: String, key: String) -> Dictionary:
	var found := false
	for item in view(id):
		if item.id==key and item.status in ["ready","overdue","paused"]: found = true
	if not found: return Rules.fail("care_reminder_unavailable")
	var notices: Dictionary = health().record(id).care_notices
	var notice: Dictionary = notices.get(key,{"last":-10080,"snoozed_until":0})
	notice.snoozed_until = now()+int(rules().snooze_minutes)
	notices[key] = notice
	return Rules.ok()
