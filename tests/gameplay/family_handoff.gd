extends RefCounted
var t

func _init(runner) -> void: t = runner

func button(shell) -> Button:
	for item in shell._body.find_children("*","Button",true,false):
		var action: Dictionary = item.get_meta("gameplay_action",{})
		if action.get("module","")=="family" and action.get("operation","")=="delegate": return item
	return null

func run() -> void:
	var original: Dictionary = t.dialogic.VAR.var_storage.World.duplicate(true)
	t.session.pause_autosave_runtime()
	t.fresh_world()
	t.gameplay.complete_chapter_one()
	var sim = t.gameplay.simulation
	sim.state.npc_reproduction.enabled = false
	var caregiver := str(sim.state.social.npcs.keys()[0])
	for id in sim.state.social.npcs:
		var other: Dictionary = sim.state.social.npcs[id]
		sim.services.npc_planner.interrupt(str(id),"family_ui_fixture")
		other.pinned_until = int(sim.state.clock.total_minutes)+100000
	var npc: Dictionary = sim.state.social.npcs[caregiver]
	npc.home = "bedroom"
	npc.location = "bedroom"
	npc.activity = "rest"
	npc.pinned_until = 0
	npc.schedule = []
	npc.health = 100
	for need in npc.needs: npc.needs[need] = 100.0
	for need in sim.state.player.needs: sim.state.player.needs[need] = 100.0
	sim.state.economy.cash = 1000
	sim.state.world.location = "global_map"
	sim.state.healthcare.family.append({"parent":caregiver,"partner":"player","minute":int(sim.state.clock.total_minutes),"care":0,"status":"dependent"})
	sim.services.family.initialize()
	var member: Dictionary = sim.state.family.members.family_1
	member.needs.food = 20.0
	var shell = load("res://scripts/ui/gameplay/gameplay_shell.gd").new()
	t.root.add_child(shell)
	shell._screen_state.family_tab = "duties"
	shell.open_panel("family")
	var before: Dictionary = sim.export_snapshot()
	shell._refresh()
	t.check(before==sim.export_snapshot(),"family duties and alternatives render without changing live state or RNG")
	var request := button(shell)
	t.check(request!=null and not request.disabled,"actual family duties screen offers a present co-guardian's one-time help")
	npc.location = "global_map"
	shell._refresh()
	request = button(shell)
	t.check(request!=null and request.disabled and request.tooltip_text.contains("не дома"),"family UI explains why an absent helper cannot perform remote care")
	npc.location = "bedroom"
	shell._refresh()
	request = button(shell)
	var minute := int(sim.state.clock.total_minutes)
	var cash := int(sim.state.economy.cash)
	var energy := float(sim.state.player.needs.energy)
	if request!=null and not request.disabled: request.pressed.emit()
	t.check(member.task.get("caregiver","")==caregiver and member.assignments.food=="player","real UI button starts existing family care and retains the assigned guardian")
	t.check(sim.state.clock.total_minutes==minute and member.needs.food==20 and sim.state.economy.cash==cash-3,"request pays actual supplies without granting care or time at once")
	t.check(sim.state.player.needs.energy==energy,"delegated NPC effort does not consume player energy")
	for frame in range(2): await t.process_frame
	t.check(button(shell)==null,"while care runs the duties screen shows the caregiver instead of offering duplicate tasks")
	var elapsed: Dictionary = t.gameplay.execute("clock","advance",{"minutes":20})
	t.check(elapsed.ok and member.task.is_empty() and member.needs.food>=75,"main shared clock completes the delegated care exactly once")
	t.check(member.assignments.food=="player" and member.bonds.get(caregiver,0)==2,"completed UI request keeps responsibilities and records the actual helper bond")
	t.check(t.session.get_game_time_snapshot().total_minutes==sim.state.clock.total_minutes,"delegated care remains synchronized with the main game clock")
	t.check(sim.restore_snapshot(JSON.parse_string(JSON.stringify(sim.export_snapshot()))).ok,"main game restores the unchanged family schema after delegated care")
	shell.free()
	t.dialogic.VAR.var_storage.World = original
	t.fresh_world()
