extends RefCounted
## Pure visual assembly. No gameplay RNG, equipment ownership changes, or file writes.
const PATH := "res://data/art/character_layers.json"
const Pregnancy = preload("res://scripts/portraits/pregnancy_visuals.gd")
const EXPRESSIONS := ["neutral","smile","concern","angry","attentive"]
static var _catalog: Dictionary = {}

static func catalog() -> Dictionary:
	if _catalog.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary and parsed.get("schema") == 1: _catalog = parsed
	return _catalog

static func generate(actor: Dictionary, world_seed: int = 0) -> Dictionary:
	var c := catalog()
	var a: Dictionary = actor.get("appearance",{})
	var gender := str(actor.get("gender",a.get("gender","male")))
	var morphology := str(a.get("morphology","human"))
	var rig := "prototype_female" if gender == "female" else "prototype_male"
	if morphology == "furry": rig = "anthro_pending"
	var rng := RandomNumberGenerator.new()
	rng.seed = (str(world_seed)+":"+str(actor.get("id","player"))).hash()
	var result := {"schema":1,"rig":rig,"pose":"idle","body_type":"athletic" if rng.randf()<0.3 else "slim","face":rng.randi_range(1,3),"eyes":rng.randi_range(1,3),"hair":["short","long","loose"][rng.randi_range(0,2)],"hair_color":c.palettes.hair[rng.randi_range(0,c.palettes.hair.size()-1)],"skin_color":c.palettes.skin[rng.randi_range(0,c.palettes.skin.size()-1)],"eye_color":c.palettes.eyes[rng.randi_range(0,c.palettes.eyes.size()-1)],"clothing_color":c.palettes.clothing[rng.randi_range(0,c.palettes.clothing.size()-1)],"morphology":morphology}
	var id := str(actor.get("id",""))
	if c.story_profiles.has(id):
		result.merge(c.story_profiles[id],true)
		result.rig = "prototype_female" if c.story_profiles[id].gender == "female" else "prototype_male"
	result.face = int(result.face)
	result.eyes = int(result.eyes)
	return result

static func story_actor(name_or_id: String) -> Dictionary:
	var c := catalog()
	var id: String = c.get("aliases",{}).get(name_or_id,name_or_id)
	if not c.get("story_profiles",{}).has(id): return {}
	var preset: Dictionary = c.story_profiles[id]
	return {"id":id,"name":preset.name,"gender":preset.gender,"age":23,"outfit":preset.get("outfit","casual"),"appearance":{"gender":preset.gender,"morphology":preset.morphology,"visual":generate({"id":id,"gender":preset.gender,"appearance":{"morphology":preset.morphology}})}}

static func player_actor(profile: Dictionary, runtime: Dictionary = {}) -> Dictionary:
	var appearance: Dictionary = profile.get("appearance",{}).duplicate(true)
	var actor := {"id":"player","age":23,"gender":str(appearance.get("gender","male")),"name":str(profile.get("full_name",profile.get("identity",{}).get("full_name",""))),"appearance":appearance}
	var visual := generate(actor)
	visual.body_type = str(appearance.get("body_type","slim"))
	var sharp: bool = appearance.get("face_id","soft") == "sharp"
	visual.face = 3 if sharp else 1
	visual.eyes = 1 if sharp else 3
	visual.hair = str(appearance.get("hair_style","short"))
	visual.hair_color = "d7c29b" if appearance.get("hair_color","dark") == "light" else "40363d"
	visual.skin_color = "ffffff"
	visual.clothing_color = "8b9daa"
	actor.appearance.visual = visual
	if not runtime.is_empty():
		actor.needs = runtime.get("needs",{}).duplicate(true)
		actor.injuries = runtime.get("injuries",{}).duplicate(true)
		actor.appearance.pregnancy_stage = int(runtime.get("appearance",{}).get("pregnancy_stage",0))
	return actor

