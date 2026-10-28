extends "res://scripts/mechanics/core/module.gd"
## Household simulation. Family members stay separate from the adult social population.
const CHECK = preload("res://scripts/mechanics/core/validation.gd")
const NEEDS := ["food", "hygiene", "rest", "attention", "health"]
const Handoff = preload("res://scripts/mechanics/family_handoff.gd")
var handoff

func _init(simulation) -> void:
	super(simulation)
	handoff = Handoff.new(simulation)

func care_options(id: String, need: String) -> Array:
	var member: Dictionary = sim.state.family.members.get(id,{})
	if member.is_empty() or not "player" in member.get("guardians",member.parents): return []
	return handoff.options(member,need)

static func defaults() -> Dictionary:
	return {"version": 1, "members": {}, "next_id": 1, "imported_births": 0, "budget": 0, "arrears": 0, "spent": 0, "history": []}

static func catalog_error(catalog: Dictionary) -> String:
	var household: Variant = catalog.get("family_rules",{}).get("household")
	if not CHECK.fields(household,{"daily_cost":"n","care_interval":"n","support_cost":"n","support_minutes":"n","history_limit":"n"}): return "invalid_family_rules"
	for key in ["daily_cost","care_interval","support_cost","support_minutes","history_limit"]:
		if household[key] < 0 or int(household[key]) != household[key] or household[key] > 10080: return "invalid_family_rules"
	if household.care_interval < 1 or household.support_minutes < 1 or household.history_limit < 1 or household.history_limit > 64: return "invalid_family_rules"
	var prior := -1
	for stage in ["infant", "toddler", "child", "teen", "adult"]:
		var spec: Variant = catalog.get("family_stages", {}).get(stage)
		if not CHECK.fields(spec, {"label":"s", "after_months":"n", "decay":"d"}): return "invalid_family_stage_catalog"
		if float(spec.after_months) != int(spec.after_months) or int(spec.after_months) <= prior: return "invalid_family_stage_catalog"
		prior = int(spec.after_months)
		for need in ["food", "hygiene", "rest", "attention"]:
			if not CHECK.number(spec.decay.get(need)) or float(spec.decay[need]) < 0 or float(spec.decay[need]) > 20: return "invalid_family_decay"
	for spec in catalog.get("family_actions", {}).values():
		if not CHECK.fields(spec, {"label":"s", "minutes":"n", "energy":"n", "cost":"n", "needs":"d", "stages":"a"}): return "invalid_family_action_catalog"
		if float(spec.minutes) != int(spec.minutes) or float(spec.minutes) < 1 or float(spec.minutes) > 180 or float(spec.cost) < 0 or float(spec.cost) != int(spec.cost) or float(spec.cost) > 1000 or float(spec.energy) < 0 or float(spec.energy) > 100: return "invalid_family_action_catalog"
		if not CHECK.number(spec.get("development", 0)) or float(spec.get("development", 0)) < 0 or float(spec.get("development", 0)) > 10: return "invalid_family_action_catalog"
		for need in spec.needs:
			if not need in NEEDS or not CHECK.number(spec.needs[need]) or float(spec.needs[need]) < 0 or float(spec.needs[need]) > 100: return "invalid_family_action_need"
		if spec.stages.is_empty(): return "invalid_family_action_stage"
		for stage in spec.stages:
			if not stage is String or not catalog.family_stages.has(stage): return "invalid_family_action_stage"
	return ""

func initialize() -> void:
	if not sim.state.has("family"): sim.state.family = defaults()
	_sync_births()

func _now() -> int:
	return int(sim.state.clock.total_minutes)

func _log(kind: String, id: String, details: Dictionary = {}) -> void:
	var entry := {"kind": kind, "member": id, "minute": _now(), "details": details.duplicate(true)}
	sim.state.family.history.append(entry)
	while sim.state.family.history.size() > int(sim.catalog.family_rules.household.history_limit): sim.state.family.history.pop_front()
	emit_event("family_" + kind, {"member": id, "details": details})

