extends RefCounted
const Visuals = preload("res://scripts/portraits/character_visuals.gd")
const Pregnancy = preload("res://scripts/portraits/pregnancy_visuals.gd")
const Calendar = preload("res://scripts/mechanics/core/calendar.gd")
const View = preload("res://scripts/portraits/layered_character_view.gd")

static func slot(composition: Dictionary, name: String) -> Array:
	return composition.layers.filter(func(entry): return entry.slot == name)

static func run(suite) -> void:
	var actor := {"id":"pregnancy_art_test","age":30,"gender":"female","appearance":{"morphology":"human"}}
	actor.appearance.visual = Visuals.generate(actor,17)
	actor.appearance.visual.body_type = "athletic"
	var original := actor.duplicate(true)
	var rng_state: int = suite.gameplay.simulation.rng.state
	var neutral := Visuals.assemble(actor)
	var textures := {}
	var materials := {}
	var stages_valid := true
	var identity_stable := true
	var outfits_valid := true
	for month in range(1,10):
		actor.appearance.pregnancy_visual_variant = month
		for outfit in ["casual","work","training","underwear","base"]:
			var assembly := Visuals.assemble(actor,"neutral",outfit)
			var abdomen := slot(assembly,"pregnancy_abdomen")
			stages_valid = stages_valid and abdomen.size() == 1 and abdomen[0].variant == month and slot(assembly,"body_detail").is_empty()
			textures[abdomen[0].texture] = true
			for name in ["face","eyes","hair_front","arms_front"]:
				identity_stable = identity_stable and slot(assembly,name) == slot(neutral,name)
			for entry in assembly.layers:
				if entry.slot in ["top","bottom","underwear_bottom"]:
					outfits_valid = outfits_valid and entry.has("pregnancy_material") and entry.pregnancy_role == (1 if entry.slot=="top" else 2)
					materials[entry.pregnancy_material] = true
	suite.check(stages_valid and textures.size()==9 and materials.size()==9,"nine pregnancy stages use nine painted layers and nine garment material resources")
	suite.check(identity_stable,"pregnancy variants preserve face, eyes, hair and arm anatomy")
	suite.check(outfits_valid,"every supported outfit fits abdomen independently of identity layers")
	actor = original.duplicate(true)
	suite.check(slot(Visuals.assemble(actor),"pregnancy_abdomen").is_empty() and not slot(Visuals.assemble(actor),"body_detail").is_empty(),"nonpregnant anatomy and athletic detail remain original")
	for stage in range(5):
		actor.appearance.pregnancy_stage = stage
		suite.check(Pregnancy.variant(actor) == [0,1,4,7,9][stage],"legacy pregnancy stage %d has a deterministic art fallback" % stage)
	actor = original.duplicate(true)
	var state := {"clock":{"total_minutes":0},"conditions":{actor.id+":pregnancy":{"status":"active","started":0,"end_time":Calendar.add_months(0,9)}}}
	var snapshot := state.duplicate(true)
	var months_valid := true
	for month in range(9):
		state.clock.total_minutes = Calendar.add_months(0,month)
		months_valid = months_valid and Pregnancy.variant(Pregnancy.with_runtime(actor,state)) == month+1
	suite.check(months_valid,"calendar pregnancy derives all nine visual months at exact calendar boundaries")
	state = snapshot.duplicate(true)
	var enriched := Pregnancy.with_runtime(actor,state)
	suite.check(actor == original and state == snapshot and enriched != actor and suite.gameplay.simulation.rng.state == rng_state,"visual runtime enrichment changes neither actor, world, save data nor gameplay RNG")
	state.conditions[actor.id+":pregnancy"].status = "completed"
	actor.appearance.pregnancy_stage = 4
	suite.check(Pregnancy.variant(Pregnancy.with_runtime(actor,state))==0,"birth or pregnancy completion clears the displayed abdomen even with a stale coarse stage")
	state.conditions[actor.id+":pregnancy"].status = "active"
	state.conditions[actor.id+":pregnancy"].end_time = 90
	state.clock.total_minutes = 80
	suite.check(Pregnancy.variant(Pregnancy.with_runtime(actor,state))==9,"compressed pregnancy fixtures retain all nine proportional visual stages")
	actor.gender = "male"
	actor.appearance.visual = Visuals.generate(actor,17)
	actor.appearance.pregnancy_visual_variant = 9
	suite.check(slot(Visuals.assemble(actor),"pregnancy_abdomen").is_empty(),"female pregnancy art is never substituted onto a male rig")
	actor.appearance.morphology = "furry"
	suite.check(not Visuals.assemble(actor).ok,"pregnancy cannot bypass the missing fully furry art restriction")
	actor = original.duplicate(true)
	var view := View.new()
	suite.root.add_child(view)
	view.size = Vector2(600,800)
	for month in [9,1,7,0,4,0]:
		actor.appearance.pregnancy_visual_variant = month
		view.set_actor(actor)
		view.set_expression("smile")
	var declared: Array = view.composition.layers.map(func(entry): return str(entry.id))
	var live: Array = view._canvas.get_children().map(func(child): return str(child.name))
	suite.check(live == declared and slot(view.composition,"pregnancy_abdomen").is_empty(),"repeated stage changes remove obsolete abdomen sprites without duplicate nodes")
	suite.check(view._sprites.values().all(func(sprite): return sprite.material == null or sprite.material.shader != load("res://scripts/portraits/pregnancy_garment.gdshader")),"returning to baseline removes every pregnancy garment material")
	var world: Dictionary = suite.gameplay.simulation.state
	for target in [str(actor.id),"player"]:
		actor.id = target
		var condition_key: String = target+":pregnancy"
		var had_condition: bool = world.conditions.has(condition_key)
		var prior: Dictionary = world.conditions.get(condition_key,{}).duplicate(true)
		world.conditions[condition_key] = {"status":"active","started":int(world.clock.total_minutes),"end_time":Calendar.add_months(int(world.clock.total_minutes),9)}
		view.set_actor(actor)
		suite.check(Pregnancy.variant(view.actor)==1 and slot(view.composition,"pregnancy_abdomen").size()==1,"live portrait derives %s art from its active world condition" % target)
		if had_condition: world.conditions[condition_key] = prior
		else: world.conditions.erase(condition_key)
	view.free()
