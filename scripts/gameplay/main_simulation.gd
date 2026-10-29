extends "res://scripts/mechanics/autonomous_reproductive_simulation.gd"
## Main-game extensions remain outside the independent mechanics/parity runtime.
const PlayerNeeds = preload("res://scripts/gameplay/player_needs.gd")
const ActionPolicy = preload("res://scripts/gameplay/action_policy.gd")
const PlayerCharacter = preload("res://scripts/gameplay/player_character.gd")
const ProtagonistAppearance = preload("res://scripts/characters/protagonist_appearance.gd")
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
const Education = preload("res://scripts/mechanics/education_schedule.gd")
const Residents = preload("res://scripts/gameplay/city_residents.gd")
const PlaceContent = preload("res://scripts/gameplay/city_place_content.gd")
const Graph = preload("res://scripts/gameplay/city_graph.gd")
const Employment = preload("res://scripts/mechanics/npc_employment.gd")
const Companion = preload("res://scripts/gameplay/companion_interactions.gd")
const Computer = preload("res://scripts/mechanics/computer.gd")
const ComputerCheck = preload("res://scripts/mechanics/core/computer_validation.gd")
const Antagonism = preload("res://scripts/mechanics/antagonism.gd")
const AntagonismCheck = preload("res://scripts/mechanics/core/antagonism_validation.gd")
const MAIN_SCHEMA := 14
const RandomEvents = preload("res://scripts/gameplay/random_events.gd")
const RandomSocial = preload("res://scripts/gameplay/random_event_social.gd")
const RandomAgency = preload("res://scripts/gameplay/random_event_agency.gd")
var action_context: Dictionary = {}
var _city_base_catalog: Dictionary = {}
var _city_catalog_before: Dictionary = {}

func reset(profile: Dictionary = {}) -> void:
	if not _city_base_catalog.is_empty(): catalog = _city_base_catalog.duplicate(true)
	super.reset(profile)
	Education.apply_plan(state,true,[])
	state.world.flags.city_story_home = true
	if services.get("events") is RandomEvents:
		services.events.initialize()

func _load_catalog() -> Dictionary:
	var result := super._load_catalog()
	for file in ["npc_stories","livelihood","growth","work_banks","computer","antagonism"]:
		var extra: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/mechanics/%s.json" % file))
		for key in extra:
			if key == "skills": result.skills.merge(extra.skills,true)
			else: result[key] = extra[key]
	result.difficulties.custom.minigame_floor = 0.70
	result.difficulties.custom.skill_help_cap = 0.28
	result.professions.journalism.publication_slots_at = [0,2,3,4,5]
	var bound := City.apply_catalog(result)
	if not bound.ok:
		result.locations = {}
		return result
	result.npc_jobs = Employment.from_player_jobs(result)
	result.npc_jobs.south_grocer = result.npc_jobs.shop_assistant.duplicate(true)
	result.npc_jobs.south_grocer.location = "south_market"
	var people := Residents.apply_catalog(result)
	if not people.ok: result["city_catalog_error"] = {"message":str(people.error)}
	var objects := PlaceContent.read_file()
	if objects.ok:
		var content: Dictionary = objects.data.content
		var content_error := PlaceContent.validate(content,result.city_graph,result)
		if content_error.is_empty():
			result.actions.merge(PlaceContent.catalogue_actions(content),true)
			result.city_place_content = content
		else: result["city_catalog_error"] = {"message":content_error}
	else: result["city_catalog_error"] = {"message":str(objects.error)}
	result.quests.home_with_purpose.bindings.project.append({"module":"computer","operation":"deliver_project","result":{"completed":true}})
	result.quests.home_with_purpose.bindings.furnish.append({"module":"computer","operation":"upgrade"})
	return result

