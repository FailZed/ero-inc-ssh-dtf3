extends RefCounted
## Player-facing names and errors. Domain IDs never appear as the interface.
const NAMES := {
	"bedroom":"Спальня", "apartment_hall":"Прихожая", "bathroom":"Ванная", "kitchen":"Кухня", "global_map":"Город", "training_center":"Университет Альтерра",
	"meal":"Готовый обед", "grain":"Крупа", "vegetable":"Овощи", "jacket":"Куртка", "book":"Книга", "lockpick":"Отмычка", "computer":"Компьютер", "stove":"Плита", "desk":"Стол", "chair":"Стул", "bookshelf":"Книжный шкаф", "camera":"Камера", "bandage":"Бинт", "medicine":"Лекарство", "knuckles":"Кастет", "blade":"Нож", "bat":"Бита", "spiked_knuckles":"Шипованный кастет", "folding_blade":"Складной нож",
	"strength":"Сила", "agility":"Ловкость", "charisma":"Харизма", "intellect":"Интеллект", "luck":"Удача", "endurance":"Выносливость", "erudition":"Эрудиция", "authority":"Авторитет", "cunning":"Хитрость",
	"energy":"Выносливость", "satiety":"Сытость", "health":"Здоровье", "hygiene":"Гигиена", "mood":"Настроение", "hydration":"Запас воды", "bladder":"Туалет", "rested":"Выспанность", "fun":"Досуг", "social":"Общение",
	"study":"Учёба", "cooking":"Кулинария", "computing":"Программирование", "fighting":"Самооборона", "stealth":"Ловкость рук", "cards":"Карты", "journalism":"Журналистика",
	"human":"Человек", "semi_furry":"Полуфурри", "furry":"Фурри", "rest":"Отдыхает", "sleep":"Спит", "eat":"Ест", "work":"Работает", "walk":"Гуляет", "read":"Читает", "paid_work":"Работает", "socialize":"Общается", "train":"Тренируется", "recover":"Восстанавливается",
	"talk":"Поговорить", "listen":"Выслушать", "share_interest":"Общие интересы", "discuss_books":"Обсудить книги", "offer_help":"Предложить помощь", "joke":"Пошутить", "flirt":"Флиртовать", "set_boundary":"Обозначить границы", "invite_meeting":"Предложить встречу",
	"strength_training":"Силовая тренировка", "running":"Пробежка", "reading":"Почитать", "speech":"Практика выступлений", "cinema":"Сходить в кино",
	"first_steps":"Освоиться в городе", "quick_learner":"Быстро учусь", "first_level":"Первый шаг", "creative_collective":"Творческий клуб", "apartment":"Квартира", "studio":"Небольшая студия", "small_website":"Небольшой сайт", "application":"Приложение", "data_repair":"Восстановление данных", "photo_assignment":"Фоторепортаж", "digital":"Цифровые проекты", "retail":"Работа в магазине", "games":"Игры", "education":"Образование", "creative":"Творчество", "festival":"Фестиваль", "research":"Исследование", "publicity":"Публичная кампания", "balanced":"Сбалансированно", "exhibition":"Выставка", "read_book":"Прочитать книгу", "complete_project":"Завершить проект", "computing_class":"Практика информатики", "vegetable_meal":"Обед из овощей", "freelance":"Разовая подработка", "website_order":"Заказ сайта", "head":"Голова", "body":"Корпус", "arms":"Руки", "legs":"Ноги", "jab":"Джеб", "heavy":"Сильный удар", "kick":"Удар ногой", "feint":"Финт", "body_hook":"Хук в корпус", "uppercut":"Апперкот", "sweep":"Подсечка", "disarm":"Обезоруживание", "slash":"Режущий удар", "thrust":"Выпад", "bat_precise":"Точный удар", "bat_swing":"Размашистый удар"
}
static var _content_labels: Dictionary = {}
static func title(id: String) -> String:
	var skill_label := preload("res://scripts/gameplay/growth_presentation.gd").label(id)
	if not skill_label.is_empty(): return skill_label
	var reproductive_names := {"clinic":"Клиника","barrier_protection":"Барьерная защита","contraceptive_pill":"Регулярная контрацепция","emergency_contraception":"Экстренная контрацепция","private_time":"Проводит время наедине"}
	if reproductive_names.has(id): return str(reproductive_names[id])
	if id == "cybersecurity": return "Цифровая безопасность"
	if _content_labels.is_empty():
		var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/mechanics/remaining_content.json"))
		_content_labels = source.get("content_labels", {})
	if _content_labels.has(id): return str(_content_labels[id].label)
	var city := preload("res://scripts/gameplay/city_layout.gd").point(id)
	if not city.is_empty(): return str(city.name)
	if id == "apartment": return "Дом героя"
	var conditions := {"focused":"Сосредоточенность", "energized":"Бодрость", "stimulant":"Бодрящий тоник"}
	if conditions.has(id): return str(conditions[id])
	var life_names := {"social": "Общение", "fun": "Досуг", "travel": "В пути", "wash": "Следит за собой", "practice": "Развивает навык", "create": "Занимается проектом", "publish": "Публикует работу", "recreation": "Отдыхает", "visit": "Ищет компанию", "connect": "Общается", "support": "Поддерживает знакомого", "cooperate": "Помогает с делом", "share_values": "Говорит о важном", "apologize": "Пытается помириться", "reconcile": "Пытается помириться", "dispute": "Выясняет отношения", "court": "Проявляет интерес", "invite_relationship": "Обсуждает отношения", "gossip": "Обсуждает новости", "deceive": "Рассказывает о себе", "verify": "Проверяет сведения", "boast": "Делится успехами"}
	if life_names.has(id): return str(life_names[id])
	var extra := {"residential_district":"Жилой район", "knife":"Нож", "casual_top":"Повседневная рубашка", "work_top":"Рабочая рубашка", "training_top":"Спортивная футболка", "trousers":"Брюки", "efficient_worker":"Эффективная работа", "resilient":"Стойкость", "persuasive":"Убедительность", "fighter":"Боец", "scholar":"Эрудит", "common_day":"Общий день группы", "neighborhood_report":"Жизнь района", "club_report":"Жизнь клуба"}
	if extra.has(id): return str(extra[id])
	for subject in preload("res://scripts/gameplay/curriculum.gd").SUBJECTS:
		if id == subject+"_class": return str(preload("res://scripts/gameplay/curriculum.gd").SUBJECTS[subject].title)
	return str(NAMES.get(id, "Новый объект"))

