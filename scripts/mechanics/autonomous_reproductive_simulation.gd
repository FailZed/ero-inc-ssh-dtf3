extends "res://scripts/mechanics/reproductive_simulation.gd"
## Autonomous NPC-to-NPC life uses the same reproductive and family contracts.
const NpcReproduction = preload("res://scripts/mechanics/npc_reproduction.gd")
const NpcReproductionCheck = preload("res://scripts/mechanics/core/npc_reproductive_validation.gd")

func _load_catalog() -> Dictionary:
	var result := super._load_catalog()
	var extra: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/mechanics/npc_reproduction.json"))
	for group in extra: result[group] = extra[group]
	return result

func _init(random_seed: int = 1, extensions: Dictionary = {}) -> void:
	super(random_seed, extensions)
	services["npc_reproduction"] = NpcReproduction.new(self)
	state_restored.connect(_initialize_autonomy)
	_initialize_autonomy()
	var error := NpcReproductionCheck.catalog_error(catalog)
	if not error.is_empty(): configuration_error = error

func _initialize_autonomy() -> void:
	if not state.has("npc_reproduction"): state.npc_reproduction = NpcReproduction.defaults()

func export_snapshot() -> Dictionary:
	var snapshot := super.export_snapshot()
	snapshot.npc_reproduction_schema = 1
	return snapshot

func restore_snapshot(snapshot: Dictionary) -> Dictionary:
	if snapshot.get("npc_reproduction_schema") != 1: return Rules.fail("unsupported_npc_reproduction_schema")
	return super.restore_snapshot(snapshot)

func validate_state(candidate: Dictionary) -> Dictionary:
	var result := super.validate_state(candidate)
	if not result.ok: return result
	var error := NpcReproductionCheck.state_error(candidate, catalog)
	return Rules.fail(error) if not error.is_empty() else result

func after_command(module_id: String, operation: String, args: Dictionary, result: Dictionary, before: Dictionary) -> Dictionary:
	result = super.after_command(module_id, operation, args, result, before)
	if result.ok: services.npc_reproduction.recheck()
	return result