func _init(random_seed: int = 1, extensions: Dictionary = {}) -> void:
	super(random_seed,extensions)
	services["npc_stories"] = PersonalStories.new(self)
	services["livelihood"] = Livelihood.new(self)
	services["growth"] = Growth.new(self)
	for id in ["npc_stories","livelihood","growth"]:
		state_restored.connect(services[id].initialize)
		services[id].initialize()
	services["needs"] = PlayerNeeds.new(self)
	services["companion"] = Companion.new(self)
	services["computer"] = Computer.new(self)
	state_restored.connect(services.computer.initialize)
	services.computer.initialize()
	services["antagonism"] = Antagonism.new(self)
	state_restored.connect(services.antagonism.initialize)
	services.antagonism.initialize()
	services["planning"] = preload("res://scripts/gameplay/day_planning.gd").new(self)
	services.character = PlayerCharacter.new(self)
	services.encounters = preload("res://scripts/gameplay/player_encounters.gd").new(self)
	services.preferences = preload("res://scripts/gameplay/player_preferences.gd").new(self)
	services.careers = preload("res://scripts/gameplay/player_careers.gd").new(self)
	services.npc_relationships = PlayerRelationships.new(self)
	services.institutions = PlayerInstitutions.new(self)
	services.social_rules = PlayerSocialRules.new(self)
	services.world = CityWorld.new(self)
	services.housing = CityHousing.new(self)
	services.npc_agency = RandomAgency.new(self)
	services.social = RandomSocial.new(self)
	services.events = RandomEvents.new(self)
	services.events.initialize()
	services.npc_dialogue = CityDialogue.new(self)
	_city_base_catalog = catalog.duplicate(true)
	if catalog.has("city_catalog_error"): configuration_error = str(catalog.city_catalog_error.message)
	for error in [Validation.catalog_error(catalog),PersonalStories.catalog_error(catalog),LivelihoodCheck.catalog_error(catalog),Growth.catalog_error(catalog),ComputerCheck.catalog_error(catalog),AntagonismCheck.catalog_error(catalog)]:
		if not error.is_empty(): configuration_error = error

func before_command(module_id: String, operation: String, args: Dictionary) -> Dictionary:
	if module_id in ["social","population"] and operation == "generate": _city_catalog_before = catalog.duplicate(true)
	if (not state.computer.hack.is_empty() or not state.computer.broadcast.is_empty()) and module_id in ["digital","careers","economy","livelihood"]:
		return Rules.fail("computer_session_active")
	if not state.companion.active.is_empty() and not (module_id == "companion" and operation in ["finish","cancel"]) and not (module_id == "npc_relationships" and operation == "boundary"):
		return Rules.fail("finish_companion_moment")
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
	services.computer.observe(module_id,operation,args,result,before)
	services.careers.synchronize()
	services.pregnancy_wellbeing.observe(module_id,operation,args,before)
	services.adult_health.observe(module_id,operation,args,before,result)
	return result

func finish_command() -> void:
	super.finish_command()
	action_context = {}
	_city_catalog_before = {}

func allowed_during_recovery(module_id: String, operation: String) -> bool:
	if module_id == "computer" and operation in ["hack_abort","stream_finish"]: return true
	if module_id == "companion" and operation in ["cancel","finish"]: return true
	return (module_id == "livelihood" and operation in ["input","cancel"]) or (module_id == "growth" and operation == "need_toggle") or super.allowed_during_recovery(module_id, operation) or (module_id == "needs" and operation in ["sleep", "nap"])

func export_snapshot() -> Dictionary:
	var snapshot := super.export_snapshot()
	snapshot.main_schema = MAIN_SCHEMA
	snapshot.city_home_owners = City.dynamic_home_owners(catalog)
	return snapshot

