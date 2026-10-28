extends "res://scripts/mechanics/core/module.gd"
## Abstract game checks only. No network, commands, files or real exploit techniques.
const CHECK = preload("res://scripts/mechanics/core/validation.gd")

static func defaults() -> Dictionary:
	return {"serial":0, "pending":{}, "cooldowns":{}, "trace":0.0, "history":[], "leads":[]}

static func catalog_error(catalog: Dictionary) -> String:
	for spec in catalog.get("digital_operations", {}).values():
		if not CHECK.fields(spec, {"label":"s", "minutes":"n", "level":"n", "reward":"n", "risk":"n", "cooldown":"n", "outcome":"s"}): return "invalid_digital_catalog"
		for key in ["minutes", "level", "reward", "risk", "cooldown"]:
			if float(spec[key]) < 0 or float(spec[key]) != int(spec[key]): return "invalid_digital_catalog"
		if int(spec.minutes) < 1 or int(spec.minutes) > 240 or int(spec.cooldown) < 60 or int(spec.reward) > 1000 or int(spec.risk) > 100: return "invalid_digital_catalog"
		if not spec.outcome in ["practice", "work", "grades", "directory", "money"]: return "invalid_digital_catalog"
	return ""

func initialize() -> void:
	if not sim.state.has("digital"): sim.state.digital = defaults()

func blocked(id: String) -> String:
	var spec := definition("digital_operations", id)
	if spec.is_empty(): return "unknown_digital_operation"
	if not "computer" in sim.state.world.equipment: return "missing_equipment"
	if not sim.is_player_home_location(str(sim.state.world.location)): return "home_workspace_required"
	if float(spec.risk) > 0 and "crime" in sim.state.preferences.disabled_tags: return "content_disabled"
	if int(sim.state.player.skills.get("computing", 0)) < int(spec.level): return "digital_skill_required"
	if int(sim.state.digital.cooldowns.get(id, 0)) > int(sim.state.clock.total_minutes): return "digital_cooldown"
	return ""

func preview(id: String, approach: String = "balanced") -> Dictionary:
	var spec := definition("digital_operations",id)
	if spec.is_empty(): return Rules.fail("unknown_digital_operation")
	var styles := {"careful":{"time":1.5,"chance":0.12,"trace":0.5,"pay":0.85},"balanced":{"time":1.0,"chance":0.0,"trace":1.0,"pay":1.0},"fast":{"time":0.65,"chance":-0.12,"trace":1.5,"pay":1.15}}
	if not styles.has(approach): return Rules.fail("invalid_digital_approach")
	var style: Dictionary = styles[approach]
	var computing := float(sim.state.player.skills.get("computing",0))
	var security := float(sim.state.player.skills.get("cybersecurity",0))
	var chance := clampf(0.5+computing/(computing+150)*0.35+security/(security+100)*0.15-float(spec.risk)*0.006-float(sim.state.digital.trace)*0.003+float(style.chance),0.1,0.95)
	var modifiers: Dictionary = sim.services.computer.digital_modifiers(id) if sim.services.has("computer") else {"chance":0.0,"trace_scale":1.0}
	chance = clampf(chance+float(modifiers.chance),0.1,0.95)
	return Rules.ok({"id":id,"approach":approach,"minutes":ceili(float(spec.minutes)*float(style.time)),"chance":chance,"trace_scale":float(style.trace)*float(modifiers.trace_scale),"reward":roundi(float(spec.reward)*float(style.pay)),"blocked":blocked(id),"partial_possible":spec.outcome in ["practice","work"]})

