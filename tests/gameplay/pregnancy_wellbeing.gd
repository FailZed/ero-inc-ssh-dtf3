extends RefCounted
var t

func _init(runner) -> void:
	t = runner

func _button(shell, operation: String) -> Button:
	for button in shell._body.find_children("*","Button",true,false):
		var action: Dictionary = button.get_meta("gameplay_action",{})
		if action.get("module","")=="pregnancy_wellbeing" and action.get("operation","")==operation: return button
	return null

func run() -> void:
	var initial := int(t.checks)
	var original: Dictionary = t.dialogic.VAR.var_storage.World.duplicate(true)
	t.session.pause_autosave_runtime()
	t.fresh_world()
	t.gameplay.complete_chapter_one()
	var sim = t.gameplay.simulation
	sim.state.world.location = "bathroom"
	sim.state.economy.cash = 1000
	t.check(t.gameplay.execute("reproduction","configure",{"profile":{"can_gestate":true,"produces_sperm":false,"cycling":true}}).ok,"main player supports pregnancy wellbeing")
	t.check(t.gameplay.execute("lifecycle","start",{"id":"pregnancy","target":"player"}).ok,"main pregnancy initializes wellbeing")
	var before_bladder := float(sim.state.player.needs.bladder)
	t.check(t.gameplay.execute("clock","advance",{"minutes":15}).ok and float(sim.state.player.needs.bladder)<before_bladder-1.75,"main pregnancy urgency stacks with normal need decay")
	var record: Dictionary = sim.state.pregnancy_wellbeing.records.player
	record.soiled = true
	var shell = load("res://scripts/ui/gameplay/gameplay_shell.gd").new()
	t.root.add_child(shell)
	shell._screen_state.health_tab = "reproduction"
	shell.open_panel("health")
	var status_before: Dictionary = sim.export_snapshot()
	shell._refresh()
	t.check(status_before==sim.export_snapshot(),"rendering wellbeing panel and action probes does not change the world")
	for operation in ["rest","toilet","cleanup","supplies","checkup"]:
		t.check(_button(shell,operation)!=null,"live health panel exposes pregnancy "+operation)
	var button := _button(shell,"cleanup")
	t.check(button!=null and not button.disabled,"live cleanup action is available in bathroom")
	if button!=null and not button.disabled: button.pressed.emit()
	t.check(not sim.state.pregnancy_wellbeing.records.player.soiled,"real UI cleanup button changes the actual pregnancy state")
	for frame in range(3): await t.process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		var path := "res://docs/mechanics/verification/pregnancy-wellbeing-2026-10-27"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
		t.root.get_texture().get_image().save_png(path+"/health-panel.png")
	t.check(sim.command("growth","need_toggle",{"id":"bladder","enabled":false}).ok,"urinary comfort follows the game's need toggle")
	var count := int(sim.state.pregnancy_wellbeing.records.player.accidents)
	t.check(not sim.services.pregnancy_wellbeing.stress("player","full_bladder"),"disabling bladder need suppresses pregnancy incontinence events")
	t.check(sim.command("clock","advance",{"minutes":15}).ok and sim.state.player.needs.bladder==100 and int(sim.state.pregnancy_wellbeing.records.player.accidents)==count,"disabled bladder stays full without new episodes")
	shell.free()
	t.dialogic.VAR.var_storage.World = original
	t.fresh_world()
	print("PREGNANCY_MAIN_UI_RESULT ",JSON.stringify({"checks":int(t.checks)-initial,"main_ui":true}))
