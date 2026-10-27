extends RefCounted
## Regression coverage for incomplete eyes, mismatched heads and layer/UI Z leaks.
const Visuals = preload("res://scripts/portraits/character_visuals.gd")
const View = preload("res://scripts/portraits/layered_character_view.gd")

static func _slot(composition: Dictionary, slot: String) -> Array:
	return composition.layers.filter(func(layer): return layer.slot == slot)

static func run(suite) -> void:
	suite.check(Visuals.validate_catalog().is_empty(),"all modular portrait textures and rigs resolve")
	var actor := {"id":"visual_regression","gender":"male","appearance":{"morphology":"human"}}
	actor.appearance.visual = Visuals.generate(actor,42)
	var before: Dictionary = actor.duplicate(true)
	var rng_state: int = suite.gameplay.simulation.rng.state
	var complete_eyes := true
	var compatible_head := true
	var stable_features := true
	var untinted_whites := true
	var exclusive_emotions := true
	for sex in ["male","female"]:
		actor.gender = sex
		actor.appearance.visual = Visuals.generate(actor,42)
		for eyes in [1,2,3]:
			actor.appearance.visual.eyes = eyes
			var neutral := Visuals.assemble(actor)
			for expression in Visuals.EXPRESSIONS:
				var assembly := Visuals.assemble(actor,expression)
				complete_eyes = complete_eyes and _slot(assembly,"sclera").size()==1 and _slot(assembly,"iris_left").size()==1 and _slot(assembly,"iris_right").size()==1 and _slot(assembly,"eyes").size()==1
				var depths := {}
				for entry in assembly.layers: depths[entry.slot] = int(entry.z)
				complete_eyes = complete_eyes and depths.sclera < depths.iris_left and depths.iris_left < depths.eyes
				if sex == "male": compatible_head = compatible_head and _slot(assembly,"face").is_empty() and _slot(assembly,"nose").is_empty() and _slot(assembly,"eye_base").size()==1
				else: compatible_head = compatible_head and _slot(assembly,"face").size()==1 and _slot(assembly,"nose").size()==1
				untinted_whites = untinted_whites and _slot(assembly,"sclera")[0].color == Color.WHITE
				exclusive_emotions = exclusive_emotions and _slot(assembly,"mouth").size()==1 and _slot(assembly,"brows").size()==1
				for slot in ["body","face","eyes","iris_left","iris_right","hair_front"]:
					stable_features = stable_features and _slot(assembly,slot) == _slot(neutral,slot)
	suite.check(complete_eyes,"all eye shapes and expressions have whites below irises and lids above")
	suite.check(compatible_head,"male body uses its matching eye base without the incompatible legacy head or duplicate nose")
	suite.check(untinted_whites,"skin and iris colors cannot tint the eye whites")
	suite.check(exclusive_emotions,"each expression has exactly one mouth and one pair of eyebrows")
	suite.check(stable_features,"expressions preserve the same body, face, hair and eye identity")
	actor = before.duplicate(true)
	var casual := Visuals.assemble(actor)
	var work := Visuals.assemble(actor,"neutral","work")
	var bare := Visuals.assemble(actor,"neutral","base")
	suite.check(_slot(work,"top") != _slot(casual,"top") and _slot(work,"body") == _slot(casual,"body"),"dressing changes garments without changing anatomy")
	suite.check(bare.layers.all(func(entry): return not entry.slot in ["top","bottom","outerwear","underwear_top","underwear_bottom"]),"base anatomy remains independent of every garment")
	suite.check(_slot(bare,"eyes") == _slot(casual,"eyes") and _slot(bare,"mouth") == _slot(casual,"mouth"),"undressing cannot replace the face")
	suite.check(actor == before and suite.gameplay.simulation.rng.state == rng_state,"visual inspection consumes neither actor state nor gameplay RNG")
	suite.check(Visuals.generate(actor,42) == before.appearance.visual,"a world seed and actor ID reproduce their original appearance")
	actor.appearance.morphology = "furry"
	suite.check(not Visuals.assemble(actor).ok,"a fully furry actor never gets a human modular face")
	suite.check(Visuals.story_actor("Лира").is_empty(),"adult modular presets exclude the childhood character")
	suite.check(_slot(Visuals.assemble(Visuals.player_actor({"appearance":{"face_id":"soft"}})),"eyes") != _slot(Visuals.assemble(Visuals.player_actor({"appearance":{"face_id":"sharp"}})),"eyes"),"the hero face-style choice visibly changes the assembled eyes")
	var story_presets_valid := true
	var story_identity_stable := true
	for id in Visuals.catalog().story_profiles:
		var story := Visuals.story_actor(id)
		story_presets_valid = story_presets_valid and Visuals.profile_valid(story.appearance.visual) and Visuals.assemble(story).ok
		story_identity_stable = story_identity_stable and Visuals.generate(story,2026) == story.appearance.visual
	suite.check(story_presets_valid,"all authored adult portrait presets assemble with their own rig")
	suite.check(story_identity_stable,"authored cast keeps its complete identity between chapter portraits and generated world state")
	var restored: Dictionary = JSON.parse_string(JSON.stringify(before))
	suite.check(Visuals.profile_valid(restored.appearance.visual) and Visuals.assemble(restored).profile == Visuals.assemble(before).profile,"JSON restoration preserves the exact modular identity")
	var view := View.new()
	view.size = Vector2(600,800)
	suite.root.add_child(view)
	view.set_actor(before)
	view.set_expression("smile")
	view.set_expression("neutral")
	suite.check(view._sprites.values().all(func(sprite): return sprite.z_index==0),"portrait layer depth cannot escape its UI branch and cover dialogue")
	var ordered: Array = view._canvas.get_children().filter(func(child): return child is Sprite2D and not child.is_queued_for_deletion()).map(func(child): return str(child.name))
	var declared: Array = view.composition.layers.map(func(entry): return str(entry.id))
	suite.check(ordered == declared,"live sprites retain catalog order after repeated expression changes")
	view.mirrored = true
	view.framing = "mirror"
	view._layout()
	suite.check(view._canvas.scale.x < 0 and view._canvas.scale.y > 0,"the mirror flips the whole registered character together")
	view.queue_free()