func restore_snapshot(snapshot: Dictionary) -> Dictionary:
	if snapshot.get("main_schema") != MAIN_SCHEMA: return Rules.fail("unsupported_main_schema")
	if not snapshot.get("city_home_owners") is Array: return Rules.fail("invalid_city_home_owners")
	var candidate_catalog := _city_base_catalog.duplicate(true)
	var seen := {}
	for owner in snapshot.city_home_owners:
		if not owner is String or seen.has(owner): return Rules.fail("invalid_city_home_owners")
		seen[owner] = true
		var installed := City.install_home(candidate_catalog,owner)
		if not installed.ok: return installed
	if snapshot.get("catalog_hash","") != JSON.stringify(candidate_catalog).sha256_text(): return Rules.fail("catalog_mismatch")
	var previous_catalog := catalog
	catalog = candidate_catalog
	var restored := super.restore_snapshot(snapshot)
	if not restored.ok: catalog = previous_catalog
	return restored

func validate_state(candidate: Dictionary) -> Dictionary:
	var result := super.validate_state(candidate)
	if not result.ok: return result
	var appearance: Variant = candidate.player.get("appearance", {})
	if not appearance is Dictionary: return Rules.fail("invalid_player_appearance")
	if appearance.has("live2d") and not ProtagonistAppearance.validate_appearance(appearance.live2d):
		return Rules.fail("invalid_protagonist_live2d")
	var random_error := RandomEvents.state_error(candidate)
	if not random_error.is_empty(): return Rules.fail(random_error)
	if not candidate.world.flags.get("student_enrolled") is bool: return Rules.fail("invalid_education_status")
	for id in Education.SUBJECTS:
		var selected: Variant = candidate.world.flags.get("subject_"+id)
		if not selected is bool or (selected and not candidate.world.flags.student_enrolled): return Rules.fail("invalid_education_subject")
	var people_error := Residents.state_error(candidate,catalog)
	if not people_error.is_empty(): return Rules.fail(people_error)
	for check in [PersonalStories.state_error(candidate,catalog),LivelihoodCheck.state_error(candidate,catalog),Growth.state_error(candidate),ComputerCheck.state_error(candidate,catalog),AntagonismCheck.state_error(candidate,catalog)]:
		if not check.is_empty(): return Rules.fail(check)
	var companion_error := Companion.state_error(candidate)
	if not companion_error.is_empty(): return Rules.fail(companion_error)
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

func player_home_room(kind: String) -> String:
	return City.home_room(catalog,state,kind)

func player_home() -> String:
	return player_home_room("bedroom")

func room_kind(id: String) -> String:
	return City.room_kind(catalog,id)

func is_player_home_location(id: String) -> bool:
	return City.is_home_room(catalog,state,id)

func prepare_npc_template(id: String, args: Dictionary, template: Dictionary) -> Dictionary:
	if _busy and _city_catalog_before.is_empty(): _city_catalog_before = catalog.duplicate(true)
	var prepared := template.duplicate(true)
	var installed := City.install_home(catalog,id)
	if not installed.ok: return installed
	prepared.home = str(installed.data.id)
	for block in prepared.get("schedule",[]):
		if block.get("location") == "home": block.location = prepared.home
	return Rules.ok(prepared)

func generate_population(config: Dictionary) -> Dictionary:
	if state.world.flags.get(Residents.MARKER,{}).get("complete",false): return services.population.generate_batch(config)
	var planned := Residents.population_plan(config,_initial_seed)
	if not planned.ok: return planned
	var plan: Dictionary = planned.data
	if state.social.npcs.size()+int(plan.requested_count)>500: return Rules.fail("population_limit")
	var ids: Array = []
	if int(plan.random_settings.count)>0:
		var generated: Dictionary = services.population.generate_batch(plan.random_settings,false)
		if not generated.ok: return generated
		ids.append_array(generated.data.ids)
	var people := Residents.seed(self,config,_initial_seed)
	if not people.ok: return people
	ids.append_array(people.data.ids)
	return services.population.finish_batch(ids,plan.full_morphologies)

func rollback_command() -> void:
	if not _city_catalog_before.is_empty(): catalog = _city_catalog_before
