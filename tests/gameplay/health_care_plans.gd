extends RefCounted
const Names = preload("res://scripts/gameplay/presentation.gd")
var t

func _init(runner) -> void:
	t = runner

func button(shell, operation: String) -> Button:
	for item in shell._body.find_children("*","Button",true,false):
		var action: Dictionary = item.get_meta("gameplay_action",{})
		if action.get("module","")=="adult_health" and action.get("operation","")==operation: return item
	return null

func set_time(sim, minute: int) -> void:
	sim.state.clock = sim.calendar.snapshot(minute)
	t.gameplay._syncing = true
	t.session.set_game_time_total_minutes(minute)
	t.gameplay._syncing = false
	for need in sim.state.player.needs: sim.state.player.needs[need] = 100.0
	if sim.state.healthcare.records.has("player"): sim.state.healthcare.records.player.unconscious_until = 0
	sim.services.adult_health.synchronize()

func run() -> void:
	var original: Dictionary = t.dialogic.VAR.var_storage.World.duplicate(true)
	t.session.pause_autosave_runtime()
	t.fresh_world()
	t.gameplay.complete_chapter_one()
	var sim = t.gameplay.simulation
	var opening := int(sim.state.clock.total_minutes)
	while not sim.services.world.is_open(sim.catalog.locations.clinic): sim.state.clock = sim.calendar.snapshot(int(sim.state.clock.total_minutes)+15)
	set_time(sim,int(sim.state.clock.total_minutes))
	sim.state.world.location = "clinic"
	sim.state.economy.cash = 2000
	sim.state.player.age = 32
	var health = sim.services.adult_health
	health.infections.onset("player","contact_irritation")
	t.check(t.gameplay.execute("adult_health","consult").ok,"main provider diagnoses care-plan symptoms")
	t.check(t.gameplay.execute("adult_health","treat",{"condition":"contact_irritation"}).ok,"main provider creates a finite care course")
	var course: Dictionary = health.record("player").conditions.contact_irritation.course
	set_time(sim,int(course.next_due))
	sim.state.world.location = "bedroom"
	health.plans.tick_actor("player")
	var shell = load("res://scripts/ui/gameplay/gameplay_shell.gd").new()
	t.root.add_child(shell)
	shell._screen_state.health_tab = "adult_health"
	shell.open_panel("health")
	var before: Dictionary = sim.export_snapshot()
	shell._refresh()
	t.check(before==sim.export_snapshot(),"medical calendar rendering preserves world state and RNG")
	var step := button(shell,"care_step")
	var snooze := button(shell,"snooze_care")
	t.check(step!=null and not step.disabled,"actual health UI offers due home care")
	t.check(snooze!=null and not snooze.disabled,"actual health UI offers a private reminder snooze")
	var minute := int(sim.state.clock.total_minutes)
	var due := int(course.next_due)
	if snooze!=null and not snooze.disabled: snooze.pressed.emit()
	t.check(sim.state.clock.total_minutes==minute and course.next_due==due,"main reminder snooze spends no time and does not move treatment deadline")
	for frame in range(2): await t.process_frame
	step = button(shell,"care_step")
	if step!=null and not step.disabled: step.pressed.emit()
	t.check(sim.state.clock.total_minutes==minute+3 and course.completed==2 and course.supplies==1,"real UI action spends time and one actual care supply")
	t.check(t.session.get_game_time_snapshot().total_minutes==sim.state.clock.total_minutes,"care action keeps main and session clocks synchronized")
	var npc := str(sim.state.social.npcs.keys()[0])
	t.check(Names.event_text({"kind":"adult_health_care_reminder","data":{"target":npc,"text":"Личное назначение"}},sim).is_empty(),"NPC medical reminders remain confidential in the player journal")
	t.check(not Names.event_text({"kind":"adult_health_care_reminder","data":{"target":"player","text":"Личное назначение"}},sim).is_empty(),"player sees their own care reminder")
	t.check(sim.restore_snapshot(JSON.parse_string(JSON.stringify(sim.export_snapshot()))).ok,"main world restores actual care progress and reminders")
	for frame in range(3): await t.process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		var path := "res://docs/mechanics/verification/health-care-plans-2026-10-28"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
		t.root.get_texture().get_image().save_png(path+"/care-plan-panel.png")
	shell.free()
	t.dialogic.VAR.var_storage.World = original
	t.fresh_world()
