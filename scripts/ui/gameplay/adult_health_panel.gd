extends RefCounted
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const W = preload("res://scripts/ui/gameplay/game_widgets.gd")

static func populate(owner: Control, parent: Node) -> void:
	var sim = Gameplay.simulation
	var status: Dictionary = sim.services.adult_health.view()
	if status.is_empty():
		UI.label(parent,"Сведения о взрослом здоровье сейчас недоступны.",20,UI.MUTED)
		return
	var columns := UI.row(parent,28)
	var personal := UI.column(columns,18)
	personal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var card := W.panel(personal)
	UI.label(card,"Самочувствие и желания",25,UI.BLUE)
	var libido := int(status.desire.libido)
	UI.label(card,"Либидо: "+("низкое" if libido<30 else "умеренное" if libido<65 else "высокое")+" · удовлетворённость %d/100" % int(status.desire.satisfaction),19)
	if float(status.desire.frustration)>=5: UI.label(card,"После неудачи осталось разочарование. Отдых и поддержка помогают восстановить настроение.",18,UI.MUTED)
	var preference := OptionButton.new()
	var intentions := {"context":"Ориентироваться на самочувствие","want_intimacy":"Сейчас хочется близости","not_now":"Сейчас не хочу близости"}
	for key in intentions:
		preference.add_item(intentions[key])
		preference.set_item_metadata(preference.item_count-1,key)
		if key==status.desire.intent: preference.select(preference.item_count-1)
	preference.item_selected.connect(func(index): owner._act("adult_health","desire",{"intent":preference.get_item_metadata(index)}))
	card.add_child(preference)
	if status.symptom_list.is_empty(): UI.label(card,"Сейчас без заметных жалоб.",19,UI.MUTED)
	for symptom in status.symptom_list:
		UI.label(card,str(symptom.label)+(" · выражено" if int(symptom.severity)>=65 else " · заметно" if int(symptom.severity)>=35 else " · незначительно"),18,UI.ORANGE if int(symptom.severity)>=65 else UI.INK)
	if status.soiled:
		UI.label(card,"Нужно сменить одежду и привести себя в порядок.",19,UI.ORANGE)
		owner._offer(card,"Привести себя в порядок","10 мин · нужен доступ к туалету","adult_health","cleanup")
	owner._offer(card,"Спокойный перерыв","15 мин · снизить дискомфорт и восстановить силы","adult_health","rest")
	if status.capabilities.menstruates:
		var menstrual := W.panel(personal)
		UI.label(menstrual,"Менструальный цикл",24,UI.BLUE)
		UI.label(menstrual,"Месячные · день %d" % int(status.cycle.day) if status.cycle.active else "Сейчас без менструальных выделений",19)
		for product in sim.services.adult_health.config().cycle.products:
			var spec: Dictionary = sim.services.adult_health.config().cycle.products[product]
			UI.label(menstrual,str(spec.label)+" · в запасе %d" % int(status.cycle.supplies[product]),18)
			owner._offer(menstrual,"Использовать: "+str(spec.label),"5 мин · в туалете или дома","adult_health","change_product",{"product":product})
			owner._offer(menstrual,"Пополнить запас","5 мин · 8 ¤ · магазин или клиника","adult_health","buy_products",{"product":product})
		if status.cycle.product!="none": UI.label(menstrual,"Используется: "+str(sim.services.adult_health.config().cycle.products[status.cycle.product].label),18,UI.MUTED)
	var medical := W.panel(columns)
	UI.label(medical,"Клиника и профилактика",24,UI.BLUE)
	if status.urgent:
		UI.label(medical,"Нужна срочная медицинская помощь. Прервите обычные дела и обратитесь в клинику.",20,UI.ORANGE)
		owner._offer(medical,"Срочная помощь","30 мин · в клинике · без оплаты","adult_health","emergency")
	if sim.state.world.location!="clinic": owner._offer(medical,"Доехать до клиники","Осмотр, наблюдение и профилактика","world","journey",{"id":"clinic"})
	owner._offer(medical,"Обсудить жалобы с врачом","30 мин · 25 ¤ · в клинике","adult_health","consult")
	for diagnosis in status.diagnoses:
		UI.label(medical,str(diagnosis.label),19,UI.MUTED)
		if sim.services.adult_health.config().conditions.has(diagnosis.id): owner._offer(medical,"Начать назначенный курс","15 мин · 20 ¤ · в клинике","adult_health","treat",{"condition":diagnosis.id})
	owner._offer(medical,"Обработка выявленных изменений кожи","45 мин · 60 ¤ · по результату осмотра","adult_health","treat_lesions")
	UI.label(medical,"Вакцинация против ВПЧ: %d из 3 этапов" % int(status.vaccine.doses),19)
	if int(status.vaccine.doses)<3: owner._offer(medical,"Пройти очередной этап вакцинации","15 мин · 40 ¤ · в клинике","adult_health","vaccinate")
	if status.capabilities.has_cervix:
		owner._offer(medical,"Скрининг шейки матки","30 мин · 35 ¤ · по возрасту и плану наблюдения","adult_health","screen")
		var results := {"none":"ещё не проводился","negative":"ВПЧ высокого риска не выявлен","positive":"выявлен ВПЧ высокого риска","normal":"изменений клеток не выявлено","cell_changes":"выявлены изменения клеток","under_observation":"составлен план наблюдения"}
		UI.label(medical,"Последний скрининг: "+str(results[status.screening.result]),18,UI.MUTED)
		if status.screening.followup: owner._offer(medical,"Уточняющий осмотр","45 мин · 50 ¤ · составить план наблюдения","adult_health","followup")
