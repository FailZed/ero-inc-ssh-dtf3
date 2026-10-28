extends "res://scripts/mechanics/core/module.gd"
## Read-only planning queries. Commands are executed only on an isolated copy.

func execute(operation: String, args: Dictionary) -> Dictionary:
	match operation:
		"inspect": return Rules.ok({"budget":budget(int(args.get("days",7))),"priorities":priorities(),"opportunities":opportunities()})
		"forecast": return forecast(args.get("actions",[]))
		"routine": return routine(str(args.get("id","morning")))
	return Rules.fail("unknown_operation")

func budget(days: int = 7) -> Dictionary:
	days = clampi(days,1,90)
	var now := int(sim.state.clock.total_minutes)
	var end := now+days*1440
	var bills: Array = []
	var income := 0
	for id in sim.state.economy.assets:
		var spec := definition("assets",str(id))
		income += days*(int(spec.get("daily_income",0))*int(sim.state.economy.assets[id].level)-int(spec.get("daily_expense",0)))
	for id in sim.state.housing.properties:
		var property: Dictionary = sim.state.housing.properties[id]
		if property.owned: continue
		# Existing debt survives eviction and the rent toggle.
		if int(property.arrears) > 0: bills.append({"kind":"rent_debt","id":id,"minute":now,"amount":int(property.arrears)})
		if property.get("evicted",false) or not sim.services.preferences.rule("rent_enabled",true): continue
		var due := int(property.next_bill)
		while due <= end:
			bills.append({"kind":"rent","id":id,"minute":due,"amount":int(definition("properties",str(id)).get("monthly_rent",0))})
			due = sim.calendar.add_months(due,1)
	var family_cost := 0
	for member in sim.state.get("family",{}).get("members",{}).values():
		if "player" in member.get("guardians",member.parents): family_cost += int(sim.catalog.family_rules.household.daily_cost)*days
	if family_cost > 0: bills.append({"kind":"family","minute":end,"amount":family_cost})
	var family_debt := int(sim.state.get("family",{}).get("arrears",0))
	if family_debt > 0: bills.append({"kind":"family_debt","minute":now,"amount":family_debt})
	for obligation in sim.state.get("child_support",{}).get("obligations",{}).values():
		if obligation.payer != "player": continue
		var amount := int(obligation.arrears)
		var due := int(obligation.next_due)
		while obligation.active and due <= end and due < int(obligation.ends_at):
			amount += int(obligation.monthly)
			due = sim.calendar.add_months(due,1)
		if amount > 0: bills.append({"kind":"child_support","id":obligation.id,"minute":mini(end,int(obligation.next_due)),"amount":amount})
	var debt := int(sim.state.economy.debt)
	var initial_debt := debt
	for day in range(int(sim.state.clock.day_index)+1,int(sim.state.clock.day_index)+days+1):
		if int(sim.calendar.snapshot(day*1440).weekday) == 1: debt += ceili(debt*float(sim.catalog.settings.weekly_debt_interest))
	if debt > initial_debt: bills.append({"kind":"credit_interest","minute":end,"amount":debt-initial_debt})
	var total := 0
	for bill in bills: total += int(bill.amount)
	bills.sort_custom(func(a,b): return int(a.minute) < int(b.minute))
	var funds := int(sim.state.economy.cash)+int(sim.state.economy.bank)
	var reserved := mini(family_cost+family_debt,int(sim.state.get("family",{}).get("budget",0)))
	return {"days":days,"available":funds,"scheduled_expenses":total,"asset_net_income":income,"family_reserve_used":reserved,"after_scheduled":funds+income-total+reserved,"bills":bills,"description":"Обязательные платежи и доход активов. Еда, покупки, лечение, будущая работа и погашение основного кредита не включены."}

func priorities() -> Array:
	var result: Array = []
	var needs: Dictionary = sim.state.player.needs
	for id in ["health","energy","satiety","hydration","rested","hygiene","bladder","fun","social"]:
		if not needs.has(id) or float(needs[id]) >= 30: continue
		if sim.services.has("growth") and not sim.services.growth.enabled(id): continue
		result.append({"kind":"need","id":id,"value":needs[id],"urgent":float(needs[id]) < 15})
	var obligations: Array = preload("res://scripts/gameplay/action_policy.gd").commitments(sim.state,int(sim.state.clock.total_minutes)+1440)
	for entry in obligations: result.append(entry.duplicate(true))
	return result

func opportunities() -> Array:
	var result: Array = []
	for id in sim.state.computer.projects:
		if sim.services.computer.project_view(str(id)).ready:
			result.append({"kind":"computer_project","id":id,"title":"Проект готов к сдаче клиенту","command":{"module":"computer","operation":"deliver_project","args":{"id":id}}})
	for id in sim.services.education.available():
		var course: Dictionary = sim.services.education.view(str(id))
		if course.can_assess: result.append({"kind":"education","id":id,"title":"Готовность к аттестации","command":{"module":"education","operation":"assess","args":{"id":id}}})
	for id in sim.state.journal.quests:
		var quest: Dictionary = sim.state.journal.quests[id]
		if quest.status == "completed" and not quest.claimed: result.append({"kind":"quest","id":id,"title":"Награда за выполненное задание","command":{"module":"events","operation":"claim_quest","args":{"id":id}}})
	for id in sim.state.careers.contracts:
		var contract: Dictionary = sim.state.careers.contracts[id]
		if contract.status == "completed" and not contract.claimed: result.append({"kind":"contract","id":id,"title":"Готовый заказ ждёт сдачи","command":{"module":"careers","operation":"claim_contract","args":{"id":id}}})
	return result