static func extensions() -> Dictionary:
	var items: Dictionary = {}
	for file in ["base", "advanced", "parity", "balance", "remaining_content"]:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/mechanics/%s.json" % file))
		items.merge(data.get("items", {}), true)
	var stock := {}
	for id in items: stock[id] = 20 if items[id].get("category", "") in ["food", "ingredient", "medicine"] else 5
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/mechanics/base.json"))
	var resident: Dictionary = base.npc_templates.resident.duplicate(true)
	for file in ["advanced","parity","balance"]:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/mechanics/%s.json" % file))
		if data.get("npc_templates",{}).has("resident"): resident = data.npc_templates.resident.duplicate(true)
	resident.home = "residential_district"
	var student := resident.duplicate(true)
	student.role = "learner"
	student.cohort = "learner"
	student.occupation = "student"
	student.gender = "female"
	student.education = "general"
	student.schedule = [{"location": "training_center", "activity": "study", "hours": [480, 960], "weekdays": [1, 2, 3, 4, 5]}]
	var city: Dictionary = base.locations.global_map.duplicate(true)
	city.routes.residential_district = {"minutes":10}
	return {"shops": {"market": {"location": "global_map", "hours": [480, 1320], "price_multiplier": 1.0, "sell_ratio": 0.5, "stock": stock}}, "npc_templates":{"resident":resident,"story_student":student}, "locations":{"global_map":city,"residential_district":{"routes":{"global_map":{"minutes":10}}}}, "lessons":preload("res://scripts/gameplay/curriculum.gd").lessons()}

