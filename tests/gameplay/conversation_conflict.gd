extends RefCounted
var t

func _init(runner) -> void: t = runner

func run() -> void:
	t.fresh_world()
	t.gameplay.complete_chapter_one()
	var sim: RefCounted = t.gameplay.simulation
	sim.state.world.location = "global_map"
	for npc: Dictionary in sim.state.social.npcs.values():
		sim.services.npc_agency._cancel(npc,"test_conversation_combat")
		npc.location = "global_map"
		npc.activity = "idle"
		npc.schedule = []
		npc.decision = {"committed":false}
		npc.pinned_until = int(sim.state.clock.total_minutes)+1440
		npc.needs.merge({"energy":95.0,"satiety":95.0,"hygiene":95.0},true)
	var scene := Control.new()
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	t.root.add_child(scene)
	var window: Control = load("res://scripts/ui/gameplay/conversation_window.gd").new()
	window.configure("asuka","free","res://assets/textures/backgrounds/campus_v1/hall.tres")
	scene.add_child(window)
	var stage: Control = window._live_stage
	t.check(stage._animated and is_instance_valid(stage.puppet.model),"main-game Live2D conversation uses the common stage")
	stage._select_tab("conflict")
	t.check(stage._options.get_child(0).text.begins_with("0. Отдай мне"),"aggression menu starts at zero like the reference")
	await _capture(stage,"aggression-live2d")
	var minute := int(sim.state.clock.total_minutes)
	stage._choose("hg_fight",int(stage.session.present().turn))
	t.check(stage.session.combat_active() and stage._menu_area.visible and not stage._navigation.visible,"choosing fight replaces dialogue actions with actual battle controls")
	t.check(int(sim.state.clock.total_minutes)==minute+1 and sim.validate_state(sim.state).ok,"main-game dialogue combat starts with valid energy and one elapsed minute")
	var found := false
	for button: Button in stage._buttons:
		if button.get_meta("combat_move","") == "jab": found = true
	t.check(found and stage._stats.text.contains("здоровье"),"battle exposes real moves and both health values")
	stage._close()
	t.check(not stage._closing and stage.session.combat_active(),"closing the conversation cannot hide an active encounter")
	minute = int(sim.state.clock.total_minutes)
	stage._fight({"action":"end_turn"})
	t.check(sim.state.encounters.combat.phase=="defence" and int(sim.state.clock.total_minutes)==minute,"UI waits for defence before spending round time")
	while sim.state.encounters.combat.phase=="defence": stage._fight({"action":"guard","part":"head"})
	t.check(int(sim.state.clock.total_minutes)==minute+1 and sim.validate_state(sim.state).ok,"main game charges each conversation battle round once")
	await _capture(stage,"fight-live2d")
	sim.state.player.stats.agility = 30
	for attempt in range(20):
		if not stage.session.combat_active(): break
		stage._fight({"action":"guard" if sim.state.encounters.combat.phase=="defence" else "escape"})
	t.check(not stage.session.combat_active() and stage._reply_mode,"completed battle returns to its final reply")
	t.check(stage._text.text==stage.session.present().utterance.text,"visible final reply comes from the authoritative runtime")
	window._close()
	await t.process_frame
	# A resident without a Live2D binding receives the same categories and rules.
	var id := ""
	for key: String in sim.state.social.npcs:
		if key != "asuka": id = key; break
	window = load("res://scripts/ui/gameplay/conversation_window.gd").new()
	window.configure(id,"free","res://assets/textures/backgrounds/campus_v1/hall.tres")
	scene.add_child(window)
	stage = window._live_stage
	t.check(not stage._animated and stage._tab_buttons.size()==7,"ordinary NPCs have the complete conversation menu with their own portrait")
	stage._select_tab("conflict")
	await _capture(stage,"aggression-portrait")
	stage._select_tab("dialogue")
	stage._open_folder("Повседневные темы")
	var before: Dictionary = sim.export_snapshot()
	stage._select_tab("questions")
	t.check(sim.export_snapshot()==before,"ordinary NPC menu navigation changes no gameplay state")
	stage._choose("day",int(stage.session.present().turn))
	t.check(stage._reply_mode and stage._text.text==stage.session.present().utterance.text,"ordinary NPC choices render an actual reply")
	window._close()
	await t.process_frame
	# Returning to the actual victim must respect the recent conflict.
	var opened: Dictionary = t.gameplay.execute("npc_dialogue","open",{"id":"asuka"})
	t.check(opened.ok and opened.data.node=="end" and opened.data.utterance.memory=="violence","the main game explains the victim's refusal after escaping")
	before = sim.export_snapshot()
	var refused: Dictionary = t.gameplay.execute("npc_dialogue","choose_menu",{"id":"asuka","choice":"day","turn":int(sim.state.social.npcs.asuka.mind.dialogue.turn)})
	t.check(not refused.ok and sim.export_snapshot()==before,"a menu choice cannot force the victim to continue the refused conversation")
	window = load("res://scripts/ui/gameplay/conversation_window.gd").new()
	window.configure("asuka","free","res://assets/textures/backgrounds/campus_v1/hall.tres")
	scene.add_child(window)
	stage = window._live_stage
	t.check(stage._text.text==stage.session.present().utterance.text and stage.session.present().node=="end","the visible stage renders the actual post-fight refusal")
	var respects_space := false
	for button: Button in stage._buttons:
		if button.text=="Поговорить ещё": respects_space = button.disabled
	t.check(respects_space,"reopen stays disabled while the NPC needs distance")
	window._close()
	await t.process_frame
	# Verify the opening attack on another resident who has not fought the player.
	opened = t.gameplay.execute("npc_dialogue","open",{"id":id})
	t.check(opened.ok and opened.data.node=="root","a different willing resident keeps their own availability")
	var result: Dictionary = t.gameplay.execute("npc_dialogue","choose_menu",{"id":id,"choice":"hg_beat","turn":int(sim.state.social.npcs[id].mind.dialogue.turn)})
	t.check(result.ok and sim.state.encounters.combat.ap==1 and sim.state.encounters.combat.log[0].move=="heavy","main-game opening attack spends its actual three AP")
	t.check(sim.validate_state(sim.state).ok and is_equal_approx(float(sim.state.encounters.combat.stamina.player),float(sim.state.player.needs.energy)),"opening attack energy remains synchronized with player needs")
	for attempt in range(20):
		if sim.state.encounters.combat.status != "active": break
		t.gameplay.execute("combat","action",{"action":"guard" if sim.state.encounters.combat.phase == "defence" else "escape"})
	scene.queue_free()
	await t.process_frame

func _capture(stage: Control, name: String) -> void:
	if not "--capture-conflict" in OS.get_cmdline_user_args(): return
	for frame in range(12): await t.process_frame
	stage._finish_speech()
	await RenderingServer.frame_post_draw
	var path := "res://docs/gameplay/verification/conversation-conflict-2026-10-28/%s-%d.png" % [name,t.root.size.x]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	t.check(t.root.get_texture().get_image().save_png(path)==OK,"native conversation capture saved: "+name)
