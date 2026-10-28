extends RefCounted
## Task-specific game screens. Presentation state is separate from world/save state.
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const W = preload("res://scripts/ui/gameplay/game_widgets.gd")
const HUD = preload("res://scripts/ui/gameplay/hud_widgets.gd")
const Names = preload("res://scripts/gameplay/presentation.gd")
const Art = preload("res://scripts/ui/gameplay/item_art.gd")
const Portrait = preload("res://scripts/ui/gameplay/resident_preview.gd")
const RoomPlan = preload("res://scripts/ui/gameplay/room_plan.gd")
const Reproductive = preload("res://scripts/ui/gameplay/reproductive_panel.gd")
const Book = preload("res://scripts/ui/gameplay/journal_book.gd")
const Social = preload("res://scripts/gameplay/social_presentation.gd")
const SocialStatus = preload("res://scripts/ui/gameplay/social_status.gd")

static func tabs(owner: Control, parent: Node, key: String, options: Dictionary, fallback: String) -> String:
	var selected := str(owner._screen_state.get(key, fallback))
	if not options.has(selected): selected = fallback
	W.tabs(parent, options, selected, owner._choose_screen.bind(key))
	return selected

static func action(owner: Control, parent: Node, title: String, detail: String, module_id: String, operation: String, args: Dictionary = {}, verb: String = "Начать") -> Button:
	var embedded: bool = parent is VBoxContainer and parent.get_parent() is PanelContainer
	var button: Button = owner._offer(parent, title, detail, module_id, operation, args, "", true, embedded)
	button.text = verb
	return button

static func _compact_links(parent: Node) -> void:
	for child in parent.get_children():
		if not child is Button: continue
		child.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		child.custom_minimum_size.y = 34
		child.add_theme_font_size_override("font_size",roundi(17*UI.text_scale))
		HUD.quiet_button(child)
		child.text = {"МОИ ЖИЗНЕННЫЕ ЦЕЛИ":"Мои жизненные цели  ↗","РАБОТА, ЗАКАЗЫ И СВОИ ЦЕЛИ":"Подработки и личные цели  ↗","УЛУЧШЕНИЯ ДЛЯ УЮТА И РАБОТЫ":"Уют и удобства  ↗","МОИ ПОТРЕБНОСТИ И ПРИВЫЧКИ":"Потребности и привычки  ↗","НАСТРОИТЬ ПОТРЕБНОСТИ ПЕРСОНАЖА":"Настроить потребности  ↗"}.get(child.text,child.text)

static func journal(owner: Control, parent: Node) -> void:
	_compact_links(parent)
	var sim = Gameplay.simulation
	owner._heading("Мой дневник")
	var tab := tabs(owner, parent, "journal_tab", {"tasks":"Мои дела", "stories":"Личные истории", "history":"Хроника", "achievements":"Достижения"}, "tasks")
	if tab == "history":
		var entries: Array = Gameplay.log_entries().duplicate()
		entries.reverse()
		if entries.is_empty(): W.empty(parent, "journal", "История только начинается", "Здесь останутся важные события вашего дня.")
		for entry in entries.slice(0, 24):
			var line := UI.row(parent, 16)
			W.icon(line, "journal", 20, UI.MUTED)
			UI.label(line, str(entry.text), 20)
		return
	if tab == "stories":
		var cards := W.grid(parent)
		for id in sim.state.npc_stories.arcs:
			var story: Dictionary = sim.services.npc_stories.present(id)
			var card := W.panel(cards)
			UI.label(card, str(story.title), 25)
			UI.label(card, "Завершено" if story.status == "completed" else "Личная история", 16, UI.MUTED)
			UI.button(card, "Открыть историю", owner._open_personal_story.bind(str(id)))
		if cards.get_child_count() == 0: W.empty(parent, "people", "У каждого есть своя история", "Узнавайте людей: личные дела появятся после знакомства.")
		UI.button(parent, "Альбом воспоминаний", owner.open_panel.bind("collection"))
		return
	if tab == "achievements":
		var cards := W.grid(parent, 3)
		for id in sim.catalog.achievements:
			var card := W.panel(cards)
			W.icon(card, "journal", 40, UI.BLUE if id in sim.state.journal.achievements else UI.MUTED)
			UI.label(card, Names.title(id), 23)
			if id in sim.state.journal.achievements: UI.label(card, "Открыто", 17, UI.BLUE)
			else: action(owner, card, "Получить награду", "После выполнения условий достижения", "events", "claim_achievement", {"id":id}, "Получить")
		return
	var book := Book.new()
	parent.add_child(book)
	var index := book.sheet(true)
	var page := book.sheet(false)
	UI.label(index,"ЗАПИСИ",14,UI.MUTED)
	var entries: Array[Dictionary] = []
	for key in sim.state.social.promises:
		var promise: Dictionary = sim.state.social.promises[key]
		entries.append({"key":"promise:" + str(key), "title":Names.title(str(promise.id)), "status":str(promise.status), "data":promise, "kind":"promise"})
	for id in sim.state.journal.quests:
		var quest: Dictionary = sim.state.journal.quests[id]
		entries.append({"key":"quest:" + str(id), "title":Names.title(id), "status":str(quest.status), "data":quest, "kind":"quest", "id":str(id)})
	for id in sim.state.journal.ready_events:
		entries.append({"key":"event:"+str(id),"title":"Событие дня" if id == "first_evening" else Names.title(id),"status":"active","data":{},"kind":"event","id":str(id)})
	if entries.is_empty(): W.empty(page, "journal", "На сегодня всё", "Выберите занятие или познакомьтесь с кем-нибудь в городе."); return
	var selected: String = str(owner._screen_state.get("journal_selected", entries[0].key))
	var chosen: Dictionary = entries[0]
	for entry in entries:
		var title := str(entry.title) + ("  ✓" if entry.status in ["completed", "fulfilled"] else "")
		var button := UI.button(index, title, owner._choose_screen.bind(str(entry.key), "journal_selected"))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size.y = 68
		if entry.key == selected:
			chosen = entry
			button.modulate = UI.BLUE
			button.set_meta("initial_focus",true)
	UI.label(page, "МОИ ДЕЛА", 13, UI.BLUE)
	UI.label(page, str(chosen.title), 32)
	var item: Dictionary = chosen.data
	if chosen.kind == "promise":
		UI.label(page, "Обещание: " + Names.actor_name(sim, str(item.npc)), 20, UI.MUTED)
		var due: Dictionary = sim.calendar.snapshot(int(item.deadline))
		UI.label(page, "До %s · %s" % [due.date_text, due.time_text], 18, UI.ORANGE)
		UI.label(page, "Выполнено" if item.status == "fulfilled" else "Человек рассчитывает на вас.", 22)
		if item.status == "active":
			UI.button(page, "Заняться проектом" if item.id == "complete_project" else "Выбрать занятие", owner.open_panel.bind("work" if item.id == "complete_project" else "activities"))
			action(owner, page, "Подтвердить выполнение", "Собеседник оценит результат обещанного дела", "social_rules", "fulfill", {"id":item.npc, "promise":item.id}, "Подтвердить")
	elif chosen.kind == "quest":
		UI.label(page, {"active":"В процессе", "completed":"Выполнено", "failed":"Срок истёк"}.get(item.status, "Завершено"), 18, UI.BLUE)
		for objective in sim.catalog.quests[chosen.id].objectives:
			var count := int(item.objectives.get(objective, 0))
			var needed := int(sim.catalog.quests[chosen.id].objectives[objective])
			UI.label(page, ("✓  " if count >= needed else "◇  ") + ("Позаниматься самостоятельно" if objective == "practice" else "Этап задания") + "  %d / %d" % [count, needed], 22)
		if item.status == "active":
			UI.label(page, "Следующий шаг", 16, UI.MUTED)
			W.primary(page, "Найти занятие", owner.open_panel.bind("activities"))
		if item.status == "completed" and not item.claimed: action(owner, page, "Задание выполнено", "Награда за ваши поступки", "events", "claim_quest", {"id":chosen.id}, "Получить награду")
	else: action(owner,page,str(chosen.title),"Что-то изменилось в городе","events","fire",{"id":chosen.id},"Узнать, что произошло")

