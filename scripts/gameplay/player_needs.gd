extends "res://scripts/mechanics/core/module.gd"
## Player needs for EroInc's main game. Values mean fulfilment: higher is better.
const DEFAULTS := {"hydration": 100.0, "bladder": 100.0, "rested": 100.0, "fun": 80.0, "social": 80.0}
const DECAY_PER_HOUR := {"hydration": 4.0, "bladder": 7.0, "rested": 4.0, "fun": 3.0, "social": 3.0}
const STAMINA_RECOVERY_PER_MINUTE := 1.0
const DISPLAYED := ["health", "energy", "hydration", "satiety", "hygiene", "bladder", "rested", "fun", "social"]
const LABELS := {"health": "Низкое здоровье", "energy": "Мало выносливости", "hydration": "Хочется пить", "satiety": "Хочется есть", "hygiene": "Пора принять душ", "bladder": "Пора в туалет", "rested": "Хочется спать", "fun": "Не хватает досуга", "social": "Не хватает общения"}
const REMEDIES := {"health": "Отдохнуть или обратиться за лечением", "energy": "Снизить нагрузку и перевести дух", "hydration": "Вода доступна на кухне и в ванной", "satiety": "Поесть из сумки или приготовить еду на кухне", "hygiene": "Принять душ в ванной", "bladder": "Зайти в туалет в ванной", "rested": "Поспать или вздремнуть в спальне", "fun": "Хобби, книга, кино или игра", "social": "Поговорить с человеком или позвонить знакомому"}

func _init(simulation) -> void:
	super(simulation)
	sim.state_restored.connect(initialize)
	initialize()

func initialize() -> void:
	# Only the loaded in-memory world is initialized; save files are never rewritten.
	for id in DEFAULTS:
		if not sim.state.player.needs.has(id): sim.state.player.needs[id] = DEFAULTS[id]
	if not sim.state.player.has("need_warnings"): sim.state.player.need_warnings = {}
	for id in DISPLAYED:
		if not sim.state.player.need_warnings.has(id): sim.state.player.need_warnings[id] = float(sim.state.player.needs[id]) < 20.0

func execute(operation: String, _args: Dictionary) -> Dictionary:
	var location := str(sim.state.world.location)
	var minutes := 0
	match operation:
		"drink":
			if not location in ["kitchen", "bathroom"]: return Rules.fail("water_source_required")
			minutes = 2
		"toilet":
			if location != "bathroom": return Rules.fail("toilet_required")
			minutes = 5
		"leisure":
			if not location in ["bedroom", "global_map", "riverside_cafe", "city_park", "south_promenade", "north_beach"]: return Rules.fail("leisure_place_required")
			minutes = 30
		"sleep", "nap":
			if location != "bedroom": return Rules.fail("bed_required")
			minutes = int(_args.get("minutes", 480 if operation == "sleep" else 30))
			if minutes < 15 or minutes > 720: return Rules.fail("invalid_rest_duration")
			return sim.services.character.execute("rest", {"minutes": minutes})
		_: return Rules.fail("unknown_operation")
	var result: Dictionary = sim.advance(minutes)
	if not result.ok: return result
	match operation:
		"drink":
			sim.services.character.adjust_need("hydration", 50.0)
			sim.services.character.adjust_need("bladder", -6.0)
		"toilet":
			sim.services.character.adjust_need("bladder", 100.0)
			sim.services.character.adjust_need("hygiene", -5.0)
		"leisure":
			sim.services.character.adjust_need("fun", 40.0)
			sim.services.character.adjust_need("mood", 8.0)
	return Rules.ok({"minutes": minutes})

func recovery_factor() -> float:
	var factor := 1.0
	for id in ["hydration","rested"]:
		var value := _effective(id,25)
		if value < 25: factor *= 0.35+0.65*value/25.0
	return factor

func learning_factor() -> float:
	var factor := 1.0
	for id in ["hydration","rested"]:
		var value := _effective(id,25)
		if value < 25: factor *= 0.8+0.2*value/25.0
	return factor

func mood_target() -> float:
	var target := 78.0
	for id in sim.services.growth.NEED_IDS:
		if not sim.services.growth.enabled(id): continue
		target -= maxf(0,50-float(sim.state.player.needs[id]))*0.20*sim.services.growth.penalty_factor(id)
	return clampf(target,15,78)

