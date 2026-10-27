extends "res://scripts/mechanics/core/module.gd"
const CHECK = preload("res://scripts/mechanics/core/validation.gd")

static func defaults() -> Dictionary:
	return {"unlocked":[], "seen":[]}

static func catalog_error(catalog: Dictionary) -> String:
	for spec in catalog.get("gallery_entries", {}).values():
		if not CHECK.fields(spec, {"label":"s", "image":"s", "text":"s", "requirements":"d"}): return "invalid_collection_catalog"
		if not spec.image.begins_with("res://assets/") or ".." in spec.image: return "invalid_collection_image"
	return ""

func initialize() -> void:
	if not sim.state.has("collection"): sim.state.collection = defaults()

func poll() -> void:
	for id in sim.catalog.gallery_entries:
		if not id in sim.state.collection.unlocked and Rules.check(sim.state, sim.catalog.gallery_entries[id].requirements):
			sim.state.collection.unlocked.append(id)
			emit_event("collection_unlocked", {"id":id})

func entries() -> Array:
	var result: Array = []
	for id in sim.catalog.gallery_entries:
		var entry: Dictionary = sim.catalog.gallery_entries[id].duplicate(true)
		entry.id = id
		entry.unlocked = id in sim.state.collection.unlocked
		entry.seen = id in sim.state.collection.seen
		result.append(entry)
	return result

func execute(operation: String, args: Dictionary) -> Dictionary:
	var id := str(args.get("id", ""))
	if operation != "view": return Rules.fail("unknown_operation")
	if not id in sim.state.collection.unlocked: return Rules.fail("collection_locked")
	if not id in sim.state.collection.seen: sim.state.collection.seen.append(id)
	return Rules.ok(definition("gallery_entries", id).duplicate(true))

static func state_error(state: Dictionary, catalog: Dictionary) -> String:
	var c: Variant = state.get("collection")
	if not CHECK.fields(c, {"unlocked":"a", "seen":"a"}): return "invalid_collection"
	for field in ["unlocked", "seen"]:
		var used: Array = []
		for id in c[field]:
			if not id is String or not catalog.gallery_entries.has(id) or id in used: return "invalid_collection_entry"
			if field == "seen" and not id in c.unlocked: return "invalid_collection_entry"
			used.append(id)
	return ""
