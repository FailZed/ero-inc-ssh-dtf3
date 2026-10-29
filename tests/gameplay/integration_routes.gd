extends RefCounted
## Press real main-game buttons, then inspect time, relationships and World restore.
var t

func _init(runner) -> void:
	t = runner

func _action(shell, module_id: String, operation: String, id: String = "") -> Button:
	for button in shell._body.find_children("*", "Button", true, false):
		var action: Dictionary = button.get_meta("gameplay_action", {})
		if action.get("module", "") == module_id and action.get("operation", "") == operation and (id.is_empty() or action.get("args", {}).get("id", "") == id): return button
	return null

func _press(button: Button, description: String) -> bool:
	var available := button != null and not button.disabled
	t.check(available, description)
	if available: button.pressed.emit()
	return available

func _ready_people(sim) -> void:
	for npc in sim.state.social.npcs.values():
		sim.services.npc_agency._cancel(npc, "integration_fixture")
		npc.location = "residential_district"
		# Employed residents must retain their mandatory shifts for catalog validation.
		if not npc.has("employment_plan"): npc.schedule = []
		npc.activity = "idle"
		npc.decision = {"committed":false}
		npc.pinned_until = int(sim.state.clock.total_minutes) + 1440
	for id in ["asuka", "ellie"]:
		var npc: Dictionary = sim.state.social.npcs[id]
		npc.location = sim.state.world.location
		npc.needs.merge({"energy":100.0,"satiety":80.0,"social":20.0,"fun":20.0}, true)
		npc.mind.boundaries.contact = true
		npc.mind.boundaries.romance = true
		var bond: Dictionary = sim.services.npc_relationships._bond(id, "player")
		bond.trust = 70.0
		bond.comfort = 70.0
		bond.grievance = 0.0
		sim.services.npc_relationships._project(id, "player")

