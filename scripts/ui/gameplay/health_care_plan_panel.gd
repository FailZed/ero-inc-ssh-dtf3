extends RefCounted
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")

static func populate(owner: Control, parent: Node, entries: Array) -> void:
	if entries.is_empty(): return
	UI.label(parent,"Личный план здоровья",23,UI.BLUE)
	var sim = Gameplay.simulation
	var now := int(sim.state.clock.total_minutes)
	for item in entries:
		UI.label(parent,str(item.label),18,UI.INK)
		var due: Dictionary = sim.calendar.snapshot(int(item.due))
		var when := "Сегодня в %02d:%02d" % [int(due.hour),int(due.minute)] if int(due.day_index)==int(sim.state.clock.day_index) else "%d.%02d · %02d:%02d" % [int(due.day),int(due.month_number),int(due.hour),int(due.minute)]
		if item.status=="deferred": when = "Отложено на время беременности"
		elif item.status=="paused": when = "План приостановлен: нужно уточнить назначение у врача"
		elif item.status=="overdue": when = "Запланированное время прошло · "+when
		elif item.status=="waiting": when = "Все действия выполнены · наблюдение до "+when
		UI.label(parent,when,16,UI.ORANGE if item.status in ["overdue","paused"] else UI.MUTED)
		if item.has("completed"): UI.label(parent,"Выполнено %d из %d · запас для ухода: %d" % [int(item.completed),int(item.required),int(item.supplies)],16,UI.MUTED)
		if item.operation.is_empty(): continue
		var args := {"condition":str(item.condition)} if not str(item.condition).is_empty() else {}
		var captions := {"care_step":"Выполнить назначенный уход","care_review":"Уточнить план у врача","treat":"Начать назначенный курс","screen":"Пройти плановый скрининг","followup":"Пройти уточняющий осмотр","vaccinate":"Пройти следующий этап вакцинации"}
		var spec: Dictionary = sim.services.adult_health.config().actions[item.operation]
		owner._offer(parent,str(captions[item.operation]),"%d мин · %d ¤" % [int(spec.minutes),int(spec.cost)],"adult_health",str(item.operation),args)
		if int(item.due)<=now and item.status!="deferred": owner._offer(parent,"Напомнить через два часа","Срок плана при этом не меняется","adult_health","snooze_care",{"id":str(item.id)})