static func activities(owner: Control, parent: Node) -> void:
	var sim = Gameplay.simulation
	owner._heading("Чем займёмся?")
	var tab := tabs(owner, parent, "activities_tab", {"day":"Для себя", "training":"Тренировки", "university":"Учёба", "games":"Испытания"}, "day")
	var cards := W.grid(parent, 2)
	if tab == "day":
		for id in sim.catalog.actions:
			var spec: Dictionary = sim.catalog.actions[id]
			var name: String = {"exercise":"Размяться", "read":"Почитать книгу"}.get(id, Names.title(id))
			action(owner, cards, name, "%d мин" % spec.get("minutes", 0) + (" · нужна книга" if id == "read" else " · физическое развитие"), "actions", "perform", {"id":id}, "Почитать" if id == "read" else "Начать")
		action(owner, cards, "Отдохнуть", "15 мин · восстановить силы", "character", "rest", {"minutes":15}, "Отдохнуть")
		return
	if tab == "training":
		for id in sim.catalog.training_programs:
			var spec: Dictionary = sim.catalog.training_programs[id]
			action(owner, cards, "Силовая тренировка" if id == "strength" else Names.title(id), "%d мин · %d ¤ · выносливость −%d" % [spec.get("minutes",30),spec.get("cost",0),spec.get("energy",5)*sim.multiplier("resource_cost")], "activities", "practice", {"id":id}, "Тренироваться")
		return
	if tab == "games":
		for id in ["blackjack","reaction","strength","guess","lockpick","timing","pushups"]:
			var card := W.panel(cards)
			W.icon(card, "leisure", 36)
			UI.label(card, {"blackjack":"Двадцать одно","reaction":"Реакция","strength":"Проверка силы","guess":"Угадать число","lockpick":"Учебный замок","timing":"Поймать ритм","pushups":"Отжимания"}[id], 25)
			UI.button(card, "Попробовать", owner._act.bind("encounters", "game_start", {"type":id, "stake":0}))
		return
	UI.label(parent, "Учебный результат %d · пропусков %d" % [sim.state.world.education.grade,sim.state.world.education.absences], 18, UI.MUTED)
	for id in sim.catalog.lessons:
		var spec: Dictionary = sim.catalog.lessons[id]
		if not preload("res://scripts/mechanics/core/rules.gd").check(sim.state,spec.get("requirements",{})): continue
		var hours: Array = spec.get("hours", [0,0])
		var days: Array[String] = []
		for day in spec.get("weekdays", [1,2,3,4,5]): days.append(["вс","пн","вт","ср","чт","пт","сб"][int(day)%7])
		action(owner, cards, Names.title(id), "%s · %02d:%02d–%02d:%02d\n%s · %d мин" % [", ".join(days),int(hours[0])/60,int(hours[0])%60,int(hours[1])/60,int(hours[1])%60,Names.title(spec.location),spec.get("minutes",60)], "world", "lesson", {"id":id}, "На занятие")
	action(owner, cards, "Домашнее задание", "45 мин · заниматься дома", "world", "homework", {}, "Заниматься")
	if sim.state.world.education.get("expelled", false): action(owner, cards, "Восстановиться в университете", "30 мин · 50 ¤", "world", "appeal", {}, "Подать заявление")

