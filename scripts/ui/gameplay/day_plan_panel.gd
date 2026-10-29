extends RefCounted
## Read-only day outlook; actions still go through the existing queue or Gameplay.execute.
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const W = preload("res://scripts/ui/gameplay/game_widgets.gd")

const NEEDS := {"health":"Здоровье", "energy":"Силы", "satiety":"Сытость", "hydration":"Вода", "rested":"Отдых", "hygiene":"Гигиена", "bladder":"Туалет", "fun":"Досуг", "social":"Общение"}
const KINDS := {"rent":"Аренда", "rent_debt":"Долг за жильё", "family":"Семейный уход", "family_debt":"Семейный долг", "child_support":"Алименты", "credit_interest":"Проценты по долгу", "appointment":"Встреча", "promise":"Обещание", "contract":"Срок заказа", "computer_project":"Срок компьютерного заказа", "local_order":"Срок городского заказа", "quest":"Срок задания", "pressure":"Чужое давление"}

static func render(owner: Control, parent: Node) -> void:
	var sim = Gameplay.simulation
	var planning = sim.services.planning
	var horizon := str(owner._screen_state.get("plan_horizon", "7"))
	if not horizon in ["7", "30"]: horizon = "7"
	W.tabs(parent, {"7":"7 дней", "30":"30 дней"}, horizon, owner._choose_screen.bind("plan_horizon"))
	var budget: Dictionary = planning.budget(int(horizon))
	var card := W.panel(parent)
	UI.label(card, "Обязательные деньги на %s дней" % horizon, 22)
	UI.label(card, "Сейчас %d €$ · платежи %d €$ · доход активов %d €$" % [int(budget.available), int(budget.scheduled_expenses), int(budget.asset_net_income)], 18, UI.MUTED)
	UI.label(card, "После известных платежей: %d €$" % int(budget.after_scheduled), 23, UI.ORANGE if int(budget.after_scheduled) < 0 else UI.BLUE)
	UI.label(card, str(budget.description), 16, UI.MUTED)
	for bill in budget.bills:
		var due: Dictionary = sim.calendar.snapshot(int(bill.minute))
		UI.label(card, "%s · %s %s · %d €$" % [KINDS.get(str(bill.kind), str(bill.kind)), due.date_text, due.time_text, int(bill.amount)], 17)
	var priorities: Array = planning.priorities()
	if not priorities.is_empty():
		UI.label(parent, "Что требует внимания", 21, UI.BLUE)
		var list := W.grid(parent, 2)
		for priority in priorities:
			var row := W.panel(list)
			if priority.kind == "need":
				UI.label(row, "%s · %d/100" % [NEEDS.get(str(priority.id), str(priority.id)), roundi(float(priority.value))], 18, UI.ORANGE if bool(priority.urgent) else UI.MUTED)
			else:
				var due: Dictionary = sim.calendar.snapshot(int(priority.minute))
				UI.label(row, "%s · %s" % [KINDS.get(str(priority.kind), str(priority.kind)), str(priority.id)], 18)
				UI.label(row, "%s · %s" % [due.date_text, due.time_text], 16, UI.ORANGE)
	var opportunities: Array = planning.opportunities()
	if not opportunities.is_empty():
		UI.label(parent, "Можно завершить сейчас", 21, UI.BLUE)
		var list := W.grid(parent, 2)
		for opportunity in opportunities:
			var row := W.panel(list)
			UI.label(row, str(opportunity.title), 19)
			var command: Dictionary = opportunity.command
			UI.button(row, "Завершить дело", owner._act.bind(str(command.module), str(command.operation), command.args))
	var entries: Array = owner._queue.entries
	if not entries.is_empty():
		UI.label(parent, "Прогноз текущего плана", 21, UI.BLUE)
		var forecast: Dictionary = planning.forecast(entries)
		if forecast.ok:
			var result: Dictionary = forecast.data
			var summary := "%d мин · деньги %+d €$ · силы %+.0f" % [int(result.minutes), int(result.cash_delta), float(result.energy_delta)]
			UI.label(parent, summary, 19)
			for step in result.steps:
				var label := "Шаг %d: " % [int(step.index)+1]
				if step.get("uncertain", false): label += "случайный или интерактивный исход — дальнейший расчёт остановлен"
				elif step.ok: label += "%d мин" % int(step.minutes)
				else: label += "недоступно (%s)" % str(step.reason)
				UI.label(parent, label, 17, UI.ORANGE if step.get("uncertain", false) or not step.get("ok", true) else UI.MUTED)
			UI.label(parent, str(result.description), 16, UI.MUTED)
	UI.label(parent, "Предложенные бытовые шаги", 21, UI.BLUE)
	var routine_id := str(owner._screen_state.get("plan_routine", "morning"))
	if not routine_id in ["morning", "recovery", "study"]: routine_id = "morning"
	W.tabs(parent, {"morning":"Утро", "recovery":"Восстановление", "study":"Учёба"}, routine_id, owner._choose_screen.bind("plan_routine"))
	var routine: Dictionary = planning.routine(routine_id)
	if not routine.ok:
		UI.label(parent, "Пока нет домашнего места для такого плана.", 17, UI.ORANGE)
		return
	if routine.data.actions.is_empty():
		UI.label(parent, "Сейчас обязательных шагов нет.", 17, UI.MUTED)
		return
	for step in routine.data.actions:
		var row := UI.row(parent)
		UI.label(row, str(step.title), 17)
		var entry: Dictionary = step.duplicate(true)
		UI.button(row, "В план", func(): owner._queue.enqueue(entry); owner._refresh())
