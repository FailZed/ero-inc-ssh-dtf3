extends "res://scripts/mechanics/core/module.gd"

func execute(operation: String, args: Dictionary) -> Dictionary:
	var id := str(args.get("id", ""))
	var groups: Dictionary = sim.state.organizations
	if operation == "create":
		var template := definition("organizations", id)
		if template.is_empty() or groups.has(id): return Rules.fail("organization_unavailable")
		groups[id] = {"members": {}, "budget": int(template.get("budget", 0)),
			"reputation": 0.0, "cleanliness": 100.0, "projects": {}, "articles": 0}
		sim.services.institutions.initialize_group(groups[id])
		return Rules.ok()
	if not groups.has(id): return Rules.fail("unknown_organization")
	var group: Dictionary = groups[id]
	var npc := str(args.get("npc", ""))
	match operation:
		"recruit":
			if not sim.state.social.npcs.has(npc) or group.members.has(npc): return Rules.fail("invalid_recruit")
			if group.members.size() >= int(definition("organizations", id).get("capacity", 20)): return Rules.fail("organization_full")
			group.members[npc] = {"role": "member", "task": "idle"}
			sim.services.institutions.roster_changed(id)
		"dismiss":
			if not group.members.has(npc): return Rules.fail("not_member")
			group.members.erase(npc)
			sim.services.institutions.roster_changed(id)
		"assign":
			var task := str(args.get("task", "idle"))
			if not group.members.has(npc): return Rules.fail("not_member")
			if not task in ["idle", "clean", "fundraise", "article"] and not group.projects.has(task): return Rules.fail("unknown_task")
			if args.has("role"): return Rules.fail("role_requires_election")
			sim.services.institutions.attendance.cancel(group,npc,"reassigned")
			group.members[npc].task = task
		"fund":
			var amount := int(args.get("amount", 0))
			if amount <= 0 or sim.state.economy.cash < amount: return Rules.fail("invalid_funding")
			sim.state.economy.cash -= amount
			group.budget += amount
		"project":
			var project_id := str(args.get("project", ""))
			var project := definition("group_projects", project_id)
			if project.is_empty() or group.projects.has(project_id): return Rules.fail("project_unavailable")
			if group.budget < int(project.get("cost", 0)): return Rules.fail("organization_funds")
			group.budget -= int(project.get("cost", 0))
			group.projects[project_id] = {"progress": 0.0, "completed": false}
		_:
			return Rules.fail("unknown_operation")
	return Rules.ok()

func tick(minute: int) -> void:
	if minute % 1440 != 0: return
	for group in sim.state.organizations.values():
		group.cleanliness = maxf(0,float(group.cleanliness)-group.members.size())
