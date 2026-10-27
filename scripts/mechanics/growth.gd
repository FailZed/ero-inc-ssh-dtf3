extends "res://scripts/mechanics/core/module.gd"
const V = preload("res://scripts/mechanics/core/agency_validation.gd")
const NEED_IDS := ["hydration","satiety","hygiene","bladder","rested","fun","social"]
const HOME := ["bedroom","bathroom","kitchen","apartment_hall"]

static func defaults() -> Dictionary:
	return {"version":1,"need_overrides":{},"habits":{},"practice_counts":{}}

func initialize() -> void:
	if not sim.state.has("growth"): sim.state.growth = defaults()
	if not sim.state.player.has("need_warnings"): sim.state.player.need_warnings = {}
	for id in NEED_IDS:
		if not enabled(id):
			sim.state.player.needs[id] = 100.0
			sim.state.player.need_warnings[id] = false

func rules() -> Dictionary:
	return sim.catalog.growth_rules

func enabled(id: String) -> bool:
	if not id in NEED_IDS: return true
	if sim.state.growth.need_overrides.has(id): return bool(sim.state.growth.need_overrides[id])
	return bool(sim.services.preferences.rule("satiety_enabled",true)) if id == "satiety" else true

func decay_factor(id: String) -> float:
	return 1.0-0.12*int(sim.state.growth.habits.get(id,0))

func penalty_factor(id: String) -> float:
	return 1.0-0.15*int(sim.state.growth.habits.get(id,0))

func level(id: String) -> int:
	return clampi(int(sqrt(maxf(0,float(sim.state.player.skills.get(id,0)))/10.0)),0,10)

func job_skill(id: String) -> String:
	return str(sim.catalog.livelihood_rules.jobs[id].skill)

func policy() -> Dictionary:
	var difficulty := str(sim.state.preferences.difficulty)
	var result: Dictionary = rules().profiles.get(difficulty,rules().profiles.normal).duplicate(true)
	if difficulty == "custom":
		result.floor = float(sim.services.preferences.rule("minigame_floor",0.70))
		result.help_cap = float(sim.services.preferences.rule("skill_help_cap",0.28))
	return result

func _help(skill: String, secondary: String = "discipline") -> float:
	var p := policy()
	var score := 0.75*float(sim.state.player.skills.get(skill,0))+0.25*float(sim.state.player.skills.get(secondary,0))
	var mastery := clampf(sqrt(maxf(0,score)/1000.0),0,1)
	return minf(float(p.help_cap),1.0-float(p.floor))*mastery

func work_assistance(id: String) -> Dictionary:
	var p := policy()
	var skill := job_skill(id)
	var help := _help(skill,"logic" if sim.catalog.livelihood_rules.jobs[id].kind == "sorting" else "discipline")
	var kind: String = sim.catalog.livelihood_rules.jobs[id].kind
	var time_scale := 1.5 if kind in ["sequence","reasoning"] else 1.0
	return {"skill":skill,"help":help,"rounds":maxi(ceili(5*float(p.floor)),5-roundi(5*help)) if kind == "memory" else 5,"duration_ms":mini(60000,roundi(float(p.work_ms)*(1+help)*time_scale)),"round_ms":roundi(float(p.round_ms)*(1+help)),"window":minf(0.23,float(p.focus)*(1+2*help))}

func game_assistance(type: String) -> Dictionary:
	var skill: String = {"blackjack":"cards","guess":"logic","lockpick":"stealth","reaction":"athletics","timing":"performance","strength":"fitness","pushups":"fitness"}.get(type,"logic")
	var help := _help(skill,"handiness" if type == "lockpick" else "logic")
	var p := policy()
	return {"skill":skill,"help":help,"window":minf(0.24,0.12*float(p.game_factor)*(1+2*help)),"time_factor":float(p.game_factor)*(1+help),"extra_attempts":floori(help*10)}