static func profile_valid(visual: Dictionary) -> bool:
	if visual.get("schema") != 1: return false
	if not catalog().rigs.has(visual.get("rig","")) and visual.get("rig","") != "anthro_pending": return false
	if visual.get("pose","") != "idle": return false
	# JSON round-trips integral choices as floats; reject fractional/corrupt
	# variants while retaining the exact authored identity after restoration.
	for key in ["face","eyes"]:
		var value: Variant = visual.get(key,0)
		if not (value is int or value is float) or value != int(value) or not int(value) in [1,2,3]: return false
	if not visual.get("hair","") in ["short","long","loose"] or not visual.get("body_type","") in ["slim","athletic"]: return false
	for key in ["hair_color","skin_color","eye_color","clothing_color"]:
		if not visual.get(key) is String or not Color.html_is_valid(str(visual[key])): return false
	return true

static func outfit_for(actor: Dictionary, equipment: Dictionary = {}) -> String:
	var outfit := str(actor.get("outfit",""))
	if outfit in ["casual","work","training"]: return outfit
	for item in equipment.values():
		if str(item) == "work_top": return "work"
		if str(item) == "training_top": return "training"
	return "casual"

static func assemble(actor: Dictionary, expression: String = "neutral", wardrobe: String = "context", equipment: Dictionary = {}, pregnancy_layers: bool = true) -> Dictionary:
	var condition := preload("res://scripts/portraits/character_state.gd").describe(actor)
	var c := catalog()
	var a: Dictionary = actor.get("appearance",{})
	var visual: Dictionary = a.get("visual",{}).duplicate(true)
	if not profile_valid(visual): visual = generate(actor)
	for key in ["schema","face","eyes"]: visual[key] = int(visual[key])
	if not c.rigs.has(visual.rig): return {"ok":false,"reason":"missing_anthro_pack","profile":visual,"layers":[]}
	# Never substitute a human face for a fully furry morphology.
	if a.get("morphology",visual.get("morphology","human")) == "furry" and not "furry" in c.rigs[visual.rig].morphologies: return {"ok":false,"reason":"missing_anthro_pack","profile":visual,"layers":[]}
	var params := visual.duplicate(true)
	params.expression = expression if expression in EXPRESSIONS else "neutral"
	if params.expression == "neutral": params.expression = condition.expression
	params.outfit = outfit_for(actor,equipment) if wardrobe == "context" else wardrobe
	if not params.outfit in ["casual","work","training","underwear","base"]: params.outfit = "casual"
	var layers: Array = []
	for id in c.layers:
		var spec: Dictionary = c.layers[id]
		if spec.rig != visual.rig or spec.get("pose","idle") != visual.pose: continue
		var matches := true
		for key in spec.get("when",{}):
			if params.get(key) != spec.when[key]: matches = false; break
		if not matches: continue
		if params.outfit == "base" and str(spec.slot).begins_with("underwear"): continue
		if params.outfit in ["base","underwear"] and spec.slot in ["top","bottom","outerwear"]: continue
		var entry := spec.duplicate(true)
		entry.id = id
		entry.color = Color(str(params.get({"skin":"skin_color","hair":"hair_color","eyes":"eye_color","clothing":"clothing_color"}.get(str(spec.get("tint","")),""),"ffffff")))
		layers.append(entry)
	if pregnancy_layers: layers = Pregnancy.apply(layers,str(visual.rig),actor)
	layers.sort_custom(func(first,second): return int(first.z)<int(second.z) if first.z != second.z else str(first.id)<str(second.id))
	return {"ok":true,"profile":visual,"parameters":params,"rig":c.rigs[visual.rig],"layers":layers,"condition":condition}

static func validate_catalog() -> Array[String]:
	var errors: Array[String] = []
	errors.append_array(Pregnancy.validate())
	var c := catalog()
	for id in c.get("layers",{}):
		var spec: Dictionary = c.layers[id]
		if not c.rigs.has(spec.rig): errors.append("unknown_rig:"+id)
		if not str(spec.texture).begins_with("res://assets/") or not ResourceLoader.exists(spec.texture,"Texture2D"): errors.append("missing_texture:"+id)
	return errors