static func combat_log(entry: Dictionary) -> String:
	var actor := "Вы" if entry.get("actor", "") == "player" else "Противник"
	if entry.has("move"):
		return "%s: %s · %s" % [actor,title(str(entry.move)),"мимо" if not entry.get("hit",false) else "%d урона" % float(entry.get("damage",0))]
	return actor + (" поднимается" if entry.get("action","") == "stand_up" else " восстанавливает выносливость")

static func error(id: String) -> String:
	if preload("res://scripts/gameplay/adult_health_presentation.gd").ERRORS.has(id): return preload("res://scripts/gameplay/adult_health_presentation.gd").ERRORS[id]
	if preload("res://scripts/gameplay/growth_presentation.gd").ERRORS.has(id): return preload("res://scripts/gameplay/growth_presentation.gd").ERRORS[id]
	if preload("res://scripts/gameplay/livelihood_presentation.gd").ERRORS.has(id): return preload("res://scripts/gameplay/livelihood_presentation.gd").ERRORS[id]
	if id == "personal_story_trust": return "Для личного разговора нужны доверие и спокойные отношения."
	if id == "personal_story_finished": return "Эта личная история уже завершена."
	if id == "stale_personal_story": return "Разговор изменился. Откройте актуальный шаг."
	var reproductive_errors := {"private_location_required":"Для личной встречи нужно уединённое место.","intimacy_declined":"Человек сейчас не готов к близости.","protection_required":"Один из участников согласен только с защитой.","missing_contraception":"Нужного средства защиты нет в сумке.","contraception_not_active":"Постоянная контрацепция сейчас не действует.","mutual_family_intention_required":"Планировать зачатие должны хотеть оба участника.","clinic_required":"Для этой процедуры нужно прийти в клинику.","intimacy_cooldown":"После предыдущей встречи нужно время.","finish_active_intimacy":"Сначала завершите или остановите текущую встречу.","stale_intimacy_callback":"Этот шаг уже завершён. Обновите выбор.","patient_decision_required":"Решение принимает сам пациент.","pregnancy_not_confirmed":"Беременность ещё не подтверждена.","no_recent_exposure":"Нет недавнего эпизода, для которого доступна экстренная контрацепция.","active_pregnancy":"Во время беременности эта процедура недоступна.","reproductive_recovery":"Сначала нужно завершить восстановление.","dose_already_taken":"Сегодня регулярное средство уже использовано.","remove_existing_contraception":"Сначала нужно отменить текущий метод.","risk_acknowledgement_required":"Подтвердите, что принимаете возможность беременности.","termination_unavailable":"Этот вариант помощи сейчас недоступен.","pregnancy_decision_unchanged":"Это решение уже принято.","no_active_pregnancy":"Активной беременности нет.","gestational_capability_required":"Этот вариант не подходит репродуктивному профилю персонажа.","participant_unavailable":"Один из участников сейчас не может принять решение.","no_support_arrears":"Задолженности по алиментам нет.","support_enforcement_pending":"Заявление уже подано или взыскание действует.","support_payer_required":"Перевод должен выполнить плательщик.","support_recipient_required":"Заявление подаёт получатель алиментов."}
	if reproductive_errors.has(id): return str(reproductive_errors[id])
	var extended := {"unknown_family_member":"Этот член семьи недоступен.", "not_family_guardian":"Уход доступен родителям и опекунам.", "family_home_required":"Для ухода нужно вернуться к семье домой.", "family_care_in_progress":"Сейчас уход уже выполняется.", "family_care_cooldown":"Эту заботу недавно уже оказали. Можно выбрать другое дело.", "family_member_at_school":"Сейчас идут занятия. Член семьи вернётся после 14:00.", "family_support_active":"Помощь с уходом уже оплачена и действует.", "npc_caring_for_family":"Сейчас этот человек занят уходом за ребёнком.", "digital_skill_required":"Для этой операции нужен более высокий навык программирования.", "digital_cooldown":"Эта цифровая задача пока недоступна повторно.", "finish_digital_report":"Сначала завершите или отмените подготовленную задачу.", "stale_digital_report":"Подготовка устарела. Начните её заново.", "collection_locked":"Это воспоминание пока не открыто."}
	if extended.has(id): return str(extended[id])
	var city_errors := {"agency_required":"Оформить жильё можно в агентстве недвижимости.","agency_closed":"Агентство работает с 09:00 до 18:00.","social_housing_ineligible":"Социальное жильё доступно после потери ученического дома, если нет денег на обычную аренду.","city_route_unavailable":"Сейчас путь закрыт. Проверьте часы работы места назначения.","no_current_home":"Сначала найдите новое жильё в агентстве недвижимости."}
	if city_errors.has(id): return str(city_errors[id])
	if id == "tonic_vendor_required": return "Тоник можно купить и выпить у городского продавца."
	if id == "guest_schedule_conflict": return "На это время у гостя уже запланированы учёба, работа или встреча."
	var shared_time := {"invalid_gathering_size":"Выберите от двух до шести гостей.", "gathering_daily_limit":"Сегодня вы уже проводили встречу компанией.", "guest_not_present":"Все выбранные гости должны находиться рядом.", "invalid_guest":"Состав гостей изменился. Выберите участников заново.", "guest_trust":"Гостю нужно больше доверия, чтобы провести время вместе.", "encouragement_daily_limit":"Вы уже поддержали этого человека сегодня.", "insufficient_trust":"Пока не хватает доверия для такого разговора.", "project_requirements":"Для проекта нужен установленный дома компьютер.", "project_completed":"Этот проект уже завершён и оплачен."}
	if shared_time.has(id): return str(shared_time[id])
	var invitations := {"meet_person_first":"Сначала познакомьтесь с этим человеком.", "tenant_invitation_declined":"Человек пока не готов жить вместе. Сначала нужно больше доверия.", "club_invitation_declined":"Сейчас человеку неинтересно вступать в клуб.", "npc_overcommitted":"У человека уже достаточно обязательств в других клубах.", "npc_ballot_private":"Участники сами выбирают, за кого голосовать.", "voting_incomplete":"Дождитесь голосов остальных участников.", "voters_busy":"Оставшиеся участники сейчас спят или заняты. Проведите голосование позже."}
	if invitations.has(id): return invitations[id]
	if id == "promise_already_satisfied": return "Это уже сделано. Обещание должно относиться к будущему поступку."
	var places := {"bed_required":"Для сна нужна кровать в спальне.", "bathroom_required":"Сначала нужно зайти в ванную.", "home_required":"Это домашнее дело. Сначала вернитесь в квартиру.", "kitchen_required":"Готовить на плите можно на кухне.", "home_workspace_required":"Нужно вернуться к домашнему рабочему месту.", "invalid_rest_kind":"Выберите отдых, сон или короткий сон."}
	if places.has(id): return places[id]
	if id == "water_source_required": return "Воду можно набрать на кухне или в ванной."
	if id == "toilet_required": return "Сначала нужно зайти в ванную."
	if id == "leisure_place_required": return "Отдохнуть за хобби можно в спальне, а прогуляться — в городе."
	if id == "private_conversation_required": return "Для этой темы нужен разговор без посторонних или личная переписка."
	if id == "adults_only": return "Тема доступна только совершеннолетним персонажам."
	var dialogue_errors := {"stale_dialogue_turn": "Разговор уже продолжился. Выберите один из текущих ответов.", "dialogue_expired": "После этого разговора прошло время. Начните новый разговор.", "stale_initiative": "Предложение уже неактуально. Можно связаться с человеком позже.", "missing_contact": "Сначала обменяйтесь контактами при встрече.", "unknown_dialogue_choice": "Этот ответ сейчас недоступен."}
	if dialogue_errors.has(id): return str(dialogue_errors[id])
	var social_errors := {"contact_boundary": "Собеседник сейчас не хочет общаться. Уважайте его границы.", "romantic_boundary": "Собеседник не принимает романтические инициативы. Дайте ему пространство.", "gossip_boundary": "Собеседник не хочет обсуждать чужие новости.", "unresolved_harm": "Сначала нужно разобраться с причинённым вредом и восстановить доверие.", "insufficient_closeness": "Для личного разговора пока не хватает доверия и комфорта.", "no_unacknowledged_harm": "Сейчас нет непризнанного вреда. Повторять извинения не требуется.", "relationship_not_ready": "Предложение отношений требует взаимных доверия, близости и интереса.", "existing_relationship": "Один из вас уже состоит в отношениях.", "relationship_cooldown": "После расставания нужно время.", "npc_needs_recovery": "Собеседнику сейчас нужен сон, еда или восстановление.", "invalid_personality_settings": "Проверьте настройки характеров жителей."}
	if social_errors.has(id): return str(social_errors[id])
	var messages := {"story_locked":"Сейчас продолжается история. Свободные действия откроются после первой главы.", "incompatible_save":"Состояние мира не удалось восстановить.", "insufficient_funds":"Не хватает денег.", "travel_funds":"Не хватает денег на дорогу.", "insufficient_energy":"Сначала нужно отдохнуть.", "location_closed":"Это место сейчас закрыто.", "no_route":"Сначала вернитесь к выходу из локации.", "wrong_location":"Это занятие доступно в другом месте.", "wrong_workplace":"Нужно прийти на рабочее место.", "shop_closed":"Магазины открыты с 08:00 до 22:00.", "missing_equipment":"Нужно установить необходимое оборудование дома.", "missing_work_equipment":"Для этой работы нужно оборудование дома.", "missing_ingredients":"Не хватает ингредиентов.", "inventory_capacity":"В сумке не хватает места.", "insufficient_items":"Нет нужного предмета.", "out_of_stock":"Товар закончился. Загляните завтра.", "npc_not_present":"Этот человек сейчас в другом месте.", "dialogue_fatigue":"Собеседник устал. Дайте ему время.", "npc_busy":"Сейчас собеседник занят.", "npc_sleeping":"Собеседник спит.", "npc_recovering":"Собеседнику нужно восстановиться.", "insufficient_trust":"Сначала стоит узнать друг друга лучше.", "incompatible_attraction":"Нет взаимного романтического интереса.", "content_disabled":"Это отключено в настройках мира.", "finish_active_combat":"Сначала завершите бой.", "finish_active_game":"Сначала завершите текущую мини-игру.", "recover_from_exhaustion":"Нужно восстановиться после истощения.", "no_points_or_unknown_stat":"Нет свободных очков развития.", "overtraining_limit":"На сегодня нагрузки достаточно.", "job_daily_limit":"Сегодня эта подработка уже недоступна.", "shift_daily_limit":"Сегодняшняя смена уже отработана.", "lesson_unavailable":"Занятие сейчас не проводится.", "lesson_already_attended":"Сегодня вы уже были на этом занятии.", "education_expelled":"Сначала нужно восстановиться в университете.", "appointment_conflict":"На это время уже назначена другая встреча.", "furniture_collision":"Это место занято другой мебелью.", "furniture_out_of_bounds":"Предмет не помещается в комнате.", "property_not_acquired":"Сначала нужно арендовать или купить жильё.", "not_equipment":"Этот предмет нельзя установить.", "already_installed":"Оборудование уже установлено.", "already_furnished":"Такая мебель уже стоит в квартире.", "treatment_cooldown":"Лечение пока нельзя повторить.", "no_fine":"Неоплаченных штрафов нет.", "no_sentence":"У вас нет назначенного наказания.", "no_unresolved_conflict":"Сейчас не за что извиняться.", "date_cooldown":"После свидания должно пройти время."}
	if messages.has(id): return messages[id]
	if id.contains("requirement"): return "Пока не выполнены условия: проверьте место, навыки и снаряжение."
	if id.contains("cooldown") or id.contains("limit"): return "Пока недоступно. Попробуйте после отдыха или в другой день."
	if id.contains("level"): return "Для этого нужен более высокий уровень навыка."
	if id.contains("trust") or id.contains("relationship") or id.contains("attraction"): return "Ваши отношения пока не позволяют это сделать."
	if id.contains("ap") or id.contains("stamina"): return "Недостаточно очков действия или выносливости. Завершите ход или восстановитесь."
	if id.contains("equipment") or id.contains("furniture"): return "Нужного снаряжения или мебели пока нет."
	return "Сейчас это действие недоступно. Ресурсы не потрачены."

