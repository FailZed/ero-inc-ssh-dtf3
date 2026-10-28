extends "res://scripts/mechanics/npc_dialogue.gd"
const City = preload("res://scripts/gameplay/city_layout.gd")

func _pressure_choices(id: String) -> Array:
	var choices: Array = []
	if not sim.services.has("antagonism"): return choices
	for c in sim.services.antagonism.inspect().cases:
		if int(sim.state.clock.total_minutes) > int(c.deadline)+10080 or c.status == "cancelled": continue
		if id == c.actor or id == c.target:
			for response in c.responses:
				if response.blocked in ["pressure_response_used","pressure_case_closed","pressure_payment_unavailable","pressure_response_unavailable"]: continue
				var row: Dictionary = response.duplicate(true)
				row.id = "pressure:"+str(c.id)+":"+str(response.id)
				row.text = str(c.label)+": "+str(response.text)
				choices.append(row)
		else:
			for ally in c.allies:
				if ally.id == id and str(ally.blocked).is_empty(): choices.append({"id":"pressure:"+str(c.id)+":ally","text":"Попросить поддержки: "+str(c.label),"minutes":15,"blocked":""})
	return choices

func present(id: String) -> Dictionary:
	var result := super.present(id)
	if not result.is_empty() and result.node != "end": result.choices = _pressure_choices(id)+result.choices
	return result

func execute(operation: String,args: Dictionary) -> Dictionary:
	var choice := str(args.get("choice",""))
	if operation != "choose" or not choice.begins_with("pressure:"): return super.execute(operation,args)
	var id := str(args.get("id",""))
	var npc: Dictionary = sim.state.social.npcs.get(id,{})
	if not npc.has("mind"): return Rules.fail("unknown_npc")
	var d: Dictionary = npc.mind.dialogue
	if int(d.expires) <= _now(): return Rules.fail("dialogue_expired")
	if not args.get("turn") is int and not args.get("turn") is float: return Rules.fail("stale_dialogue_turn")
	if args.turn != d.turn: return Rules.fail("stale_dialogue_turn")
	var selected := false
	for row in present(id).get("choices",[]):
		if row.id == choice:
			if not str(row.blocked).is_empty(): return Rules.fail(row.blocked)
			selected = true
	if not selected: return Rules.fail("unknown_dialogue_choice")
	var response := choice.get_slice(":",2)
	var result: Dictionary = sim.services.antagonism.execute("respond",{"id":choice.get_slice(":",1),"choice":response,"ally":id if response == "ally" else ""})
	if not result.ok: return result
	d.turn += 1
	d.expires = _now()+int(rules().session_duration)
	d.utterance.text = result.data.description
	d.utterance.minute = _now()
	var view := present(id)
	view.description = result.data.description
	return Rules.ok(view)

func local_initiative(npc: Dictionary) -> bool:
	return npc.location == sim.state.world.location and (not City.point(str(npc.location)).is_empty() or npc.location == "residential_district")
