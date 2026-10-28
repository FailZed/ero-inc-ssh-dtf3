extends Node
## Main-game orchestration. Dialogic owns narrative; Simulation owns free-play rules.
## Existing save slots already serialize World variables. No slot implementation is replaced.
signal changed
signal phase_changed(phase: String)
signal notification(text: String)
signal panel_requested(id: String)
signal guide_changed
signal story_requested(timeline: String)
signal intimacy_scene_requested(request: Dictionary)
const Simulation = preload("res://scripts/gameplay/main_simulation.gd")
const Setup = preload("res://scripts/mechanics/setup_config.gd")
const InventoryBridge = preload("res://scripts/mechanics/adapters/quest_inventory_controller.gd")
const Presentation = preload("res://scripts/gameplay/presentation.gd")
const Guide = preload("res://scripts/gameplay/guided_story.gd")
const SandboxFlow = preload("res://scripts/gameplay/sandbox_flow.gd")
var simulation
var configuration: Dictionary = Setup.defaults()
var phase := "story"
var story_flags: Dictionary = {}
var _pending_configuration: Dictionary = {}
var _syncing := false
var _inventory_bridge: Node
var _log: Array = []
var restore_error := ""
var mini_elapsed_ms := 0.0

func _ready() -> void:
	_inventory_bridge = InventoryBridge.new()
	add_child(_inventory_bridge)
	_new_simulation()
	GameSession.game_time_reset.connect(_on_time_reset)
	GameSession.game_time_advanced.connect(_on_time_advanced)
	LocationManager.set_travel_guard(_guard_legacy_travel)
	Dialogic.signal_event.connect(_on_story_signal)
	GameSession.set_game_time_mode("actions")

func _new_simulation() -> void:
	simulation = make_simulation()
	simulation.reset(GameSession.get_character_profile())
	simulation.state.clock = Simulation.calendar.snapshot(int(GameSession.get_game_time_snapshot().total_minutes))
	simulation.command("preferences", "customize", {"values": configuration.custom}) if configuration.difficulty == "custom" else simulation.command("preferences", "difficulty", {"id": configuration.difficulty})
	simulation.command("population", "configure", {"values": configuration.population})
	simulation.command("population", "generate")
	_bind_npc_art()
	_inventory_bridge.bind(simulation)
	simulation.domain_event.connect(_on_domain_event)

func make_simulation():
	var extensions := Presentation.extensions()
	var personality := Setup.personality_defaults()
	for key in personality: personality[key] = int(configuration.get("personality", {}).get(key, personality[key]))
	extensions["human_generation"] = {"population": personality}
	return Simulation.new(int(configuration.seed), extensions)

func begin_new_game(config: Dictionary) -> Error:
	var prepared := config.duplicate(true)
	# The story creates its hero later at the mirror. Laboratory allocations must
	# not consume the pre-story budget or reject a valid low-point custom world.
	prepared.profile = Setup.defaults().profile
	for stat in Setup.STATS: prepared.profile.stats[stat] = 5
	var valid: Dictionary = Setup.validate(prepared)
	if not valid.ok: return ERR_INVALID_PARAMETER
	_pending_configuration = prepared
	return GameSession.start_new_game()