func work_care() -> void:
	if not sim.action_context.get("auto_work",false): return
	for id in rules().work_care:
		if not enabled(id): continue
		var current := float(sim.state.player.needs[id])
		var target := float(rules().work_care[id])
		if current < target: sim.services.character.adjust_need(id,minf(target-current,0.35 if id == "social" else 1.0))

func practice_blocked(id: String) -> String:
	var spec: Dictionary = sim.catalog.skills.get(id,{})
	if not spec.has("practice"): return "unknown_practice"
	var location := str(sim.state.world.location)
	var home_match: bool = "bedroom" in spec.locations and location in HOME
	if not location in spec.locations and not home_match: return "practice_location"
	if spec.has("tool") and not spec.tool in sim.state.world.equipment and int(sim.state.inventory.items.get(spec.tool,0)) < 1: return "missing_work_equipment"
	if float(sim.state.player.needs.energy) < float(spec.energy)*sim.multiplier("resource_cost"): return "insufficient_energy"
	if int(sim.state.economy.cash) < int(spec.cost): return "insufficient_funds"
	if int(sim.state.growth.practice_counts.get("%d:%s" % [int(sim.state.clock.day_index),id],0)) >= 4: return "practice_daily_limit"
	return ""

func habit_blocked(id: String) -> String:
	if not rules().habits.has(id): return "unknown_need"
	var rank := int(sim.state.growth.habits.get(id,0))
	if rank >= 3: return "habit_max"
	var mastery := 0
	for skill in rules().habits[id].skills: mastery = maxi(mastery,int(sim.state.player.skills.get(skill,0)))
	if mastery < int(rules().habit_thresholds[rank]): return "habit_practice_required"
	if int(sim.state.player.points) < rank+1: return "no_points_or_unknown_stat"
	return ""

func execute(operation: String, args: Dictionary) -> Dictionary:
	var id := str(args.get("id",""))
	if operation == "need_toggle":
		if not id in NEED_IDS or not args.get("enabled") is bool: return Rules.fail("invalid_need_setting")
		sim.state.growth.need_overrides[id] = bool(args.enabled)
		if not args.enabled:
			sim.state.player.needs[id] = 100.0
			sim.state.player.need_warnings[id] = false
		return Rules.ok()
	if operation == "habit":
		var reason := habit_blocked(id)
		if not reason.is_empty(): return Rules.fail(reason)
		var rank := int(sim.state.growth.habits.get(id,0))
		sim.state.player.points -= rank+1
		sim.state.growth.habits[id] = rank+1
		return Rules.ok()
	if operation != "practice": return Rules.fail("unknown_operation")
	var reason := practice_blocked(id)
	if not reason.is_empty(): return Rules.fail(reason)
	var spec: Dictionary = sim.catalog.skills[id]
	var key := "%d:%s" % [int(sim.state.clock.day_index),id]
	sim.state.growth.practice_counts[key] = int(sim.state.growth.practice_counts.get(key,0))+1
	sim.state.economy.cash -= int(spec.cost)
	sim.services.character.adjust_need("energy",-float(spec.energy)*sim.multiplier("resource_cost"))
	var advanced: Dictionary = sim.advance(int(spec.minutes))
	if not advanced.ok: return advanced
	if spec.category == "creative": sim.services.character.adjust_need("fun",8)
	return sim.services.character.execute("train",{"skill":id,"xp":int(spec.xp)})

func observe(module_id: String, operation: String, before: Dictionary) -> void:
	if module_id == "encounters" and operation == "game_input" and before.encounters.game.get("status","") == "active" and sim.state.encounters.game.get("status","") != "active":
		var type := str(sim.state.encounters.game.type)
		var skill := str(game_assistance(type).skill)
		sim.services.character.execute("train",{"skill":skill,"xp":2 if sim.state.encounters.game.status == "won" else 1})

func tick(minute: int) -> void:
	if minute % 1440 != 0: return
	for key in sim.state.growth.practice_counts.keys():
		if int(str(key).get_slice(":",0)) < int(sim.state.clock.day_index)-7: sim.state.growth.practice_counts.erase(key)