static func work(owner: Control, parent: Node) -> void:
	_compact_links(parent)
	var sim = Gameplay.simulation
	var state: Dictionary = sim.state
	owner._heading("Дела и заработок")
	var at_shop: bool = state.world.location in ["global_map", "north_shops"]
	var tab := tabs(owner, parent, "work_tab", {"projects":"Мои проекты", "jobs":"Работа", "shop":"Магазин", "channel":"Мой канал", "assets":"Имущество"}, "shop" if at_shop else "projects")
	if tab == "shop": _shop(owner, parent); return
	var cards := W.grid(parent)
	if tab == "projects":
		for id in sim.catalog.projects:
			var spec: Dictionary = sim.catalog.projects[id]
			var progress: Dictionary = state.economy.projects.get(id,{})
			var card := W.panel(cards)
			W.icon(card, "desk", 36)
			UI.label(card, Names.title(id), 27)
			var completed: bool = progress.get("completed", false)
			var remaining := maxi(0, int(spec.effort)-int(progress.get("progress",0)))
			UI.label(card, "Готово · оплата получена" if completed else "Осталось %d мин · оплата %d ¤" % [remaining,spec.get("pay",0)], 18, UI.MUTED)
			var bar := HUD.rail(card, 6, UI.BLUE)
			bar.value = 100.0*float(progress.get("progress",0))/float(spec.effort)
			if not completed: action(owner, card, "Поработать над проектом", "%d мин · нужен домашний компьютер" % mini(60,remaining), "economy", "project", {"id":id,"minutes":mini(60,remaining)}, "Работать · %d мин" % mini(60,remaining))
		for id in sim.catalog.contracts:
			var spec: Dictionary = sim.catalog.contracts[id]
			var progress: Dictionary = state.careers.contracts.get(id,{})
			var card := W.panel(cards)
			UI.label(card, Names.title(id), 25)
			UI.label(card, "От %d ¤ · срок %d ч" % [int(spec.pay)*0.75,int(spec.deadline)/60], 18, UI.MUTED)
			if progress.is_empty(): action(owner, card, "Новый заказ", "Профессия %d уровня" % spec.get("level",1), "careers", "take_contract", {"id":id}, "Взять заказ")
			elif progress.status == "active": action(owner, card, "Работа над заказом", "До 60 мин за один подход", "careers", "work_contract", {"id":id,"minutes":60}, "Продолжить")
			elif progress.status == "completed" and not progress.claimed: action(owner, card, "Заказ готов", "Можно получить оплату", "careers", "claim_contract", {"id":id}, "Сдать заказ")
		return
	if tab == "jobs":
		for id in sim.catalog.jobs:
			var spec: Dictionary = sim.catalog.jobs[id]
			action(owner, cards, Names.title(id), "%d мин · %d ¤" % [spec.get("minutes",60),spec.get("pay",0)], "economy", "work", {"id":id}, "Приступить")
		for id in sim.catalog.professions:
			var spec: Dictionary = sim.catalog.professions[id]
			if spec.has("pay"): action(owner,cards,Names.title(id),"%d мин · от %d ¤ за смену" % [spec.get("minutes",240),spec.pay],"careers","shift",{"id":id},"На смену")
		return
	if tab == "channel":
		UI.label(parent, "%d подписчиков" % state.economy.channel.followers, 22, UI.BLUE)
		for id in sim.catalog.get("stream_topics",{}): action(owner,cards,Names.title(id),"60 мин · нужен компьютер","careers","stream",{"id":id,"minutes":60},"Начать эфир")
		for id in sim.catalog.get("publications",{}):
			var card := W.panel(cards)
			UI.label(card, "Новый материал", 25)
			for operation in ["investigate","verify","publish"]: UI.button(card,{"investigate":"Исследовать тему","verify":"Проверить источники","publish":"Опубликовать"}[operation],owner._act.bind("careers",operation,{"id":id}))
			for npc in state.social.npcs:
				if state.social.npcs[npc].location == state.world.location: UI.button(card,"Интервью: " + str(state.social.npcs[npc].name),owner._act.bind("careers","interview",{"id":id,"npc":npc}))
		return
	for id in sim.catalog.assets:
		var card := W.panel(cards)
		UI.label(card, Names.title(id), 26)
		if not state.economy.assets.has(id): action(owner,card,"Приобрести имущество","%d ¤" % sim.catalog.assets[id].price,"economy","buy_asset",{"id":id},"Купить")
		else:
			UI.button(card,"Улучшить",owner._act.bind("economy","upgrade_asset",{"id":id}))
			UI.button(card,"Продать",owner._act.bind("economy","sell_asset",{"id":id}))
	if cards.get_child_count() == 0: W.empty(parent,"wallet","Пока нет имущества")

static func _shop(owner: Control, parent: Node) -> void:
	var sim = Gameplay.simulation
	var local: bool = sim.state.world.location in ["global_map", "north_shops"]
	if not local:
		W.empty(parent,"inventory","Загляните в магазин","Городские магазины открыты с 08:00 до 22:00.")
		W.primary(parent,"Найти на карте",owner.open_panel.bind("map"))
		return
	var shop := "north_market" if sim.state.world.location == "north_shops" else "market"
	var cards := W.grid(parent,3)
	for id in sim.catalog.shops[shop].stock:
		var item: Dictionary = sim.catalog.items[id]
		var card := W.panel(cards,16)
		var art := TextureRect.new()
		art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		art.texture = Art.texture(id,item)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.custom_minimum_size.y = 110
		card.add_child(art)
		UI.label(card,Names.title(id),23)
		UI.label(card,"%d ¤ · у вас %d" % [roundi(float(item.get("price",0))*float(sim.catalog.shops[shop].get("price_multiplier",1))),int(sim.state.inventory.items.get(id,0))],18,UI.MUTED)
		UI.button(card,"Купить",owner._act.bind("inventory","buy",{"id":id,"shop":shop}))
		if int(sim.state.inventory.items.get(id,0)) > 0: UI.button(card,"Продать один",owner._act.bind("inventory","sell",{"id":id,"shop":shop}))
	if shop == "market": action(owner,parent,"Бодрящий тоник","15 ¤ · 2 мин · временный прилив сил; при частом употреблении вызывает привыкание","character","substance",{"id":"stimulant"},"Выпить на месте")

