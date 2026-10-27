extends RefCounted
## Local art manifest. Stable portrait IDs are cosmetic state; external model APIs aren't required.
static func entries() -> Array:
	var path := "res://data/art/npc_portraits.json"
	if not FileAccess.file_exists(path): return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or not parsed.get("portraits") is Array: return []
	var result: Array = []
	for entry in parsed.portraits:
		if not entry is Dictionary: continue
		if not entry.get("id") is String or not entry.get("texture") is String: continue
		if not entry.get("morphology") in ["human","semi_furry","furry"] or not entry.get("gender") in ["male","female","nonbinary"]: continue
		if not str(entry.texture).begins_with("res://assets/") or not ResourceLoader.exists(entry.texture,"Texture2D"): continue
		result.append(entry)
	return result

static func choose(actor: Dictionary, catalog: Array, used: Dictionary = {}) -> String:
	var candidates: Array = []
	for entry in catalog:
		if entry.gender == actor.gender and entry.morphology == actor.appearance.get("morphology","human") and not used.has(str(entry.id)): candidates.append(str(entry.id))
	candidates.sort()
	if candidates.is_empty(): return ""
	return candidates[posmod(str(actor.id).hash(),candidates.size())]

static func texture(id: String) -> Texture2D:
	for entry in entries():
		if entry.id == id: return load(entry.texture)
	return null