func _sync_births() -> void:
	var family: Dictionary = sim.state.family
	while int(family.imported_births) < sim.state.healthcare.family.size():
		var index := int(family.imported_births)
		var birth: Dictionary = sim.state.healthcare.family[index]
		var id := "family_%d" % int(family.next_id)
		family.next_id += 1
		family.imported_births += 1
		var parents: Array = []
		for parent in [str(birth.get("parent", "")), str(birth.get("partner", ""))]:
			if (parent == "player" or sim.state.social.npcs.has(parent)) and not parent in parents: parents.append(parent)
		var guardian: String = str(birth.get("parent", "player"))
		var home: String = _initial_home("player" if "player" in parents else guardian)
		var assignments := {"food": "player" if "player" in parents else guardian, "hygiene": guardian, "rest": guardian, "attention": "player" if "player" in parents else guardian}
		family.members[id] = {"id": id, "name": "Ребёнок %d" % int(family.next_id - 1), "birth_index": index,
			"born": int(birth.minute), "parents": parents, "home": home, "stage": "infant", "development": 0.0,
			"needs": {"food": 90.0, "hygiene": 90.0, "rest": 90.0, "attention": 80.0, "health": 100.0},
			"assignments": assignments, "recent": {}, "milestones": ["infant"], "next_stage": sim.calendar.add_months(int(birth.minute), 12), "support_until": 0, "task": {}, "bonds": {}, "school_days": 0, "school_progress": 0.0}
		if birth.get("custody", "parents") == "adoption":
			family.members[id].guardians = []
			family.members[id].custody = "adoption"
		elif not str(birth.get("declined_parent", "")).is_empty() or not birth.get("declined_parents", []).is_empty():
			var guardians: Array = parents.duplicate()
			guardians.erase(str(birth.get("declined_parent", "")))
			for declined in birth.get("declined_parents", []): guardians.erase(str(declined))
			family.members[id].guardians = guardians
			family.members[id].custody = "other_parent" if not guardians.is_empty() else "public_care"
			if not guardians.is_empty():
				guardian = str(guardians[0])
				family.members[id].home = _initial_home(guardian)
				for need in family.members[id].assignments: family.members[id].assignments[need] = guardian
		_log("born", id)
		_update_stage(family.members[id])

func _initial_home(guardian: String) -> String:
	var home: String = sim.actor_home(guardian)
	if not home.is_empty(): return home
	return str(sim.state.world.location) if guardian=="player" else str(sim.state.social.npcs[guardian].location)

func _household_guardian(member: Dictionary) -> String:
	var guardians: Array = member.get("guardians",member.parents)
	return "player" if "player" in guardians else "" if guardians.is_empty() else str(guardians[0])

func synchronize_homes() -> void:
	for member in sim.state.family.members.values(): _synchronize_home(member)

func _synchronize_home(member: Dictionary) -> void:
	var guardian := _household_guardian(member)
	if guardian.is_empty(): return
	var home: String = sim.actor_home(guardian)
	if home.is_empty() or home==member.home: return
	var location: String = str(sim.state.world.location) if guardian=="player" else str(sim.state.social.npcs[guardian].location)
	if not sim.is_actor_home_location(guardian,location): return
	if not member.task.is_empty():
		_release_caregiver(member.task)
		member.task = {}
		_log("care_interrupted",str(member.id),{"reason":"household_moved"})
	var previous := str(member.home)
	member.home = home
	_log("home_changed",str(member.id),{"previous":previous,"home":home,"guardian":guardian})

func _at_home(member: Dictionary, caregiver: String = "player") -> bool:
	var location: String = str(sim.state.world.location) if caregiver=="player" else str(sim.state.social.npcs.get(caregiver,{}).get("location",""))
	if location==str(member.home): return true
	var guardian := _household_guardian(member)
	return not guardian.is_empty() and member.home==sim.actor_home(guardian) and sim.is_actor_home_location(guardian,location)

func _charge(amount: int) -> bool:
	if int(sim.state.family.budget) + int(sim.state.economy.cash) < amount: return false
	var reserve := mini(amount, int(sim.state.family.budget))
	sim.state.family.budget -= reserve
	sim.state.economy.cash -= amount - reserve
	sim.state.family.spent += amount
	return true

