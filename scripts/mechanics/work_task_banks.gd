extends RefCounted
## Tiered authored content. The existing pending session keeps the frozen questions.
const V = preload("res://scripts/mechanics/core/agency_validation.gd")
const Progress = preload("res://scripts/mechanics/core/career_progress.gd")

static func rank(state: Dictionary, catalog: Dictionary, id: String) -> int:
	var rules: Dictionary = catalog.livelihood_rules
	var job: Dictionary = rules.jobs[id]
	return Progress.work_rank(float(state.player.skills.get(job.skill,0)),int(state.livelihood.careers.get(id,{}).get("xp",0)),job.kind=="shift",rules.promotion.skill_levels,rules.promotion.experience)

static func bank(job: Dictionary, catalog: Dictionary, career_rank: int) -> Dictionary:
	var selected: Dictionary = {}
	for candidate in catalog.work_task_banks[job.task_bank]:
		if int(candidate.min_rank)>career_rank: break
		selected = candidate
	return selected

static func info(sim, id: String) -> Dictionary:
	var job: Dictionary = sim.catalog.livelihood_rules.jobs[id]
	if not job.kind in ["reasoning","sequence"]: return {}
	var selected := bank(job,sim.catalog,rank(sim.state,sim.catalog,id))
	return {"id":selected.id,"title":selected.title,"min_rank":selected.min_rank,"count":selected.tasks.size(),"time_factor":selected.time_factor}

static func deal(sim, id: String, count: int) -> Array:
	var job: Dictionary = sim.catalog.livelihood_rules.jobs[id]
	var selected := bank(job,sim.catalog,rank(sim.state,sim.catalog,id))
	var deck: Array = range(selected.tasks.size())
	var order := RandomNumberGenerator.new()
	order.seed = (str(sim._initial_seed)+":"+id+":"+str(selected.id)).hash()
	for index in range(deck.size()-1,0,-1):
		var other := order.randi_range(0,index)
		var saved: int = deck[index]
		deck[index] = deck[other]
		deck[other] = saved
	var day := int(sim.state.clock.day_index)
	var shift := maxi(0,int(sim.state.livelihood.workdays.get("%d:%s" % [day,id],1))-1)
	var offset := posmod(day*3+shift*count,deck.size())
	var result: Array = []
	for index in range(count): result.append(selected.tasks[int(deck[(offset+index)%deck.size()])])
	return result

static func job_error(job: Dictionary, catalog: Dictionary) -> String:
	if job.has("tasks"): return "superseded_work_task_field"
	if not job.get("task_bank") is String or not catalog.get("work_task_banks",{}) is Dictionary or not catalog.work_task_banks.has(job.task_bank): return "missing_work_task_bank"
	var banks: Variant = catalog.work_task_banks[job.task_bank]
	if not banks is Array or banks.is_empty() or banks.size()>5: return "invalid_work_task_banks"
	var ids: Array = []
	var prompts: Array = []
	var last_rank := 0
	for entry in banks:
		if not V.shape(entry,{"id":"s","title":"s","min_rank":"n","time_factor":"n","tasks":"a"}) or entry.id.is_empty() or entry.title.is_empty() or entry.id in ids: return "invalid_work_task_bank"
		if not V.integer(entry.min_rank,1,5) or int(entry.min_rank)<=last_rank or (last_rank==0 and int(entry.min_rank)!=1) or not V.number(entry.time_factor,1,1.4): return "invalid_work_bank_gate"
		ids.append(entry.id)
		last_rank = int(entry.min_rank)
		if entry.tasks.size()<5 or entry.tasks.size()>128: return "invalid_work_bank_size"
		for task in entry.tasks:
			if not V.shape(task,{"prompt":"s"}) or task.prompt.is_empty() or task.prompt.length()>240 or task.prompt in prompts: return "invalid_work_task"
			prompts.append(task.prompt)
			if job.kind=="reasoning":
				if not V.shape(task,{"options":"a","answer":"n","explanation":"s"}) or task.options.size()!=4 or not V.integer(task.answer,0,3) or task.explanation.is_empty(): return "invalid_work_task"
				if not strings(task.options): return "invalid_work_task"
			else:
				if not V.shape(task,{"steps":"a"}) or task.steps.size()!=3 or not strings(task.steps): return "invalid_work_task"
	return ""

static func strings(values: Array) -> bool:
	var seen: Array = []
	for value in values:
		if not value is String or value.is_empty() or value in seen: return false
		seen.append(value)
	return true
