extends RefCounted
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const Names = preload("res://scripts/gameplay/presentation.gd")
const W = preload("res://scripts/ui/gameplay/game_widgets.gd")
const CHOICES := {"accept":"Продолжить разговор", "decline":"Отказаться", "non_reproductive":"Близость без возможности зачатия", "pregnancy_possible":"Близость с возможностью зачатия", "plan_pregnancy":"Попробовать зачать ребёнка", "stop":"Остановиться", "barrier":"Использовать барьерную защиту", "regular_method":"Полагаться на действующую контрацепцию", "unprotected":"Без барьерной защиты", "start":"Провести время вместе", "finish":"Завершить время наедине", "close":"Закончить встречу"}
const STAGES := {"invitation":"Предложение", "discussion":"Намерения", "protection":"Защита", "ready":"Совместное решение", "active":"Время наедине", "aftercare":"После встречи"}

static func encounter(owner: Control, parent: VBoxContainer) -> bool:
	var sim = Gameplay.simulation
	var request: Dictionary = sim.services.intimacy.presentation()
	if request.is_empty(): return false
	var session: Dictionary = sim.state.intimacy.active
	var columns := UI.row(parent,36)
	var identity := UI.column(columns,12)
	identity.custom_minimum_size.x = 260
	var portrait := preload("res://scripts/ui/gameplay/resident_preview.gd").new()
	portrait.custom_minimum_size = Vector2(260,350)
	portrait.set_actor(sim.state.social.npcs[session.npc])
	identity.add_child(portrait)
	UI.label(identity,str(sim.state.social.npcs[session.npc].name),25)
	parent = UI.column(columns,18)
	parent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.label(parent, "Время наедине · " + str(sim.state.social.npcs[session.npc].name), 30, UI.BLUE)
	UI.label(parent, str(STAGES[request.stage]), 24)
	UI.label(parent,"Выберите, как провести время вместе. Перед началом можно обсудить планы и защиту. Любой участник может остановить встречу.",19,UI.MUTED)
	var acknowledge: CheckBox
	if request.stage == "protection" and session.potential_conception:
		acknowledge = CheckBox.new()
		acknowledge.text = "Я принимаю возможность незапланированной беременности"
		parent.add_child(acknowledge)
	for entry in request.choices:
		var args := {"session":request.session,"revision":request.revision,"choice":entry.id}
		var button := UI.button(parent, str(CHOICES[entry.id]), func():
			var chosen := args.duplicate()
			if entry.id == "unprotected": chosen.risk_acknowledged = acknowledge.button_pressed
			owner._act("intimacy","choose",chosen))
		button.disabled = not entry.enabled
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size.y = 58
		button.set_meta("gameplay_action",{"module":"intimacy","operation":"choose","args":args.duplicate(true)})
		if not entry.enabled: button.tooltip_text = Names.error(str(entry.reason))
		if entry.id == "unprotected" and session.potential_conception and entry.enabled:
			button.disabled = true
			acknowledge.toggled.connect(func(accepted): button.disabled = not accepted)
	return true

static func confirm(owner: Control, title: String, module_id: String, operation: String, args: Dictionary) -> void:
	preload("res://scripts/ui/gameplay/game_widgets.gd").confirm(owner,title,"Это решение повлияет на дальнейшую жизнь персонажа.","Подтвердить",func(): owner._act(module_id,operation,args))