func inspect() -> Dictionary:
	var members: Array = []
	for member in sim.state.family.members.values():
		if not "player" in member.get("guardians",member.parents): continue
		var available: Array = []
		for id in sim.catalog.family_actions:
			var spec: Dictionary = sim.catalog.family_actions[id]
			if member.stage in spec.stages:
				available.append({"id":id,"label":spec.label,"minutes":spec.minutes,"cost":spec.cost,"energy":spec.energy,"ready_at":int(member.recent.get(id,-10080))+int(sim.catalog.family_rules.household.care_interval)})
		var milestones: Array = []
		for milestone in [{"value":25,"label":"Любознательность"},{"value":50,"label":"Уверенность"},{"value":75,"label":"Самостоятельность"}]:
			milestones.append({"value":milestone.value,"label":milestone.label,"reached":float(member.development) >= int(milestone.value)})
		members.append({"id":member.id,"name":member.name,"stage":member.stage,"needs":member.needs.duplicate(true),"development":member.development,"milestones":milestones,"assignments":member.assignments.duplicate(true),"actions":available,"at_school":_school(member),"at_home":_at_home(member),"busy":not member.task.is_empty(),"independent_food":member.stage == "adult" or (member.stage == "teen" and float(member.development) >= 50)})
	return {"members":members,"daily_cost":members.size()*int(sim.catalog.family_rules.household.daily_cost),"budget":sim.state.family.budget,"arrears":sim.state.family.arrears,"description":"Развитие ускоряет обучение. Подростки с развитием от 50 и взрослые сами готовят еду из семейного бюджета; совместное время остаётся важным."}

func execute(operation: String, args: Dictionary) -> Dictionary:
	if operation == "inspect": return Rules.ok(inspect())
	var family: Dictionary = sim.state.family
	if operation == "deposit":
		var amount := int(args.get("amount", 0))
		if amount <= 0 or int(sim.state.economy.cash) < amount: return Rules.fail("insufficient_funds")
		sim.state.economy.cash -= amount
		family.budget += amount
		return Rules.ok()
	if operation == "pay_arrears":
		if int(family.arrears) <= 0: return Rules.fail("no_family_arrears")
		if not _charge(int(family.arrears)): return Rules.fail("insufficient_funds")
		family.arrears = 0
		return Rules.ok()
	var id := str(args.get("id", ""))
	if not family.members.has(id): return Rules.fail("unknown_family_member")
	var member: Dictionary = family.members[id]
	if not "player" in member.get("guardians", member.parents): return Rules.fail("not_family_guardian")
	match operation:
		"rename":
			var value := str(args.get("name", "")).strip_edges()
			if value.is_empty() or value.length() > 40 or value.contains("\n"): return Rules.fail("invalid_family_name")
			member.name = value
		"assign":
			var need := str(args.get("need", ""))
			var caregiver := str(args.get("caregiver", ""))
			if not need in ["food", "hygiene", "rest", "attention"] or not caregiver in member.get("guardians", member.parents): return Rules.fail("invalid_care_assignment")
			member.assignments[need] = caregiver
			_log("assignment", id, {"need": need, "caregiver": caregiver})
		"support":
			if int(member.support_until) > _now(): return Rules.fail("family_support_active")
			if not _charge(int(sim.catalog.family_rules.household.support_cost)): return Rules.fail("insufficient_funds")
			member.support_until = _now() + int(sim.catalog.family_rules.household.support_minutes)
			_log("support", id)
		"care": return _care(member, str(args.get("action", "")))
		"delegate": return handoff.delegate(member,str(args.get("need","")),str(args.get("caregiver","")))
		_:
			return Rules.fail("unknown_operation")
	return Rules.ok()

func _care(member: Dictionary, action: String) -> Dictionary:
	var spec := definition("family_actions", action)
	if spec.is_empty() or not member.stage in spec.stages: return Rules.fail("family_action_unavailable")
	if not _at_home(member): return Rules.fail("family_home_required")
	if not member.task.is_empty(): return Rules.fail("family_care_in_progress")
	if _school(member): return Rules.fail("family_member_at_school")
	if _now() - int(member.recent.get(action, -10080)) < int(sim.catalog.family_rules.household.care_interval): return Rules.fail("family_care_cooldown")
	if float(sim.state.player.needs.energy) < float(spec.energy): return Rules.fail("insufficient_energy")
	if not _charge(int(spec.cost)): return Rules.fail("insufficient_funds")
	member.task = {"caregiver": "player", "action": action, "due": _now() + int(spec.minutes)}
	sim.services.character.adjust_need("energy", -float(spec.energy))
	var result: Dictionary = sim.advance(int(spec.minutes))
	if not result.ok: return result
	return Rules.ok({"name": member.name, "action": action})

