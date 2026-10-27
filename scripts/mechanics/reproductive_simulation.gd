extends "res://scripts/mechanics/extended_simulation.gd"
## Non-graphic encounter and reproductive state, independent of scene content.
const Reproduction = preload("res://scripts/mechanics/reproduction.gd")
const Intimacy = preload("res://scripts/mechanics/intimacy.gd")
const ChildSupport = preload("res://scripts/mechanics/child_support.gd")
const ReproductiveLifecycle = preload("res://scripts/mechanics/reproductive_lifecycle.gd")
const ReproductiveCheck = preload("res://scripts/mechanics/core/reproductive_validation.gd")
const PregnancyWellbeing = preload("res://scripts/mechanics/pregnancy_wellbeing.gd")
const PregnancyWellbeingCheck = preload("res://scripts/mechanics/core/pregnancy_wellbeing_validation.gd")
const AdultHealth = preload("res://scripts/mechanics/adult_health.gd")
const AdultHealthCheck = preload("res://scripts/mechanics/core/adult_health_validation.gd")
var previous_extended_catalog: Dictionary = {}

func _load_catalog() -> Dictionary:
	var result := super._load_catalog()
	previous_extended_catalog = result.duplicate(true)
	var extra: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/mechanics/reproduction.json"))
	for group in extra:
		if not result.has(group): result[group] = {}
		result[group].merge(extra[group], true)
	result.locations.bedroom["private"] = true
	result.locations.global_map.routes.clinic = {"minutes":15}
	if result.has("shops") and result.shops.has("market"):
		for item in ["barrier_protection", "contraceptive_pill", "emergency_contraception"]:
			result.shops.market.stock[item] = 100
	return result

func _init(random_seed: int = 1, extensions: Dictionary = {}) -> void:
	super(random_seed, extensions)
	for group in extensions:
		if previous_extended_catalog.has(group) and extensions[group] is Dictionary:
			previous_extended_catalog[group].merge(extensions[group].duplicate(true), true)
	# Main presentation extensions replace entire shop/route definitions.
	catalog.locations.bedroom["private"] = true
	catalog.locations.global_map.routes.clinic = {"minutes":15}
	for item in ["barrier_protection", "contraceptive_pill", "emergency_contraception"]:
		if catalog.shops.has("market"): catalog.shops.market.stock[item] = 100
	services["reproduction"] = Reproduction.new(self)
	services["intimacy"] = Intimacy.new(self)
	services["child_support"] = ChildSupport.new(self)
	services["pregnancy_wellbeing"] = PregnancyWellbeing.new(self)
	services["adult_health"] = AdultHealth.new(self)
	services.lifecycle = ReproductiveLifecycle.new(self)
	state_restored.connect(_initialize_reproduction)
	_initialize_reproduction()
	var error := ReproductiveCheck.catalog_error(catalog)
	if not error.is_empty(): configuration_error = error

func _initialize_reproduction() -> void:
	if not state.has("reproduction"): state.reproduction = Reproduction.defaults()
	if not state.has("intimacy"): state.intimacy = Intimacy.defaults()
	if not state.has("child_support"): state.child_support = ChildSupport.defaults()
	services.pregnancy_wellbeing.initialize()
	services.adult_health.initialize()

func before_command(module_id: String, operation: String, args: Dictionary) -> Dictionary:
	if module_id == "lifecycle" and operation == "start" and args.get("id", "") == "pregnancy" and "pregnancy" in state.preferences.disabled_tags: return Rules.fail("content_disabled")
	var allowed: Dictionary = services.intimacy.command_allowed(module_id, operation)
	return super.before_command(module_id, operation, args) if allowed.ok else allowed

func after_command(module_id: String, operation: String, args: Dictionary, result: Dictionary, before: Dictionary) -> Dictionary:
	result = super.after_command(module_id, operation, args, result, before)
	if result.ok:
		services.intimacy.recheck()
		services.child_support.synchronize()
		services.pregnancy_wellbeing.observe(module_id,operation,args,before)
		services.adult_health.observe(module_id,operation,args,before,result)
	return result

func validate_state(candidate: Dictionary) -> Dictionary:
	var result := super.validate_state(candidate)
	if not result.ok: return result
	var error := ReproductiveCheck.state_error(candidate, catalog)
	if error.is_empty(): error = PregnancyWellbeingCheck.state_error(candidate)
	if error.is_empty(): error = AdultHealthCheck.state_error(candidate)
	return Rules.fail(error) if not error.is_empty() else result

func export_snapshot() -> Dictionary:
	var result := super.export_snapshot()
	result.reproduction_schema = 1
	return result

func prepare_legacy_reproduction(snapshot: Dictionary) -> void:
	if not snapshot.get("state") is Dictionary: return
	for pair in [["family", Family.defaults()], ["digital", Digital.defaults()], ["collection", Collections.defaults()], ["reproduction", Reproduction.defaults()], ["intimacy", Intimacy.defaults()], ["child_support", ChildSupport.defaults()]]:
		if not snapshot.state.has(pair[0]): snapshot.state[pair[0]] = pair[1]
	snapshot.reproduction_schema = 1

func restore_snapshot(snapshot: Dictionary) -> Dictionary:
	var prepared := snapshot.duplicate(true)
	var old_hash := str(prepared.get("catalog_hash", ""))
	if not prepared.has("reproduction_schema") and old_hash in [JSON.stringify(previous_extended_catalog).sha256_text(), JSON.stringify(previous_catalog).sha256_text()]:
		prepared.catalog_hash = JSON.stringify(catalog).sha256_text()
		prepare_legacy_reproduction(prepared)
	if prepared.get("reproduction_schema") != 1: return Rules.fail("unsupported_reproduction_schema")
	return super.restore_snapshot(prepared)
