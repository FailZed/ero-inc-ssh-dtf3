extends RefCounted
const V = preload("res://scripts/mechanics/core/agency_validation.gd")
const Challenges = preload("res://scripts/mechanics/work_challenges.gd")

static func integer(value: Variant, low: int = 0, high: int = 2147483647) -> bool:
	return V.integer(value,low,high)

static func catalog_error(catalog: Dictionary) -> String:
	var rules: Variant = catalog.get("livelihood_rules")
	if not V.shape(rules,{"jobs":"d","orders":"d","upgrades":"d","aspirations":"d","promotion":"d","profession_skills":"d"}): return "invalid_livelihood_catalog"
	for id in catalog.professions:
		if not catalog.skills.has(rules.profession_skills.get(id,"")): return "invalid_profession_skill"
	if not V.shape(rules.promotion,{"skill_levels":"a","experience":"a","quality_bonus":"n"}) or rules.promotion.skill_levels.size() != 5 or rules.promotion.experience.size() != 5 or not integer(rules.promotion.quality_bonus,0,50): return "invalid_promotion_rules"
	for index in range(5):
		if not integer(rules.promotion.skill_levels[index],0,10) or not integer(rules.promotion.experience[index],0,600): return "invalid_promotion_rules"
		if index > 0 and (rules.promotion.skill_levels[index] <= rules.promotion.skill_levels[index-1] or rules.promotion.experience[index] <= rules.promotion.experience[index-1]): return "invalid_promotion_rules"
	for job in rules.jobs.values():
		if not V.shape(job,{"title":"s","description":"s","location":"s","hours":"a","minutes":"n","energy":"n","pay":"n","career":"s","skill":"s","kind":"s","min_skill":"n","risk":"n"}): return "invalid_livelihood_job"
		if not catalog.locations.has(job.location) or not catalog.skills.has(job.skill) or not job.kind in Challenges.KINDS+["shift"]: return "invalid_livelihood_job"
		if not integer(job.minutes,15,480) or not V.number(job.energy,1,100) or not integer(job.pay,1,1000) or not integer(job.min_skill,0,10) or not V.number(job.risk,0,0.9): return "invalid_livelihood_job"
		if job.hours.size() != 2 or not integer(job.hours[0],0,1439) or not integer(job.hours[1],1,1440) or int(job.hours[1])-int(job.hours[0]) < int(job.minutes): return "invalid_livelihood_hours"
		var task_error := Challenges.catalog_error(job)
		if not task_error.is_empty(): return task_error
	for order in rules.orders.values():
		if not V.shape(order,{"title":"s","item":"s","quantity":"n","pay":"n"}) or not catalog.items.has(order.item) or not integer(order.quantity,1,10) or not integer(order.pay,1,1000): return "invalid_livelihood_order"
	for upgrade in rules.upgrades.values():
		if not V.shape(upgrade,{"title":"s","description":"s","price":"n","max_level":"n"}) or not integer(upgrade.price,1,10000) or not integer(upgrade.max_level,1,5): return "invalid_livelihood_upgrade"
	for goal in rules.aspirations.values():
		if not V.shape(goal,{"title":"s","description":"s","metric":"s","count":"n","xp":"n"}) or not goal.metric in ["shifts","earnings","good_games","illicit","deliveries","upgrades"] or not integer(goal.count,1,10000) or not integer(goal.xp,1,1000): return "invalid_life_goal"
	return ""

