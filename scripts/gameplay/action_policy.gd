extends RefCounted
## Main-game action context. Applied inside Simulation's existing transaction.
const Rules = preload("res://scripts/mechanics/core/rules.gd")
const HOME := ["bedroom", "bathroom", "kitchen", "apartment_hall"]
const GAME_MINUTES := {"blackjack": 10, "guess": 5, "reaction": 5, "strength": 5, "lockpick": 5}

static func duration(sim, module_id: String, operation: String, args: Dictionary) -> int:
	if module_id == "careers":
		if operation == "shift": return int(sim.catalog.professions.get(str(args.get("id","")),{}).get("minutes",120))
		if operation == "stream": return int(args.get("minutes",60))
		if operation == "work_contract":
			var spec: Dictionary = sim.catalog.contracts.get(str(args.get("id","")),{})
			var progress: Dictionary = sim.state.careers.contracts.get(str(args.get("id","")),{})
			var skill := float(sim.state.player.skills.get(str(spec.get("skill","computing")),0))
			var mastery := preload("res://scripts/mechanics/core/formulas.gd").mastery(skill,float(sim.catalog.balance_rules.career.get("skill_scale",200)))
			var rate: float = 0.75+mastery*1.25+sim.services.character.effective_stat("intellect")/100.0
			return mini(int(args.get("minutes",60)),ceili(maxf(0,float(spec.get("effort",120))-float(progress.get("progress",0)))/rate))
	if module_id == "economy" and operation == "stream": return int(args.get("minutes",60))
	if module_id == "growth" and operation == "practice": return int(sim.catalog.skills.get(str(args.get("id","")),{}).get("minutes",0))
	if module_id == "livelihood":
		if operation == "work": return int(sim.catalog.livelihood_rules.jobs.get(str(args.get("id","")),{}).get("minutes",0))
		return 30 if operation == "upgrade" else 15 if operation == "deliver" else 0
	if module_id == "npc_stories" and operation == "choose":
		var story: Dictionary = sim.state.npc_stories.arcs.get(str(args.get("id","")),{})
		var node: Dictionary = sim.catalog.npc_story_arcs.get(story.get("arc",""),{}).get("nodes",{}).get(story.get("node",""),{})
		for choice in node.get("choices",[]):
			if choice.id == args.get("choice",""): return int(choice.get("minutes",5))
	if module_id == "digital": return 15 if operation == "scan" else int(sim.catalog.digital_operations.get(str(args.get("id", "")), {}).get("minutes", 0)) if operation == "resolve" else 0
	if module_id == "family" and operation == "care": return int(sim.catalog.family_actions.get(str(args.get("action", "")), {}).get("minutes", 0))
	if module_id == "clock": return int(args.get("minutes", 0))
	if module_id == "character" and operation == "rest": return int(args.get("minutes", 60))
	if module_id == "character" and operation == "substance": return 2
	if module_id == "needs": return int(args.get("minutes", {"sleep":480,"nap":30,"drink":2,"toilet":5,"leisure":30}.get(operation, 0)))
	if module_id == "economy" and operation == "project":
		var id := str(args.get("id", ""))
		return maxi(0, mini(int(args.get("minutes", 60)), int(sim.catalog.projects.get(id, {}).get("effort", 0)) - int(sim.state.economy.projects.get(id, {}).get("progress", 0))))
	if module_id == "social_rules" and operation == "gathering": return 90
	if module_id == "npc_agency" and operation == "encourage": return 5
	if module_id == "housing" and operation == "move_in" and args.get("id","") in ["detached_house","penthouse","social_housing"]:
		var planned: Dictionary = sim.services.world.route(str(args.id))
		return int(planned.get("data",{}).get("minutes",0))+1
	if module_id == "world":
		if operation == "journey":
			var planned: Dictionary = sim.services.world.route(str(args.get("id","")))
			return int(planned.get("data",{}).get("minutes",0))
		if operation == "travel": return int(sim.services.world.routes_for(str(sim.state.world.location)).get(str(args.get("id", "")), {}).get("minutes", 0))
		if operation == "lesson": return int(sim.catalog.lessons.get(str(args.get("id", "")), {}).get("minutes", 0))
		return int({"clean":30,"shower":15,"homework":45,"appeal":30}.get(operation, 0))
	var groups := {"actions":"actions", "activities":"training_programs", "inventory":"recipes", "economy":"jobs"}
	if groups.has(module_id): return int(sim.catalog[groups[module_id]].get(str(args.get("id", "")), {}).get("minutes", 0))
	return 0

