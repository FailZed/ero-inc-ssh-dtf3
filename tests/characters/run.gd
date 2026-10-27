extends SceneTree

const Bank = preload("res://scripts/characters/parameter_bank.gd")
const Clip = preload("res://scripts/characters/motion_clip.gd")
const Memory = preload("res://scripts/characters/interaction_memory.gd")
const Puppet = preload("res://scripts/characters/puppet_view.gd")
var passed := 0
var failed := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, title: String) -> void:
	if condition: passed += 1
	else:
		failed += 1
		push_error("FAIL: " + title)

func _bank() -> RefCounted:
	var result := Bank.new()
	result.configure([{"id":"X","min":-1.0,"max":1.0,"default":0.0},{"id":"Eye","min":-1.0,"max":0.0,"default":0.0},{"id":"Gesture","min":1.0,"max":3.0,"default":1.0}])
	return result

func _pure_tests() -> void:
	var bank := _bank()
	check(not bank.set_target("absent",1.0),"unknown parameter rejected")
	check(not bank.set_target("X",NAN),"NaN rejected")
	check(not bank.set_target("X",INF),"infinity rejected")
	check(is_equal_approx(bank.normalized_value("Eye",-1.0),-1.0),"asymmetric eye range")
	check(is_equal_approx(bank.normalized_value("Gesture",1.0),3.0),"gesture default is one")
	bank.set_target("X",8.0,"pose",20)
	check(is_equal_approx(bank.target_for("X"),1.0),"range clamps")
	bank.set_target("X",-0.4,"pointer",60)
	check(is_equal_approx(bank.target_for("X"),-0.4),"higher priority wins")
	bank.clear_channel("pointer")
	check(is_equal_approx(bank.target_for("X"),1.0),"release restores lower priority")
	bank.set_target("X",-0.2,"add",80,"add")
	check(is_equal_approx(bank.target_for("X"),0.8),"additive source")
	for mode: String in ["smooth","linear","spring"]:
		var a := _bank()
		var b := _bank()
		a.mode = mode
		b.mode = mode
		a.set_target("X",0.7)
		b.set_target("X",0.7)
		for i in range(30): a.advance(1.0/30.0)
		for i in range(120): b.advance(1.0/120.0)
		check(absf(float(a.values.X)-float(b.values.X)) < 0.0001,mode+" frame independence")
		check(is_finite(a.values.X) and absf(a.values.X) <= 1.0,mode+" bounded")
	bank.reset()
	check(bank.channels.is_empty() and is_equal_approx(bank.values.X,0.0),"reset clears sources")
	var clip := Clip.new()
	clip.start_recording("fixture")
	for i in range(31): clip.record_step(1.0/30.0,{"X":float(i)/30.0})
	clip.stop()
	var loaded := Clip.new()
	check(loaded.load_clip(JSON.parse_string(JSON.stringify(clip.serialize()))),"clip JSON round trip")
	check(loaded.play(),"clip plays")
	var middle: Dictionary = loaded.sample(0.5)
	check(absf(float(middle.get("X",-1.0))-14.0/30.0)<0.0001,"clip time interpolation")
	check(is_equal_approx(loaded.sample(5.0).X,1.0) and not loaded.playing,"clip endpoint stops")
	loaded.play(true)
	check(not loaded.sample(5.0).is_empty() and loaded.playing,"clip loops")
	check(not loaded.load_clip({"schema":1,"frames":[{"time":0,"values":{"X":1}},{"time":0,"values":{"X":2}}]}),"non-monotonic clip rejected")
	check(not loaded.load_clip({"schema":1,"frames":[{"time":0,"values":{"X":"bad"}},{"time":1,"values":{"X":2}}]}),"non-numeric clip rejected")
	var memory := Memory.new()
	memory.begin("head")
	memory.advance(0.7)
	memory.motion(0.2)
	var event: Dictionary = memory.finish()
	check(event.interaction == "head" and is_equal_approx(event.duration,0.7),"hold duration")
	check(memory.state == "comfortable" and memory.history.size() == 1,"release records reaction")
	memory.begin("hand")
	check(memory.finish(true).cancelled,"cancelled interaction recorded")
	for i in range(100): memory.begin("head"); memory.finish()
	check(memory.history.size() == 64,"memory history bounded")
	check(Puppet.point_in_triangle(Vector2(0.2,0.2),Vector2.ZERO,Vector2.RIGHT,Vector2.DOWN),"triangle inside")
	check(not Puppet.point_in_triangle(Vector2.ONE,Vector2.ZERO,Vector2.RIGHT,Vector2.DOWN),"triangle outside")
	check(not Puppet.point_in_triangle(Vector2.ZERO,Vector2.ZERO,Vector2.ZERO,Vector2.ZERO),"degenerate triangle rejected")
	check(not Puppet.validate_profile({"zones":"invalid"}),"malformed zones rejected")
	check(not Puppet.validate_profile({"poses":{"pose":[1,2,3]}}),"malformed preset rejected")

