extends "res://scripts/mechanics/core/module.gd"
## Optional personal arcs; progress comes from real committed actions in the world.
const Check = preload("res://scripts/mechanics/core/validation.gd")

static func defaults() -> Dictionary:
	return {"version":1, "arcs":{}}

func initialize() -> void:
	if not sim.state.has("npc_stories"): sim.state.npc_stories = defaults()

func arc_for(id: String) -> String:
	var npc: Dictionary = sim.state.social.npcs.get(id, {})
	if npc.is_empty(): return ""
	if not _binding_error(npc,sim.catalog).is_empty(): return ""
	var biography: Dictionary = npc.get("biography",{})
	if biography.has("story_arc"): return str(biography.story_arc)
	if sim.state.npc_stories.arcs.has(id): return str(sim.state.npc_stories.arcs[id].arc)
	if sim.catalog.npc_story_arcs.has(id): return id
	var goal := str(npc.get("mind",{}).get("aspiration",{}).get("id",npc.biography.goal))
	var scores := {"neighbor":0.0,"maker":0.0,"newcomer":0.0}
	if goal in ["community","relationship"]: scores.neighbor += 3
	if goal in ["mastery","creativity","career","wealth"]: scores.maker += 3
	if goal in ["exploration","wellbeing","independence"]: scores.newcomer += 3
	for skill in ["crafting","art","computing","journalism"]: scores.maker += minf(0.5,float(npc.skills.get(skill,0))/200.0)
	var candidates: Array = scores.keys()
	# Stable identity breaks ties without consuming a gameplay random draw.
	candidates.sort_custom(func(a,b): return posmod((id+str(a)).hash(),100000) < posmod((id+str(b)).hash(),100000) if scores[a] == scores[b] else scores[a] > scores[b])
	return str(candidates[0])

func blocked(id: String) -> String:
	var npc: Dictionary = sim.state.social.npcs.get(id, {})
	if npc.is_empty(): return "unknown_npc"
	var binding_error := _binding_error(npc,sim.catalog)
	if not binding_error.is_empty(): return binding_error
	if arc_for(id).is_empty(): return "personal_story_unassigned"
	if npc.biography.get("city_cast_id","")=="first_trade_loop" and not sim.services.npc_agency.enabled(): return "personal_story_city_closed"
	if npc.location != sim.state.world.location: return "npc_not_present"
	if not id in sim.state.social.contacts: return "missing_contact"
	var bond: Dictionary = sim.services.npc_relationships.view(id, "player")
	if float(bond.trust) < 5 or float(bond.grievance) >= 10: return "personal_story_trust"
	var available: Dictionary = sim.services.social_rules.availability(id, true)
	if not available.ok: return str(available.error)
	var spec := definition("npc_story_arcs",arc_for(id))
	if spec.has("locations") and not npc.location in spec.locations: return "personal_story_place"
	var owner: Dictionary = sim.services.npc_planner.active_owner(id)
	if not owner.is_empty(): return "npc_busy"
	var active: Dictionary = npc.get("mind",{}).get("active",{})
	if active.get("phase","")=="travel" or not str(active.get("partner","")).is_empty(): return "npc_busy"
	return ""

func present(id: String, locale: String = "ru") -> Dictionary:
	var arc_id := arc_for(id)
	if arc_id.is_empty(): return {}
	var spec := definition("npc_story_arcs", arc_id)
	if spec.is_empty(): return {}
	var saved: Dictionary = sim.state.npc_stories.arcs.get(id, {})
	if not saved.is_empty() and sim.state.social.npcs[id].biography.has("story_arc") and saved.get("arc","") != arc_id: return {}
	var node_id := str(saved.get("node", "intro"))
	var node: Dictionary = spec.nodes[node_id]
	var result := {"npc":id,"arc":arc_id,"title":spec.title,"node":node_id,"text":node.text,"status":saved.get("status","available"),"blocked":blocked(id),"choices":node.get("choices",[]).duplicate(true),"goal":saved.get("goal",{}).duplicate(true),"required":int(node.get("goal",{}).get("count",0)),"instruction":node.get("instruction","")}
	for field in ["title","text","instruction"]: result[field] = _text(str(result[field]),locale)
	for choice: Dictionary in result.choices: choice.text = _text(str(choice.text),locale)
	result.revisit = revisit(id,locale)
	return result

