extends SceneTree
const Guide = preload("res://scripts/gameplay/guided_story.gd")
var _branch := 0
var _flee := false
var _teacher_right := false
var _difficulty := "normal"
var _points := 30
var _checks := 0
var _failures: Array[String] = []
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok: _failures.append(message); printerr("FAIL: ",message)
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--branch="): _branch = int(arg.trim_prefix("--branch="))
		if arg == "--flee": _flee = true
		if arg == "--teacher-right": _teacher_right = true
		if arg.begins_with("--difficulty="): _difficulty = arg.trim_prefix("--difficulty=")
		if arg.begins_with("--points="): _points = int(arg.trim_prefix("--points="))
	Engine.time_scale = 40
	var gameplay := root.get_node("Gameplay")
	var session := root.get_node("GameSession")
	var dialogic := root.get_node("Dialogic")
	var config := preload("res://scripts/mechanics/setup_config.gd").defaults()
	config.population.count = 8
	config.difficulty = _difficulty
	if _difficulty == "custom": config.custom.initial_points = _points
	check(gameplay.begin_new_game(config) == OK,"main new-game entry")
	var stages := {}
	var met := ""
	var last_marker := ""
	var started := Time.get_ticks_msec()
	var reloaded := false
	var seen_visuals := {}
	var flashback_clear := true
	for iteration in range(18000):
		await process_frame
		# A stalled regression test must never write an automatic user slot.
		session.pause_autosave_runtime()
		for character in dialogic.Portraits.get_joined_characters():
			if preload("res://scripts/portraits/character_visuals.gd").story_actor(character.get_identifier()).is_empty(): continue
			var holder: Node = dialogic.Portraits.get_character_node(character)
			if holder != null and holder.get_child_count()>0:
				var adapter: Node = holder.get_child(-1)
				if adapter.get("_view") != null and adapter._view.composition.get("ok",false): seen_visuals[character.get_identifier()] = true
			if dialogic.current_timeline != null and "flashback" in dialogic.current_timeline.get_identifier(): flashback_clear = false
		if gameplay.phase == "free_roam": break
		if Time.get_ticks_msec()-started > 55000: break
		var game := current_scene
		if game == null: continue
		if is_instance_valid(game._character_creation_modal) and game._character_creation_modal.visible:
			game._character_creation_modal._confirm_profile()
			continue
		if is_instance_valid(game._curriculum_window) and game._curriculum_window.visible:
			game._curriculum_window.confirmed.emit(["computing","physics","statistics"],"running")
			continue
		var stage_id := str(gameplay.story_flags.get("guide_stage",""))
		if not stage_id.is_empty() and game._guided_exploration.visible:
			stages[stage_id] = true
			if stage_id == "night" and not reloaded:
				reloaded = true
				var state: DialogicSaveState = dialogic.get_full_state()
				dialogic.load_full_state(state)
				session._sync_character_profile_from_dialogic()
				session._sync_game_time_from_dialogic()
				for wait_frame in range(5): await process_frame
				check(gameplay.story_flags.guide_stage == "night","in-memory load keeps guided task")
				continue
			var stage: Dictionary = Guide.STAGES[stage_id]
			var location := str(gameplay.story_flags.guide_location)
			if met.is_empty() and location == "campus_hall":
				var crowd: Array = gameplay.story_crowd(location)
				if not crowd.is_empty():
					met = crowd[0]
					check(gameplay.talk_to_story_npc(met).ok,"generated student can be met in chapter")
					var before: Dictionary = gameplay.simulation.export_snapshot()
					gameplay.talk_to_story_npc(met)
					check(before == gameplay.simulation.export_snapshot(),"repeating introduction gives no extra reward")
			if location == stage.goal_place:
				check(gameplay.inspect_story_object(str(stage.goal)).ok,"quest action " + stage_id)
			else:
				var route := _route(location,str(stage.goal_place),stage.allowed)
				check(not route.is_empty(),"guided route to " + str(stage.goal_place))
				if not route.is_empty(): gameplay.guided_travel(route[0])
			continue
		if dialogic.paused: continue
		if dialogic.current_state == DialogicGameHandler.States.AWAITING_CHOICE:
			var choices: Array = dialogic.Choices.get_current_question_info().choices.filter(func(choice): return choice.visible and not choice.disabled)
			if choices.is_empty(): continue
			var selected: Dictionary = choices[0]
			for choice in choices:
				if choice.text.contains("старше 18"): selected = choice
				if _flee and choice.text == "Убежать": selected = choice
			if choices.size() == 4 and str(choices[0].text).contains("Оливера"): selected = choices[clampi(_branch,0,3)]
			if choices.size() == 2 and str(choices[0].text).contains("Поднять руку") and _flee: selected = choices[1]
			if _teacher_right and choices.size() == 2 and str(choices[0].text).contains("Побежать налево"): selected = choices[1]
			if not dialogic.Choices._choice_blocker.is_stopped(): continue
			dialogic.Choices.select_choice(int(selected.button_index))
			continue
		if dialogic.current_timeline == null or dialogic.current_event_idx < 0 or dialogic.current_event_idx >= dialogic.current_timeline_events.size(): continue
		var event = dialogic.current_timeline_events[dialogic.current_event_idx]
		if event is DialogicTextEvent:
			if event.state == DialogicTextEvent.States.REVEALING: dialogic.Text.skip_text_reveal()
			elif event.state == DialogicTextEvent.States.DONE: event.advance.emit()
		var marker: String = str(dialogic.current_timeline.get_identifier()) + ":" + str(dialogic.current_event_idx)
		if marker != last_marker:
			last_marker = marker
	check(gameplay.phase == "free_roam","actual first chapter reaches the open world; stopped at " + last_marker)
	check(stages.size() == 9,"all nine guided exploration tasks visited")
	check(seen_visuals.has("Асука") and seen_visuals.has("Элли") and (seen_visuals.has("Оливер") or _branch==3),"authored speakers use modular portraits during the actual chapter")
	check(flashback_clear,"adult modular portraits never carry into childhood flashbacks")
	check(session.player_character_created,"mirror creates the character in real playthrough")
	check(gameplay.story_flags.get("subjects",[]).size() == 3,"curriculum modal records subjects")
	check(gameplay.simulation.state.preferences.difficulty == _difficulty,"chosen difficulty reaches actual gameplay")
	check(gameplay.simulation.state.player.points == preload("res://scripts/mechanics/setup_config.gd").point_budget(config),"unallocated mirror points carry over on the selected difficulty")
	check(not met.is_empty(),"playthrough meets an existing generated student")
	if not met.is_empty(): check(met in gameplay.simulation.state.social.contacts,"random student remains a contact after unlock")
	check(not str(gameplay.story_flags.get("guide_stage","")).is_empty() if gameplay.phase != "free_roam" else current_scene._gameplay_shell.visible,"proper final view is visible")
	for final_frame in range(8): await process_frame
	print("FLOW_RESULT ",JSON.stringify({"branch":_branch,"difficulty":_difficulty,"flee":_flee,"teacher_right":_teacher_right,"checks":_checks,"failed":_failures.size(),"failures":_failures,"stages":stages.keys(),"last":last_marker,"milliseconds":Time.get_ticks_msec()-started}))
	Engine.time_scale = 1
	quit(0 if _failures.is_empty() else 1)

func _route(source: String, target: String, allowed: Array) -> Array:
	var queue: Array = [[source,[]]]
	var seen := {}
	while not queue.is_empty():
		var entry: Array = queue.pop_front()
		if entry[0] == target: return entry[1]
		seen[entry[0]] = true
		for next in Guide.PLACES[entry[0]].exits:
			if next in allowed and not seen.has(next): queue.append([next,entry[1]+[next]])
	return []