static func commitments(state: Dictionary, ending: int) -> Array:
	var result: Array = []
	var now := int(state.clock.total_minutes)
	for meeting in state.social.appointments:
		if meeting.status == "pending" and int(meeting.minute) >= now and int(meeting.minute) <= ending:
			result.append({"kind":"appointment", "id":str(meeting.npc), "minute":int(meeting.minute)})
	for id in state.social.promises:
		var promise: Dictionary = state.social.promises[id]
		if promise.status == "active" and int(promise.deadline) >= now and int(promise.deadline) <= ending:
			result.append({"kind":"promise", "id":str(promise.id), "minute":int(promise.deadline)})
	for id in state.careers.contracts:
		var contract: Dictionary = state.careers.contracts[id]
		if contract.status == "active" and int(contract.deadline) >= now and int(contract.deadline) <= ending:
			result.append({"kind":"contract", "id":str(id), "minute":int(contract.deadline)})
	for id in state.get("livelihood",{}).get("orders",{}):
		var order: Dictionary = state.livelihood.orders[id]
		if order.status == "active" and int(order.deadline) >= now and int(order.deadline) <= ending:
			result.append({"kind":"local_order","id":str(id),"minute":int(order.deadline)})
	for id in state.journal.quests:
		var quest: Dictionary = state.journal.quests[id]
		if quest.status == "active" and int(quest.get("deadline", 0)) > 0 and int(quest.deadline) >= now and int(quest.deadline) <= ending:
			result.append({"kind":"quest", "id":str(id), "minute":int(quest.deadline)})
	result.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.minute) < int(b.minute))
	return result

static func describe(sim, module_id: String, operation: String, args: Dictionary) -> Dictionary:
	var context := {"exerting": false, "physical": false, "sleeping": false, "extra_stamina": 0.0}
	match module_id:
		"growth":
			context.exerting = operation == "practice"
			context.physical = context.exerting and sim.catalog.skills.get(str(args.get("id","")),{}).get("category","") == "body"
		"livelihood":
			context.exerting = operation in ["work","deliver","upgrade","input"]
			context.physical = operation in ["deliver","upgrade"] or (operation == "work" and args.get("id","") in ["warehouse_shift","street_performer","underground_courier"])
		"npc_stories": context.exerting = operation == "choose"
		"digital": context.exerting = operation in ["scan", "resolve"]
		"family": context.exerting = operation == "care"
		"housing":
			if operation == "move_in" and args.get("id","") in ["detached_house","penthouse","social_housing"]:
				context.exerting = true
				context.physical = true
				context.extra_stamina = duration(sim,module_id,operation,args)*0.15
		"character":
			if operation == "rest":
				var duration := int(args.get("minutes", 60))
				context.rest_kind = str(args.get("kind", "sleep" if duration >= 120 else "rest"))
				context.sleeping = context.rest_kind in ["sleep", "nap"]
		"needs":
			context.sleeping = operation in ["sleep", "nap"]
			context.rest_kind = operation
			context.physical = operation == "leisure" and sim.state.world.location in ["global_map", "city_park", "south_promenade", "north_beach"]
			context.exerting = context.physical
			if context.physical: context.extra_stamina = 3.0
		"economy": context.exerting = operation in ["work", "project", "stream"]
		"careers": context.exerting = operation in ["work_contract", "shift", "stream", "investigate", "interview", "verify", "publish"]
		"activities":
			context.exerting = operation == "practice"
			context.physical = str(args.get("id", "")) in ["strength", "running"]
		"actions":
			context.exerting = operation == "perform"
			context.physical = args.get("id", "") == "exercise"
		"world":
			context.exerting = operation in ["travel", "journey", "clean", "lesson", "homework", "appeal"]
			context.physical = operation in ["travel", "journey", "clean"]
			if operation == "journey": context.extra_stamina = duration(sim,module_id,operation,args) * 0.15
			elif operation == "travel":
				context.extra_stamina = duration(sim,module_id,operation,args)*0.15
			elif operation == "homework": context.extra_stamina = 3.0
			elif operation == "lesson": context.extra_stamina = float(sim.catalog.lessons.get(str(args.get("id", "")), {}).get("minutes", 0)) * 0.05
		"inventory":
			context.exerting = operation == "craft"
			if operation == "craft": context.extra_stamina = float(sim.catalog.recipes.get(str(args.get("id", "")), {}).get("minutes", 0)) * 0.08
		"social_rules":
			context.exerting = operation in ["date", "gathering"]
			context.physical = operation == "date" and args.get("venue", "coffee") == "walk"
		"security":
			context.exerting = operation in ["steal", "begin_burglary"]
			context.physical = context.exerting
		"combat": context.exerting = true; context.physical = true
		"encounters":
			context.exerting = true
			var game_type := str(args.get("type", sim.state.encounters.game.get("type", "")))
			context.physical = operation in ["combat_start", "combat_action"] or game_type in ["strength", "pushups"]
	context.auto_work = (module_id == "livelihood" and operation == "work" and (sim.catalog.livelihood_rules.jobs.get(str(args.get("id","")),{}).get("kind","") == "shift" or not args.get("interactive",true))) or (module_id == "careers" and operation in ["shift","work_contract","stream"]) or (module_id == "economy" and operation in ["work","project","stream"])
	return context

