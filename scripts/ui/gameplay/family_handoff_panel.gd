extends RefCounted
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const Names = preload("res://scripts/gameplay/presentation.gd")
const NEEDS := {"food":"питание","hygiene":"гигиена","rest":"отдых","attention":"внимание"}

static func populate(owner: Control, parent: Node, member: Dictionary) -> void:
	var sim = Gameplay.simulation
	if not member.task.is_empty():
		var task: Dictionary = member.task
		var caregiver := "Вы" if task.caregiver=="player" else Names.actor_name(sim,str(task.caregiver))
		UI.label(parent,"Сейчас помогает: "+caregiver+" · "+str(sim.catalog.family_actions[task.action].label),18,UI.BLUE)
		UI.label(parent,"Осталось %d мин. Результат появится после завершения ухода." % maxi(0,int(task.due)-int(sim.state.clock.total_minutes)),16,UI.MUTED)
		return
	var offered := false
	for need in NEEDS:
		if float(member.needs[need])>=45: continue
		for option in sim.services.family.care_options(str(member.id),str(need)):
			if not offered: UI.label(parent,"Разовая помощь другого опекуна",20,UI.BLUE); offered = true
			var title := Names.actor_name(sim,str(option.caregiver))+" · "+str(NEEDS[need])
			var detail := "%d мин · %d ¤ · постоянный ответственный сохранится" % [int(option.minutes),int(option.cost)]
			var reason := "" if option.available else Names.error(str(option.reason))
			var button: Button = owner._offer(parent,title,detail,"family","delegate",{"id":member.id,"need":need,"caregiver":option.caregiver},reason,false,true)
			button.text = "Попросить помочь один раз"