func _text(token: String, locale: String = "ru") -> String:
	var strings: Dictionary = sim.catalog.get("city_story_strings",{})
	if not strings.has("ru") or not strings.ru.has(token): return token
	return str(strings.get(locale,strings.ru)[token])

func revisit(id: String, locale: String = "ru") -> String:
	var story: Dictionary = sim.state.npc_stories.arcs.get(id,{})
	if story.get("status","") != "completed": return ""
	var spec: Dictionary = sim.catalog.get("city_story_revisits",{}).get(str(story.arc),{})
	if spec.is_empty() or sim.state.world.location != spec.location: return ""
	if int(sim.state.world.visits.get(str(spec.location),0))<=int(story.revisit_visits): return ""
	var ended: Dictionary = sim.calendar.snapshot(int(story.updated))
	if int(sim.state.clock.day_index)-int(ended.day_index)<int(spec.minimum_days_after): return ""
	var reaction: Dictionary = spec.endings.get(str(story.ending),{})
	if reaction.is_empty(): return ""
	var actor: Dictionary = sim.state.social.npcs.get(str(reaction.present_actor),{})
	var present_here: bool = not actor.is_empty() and actor.location==sim.state.world.location and not actor.activity in ["travel","sleep","recover","eat"]
	if present_here and not sim.services.npc_planner.active_owner(str(reaction.present_actor)).is_empty(): present_here = false
	return _text(str(reaction.with_actor if present_here else reaction.without_actor),locale)

func execute(operation: String, args: Dictionary) -> Dictionary:
	var id := str(args.get("id", ""))
	if not operation in ["start", "choose"]: return Rules.fail("unknown_operation")
	var reason := blocked(id)
	if not reason.is_empty(): return Rules.fail(reason)
	var arcs: Dictionary = sim.state.npc_stories.arcs
	var arc_id := arc_for(id)
	var spec := definition("npc_story_arcs", arc_id)
	if spec.is_empty(): return Rules.fail("personal_story_unassigned")
	if operation == "start":
		if arcs.has(id): return Rules.fail("personal_story_started")
		arcs[id] = {"arc":arc_id,"node":"intro","status":"active","started":sim.state.clock.total_minutes,"updated":sim.state.clock.total_minutes,"goal":{},"history":[],"ending":"","rewarded":false}
		return Rules.ok()
	if not arcs.has(id): return Rules.fail("personal_story_not_started")
	var story: Dictionary = arcs[id]
	if sim.state.social.npcs[id].biography.has("story_arc") and story.arc != arc_id: return Rules.fail("invalid_personal_story_binding")
	if story.status != "active": return Rules.fail("personal_story_finished")
	if not args.get("node") is String or args.node != story.node: return Rules.fail("stale_personal_story")
	var selected: Dictionary = {}
	for choice in spec.nodes[story.node].get("choices", []):
		if choice.id == args.get("choice", ""): selected = choice; break
	if selected.is_empty(): return Rules.fail("invalid_personal_choice")
	if int(sim.state.economy.cash) < int(selected.get("cost", 0)): return Rules.fail("insufficient_funds")
	if float(sim.state.player.needs.energy) < float(selected.get("energy", 0)): return Rules.fail("insufficient_energy")
	var minutes := int(selected.get("minutes", 5))
	var npc: Dictionary = sim.state.social.npcs[id]
	var conflict: String = sim.services.npc_planner.calendar.conflict(id,str(npc.location),minutes)
	if not conflict.is_empty(): return Rules.fail(conflict)
	var previous_pin := int(npc.pinned_until)
	if npc.has("mind"): sim.services.npc_agency._cancel(npc, "personal_story")
	npc.pinned_until = maxi(previous_pin, int(sim.state.clock.total_minutes) + minutes + 1)
	sim.state.economy.cash -= int(selected.get("cost", 0))
	sim.services.character.adjust_need("energy", -float(selected.get("energy", 0)))
	var advanced: Dictionary = sim.advance(minutes)
	if not advanced.ok: return advanced
	npc.pinned_until = previous_pin
	story.history.append({"node":story.node,"choice":selected.id,"minute":sim.state.clock.total_minutes})
	story.node = str(selected.next)
	story.updated = sim.state.clock.total_minutes
	var node: Dictionary = spec.nodes[story.node]
	story.goal = {"count":0,"ids":[]} if node.has("goal") else {}
	if node.get("ending", false):
		story.status = "completed"
		story.ending = story.node
		var reaction: Dictionary = sim.catalog.get("city_story_revisits",{}).get(str(story.arc),{})
		if not reaction.is_empty(): story.revisit_visits = int(sim.state.world.visits.get(str(reaction.location),0))
		if not story.rewarded:
			story.rewarded = true
			var applied: Dictionary = sim.apply_effects(node.get("effects",[]))
			if not applied.ok: return applied
			var effect: Dictionary = node.get("bond", {})
			var bond: Dictionary = sim.services.npc_relationships._bond(id,"player")
			sim.services.npc_relationships._change(bond, effect)
			sim.services.npc_relationships._project(id,"player")
			var xp := int(node.get("xp",10))
			if xp > 0:
				var reward: Dictionary = sim.services.character.execute("gain_xp", {"amount":xp})
				if not reward.ok: return reward
			sim.services.social.remember(id,"personal_story",{"arc":story.arc,"ending":story.ending})
			emit_event("personal_story_completed", {"id":id,"title":_text(str(spec.title)),"ending":_text(str(node.text))})
	return Rules.ok({"description":_text(str(node.text))})