func _on_time_reset(_snapshot: Dictionary) -> void:
	if _syncing: return
	var world: Dictionary = Dialogic.VAR.var_storage.get("World", {})
	var saved: Dictionary = world.get("gameplay", {})
	restore_error = ""
	if not _pending_configuration.is_empty():
		configuration = _pending_configuration.duplicate(true)
		_pending_configuration.clear()
		if is_sandbox():
			_syncing = true
			GameSession.set_game_time_total_minutes(480)
			_syncing = false
		phase = "story"
		story_flags = {"lyra":"help", "cosplay":"approach", "oliver":"help", "seating":"together", "assistant":"volunteer", "subject":"computing", "sport":"running", "asked_cosplay":"no", "asked_parents":"no", "asked_school":"no"}
		_log.clear()
		_new_simulation()
		simulation.reset({"appearance": GameSession.CHARACTER_APPEARANCE_DEFAULTS})
		simulation.state.clock = Simulation.calendar.snapshot(int(GameSession.get_game_time_snapshot().total_minutes))
		_apply_configuration()
		if is_sandbox(): story_flags = {"sandbox":true,"modal":"creator"}
	elif not saved.is_empty():
		configuration = world.get("gameplay_setup", Setup.defaults()).duplicate(true)
		_new_simulation()
		var restored: Dictionary = simulation.restore_snapshot(saved)
		if not restored.ok:
			restore_error = str(restored.error)
			notification.emit(Presentation.error(restore_error))
			phase = "story"
			phase_changed.emit(phase)
			return
		phase = str(world.get("gameplay_phase", "story"))
		story_flags = world.get("story_flags", {}).duplicate(true)
		_log = world.get("gameplay_log", []).duplicate(true)
	else:
		# Old slots remain readable and stay in their authored story. No invented unlock.
		phase = "story"
		configuration = Setup.defaults()
		story_flags.clear()
		_new_simulation()
	GameSession.set_game_time_mode("actions")
	mini_elapsed_ms = float(simulation.state.encounters.game.get("elapsed_ms", 0))
	_bind_npc_art()
	_checkpoint()
	phase_changed.emit(phase)
	changed.emit()

func _on_time_advanced(previous: int, current: int) -> void:
	if _syncing or simulation == null: return
	if phase == "free_roam":
		var remaining := current - previous
		while remaining > 0:
			var step := mini(remaining, 43200)
			var result: Dictionary = simulation.command("clock", "advance", {"minutes": step})
			if not result.ok:
				restore_error = str(result.error)
				notification.emit("Не удалось продолжить жизнь города: " + Presentation.error(restore_error))
				return
			remaining -= step
	else:
		simulation.state.clock = Simulation.calendar.snapshot(current)
	_checkpoint()
	changed.emit()

func execute(module_id: String, operation: String, args: Dictionary = {}) -> Dictionary:
	if phase != "free_roam": return {"ok": false, "error": "story_locked"}
	if not restore_error.is_empty(): return {"ok": false, "error": "incompatible_save"}
	var before := int(simulation.state.clock.total_minutes)
	var result: Dictionary = simulation.command(module_id, operation, args)
	if result.ok:
		if module_id == "encounters" and operation == "game_start": mini_elapsed_ms = 0.0
		_syncing = true
		GameSession.advance_game_time(int(simulation.state.clock.total_minutes) - before)
		_syncing = false
		var location := str(simulation.state.world.location)
		if LocationManager.current_location_id != location:
			LocationManager.previous_location_id = LocationManager.current_location_id
			LocationManager.current_location_id = location
			LocationManager.location_changed.emit(location)
		_track_objectives(module_id, operation, args)
		_checkpoint()
		GameSession._mark_autosave_progress()
		changed.emit()
	else:
		notification.emit(Presentation.error(str(result.error)))
	return result

func _track_objectives(module_id: String, operation: String, _args: Dictionary) -> void:
	# Progress is driven by successful actions, never by an exposed progress button.
	var practiced := module_id == "activities" and operation == "practice"
	practiced = practiced or (module_id == "actions" and operation == "perform" and _args.get("id","") == "exercise")
	if practiced and simulation.state.journal.quests.get("first_steps", {}).get("status", "") == "active":
		simulation.command("events", "progress", {"id": "first_steps", "objective": "practice", "amount": 1})

func _on_profile_changed(profile: Dictionary) -> void:
	if simulation == null or phase != "story": return
	simulation.state.player.name = str(profile.full_name)
	simulation.state.player.appearance = profile.appearance.duplicate(true)
	for stat in profile.stats: simulation.state.player.stats[stat] = profile.stats[stat]
	_checkpoint()
	changed.emit()

func creation_budget() -> int:
	return Setup.point_budget(configuration)

