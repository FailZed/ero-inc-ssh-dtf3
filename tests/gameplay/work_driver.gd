extends RefCounted

static func answer(sim, wrong: bool = false) -> Dictionary:
	var p: Dictionary = sim.state.livelihood.pending
	if p.preview: return {"token":p.token,"round":p.round,"action":"ready"}
	var task: Dictionary = p.tasks[int(p.round)]
	var kind: String = sim.catalog.livelihood_rules.jobs[p.id].kind
	var args := {"token":p.token,"round":int(p.round),"elapsed_ms":int(p.last)+300}
	if kind == "focus":
		var elapsed := roundi(float(task.target)*1500.0)
		if wrong: elapsed = roundi(fposmod(float(task.target)+0.5,1.0)*1500.0)
		while elapsed < int(p.last)+200: elapsed += 1500
		args.elapsed_ms = elapsed
	elif kind == "sequence":
		var index: int = p.selection.size()
		if wrong and index < 2: index = 1-index
		args.choice = int(task.order[index])
	else:
		args.choice = int(task.answer)
		if wrong:
			var count: int = 9 if kind == "comparison" else 4 if kind == "reasoning" else sim.catalog.livelihood_rules.jobs[p.id].choices.size()
			for choice in range(count):
				if choice != int(task.answer) and choice != int(task.get("excluded",-1)): args.choice = choice; break
	return args

static func finish(sim, wrong: bool = false) -> bool:
	for step in range(30):
		if sim.state.livelihood.pending.is_empty(): return true
		if not sim.command("livelihood","input",answer(sim,wrong)).ok: return false
	return false