func observe(module_id: String, operation: String, args: Dictionary, result: Dictionary) -> void:
	for id in sim.state.npc_stories.arcs:
		var story: Dictionary = sim.state.npc_stories.arcs[id]
		if story.status != "active": continue
		var spec := definition("npc_story_arcs", str(story.arc))
		var node: Dictionary = spec.nodes[story.node]
		var goal: Dictionary = node.get("goal", {})
		if goal.is_empty(): continue
		var matched: bool = module_id == goal.get("module", "") and operation == goal.get("operation", "")
		if not matched: continue
		if module_id=="world" and operation=="journey" and result.data.path.is_empty(): continue
		if goal.get("target_npc", false) and args.get("id", "") != id: continue
		if goal.has("id") and args.get("id", "") != goal.id: continue
		if goal.has("action") and args.get("action", "") != goal.action: continue
		if goal.has("item") and args.get("item", "") != goal.item: continue
		if result.data.get("success", true) == false: continue
		if result.data.get("accepted", true) == false or result.data.get("crafted", true) == false: continue
		var token := str(args.get("id", ""))
		if goal.has("locations"):
			if not sim.state.world.location in goal.locations: continue
			token = str(sim.state.world.location)
		if goal.get("unique", false):
			if token in story.goal.ids: continue
			story.goal.ids.append(token)
		story.goal.count += 1
		if int(story.goal.count) >= int(goal.get("count",1)):
			story.node = str(node.done)
			story.updated = sim.state.clock.total_minutes
			story.goal = {}
			emit_event("personal_story_ready", {"id":id,"title":_text(str(spec.title))})