func is_sandbox() -> bool:
	return configuration.get("mode", "story") == "sandbox"

func open_sandbox() -> Dictionary:
	if not is_sandbox() or phase != "story": return {"ok":false,"error":"sandbox_unavailable"}
	return SandboxFlow.begin(self)

func apply_curriculum(subjects: Array, sport: String) -> bool:
	var Curriculum = preload("res://scripts/gameplay/curriculum.gd")
	if phase != "story" or subjects.size() < 2 or subjects.size() > 4 or not sport in Curriculum.SPORTS: return false
	var unique := {}
	for id in subjects:
		if not id in Curriculum.SUBJECTS or unique.has(id): return false
		unique[id] = true
	story_flags.subjects = subjects.duplicate()
	story_flags.sport = sport
	for id in Curriculum.SUBJECTS: simulation.state.world.flags["subject_"+id] = id in subjects
	_checkpoint()
	return true

func plan_family(id: String) -> Dictionary:
	if phase != "free_roam" or not simulation.state.social.npcs.has(id): return {"ok":false,"error":"story_locked"}
	var npc: Dictionary = simulation.state.social.npcs[id]
	var relation: Dictionary = simulation.services.social.relationship(id,"player")
	if npc.location != simulation.state.world.location: return {"ok":false,"error":"npc_not_present"}
	if int(npc.age) < 18 or int(simulation.state.player.age) < 18: return {"ok":false,"error":"adults_only"}
	if "romance" in simulation.state.preferences.disabled_tags: return {"ok":false,"error":"content_disabled"}
	var reason: String = simulation.services.npc_relationships.blocked("player", id, "court")
	if not reason.is_empty(): return {"ok":false,"error":reason}
	var bond: Dictionary = simulation.services.npc_relationships.view(id,"player")
	if relation.status != "partner" or float(bond.trust) < 60 or float(bond.comfort) < 40: return {"ok":false,"error":"family_requirements"}
	var available: Dictionary = simulation.services.social_rules.availability(id, true)
	if not available.ok: return available
	return execute("intimacy","begin",{"id":id})

func _apply_configuration() -> void:
	simulation.state.player.age = int(configuration.profile.age)
	for tag in configuration.get("content", {}): simulation.command("preferences", "content_tag", {"id": tag, "enabled": configuration.content[tag]})
	simulation.command("preferences", "customize", {"values": configuration.custom}) if configuration.difficulty == "custom" else simulation.command("preferences", "difficulty", {"id": configuration.difficulty})
	simulation.command("population", "configure", {"values": configuration.population})
	simulation.command("population", "generate")
	for id in configuration.get("needs",{}): simulation.command("growth","need_toggle",{"id":id,"enabled":configuration.needs[id]})
	_bind_npc_art()

func _bind_npc_art() -> void:
	var Visuals = preload("res://scripts/portraits/character_visuals.gd")
	for actor in simulation.state.social.npcs.values():
		if not Visuals.profile_valid(actor.appearance.get("visual",{})):
			actor.appearance.visual = Visuals.generate(actor,int(configuration.seed))
	var Library = preload("res://scripts/portraits/npc_portrait_library.gd")
	var entries: Array = Library.entries()
	if entries.is_empty(): return
	var used := {}
	for actor in simulation.state.social.npcs.values():
		var assigned := str(actor.appearance.get("portrait_id",""))
		if not assigned.is_empty(): used[assigned] = true
	var ids: Array = simulation.state.social.npcs.keys()
	ids.sort()
	for actor_id in ids:
		# A generic portrait pool must not recast authored story characters.
		if not str(actor_id).begins_with("resident_"): continue
		var actor: Dictionary = simulation.state.social.npcs[actor_id]
		if not str(actor.appearance.get("portrait_id","")).is_empty(): continue
		var id: String = Library.choose(actor,entries,used)
		if not id.is_empty():
			actor.appearance.portrait_id = id
			used[id] = true