static func check(sim, module_id: String, operation: String, args: Dictionary, context: Dictionary) -> Dictionary:
	var location := str(sim.state.world.location)
	if context.get("auto_work",false) and module_id != "livelihood":
		if not args.get("skip_classes",false) is bool: return Rules.fail("invalid_arguments")
		if not args.get("skip_classes",false) and not preload("res://scripts/mechanics/work_schedule.gd").conflicts(sim,location,duration(sim,module_id,operation,args)).is_empty(): return Rules.fail("work_conflicts_study")
	if context.get("rest_kind", "rest") not in ["rest", "sleep", "nap", "drink", "toilet", "leisure"]: return Rules.fail("invalid_rest_kind")
	if context.sleeping and location != "bedroom": return Rules.fail("bed_required")
	if module_id == "world":
		if operation == "shower" and location != "bathroom": return Rules.fail("bathroom_required")
		if operation in ["clean", "homework"] and not location in HOME: return Rules.fail("home_required")
	if module_id == "inventory" and operation == "craft":
		var recipe: Dictionary = sim.catalog.recipes.get(str(args.get("id", "")), {})
		if "stove" in recipe.get("equipment", []) and location != "kitchen": return Rules.fail("kitchen_required")
	var home_work: bool = module_id == "economy" and operation in ["work", "project", "stream"]
	home_work = home_work or (module_id == "careers" and operation in ["work_contract", "stream", "investigate", "verify", "publish"])
	if module_id == "careers" and operation == "shift":
		home_work = not sim.catalog.professions.get(str(args.get("id", "")), {}).has("location")
	if home_work and not location in HOME: return Rules.fail("home_workspace_required")
	if module_id == "social" and operation == "call":
		var person: Dictionary = sim.state.social.npcs.get(str(args.get("id", "")), {})
		if person.get("activity", "") == "sleep": return Rules.fail("npc_sleeping")
		if person.get("activity", "") in ["eat", "recover"] or person.get("decision", {}).get("committed", false): return Rules.fail("npc_busy")
	if module_id == "social_rules" and operation == "promise":
		var promise: Dictionary = sim.catalog.promises.get(str(args.get("promise", "")), {})
		if not promise.is_empty() and Rules.check(sim.state, promise.get("requirements", {})): return Rules.fail("promise_already_satisfied")
	if module_id == "npc_agency" and operation == "encourage":
		var reason: String = sim.services.npc_relationships.blocked("player", str(args.get("id", "")), "support")
		if not reason.is_empty(): return Rules.fail(reason)
	if (module_id == "organizations" and operation == "recruit") or (module_id == "housing" and operation == "tenant"):
		var person: Dictionary = sim.state.social.npcs.get(str(args.get("npc", "")), {})
		if not person.is_empty():
			if not str(person.id) in sim.state.social.contacts and person.location != location: return Rules.fail("meet_person_first")
			if person.has("mind") and not person.mind.boundaries.contact: return Rules.fail("contact_boundary")
			var bond: Dictionary = sim.services.npc_relationships.view(str(person.id), "player")
			if module_id == "housing" and float(bond.trust) < 15.0: return Rules.fail("tenant_invitation_declined")
			if module_id == "organizations":
				var willing: bool = float(bond.trust) >= 5.0 or str(person.biography.goal) in ["community", "creativity"]
				if person.has("mind"): willing = willing or person.mind.aspiration.id in ["creativity", "community"]
				if not willing: return Rules.fail("club_invitation_declined")
				var groups := 0
				for group in sim.state.organizations.values():
					if group.members.has(str(person.id)): groups += 1
				if groups >= 2: return Rules.fail("npc_overcommitted")
	if float(sim.state.player.needs.energy) + 0.000001 < float(context.extra_stamina): return Rules.fail("insufficient_energy")
	return Rules.ok()

