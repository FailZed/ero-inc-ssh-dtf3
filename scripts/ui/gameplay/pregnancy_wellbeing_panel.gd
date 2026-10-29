extends RefCounted
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")

static func populate(owner: Control, parent: VBoxContainer, target: String = "player") -> void:
	var sim = Gameplay.simulation
	var status: Dictionary = sim.services.pregnancy_wellbeing.view(target)
	if status.is_empty() or (not status.active and not status.soiled): return
	var card := UI.card(parent)
	UI.label(card,"Восстановление после родов" if status.phase=="postpartum" else "Самочувствие",24,UI.BLUE)
	if status.phase=="pregnancy" and not sim.services.reproduction.pregnancy(target).is_empty() and sim.services.reproduction.pregnancy(target).known:
		UI.label(card,"Беременность · месяц %d" % int(status.month),19,UI.MUTED)
	if status.symptom_list.is_empty(): UI.label(card,"Сейчас без заметного дискомфорта.",19,UI.MUTED)
	for symptom in status.symptom_list:
		var intensity := "сильнее обычного" if int(symptom.severity)>=65 else "заметно" if int(symptom.severity)>=35 else "незначительно"
		UI.label(card,str(symptom.label)+" · "+intensity,18,UI.ORANGE if int(symptom.severity)>=65 else UI.INK)
	if status.soiled: UI.label(card,"Нужно уединиться и сменить одежду.",19,UI.ORANGE)
	if status.seek_care: UI.label(card,"Самочувствие требует внимания врача. Обратитесь в клинику.",19,UI.ORANGE)
	if target!="player":
		owner._offer(card,"Предложить помощь","5 мин · помочь сделать спокойный перерыв","pregnancy_wellbeing","support",{"target":target})
		return
	UI.label(card,"Гигиенические средства: %d" % int(status.supplies),18,UI.MUTED)
	if status.active:
		owner._offer(card,"Сделать спокойный перерыв","15 мин · немного восстановить силы","pregnancy_wellbeing","rest")
		owner._offer(card,"Зайти в туалет","5 мин · нужен доступный туалет","pregnancy_wellbeing","toilet")
	if status.soiled: owner._offer(card,"Привести себя в порядок","10 мин · сменить одежду и умыться","pregnancy_wellbeing","cleanup")
	if status.active:
		owner._offer(card,"Купить гигиенические средства","5 мин · 6 €$ за три · клиника или магазин","pregnancy_wellbeing","supplies")
		if status.phase=="pregnancy": owner._offer(card,"Обсудить самочувствие на осмотре","30 мин · 30 €$ · в клинике","pregnancy_wellbeing","checkup")
