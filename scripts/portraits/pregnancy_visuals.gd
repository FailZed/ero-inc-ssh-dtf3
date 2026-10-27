extends RefCounted
## Presentation only: derives nine art variants without modifying simulation or saves.
const PATH := "res://data/art/pregnancy_materials.json"
const Calendar = preload("res://scripts/mechanics/core/calendar.gd")
static var _catalog: Dictionary = {}

static func catalog() -> Dictionary:
	if _catalog.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary and parsed.get("schema") == 1: _catalog = parsed
	return _catalog

static func variant(actor: Dictionary) -> int:
	var appearance: Dictionary = actor.get("appearance",{})
	if appearance.has("pregnancy_visual_variant"):
		return clampi(int(appearance.pregnancy_visual_variant),0,9)
	return [0,1,4,7,9][clampi(int(appearance.get("pregnancy_stage",0)),0,4)]

static func with_runtime(actor: Dictionary, state: Dictionary) -> Dictionary:
	var result := actor.duplicate(true)
	var condition: Dictionary = state.get("conditions",{}).get(str(actor.get("id",""))+":pregnancy",{})
	if condition.is_empty(): return result
	var month := 0
	if condition.get("status","") == "active":
		var now := int(state.get("clock",{}).get("total_minutes",0))
		var start := int(condition.get("started",now))
		var finish := int(condition.get("end_time",start+1))
		if finish == Calendar.add_months(start,9):
			month = 1
			while month < 9 and now >= Calendar.add_months(start,month): month += 1
		else:
			month = clampi(int(floor(float(now-start)*9.0/maxi(1,finish-start)))+1,1,9)
	if not result.has("appearance"): result.appearance = {}
	result.appearance.pregnancy_visual_variant = month
	return result

static func apply(layers: Array, rig: String, actor: Dictionary) -> Array:
	var month := variant(actor)
	if rig != "prototype_female" or month == 0: return layers
	var spec: Dictionary = catalog().get("variants",{}).get(str(month),{})
	if spec.is_empty(): return layers
	var result: Array = []
	var skin := Color.WHITE
	for original in layers:
		var entry: Dictionary = original.duplicate(true)
		if entry.slot == "body_detail": continue
		if entry.slot == "body": skin = entry.color
		if entry.slot == "chest": entry.z = 23
		if entry.slot in ["top","outerwear","bottom","underwear_bottom"]:
			entry.pregnancy_material = spec.material
			entry.pregnancy_role = 1 if entry.slot in ["top","outerwear"] else 2
		result.append(entry)
	result.append({"id":"female_pregnancy_%02d" % month,"rig":rig,"slot":"pregnancy_abdomen","texture":spec.texture,"z":22,"tint":"skin","pose":"idle","color":skin,"variant":month})
	return result

static func validate() -> Array[String]:
	var errors: Array[String] = []
	var variants: Dictionary = catalog().get("variants",{})
	if variants.size() != 9: errors.append("pregnancy_variant_count")
	for month in range(1,10):
		var spec: Dictionary = variants.get(str(month),{})
		if not ResourceLoader.exists(str(spec.get("texture","")),"Texture2D"): errors.append("pregnancy_texture_%d" % month)
		if not ResourceLoader.exists(str(spec.get("material","")),"ShaderMaterial"): errors.append("pregnancy_material_%d" % month)
	return errors
