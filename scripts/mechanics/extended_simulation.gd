extends "res://scripts/mechanics/npc_life_simulation.gd"
## Additive systems keep the historical mechanics/parity catalog intact.
const Family = preload("res://scripts/mechanics/family.gd")
const FamilyLifecycle = preload("res://scripts/mechanics/family_lifecycle.gd")
const Digital = preload("res://scripts/mechanics/digital.gd")
const Collections = preload("res://scripts/mechanics/collections.gd")
var previous_catalog: Dictionary = {}

func _load_catalog() -> Dictionary:
	var result := super._load_catalog()
	previous_catalog = result.duplicate(true)
	for file in ["family", "digital", "collections", "remaining_content"]:
		var extra: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/mechanics/%s.json" % file))
		for group in extra:
			if not result.has(group): result[group] = {}
			result[group].merge(extra[group], true)
	return result

func _init(random_seed: int = 1, extensions: Dictionary = {}) -> void:
	super(random_seed, extensions)
	for group in extensions:
		if previous_catalog.has(group) and previous_catalog[group] is Dictionary and extensions[group] is Dictionary: previous_catalog[group].merge(extensions[group].duplicate(true), true)
	# Presentation stocks the current items; reconstruct the exact old stock for hash matching.
	for shop in previous_catalog.shops.values():
		for item in shop.get("stock", {}).keys():
			if not previous_catalog.items.has(item): shop.stock.erase(item)
	services["family"] = Family.new(self)
	services["digital"] = Digital.new(self)
	services["collections"] = Collections.new(self)
	services.lifecycle = FamilyLifecycle.new(self)
	state_restored.connect(services.family.initialize)
	services.family.initialize()
	state_restored.connect(services.digital.initialize)
	services.digital.initialize()
	state_restored.connect(services.collections.initialize)
	services.collections.initialize()
	for validator in [Family, Digital, Collections]:
		var error: String = validator.catalog_error(catalog)
		if not error.is_empty(): configuration_error = error

func validate_state(candidate: Dictionary) -> Dictionary:
	var result := super.validate_state(candidate)
	if not result.ok: return result
	var error := Family.state_error(candidate, catalog)
	if error.is_empty(): error = Digital.state_error(candidate, catalog)
	if error.is_empty(): error = Collections.state_error(candidate, catalog)
	return Rules.fail(error) if not error.is_empty() else result

func restore_snapshot(snapshot: Dictionary) -> Dictionary:
	var prepared := snapshot.duplicate(true)
	if str(prepared.get("catalog_hash", "")) == JSON.stringify(previous_catalog).sha256_text():
		prepared.catalog_hash = JSON.stringify(catalog).sha256_text()
		if prepared.get("state") is Dictionary and not prepared.state.has("family"): prepared.state.family = Family.defaults()
		if prepared.get("state") is Dictionary and not prepared.state.has("digital"): prepared.state.digital = Digital.defaults()
		if prepared.get("state") is Dictionary and not prepared.state.has("collection"): prepared.state.collection = Collections.defaults()
	return super.restore_snapshot(prepared)

func after_command(module_id: String, operation: String, args: Dictionary, result: Dictionary, before: Dictionary) -> Dictionary:
	result = super.after_command(module_id, operation, args, result, before)
	if result.ok: services.collections.poll()
	return result
