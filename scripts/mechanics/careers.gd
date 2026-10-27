extends "res://scripts/mechanics/core/module.gd"
const Formulas = preload("res://scripts/mechanics/core/formulas.gd")

func execute(operation: String, args: Dictionary) -> Dictionary:
	var id := str(args.get("id", ""))
	match operation:
		"take_contract":
			var spec := definition("contracts", id)
			if spec.is_empty() or sim.state.careers.contracts.has(id): return Rules.fail("contract_unavailable")
			if not Rules.check(sim.state, spec.get("requirements", {})): return Rules.fail("contract_requirements")
			if int(sim.state.careers.professions.get(str(spec.get("profession", "digital")), {}).get("level", 1)) < int(spec.get("level", 1)): return Rules.fail("profession_level")
			sim.state.careers.contracts[id] = {"progress": 0.0, "quality": 0.0, "status": "active", "claimed": false,
				"deadline": int(sim.state.clock.total_minutes) + int(spec.get("deadline", 2880))}
		"work_contract": return _work_contract(id, int(args.get("minutes", 60)))
		"claim_contract":
			if not sim.state.careers.contracts.has(id): return Rules.fail("unknown_contract")
			var contract: Dictionary = sim.state.careers.contracts[id]
			if contract.status != "completed" or contract.claimed: return Rules.fail("contract_reward_unavailable")
			var spec := definition("contracts", id)
			var pay := int(spec.get("pay", 0) * (0.75 + float(contract.quality) * 0.005))
			sim.state.economy.cash += pay
			contract.claimed = true
			_promote(str(spec.get("profession", "digital")), int(spec.get("xp", 20)))
			return Rules.ok({"pay": pay, "quality": contract.quality})
		"shift": return _shift(id)
		"stream": return _stream(id, int(args.get("minutes", 60)))
		"investigate", "interview", "verify", "publish": return _publication(operation, id, args)
		_: return Rules.fail("unknown_operation")
	return Rules.ok()

func _work_contract(id: String, minutes: int) -> Dictionary:
	if not sim.state.careers.contracts.has(id): return Rules.fail("unknown_contract")
	var contract: Dictionary = sim.state.careers.contracts[id]
	var spec := definition("contracts", id)
	if contract.status != "active": return Rules.fail("contract_not_active")
	if minutes < 1 or minutes > 240: return Rules.fail("invalid_work_duration")
	for equipment in spec.get("equipment", []):
		if not equipment in sim.state.world.equipment: return Rules.fail("missing_work_equipment")
	var skill_id := str(spec.get("skill", "computing"))
	var spent := 0
	while spent < minutes and contract.status == "active":
		if int(sim.state.clock.total_minutes) + 1 > int(contract.deadline): return Rules.fail("contract_deadline_would_expire")
		var energy: float = 0.15 * sim.multiplier("resource_cost")
		if sim.state.player.needs.energy < energy: return Rules.fail("insufficient_energy")
		var mastery := Formulas.mastery(float(sim.state.player.skills.get(skill_id, 0)), float(definition("balance_rules", "career").get("skill_scale", 200)))
		var rate: float = 0.75 + mastery * 1.25 + sim.services.character.effective_stat("intellect") / 100.0
		sim.services.character.adjust_need("energy", -energy)
		contract.progress = minf(float(spec.get("effort", 120)), float(contract.progress) + rate)
		contract.quality = clampf(40.0 + mastery * 50.0 + sim.services.character.effective_stat("intellect"), 0, 100)
		if float(contract.progress) >= float(spec.get("effort", 120)): contract.status = "completed"
		var result: Dictionary = sim.advance(1)
		if not result.ok: return result
		_train_minutes(skill_id)
		spent += 1
	if contract.status == "failed": return Rules.fail("contract_deadline_would_expire")
	return Rules.ok({"status": contract.status, "progress": contract.progress, "spent_minutes": spent})

func _shift(id: String) -> Dictionary:
	var spec := definition("professions", id)
	if spec.is_empty() or not sim.services.world.is_open(spec): return Rules.fail("shift_unavailable")
	if spec.has("location") and spec.location != sim.state.world.location: return Rules.fail("wrong_workplace")
	var key := "%s:%d" % [id, sim.state.clock.day_index]
	if int(sim.state.careers.workdays.get(key, 0)) >= int(spec.get("daily_limit", 1)): return Rules.fail("shift_daily_limit")
	var energy: float = float(spec.get("energy", 20)) * sim.multiplier("resource_cost")
	if sim.state.player.needs.energy < energy: return Rules.fail("insufficient_energy")
	var level := int(sim.state.careers.professions.get(id, {}).get("level", 1))
	sim.services.character.adjust_need("energy", -energy)
	sim.state.economy.cash += int(round(float(spec.get("pay", 50)) * Formulas.career_pay(level, definition("balance_rules", "career"))))
	sim.state.careers.workdays[key] = int(sim.state.careers.workdays.get(key, 0)) + 1
	_promote(id, int(spec.get("xp", 20)))
	return sim.advance(int(spec.get("minutes", 120)))

func _promote(id: String, xp: int) -> void:
	var career: Dictionary = sim.state.careers.professions.get(id, {"level": 1, "xp": 0, "reputation": 0})
	career.xp += xp
	while int(career.xp) >= int(career.level) * 50:
		career.xp -= int(career.level) * 50
		career.level += 1
		emit_event("profession_promoted", {"id": id, "level": career.level})
	sim.state.careers.professions[id] = career

func _train_minutes(skill: String) -> void:
	var key := "skill_time:" + skill
	var accumulated := int(sim.state.counters.get(key, 0)) + 1
	sim.state.counters[key] = accumulated % 10
	if accumulated >= 10: sim.services.character.execute("train", {"skill": skill, "xp": 1})

