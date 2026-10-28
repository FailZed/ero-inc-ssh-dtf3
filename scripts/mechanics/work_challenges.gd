extends RefCounted
const V = preload("res://scripts/mechanics/core/agency_validation.gd")
const Banks = preload("res://scripts/mechanics/work_task_banks.gd")
const KINDS := ["memory","sorting","focus","reasoning","comparison","sequence"]

static func shuffled(sim, count: int) -> Array:
	var result: Array = range(count)
	for i in range(count-1,0,-1):
		var other: int = sim.rng.randi_range(0,i)
		var saved: int = result[i]
		result[i] = result[other]
		result[other] = saved
	return result

static func build(sim, job: Dictionary, assistance: Dictionary, job_id: String) -> Array:
	var result: Array = []
	var sources := Banks.deal(sim,job_id,int(assistance.rounds)) if job.kind in ["reasoning","sequence"] else []
	for index in range(int(assistance.rounds)):
		match str(job.kind):
			"memory", "sorting": result.append({"answer":sim.rng.randi_range(0,job.choices.size()-1)})
			"focus": result.append({"target":sim.rng.randf_range(0.2,0.8)})
			"comparison":
				var reference: Array = []
				for cell in range(9): reference.append(sim.rng.randi_range(0,3))
				var candidate := reference.duplicate()
				var answer: int = sim.rng.randi_range(0,8)
				candidate[answer] = (int(candidate[answer])+sim.rng.randi_range(1,3))%4
				result.append({"reference":reference,"candidate":candidate,"answer":answer})
			"reasoning":
				var source: Dictionary = sources[index]
				var choices := shuffled(sim,source.options.size())
				var options: Array = []
				for choice in choices: options.append(source.options[int(choice)])
				var answer := choices.find(int(source.answer))
				var excluded := -1
				if float(assistance.help) >= 0.25:
					for choice in choices:
						if int(choice) != answer: excluded = int(choice); break
				result.append({"prompt":source.prompt,"options":options,"answer":answer,"explanation":source.explanation,"excluded":excluded})
			"sequence":
				var source: Dictionary = sources[index]
				var choices := shuffled(sim,source.steps.size())
				var options: Array = []
				var solution: Array = []
				for choice in choices: options.append(source.steps[int(choice)])
				for step in range(source.steps.size()): solution.append(choices.find(step))
				result.append({"prompt":source.prompt,"options":options,"order":solution})
	return result

static func submit(session: Dictionary, job: Dictionary, args: Dictionary) -> Dictionary:
	var task: Dictionary = session.tasks[int(session.round)]
	var result := {"ok":true,"complete":true,"correct":false,"feedback":""}
	var elapsed := int(args.elapsed_ms)
	match str(job.kind):
		"focus":
			var phase := fposmod(float(elapsed)/1500.0,1.0)
			var distance := absf(phase-float(task.target))
			result.correct = minf(distance,1.0-distance) <= float(session.assistance.window)
		"sequence":
			if args.get("action","") == "undo":
				session.selection = session.selection.map(func(value): return int(value))
				if session.selection.is_empty(): return {"ok":false,"error":"nothing_to_undo"}
				session.selection.pop_back()
				result.complete = false
				return result
			session.selection = session.selection.map(func(value): return int(value))
			if not V.integer(args.get("choice"),0,2) or int(args.choice) in session.selection: return {"ok":false,"error":"invalid_work_choice"}
			session.selection.append(int(args.choice))
			result.complete = session.selection.size() == 3
			if result.complete:
				result.correct = true
				for index in range(3):
					if int(session.selection[index]) != int(task.order[index]): result.correct = false
				var solution: Array[String] = []
				for choice in task.order: solution.append(str(task.options[int(choice)]))
				result.feedback = "Порядок: "+" → ".join(solution)
				session.selection.clear()
		_:
			var maximum: int = 8 if job.kind == "comparison" else 3 if job.kind == "reasoning" else job.choices.size()-1
			if not V.integer(args.get("choice"),0,maximum): return {"ok":false,"error":"invalid_work_choice"}
			if job.kind == "reasoning" and int(args.choice) == int(task.excluded): return {"ok":false,"error":"invalid_work_choice"}
			result.correct = int(args.choice) == int(task.answer)
			if job.kind in ["sorting","comparison"] and elapsed-int(session.last) > int(session.assistance.round_ms): result.correct = false
			if job.kind == "reasoning": result.feedback = str(task.explanation)
	return result