func _on_story_signal(argument: String) -> void:
	if is_sandbox(): return
	if argument.begins_with("guide:"):
		begin_guide(argument.trim_prefix("guide:"))
	elif argument.begins_with("story_flag:"):
		var parts := argument.split(":", true, 2)
		if parts.size() == 3: story_flags[parts[1]] = parts[2]
		_checkpoint()
	elif argument == "chapter_one_complete":
		call_deferred("complete_chapter_one")
	elif argument == "story_university_morning":
		set_story_date(9, 1, 11, 0)
	elif argument == "story_mirror_night":
		set_story_date(8, 31, 3, 20)

func begin_guide(id: String) -> void:
	if phase != "story" or not Guide.STAGES.has(id): return
	story_flags.guide_stage = id
	story_flags.guide_location = str(Guide.STAGES[id].start)
	_checkpoint()
	guide_changed.emit()

func guided_travel(destination: String) -> Dictionary:
	var stage: Dictionary = Guide.STAGES.get(str(story_flags.get("guide_stage","")),{})
	if phase != "story" or stage.is_empty(): return {"ok":false,"error":"story_locked"}
	var source: Dictionary = Guide.PLACES.get(str(story_flags.guide_location),{})
	if not destination in source.get("exits",[]) or not destination in stage.allowed: return {"ok":false,"error":"story_route_locked"}
	story_flags.guide_location = destination
	_checkpoint()
	guide_changed.emit()
	return {"ok":true}

func inspect_story_object(id: String) -> Dictionary:
	var stage: Dictionary = Guide.STAGES.get(str(story_flags.get("guide_stage","")),{})
	if phase != "story" or stage.is_empty(): return {"ok":false,"error":"story_locked"}
	var location := str(story_flags.guide_location)
	if not Guide.PLACES[location].objects.has(id): return {"ok":false,"error":"unknown_object"}
	if not story_flags.has("inspected"): story_flags.inspected = {}
	story_flags.inspected[location+":"+id] = true
	if location == stage.goal_place and id == stage.goal:
		if not story_flags.has("completed_tasks"): story_flags.completed_tasks = []
		if not stage.objective in story_flags.completed_tasks: story_flags.completed_tasks.append(stage.objective)
		if stage.has("next"):
			begin_guide(str(stage.next))
		else:
			story_flags.guide_stage = ""
			_checkpoint()
			story_requested.emit(str(stage.timeline))
		return {"ok":true,"text":""}
	_checkpoint()
	var text := str(Guide.INSPECTIONS.get(id,"Сейчас здесь нет ничего необычного."))
	if id == "clock" and str(story_flags.guide_stage).begins_with("morning"): text = "На часах 11:00. На сборы и дорогу остался час."
	return {"ok":true,"text":text}

func story_crowd(location: String) -> Array:
	# Reuse the initial population. Selection is stable and consumes no simulation RNG.
	if not location in ["street","campus_hall","campus_corridor","campus_courtyard"]: return []
	var eligible: Array = []
	for id in simulation.state.social.npcs:
		if not str(id).begins_with("resident_"): continue
		var npc: Dictionary = simulation.state.social.npcs[id]
		if location in ["campus_hall","campus_corridor"] and npc.cohort != "learner": continue
		eligible.append(id)
	eligible.sort()
	if eligible.is_empty(): return []
	var offset := posmod(int(configuration.seed) + location.hash(),eligible.size())
	var result: Array = []
	for index in range(mini(3,eligible.size())): result.append(eligible[(offset+index)%eligible.size()])
	return result