static func health(owner: Control, parent: Node) -> void:
	_compact_links(parent)
	var sim = Gameplay.simulation
	owner._heading("Самочувствие")
	var tab := tabs(owner,parent,"health_tab",{"needs":"Моё состояние","treatment":"Восстановление","reproduction":"Личное здоровье","adult_health":"Особенности"},"needs")
	if tab=="adult_health": preload("res://scripts/ui/gameplay/adult_health_panel.gd").populate(owner,parent); return
	if tab == "reproduction": Reproductive.populate(owner,parent); return
	if tab == "treatment":
		var cards := W.grid(parent)
		for id in sim.catalog.treatments:
			var treatment: Dictionary = sim.catalog.treatments[id]
			action(owner,cards,"Обратиться в клинику" if id == "clinic" else Names.title(id),"%d мин · %d ¤" % [treatment.get("minutes",0),treatment.get("cost",0)],"health","treat",{"id":id},"Лечиться")
		for condition in sim.state.conditions.values():
			if condition.get("id","") == "pregnancy": action(owner,cards,"Плановый уход","30 мин · 30 ¤","health","prenatal_care",{"target":condition.get("target","player")},"Пройти осмотр")
		if sim.state.security.fine > 0:
			action(owner,cards,"Оплатить штраф","%d ¤" % sim.state.security.fine,"security","pay_fine",{},"Оплатить")
			action(owner,cards,"Отбыть наказание","Потребуется игровое время","security","serve_sentence",{},"Отбыть наказание")
		return
	var columns := UI.row(parent,36)
	var person := UI.column(columns)
	person.custom_minimum_size.x = 280
	var portrait := Portrait.new()
	portrait.custom_minimum_size = Vector2(280,340)
	portrait.set_actor(preload("res://scripts/portraits/character_visuals.gd").player_actor(GameSession.get_character_profile(),sim.state.player))
	person.add_child(portrait)
	var condition: Dictionary = sim.services.needs.condition()
	UI.label(person,"Всё в порядке" if condition.warnings.is_empty() and sim.state.player.injuries.is_empty() else "Стоит позаботиться о себе",23,UI.BLUE)
	for warning in condition.warnings: UI.label(person,str(warning.text),17,UI.ORANGE if warning.critical else UI.MUTED)
	for part in sim.state.player.injuries: UI.label(person,"Травма: " + Names.title(part),18,UI.ORANGE)
	var needs := UI.column(columns,16)
	needs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var grid := W.grid(needs,2)
	for spec in [["health","Здоровье","health"],["energy","Силы","energy"],["hydration","Вода","thirst"],["satiety","Сытость","satiety"],["hygiene","Чистота","hygiene"],["bladder","Туалет","toilet"],["rested","Сон","rest"],["fun","Досуг","leisure"],["social","Общение","chat"],["mood","Настроение","health"]]:
		if sim.services.growth.enabled(str(spec[0])): W.meter(grid,spec[1],float(sim.state.player.needs[spec[0]]),spec[2])
	grid.set_meta("need_meters",true)
	for meter in grid.get_children(): meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id in sim.state.player.effects: UI.label(needs,Names.title(id) + " · ещё %d мин" % maxi(0,int(sim.state.player.effects[id].expires)-int(sim.state.clock.total_minutes)),18,UI.BLUE)
	for id in sim.state.player.addictions:
		var exposure := float(sim.state.player.addictions[id].exposure)
		if exposure > 0: UI.label(needs,Names.title(id) + (" · сильное привыкание" if exposure >= 50 else " · формируется привычка"),18,UI.ORANGE)
	action(owner,needs,"Клиника","Осмотр и помощь врача","world","journey",{"id":"clinic"},"Доехать до клиники")
	if owner._at_home(): action(owner,needs,"Перевести дух","15 мин · восстановить силы","character","rest",{"minutes":15},"Отдохнуть")

static func home(owner: Control, parent: Node) -> void:
	_compact_links(parent)
	var sim = Gameplay.simulation
	owner._heading("Мой дом")
	var tab := tabs(owner,parent,"home_tab",{"room":"Обустройство","properties":"Недвижимость","household":"Домочадцы"},"room")
	if tab == "household":
		UI.button(parent,"Семья и забота",owner.open_panel.bind("family"))
		var residence: Dictionary = sim.state.housing.properties.get(str(sim.state.housing.residence),{})
		for id in residence.get("tenants",[]): UI.button(parent,"Завершить проживание: " + Names.actor_name(sim,str(id)),owner._act.bind("housing","remove_tenant",{"id":sim.state.housing.residence,"npc":id}))
		if residence.get("owned",false):
			for id in sim.state.social.contacts: UI.button(parent,"Сдать комнату: " + Names.actor_name(sim,str(id)),owner._act.bind("housing","tenant",{"id":sim.state.housing.residence,"npc":id}))
		return
	if tab == "properties":
		UI.label(parent,"Оформление — в агентстве недвижимости · 09:00–18:00",18,UI.MUTED)
		var cards := W.grid(parent)
		for id in sim.catalog.properties:
			var spec: Dictionary = sim.catalog.properties[id]
			var property: Dictionary = sim.state.housing.properties.get(id,{})
			var card := W.panel(cards)
			W.icon(card,"home",44)
			UI.label(card,Names.title(id),27)
			if property.is_empty():
				action(owner,card,"Аренда","%d ¤ в месяц" % spec.monthly_rent,"housing","rent",{"id":id},"Арендовать")
				action(owner,card,"Покупка","%d ¤" % spec.price,"housing","buy",{"id":id},"Купить")
				if id == "social_housing": action(owner,card,"Помощь с жильём","После потери дома при нехватке средств","housing","emergency",{"id":id},"Обратиться за помощью")
			else:
				UI.label(card,"Ваш дом" if property.owned else "Арендуется",18,UI.BLUE)
				if sim.state.housing.residence != id: action(owner,card,"Переезд","Сделать это жильё своим домом","housing","move_in",{"id":id},"Переехать")
				if property.arrears > 0: action(owner,card,"Задолженность","%d ¤" % property.arrears,"housing","pay_arrears",{"id":id},"Погасить")
				UI.button(card,"Продать жильё" if property.owned else "Завершить аренду",owner._act.bind("housing","sell" if property.owned else "end_lease",{"id":id}))
		return
	var id := str(sim.state.housing.residence)
	if id.is_empty():
		W.empty(parent,"home","Пока нет своего места","Подберите жильё в агентстве недвижимости.")
		UI.button(parent,"Посмотреть варианты",owner._choose_screen.bind("properties","home_tab"))
		return
	var property: Dictionary = sim.state.housing.properties[id]
	var spec: Dictionary = sim.catalog.properties[id]
	if not owner._room_item in property.equipment: owner._room_item = ""
	var columns := UI.row(parent,28)
	var room := W.panel(columns,20,Color("13242b"))
	room.get_parent().size_flags_stretch_ratio = 2
	UI.label(room,Names.title(id),27)
	var plan := RoomPlan.new()
	plan.set_meta("input_id","room_plan")
	plan.custom_minimum_size = Vector2(580,390)
	plan.dimensions = Vector2i(int(spec.get("room_size",[8,6])[0]),int(spec.get("room_size",[8,6])[1]))
	plan.plan = sim.services.interior.render_plan(id)
	plan.selected_item = owner._room_item
	if not owner._room_item.is_empty() and sim.catalog.furniture.has(owner._room_item):
		var footprint: Array = sim.catalog.furniture[owner._room_item].size
		plan.footprint = Vector2i(footprint[1],footprint[0]) if owner._rotated else Vector2i(footprint[0],footprint[1])
	plan.cell_selected.connect(func(cell):
		if owner._room_item.is_empty(): owner._notify("Сначала выберите мебель справа."); return
		owner._act("interior","place",{"id":id,"item":owner._room_item,"x":cell.x,"y":cell.y,"rotated":owner._rotated}))
	room.add_child(plan)
	UI.label(room,"Выберите мебель справа и укажите место на плане",16,UI.MUTED)
	var furniture := UI.column(columns,12)
	furniture.custom_minimum_size.x = 300
	furniture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.label(furniture,"Мебель",25)
	for item in property.equipment:
		var button := UI.button(furniture,Names.title(item),func(): owner._room_item = item; owner._refresh())
		button.set_meta("room_item",item)
		if owner._room_item == item: button.modulate = UI.BLUE
		button.icon = Art.texture(item,sim.catalog.items.get(item,{}))
		button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width",40)
	if property.equipment.is_empty(): W.empty(furniture,"home","Место для ваших вещей","Мебель можно купить в магазине и установить из сумки.")
	UI.button(furniture,"Открыть сумку",owner.open_panel.bind("inventory"))
	UI.button(furniture,"Поворот предмета: " + ("90°" if owner._rotated else "0°"),func(): owner._rotated = not owner._rotated; owner._refresh())
	if not owner._room_item.is_empty() and owner._room_item in property.equipment:
		UI.button(furniture,"Убрать с плана",owner._act.bind("interior","unplace",{"id":id,"item":owner._room_item}))
		UI.button(furniture,"Вернуть в сумку",owner._act.bind("interior","remove",{"id":id,"item":owner._room_item}))

