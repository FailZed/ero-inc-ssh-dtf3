extends SceneTree
## Narrow native-actor checks; optional render is a verification image, not a game screen.
const Actor = preload("res://scripts/characters/conversation_actor.gd")
var passed := 0
var failed := 0
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		failures.append(label)
		printerr("FAIL: ",label)

func _run() -> void:
	if "--render-only" in OS.get_cmdline_user_args():
		for argument: String in OS.get_cmdline_user_args():
			if argument.begins_with("--capture-reactions="): await _capture(argument.trim_prefix("--capture-reactions="))
		quit(1 if failed else 0)
		return
	var actor := Actor.new()
	root.add_child(actor)
	actor.size = Vector2(600,900)
	actor.set_process(false)
	actor.gaze_enabled = false
	actor.blink_enabled = false
	check(actor.load_reactions(),"authored reactions load against actual native model")
	if not is_instance_valid(actor.model): quit(1); return
	var used := {}
	for pose: Dictionary in actor.reactions.expressions.values():
		for id: String in pose: used[id] = actor.bank.definitions[id].duplicate()
	check(actor.bank.definitions.ParamEyeOpen.min == -1 and actor.bank.definitions.ParamEyeOpen.max == 0,"native asymmetric eyelid limits are respected")
	check(actor.bank.definitions.ParamMouthOpen.min == -1 and actor.bank.definitions.ParamMouthOpen.default == 0 and actor.bank.definitions.ParamMouthOpen.max == 2,"native mouth limits and rest position are confirmed")
	actor.set_expression("neutral")
	check(actor.bank.target_for("ParamMouthForm")==0,"neutral face has no inherited smile")
	actor.set_expression("smile")
	check(actor.bank.target_for("ParamMouthForm")>0 and actor.bank.target_for("ParamEyesHappy")>0,"joy uses mouth and eyes together")
	actor.set_expression("concern")
	check(actor.bank.target_for("ParamMouthForm")<0 and actor.bank.target_for("ParamBrowLY")>0,"concern differs from joy in brows and mouth")
	actor.set_expression("neutral")
	check(actor.bank.target_for("ParamBrowLRot")==0 and actor.bank.target_for("ParamEyeLShock")==0 and actor.bank.target_for("ParamBlush")==0,"neutral clears parameters owned by prior expressions")
	var channels: Dictionary = actor.bank.channels.duplicate(true)
	check(not actor.set_expression("unsupported") and actor.expression=="neutral" and actor.bank.channels==channels,"unsupported expression is rejected without pretending support")
	actor.gesture("nod")
	actor._process(0.1)
	check(actor.bank.channels.has("dialogue_gesture"),"supported head gesture runs")
	actor.gesture("shake")
	check(not actor.bank.channels.has("dialogue_gesture"),"replacing a gesture clears its old parameter before next frame")
	actor._process(0.1)
	check(actor.bank.channels.dialogue_gesture.parameters.has("ParamHeadX") and not actor.bank.channels.dialogue_gesture.parameters.has("ParamHeadY"),"gesture replacement does not keep the previous axis")
	check(not actor.gesture("unsupported") and not actor.bank.channels.has("dialogue_gesture"),"unsupported gesture releases the old channel")
	actor.gesture("tilt")
	actor._process(1.0)
	check(not actor.bank.channels.has("dialogue_gesture") and actor.bank.target_for("ParamHeadZ")==0,"short gesture restores expression control")
	var completed := [0]
	actor.speech_finished.connect(func(): completed[0] += 1)
	check(actor.present_line("Анимация речи ещё продолжается.","smile"),"supported speech begins")
	actor._process(0.1)
	check(actor.bank.values.ParamMouthOpen>0,"speech drives actual mouth values")
	actor.finish_speech()
	check(actor.bank.values.ParamMouthOpen==0 and actor._parameters.ParamMouthOpen.get("value")==0 and not actor.bank.channels.has("speech"),"skip closes bank and native mouth immediately")
	check(not actor.bank.channels.has("dialogue_gesture"),"skip releases the line gesture")
	actor.finish_speech()
	check(completed[0]==1,"skip completion is emitted once")
	actor.present_line("Незаконченная реплика.","smile")
	actor._process(0.1)
	actor.cancel_speech()
	check(not actor.speaking and actor.bank.values.ParamMouthOpen==0 and not actor.bank.channels.has("dialogue_gesture") and completed[0]==1,"cancellation closes mouth and gesture without finishing another line")
	actor.present_line("Смена реплики.","smile")
	actor._process(0.1)
	actor.present_line("Теперь тревожная речь продолжается.","concern")
	check(actor.bank.values.ParamMouthOpen==0 and actor._gesture.parameter=="ParamHeadZ","new line releases old mouth and replaces the short gesture")
	actor.present_line("Описание результата события.","concern",false,true)
	actor._process(0.15)
	check(actor.revealed>0 and not actor.bank.channels.has("speech") and not actor.bank.channels.has("dialogue_gesture") and actor.bank.values.ParamMouthOpen==0,"narration reveals without articulation or a speech gesture")
	actor.characters_per_second = 10
	actor.present_line("а, б продолжается","neutral")
	actor._process(0.2)
	check(actor.revealed==2 and actor._pause_left>0 and actor.bank.target_for("ParamMouthOpen")==0,"comma is honoured even when a frame reveals multiple characters")
	actor._process(0.04)
	check(actor.revealed==2,"punctuation pause consumes real time")
	actor.present_line("а, б продолжается","neutral")
	actor._process(0.33)
	var large_frame_count: int = actor.revealed
	var large_frame_pause: float = actor._pause_left
	actor.present_line("а, б продолжается","neutral")
	for frame in range(11): actor._process(0.03)
	check(actor.revealed==large_frame_count and is_equal_approx(actor._pause_left,large_frame_pause),"text timing is independent of frame size")
	var cancel_callback := func(count: int):
		if count>0: actor.cancel_speech()
	actor.speech_progress.connect(cancel_callback)
	actor.present_line("Реплика будет отменена обработчиком.","neutral")
	actor._process(0.2)
	check(not actor.speaking and actor.bank.values.ParamMouthOpen==0 and not actor.bank.channels.has("speech"),"progress callback cancellation cannot reopen the old mouth")
	actor.speech_progress.disconnect(cancel_callback)
	var replacement := [false]
	var replace_callback := func(count: int):
		if count>0 and not replacement[0]:
			replacement[0] = true
			actor.present_line("Новая реплика.","concern")
	actor.speech_progress.connect(replace_callback)
	actor.present_line("Старая.","neutral")
	actor._process(1.0)
	check(actor.speaking and actor.speech_text=="Новая реплика." and actor.revealed==0 and completed[0]==1,"reentrant replacement does not finish or advance the new line")
	actor.speech_progress.disconnect(replace_callback)
	actor.cancel_speech()
	actor.reactions.expressions.neutral.NonexistentParameter = 1
	check(not actor._validate_reactions(actor.reactions,actor.bank),"profile refuses a nonexistent native parameter")
	actor.reactions.expressions.neutral.erase("NonexistentParameter")
	actor.reactions.expressions.neutral.ParamBrowLRot = 31
	check(not actor._validate_reactions(actor.reactions,actor.bank),"profile refuses a real parameter outside its actual range")
	actor.reactions.expressions.neutral.erase("ParamBrowLRot")
	check(actor._validate_reactions(actor.reactions,actor.bank),"profile is valid after removing invalid test changes")
	var peaks := {}
	actor.characters_per_second = 38
	for style: String in ["neutral","smile","concern"]:
		actor.present_line("аааааааааааааааааааааааааааааааааааааааааааааааааааааааааааааааааааааааааааааааааааааааааааааааааааааааааааааааааааааааа",style)
		var peak := 0.0
		for frame in range(40):
			actor._process(0.025)
			peak = maxf(peak,float(actor.bank.target_for("ParamMouthOpen")))
		peaks[style] = peak
	check(float(peaks.smile)>float(peaks.neutral) and float(peaks.neutral)>float(peaks.concern),"joyful neutral and anxious speech use distinct bounded mouth envelopes")
	actor.cancel_speech()
	actor.reactions.gestures.nod.amplitude = 5
	check(not actor._validate_reactions(actor.reactions,actor.bank),"gesture refuses an amplitude outside actual native head travel")
	actor.reactions.gestures.nod.amplitude = 0.15
	actor.free()
	if "--conversation-regression" in OS.get_cmdline_user_args():
		await preload("res://tests/characters/conversation.gd").new(self).run()
	var capture := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-reactions="): capture = argument.trim_prefix("--capture-reactions=")
	if not capture.is_empty(): await _capture(capture)
	print("REACTIONS_RESULT ",JSON.stringify({"passed":passed,"failed":failed,"failures":failures,"native_parameters":used}))
	quit(1 if failed else 0)

func _capture(path: String) -> void:
	root.size = Vector2i(1800,900)
	RenderingServer.set_default_clear_color(Color("0b151f"))
	var actors: Array[Control] = []
	for index in range(3):
		var panel := SubViewportContainer.new()
		panel.position = Vector2(index*600,0)
		panel.size = Vector2(600,900)
		panel.stretch = true
		root.add_child(panel)
		var viewport := SubViewport.new()
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		panel.add_child(viewport)
		var camera := Camera2D.new()
		camera.position = Vector2(300,320)
		camera.zoom = Vector2(2.8,2.8)
		viewport.add_child(camera)
		var actor := Actor.new()
		viewport.add_child(actor)
		actor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		actor.load_reactions()
		actor.gaze_enabled = false
		actor.blink_enabled = false
		actor.set_framing(1.42,Vector2(0,0.08))
		actor.set_expression(["neutral","smile","concern"][index])
		actors.append(actor)
		var title := Label.new()
		title.text = ["neutral","smile","concern"][index]
		title.add_theme_font_size_override("font_size",25)
		title.position = Vector2(index*600+20,20)
		root.add_child(title)
	for frame in range(60): await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(path)==OK,"actual native actor verification image saves")
	for actor in actors: actor.get_parent().get_parent().free()