func execute(operation: String, args: Dictionary) -> Dictionary:
	var state: Dictionary = sim.state.digital
	if operation == "inspect":
		var options: Array = []
		for id in sim.catalog.digital_operations:
			var approaches: Array = []
			for approach in ["careful","balanced","fast"]: approaches.append(preview(str(id),approach).data)
			options.append({"id":id,"label":sim.catalog.digital_operations[id].label,"approaches":approaches})
		return Rules.ok({"operations":options,"pending":state.pending.duplicate(true),"trace":state.trace})
	if operation == "cancel":
		if state.pending.is_empty(): return Rules.fail("no_digital_report")
		state.pending = {}
		return Rules.ok()
	var id := str(args.get("id", ""))
	var reason := blocked(id)
	if not reason.is_empty(): return Rules.fail(reason)
	var spec := definition("digital_operations", id)
	if operation == "scan":
		if not state.pending.is_empty(): return Rules.fail("finish_digital_report")
		if float(sim.state.player.needs.energy) < 3: return Rules.fail("insufficient_energy")
		sim.services.character.adjust_need("energy", -3)
		var result: Dictionary = sim.advance(15)
		if not result.ok: return result
		state.serial += 1
		state.pending = {"id":id,"token":state.serial,"expires":int(sim.state.clock.total_minutes)+1440}
		return Rules.ok({"token":state.serial})
	if operation != "resolve": return Rules.fail("unknown_operation")
	if state.pending.is_empty() or state.pending.id != id or not CHECK.number(args.get("token")) or int(args.token) != float(args.token) or int(args.token) != int(state.pending.token): return Rules.fail("stale_digital_report")
	if int(state.pending.expires) <= int(sim.state.clock.total_minutes): return Rules.fail("stale_digital_report")
	var forecast := preview(id,str(args.get("approach","balanced")))
	if not forecast.ok: return forecast
	var plan: Dictionary = forecast.data
	var cost := float(plan.minutes) / 10.0
	if float(sim.state.player.needs.energy) < cost: return Rules.fail("insufficient_energy")
	var chance := float(plan.chance)
	var roll: float = sim.rng.randf()
	var success: bool = roll < chance
	var partial: bool = not success and bool(plan.partial_possible) and roll < minf(1.0,chance+0.15)
	var reward := int(plan.reward) if success else floori(float(plan.reward)*0.25) if partial else 0
	sim.services.character.adjust_need("energy", -cost)
	state.pending = {}
	var result: Dictionary = sim.advance(int(plan.minutes))
	if not result.ok: return result
	state.cooldowns[id] = int(sim.state.clock.total_minutes) + int(spec.cooldown)
	if success:
		sim.state.world.flags.digital_job_completed = true
		if spec.outcome == "grades": sim.state.world.education.grade += 3
		if spec.outcome == "directory":
			var candidates: Array = sim.state.social.npcs.keys()
			candidates.sort()
			for npc_id in candidates:
				if not npc_id in state.leads and not npc_id in sim.state.social.contacts:
					state.leads.append(npc_id)
					break
	sim.state.economy.cash += reward
	if float(spec.risk) > 0:
		state.trace = minf(100, float(state.trace) + float(spec.risk) * float(plan.trace_scale) * (0.4 if success else 1.0))
		if not success:
			sim.state.security.fine += int(spec.risk) * 2
			sim.state.world.heat = minf(100, float(sim.state.world.heat) + float(spec.risk))
	var trained: Dictionary = sim.services.character.execute("train", {"skill":"cybersecurity", "xp":8 if success else 3})
	if not trained.ok: return trained
	state.history.append({"id":id,"success":success,"minute":sim.state.clock.total_minutes,"reward":reward,"approach":plan.approach,"partial":partial})
	while state.history.size() > 32: state.history.pop_front()
	emit_event("digital_completed", {"id":id,"success":success})
	return Rules.ok({"success":success,"partial":partial,"chance":chance,"reward":reward,"approach":plan.approach,"description":"Задача выполнена. Результат и оплата получены." if success else "Восстановлена часть результата; выплачено 25% вознаграждения." if partial else "Попытка не удалась. Получен опыт; отчёт объясняет риск следующей попытки."})

func tick(minute: int) -> void:
	if minute % 60 == 0: sim.state.digital.trace = snappedf(maxf(0, float(sim.state.digital.trace) - 0.5), 0.001)
	if not sim.state.digital.pending.is_empty() and minute >= int(sim.state.digital.pending.expires): sim.state.digital.pending = {}

static func state_error(state: Dictionary, catalog: Dictionary) -> String:
	var d: Variant = state.get("digital")
	if not CHECK.fields(d, {"serial":"n", "pending":"d", "cooldowns":"d", "trace":"n", "history":"a", "leads":"a"}): return "invalid_digital_state"
	if float(d.serial) < 0 or int(d.serial) != float(d.serial) or float(d.trace) < 0 or float(d.trace) > 100 or d.history.size() > 32: return "invalid_digital_state"
	for id in d.cooldowns:
		if not catalog.digital_operations.has(id) or not CHECK.number(d.cooldowns[id]) or float(d.cooldowns[id]) < 0 or int(d.cooldowns[id]) != float(d.cooldowns[id]): return "invalid_digital_cooldown"
	var seen: Array = []
	for id in d.leads:
		if not id is String or not state.social.npcs.has(id) or id in seen: return "invalid_digital_lead"
		seen.append(id)
	if not d.pending.is_empty():
		if not CHECK.fields(d.pending, {"id":"s", "token":"n", "expires":"n"}): return "invalid_digital_report"
		if not catalog.digital_operations.has(d.pending.id) or d.pending.token != d.serial or float(d.pending.expires) <= float(state.clock.total_minutes) or int(d.pending.expires) != float(d.pending.expires): return "invalid_digital_report"
	for entry in d.history:
		if not CHECK.fields(entry, {"id":"s", "success":"b", "minute":"n", "reward":"n"}): return "invalid_digital_history"
		if not catalog.digital_operations.has(entry.id) or float(entry.minute) < 0 or float(entry.minute) > float(state.clock.total_minutes) or float(entry.reward) < 0: return "invalid_digital_history"
	return ""