static func state_error(state: Dictionary, catalog: Dictionary) -> String:
	var s: Variant = state.get("livelihood")
	if not V.shape(s,{"version":"n","careers":"d","workdays":"d","pending":"d","serial":"n","orders":"d","goals":"d","active_goal":"s","upgrades":"d","totals":"d","streak":"n","streak_day":"n","log":"a"}) or s.version != 2: return "invalid_livelihood_state"
	if not integer(s.serial,1) or not integer(s.streak,0,7) or not integer(s.streak_day,-1,int(state.clock.day_index)) or s.log.size() > 64: return "invalid_livelihood_state"
	var rules: Dictionary = catalog.livelihood_rules
	for id in state.careers.professions:
		if not rules.profession_skills.has(id) or not V.shape(state.careers.professions[id],{"level":"n","xp":"n","reputation":"n"}): return "invalid_skill_profession"
		var skill: String = rules.profession_skills[id]
		var level := clampi(int(sqrt(maxf(0,float(state.player.skills.get(skill,0)))/10.0)),0,10)
		var rank := 1
		for threshold in rules.promotion.skill_levels.slice(1):
			if level >= int(threshold): rank += 1
		if state.careers.professions[id].level != rank or state.careers.professions[id].xp != 0: return "invalid_skill_profession"
	for key in ["shifts","earnings","good_games","illicit","deliveries","upgrades"]:
		if not integer(s.totals.get(key)): return "invalid_work_totals"
	for id in s.careers:
		if not rules.jobs.has(id) or rules.jobs[id].kind == "shift" or not V.shape(s.careers[id],{"xp":"n"}) or s.careers[id].size() != 1 or not integer(s.careers[id].xp,0,600): return "invalid_work_career"
	for key in s.workdays:
		if not key is String or not integer(s.workdays[key],0,600): return "invalid_workdays"
	for home in s.upgrades:
		if not catalog.properties.has(home) or not s.upgrades[home] is Dictionary: return "invalid_home_upgrades"
		for id in s.upgrades[home]:
			if not rules.upgrades.has(id) or not integer(s.upgrades[home][id],1,int(rules.upgrades[id].max_level)): return "invalid_home_upgrades"
	for id in s.goals:
		if not rules.aspirations.has(id) or not V.shape(s.goals[id],{"baseline":"n","claimed":"b"}) or not integer(s.goals[id].baseline,0,int(s.totals[rules.aspirations[id].metric])): return "invalid_life_goal_progress"
	if not s.active_goal.is_empty() and (not s.goals.has(s.active_goal) or s.goals[s.active_goal].claimed): return "invalid_active_life_goal"
	var active_orders := 0
	for id in s.orders:
		var order: Variant = s.orders[id]
		if not V.shape(order,{"id":"s","type":"s","title":"s","item":"s","quantity":"n","pay":"n","deadline":"n","status":"s"}) or id != order.id or not rules.orders.has(order.type): return "invalid_local_order"
		var spec: Dictionary = rules.orders[order.type]
		for key in ["title","item","quantity","pay"]:
			if order[key] != spec[key]: return "invalid_local_order"
		if not integer(order.deadline,0) or not order.status in ["active","expired","completed"]: return "invalid_local_order"
		if order.status == "active":
			active_orders += 1
			if int(order.deadline) <= int(state.clock.total_minutes): return "invalid_local_order"
	if active_orders > 2: return "invalid_local_order"
	var p: Dictionary = s.pending
	if not p.is_empty():
		if not V.shape(p,{"id":"s","token":"s","started":"n","round":"n","correct":"n","elapsed":"n","last":"n","preview":"b","tasks":"a","selection":"a","interactive":"b"}) or not p.interactive or not rules.jobs.has(p.id): return "invalid_work_session"
		if rules.jobs[p.id].kind == "shift" or p.token != "work_%d" % (int(s.serial)-1): return "invalid_work_session"
		if not integer(p.get("missed_classes"),0,30): return "invalid_work_session"
		if not integer(p.started,0,int(state.clock.total_minutes)) or int(state.clock.total_minutes)-int(p.started) != int(rules.jobs[p.id].minutes): return "invalid_work_session_time"
		var assist: Variant = p.get("assistance")
		if not assist is Dictionary: return "invalid_work_assistance"
		if not V.shape(assist,{"rounds":"n","duration_ms":"n"}) or not integer(assist.rounds,3,5) or not integer(assist.duration_ms,1000,60000): return "invalid_work_assistance"
		var rounds := int(assist.rounds)
		if not integer(p.round,0,rounds-1) or not integer(p.correct,0,int(p.round)) or not integer(p.elapsed,0,int(assist.duration_ms)-1) or not integer(p.last,0,int(p.elapsed)): return "invalid_work_session_progress"
		if p.preview and (int(p.round) != 0 or rules.jobs[p.id].kind != "memory"): return "invalid_work_session_progress"
		var task_error := Challenges.state_error(p,rules.jobs[p.id])
		if not task_error.is_empty(): return task_error
	for entry in s.log:
		if not V.shape(entry,{"kind":"s","id":"s","minute":"n","pay":"n"}) or not integer(entry.minute,0,int(state.clock.total_minutes)) or not integer(entry.pay): return "invalid_work_log"
	return ""
