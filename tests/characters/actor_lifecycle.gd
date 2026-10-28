extends SceneTree
## Bounded native actor/real conversation lifecycle audit; no production changes.
const Actor = preload("res://scripts/characters/conversation_actor.gd")
const BasePuppet = preload("res://scripts/characters/puppet_view.gd")
const Room = preload("res://scenes/characters/conversation_room.tscn")
const PROFILE := "res://data/characters/conversation_reactions.json"
const BAD_PROFILE := "E:/GoDot/.dev-setup/reaction-lifecycle-invalid.json"
var passed := 0
var failed := 0
var failures: Array[String] = []
var samples: Array = []
var observed_parameter: Dictionary = {}

func _initialize() -> void: _run.call_deferred()

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else: failed += 1; failures.append(label); printerr("FAIL: ",label)

func settle() -> void:
	for frame in range(4): await process_frame

func counts() -> Dictionary:
	return {"objects":int(Performance.get_monitor(Performance.OBJECT_COUNT)),"resources":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),"nodes":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),"orphans":int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))}

func no_growth(before: Dictionary, after: Dictionary) -> bool:
	for key: String in before:
		if int(after[key])>int(before[key]): return false
	return true

func refs(actor: Control) -> Dictionary:
	return {"actor":weakref(actor),"model":weakref(actor.model),"parameter":weakref(actor._parameters.values()[0]),"mesh":weakref(actor._meshes.values()[0]),"bank":weakref(actor.bank)}

func all_gone(observed: Dictionary, except_bank: bool = false) -> bool:
	for key: String in observed:
		if except_bank and key=="bank": continue
		if observed[key].get_ref()!=null: return false
	return true

func attach_stage_watch(actor: Control, watched: Array) -> void:
	actor.child_entered_tree.connect(func(child: Node):
		if child.get_script()==BasePuppet:
			watched.append(weakref(child))
			child.child_entered_tree.connect(func(native_child: Node):
				if native_child.is_class("GDCubismUserModel"): watched.append(weakref(native_child))
			)
	)

func watched_gone(watched: Array) -> bool:
	for observed: WeakRef in watched:
		if observed.get_ref()!=null: return false
	return true

func room_cycle(label: String) -> void:
	var room := Room.instantiate() as Control
	root.add_child(room)
	await settle()
	var actor: Control = room.puppet
	check(is_instance_valid(actor.model),label+": real room has the native actor")
	var old := refs(actor)
	var room_ref: WeakRef = weakref(room)
	var retained_bank: RefCounted = actor.bank
	var retained_memory: RefCounted = actor.memory
	actor.present_line("Длинная реплика перед закрытием.","smile")
	actor.gesture("shake")
	room._close()
	await settle()
	check(room_ref.get_ref()==null and all_gone(old,true),label+": room actor native model parameter and mesh are released")
	check(retained_memory.reaction_changed.get_connections().is_empty(),label+": old memory has no callbacks to its deleted actor")
	var replacement := Room.instantiate() as Control
	root.add_child(replacement)
	await settle()
	var replacement_refs := refs(replacement.puppet)
	var replacement_bank: Dictionary = replacement.puppet.bank.snapshot()
	var replacement_channels: Dictionary = replacement.puppet.bank.channels.duplicate(true)
	retained_memory.reaction_changed.emit("surprised")
	retained_bank.set_target("ParamHeadZ",0.9,"audit_old_bank",100)
	retained_bank.advance(0.2)
	check(replacement.puppet.bank.snapshot()==replacement_bank and replacement.puppet.bank.channels==replacement_channels,label+": old signals and bank cannot alter the new actor")
	check(old.model.get_ref()==null and old.parameter.get_ref()==null,label+": retained numeric bank does not retain native resources")
	retained_bank = null
	retained_memory = null
	check(old.bank.get_ref()==null,label+": old bank releases after the external reference is dropped")
	replacement._close()
	await settle()
	check(all_gone(replacement_refs),label+": replacement closes without retaining its bank")

