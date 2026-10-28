extends "res://scripts/mechanics/core/module.gd"
## Select a temporary caregiver; execution remains the existing family task.
const ACTIONS := {"food":"feed", "hygiene":"wash", "rest":"settle", "attention":"play"}

func unwell(id: String) -> bool:
	var person: Dictionary = sim.state.player if id=="player" else sim.state.social.npcs.get(id,{})
	if person.is_empty() or float(person.get("health",100))<30: return true
	if int(sim.state.healthcare.records.get(id,{}).get("unconscious_until",0))>int(sim.state.clock.total_minutes): return true
	if sim.services.has("adult_health") and sim.services.adult_health.view(id).get("urgent",false): return true
	return sim.services.has("pregnancy_wellbeing") and sim.services.pregnancy_wellbeing.view(id).get("seek_care",false)

func blocked(member: Dictionary, need: String, id: String) -> String:
	var family = sim.services.family
	if not ACTIONS.has(need): return "invalid_care_assignment"
	if not id in member.get("guardians",member.parents) or not sim.state.social.npcs.has(id): return "family_helper_not_guardian"
	if not member.task.is_empty(): return "family_care_in_progress"
	if family._school(member): return "family_member_at_school"
	var action: String = ACTIONS[need]
	var spec: Dictionary = sim.catalog.family_actions[action]
	if not member.stage in spec.stages: return "family_action_unavailable"
	if float(member.needs[need])>=45: return "family_care_not_due"
	if int(sim.state.clock.total_minutes)-int(member.recent.get(action,-10080))<120: return "family_care_cooldown"
	var npc: Dictionary = sim.state.social.npcs[id]
	if not family._at_home(member,id): return "family_helper_not_home"
	if unwell(id) or float(npc.needs.energy)<maxf(25,float(spec.energy)): return "family_helper_unwell"
	var mind: Dictionary = npc.get("mind",{})
	if not sim.services.npc_planner.active_owner(id).is_empty() or int(npc.pinned_until)>int(sim.state.clock.total_minutes): return "family_helper_busy"
	if npc.activity in ["sleep","recover","eat","work","study","travel"] or mind.get("active",{}).get("phase","")=="travel" or not str(mind.get("active",{}).get("partner","")).is_empty(): return "family_helper_busy"
	var dialogue: Dictionary = mind.get("dialogue",{})
	if dialogue.get("node","end")!="end" and int(dialogue.get("expires",0))>int(sim.state.clock.total_minutes): return "family_helper_busy"
	if int(dialogue.get("pending",{}).get("expires",0))>int(sim.state.clock.total_minutes): return "family_helper_busy"
	var conflict: String = sim.services.npc_planner.calendar.conflict(id,str(member.home),int(spec.minutes),65)
	if not conflict.is_empty(): return "family_helper_schedule"
	if "player" in member.get("guardians",member.parents):
		if int(sim.state.family.budget)+int(sim.state.economy.cash)<int(spec.cost): return "insufficient_funds"
	elif int(npc.money)<int(spec.cost): return "insufficient_funds"
	return ""

func options(member: Dictionary, need: String) -> Array:
	if not ACTIONS.has(need): return []
	var result: Array = []
	var guardians: Array = member.get("guardians",member.parents).duplicate()
	guardians.sort()
	var spec: Dictionary = sim.catalog.family_actions[ACTIONS[need]]
	for caregiver in guardians:
		var id := str(caregiver)
		if id=="player" or id==str(member.assignments[need]): continue
		var reason := blocked(member,need,id)
		result.append({"caregiver":id,"need":need,"action":ACTIONS[need],"available":reason.is_empty(),"reason":reason,"minutes":int(spec.minutes),"cost":int(spec.cost)})
	return result

func primary_unavailable(member: Dictionary, need: String) -> bool:
	var primary := str(member.assignments[need])
	if primary!="player": return not blocked(member,need,primary).is_empty()
	return not sim.services.family._at_home(member) or unwell("player") or float(sim.state.player.needs.energy)<25

func choose(member: Dictionary, need: String) -> String:
	var primary := str(member.assignments[need])
	if primary!="player" and blocked(member,need,primary).is_empty(): return primary
	if not primary_unavailable(member,need): return ""
	for option in options(member,need):
		if option.available: return str(option.caregiver)
	return ""

func delegate(member: Dictionary, need: String, id: String) -> Dictionary:
	if not ACTIONS.has(need): return Rules.fail("invalid_care_assignment")
	if id==str(member.assignments[need]): return Rules.fail("family_helper_is_primary")
	var reason := blocked(member,need,id)
	if not reason.is_empty(): return Rules.fail(reason)
	var npc: Dictionary = sim.state.social.npcs[id]
	var spec: Dictionary = sim.catalog.family_actions[ACTIONS[need]]
	var request := {"owner":"family","id":id,"kind":ACTIONS[need],"destination":str(npc.location),"minutes":int(spec.minutes),"priority":65,
		"route":{"minutes":0},"origin":str(npc.location),"payload":{"member":str(member.id),"need":need},"actors":[id]}
	if not sim.services.npc_planner._dispatch(request): return Rules.fail("family_helper_unavailable")
	return Rules.ok({"caregiver":id,"need":need,"due":int(member.task.due)})