static func catalog_error(job: Dictionary, catalog: Dictionary) -> String:
	if job.kind in ["memory","sorting"]:
		if not job.get("choices") is Array or job.choices.size() != (3 if job.kind == "sorting" else 5): return "invalid_work_choices"
		if not _strings(job.choices): return "invalid_work_choices"
	if job.kind in ["reasoning","sequence"]: return Banks.job_error(job,catalog)
	return ""

static func state_error(session: Dictionary, job: Dictionary, catalog: Dictionary, career_rank: int) -> String:
	if not session.get("tasks") is Array or not session.get("selection") is Array or session.tasks.size() != int(session.assistance.rounds): return "invalid_work_tasks"
	if (job.kind != "sequence" and not session.selection.is_empty()) or session.selection.size() > 2: return "invalid_work_selection"
	var selected: Array = []
	for choice in session.selection:
		if not V.integer(choice,0,2) or int(choice) in selected: return "invalid_work_selection"
		selected.append(int(choice))
	var seen_prompts: Array = []
	for task in session.tasks:
		if not task is Dictionary: return "invalid_work_task"
		if job.kind in ["reasoning","sequence"]:
			if not task.get("prompt") is String or task.prompt in seen_prompts: return "invalid_work_task"
			seen_prompts.append(task.prompt)
		match str(job.kind):
			"memory", "sorting":
				if not V.integer(task.get("answer"),0,job.choices.size()-1): return "invalid_work_task"
			"focus":
				if not V.number(task.get("target"),0.2,0.8): return "invalid_work_task"
			"comparison":
				if not V.shape(task,{"reference":"a","candidate":"a","answer":"n"}) or task.reference.size() != 9 or task.candidate.size() != 9 or not V.integer(task.answer,0,8): return "invalid_work_task"
				for index in range(9):
					if not V.integer(task.reference[index],0,3) or not V.integer(task.candidate[index],0,3) or (task.reference[index] != task.candidate[index]) != (index == int(task.answer)): return "invalid_work_task"
			"reasoning":
				if not V.shape(task,{"prompt":"s","options":"a","answer":"n","explanation":"s","excluded":"n"}) or task.options.size() != 4 or not V.integer(task.answer,0,3) or not V.integer(task.excluded,-1,3) or int(task.excluded) == int(task.answer): return "invalid_work_task"
				if not _strings(task.options): return "invalid_work_task"
				var known := false
				for original in Banks.bank(job,catalog,career_rank).tasks:
					if task.prompt == original.prompt and task.explanation == original.explanation and task.options[int(task.answer)] == original.options[int(original.answer)] and _same_options(task.options,original.options): known = true
				if not known: return "invalid_work_task"
			"sequence":
				if not V.shape(task,{"prompt":"s","options":"a","order":"a"}) or task.options.size() != 3 or task.order.size() != 3: return "invalid_work_task"
				if not _strings(task.options): return "invalid_work_task"
				var values: Array = []
				var solution: Array = []
				for choice in task.order:
					if not V.integer(choice,0,2) or int(choice) in values: return "invalid_work_task"
					values.append(int(choice))
					solution.append(task.options[int(choice)])
				var known := false
				for original in Banks.bank(job,catalog,career_rank).tasks:
					if task.prompt == original.prompt and solution == original.steps: known = true
				if not known: return "invalid_work_task"
	return ""

static func _same_options(a: Array, b: Array) -> bool:
	var first := a.duplicate()
	var second := b.duplicate()
	first.sort()
	second.sort()
	return first == second

static func _strings(values: Array) -> bool:
	var seen: Array = []
	for value in values:
		if not value is String or value.is_empty() or value in seen: return false
		seen.append(value)
	return true