static func catalog_error(catalog: Dictionary) -> String:
	var rules: Variant = catalog.get("growth_rules")
	if not V.shape(rules,{"profiles":"d","habits":"d","habit_thresholds":"a","work_care":"d"}) or rules.habit_thresholds.size() != 3: return "invalid_growth_catalog"
	for index in range(3):
		if not V.integer(rules.habit_thresholds[index],1,1000) or int(rules.habit_thresholds[index]) != [10,50,150][index]: return "invalid_growth_catalog"
	for id in ["easy","normal","hard"]:
		var p: Variant = rules.profiles.get(id)
		if not V.shape(p,{"floor":"n","help_cap":"n","work_ms":"n","focus":"n","round_ms":"n","game_factor":"n"}): return "invalid_assistance_profile"
		if not V.number(p.floor,0.55,0.90) or not V.number(p.help_cap,0,0.40) or not V.integer(p.work_ms,1000,60000) or not V.number(p.focus,0.05,0.23) or not V.integer(p.round_ms,1000,10000): return "invalid_assistance_profile"
	for id in catalog.skills:
		var spec: Variant = catalog.skills[id]
		if not V.shape(spec,{"label":"s","category":"s","practice":"s","locations":"a","minutes":"n","energy":"n","cost":"n","xp":"n"}) or spec.locations.is_empty(): return "invalid_skill_practice"
		if not V.integer(spec.minutes,10,120) or not V.number(spec.energy,1,50) or not V.integer(spec.cost,0,100) or not V.integer(spec.xp,1,50): return "invalid_skill_practice"
		for location in spec.locations:
			if not catalog.locations.has(location): return "invalid_practice_location"
	for id in NEED_IDS:
		var habit: Variant = rules.habits.get(id)
		if not V.shape(habit,{"label":"s","skills":"a"}) or habit.skills.is_empty(): return "invalid_habit_catalog"
		for skill in habit.skills:
			if not catalog.skills.has(skill): return "invalid_habit_catalog"
	for id in rules.work_care:
		if not id in NEED_IDS or not V.number(rules.work_care[id],1,100): return "invalid_work_care"
	return ""

static func state_error(state: Dictionary) -> String:
	var g: Variant = state.get("growth")
	if not V.shape(g,{"version":"n","need_overrides":"d","habits":"d","practice_counts":"d"}) or g.version != 1: return "invalid_growth_state"
	for id in g.need_overrides:
		if not id in NEED_IDS or not g.need_overrides[id] is bool: return "invalid_need_setting"
		if not g.need_overrides[id] and float(state.player.needs[id]) != 100: return "invalid_disabled_need"
	for id in g.habits:
		if not id in NEED_IDS or not V.integer(g.habits[id],1,3): return "invalid_habit"
	for key in g.practice_counts:
		if not key is String or not V.integer(g.practice_counts[key],0,4): return "invalid_practice_count"
	var work: Dictionary = state.livelihood.pending
	if not work.is_empty():
		if not work.has("assistance"): return "missing_work_assistance"
		var a: Variant = work.assistance
		if not V.shape(a,{"skill":"s","help":"n","rounds":"n","duration_ms":"n","round_ms":"n","window":"n"}): return "invalid_work_assistance"
		if not V.integer(a.rounds,3,5) or not V.integer(a.duration_ms,1000,60000) or not V.integer(a.round_ms,1000,10000) or not V.number(a.window,0.05,0.24) or not V.number(a.help,0,0.45): return "invalid_work_assistance"
	var game: Dictionary = state.encounters.game
	if not game.is_empty() and game.status == "active":
		var a: Variant = game.get("assistance")
		if not V.shape(a,{"skill":"s","help":"n","window":"n","time_factor":"n","extra_attempts":"n"}) or not V.number(a.help,0,0.45) or not V.number(a.window,0.05,0.24): return "invalid_game_assistance"
	return ""