func talk_to_story_npc(id: String, topic: String = "introduce") -> Dictionary:
	if phase != "story" or not id in story_crowd(str(story_flags.get("guide_location",""))): return {"ok":false,"error":"npc_not_present"}
	if not topic in ["introduce","directions","day"]: return {"ok":false,"error":"unknown_interaction"}
	var npc: Dictionary = simulation.state.social.npcs[id]
	if not story_flags.has("story_met"): story_flags.story_met = []
	var first: bool = not id in story_flags.story_met
	if first:
		var contact: Dictionary = simulation.command("social","contact",{"id":id})
		if not contact.ok: return contact
		simulation.command("social","relationship",{"id":id,"changes":{"trust":2,"affinity":2}})
		simulation.services.social.remember(id,"story_meeting",{"place":str(story_flags.guide_location)})
		story_flags.story_met.append(id)
	var text := ""
	match topic:
		"introduce": text = "«Меня зовут %s. Приятно познакомиться». Контакт добавлен в телефон." % npc.name if first else "«Мы уже знакомились. %s». Собеседник вас помнит." % npc.name
		"directions": text = "«213? Второй этаж, левое крыло. Первая цифра — этаж. И не бойся спросить дежурного»."
		"day": text = "«Здесь столько всего происходит. Надеюсь найти компанию для учёбы и занятий»." if int(npc.traits.sociability) >= 50 else "«Пока хочу спокойно осмотреться. Слишком много новых людей сразу»."
	_checkpoint()
	changed.emit()
	return {"ok":true,"text":text,"first_meeting":first}

func set_story_date(month: int, day: int, hour: int, minute: int) -> void:
	if phase != "story": return
	var date := {"year": 2026, "month": month, "day": day, "hour": hour, "minute": minute, "second": 0}
	var total := int((Time.get_unix_time_from_datetime_dict(date) - Time.get_unix_time_from_datetime_dict(Simulation.calendar.EPOCH)) / 60)
	_syncing = true
	GameSession.set_game_time_total_minutes(total)
	_syncing = false
	simulation.state.clock = Simulation.calendar.snapshot(total)
	_checkpoint()
	changed.emit()

func complete_chapter_one() -> void:
	if is_sandbox(): return
	if phase == "free_roam" or not restore_error.is_empty(): return
	set_story_date(9, 1, 19, 0)
	# Starting apartment is paid for by parents in the script. Next bill is a month away.
	var property := {"owned": false, "equipment": {"stove": 1}, "tenants": [], "next_bill": Simulation.calendar.add_months(int(simulation.state.clock.total_minutes), 1), "arrears": 0, "rent_income": 0, "tenant_arrears": {}, "original_homes": {}, "layout": {}}
	simulation.state.housing = {"properties": {"apartment": property}, "residence": "apartment"}
	simulation.state.world.location = "bedroom"
	simulation.state.world.equipment = ["stove"]
	simulation.command("inventory", "add", {"id": "meal", "quantity": 3})
	simulation.command("inventory", "add", {"id": "book", "quantity": 1})
	simulation.state.player.points = maxi(0, creation_budget() - _creation_spent())
	_seed_story_contacts()
	_start_npc_life()
	if not restore_error.is_empty(): return
	for npc in simulation.state.social.npcs.values(): simulation.services.social._schedule(npc)
	simulation.command("events", "start_quest", {"id": "first_steps"})
	simulation.state.world.flags.chapter_one_complete = true
	phase = "free_roam"
	LocationManager.current_location_id = "bedroom"
	_checkpoint()
	phase_changed.emit(phase)
	changed.emit()
	notification.emit("Глава 1 завершена. Город открыт: выбирайте место, занятие и людей, с которыми хотите провести время.")

