extends RefCounted
## Read-only views shared by the city, phone, profile and conversation screens.
const Names = preload("res://scripts/gameplay/presentation.gd")
const STAGES := {"stranger": "Ещё не знакомы", "acquaintance": "Знакомые", "friend": "Дружба", "close_friend": "Близкая дружба", "strained": "Напряжённые отношения", "partner": "Партнёрство", "separated": "После расставания"}
const EMOTIONS := {"content": "Спокойное настроение", "happy": "Хорошее настроение", "grateful": "Благодарность", "confident": "Уверенность в себе", "inspired": "Вдохновение", "hurt": "Задетые чувства", "angry": "Сердитое настроение", "sad": "Грусть", "tense": "Напряжение", "lonely": "Не хватает общения", "exhausted": "Сильная усталость", "hopeful": "Надежда", "focused": "Сосредоточенность"}
const SCALES := {"trust": "Доверие", "affection": "Симпатия", "comfort": "Комфорт", "respect": "Уважение", "closeness": "Близость", "interest": "Романтический интерес", "grievance": "Обида"}
const ACTIONS := ["connect", "support", "cooperate", "share_values", "joke", "apologize", "court", "invite_relationship"]

static func actor_name(sim, id: String) -> String:
	return Names.actor_name(sim, id)

static func life(sim, id: String) -> Dictionary:
	var npc: Dictionary = sim.state.social.npcs.get(id, {})
	if not npc.has("mind"): return {}
	var aspiration: Dictionary = npc.mind.aspiration
	var definition: Dictionary = sim.catalog.agency_aspirations[aspiration.id]
	var stage := int(aspiration.stage)
	var progress: float = 1.0 if aspiration.completed else (stage + float(aspiration.progress) / float(definition.stages[stage].minutes)) / definition.stages.size()
	var active: Dictionary = npc.mind.active
	var action := str(active.get("action", npc.activity))
	var activity := str(sim.catalog.agency_actions.get(action, {}).get("label", Names.title(str(npc.activity))))
	if active.get("phase", "") == "travel": activity = "В пути: " + Names.title(str(active.destination))
	if npc.activity=="appointment_travel": activity = "В пути на назначенную встречу"
	elif npc.activity=="appointment": activity = "Ожидает на месте встречи"
	if not str(active.get("partner", "")).is_empty(): activity += " · " + actor_name(sim, str(active.partner))
	return {"goal": definition.label, "stage": mini(stage + 1, definition.stages.size()), "stages": definition.stages.size(),
		"progress": progress * 100.0, "completed": aspiration.completed, "activity": activity,
		"emotion": EMOTIONS.get(npc.mind.emotion.id, "Занят своими делами"), "location": Names.title(str(npc.location))}

static func bond(sim, id: String, other: String = "player") -> Dictionary:
	var result: Dictionary = sim.services.npc_relationships.view(id, other)
	var pair := [id, other]
	pair.sort()
	var shared: Dictionary = sim.state.social.relationships.get("%s|%s" % [pair[0], pair[1]], {})
	result.status = str(shared.get("status", "acquaintance"))
	result.status_text = str(STAGES.get(shared.status if shared.get("status", "") in ["partner", "separated"] else result.stage, "Знакомые"))
	return result

static func preview(sim, id: String, action: String) -> Dictionary:
	var result: Dictionary = sim.services.npc_relationships.forecast("player", id, action)
	var npc: Dictionary = sim.state.social.npcs.get(id, {})
	if not npc.has("mind"): return {"blocked": "unknown_npc", "chance": 0.0}
	if str(result.blocked).is_empty() and npc.location != sim.state.world.location: result.blocked = "npc_not_present"
	if str(result.blocked).is_empty():
		var availability: Dictionary = sim.services.social_rules.availability(id, true)
		if not availability.ok: result.blocked = str(availability.error)
	if str(result.blocked).is_empty() and not str(npc.mind.active.get("partner", "")).is_empty(): result.blocked = "npc_busy"
	return result

static func change_summary(before: Dictionary, after: Dictionary) -> String:
	var changes: Array[String] = []
	for key in ["trust", "affection", "comfort", "grievance"]:
		var delta := float(after.get(key, 0)) - float(before.get(key, 0))
		if absf(delta) >= 0.1: changes.append("%s %+.1f" % [SCALES[key], delta])
	return " · ".join(changes)

static func response(action: String, accepted: bool) -> String:
	if not accepted: return "Собеседник отказался. Стоит уважить его решение и дать ему пространство."
	var reactions := {"apologize": "Собеседник услышал извинение. Вред признан; доверие восстановят дальнейшие поступки.", "invite_relationship": "Вы обсудили свои чувства и договорились об отношениях.", "cooperate": "Вы помогли с делом. Собеседник запомнит вашу поддержку.", "offer_help": "Вы помогли с делом. Собеседник запомнит вашу поддержку.", "share_values": "Вы поговорили о том, что важно для каждого из вас.", "support": "Вы выслушали собеседника и поддержали его.", "court": "Собеседник принял вашу инициативу. Можно узнавать друг друга дальше."}
	return str(reactions.get(action, "Собеседник поддержал разговор. Вы лучше узнали друг друга."))

static func history(sim, id: String) -> Array:
	var result: Array = []
	var npc: Dictionary = sim.state.social.npcs[id]
	for entry in npc.mind.history:
		var detail: Dictionary = entry.data
		var text := ""
		match str(entry.kind):
			"companion":
				var moment_labels := {"hand":"Держались за руки","head":"Тёплый жест","face":"Ласковое прикосновение"}
				var outcome_labels := {"completed":"приятный момент вместе","declined":"предложение отклонено","cancelled":"встреча остановлена","interrupted":"планы изменились"}
				text = "%s · %s" % [moment_labels.get(detail.gesture,"Время вместе"),outcome_labels.get(detail.outcome,"")]
			"social_outcome": text = "%s · %s · %s" % [sim.catalog.agency_actions[detail.action].label, actor_name(sim, str(detail.other)), "удачно" if detail.accepted else "отказ"]
			"experience":
				var experiences := {"betrayed": "Переживание предательства", "misled": "Обнаружен обман", "conflict": "Остался конфликт", "supported": "Поддержка", "romantic_interest": "Романтический интерес", "witnessed_harm": "Свидетель происшествия"}
				if experiences.has(detail.kind): text = str(experiences[detail.kind]) + " · " + actor_name(sim, str(detail.other))
			"work_paid": text = "Работа: %d мин · заработано %d ¤" % [detail.minutes,detail.paid]
			"career_progress": text = "Карьерная ступень %d · %s" % [detail.level,Names.title(str(detail.skill))]
			"milestone": text = "Продвинулся к цели: " + str(sim.catalog.agency_aspirations[detail.goal].label)
			"new_aspiration": text = "Новая цель: " + str(sim.catalog.agency_aspirations[detail.goal].label)
		if not text.is_empty():
			var clock: Dictionary = sim.calendar.snapshot(int(entry.minute))
			result.push_front({"text": text, "time": "%s · %s" % [clock.date_text, clock.time_text]})
	return result.slice(0, 6)