static func complete(sim, module_id: String, operation: String, args: Dictionary, result: Dictionary, before: Dictionary) -> Dictionary:
	var elapsed := 0
	if module_id == "social_rules" and operation == "promise":
		var key := str(args.get("id", "")) + ":" + str(args.get("promise", ""))
		sim.state.social.promises[key]["started"] = int(before.clock.total_minutes)
	if module_id == "inventory" and operation == "use":
		var item: Dictionary = sim.catalog.items.get(str(args.get("id", "")), {})
		if item.get("category", "") == "food": elapsed = 5
	var combat_action: bool = (module_id == "combat" and operation == "action") or (module_id == "encounters" and operation == "combat_action")
	var combat_start: bool = (module_id == "combat" and operation == "start") or (module_id == "encounters" and operation == "combat_start")
	var combat: Dictionary = sim.state.encounters.combat
	if combat_start:
		combat.stamina.player = float(sim.state.player.needs.energy)
		var npc: Dictionary = sim.state.social.npcs[combat.npc]
		combat.stamina.npc = float(npc.needs.energy)
		combat.previous_pin = int(npc.pinned_until)
		if npc.has("mind"): sim.services.npc_agency._cancel(npc, "combat")
		npc.pinned_until = maxi(int(npc.pinned_until), int(sim.state.clock.total_minutes) + 1440)
	elif combat_action:
		sim.services.character.adjust_need("energy", float(combat.stamina.player) - float(sim.state.player.needs.energy))
		sim.state.social.npcs[combat.npc].needs.energy = clampf(float(combat.stamina.npc), 0.0, 100.0)
		var previous: Dictionary = before.encounters.combat
		if int(combat.turn) != int(previous.turn) or combat.status != "active": elapsed = 1
	if module_id == "encounters" and operation == "game_input":
		var game: Dictionary = sim.state.encounters.game
		if game.status != "active" and int(sim.state.clock.total_minutes) == int(before.clock.total_minutes):
			elapsed = int(GAME_MINUTES.get(str(game.type), 1))
	if elapsed > 0:
		var advanced: Dictionary = sim.advance(elapsed)
		if not advanced.ok: return advanced
	var cost := float(sim.action_context.extra_stamina)
	if float(sim.state.player.needs.energy) + 0.000001 < cost: return Rules.fail("insufficient_energy")
	sim.services.character.adjust_need("energy", -cost)
	if combat_action:
		combat.stamina.player = float(sim.state.player.needs.energy)
		combat.stamina.npc = float(sim.state.social.npcs[combat.npc].needs.energy)
		combat.player_hp = sim.services.health.hp("player")
		combat.npc_hp = sim.services.health.hp(str(combat.npc))
		sim.services.combat._update_outcome()
		if combat.status != "active":
			sim.state.social.npcs[combat.npc].pinned_until = int(combat.get("previous_pin", 0))
			result.data.status = combat.status
	return result