func reload_cycle(actor: Control, label: String) -> void:
	var previous := refs(actor)
	var watched: Array = []
	attach_stage_watch(actor,watched)
	var stage_connections: Array = actor.child_entered_tree.get_connections()
	var watch_callback: Callable = stage_connections[-1].callable
	check(actor.load_reactions(PROFILE),label+": repeated valid model load succeeds")
	if observed_parameter.is_empty():
		observed_parameter = {"model_released":previous.model.get_ref()==null,"mesh_released":previous.mesh.get_ref()==null,"parameter_released":previous.parameter.get_ref()==null,"same_parameter":previous.parameter.get_ref()==actor._parameters.values()[0],"parameter_class":actor._parameters.values()[0].get_class()}
	check(previous.model.get_ref()==null and previous.parameter.get_ref()==null,label+": previous native model and parameter release after commit")
	# Successful stage's native child is now the accepted model and should remain.
	check(watched.size()==2 and watched[0].get_ref()==null and watched[1].get_ref()==actor.model,label+": temporary successful container is gone and accepted model remains")
	watched.clear()
	var accepted: Node2D = actor.model
	actor.present_line("Реплика перед ошибочной загрузкой.","concern")
	check(not actor.load_reactions(BAD_PROFILE),label+": invalid reaction is rejected")
	check(watched.size()==2 and watched_gone(watched) and actor.model==accepted and actor.get_child_count()==1,label+": rejected container and native candidate are both released")
	check(not actor.speaking and not actor.bank.channels.has("speech") and not actor.bank.channels.has("dialogue_gesture"),label+": rejected reload leaves no old speech or gesture")
	actor.child_entered_tree.disconnect(watch_callback)
	await settle()
	check(previous.mesh.get_ref()==null,label+": renderer queued mesh releases after deferred cleanup")

func reload_batch(size: int) -> void:
	var actor := Actor.new()
	root.add_child(actor)
	actor.size = Vector2(600,900)
	actor.set_process(false)
	actor.load_reactions(PROFILE)
	await reload_cycle(actor,"reload warmup")
	await settle()
	var before := counts()
	for index in range(size): await reload_cycle(actor,"reload %d/%d" % [index+1,size])
	await settle()
	var after := counts()
	samples.append({"path":"live_actor_reload","cycles":size,"before":before,"after":after})
	check(before==after,"native reload object/resource/node counters remain stable after %d cycles" % size)
	var final := refs(actor)
	actor.queue_free()
	await settle()
	check(all_gone(final),"live actor and its bank release after reload batch")

func _run() -> void:
	var invalid: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PROFILE))
	invalid.expressions.smile.NonexistentLifecycleParameter = 1
	var file := FileAccess.open(BAD_PROFILE,FileAccess.WRITE)
	file.store_string(JSON.stringify(invalid))
	file.close()
	# Two identical warmups distinguish persistent first-load caches from growth.
	await room_cycle("room warmup 1")
	await room_cycle("room warmup 2")
	await reload_batch(1)
	samples.clear()
	await settle()
	var baseline := counts()
	var settled_closed: Dictionary = {}
	for size in [1,3,10]:
		for index in range(size): await room_cycle("room %d/%d" % [index+1,size])
		await settle()
		var after := counts()
		samples.append({"path":"close_reopen_room","cycles":size,"before":baseline,"after":after})
		check(no_growth(baseline,after),"closed-room object/resource/node counters do not grow after %d cycles" % size)
		if settled_closed.is_empty(): settled_closed = after
		else: check(after==settled_closed,"closed-room counters remain identical between 1 and %d cycles" % size)
	for size in [1,3,10]: await reload_batch(size)
	await settle()
	check(no_growth(baseline,counts()) and counts()==settled_closed,"all audit paths return to the same settled closed-room baseline")
	print("ACTOR_LIFECYCLE_RESULT ",JSON.stringify({"passed":passed,"failed":failed,"failures":failures,"baseline":baseline,"final":counts(),"samples":samples,"parameter_observation":observed_parameter}))
	quit(1 if failed else 0)