static func catalog_error(catalog: Dictionary) -> String:
	if not catalog.get("npc_story_arcs") is Dictionary or catalog.npc_story_arcs.is_empty(): return "invalid_personal_story_catalog"
	for arc_id in catalog.get("npc_story_arcs", {}):
		var arc: Variant = catalog.npc_story_arcs[arc_id]
		if not Check.fields(arc,{"title":"s","nodes":"d"}) or not arc.nodes.has("intro"): return "invalid_personal_story_catalog"
		if not _text_valid(str(arc.title),catalog): return "invalid_personal_story_text"
		if not arc.get("locations",[]) is Array: return "invalid_personal_story_location"
		for place in arc.get("locations",[]):
			if not place is String or not catalog.locations.has(place): return "invalid_personal_story_location"
		for node in arc.nodes.values():
			if not Check.fields(node,{"text":"s"}): return "invalid_personal_story_node"
			for field in ["text","instruction"]:
				if not _text_valid(str(node.get(field,"")),catalog): return "invalid_personal_story_text"
			if not node.get("effects",[]) is Array: return "invalid_personal_story_effect"
			if not node.get("effects",[]).is_empty() and not node.get("ending",false): return "invalid_personal_story_effect"
			for effect: Variant in node.get("effects",[]):
				if not Check.fields(effect,{"kind":"s","id":"s","value":"s"}) or effect.kind!="flag": return "invalid_personal_story_effect"
				var owner: Variant = catalog.get("city_story_outcomes",{}).get(effect.id,{})
				if not Check.fields(owner,{"arc":"s","owner":"s","endings":"d"}) or owner.arc!=arc_id or not effect.value in owner.endings.values(): return "invalid_personal_story_effect"
			var xp: Variant = node.get("xp",10)
			if not Check.number(xp) or float(xp) < 0 or float(xp) != floor(float(xp)): return "invalid_personal_story_xp"
			if not node.get("choices",[]) is Array: return "invalid_personal_story_choice"
			var choice_ids: Array[String] = []
			for choice in node.get("choices", []):
				if not Check.fields(choice,{"id":"s","text":"s","next":"s"}) or not arc.nodes.has(choice.next): return "invalid_personal_story_choice"
				if not _text_valid(str(choice.text),catalog): return "invalid_personal_story_text"
				if choice.id.is_empty() or choice.id in choice_ids: return "invalid_personal_story_choice"
				choice_ids.append(choice.id)
				for key in ["minutes","cost","energy"]:
					if not Check.number(choice.get(key,0)) or float(choice.get(key,0)) < 0 or float(choice.get(key,0)) > 120: return "invalid_personal_story_cost"
			if node.has("goal"):
				if not Check.fields(node.goal,{"module":"s","operation":"s","count":"n"}) or not arc.nodes.has(node.get("done","")): return "invalid_personal_story_goal"
				if not node.get("choices",[]).is_empty() or float(node.goal.count) != int(node.goal.count) or int(node.goal.count) < 1 or int(node.goal.count) > 16: return "invalid_personal_story_goal"
				if node.goal.has("locations"):
					if not node.goal.locations is Array or node.goal.locations.size() < int(node.goal.count): return "invalid_personal_story_goal"
					for location in node.goal.locations:
						if not location is String or not catalog.locations.has(location): return "invalid_personal_story_goal"
			if node.get("ending",false):
				if node.has("goal") or not node.get("choices",[]).is_empty(): return "invalid_personal_story_ending"
	for flag in catalog.get("city_story_outcomes",{}):
		var outcome: Variant = catalog.city_story_outcomes[flag]
		if not Check.fields(outcome,{"arc":"s","owner":"s","endings":"d"}) or not catalog.npc_story_arcs.has(outcome.arc): return "invalid_personal_story_outcome"
		for ending in outcome.endings:
			var node: Dictionary = catalog.npc_story_arcs[outcome.arc].nodes.get(ending,{})
			if not node.get("ending",false) or not outcome.endings[ending] is String: return "invalid_personal_story_outcome"
			var expected := {"kind":"flag","id":flag,"value":outcome.endings[ending]}
			if not expected in node.get("effects",[]): return "invalid_personal_story_outcome"
	for arc_id in catalog.get("city_story_revisits",{}):
		var spec: Variant = catalog.city_story_revisits[arc_id]
		if not catalog.npc_story_arcs.has(arc_id) or not Check.fields(spec,{"location":"s","minimum_days_after":"n","endings":"d"}) or not catalog.locations.has(spec.location): return "invalid_personal_story_revisit"
		if float(spec.minimum_days_after)<0 or float(spec.minimum_days_after)!=int(spec.minimum_days_after): return "invalid_personal_story_revisit"
		for ending in spec.endings:
			var reaction: Variant = spec.endings[ending]
			if not catalog.npc_story_arcs[arc_id].nodes.get(ending,{}).get("ending",false) or not Check.fields(reaction,{"present_actor":"s","with_actor":"s","without_actor":"s"}): return "invalid_personal_story_revisit"
			if not _text_valid(reaction.with_actor,catalog) or not _text_valid(reaction.without_actor,catalog): return "invalid_personal_story_text"
	return ""

static func _text_valid(token: String, catalog: Dictionary) -> bool:
	if not token.begins_with("world_story."): return true
	for locale in ["ru","en"]:
		if not catalog.get("city_story_strings",{}).get(locale,{}).get(token) is String: return false
	return true

static func _binding_error(npc: Dictionary, catalog: Dictionary) -> String:
	var biography: Variant = npc.get("biography",{})
	if not biography is Dictionary: return "invalid_personal_story_binding"
	if not biography.has("story_arc"): return ""
	var arc: Variant = biography.story_arc
	if not arc is String: return "invalid_personal_story_binding"
	if not arc.is_empty() and not catalog.npc_story_arcs.has(arc): return "invalid_personal_story_binding"
	return ""

