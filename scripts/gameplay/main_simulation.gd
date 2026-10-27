extends "res://scripts/mechanics/autonomous_reproductive_simulation.gd"
## Main-game extensions remain outside the independent mechanics/parity runtime.
const PlayerNeeds = preload("res://scripts/gameplay/player_needs.gd")
const ActionPolicy = preload("res://scripts/gameplay/action_policy.gd")
const PlayerCharacter = preload("res://scripts/gameplay/player_character.gd")
const PlayerRelationships = preload("res://scripts/gameplay/player_relationships.gd")
const PlayerInstitutions = preload("res://scripts/gameplay/player_institutions.gd")
const PlayerSocialRules = preload("res://scripts/gameplay/player_social_rules.gd")
const City = preload("res://scripts/gameplay/city_layout.gd")
const CityWorld = preload("res://scripts/gameplay/city_world.gd")
const CityHousing = preload("res://scripts/gameplay/city_housing.gd")
const CityAgency = preload("res://scripts/gameplay/city_agency.gd")
const CityDialogue = preload("res://scripts/gameplay/city_dialogue.gd")
const PersonalStories = preload("res://scripts/mechanics/npc_stories.gd")
const Livelihood = preload("res://scripts/mechanics/livelihood.gd")
const LivelihoodCheck = preload("res://scripts/mechanics/core/livelihood_validation.gd")
const Growth = preload("res://scripts/mechanics/growth.gd")
const MAIN_SCHEMA := 8
var action_context: Dictionary = {}

func _load_catalog() -> Dictionary:
	var result := super._load_catalog()
	for file in ["npc_stories","livelihood","growth"]:
		var extra: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/mechanics/%s.json" % file))
		for key in extra:
			if key == "skills": result.skills.merge(extra.skills,true)
			else: result[key] = extra[key]
	result.difficulties.custom.minigame_floor = 0.70
	result.difficulties.custom.skill_help_cap = 0.28
	result.professions.journalism.publication_slots_at = [0,2,3,4,5]
	return result

func _init(random_seed: int = 1, extensions: Dictionary = {}) -> void:
	super(random_seed,extensions)
	City.apply_catalog(catalog)
	services["npc_stories"] = PersonalStories.new(self)
	services["livelihood"] = Livelihood.new(self)
	services["growth"] = Growth.new(self)
	for id in ["npc_stories","livelihood","growth"]:
		state_restored.connect(services[id].initialize)
		services[id].initialize()
	services["needs"] = PlayerNeeds.new(self)
	services.character = PlayerCharacter.new(self)
	services.encounters = preload("res://scripts/gameplay/player_encounters.gd").new(self)
	services.preferences = preload("res://scripts/gameplay/player_preferences.gd").new(self)
	services.careers = preload("res://scripts/gameplay/player_careers.gd").new(self)
	services.npc_relationships = PlayerRelationships.new(self)
	services.institutions = PlayerInstitutions.new(self)
	services.social_rules = PlayerSocialRules.new(self)
	services.world = CityWorld.new(self)
	services.housing = CityHousing.new(self)
	services.npc_agency = CityAgency.new(self)
	services.npc_dialogue = CityDialogue.new(self)
	for error in [Validation.catalog_error(catalog),PersonalStories.catalog_error(catalog),LivelihoodCheck.catalog_error(catalog),Growth.catalog_error(catalog)]:
		if not error.is_empty(): configuration_error = error

func before_command(module_id: String, operation: String, args: Dictionary) -> Dictionary:
	if not state.livelihood.pending.is_empty() and not (module_id == "livelihood" and operation in ["input","cancel"]): return Rules.fail("finish_work_session")
	var inherited := super.before_command(module_id, operation, args)
	if not inherited.ok: return inherited
	action_context = ActionPolicy.describe(self, module_id, operation, args)
	return ActionPolicy.check(self, module_id, operation, args, action_context)

func after_command(module_id: String, operation: String, args: Dictionary, result: Dictionary, before: Dictionary) -> Dictionary:
	var processed := ActionPolicy.complete(self, module_id, operation, args, result, before)
	if not processed.ok: return processed
	services.needs.after_action(module_id, operation, args, result, int(state.clock.total_minutes) - int(before.clock.total_minutes))
	services.needs.update_warnings()
	services.collections.poll()
	services.intimacy.recheck()
	services.child_support.synchronize()
	services.npc_reproduction.recheck()
	services.npc_stories.observe(module_id,operation,args,result)
	services.livelihood.observe(module_id,operation,args,result,before)
	services.growth.observe(module_id,operation,before)
	services.careers.synchronize()
	services.pregnancy_wellbeing.observe(module_id,operation,args,before)
	services.adult_health.observe(module_id,operation,args,before,result)
	return result

func finish_command() -> void:
	action_context = {}

func allowed_during_recovery(module_id: String, operation: String) -> bool:
	return (module_id == "livelihood" and operation in ["input","cancel"]) or (module_id == "growth" and operation == "need_toggle") or super.allowed_during_recovery(module_id, operation) or (module_id == "needs" and operation in ["sleep", "nap"])

func export_snapshot() -> Dictionary:
	var snapshot := super.export_snapshot()
	snapshot.main_schema = MAIN_SCHEMA
	return snapshot

func restore_snapshot(snapshot: Dictionary) -> Dictionary:
	if snapshot.get("main_schema") != MAIN_SCHEMA: return Rules.fail("unsupported_main_schema")
	if snapshot.get("catalog_hash","") != JSON.stringify(catalog).sha256_text(): return Rules.fail("catalog_mismatch")
	return super.restore_snapshot(snapshot)

func validate_state(candidate: Dictionary) -> Dictionary:
	var result := super.validate_state(candidate)
	if not result.ok: return result
	for check in [PersonalStories.state_error(candidate,catalog),LivelihoodCheck.state_error(candidate,catalog),Growth.state_error(candidate)]:
		if not check.is_empty(): return Rules.fail(check)
	for id in PlayerNeeds.DEFAULTS:
		if not candidate.player.needs.has(id): return Rules.fail("missing_need:"+id)
		var value: Variant = candidate.player.needs[id]
		if not _number(value) or float(value) < 0.0 or float(value) > 100.0: return Rules.fail("invalid_need:" + id)
	var warnings: Variant = candidate.player.get("need_warnings", {})
	if not warnings is Dictionary: return Rules.fail("invalid_need_warnings")
	for id in warnings:
		if not id in PlayerNeeds.DISPLAYED or not warnings[id] is bool: return Rules.fail("invalid_need_warning")
	var combat: Dictionary = candidate.encounters.combat
	if combat.has("previous_pin"):
		var pin: Variant = combat.previous_pin
		if not _number(pin) or float(pin) != int(pin) or float(pin) < 0.0: return Rules.fail("invalid_combat_pin")
	if combat.get("status","") == "active":
		if not is_equal_approx(float(combat.stamina.player),float(candidate.player.needs.energy)): return Rules.fail("inconsistent_combat_stamina")
		if not is_equal_approx(float(combat.stamina.npc),float(candidate.social.npcs[combat.npc].needs.energy)): return Rules.fail("inconsistent_combat_stamina")
	return result