func routine(id: String) -> Dictionary:
	if not id in ["morning","recovery","study"]: return Rules.fail("unknown_routine")
	if sim.state.housing.residence.is_empty() and sim.state.world.flags.get("chapter_one_complete",false): return Rules.fail("no_current_home")
	var steps: Array = []
	var location := str(sim.state.world.location)
	var add := func(room: String, module_id: String, operation: String, args: Dictionary):
		steps.append({"module":"world","operation":"journey","args":{"id":room},"title":"Перейти: "+str({"bedroom":"спальня","bathroom":"ванная","kitchen":"кухня"}.get(room,room))})
		steps.append({"module":module_id,"operation":operation,"args":args,"title":str({"nap":"Вздремнуть","toilet":"Сходить в туалет","shower":"Принять душ","drink":"Выпить воды","use":"Поесть","homework":"Выполнить учебное задание"}.get(operation,operation))})
	if id == "recovery": add.call("bedroom","needs","nap",{"minutes":30})
	if id in ["morning","recovery"]:
		if float(sim.state.player.needs.get("bladder",100)) < 70: add.call("bathroom","needs","toilet",{})
		if float(sim.state.player.needs.hygiene) < 70: add.call("bathroom","world","shower",{})
		if float(sim.state.player.needs.get("hydration",100)) < 80: add.call("kitchen","needs","drink",{})
		if float(sim.state.player.needs.satiety) < 70:
			for item in sim.state.inventory.items:
				if float(definition("items",str(item)).get("restore",{}).get("satiety",0)) > 0:
					add.call("kitchen","inventory","use",{"id":item})
					break
	else:
		for course in sim.services.education.available():
			if sim.services.education.view(str(course)).next_assignment:
				add.call("bedroom","education","homework",{"id":course})
				break
	var compact: Array = []
	for step in steps:
		if step.module == "world" and step.operation == "journey":
			if step.args.id == location: continue
			location = str(step.args.id)
		compact.append(step)
	return Rules.ok({"id":id,"actions":compact,"description":"Предлагаемые шаги. Каждый выполняется отдельной обычной командой; план можно изменить или остановить."})

func forecast(actions: Variant) -> Dictionary:
	if not actions is Array or actions.size() > 12: return Rules.fail("invalid_plan")
	for action in actions:
		if not action is Dictionary or not action.get("module") is String or not action.get("operation") is String or not action.get("args",{}) is Dictionary or action.module == "planning": return Rules.fail("invalid_plan")
	var copy = sim.get_script().new(sim._initial_seed,sim.catalog.duplicate(true))
	var restored: Dictionary = copy.restore_snapshot(sim.export_snapshot())
	if not restored.ok: return restored
	copy.services.antagonism.forecast_mode = true
	var initial: Dictionary = copy.state.duplicate(true)
	var rows: Array = []
	var complete := true
	for index in range(actions.size()):
		var action: Dictionary = actions[index]
		var before := int(copy.state.clock.total_minutes)
		if action.module == "antagonism":
			rows.append({"index":index,"uncertain":true,"reason":"autonomous_social_risk","minute":before})
			complete = false
			break
		# Do not reveal a future RNG draw through the preview.
		var uncertain: bool = action.module in ["combat","encounters","social","social_rules","npc_relationships","intimacy","companion","digital","security","computer"] or (action.module == "institutions" and action.operation == "hold_vote") or (action.module == "inventory" and action.operation == "craft") or (action.module == "livelihood" and action.operation in ["work","input"])
		if uncertain:
			rows.append({"index":index,"uncertain":true,"reason":"interactive_or_random","minute":before})
			complete = false
			break
		var result: Dictionary = copy.command(action.module,action.operation,action.get("args",{}))
		var conflicts: Array = preload("res://scripts/gameplay/action_policy.gd").commitments(initial,int(copy.state.clock.total_minutes))
		rows.append({"index":index,"ok":result.ok,"reason":str(result.get("error","")),"minutes":int(copy.state.clock.total_minutes)-before,"ending":copy.state.clock.duplicate(true),"conflicts":conflicts})
		if not result.ok:
			complete = false
			break
	return Rules.ok({"steps":rows,"complete":complete,"social_risk_unmodelled":sim.services.antagonism.enabled(),"minutes":int(copy.state.clock.total_minutes)-int(initial.clock.total_minutes),"cash_delta":int(copy.state.economy.cash)-int(initial.economy.cash),"energy_delta":float(copy.state.player.needs.energy)-float(initial.player.needs.energy),"description":"Расчёт на копии текущего мира. Новые самостоятельные угрозы не предсказываются; уже известные сроки учитываются. План останавливается перед случайным или интерактивным исходом; условия проверяются заново."})