static func state_error(state: Dictionary, catalog: Dictionary) -> String:
	var book: Variant = state.get("npc_stories")
	if not Check.fields(book,{"version":"n","arcs":"d"}) or book.version != 1: return "invalid_personal_stories"
	for flag in catalog.get("city_story_outcomes",{}):
		var outcome: Dictionary = catalog.city_story_outcomes[flag]
		var completed: Dictionary = book.arcs.get(str(outcome.owner),{})
		var value: Variant = state.world.flags.get(flag)
		if completed.get("status","")=="completed" and completed.get("arc","")==outcome.arc:
			if value!=outcome.endings.get(str(completed.ending)): return "invalid_personal_story_outcome"
		elif value!=null: return "invalid_personal_story_outcome"
	for actor: Dictionary in state.social.npcs.values():
		var binding_error := _binding_error(actor,catalog)
		if not binding_error.is_empty(): return binding_error
	for id in book.arcs:
		var story: Variant = book.arcs[id]
		if not state.social.npcs.has(id) or not Check.fields(story,{"arc":"s","node":"s","status":"s","started":"n","updated":"n","goal":"d","history":"a","ending":"s","rewarded":"b"}): return "invalid_personal_story_state"
		var biography: Dictionary = state.social.npcs[id].biography
		if biography.has("story_arc") and story.arc != biography.story_arc: return "invalid_personal_story_binding"
		if not catalog.npc_story_arcs.has(story.arc) or not catalog.npc_story_arcs[story.arc].nodes.has(story.node): return "invalid_personal_story_state"
		if not story.status in ["active","completed"] or story.history.size() > 32: return "invalid_personal_story_state"
		var node: Dictionary = catalog.npc_story_arcs[story.arc].nodes[story.node]
		if story.status == "completed" and (not node.get("ending",false) or not story.rewarded or story.ending != story.node): return "invalid_personal_story_ending"
		if story.status == "active" and (node.get("ending",false) or story.rewarded or not story.ending.is_empty()): return "invalid_personal_story_ending"
		var reaction: Dictionary = catalog.get("city_story_revisits",{}).get(str(story.arc),{})
		if story.status=="completed" and not reaction.is_empty():
			var visits: Variant = story.get("revisit_visits")
			if not Check.number(visits) or float(visits)<0 or int(visits)!=float(visits) or int(visits)>int(state.world.visits.get(str(reaction.location),0)): return "invalid_personal_story_revisit"
		for key in ["started","updated"]:
			if float(story[key]) < 0 or float(story[key]) > float(state.clock.total_minutes) or int(story[key]) != float(story[key]): return "invalid_personal_story_time"
		if float(story.updated) < float(story.started): return "invalid_personal_story_time"
		if not story.goal.is_empty():
			if not Check.fields(story.goal,{"count":"n","ids":"a"}) or float(story.goal.count) < 0 or int(story.goal.count) != float(story.goal.count) or story.goal.ids.size() > 16: return "invalid_personal_story_progress"
			for token in story.goal.ids:
				if not token is String: return "invalid_personal_story_progress"
		if node.has("goal"):
			if story.goal.is_empty() or int(story.goal.count) >= int(node.goal.count): return "invalid_personal_story_progress"
			if node.goal.get("unique",false) and story.goal.ids.size() != int(story.goal.count): return "invalid_personal_story_progress"
			var seen: Array[String] = []
			for token in story.goal.ids:
				if token in seen or (node.goal.has("locations") and not token in node.goal.locations): return "invalid_personal_story_progress"
				seen.append(token)
		elif not story.goal.is_empty(): return "invalid_personal_story_progress"
		var cursor := "intro"
		var last_minute := float(story.started)
		var nodes: Dictionary = catalog.npc_story_arcs[story.arc].nodes
		for entry in story.history:
			if not Check.fields(entry,{"node":"s","choice":"s","minute":"n"}) or not catalog.npc_story_arcs[story.arc].nodes.has(entry.node) or float(entry.minute) > float(state.clock.total_minutes) or float(entry.minute) < float(story.started): return "invalid_personal_story_history"
			if int(entry.minute) != float(entry.minute) or float(entry.minute) < last_minute or float(entry.minute) > float(story.updated): return "invalid_personal_story_history"
			if nodes[cursor].has("goal"): cursor = str(nodes[cursor].done)
			if entry.node != cursor: return "invalid_personal_story_history"
			var selected: Dictionary = {}
			for choice in nodes[cursor].get("choices",[]):
				if choice.id == entry.choice: selected = choice; break
			if selected.is_empty(): return "invalid_personal_story_history"
			cursor = str(selected.next)
			last_minute = float(entry.minute)
		if story.node != cursor and (not nodes[cursor].has("goal") or story.node != nodes[cursor].done): return "invalid_personal_story_history"
	return ""
