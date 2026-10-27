extends SceneTree
## Headless study, never binds Gameplay or opens/writes player save slots.
const Life = preload("res://scripts/mechanics/npc_life_simulation.gd")
var stories: Array = []
var event_counts: Dictionary = {}
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _command(sim, module_id: String, operation: String, args: Dictionary = {}) -> void:
	var result: Dictionary = sim.command(module_id, operation, args)
	if not result.ok: failures.append("%s.%s: %s" % [module_id, operation, result.get("error", "")])

func _record(event: Dictionary) -> void:
	if event.kind in ["npc_life_milestone", "npc_life_new_aspiration", "npc_life_conflict", "npc_life_social_outcome", "npc_life_career_progress", "npc_life_gossip", "npc_life_claim_made", "npc_life_deception_exposed", "npc_social_outcome", "npc_social_harm", "npc_relationship_formed", "npc_relationship_separated"]:
		event_counts[str(event.kind)] = int(event_counts.get(str(event.kind), 0)) + 1
		stories.append(event.duplicate(true))
		while stories.size() > 120: stories.pop_front()

func _run() -> void:
	var count := 100
	var days := 7
	var report_path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--count="): count = clampi(int(argument.trim_prefix("--count=")), 1, 500)
		if argument.begins_with("--days="): days = clampi(int(argument.trim_prefix("--days=")), 1, 30)
		if argument.begins_with("--report="): report_path = argument.trim_prefix("--report=")
	var sim = Life.new(20261019, {"settings": {"start_minutes": 480}})
	sim.domain_event.connect(_record)
	_command(sim, "npc_agency", "enable")
	var remaining := count
	while remaining > 0:
		var batch := mini(remaining, 200)
		_command(sim, "population", "configure", {"values": {"count": batch}})
		_command(sim, "population", "generate")
		remaining -= batch
	var timing: Array = []
	var started := Time.get_ticks_msec()
	for day in range(days):
		var step_start := Time.get_ticks_msec()
		_command(sim, "clock", "advance", {"minutes": 1440})
		timing.append(Time.get_ticks_msec() - step_start)
	var elapsed := Time.get_ticks_msec() - started
	var valid: Dictionary = sim.validate_state(sim.state)
	if not valid.ok: failures.append(str(valid.get("error", "invalid state")))
	var actions := {}
	var personalities := {}
	var actions_by_personality := {}
	var example_profiles := {}
	var aspirations := {}
	var emotions := {}
	var fears := {}
	var milestones := 0
	var memory_count := 0
	var social_outcomes := 0
	var examples: Array = []
	var unique_profiles := {}
	var dimensions := {}
	var directed_bonds := 0
	var grievances := 0
	var disclosures := 0
	var ids: Array = sim.state.social.npcs.keys()
	ids.sort()
	for id in ids:
		var npc: Dictionary = sim.state.social.npcs[id]
		var personality := str(npc.personality)
		unique_profiles[JSON.stringify(npc.psychology.facets)] = true
		var description: Dictionary = sim.services.npc_personalities.describe(npc)
		for key in description.dimensions:
			var value := float(description.dimensions[key])
			if not dimensions.has(key): dimensions[key] = {"min": value, "max": value, "sum": 0.0}
			dimensions[key].min = minf(float(dimensions[key].min), value)
			dimensions[key].max = maxf(float(dimensions[key].max), value)
			dimensions[key].sum += value
		for link in npc.mind.bonds.values():
			directed_bonds += 1
			if float(link.grievance) > 0: grievances += 1
			disclosures += link.known_interests.size() + link.known_values.size()
		personalities[personality] = int(personalities.get(personality, 0)) + 1
		if not actions_by_personality.has(personality): actions_by_personality[personality] = {}
		for action in npc.mind.completed_actions: actions[action] = int(actions.get(action, 0)) + int(npc.mind.completed_actions[action])
		for action in npc.mind.completed_actions:
			actions_by_personality[personality][action] = int(actions_by_personality[personality].get(action, 0)) + int(npc.mind.completed_actions[action])
		var goal := str(npc.mind.aspiration.id)
		aspirations[goal] = int(aspirations.get(goal, 0)) + 1
		var emotion := str(npc.mind.emotion.id)
		emotions[emotion] = int(emotions.get(emotion, 0)) + 1
		for fear in npc.mind.fears: fears[fear] = int(fears.get(fear, 0)) + 1
		milestones += int(npc.mind.aspiration.milestones)
		for past in npc.mind.aspiration_history: milestones += int(past.milestones)
		memory_count += npc.mind.sentiments.size()
		social_outcomes += int(npc.mind.completed_actions.get("connect", 0)) + int(npc.mind.completed_actions.get("support", 0))
		if examples.size() < 12:
			example_profiles[personality] = true
			examples.append({"id": id, "name": npc.name, "personality": sim.services.npc_personalities.describe(npc),
				"goal": npc.mind.aspiration.duplicate(true), "emotion": npc.mind.emotion.duplicate(true), "needs": npc.needs.duplicate(true),
				"decision": npc.mind.decision.duplicate(true), "recent_history": npc.mind.history.slice(-8),
				"sentiments": npc.mind.sentiments.duplicate(true), "knowledge": npc.mind.knowledge.duplicate(true),
				"claims": npc.mind.claims.duplicate(true), "bonds": npc.mind.bonds.duplicate(true), "plan": sim.services.npc_agency.inspect(str(id)).plan})
	for key in dimensions:
		dimensions[key].mean = float(dimensions[key].sum) / maxi(count, 1)
		dimensions[key].erase("sum")
	var report := {"date": "2026-10-19", "engine": Engine.get_version_info().string,
		"npcs": count, "days": days, "milliseconds": elapsed, "daily_milliseconds": timing,
		"failed": failures.size(), "failures": failures, "actions": actions, "aspirations": aspirations,
		"model": "continuous_hexaco_inspired", "unique_profiles": unique_profiles.size(), "dimensions": dimensions,
		"directed_bonds": directed_bonds, "unresolved_grievances": grievances, "disclosed_topics": disclosures,
		"legacy_labels": personalities, "actions_by_legacy_label": actions_by_personality, "event_counts": event_counts,
		"emotions": emotions, "fears": fears, "milestones": milestones,
		"relationships": sim.state.social.relationships.size(), "directed_memories": memory_count,
		"successful_social_actions": social_outcomes, "examples": examples, "stories": stories,
		"scope": "Opt-in headless logic study; no art, animation, main Gameplay binding or player saves. Not Sims 4 parity."}
	if not report_path.is_empty():
		var file := FileAccess.open(report_path, FileAccess.WRITE)
		if file == null:
			failures.append("cannot_write_report")
		else:
			file.store_string(JSON.stringify(report, "  ") + "\n")
	print("NPC_LIFE_PROBE ", JSON.stringify({"npcs": count, "days": days, "milliseconds": elapsed,
		"failed": failures.size(), "milestones": milestones, "social_actions": social_outcomes, "report": report_path}))
	quit(0 if failures.is_empty() else 1)