func _finish_care(member: Dictionary) -> void:
	var task: Dictionary = member.task
	if task.caregiver != "player":
		var person: Dictionary = sim.state.social.npcs.get(str(task.caregiver), {})
		if person.is_empty() or not _at_home(member,str(task.caregiver)) or handoff.unwell(str(task.caregiver)) or person.activity != "family_care" or int(person.pinned_until) != int(task.due) + 1:
			_release_caregiver(task)
			member.task = {}
			_log("care_interrupted", str(member.id))
			return
	if task.caregiver=="player" and not _at_home(member):
		member.task = {}
		_log("care_interrupted",str(member.id))
		return
	var spec := definition("family_actions", str(task.action))
	for need in spec.needs: member.needs[need] = minf(100, float(member.needs[need]) + float(spec.needs[need]))
	var previous_development := float(member.development)
	member.development = minf(100, previous_development + float(spec.get("development", 0)))
	for threshold in [25,50,75]:
		if previous_development < threshold and float(member.development) >= threshold: _log("development",str(member.id),{"threshold":threshold})
	member.recent[str(task.action)] = _now()
	member.bonds[str(task.caregiver)] = minf(100, float(member.bonds.get(str(task.caregiver), 0)) + 2.0)
	_release_caregiver(task)
	_log("care", str(member.id), {"action": task.action, "caregiver": task.caregiver})
	member.task = {}

func _release_caregiver(task: Dictionary) -> void:
	if task.caregiver == "player": return
	var npc: Dictionary = sim.state.social.npcs.get(str(task.caregiver), {})
	if npc.is_empty(): return
	if int(npc.pinned_until) == int(task.due) + 1: npc.pinned_until = int(task.get("previous_pin", 0))
	if npc.activity == "family_care": npc.activity = "rest"

func _school(member: Dictionary) -> bool:
	var eligible: bool = _now() >= sim.calendar.add_months(int(member.born), 72) and member.stage != "adult"
	return eligible and int(sim.state.clock.weekday) <= 5 and int(sim.state.clock.minute_of_day) >= 480 and int(sim.state.clock.minute_of_day) < 840

func _autonomy(member: Dictionary) -> void:
	if not member.task.is_empty() or _school(member) or member.get("guardians", member.parents).is_empty(): return
	var selected := ""
	for need in ["food", "hygiene", "rest", "attention"]:
		if float(member.needs[need]) < 45 and (selected.is_empty() or float(member.needs[need]) < float(member.needs[selected])): selected = need
	if selected.is_empty(): return
	var action: String = {"food":"feed", "hygiene":"wash", "rest":"settle", "attention":"play"}[selected]
	var spec := definition("family_actions", action)
	if not member.stage in spec.stages: return
	if _now() - int(member.recent.get(action, -10080)) < int(sim.catalog.family_rules.household.care_interval): return
	var id: String = handoff.choose(member,selected)
	if id.is_empty(): return
	sim.services.npc_planner.submit("family",id,action,str(sim.state.social.npcs[id].location),int(spec.minutes),65,{"member":str(member.id),"need":selected})

func start_care(request: Dictionary) -> bool:
	var member: Dictionary = sim.state.family.members.get(str(request.payload.member),{})
	if member.is_empty() or not member.task.is_empty(): return false
	var id := str(request.id)
	var need := str(request.payload.need)
	if not handoff.blocked(member,need,id).is_empty(): return false
	var npc: Dictionary = sim.state.social.npcs[id]
	var action := str(request.kind)
	if action!=handoff.ACTIONS[need] or request.destination!=npc.location: return false
	var spec := definition("family_actions",action)
	if "player" in member.get("guardians",member.parents):
		if not _charge(int(spec.cost)): return false
	else:
		if int(npc.money)<int(spec.cost): return false
		npc.money -= int(spec.cost)
	if npc.has("mind"): sim.services.npc_agency._cancel(npc, "family_care")
	member.task = {"caregiver": id, "action": action, "due": _now() + int(spec.minutes), "previous_pin": int(npc.pinned_until)}
	npc.pinned_until = _now() + int(spec.minutes) + 1
	npc.activity = "family_care"
	npc.needs.energy = maxf(0, float(npc.needs.energy) - float(spec.energy))
	if id!=str(member.assignments[need]): _log("care_handoff",str(member.id),{"from":str(member.assignments[need]),"caregiver":id,"need":need})
	return true

func tick(minute: int) -> void:
	_sync_births()
	for member in sim.state.family.members.values():
		_synchronize_home(member)
		if int(member.next_stage) > 0 and minute >= int(member.next_stage): _update_stage(member)
		if member.get("guardians", member.parents).is_empty(): continue
		if not member.task.is_empty() and minute >= int(member.task.due): _finish_care(member)
		if minute % 60 == 0: _hour(member)
		if minute % 15 == 0: _autonomy(member)