func run() -> void:
	var checks_before := int(t.checks)
	var failures_before := int(t.failures.size())
	var original: Dictionary = t.dialogic.VAR.var_storage.World.duplicate(true)
	t.session.pause_autosave_runtime()
	t.fresh_world()
	t.gameplay.complete_chapter_one()
	var sim = t.gameplay.simulation
	_ready_people(sim)
	sim.state.world.equipment = ["computer", "stove"]
	sim.state.player.needs.merge({"energy":100.0,"social":20.0,"fun":20.0}, true)
	var scene := Control.new()
	t.root.add_child(scene)
	var shell = load("res://scripts/ui/gameplay/gameplay_shell.gd").new()
	scene.add_child(shell)
	await t.process_frame
	var before: Dictionary = sim.export_snapshot()
	shell.open_panel("work")
	t.check(before == sim.export_snapshot(), "opening project offers never advances the real world or RNG")
	t.check(t.gameplay.execute("social_rules", "promise", {"id":"asuka","promise":"complete_project"}).ok, "main-game promise can precede a playable project")
	var minute := int(sim.state.clock.total_minutes)
	var cash := int(sim.state.economy.cash)
	shell.open_panel("work")
	_press(_action(shell, "economy", "project"), "project work is available through its main-game button")
	t.check(sim.state.economy.projects.get("website_order", {}).get("progress", 0) == 60 and int(sim.state.clock.total_minutes) == minute + 60, "first project session consumes actual world time and records progress")
	t.check(int(sim.state.economy.cash) == cash and sim.state.social.promises["asuka:complete_project"].status == "active", "unfinished project neither pays nor completes a promise")
	t.check(int(t.session.get_game_time_snapshot().total_minutes) == minute + 60 and t.dialogic.VAR.var_storage.World.gameplay.state.economy.projects.website_order.progress == 60, "project button synchronizes game clock and the existing World save bridge")
	_press(_action(shell, "economy", "project"), "project can be continued from the refreshed button")
	t.check(sim.state.economy.projects.website_order.completed and int(sim.state.economy.cash) == cash + 100, "finishing a playable project grants its payment")
	t.check(_action(shell, "economy", "project", "website_order") == null, "completed project cannot be worked or paid again from the interface")
	shell.open_panel("journal")
	_press(_action(shell, "social_rules", "fulfill"), "journal verifies a completed promise through the actual main-game command")
	t.check(sim.state.social.promises["asuka:complete_project"].status == "fulfilled", "project promise becomes fulfilled after real work")
	t.check(_action(shell, "social_rules", "fulfill") == null, "fulfilled promise cannot be redeemed repeatedly from the journal")
	# Company selection is UI state, and the same directed people participate in the visit.
	shell.open_panel("gathering")
	before = sim.export_snapshot()
	shell._toggle_gathering_guest("asuka")
	shell._toggle_gathering_guest("ellie")
	t.check(before == sim.export_snapshot(), "choosing guests changes no simulation data, resources or RNG")
	var first_bond: Dictionary = sim.services.npc_relationships.view("asuka", "ellie")
	var second_bond: Dictionary = sim.services.npc_relationships.view("ellie", "asuka")
	var social := float(sim.state.player.needs.social)
	var fun := float(sim.state.player.needs.fun)
	var meals := int(sim.state.inventory.items.meal)
	var pins := [int(sim.state.social.npcs.asuka.pinned_until), int(sim.state.social.npcs.ellie.pinned_until)]
	minute = int(sim.state.clock.total_minutes)
	_press(_action(shell, "social_rules", "gathering"), "selected guests can join a main-game shared evening")
	t.check(int(sim.state.clock.total_minutes) == minute + 90 and int(sim.state.inventory.items.meal) == meals - 2, "shared evening consumes time and one real meal per guest")
	t.check(float(sim.state.player.needs.social) > social and float(sim.state.player.needs.fun) > fun, "shared evening satisfies the player's communication and leisure needs")
	t.check(sim.services.npc_relationships.view("asuka", "ellie").affection > first_bond.affection and sim.services.npc_relationships.view("ellie", "asuka").affection > second_bond.affection, "guests develop both directions of their own relationship")
	t.check(float(sim.state.social.npcs.asuka.needs.social) > 20 and float(sim.state.social.npcs.ellie.needs.fun) > 20, "guests also satisfy their own needs")
	t.check(sim.state.social.npcs.asuka.memories.any(func(memory): return memory.kind == "gathering") and sim.state.social.npcs.ellie.memories.any(func(memory): return memory.kind == "gathering"), "both NPCs remember the shared event")
	t.check([int(sim.state.social.npcs.asuka.pinned_until), int(sim.state.social.npcs.ellie.pinned_until)] == pins, "shared evening restores previous NPC commitments after finishing")
	t.check(_action(shell, "social_rules", "gathering").disabled, "shared evening cannot be repeatedly farmed on the same day")
	var checkpoint: Dictionary = t.dialogic.VAR.var_storage.World.duplicate(true)
	before = sim.export_snapshot()
	t.gameplay.execute("clock", "advance", {"minutes":10})
	t.dialogic.VAR.var_storage.World = checkpoint
	t.session._sync_game_time_from_dialogic()
	sim = t.gameplay.simulation
	t.check(sim.export_snapshot() == before, "normal World restore retains project, promise, guest memories and directed bonds together")
	# Boundary, schedule and food failures must remain atomic in the main runtime.
	sim.state.counters.erase("gathering:%d" % sim.state.clock.day_index)
	sim.state.social.npcs.ellie.mind.boundaries.contact = false
	before = sim.export_snapshot()
	var denied: Dictionary = t.gameplay.execute("social_rules", "gathering", {"candidates":["asuka","ellie"]})
	t.check(not denied.ok and denied.error == "contact_boundary" and before == sim.export_snapshot(), "a shared evening respects a guest's refusal without spending food, time or RNG")
	sim.state.social.npcs.ellie.mind.boundaries.contact = true
	var current := int(sim.state.clock.minute_of_day)
	sim.state.social.npcs.ellie.schedule = [{"activity":"study","location":"training_center","hours":[(current+10)%1440,(current+15)%1440]}]
	before = sim.export_snapshot()
	denied = t.gameplay.execute("social_rules", "gathering", {"candidates":["asuka","ellie"]})
	t.check(not denied.ok and denied.error == "guest_schedule_conflict" and before == sim.export_snapshot(), "a brief upcoming class prevents forcing a guest to miss it")
	sim.state.social.npcs.ellie.schedule = []
	sim.state.inventory.items.erase("meal")
	before = sim.export_snapshot()
	denied = t.gameplay.execute("social_rules", "gathering", {"candidates":["asuka","ellie"]})
	t.check(not denied.ok and before == sim.export_snapshot(), "insufficient meals roll back the entire shared evening")
	shell._show_npc_details("asuka")
	social = float(sim.state.player.needs.social)
	minute = int(sim.state.clock.total_minutes)
	_press(_action(shell, "npc_agency", "encourage"), "support for an NPC goal is reachable from their main-game profile")
	t.check(int(sim.state.clock.total_minutes) == minute + 5 and float(sim.state.player.needs.social) > social, "support uses world time, records encouragement and satisfies communication")
	t.check(_action(shell, "npc_agency", "encourage").disabled, "support cannot be repeated endlessly on the same day")
	sim.state.social.npcs.ellie.mind.boundaries.contact = false
	before = sim.export_snapshot()
	denied = t.gameplay.execute("npc_agency", "encourage", {"id":"ellie"})
	t.check(not denied.ok and denied.error == "contact_boundary" and before == sim.export_snapshot(), "goal support cannot bypass a contact boundary")
	# Installation needs a current residence, rather than a hardcoded apartment action.
	t.gameplay.execute("inventory", "add", {"id":"desk","quantity":1})
	shell.open_panel("inventory")
	for button in shell._body.find_children("*", "Button", true, false):
		if button.get_meta("item_id", "") == "desk": button.pressed.emit(); break
	var install: Button
	for button in shell._body.find_children("*", "Button", true, false):
		if button.get_meta("gameplay_action",{}).get("module","") == "housing" and button.get_meta("gameplay_action",{}).get("operation","") == "furnish": install = button; break
	_press(install, "inventory offers installation in the current home")
	t.check(sim.state.housing.properties.apartment.equipment.has("desk") and not sim.state.inventory.items.has("desk"), "inventory installation transfers the item into the current residence")
	t.check(t.gameplay.execute("housing", "end_lease", {"id":"apartment"}).ok, "the starting lease can be ended through the main runtime")
	t.gameplay.execute("inventory", "add", {"id":"computer","quantity":1})
	shell.open_panel("inventory")
	for button in shell._body.find_children("*", "Button", true, false):
		if button.get_meta("item_id", "") == "computer": button.pressed.emit(); break
	for button in shell._body.find_children("*", "Button", true, false):
		if button.get_meta("gameplay_action",{}).get("module","") == "housing" and button.get_meta("gameplay_action",{}).get("operation","") == "furnish": t.check(button.disabled, "installation is unavailable without a current residence")
	# Family access uses current human relationships and boundaries, never the old archetype.
	_ready_people(sim)
	sim.state.social.npcs.asuka.traits.romantic = 0
	sim.services.npc_relationships._bond("asuka", "player").consent = true
	sim.services.social.relationship("asuka", "player").status = "partner"
	sim.state.social.npcs.asuka.mind.boundaries.romance = false
	before = sim.export_snapshot()
	denied = t.gameplay.plan_family("asuka")
	t.check(not denied.ok and denied.error == "romantic_boundary" and before == sim.export_snapshot(), "family planning respects a partner's current romantic boundary")
	sim.state.social.npcs.asuka.mind.boundaries.romance = true
	sim.state.world.location = "bedroom"
	sim.state.social.npcs.asuka.location = "bedroom"
	sim.state.social.npcs.asuka.pinned_until = 0
	sim.services.npc_relationships._bond("asuka","player").interest = 60.0
	var family: Dictionary = t.gameplay.plan_family("asuka")
	t.check(family.ok and not sim.state.intimacy.active.is_empty() and not sim.state.conditions.has("asuka:pregnancy"), "family planning opens a consensual encounter instead of directly creating pregnancy: " + str(family))
	# Existing temporary effects and habit rules now have a paid, contextual game route.
	t.fresh_world()
	t.gameplay.complete_chapter_one()
	t.gameplay.execute("clock", "advance", {"minutes":840}) # next morning, shop is open
	sim = t.gameplay.simulation
	sim.state.world.location = sim.location_role("supply_shop")
	shell.open_panel("work")
	minute = int(sim.state.clock.total_minutes)
	cash = int(sim.state.economy.cash)
	var endurance: float = sim.services.character.effective_stat("endurance")
	_press(_action(shell, "character", "substance"), "city shop exposes the existing tonic and habit mechanic as a paid action")
	t.check(int(sim.state.economy.cash) == cash - 15 and int(sim.state.clock.total_minutes) == minute + 2, "tonic purchase consumes real money and world time")
	t.check(sim.state.player.effects.has("energized") and sim.services.character.effective_stat("endurance") > endurance, "tonic temporarily changes effective rather than permanent characteristics")
	t.check(sim.state.player.addictions.get("stimulant", {}).get("exposure", 0) == 10, "using the tonic enters the existing habit simulation")
	shell.open_panel("health")
	var health_text := ""
	for label in shell._body.find_children("*", "Label", true, false): health_text += label.text + "\n"
	t.check(health_text.contains("Бодрость") and health_text.contains("формируется привычка"), "the health window exposes the actual temporary effect and developing habit")
	var tonic_checkpoint: Dictionary = sim.export_snapshot()
	var restored = t.gameplay.make_simulation()
	t.check(restored.restore_snapshot(tonic_checkpoint).ok and restored.state.player.effects == sim.state.player.effects and restored.state.player.addictions == sim.state.player.addictions, "effect expiry and habit exposure survive a complete main-world snapshot")
	t.gameplay.execute("clock", "advance", {"minutes":60})
	t.check(not sim.state.player.effects.has("energized") and sim.state.player.stats.endurance == 5, "temporary tonic benefit expires without increasing base attributes")
	sim.state.economy.cash = 0
	before = sim.export_snapshot()
	denied = t.gameplay.execute("character", "substance", {"id":"stimulant"})
	t.check(not denied.ok and before == sim.export_snapshot(), "failed tonic purchase grants neither effect nor habit exposure")
	sim.state.world.location = "bedroom"
	sim.state.economy.cash = 100
	before = sim.export_snapshot()
	denied = t.gameplay.execute("character", "substance", {"id":"stimulant"})
	t.check(not denied.ok and denied.error == "tonic_vendor_required" and before == sim.export_snapshot(), "the contextual tonic purchase cannot be invoked away from its vendor")
	scene.queue_free()
	await t.process_frame
	t.dialogic.VAR.var_storage.World = original
	t.session._sync_game_time_from_dialogic()
	print("INTEGRATION_ROUTES_RESULT ", JSON.stringify({"main_ui":true,"world_restore":true,"checks":int(t.checks)-checks_before,"failed":int(t.failures.size())-failures_before}))