func condition() -> Dictionary:
	var warnings: Array = []
	for id in DISPLAYED:
		if id == "satiety" and not sim.services.preferences.rule("satiety_enabled", true): continue
		var value := float(sim.state.player.needs[id])
		if value < 40.0: warnings.append({"id": id, "value": value, "critical": value < 20.0, "text": LABELS[id], "remedy": REMEDIES[id]})
	var disabled: Array = []
	for id in sim.services.growth.NEED_IDS:
		if not sim.services.growth.enabled(id): disabled.append(id)
	return {"recovery": recovery_factor(), "learning": learning_factor(), "mood_target": mood_target(), "warnings": warnings,"disabled_needs":disabled}

func update_warnings() -> void:
	for id in DISPLAYED:
		if id == "satiety" and not sim.services.preferences.rule("satiety_enabled", true):
			sim.state.player.need_warnings[id] = false
			continue
		var value := float(sim.state.player.needs[id])
		var warned: bool = sim.state.player.need_warnings[id]
		if value < 20.0 and not warned:
			sim.state.player.need_warnings[id] = true
			emit_event("player_need_critical", {"need": id})
		elif value >= 40.0 and warned:
			sim.state.player.need_warnings[id] = false
			emit_event("player_need_recovered", {"need": id})

func tick(_minute: int) -> void:
	for id in DECAY_PER_HOUR:
		sim.services.character.adjust_need(id, -float(DECAY_PER_HOUR[id]) * sim.multiplier("need_decay") / 60.0)
	var context: Dictionary = sim.action_context
	if context.get("sleeping", false):
		sim.services.character.adjust_need("rested", 0.38 if context.get("rest_kind", "sleep") == "sleep" else 0.30)
	if not context.get("exerting", false):
		sim.services.character.adjust_need("energy", STAMINA_RECOVERY_PER_MINUTE * recovery_factor())
	if context.get("physical", false):
		sim.services.character.adjust_need("hydration", -0.03)
		sim.services.character.adjust_need("hygiene", -0.02)
	var mood := float(sim.state.player.needs.mood)
	sim.services.character.adjust_need("mood", clampf(mood_target() - mood, -0.06, 0.02))
	if float(sim.state.player.needs.hydration) <= 0.0: sim.services.character.adjust_need("health", -0.02*sim.services.growth.penalty_factor("hydration"))
	update_warnings()

func after_action(module_id: String, operation: String, args: Dictionary, result: Dictionary, minutes: int) -> void:
	# Reward only completed actions that consumed world time, never UI navigation.
	if minutes <= 0: return
	if module_id == "npc_dialogue" and operation == "choose":
		if result.get("data", {}).get("accepted", true):
			sim.services.character.adjust_need("social", minf(15.0, minutes * 1.2))
	elif module_id in ["social", "npc_relationships"] and operation in ["interact", "call"]:
		if result.get("data", {}).get("accepted", true): sim.services.character.adjust_need("social", 12.0 if operation == "call" else minf(40.0, maxf(8.0, minutes * 1.2)))
	elif module_id == "activities" and operation == "practice" and args.get("id", "") == "cinema":
		sim.services.character.adjust_need("fun", 40.0)
	elif module_id == "actions" and operation == "perform" and args.get("id", "") == "read":
		sim.services.character.adjust_need("fun", 15.0)

	elif module_id == "encounters" and operation == "game_input":
		var game: Dictionary = sim.state.encounters.game
		if game.get("status", "active") != "active" and not game.has("context"):
			sim.services.character.adjust_need("fun", 10.0)
	elif module_id == "social_rules" and operation == "date":
		sim.services.character.adjust_need("social", 25.0)
		sim.services.character.adjust_need("fun", 20.0)
	elif module_id == "social_rules" and operation == "gathering":
		sim.services.character.adjust_need("social", 40.0)
		sim.services.character.adjust_need("fun", 30.0)
	elif module_id == "npc_agency" and operation == "encourage":
		sim.services.character.adjust_need("social", 6.0)

func _effective(id: String, threshold: float) -> float:
	if not sim.services.growth.enabled(id): return 100.0
	var value := float(sim.state.player.needs[id])
	return threshold-(threshold-value)*sim.services.growth.penalty_factor(id) if value < threshold else value