func _update_stage(member: Dictionary) -> void:
	member.next_stage = 0
	for stage in sim.catalog.family_stages:
		var threshold: int = sim.calendar.add_months(int(member.born), int(sim.catalog.family_stages[stage].after_months))
		if threshold > _now() and int(member.next_stage) == 0: member.next_stage = threshold
		if _now() >= threshold and not stage in member.milestones:
			member.stage = stage
			member.milestones.append(stage)
			if stage != "infant": _log("milestone", str(member.id), {"stage": stage})

func _hour(member: Dictionary) -> void:
	var minute := int(sim.state.clock.minute_of_day)
	var automatic: bool = int(member.support_until) > _now() or _school(member)
	for need in sim.catalog.family_stages[member.stage].decay:
		member.needs[need] = maxf(0, float(member.needs[need]) - float(sim.catalog.family_stages[member.stage].decay[need]))
	if not automatic and member.task.is_empty() and (member.stage == "adult" or (member.stage == "teen" and float(member.development) >= 50)) and float(member.needs.food) < 45:
		var cost := int(sim.catalog.family_actions.feed.cost)
		var paid := false
		if "player" in member.get("guardians",member.parents): paid = _charge(cost)
		else:
			for guardian in member.get("guardians",member.parents):
				var npc: Dictionary = sim.state.social.npcs.get(guardian,{})
				if not npc.is_empty() and int(npc.money) >= cost:
					npc.money -= cost
					paid = true
					break
		if paid:
			member.needs.food = minf(100,float(member.needs.food)+float(sim.catalog.family_actions.feed.needs.food))
			_log("self_care",str(member.id),{"action":"feed","cost":cost})
	if automatic:
		for need in ["food", "hygiene", "attention"]: member.needs[need] = minf(100, float(member.needs[need]) + 8)
	if member.stage in ["teen", "adult"]:
		member.needs.hygiene = minf(100, float(member.needs.hygiene) + 3)
	if minute < 360 or minute >= 1260: member.needs.rest = minf(100, float(member.needs.rest) + 14)
	var low := false
	for need in ["food", "hygiene", "rest"]: low = low or float(member.needs[need]) < 15
	member.needs.health = clampf(float(member.needs.health) + (-1 if low else 0.25), 10, 100)
	if low and int(member.recent.get("warning_day", -1)) != int(sim.state.clock.day_index):
		member.recent.warning_day = int(sim.state.clock.day_index)
		_log("needs_attention", str(member.id))
	if minute == 840 and int(sim.state.clock.weekday) <= 5 and _now() >= sim.calendar.add_months(int(member.born), 72) and member.stage != "adult":
		member.school_days += 1
		member.school_progress = minf(100, float(member.school_progress) + (1.0 if not low else 0.25)*(1.0+float(member.development)/100.0))
	if minute == 0 and "player" in member.get("guardians", member.parents):
		if not _charge(int(sim.catalog.family_rules.household.daily_cost)):
			sim.state.family.arrears += int(sim.catalog.family_rules.household.daily_cost)
			_log("expenses_due", str(member.id))