static func populate(owner: Control, parent: VBoxContainer) -> void:
	var sim = Gameplay.simulation
	var r: Dictionary = sim.services.reproduction.view()
	var section := str(owner._screen_state.get("repro_tab","status"))
	W.tabs(parent,{"status":"Самочувствие","protection":"Контрацепция","family":"Семейные планы"},section,owner._choose_screen.bind("repro_tab"))
	if section == "status":
		preload("res://scripts/ui/gameplay/pregnancy_wellbeing_panel.gd").populate(owner,parent)
		var card := W.panel(parent)
		UI.label(card,"Личное здоровье",26)
		if r.cycling:
			var phases := {"menstruation":"Месячные","follicular":"Первая фаза цикла","ovulation":"Овуляция","luteal":"Вторая фаза цикла","pregnancy":"Беременность","none":"Нет цикла"}
			UI.label(card,"%s · день %d из %d" % [phases[r.phase],r.cycle_day,r.cycle_days],20)
		if r.infertile: UI.label(card,"Бесплодие",20,UI.MUTED)
		if r.sterilization != "none": UI.label(card,("Перевязка маточных труб" if r.sterilization=="tubal_ligation" else "Вазэктомия")+(" · действует" if r.sterile else " · результат ещё не вступил в силу"),20)
		if int(r.recovery_until)>int(sim.state.clock.total_minutes): UI.label(card,"Восстановление: ещё %d мин" % [int(r.recovery_until)-int(sim.state.clock.total_minutes)],19,UI.MUTED)
		if r.can_gestate: owner._offer(card,"Проверить беременность","5 мин · 10 €$","reproduction","test")
		if not r.cycling and not r.infertile and r.sterilization == "none": UI.label(card,"Сейчас нет особых состояний.",20,UI.MUTED)
	elif section == "protection":
		var setting := W.panel(parent)
		UI.label(setting,"Личные границы",24)
		var protection := CheckBox.new()
		protection.text = "Требовать защиту"
		protection.button_pressed = r.requires_protection
		protection.toggled.connect(func(value): owner._act("reproduction","preference",{"requires_protection":value}))
		setting.add_child(protection)
		if r.can_gestate:
			UI.label(setting,str(sim.catalog.contraceptive_methods[r.method].label)+(" · действует" if r.method_active else " · сейчас не действует"),19,UI.MUTED)
			var methods := W.grid(parent,2)
			for method in ["pill","iud","implant","none"]:
				if method==r.method and method!="pill": continue
				var spec: Dictionary = sim.catalog.contraceptive_methods[method]
				owner._offer(methods,"Отменить текущую контрацепцию" if method=="none" else str(spec.label),"%d мин · %d €$" % [spec.minutes,spec.cost],"reproduction","contraception",{"method":method})
			owner._offer(parent,"Экстренная контрацепция","Нужен предмет и недавний эпизод риска","reproduction","emergency")
		for id in sim.catalog.reproductive_procedures:
			var spec: Dictionary = sim.catalog.reproductive_procedures[id]
			if not r.get(spec.capability,false) or r.sterilization!="none": continue
			UI.button(parent,"Клиника: %s · %d €$" % [spec.label,spec.cost],confirm.bind(owner,str(spec.label),"reproduction","procedure",{"id":id,"confirm":true}))
	else:
		UI.label(parent,"Ваши планы",26)
		var desire := OptionButton.new()
		for id in {"avoid":"Не планирую ребёнка","open":"Допускаю ребёнка","want":"Хочу ребёнка"}:
			desire.add_item({"avoid":"Не планирую ребёнка","open":"Допускаю ребёнка","want":"Хочу ребёнка"}[id])
			desire.set_item_metadata(desire.item_count-1,id)
			if id == r.desire: desire.select(desire.item_count-1)
		desire.item_selected.connect(func(index): owner._act("reproduction","preference",{"desire":desire.get_item_metadata(index)}))
		parent.add_child(desire)
		var pregnancy: Dictionary = r.pregnancy
		if not pregnancy.is_empty() and pregnancy.known:
			UI.label(parent,"Подтверждённая беременность"+(" · запланированная" if pregnancy.intended else " · незапланированная"),23,UI.BLUE)
			for pair in [["continue","Продолжить беременность"],["adoption","Передача ребёнка на усыновление"],["terminate","Прервать беременность в клинике"]]:
				UI.button(parent,pair[1],confirm.bind(owner,str(pair[1]),"reproduction","pregnancy_decision",{"decision":pair[0],"confirm":true}))
		for p in sim.state.reproduction.pregnancies.values():
			if p.status!="active" or not p.known or p.partner!="player": continue
			UI.label(parent,"Будущий ребёнок · "+str(sim.state.social.npcs[p.target].name),22,UI.BLUE)
			if p.partner_response=="unasked":
				owner._offer(parent,"Поддержать будущего родителя","Принять участие в жизни ребёнка","reproduction","pregnancy_response",{"target":p.target,"response":"support"})
				UI.button(parent,"Отказаться от непосредственного участия",confirm.bind(owner,"Отказаться от ухода; алименты сохранятся","reproduction","pregnancy_response",{"target":p.target,"response":"decline_parenthood"}))
	if sim.state.world.location != "clinic": owner._offer(parent,"Доехать до клиники","Осмотры и репродуктивная помощь","world","journey",{"id":"clinic"})

static func support(owner: Control, parent: VBoxContainer) -> void:
	var sim = Gameplay.simulation
	UI.label(parent,"Алименты и опека",26,UI.BLUE)
	var count := 0
	for o in sim.state.child_support.obligations.values():
		if not "player" in [o.payer,o.recipient]: continue
		count+=1
		var card := UI.card(parent)
		UI.label(card,str(sim.state.family.members[o.member].name) + (" · вы платите" if o.payer=="player" else " · вам платят"),22)
		UI.label(card,"%d €$ в месяц · задолженность %d €$ · выплачено %d €$" % [o.monthly,o.arrears,o.paid],19,UI.MUTED)
		if o.payer=="player":
			var automatic := CheckBox.new()
			automatic.text = "Автоплатёж при наличии средств"
			automatic.button_pressed = o.autopay
			automatic.toggled.connect(func(value): owner._act("child_support","autopay",{"id":o.id,"enabled":value}))
			card.add_child(automatic)
		if int(o.arrears)>0:
			if o.payer=="player":
				owner._offer(card,"Погасить задолженность","Перевод второму родителю","child_support","pay",{"id":o.id,"amount":o.arrears})
			else: owner._offer(card,"Подать на взыскание","30 €$ · рассмотрение занимает время","child_support","file_enforcement",{"id":o.id})
		if o.order: UI.label(card,"Действует взыскание задолженности",18,UI.ORANGE)
	if count==0: UI.label(parent,"Обязательства появляются, когда ребёнок живёт отдельно от одного из родителей. Отказ от ухода не отменяет финансовые обязанности.",19,UI.MUTED)
