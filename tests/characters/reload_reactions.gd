extends SceneTree
## Real native reload failures in isolated test files, never game saves.
const Actor = preload("res://scripts/characters/conversation_actor.gd")
const PROFILE := "res://data/characters/conversation_reactions.json"
const FIXTURES := "E:/GoDot/.dev-setup/reaction-reload-fixtures"
var passed := 0
var failed := 0
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()
func check(value: bool, label: String) -> void:
	if value: passed += 1
	else: failed += 1; failures.append(label); printerr("FAIL: ",label)

func write_file(name: String, content: String) -> String:
	var path := FIXTURES.path_join(name)
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(content)
	return path

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(FIXTURES)
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PROFILE))
	var cases := {}
	cases.invalid_json = write_file("invalid.json","{")
	var candidate := original.duplicate(true)
	candidate.model.title = "Rejected candidate"
	candidate.profile = FIXTURES.path_join("missing-profile.json")
	cases.missing_profile = write_file("missing-profile-ref.json",JSON.stringify(candidate))
	candidate = original.duplicate(true)
	candidate.model.title = "Rejected candidate"
	candidate.model.model = FIXTURES.path_join("missing.model3.json")
	cases.missing_model = write_file("missing-model-ref.json",JSON.stringify(candidate))
	candidate = original.duplicate(true)
	candidate.expressions.smile.UnknownNativeParameter = 1
	cases.unknown_parameter = write_file("unknown-parameter.json",JSON.stringify(candidate))
	candidate = original.duplicate(true)
	candidate.profile = write_file("array-profile.json","[]")
	cases.invalid_profile = write_file("invalid-profile-ref.json",JSON.stringify(candidate))
	for key: String in ["model","speech","gestures","line_gestures","idle"]:
		candidate = original.duplicate(true)
		candidate[key] = []
		cases["invalid_shape_"+key] = write_file("shape-"+key+".json",JSON.stringify(candidate))
	candidate = original.duplicate(true)
	candidate.speech.expressions.neutral = "invalid"
	cases.invalid_speech_style = write_file("invalid-speech-style.json",JSON.stringify(candidate))
	candidate = original.duplicate(true)
	candidate.expressions.erase("attentive")
	cases.missing_start_expression = write_file("missing-start-expression.json",JSON.stringify(candidate))
	candidate = original.duplicate(true)
	candidate.model.model = write_file("invalid.model3.json","{")
	cases.invalid_model_json = write_file("invalid-model-ref.json",JSON.stringify(candidate))
	candidate = original.duplicate(true)
	candidate.model.model = write_file("missing-moc.model3.json",JSON.stringify({"Version":3,"FileReferences":{"Moc":"absent.moc3","Textures":["absent.png"]}}))
	cases.missing_moc = write_file("missing-moc-ref.json",JSON.stringify(candidate))
	var native_model: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(str(original.model.model)))
	var source := str(original.model.model).get_base_dir().path_join(str(native_model.FileReferences.Moc))
	var moc_fixture := FileAccess.open(FIXTURES.path_join("existing-model.moc3"),FileAccess.WRITE)
	moc_fixture.store_buffer(FileAccess.get_file_as_bytes(source))
	moc_fixture.close()
	native_model.FileReferences = {"Moc":"existing-model.moc3","Textures":["missing-texture.png"]}
	candidate = original.duplicate(true)
	candidate.model.model = write_file("missing-texture.model3.json",JSON.stringify(native_model))
	cases.missing_texture = write_file("missing-texture-ref.json",JSON.stringify(candidate))
	var binding_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(str(original.profile)))
	binding_data.initial.UnknownBindingParameter = 1
	candidate = original.duplicate(true)
	candidate.profile = write_file("unknown-binding.json",JSON.stringify(binding_data))
	cases.unknown_binding_parameter = write_file("unknown-binding-ref.json",JSON.stringify(candidate))
	var actor := Actor.new()
	root.add_child(actor)
	actor.size = Vector2(600,900)
	actor.set_process(false)
	var errors: Array[String] = []
	var loaded := [0]
	var diagnostics := {}
	actor.load_failed.connect(func(message: String): errors.append(message))
	actor.model_loaded.connect(func(_descriptor): loaded[0] += 1)
	for key: String in cases:
		check(actor.load_reactions(PROFILE),"prepare healthy native actor: "+key)
		actor.present_line("Продолжающаяся радостная реплика.","smile")
		actor._process(0.1)
		var model: Node2D = actor.model
		var reactions: Dictionary = actor.reactions.duplicate(true)
		var definitions: Dictionary = actor.bank.definitions.duplicate(true)
		var bindings: Dictionary = actor.profile.duplicate(true)
		var descriptor: Dictionary = actor.descriptor.duplicate(true)
		var channels: Dictionary = actor.bank.channels.duplicate(true)
		channels.erase("speech")
		channels.erase("dialogue_gesture")
		var error_count := errors.size()
		var loaded_count: int = loaded[0]
		var result: Variant = actor.load_reactions(str(cases[key]))
		check(result is bool and not result,"explicit false on rejected reload: "+key)
		diagnostics[key] = actor.last_load_error
		if key=="missing_texture": check(actor.last_load_error=="missing_model_texture","missing texture reaches its intended validation branch")
		check(errors.size()==error_count+1 and loaded[0]==loaded_count and not actor.last_load_error.is_empty(),"one failure signal and no premature success signal: "+key)
		check(not actor.speaking and not actor.bank.channels.has("speech") and not actor.bank.channels.has("dialogue_gesture"),"rejected reload stops previous speech and gesture: "+key)
		check(is_instance_valid(actor.model) and actor.model==model and actor.reactions==reactions and actor.bank.definitions==definitions and actor.profile==bindings and actor.descriptor==descriptor,"rejected reload retains the entire healthy presentation atomically: "+key)
		check(actor.bank.channels==channels and actor.bank.values.ParamMouthOpen==0,"rejected reload preserves non-speech channels and closes mouth: "+key)
		check(actor.load_reactions(PROFILE) and actor.present_line("Успешное восстановление речи.","neutral"),"successful reload remains possible after rejection: "+key)
		check(loaded[0]==loaded_count+1 and actor.last_load_error.is_empty() and actor.get_child_count()==1,"successful retry has exactly one native child and clears diagnostics: "+key)
	actor.cancel_speech()
	var current: Node2D = actor.model
	var bank: RefCounted = actor.bank
	actor.present_line("Прямая загрузка ошибочной модели.","smile")
	var direct: Variant = actor.load_character({"model":FIXTURES.path_join("absent.model3.json")},actor.profile)
	check(direct is bool and not direct and actor.model==current and not actor.speaking and not actor.bank.channels.has("dialogue_gesture"),"direct inherited model API also rejects atomically and stops old speech")
	actor.bank.smoothing = 0.2
	actor.set_framing(1.7,Vector2(0,0.1))
	check(actor.load_character(original.model,actor.profile) and actor.bank==bank and actor.bank.smoothing==0.2 and actor.zoom==1.7,"successful direct reload preserves bank identity smoothing and framing")
	var named_palette: Dictionary = actor.profile.duplicate(true)
	named_palette.palette[0].color = "white"
	check(actor.load_character(original.model,named_palette),"valid named palette colors retain the existing renderer contract")
	check(actor.load_reactions(PROFILE) and actor.bank==bank and actor.get_child_count()==1,"reaction reload does not leak staged models or replace the bank contract")
	actor.free()
	var empty_actor := Actor.new()
	root.add_child(empty_actor)
	empty_actor.set_process(false)
	check(not empty_actor.load_reactions(str(cases.unknown_parameter)) and empty_actor.model==null and empty_actor.reactions.is_empty() and empty_actor.bank.definitions.is_empty() and empty_actor.get_child_count()==0,"first invalid profile leaves a clean actor without a staged model")
	check(empty_actor.load_reactions(PROFILE),"fresh actor recovers after its first failed load")
	empty_actor.free()
	await process_frame
	print("REACTION_RELOAD_RESULT ",JSON.stringify({"passed":passed,"failed":failed,"failures":failures,"invalid_cases":cases.size(),"diagnostics":diagnostics}))
	quit(1 if failed else 0)