static func state_error(state: Dictionary, catalog: Dictionary) -> String:
	for birth in state.healthcare.family:
		if not CHECK.fields(birth, {"parent":"s", "partner":"s", "minute":"n", "care":"n", "status":"s"}): return "invalid_family_birth"
		if float(birth.minute) < 0 or float(birth.minute) != int(birth.minute) or float(birth.minute) > float(state.clock.total_minutes): return "invalid_family_birth"
		if birth.parent != "player" and not state.social.npcs.has(birth.parent): return "invalid_family_parent"
		if not birth.partner.is_empty() and birth.partner != "player" and not state.social.npcs.has(birth.partner): return "invalid_family_parent"
	var f: Variant = state.get("family")
	if not CHECK.fields(f, {"version":"n", "members":"d", "next_id":"n", "imported_births":"n", "budget":"n", "arrears":"n", "spent":"n", "history":"a"}): return "invalid_family_state"
	if f.version != 1 or f.members.size() > 256 or f.history.size() > 64: return "invalid_family_state"
	for key in ["next_id", "imported_births", "budget", "arrears", "spent"]:
		if float(f[key]) < 0 or int(f[key]) != float(f[key]): return "invalid_family_number"
	if int(f.imported_births) > state.healthcare.family.size(): return "invalid_birth_cursor"
	if f.members.size() != int(f.imported_births) or int(f.next_id) != int(f.imported_births) + 1: return "invalid_birth_cursor"
	for entry in f.history:
		if not CHECK.fields(entry, {"kind":"s", "member":"s", "minute":"n", "details":"d"}): return "invalid_family_history"
		if not f.members.has(entry.member) or float(entry.minute) < 0 or float(entry.minute) > float(state.clock.total_minutes): return "invalid_family_history"
	var used: Array = []
	for id in f.members:
		var m: Variant = f.members[id]
		if not CHECK.fields(m, {"id":"s", "name":"s", "birth_index":"n", "born":"n", "parents":"a", "home":"s", "stage":"s", "needs":"d", "development":"n", "assignments":"d", "recent":"d", "milestones":"a", "next_stage":"n", "support_until":"n", "task":"d", "bonds":"d", "school_days":"n", "school_progress":"n"}): return "invalid_family_member"
		if m.id != id or m.name.is_empty() or m.name.length() > 40 or not catalog.family_stages.has(m.stage) or not catalog.locations.has(m.home): return "invalid_family_identity"
		if float(m.born) < 0 or int(m.born) != float(m.born) or int(m.born) > int(state.clock.total_minutes): return "invalid_family_birth"
		if int(m.birth_index) in used or int(m.birth_index) < 0 or int(m.birth_index) >= int(f.imported_births): return "invalid_family_birth"
		if float(m.birth_index) != int(m.birth_index) or int(m.born) != int(state.healthcare.family[int(m.birth_index)].minute): return "invalid_family_birth"
		used.append(int(m.birth_index))
		for need in NEEDS:
			if not CHECK.number(m.needs.get(need)) or float(m.needs[need]) < 0 or float(m.needs[need]) > 100: return "invalid_family_need"
		for parent in m.parents:
			if not parent is String or (parent != "player" and not state.social.npcs.has(parent)): return "invalid_family_parent"
		if m.parents.is_empty() or m.parents.size() > 2: return "invalid_family_parent"
		if m.parents.size() == 2 and m.parents[0] == m.parents[1]: return "invalid_family_parent"
		for need in ["food", "hygiene", "rest", "attention"]:
			if not m.assignments.get(need) in m.parents: return "invalid_care_assignment"
		for milestone in m.milestones:
			if not milestone is String or not catalog.family_stages.has(milestone): return "invalid_family_milestone"
		if float(m.next_stage) < 0 or float(m.next_stage) != int(m.next_stage): return "invalid_family_milestone"
		var calendar_script = preload("res://scripts/mechanics/core/calendar.gd")
		var expected_stage := "infant"
		var next_stage := 0
		var expected_milestones: Array = []
		for stage in catalog.family_stages:
			var due: int = calendar_script.add_months(int(m.born), int(catalog.family_stages[stage].after_months))
			if due <= int(state.clock.total_minutes): expected_stage = str(stage); expected_milestones.append(stage)
			elif next_stage == 0: next_stage = due
		if m.stage != expected_stage or int(m.next_stage) != next_stage or m.milestones != expected_milestones: return "invalid_family_milestone"
		for value in m.recent.values():
			if not CHECK.number(value) or float(value) < 0 or int(value) != float(value): return "invalid_family_recent"
		for value in m.bonds.values():
			if not CHECK.number(value) or float(value) < 0 or float(value) > 100: return "invalid_family_bond"
		for key in ["development", "school_progress"]:
			if float(m[key]) < 0 or float(m[key]) > 100: return "invalid_family_progress"
		if float(m.support_until) < 0 or int(m.support_until) != float(m.support_until) or float(m.school_days) < 0 or int(m.school_days) != float(m.school_days): return "invalid_family_time"
		if not m.task.is_empty():
			if not CHECK.fields(m.task, {"action":"s", "caregiver":"s", "due":"n"}): return "invalid_family_task"
			if not catalog.family_actions.has(m.task.action) or not m.task.caregiver in m.parents or float(m.task.due) < float(state.clock.total_minutes): return "invalid_family_task"
			if not m.stage in catalog.family_actions[m.task.action].stages: return "invalid_family_task"
			if int(m.task.due) != float(m.task.due) or float(m.task.due) > float(state.clock.total_minutes) + 60: return "invalid_family_task"
			if m.task.caregiver != "player" and (not CHECK.number(m.task.get("previous_pin")) or float(m.task.previous_pin) < 0): return "invalid_family_task"
	return ""
