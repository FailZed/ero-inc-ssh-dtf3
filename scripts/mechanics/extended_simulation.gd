extends "res://scripts/mechanics/npc_life_simulation.gd"
## Current household, digital and collection systems share one catalog.
const Family = preload("res://scripts/mechanics/family.gd")
const FamilyLifecycle = preload("res://scripts/mechanics/family_lifecycle.gd")
const Digital = preload("res://scripts/mechanics/digital.gd")
const Collections = preload("res://scripts/mechanics/collections.gd")

func _load_catalog() -> Dictionary:
	var result := super._load_catalog()
	for file in ["family", "digital", "collections", "remaining_content"]:
		var extra: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/mechanics/%s.json" % file))
		for group in extra:
			if not result.has(group): result[group] = {}
			result[group].merge(extra[group], true)
	return result

func _init(random_seed: int = 1, extensions: Dictionary = {}) -> void:
	super(random_seed, extensions)
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

func after_command(module_id: String, operation: String, args: Dictionary, result: Dictionary, before: Dictionary) -> Dictionary:
	result = super.after_command(module_id, operation, args, result, before)
	if result.ok: services.collections.poll()
	if result.ok and module_id=="housing" and operation=="move_in": services.family.synchronize_homes()
	return result