func _run() -> void:
	_pure_tests()
	await process_frame
	check(ClassDB.class_exists("GDCubismUserModel"),"native Cubism registered")
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/characters/study_catalog.json"))
	var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/characters/interaction_profile.json"))
	var view := Puppet.new()
	root.add_child(view)
	view.size = Vector2(700,700)
	view.set_process(false)
	for item: Dictionary in catalog.models:
		var ok: bool = view.load_character(item, profile if item.id == "interaction_model" else {})
		check(ok,"load "+item.id)
		if not ok: continue
		check(view.bank.definitions.size() == int(item.parameters),"parameter count "+item.id)
		check(view.model.call("get_meshes").size() == int(item.drawables),"drawable count "+item.id)
		for i in range(3): view._process(1.0/60.0)
		check(view.model.call("get_canvas_info").size_in_pixels.x > 0,"canvas "+item.id)
		await process_frame
	check(view.load_character(catalog.models[0],profile),"reload ordinary model")
	check(is_equal_approx(view.bank.values.ParamShirtEnabled,1.0),"first frame clothed")
	check(view.part_values.size()==36,"model part opacity exposed")
	check(not view.load_character(catalog.models[0],{"zones":"invalid"}) and view.bank.definitions.size()==106,"invalid profile preserves loaded model")
	view.physics_enabled = false
	view.gaze_enabled = false
	view.blink_enabled = false
	view.choose_preset("poses","Приветствие")
	for i in range(60): view._process(1.0/60.0)
	check(float(view.bank.values.ParamArmRUp)>0.99,"pose applied")
	view.choose_preset("outfits","Худи и брюки")
	for i in range(60): view._process(1.0/60.0)
	check(float(view.bank.values.ParamHoodieEnabled)>0.99 and float(view.bank.values.ParamShirtEnabled)<0.01,"wardrobe exclusive")
	view.reset_character()
	view.clip.load_clip({"schema":1,"model":"interaction_model","frames":[{"time":0.0,"values":{"ParamHeadX":0.0}},{"time":1.0,"values":{"ParamHeadX":1.0}}]})
	view.clip.play()
	view._process(0.5)
	check(is_equal_approx(view.bank.values.ParamHeadX,0.5),"playback does not double smooth")
	view.reset_character()
	for i in range(4): view._process(1.0/60.0)
	# Find an actual triangle in the authored head region, not a screen rectangle.
	var head_mesh := view.model.get_node_or_null("HitAreaHeadpat") as MeshInstance2D
	check(is_instance_valid(head_mesh),"head hit mesh exists")
	var head_point := Vector2.ZERO
	var hit := false
	if is_instance_valid(head_mesh):
		var box: AABB = (head_mesh.mesh as ArrayMesh).custom_aabb
		for x in range(1,10):
			for y in range(1,10):
				var local := Vector2(box.position.x+box.size.x*x/10.0,box.position.y+box.size.y*y/10.0)
				var point: Vector2 = view.get_global_transform().affine_inverse()*head_mesh.to_global(local)
				if view.hit_test(point).get("id") == "head":
					head_point = point
					hit = true
					break
			if hit: break
	check(hit,"deformed triangle hit test")
	if hit:
		view.clip.start_recording("interaction_model")
		check(view.begin_grab(head_point),"head press")
		view.move_grab(head_point+Vector2(70,0))
		for i in range(12): view._process(1.0/60.0)
		check(float(view.bank.values.ParamHeadX)>0.1,"drag changes head parameter")
		check(view.clip.recording and view.clip.frames.size()>1,"recording survives interaction")
		view.release_grab()
		for i in range(120): view._process(1.0/60.0)
		check(absf(float(view.bank.values.ParamHeadX))<0.001,"release returns pose")
		check(view.memory.history.size()==1,"interaction memory connected")
		view.begin_grab(head_point)
		view.load_character(catalog.models[0],profile)
		check(view.held.is_empty() and not view.bank.channels.has("pointer"),"switch cancels drag")
	view.free()
	await process_frame
	var workshop := load("res://scenes/characters/character_workshop.tscn").instantiate() as Control
	root.add_child(workshop)
	workshop.set_deferred("size",Vector2(1440,900))
	await process_frame
	check(workshop.sliders.size()==106,"workshop parameter inspector")
	workshop._filter_parameters("HeadX")
	var visible_rows := 0
	for row: Control in workshop.rows.values():
		if row.visible: visible_rows += 1
	check(visible_rows==1,"parameter search")
	workshop.puppet.bank.set_target("ParamHeadX",0.4)
	for i in range(90): workshop.puppet._process(1.0/60.0)
	var saved := float(workshop.puppet.bank.values.ParamHeadX)
	workshop.file_action = "save_profile"
	workshop.puppet.part_values["Part5"] = 0.35
	workshop._file_selected("user://character_profile_test.json")
	workshop.puppet.reset_character()
	workshop.file_action = "load_profile"
	workshop._file_selected("user://character_profile_test.json")
	for i in range(90): workshop.puppet._process(1.0/60.0)
	check(absf(float(workshop.puppet.bank.values.ParamHeadX)-saved)<0.001,"workshop profile round trip")
	check(is_equal_approx(workshop.puppet.part_values["Part5"],0.35),"part opacity profile round trip")
	DirAccess.remove_absolute("user://character_profile_test.json")
	workshop.free()
	await process_frame
	print("CHARACTERS_RESULT ", JSON.stringify({"passed":passed,"failed":failed,"models":catalog.models.size()}))
	quit(1 if failed else 0)
