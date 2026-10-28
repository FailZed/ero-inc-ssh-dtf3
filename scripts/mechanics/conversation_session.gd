extends RefCounted
## A view of the existing npc_dialogue rules. Commands remain authoritative.
signal changed
var sim: RefCounted
var npc_id := ""
var channel := "face"
var active := false
var last_result: Dictionary = {}
var transcript: Array[Dictionary] = []
var _execute: Callable
var _last_turn := -1

func _init(runtime: RefCounted, actor_id: String, executor: Callable = Callable()) -> void:
	sim = runtime
	npc_id = actor_id
	_execute = executor

func command(module: String, operation: String, args: Dictionary = {}) -> Dictionary:
	if _execute.is_valid(): return _execute.call(module,operation,args)
	return sim.command(module,operation,args)

func open(conversation_channel: String = "face", initiative: String = "") -> Dictionary:
	channel = conversation_channel
	last_result = command("npc_dialogue","open",{"id":npc_id,"channel":channel,"initiative":initiative})
	active = bool(last_result.get("ok",false))
	if active: _remember_reply()
	changed.emit()
	return last_result

func present() -> Dictionary:
	return sim.services.npc_dialogue.present(npc_id) if active else {}

func actor() -> Dictionary:
	return sim.state.social.npcs.get(npc_id,{})

func bond() -> Dictionary:
	return sim.services.npc_relationships.view(npc_id,"player")

func choose(id: String, turn: int, from_menu: bool = false) -> Dictionary:
	if not active: return {"ok":false,"error":"dialogue_expired","data":{}}
	var current: Dictionary = sim.services.npc_dialogue.menu(npc_id) if from_menu else present()
	var caption := ""
	for choice: Dictionary in current.get("choices",[]):
		if choice.id == id: caption = str(choice.text)
	last_result = command("npc_dialogue","choose_menu" if from_menu else "choose",{"id":npc_id,"choice":id,"turn":turn})
	if last_result.get("ok",false):
		_append("player",caption)
		_remember_reply()
	changed.emit()
	return last_result

func choice_minutes(id: String) -> int:
	var spec: Dictionary = sim.catalog.dialogue_choices.get(id,{})
	var action := str(spec.get("action",""))
	if not action.is_empty(): return int(sim.catalog.agency_actions.get(action,{}).get("minutes",0))
	return int(spec.get("minutes",0))

func combat() -> Dictionary:
	var encounter: Dictionary = sim.state.encounters.combat
	return encounter if encounter.get("npc","") == npc_id else {}

func combat_active() -> bool:
	return combat().get("status","") == "active"

func fight(args: Dictionary) -> Dictionary:
	if not combat_active(): return {"ok":false,"error":"no_active_combat","data":{}}
	last_result = command("combat","action",args)
	if last_result.get("ok",false): _remember_reply()
	changed.emit()
	return last_result

func _append(speaker: String, text: String) -> void:
	if text.is_empty(): return
	transcript.append({"speaker":speaker,"text":text,"minute":int(sim.state.clock.total_minutes)})
	while transcript.size()>64: transcript.pop_front()

func _remember_reply() -> void:
	var reply := present()
	if not reply.is_empty() and int(reply.turn) != _last_turn:
		_last_turn = int(reply.turn)
		_append(npc_id,str(reply.utterance.text))

func close() -> void:
	if not active: return
	if combat_active(): return
	command("npc_dialogue","close",{"id":npc_id})
	active = false
	changed.emit()