static func actor_name(sim, id: String) -> String:
	return "вы" if id == "player" else str(sim.state.social.npcs.get(id, {}).get("name", "знакомый"))

static func event_text(event: Dictionary, sim) -> String:
	var data: Dictionary = event.get("data", {})
	if str(event.get("kind","")).begins_with("adult_health_"):
		var target := str(data.get("target",""))
		if target!="player":
			if event.kind=="adult_health_setback" and data.get("partner","")=="player": pass
			elif event.kind!="adult_health_remark" or sim.state.social.npcs.get(target,{}).get("location","")!=sim.state.world.location: return ""
		if str(data.get("text","")).is_empty(): return ""
		return str(data.text) if target=="player" else actor_name(sim,target)+": «"+str(data.text)+"»"
	if str(event.get("kind","")).begins_with("pregnancy_wellbeing_"):
		var target := str(data.get("target",""))
		if target!="player" and sim.state.social.npcs.get(target,{}).get("location","")!=sim.state.world.location: return ""
		if str(data.get("text","")).is_empty(): return ""
		return str(data.text) if target=="player" else actor_name(sim,target)+": «"+str(data.text)+"»"
	if event.get("kind", "") == "reproduction_pregnancy_detected" and "player" in [data.get("target", ""),data.get("partner", "")]:
		return "Беременность подтверждена: " + ("вы" if data.target=="player" else actor_name(sim,str(data.target))) + "."
	if event.get("kind", "") == "intimacy_ended": return "Встреча завершена." if data.get("status", "") == "completed" else "Встреча остановлена."
	if str(event.get("kind", "")).begins_with("child_support_"):
		var obligation: Dictionary = sim.state.get("child_support",{}).get("obligations",{}).get(str(data.get("id","")),{})
		if not "player" in [obligation.get("payer",""),obligation.get("recipient","")]: return ""
		if event.kind == "child_support_billed": return "Начислены алименты: %d ¤." % int(data.amount)
		if event.kind == "child_support_payment": return "Перевод алиментов: %d ¤." % int(data.amount)
		if event.kind == "child_support_order": return "Началось взыскание задолженности по алиментам."
	if str(event.get("kind","")) == "personal_story_ready": return str(data.title) + ": можно вернуться к собеседнику."
	if str(event.get("kind","")) == "personal_story_completed": return str(data.title) + ": личная история завершена."
	if str(event.get("kind", "")).begins_with("family_"):
		var member: Dictionary = sim.state.get("family", {}).get("members", {}).get(str(data.get("member", "")), {})
		if member.is_empty() or not "player" in member.get("parents", []): return ""
		match str(event.kind):
			"family_born": return "В семье появился ребёнок. Уход и обязанности доступны в разделе «Моя семья»."
			"family_milestone": return str(member.name) + ": новый этап — " + str(sim.catalog.family_stages[member.stage].label) + "."
			"family_needs_attention": return str(member.name) + ": нужна помощь с повседневными потребностями."
			"family_expenses_due": return "Не хватило денег на семейные расходы. Задолженность видна в разделе семьи."
		return ""
	match str(event.get("kind", "")):
		"effect_expired": return "Закончился эффект: " + title(str(data.id)) + "."
		"project_completed": return "Проект «%s» завершён. Оплата поступила." % title(str(data.id))
		"gathering_completed": return "Встреча компанией завершилась. Участники отдохнули и узнали друг друга лучше."
		"club_election_finished": return "Участники клуба выбрали руководителя: " + actor_name(sim, str(data.winner)) + "."
		"club_election_cancelled": return "Состав клуба изменился. Выборы нужно назначить заново."
		"player_need_critical":
			var life = preload("res://scripts/gameplay/player_needs.gd")
			return str(life.LABELS.get(str(data.need), "Пора позаботиться о себе")) + ". " + str(life.REMEDIES.get(str(data.need), "")) + "."
		"player_need_recovered": return "Снова комфортно: " + title(str(data.need)) + "."
		"npc_initiative": return "%s: %s" % [actor_name(sim, str(data.npc)), str(data.text)]
		"npc_social_outcome":
			var actor := str(data.actor)
			var target := str(data.target)
			var present: bool = sim.state.social.npcs.get(actor, {}).get("location", "") == sim.state.world.location and sim.state.social.npcs[target].location == sim.state.world.location
			if actor != "player" and target != "player" and not present: return ""
			return "%s → %s: %s · %s." % [actor_name(sim, actor), actor_name(sim, target), sim.catalog.agency_actions[data.action].label, "принято" if data.accepted else "отказ"]
		"npc_social_harm":
			if data.actor != "player" or data.get("reason", "") == "witnessed_crime": return ""
			return actor_name(sim, str(data.victim)) + " помнит причинённый вред. Доверие и комфорт изменились."
		"npc_relationship_formed", "npc_relationship_separated":
			if not "player" in [data.a, data.b] and not (str(data.a) in sim.state.social.contacts and str(data.b) in sim.state.social.contacts): return ""
			return "%s и %s %s." % [actor_name(sim, str(data.a)), actor_name(sim, str(data.b)), "договорились об отношениях" if event.kind == "npc_relationship_formed" else "расстались"]
		"npc_life_milestone", "npc_life_new_aspiration":
			if not str(data.npc) in sim.state.social.contacts: return ""
			var goal := str(sim.catalog.agency_aspirations[data.details.goal].label)
			return "%s: %s «%s»." % [actor_name(sim, str(data.npc)), "новая цель" if event.kind == "npc_life_new_aspiration" else "продвижение к цели", goal]
		"level_up": return "Новый уровень! Доступны очки развития."
		"quest_completed": return "Задача выполнена. Заберите награду в журнале."
		"quest_failed": return "Срок задания истёк. В журнале появились подробности."
		"education_warning": return "Из университета пришло предупреждение о пропусках."
		"education_expulsion": return "Вас отчислили. В разделе учёбы доступна процедура восстановления."
		"npc_message_received": return "Новое сообщение в телефоне."
		"contract_failed": return "Срок заказа истёк."
		"club_wages_unpaid": return "В бюджете клуба не хватило денег на оплату."
		"wanted": return "Вас разыскивают. Проверьте штрафы и последствия."
		"condition_completed": return "Изменилось длительное состояние персонажа."
		"condition_stage": return "Новый этап состояния персонажа."
		"combat_finished": return "Бой завершён. Проверьте самочувствие и раны."
		"game_finished": return "Испытание завершено: " + ("победа" if data.get("status", "") == "won" else "ничья" if data.get("status", "") == "draw" else "поражение") + "."
	return ""