static func digital(owner: Control, parent: Node) -> void:
	var sim = Gameplay.simulation
	var data: Dictionary = sim.state.digital
	owner._heading("За компьютером")
	var desktop := W.panel(parent,24,Color("101f2c"))
	var bar := UI.row(desktop)
	W.icon(bar,"desk",24)
	UI.label(bar,"EINC  /  СЕТЬ",15,UI.BLUE)
	UI.label(bar,"Цифровой след %d / 100" % data.trace,16,UI.ORANGE if data.trace > 40 else UI.MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var tab := tabs(owner,desktop,"digital_tab",{"tasks":"Задачи","history":"История"},"tasks")
	if tab == "history":
		for entry in data.history: UI.label(desktop,str(sim.catalog.digital_operations[entry.id].label) + (" · выполнено" if entry.success else " · не удалось"),20)
		if data.history.is_empty(): W.empty(desktop,"desk","История пуста","Результаты выполненных задач появятся здесь.")
		return
	if not data.pending.is_empty():
		var spec: Dictionary = sim.catalog.digital_operations[data.pending.id]
		action(owner,desktop,str(spec.label),"%d мин · риск %d · возможный доход %d ¤" % [spec.minutes,spec.risk,spec.reward],"digital","resolve",{"id":data.pending.id,"token":data.pending.token},"Выполнить")
		UI.button(desktop,"Отменить подготовку",owner._act.bind("digital","cancel"))
	else:
		var cards := W.grid(desktop)
		for id in sim.catalog.digital_operations:
			var spec: Dictionary = sim.catalog.digital_operations[id]
			action(owner,cards,str(spec.label),"Подготовка 15 мин · программирование от %d · риск %d" % [spec.level,spec.risk],"digital","scan",{"id":id},"Подготовиться")
	for id in data.leads: UI.button(desktop,"Контакт: " + Names.actor_name(sim,str(id)),owner._show_npc_details.bind(str(id)))

static func family(owner: Control, parent: Node) -> void:
	var sim = Gameplay.simulation
	var data: Dictionary = sim.state.family
	owner._heading("Моя семья")
	var tab := tabs(owner,parent,"family_tab",{"care":"Забота","duties":"Обязанности","budget":"Общие деньги","history":"Семейная история"},"care")
	if tab == "budget":
		var box := W.panel(parent,24)
		UI.label(box,"Семейный запас",20,UI.MUTED)
		UI.label(box,"%d ¤" % data.budget,46)
		UI.label(box,"Потрачено %d ¤ · долг %d ¤" % [data.spent,data.arrears],18,UI.MUTED)
		var row := UI.row(box)
		for amount in [50,100]: UI.button(row,"Отложить %d ¤" % amount,owner._act.bind("family","deposit",{"amount":amount}))
		if data.arrears > 0: UI.button(box,"Погасить задолженность",owner._act.bind("family","pay_arrears"))
		Reproductive.support(owner,parent)
		return
	if tab == "history":
		var count := 0
		for entry in data.history.slice(maxi(0,data.history.size()-20)):
			var member: Dictionary = data.members.get(str(entry.member),{})
			if member.is_empty() or not "player" in member.parents: continue
			count += 1
			var description: String = {"born":"Появление в семье","care":"Забота","assignment":"Обязанности распределены","support":"Приглашена помощь","milestone":"Новый этап взросления","needs_attention":"Нужна помощь","expenses_due":"Неоплаченные расходы"}.get(str(entry.kind),"Семейное событие")
			UI.label(parent,str(member.name) + " · " + description,21)
		if count == 0: W.empty(parent,"home","История семьи впереди","Важные моменты останутся здесь.")
		return
	var members: Array[Dictionary] = []
	for member in data.members.values():
		if "player" in member.parents: members.append(member)
	if members.is_empty():
		W.empty(parent,"home","Вместе — свой маленький мир","Когда появятся домочадцы, здесь будут их потребности и ваши общие дела.")
		W.primary(parent,"Близкие люди",owner.open_panel.bind("people"))
		Reproductive.support(owner,parent)
		return
	var columns := UI.row(parent,28)
	var roster := UI.column(columns)
	roster.custom_minimum_size.x = 260
	var selected: String = str(owner._screen_state.get("family_member",members[0].id))
	var person: Dictionary = members[0]
	for member in members:
		var button := UI.button(roster,str(member.name),owner._choose_screen.bind(str(member.id),"family_member"))
		if member.id == selected: person = member; button.modulate = UI.BLUE
	var detail := UI.column(columns,16)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.label(detail,str(person.name),30)
	UI.label(detail,str(sim.catalog.family_stages[person.stage].label),18,UI.BLUE)
	var guardians: Array = person.get("guardians",person.parents)
	if not "player" in guardians:
		UI.label(detail,"Сейчас живёт с другим опекуном" if not guardians.is_empty() else "Под внешней опекой",21,UI.MUTED)
		return
	if tab == "duties":
		var naming := UI.row(detail)
		var name_input := LineEdit.new()
		name_input.text = str(person.name)
		name_input.max_length = 40
		name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		naming.add_child(name_input)
		UI.button(naming,"Сохранить имя",func(): owner._act("family","rename",{"id":person.id,"name":name_input.text}))
		for need in ["food","hygiene","rest","attention"]:
			var row := UI.row(detail)
			UI.label(row,{"food":"Питание","hygiene":"Гигиена","rest":"Отдых","attention":"Внимание"}[need],19)
			var choice := OptionButton.new()
			for index in range(guardians.size()):
				choice.add_item("Вы" if guardians[index] == "player" else Names.actor_name(sim,str(guardians[index])))
				if person.assignments[need] == guardians[index]: choice.select(index)
			choice.item_selected.connect(func(index): owner._act("family","assign",{"id":person.id,"need":need,"caregiver":guardians[index]}))
			row.add_child(choice)
		if person.stage != "adult": UI.button(detail,"Обсудить передачу ухода",Reproductive.confirm.bind(owner,"Передать уход; алиментные обязательства сохранятся","reproduction","parenthood",{"member":person.id,"decision":"relinquish","confirm":true}))
		return
	var needs := W.grid(detail,2)
	for spec in [["food","Питание","satiety"],["hygiene","Чистота","hygiene"],["rest","Отдых","rest"],["attention","Внимание","chat"],["health","Здоровье","health"]]: W.meter(needs,spec[1],float(person.needs[spec[0]]),spec[2])
	var actions := W.grid(detail,2)
	for id in sim.catalog.family_actions:
		var spec: Dictionary = sim.catalog.family_actions[id]
		if person.stage in spec.stages: action(owner,actions,str(spec.label),"%d мин · %d ¤ · сил −%d" % [spec.minutes,spec.cost,spec.energy],"family","care",{"id":person.id,"action":id},str(spec.label))
	action(owner,detail,"Помощь с уходом","8 часов помощи · 60 ¤","family","support",{"id":person.id},"Пригласить помощника")

static func club(owner: Control, parent: Node) -> void:
	var sim = Gameplay.simulation
	var id := "creative_collective"
	owner._heading("Наш клуб")
	if not sim.state.organizations.has(id):
		W.empty(parent,"people","Общее дело начинается с вас","Соберите знакомых, выберите проект и найдите свой ритм.")
		action(owner,parent,"Создать творческий клуб","Собственная команда и совместные проекты","organizations","create",{"id":id},"Создать клуб")
		return
	var group: Dictionary = sim.state.organizations[id]
	var tab := tabs(owner,parent,"club_tab",{"people":"Команда","projects":"Проекты","affairs":"Дела клуба"},"people")
	UI.label(parent,"В клубе %d · бюджет %d ¤ · настроение %d" % [group.members.size(),group.budget,group.morale],18,UI.MUTED)
	if tab == "people":
		var cards := W.grid(parent)
		for npc in group.members:
			var card := W.panel(cards)
			UI.label(card,Names.actor_name(sim,str(npc)),26)
			var assignment := OptionButton.new()
			for task in ["idle","clean","fundraise","article"]:
				assignment.add_item({"idle":"Пока отдыхает","clean":"Позаботиться о порядке","fundraise":"Собрать средства","article":"Подготовить статью"}[task])
				assignment.set_item_metadata(assignment.item_count-1,task)
				if group.members[npc].task == task: assignment.select(assignment.item_count-1)
			assignment.item_selected.connect(func(index): owner._act("organizations","assign",{"id":id,"npc":npc,"task":assignment.get_item_metadata(index)}))
			card.add_child(assignment)
			UI.button(card,"Убрать из команды",owner._act.bind("organizations","dismiss",{"id":id,"npc":npc}))
		var invite := UI.row(parent)
		UI.label(invite,"Позвать знакомого",20)
		var candidates := OptionButton.new()
		for npc in sim.state.social.contacts:
			if not group.members.has(npc):
				candidates.add_item(Names.actor_name(sim,str(npc)))
				candidates.set_item_metadata(candidates.item_count-1,npc)
		invite.add_child(candidates)
		UI.button(invite,"Пригласить",func():
			if candidates.selected >= 0: owner._act("organizations","recruit",{"id":id,"npc":candidates.get_item_metadata(candidates.selected)})).disabled = candidates.item_count == 0
		owner._club_election(id,group)
		return
	if tab == "projects":
		var cards := W.grid(parent)
		for project in sim.catalog.group_projects:
			var card := W.panel(cards)
			UI.label(card,Names.title(project),26)
			if not group.projects.has(project): UI.button(card,"Начать проект",owner._act.bind("organizations","project",{"id":id,"project":project}))
			else:
				UI.label(card,"Готово" if group.projects[project].completed else "Работаем вместе",18,UI.BLUE)
				for npc in group.members: UI.button(card,"Поручить: " + Names.actor_name(sim,str(npc)),owner._act.bind("organizations","assign",{"id":id,"npc":npc,"task":project}))
		for campaign in sim.catalog.campaigns:
			if not group.campaigns.has(campaign): UI.button(parent,"Кампания: " + Names.title(campaign),owner._act.bind("institutions","campaign",{"id":id,"campaign":campaign}))
			elif group.campaigns[campaign].status == "completed" and not group.campaigns[campaign].claimed: UI.button(parent,"Подвести итоги: " + Names.title(campaign),owner._act.bind("institutions","claim_campaign",{"id":id,"campaign":campaign}))
		return
	action(owner,parent,"Внести в общий бюджет","50 ¤ из своих средств","organizations","fund",{"id":id,"amount":50},"Внести 50 ¤")
	var settings := W.panel(parent)
	UI.label(settings,"Куда движемся",24)
	var focus := OptionButton.new()
	for key in ["balanced","research","publicity","festival"]:
		focus.add_item(Names.title(key))
		focus.set_item_metadata(focus.item_count-1,key)
		if group.policies.focus == key: focus.select(focus.item_count-1)
	settings.add_child(focus)
	var wage := SpinBox.new()
	wage.max_value = 100
	wage.value = int(group.policies.wage)
	settings.add_child(wage)
	UI.button(settings,"Сохранить курс и дневную оплату",func(): owner._act("institutions","policy",{"id":id,"focus":focus.get_item_metadata(focus.selected),"wage":int(wage.value)}))
	for item in sim.state.inventory.items:
		if sim.catalog.items[item].has("equipment"): UI.button(parent,"Передать клубу: " + Names.title(item),owner._act.bind("institutions","install",{"id":id,"item":item}))

static func person(owner: Control, parent: Node) -> void:
	var sim = Gameplay.simulation
	var id: String = owner.selected_npc
	if not sim.state.social.npcs.has(id): owner.open_panel("people"); return
	var npc: Dictionary = sim.state.social.npcs[id]
	var bond := Social.bond(sim,id)
	var local: bool = npc.location == sim.state.world.location
	owner._heading(str(npc.name))
	var tab := tabs(owner,parent,"person_tab",{"about":"О человеке","together":"Время вместе","gifts":"Подарки и обещания","history":"История отношений"},"about")
	var columns := UI.row(parent,32)
	var identity := UI.column(columns,12)
	identity.custom_minimum_size.x = 260
	var portrait := Portrait.new()
	portrait.custom_minimum_size = Vector2(250,330)
	portrait.set_actor(npc)
	identity.add_child(portrait)
	UI.label(identity,str(bond.status_text),21,UI.BLUE)
	UI.label(identity,Names.title(str(npc.location)),17,UI.MUTED)
	if local: W.primary(identity,"Поговорить",owner._open_conversation.bind(id,"free"))
	elif id in sim.state.social.contacts: W.primary(identity,"Написать",owner._open_conversation.bind(id,"message"))
	else: UI.button(identity,"Показать карту",owner.open_panel.bind("map"))
	var detail := UI.column(columns,16)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if tab == "about":
		var life := Social.life(sim,id)
		UI.label(detail,str(life.emotion),24)
		UI.label(detail,str(life.activity),18,UI.MUTED)
		UI.label(detail,str(life.goal),22)
		var bonds := W.grid(detail,3)
		for spec in [["trust","Доверие","chat"],["affection","Симпатия","health"],["comfort","Комфорт","rest"]]: W.meter(bonds,spec[1],float(bond[spec[0]]),spec[2])
		if float(bond.grievance) > 0: UI.label(detail,"Осталась обида. Для восстановления отношений нужны поступки и время.",18,UI.ORANGE)
		var actions := W.grid(detail)
		action(owner,actions,"Поддержать личную цель","5 мин · помочь не опускать руки","npc_agency","encourage",{"id":id},"Поддержать")
		action(owner,actions,"Побыть наедине","Обсудить намерения и личные границы","intimacy","begin",{"id":id},"Предложить")
		if not id in sim.state.social.contacts: owner._offer(detail,"Обменяться контактами","Чтобы можно было написать друг другу","social","contact",{"id":id},"Нужно встретиться лично" if not local else "")
		if bond.status == "partner":
			UI.button(detail,"Обсудить планы на семью",owner._family_plan.bind(id))
			UI.button(detail,"Расстаться",owner._act.bind("social_rules","breakup",{"id":id}))
		return
	if tab == "history":
		UI.button(detail,"Личная история",owner._open_personal_story.bind(id))
		SocialStatus.recent(detail,sim,id)
		var more := UI.button(detail,"Характер и знакомства  ▾",func(): pass)
		var extra := UI.column(detail)
		extra.hide()
		more.pressed.connect(func(): extra.visible = not extra.visible)
		UI.label(extra,sim.services.social_rules.describe(id),18,UI.MUTED)
		SocialStatus.network(extra,sim,id)
		return
	if tab == "gifts":
		UI.label(detail,"Подарить что-нибудь",24)
		var gifts := W.grid(detail,3)
		for item in sim.state.inventory.items:
			var button := UI.button(gifts,Names.title(item),owner._act.bind("social","gift",{"id":id,"item":item}))
			button.icon = Art.texture(item,sim.catalog.items[item])
			button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			button.expand_icon = true
			button.add_theme_constant_override("icon_max_width",36)
			button.disabled = not local
			button.tooltip_text = "Вручить лично" if local else "Чтобы вручить подарок, нужно встретиться"
		UI.label(detail,"Дать слово",24)
		for promise in sim.catalog.promises:
			var row := UI.row(detail)
			UI.label(row,Names.title(promise),19)
			UI.button(row,"Обещать",owner._act.bind("social_rules","promise",{"id":id,"promise":promise}))
			UI.button(row,"Выполнено",owner._act.bind("social_rules","fulfill",{"id":id,"promise":promise}))
		return
	var activities := W.grid(detail)
	var together := UI.button(activities,"Прикосновения и время вместе",owner._open_companion.bind(id))
	together.set_meta("companion_entry",id)
	together.disabled = not local
	together.tooltip_text = "Нужно встретиться лично" if not local else "Предложить жест и узнать ответ собеседника"
	for venue in ["coffee","walk","cinema"]:
		action(owner,activities,{"coffee":"Выпить кофе","walk":"Прогуляться","cinema":"Сходить в кино"}[venue],{"coffee":"60 мин · 15 ¤","walk":"45 мин · в хорошую погоду","cinema":"90 мин · 30 ¤"}[venue],"social_rules","date",{"id":id,"venue":venue},"Пригласить")
	for key in Social.ACTIONS:
		var forecast := Social.preview(sim,id,key)
		var spec: Dictionary = sim.catalog.agency_actions[key]
		var button: Button = owner._offer(activities,str(spec.label),"%d мин · вероятность принятия %d %%" % [spec.minutes,forecast.chance*100],"npc_relationships","interact",{"id":id,"action":key},Names.error(str(forecast.blocked)) if not str(forecast.blocked).is_empty() else "",false)
		button.text = "Предложить"
	action(owner,detail,"Узнать прошлое","5 мин · нужно доверие","social_rules","ask_history",{"id":id},"Спросить")
	if id in sim.state.social.contacts:
		UI.button(detail,"Назначить встречу",func(): owner.open_panel("phone"); owner._phone_view.open_person(id); owner._phone_view.app = "meeting"; owner._phone_view._rebuild())
		if owner._at_home(): UI.button(detail,"Пригласить домой · 60 мин",owner._act.bind("social","invite",{"id":id,"minutes":60}))
	UI.button(detail,"Конфликт и рискованные действия…",owner._risk_actions.bind(id))

static func combat(owner: Control, parent: Node) -> void:
	var sim = Gameplay.simulation
	var state: Dictionary = sim.state.encounters.combat
	owner._heading("Конфликт")
	var arena := UI.row(parent,28)
	var player := UI.column(arena,14)
	player.custom_minimum_size.x = 200
	UI.label(player,"Вы",27)
	W.meter(player,"Здоровье",float(state.player_hp),"health")
	W.meter(player,"Выносливость",float(state.stamina.player),"energy")
	var moves := UI.column(arena,16)
	moves.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var turn := UI.row(moves)
	UI.label(turn,"Ход %d" % state.turn,23,UI.BLUE)
	UI.label(turn,"%d очков действия" % state.ap,20).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var target := UI.row(moves)
	UI.label(target,"Цель удара",17,UI.MUTED)
	var parts := OptionButton.new()
	parts.set_meta("input_id","combat_target")
	var part: String = str(owner._screen_state.get("combat_target","body"))
	for id in ["body","head","arms","legs"]:
		parts.add_item(Names.title(id))
		parts.set_item_metadata(parts.item_count-1,id)
		if id == part: parts.select(parts.item_count-1)
	parts.item_selected.connect(func(index): owner._screen_state.combat_target = parts.get_item_metadata(index); owner._refresh())
	target.add_child(parts)
	var attacks := W.grid(moves,2)
	for id in sim.catalog.combat_moves:
		var forecast: Dictionary = sim.services.combat.forecast(id,part)
		if not forecast.ok: continue
		var button := UI.button(attacks,"%s\n%d ОД · ≈%d урона · %d %%" % [Names.title(id),forecast.data.ap,forecast.data.damage,forecast.data.accuracy*100],owner._act.bind("combat","action",{"action":"attack","move":id,"part":part}))
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size = Vector2(210,78)
		button.add_theme_font_size_override("font_size",roundi(17*UI.text_scale))
		button.disabled = int(state.ap) < int(forecast.data.ap) or float(state.stamina.player) < float(forecast.data.stamina)
		button.tooltip_text = "Не хватает очков действия или выносливости" if button.disabled else "Прогноз для выбранной цели"
		button.set_meta("gameplay_action",{"module":"combat","operation":"action","args":{"action":"attack","move":id,"part":part}})
	var tactics := W.grid(moves,3)
	for id in ["guard","recover","intimidate","escape","end_turn"]:
		var caption: String = {"guard":"Прикрыться · 1 ОД","recover":"Перевести дух","intimidate":"Остановить драку · 4 ОД","escape":"Попытаться уйти","end_turn":"Завершить ход"}[id]
		var button := UI.button(tactics,caption,owner._act.bind("combat","action",{"action":id}))
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_font_size_override("font_size",roundi(16*UI.text_scale))
		button.tooltip_text = "Восстановить 25 выносливости и завершить ход" if id == "recover" else caption
		if id == "guard": button.disabled = int(state.ap) < 1
		if id == "intimidate": button.disabled = int(state.ap) < 4
	var stance := OptionButton.new()
	for id in ["balanced","defensive","aggressive"]:
		stance.add_item({"balanced":"Обычная стойка","defensive":"Защитная стойка","aggressive":"Агрессивная стойка"}[id] + " · смена 1 ОД")
		stance.set_item_metadata(stance.item_count-1,id)
		if state.stances.player == id: stance.select(stance.item_count-1)
	stance.item_selected.connect(func(index): owner._act("combat","action",{"action":"stance","id":stance.get_item_metadata(index)}))
	moves.add_child(stance)
	var opponent := UI.column(arena,12)
	opponent.custom_minimum_size.x = 220
	var npc: Dictionary = sim.state.social.npcs[state.npc]
	UI.label(opponent,str(npc.name),27)
	var portrait := Portrait.new()
	portrait.custom_minimum_size = Vector2(220,280)
	portrait.set_actor(npc)
	opponent.add_child(portrait)
	W.meter(opponent,"Здоровье",float(state.npc_hp),"health")
	W.meter(opponent,"Выносливость",float(state.stamina.npc),"energy")
	var details := UI.button(parent,"История ходов  ▾",func(): owner._screen_state.combat_log = not bool(owner._screen_state.get("combat_log",false)); owner._refresh())
	HUD.quiet_button(details)
	if owner._screen_state.get("combat_log",false):
		for entry in state.log.slice(-8): UI.label(parent,Names.combat_log(entry),17,UI.MUTED)