func _stream(id: String, minutes: int) -> Dictionary:
	var topic := definition("stream_topics", id)
	if topic.is_empty() or minutes < 15 or minutes > 240: return Rules.fail("invalid_stream")
	if not "computer" in sim.state.world.equipment: return Rules.fail("missing_computer")
	var key := "stream:%d" % sim.state.clock.day_index
	var rules := definition("balance_rules", "career")
	var limit := int(rules.get("stream_daily_minutes", 360))
	var ending_day: int = sim.calendar.snapshot(int(sim.state.clock.total_minutes) + minutes - 1).day_index
	var today: int = mini(minutes, 1440 - int(sim.state.clock.minute_of_day))
	if int(sim.state.careers.workdays.get(key, 0)) + today > limit: return Rules.fail("stream_daily_limit")
	if ending_day != int(sim.state.clock.day_index) and int(sim.state.careers.workdays.get("stream:%d" % ending_day, 0)) + minutes - today > limit: return Rules.fail("stream_daily_limit")
	var energy: float = minutes * float(rules.get("stream_energy_per_minute", 0.12)) * sim.multiplier("resource_cost")
	if sim.state.player.needs.energy < energy: return Rules.fail("insufficient_energy")
	var channel: Dictionary = sim.state.economy.channel
	var old_followers := int(channel.followers)
	var earned := 0
	var started := int(sim.state.clock.total_minutes)
	var exposure := 0.0
	var quality := 0.0
	var skill_id := str(topic.get("skill", "computing"))
	for elapsed in range(minutes):
		sim.services.character.adjust_need("energy", -float(rules.get("stream_energy_per_minute", 0.12)) * sim.multiplier("resource_cost"))
		var minute_key := "stream:%d" % int(sim.state.clock.day_index)
		sim.state.careers.workdays[minute_key] = int(sim.state.careers.workdays.get(minute_key, 0)) + 1
		var mastery := Formulas.mastery(float(sim.state.player.skills.get(skill_id, 0)), float(rules.get("skill_scale", 200)))
		quality = clampf(20.0 + mastery * 50.0 + sim.services.character.effective_stat("charisma") * 2.0, 0, 100)
		var audience := (quality + sqrt(float(channel.followers)) * float(rules.get("audience_followers_scale", 4))) / 60.0
		exposure += audience
		var growth := float(channel.get("growth_credit", 0)) + audience * float(topic.get("growth", 0.05))
		channel.followers += int(floor(growth))
		channel.growth_credit = growth - floor(growth)
		var income := float(channel.get("income_credit", 0)) + audience * float(topic.get("monetization", 0.2))
		sim.state.economy.cash += int(floor(income))
		earned += int(floor(income))
		channel.income_credit = income - floor(income)
		var result: Dictionary = sim.advance(1)
		if not result.ok: return result
		_train_minutes(skill_id)
	sim.state.careers.streams.append({"topic": id, "minute": started, "audience": int(round(exposure)), "income": earned, "quality": quality})
	while sim.state.careers.streams.size() > 64: sim.state.careers.streams.pop_front()
	return Rules.ok({"followers": int(channel.followers) - old_followers, "income": earned, "quality": quality})

func publication_capacity() -> int:
	var level := int(sim.state.careers.professions.get("journalism", {}).get("level", 1))
	var slots := 0
	for threshold in definition("professions", "journalism").get("publication_slots_at", [0, 3, 8, 15, 30]):
		if level >= int(threshold): slots += 1
	return maxi(1, slots)

func _publication(operation: String, id: String, args: Dictionary) -> Dictionary:
	var spec := definition("publications", id)
	if spec.is_empty(): return Rules.fail("unknown_publication")
	if operation == "investigate":
		if sim.state.careers.publications.has(id): return Rules.fail("publication_already_started")
		var active := 0
		for article in sim.state.careers.publications.values():
			if not article.published: active += 1
		if active >= publication_capacity(): return Rules.fail("publication_capacity")
		sim.state.careers.publications[id] = {"research": 1, "interviewed": [], "verified": false, "published": false, "quality": 0.0}
		return sim.advance(30)
	if not sim.state.careers.publications.has(id): return Rules.fail("publication_not_started")
	var article: Dictionary = sim.state.careers.publications[id]
	if article.published: return Rules.fail("publication_already_published")
	match operation:
		"interview":
			var npc := str(args.get("npc", ""))
			if not sim.state.social.npcs.has(npc) or npc in article.interviewed: return Rules.fail("invalid_interview")
			if sim.state.social.npcs[npc].location != sim.state.world.location: return Rules.fail("npc_not_present")
			article.interviewed.append(npc)
			article.research += 1
		"verify":
			if article.research < int(spec.get("sources", 2)): return Rules.fail("insufficient_sources")
			article.verified = true
			article.quality = minf(100.0, 40.0 + article.research * 10.0 + sim.state.player.skills.get("journalism", 0) * 0.2)
		"publish":
			if not article.verified: return Rules.fail("publication_not_verified")
			article.published = true
			sim.state.economy.cash += int(spec.get("pay", 30) * float(article.quality) / 100.0)
			_promote("journalism", int(spec.get("xp", 20)))
			emit_event("article_published", {"id": id, "quality": article.quality})
			return sim.services.character.execute("train", {"skill": "journalism", "xp": int(spec.get("xp", 20))})
	return sim.advance(20)

func tick(minute: int) -> void:
	for id in sim.state.careers.contracts:
		var contract: Dictionary = sim.state.careers.contracts[id]
		if contract.status == "active" and minute >= int(contract.deadline):
			contract.status = "failed"
			emit_event("contract_expired", {"id": id})