func _start_npc_life() -> void:
	# The authored chapter jumps between dates. Start life at the actual city opening.
	var prior: Dictionary = simulation.state.social.relationships.duplicate(true)
	var enabled: Dictionary = simulation.command("npc_agency", "enable")
	if not enabled.ok:
		restore_error = str(enabled.error)
		return
	for key in prior:
		var ids := str(key).split("|")
		if ids.size() != 2 or not "player" in ids: continue
		var id := str(ids[1] if ids[0] == "player" else ids[0])
		var bond: Dictionary = simulation.services.npc_relationships._bond(id, "player")
		bond.trust = float(prior[key].trust)
		bond.affection = float(prior[key].affinity)
		bond.comfort = maxf(0, float(prior[key].affinity))
		bond.closeness = minf(20, maxf(0, float(prior[key].affinity)))
		simulation.services.npc_relationships._project(id, "player")
	var cast := {
		"asuka": {"goal": "community", "facets": {"sociability": 78, "social_boldness": 75, "creativity": 82, "sincerity": 72}},
		"oliver": {"goal": "mastery", "facets": {"social_boldness": 30, "inquisitiveness": 82, "gentleness": 75, "diligence": 70}},
		"ellie": {"goal": "mastery", "facets": {"organization": 85, "diligence": 82, "social_boldness": 68, "fairness": 78}}}
	for id in cast:
		if not simulation.state.social.npcs.has(id): continue
		simulation.command("npc_personalities", "configure", {"id": id, "facets": cast[id].facets})
		simulation.command("npc_agency", "set_aspiration", {"id": id, "goal": cast[id].goal})
		if id == "oliver" and story_flags.get("oliver", "") in ["help", "quiet"]:
			simulation.services.npc_agency.record_social_experience(simulation.state.social.npcs[id], "supported", "player")
	simulation.services.npc_agency._build_index()
	for npc in simulation.state.social.npcs.values():
		if npc.mind.active.is_empty(): simulation.services.npc_agency._choose(npc)

func _creation_spent() -> int:
	var spent := 0
	for id in GameSession.CHARACTER_STAT_KEYS: spent += int(simulation.state.player.stats[id]) - 5
	return spent

func _seed_story_contacts() -> void:
	# Authored cast is separate from random population. Childhood Lyra never becomes an adult random NPC.
	for id in ["asuka", "oliver"]:
		if id == "oliver" and story_flags.get("oliver", "") == "leave": continue
		simulation.command("social", "generate", {"id": id, "template":"story_student", "name": "Асука" if id == "asuka" else "Оливер", "age": 23, "appearance": {"gender": "female" if id == "asuka" else "male", "morphology": "human" if id == "asuka" else "semi_furry", "has_tail": id == "oliver"}})
		simulation.command("appearance", "customize", {"target":id,"features":{"gender":"female" if id == "asuka" else "male"}})
		simulation.command("social", "contact", {"id": id})
		simulation.command("social", "relationship", {"id": id, "changes": {"trust": 15, "affinity": 10}})
	simulation.command("social","generate",{"id":"ellie","template":"story_student","name":"Элли","age":23,"appearance":{"gender":"female","morphology":"semi_furry","has_tail":false}})
	simulation.command("social","contact",{"id":"ellie"})
	simulation.command("social","relationship",{"id":"ellie","changes":{"trust":10,"affinity":5}})
	_bind_npc_art()

func _guard_legacy_travel(_id: String) -> Dictionary:
	# The free-play map stays inside game.tscn so narrative and save context survive travel.
	return {"ok": false, "error": "use_gameplay_map" if phase == "free_roam" else "story_locked"}

func _on_domain_event(event: Dictionary) -> void:
	if event.get("kind", "") == "intimacy_scene_requested": intimacy_scene_requested.emit(event.data.duplicate(true))
	var text := Presentation.event_text(event, simulation)
	if text.is_empty(): return
	_log.append({"minute": int(event.get("minute", simulation.state.clock.total_minutes)), "text": text})
	while _log.size() > 80: _log.pop_front()
	notification.emit(text)

func log_entries() -> Array:
	return _log.duplicate(true)

func _checkpoint() -> void:
	if simulation == null or not restore_error.is_empty(): return
	var world: Dictionary = Dialogic.VAR.var_storage.get("World", {}).duplicate(true)
	world.gameplay = simulation.export_snapshot()
	world.gameplay_setup = configuration.duplicate(true)
	world.gameplay_phase = phase
	world.story_flags = story_flags.duplicate(true)
	world.gameplay_log = _log.duplicate(true)
	Dialogic.VAR.var_storage["World"] = world
