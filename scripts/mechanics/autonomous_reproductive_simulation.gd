extends "res://scripts/mechanics/reproductive_simulation.gd"
## Autonomous NPC-to-NPC life uses the same reproductive and family contracts.
const NpcReproduction = preload("res://scripts/mechanics/npc_reproduction.gd")
const NpcReproductionCheck = preload("res://scripts/mechanics/core/npc_reproductive_validation.gd")
var previous_autonomy_catalog: Dictionary = {}

func _load_catalog() -> Dictionary:
	var result := super._load_catalog()
	var extra: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/mechanics/npc_reproduction.json"))
	for group in extra: result[group] = extra[group]
	return result

func _init(random_seed: int = 1, extensions: Dictionary = {}) -> void:
	super(random_seed, extensions)
	previous_autonomy_catalog = catalog.duplicate(true)
	previous_autonomy_catalog.erase("npc_reproduction_rules")
	services["npc_reproduction"] = NpcReproduction.new(self)
	state_restored.connect(_initialize_autonomy)
	_initialize_autonomy()
	var error := NpcReproductionCheck.catalog_error(catalog)
	if not error.is_empty(): configuration_error = error

func _initialize_autonomy() -> void:
	if not state.has("npc_reproduction"): state.npc_reproduction = NpcReproduction.defaults()

func prepare_autonomy(snapshot: Dictionary) -> void:
	if snapshot.get("state") is Dictionary and not snapshot.state.has("npc_reproduction"):
		snapshot.state.npc_reproduction = NpcReproduction.defaults()
	snapshot.npc_reproduction_schema = 1

func prepare_legacy_reproduction(snapshot: Dictionary) -> void:
	super.prepare_legacy_reproduction(snapshot)
	prepare_autonomy(snapshot)

func export_snapshot() -> Dictionary:
	var snapshot := super.export_snapshot()
	snapshot.npc_reproduction_schema = 1
	return snapshot

func restore_snapshot(snapshot: Dictionary) -> Dictionary:
	var prepared := snapshot.duplicate(true)
	var hash_value := str(prepared.get("catalog_hash", ""))
	if not prepared.has("npc_reproduction_schema"):
		if hash_value == JSON.stringify(previous_autonomy_catalog).sha256_text():
			prepared.catalog_hash = JSON.stringify(catalog).sha256_text()
			prepare_autonomy(prepared)
		elif hash_value in [JSON.stringify(previous_extended_catalog).sha256_text(), JSON.stringify(previous_catalog).sha256_text()]:
			prepare_autonomy(prepared)
	if prepared.get("npc_reproduction_schema") != 1: return Rules.fail("unsupported_npc_reproduction_schema")
	return super.restore_snapshot(prepared)

func validate_state(candidate: Dictionary) -> Dictionary:
	var result := super.validate_state(candidate)
	if not result.ok: return result
	var error := NpcReproductionCheck.state_error(candidate, catalog)
	return Rules.fail(error) if not error.is_empty() else result

func after_command(module_id: String, operation: String, args: Dictionary, result: Dictionary, before: Dictionary) -> Dictionary:
	result = super.after_command(module_id, operation, args, result, before)
	if result.ok: services.npc_reproduction.recheck()
	return result
