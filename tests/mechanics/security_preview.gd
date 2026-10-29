extends SceneTree
## Focused sandbox security preview: read purity, command parity and lock outcomes.
const Main = preload("res://scripts/gameplay/main_simulation.gd")
const Options = preload("res://scripts/mechanics/conversation_options.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL: ", label)

func fresh():
	var sim = Main.new(551)
	sim.state.clock = sim.calendar.snapshot(480)
	check(sim.command("social", "generate", {"id":"target"}).ok, "generate a security target")
	return sim

func snapshot(sim) -> Dictionary:
	return JSON.parse_string(JSON.stringify(sim.export_snapshot()))

func run() -> void:
	_direct_theft()
	_direct_burglary()
	_interactive_burglary()
	print("SECURITY_PREVIEW_RESULT ", JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)

func _direct_theft() -> void:
	var sim = fresh()
	var npc: Dictionary = sim.state.social.npcs.target
	npc.location = sim.state.world.location
	var before := snapshot(sim)
	var rng_before: int = sim.rng.state
	var plan: Dictionary = sim.services.security.preview("steal", {"npc":"target"})
	check(plan.ok and plan.data.blocked.is_empty() and plan.data.minutes == 10 and plan.data.chance_min == plan.data.chance_max, "theft preview shows an exact current roll chance and time")
	check(plan.data.fine_on_failure == 20 and plan.data.heat_on_failure == 15.0, "theft preview shows the actual failure penalty")
	check(snapshot(sim) == before and sim.rng.state == rng_before, "theft preview leaves snapshot and RNG untouched")
	var minute := int(sim.state.clock.total_minutes)
	var fine := int(sim.state.security.fine)
	var heat := float(sim.state.world.heat)
	var result: Dictionary = sim.command("security", "steal", {"npc":"target"})
	check(result.ok and is_equal_approx(float(result.data.chance), float(plan.data.chance_min)), "theft command uses the previewed chance")
	check(int(sim.state.clock.total_minutes) == minute + int(plan.data.minutes), "theft spends previewed world time")
	if result.ok and not result.data.success:
		check(int(sim.state.security.fine) - fine == int(plan.data.fine_on_failure) and is_equal_approx(float(sim.state.world.heat) - heat, float(plan.data.heat_on_failure)), "failed theft applies the previewed fine and heat")
	else:
		check(int(sim.state.security.fine) == fine and is_equal_approx(float(sim.state.world.heat), heat), "successful theft adds no failure penalty")
	before = snapshot(sim)
	plan = sim.services.security.preview("steal", {"npc":"missing"})
	check(plan.ok and plan.data.blocked == "unknown_npc" and not sim.command("security", "steal", {"npc":"missing"}).ok, "unavailable target has the same preview and command block")
	check(snapshot(sim) == before, "rejected theft is atomic")
	check(sim.command("preferences", "content_tag", {"id":"crime","enabled":false}).ok, "turn off crime content")
	before = snapshot(sim)
	plan = sim.services.security.preview("steal", {"npc":"target"})
	check(plan.ok and plan.data.blocked == "content_disabled" and not sim.command("security", "steal", {"npc":"target"}).ok, "crime filter blocks both preview and theft")
	check(snapshot(sim) == before, "crime filter rejection consumes no world state or RNG")
	check(sim.command("preferences", "content_tag", {"id":"crime","enabled":true}).ok, "restore crime content for chance comparison")
	sim.state.world.heat = 100.0
	check(sim.command("social", "generate", {"id":"witness"}).ok, "generate a theft witness")
	sim.state.social.npcs.witness.location = sim.state.world.location
	check(sim.command("npc_agency", "enable").ok, "enable contextual dialogue for theft preview")
	plan = sim.services.security.preview("steal", {"npc":"target"})
	npc = sim.state.social.npcs.target
	var dialogue: Dictionary = Options.new(sim).preview(npc, "hg_steal")
	check(is_equal_approx(float(plan.data.chance_min), float(dialogue.chance)), "dialogue theft forecast uses the same chance as the security command")

func _direct_burglary() -> void:
	var sim = fresh()
	sim.state.world.location = str(sim.state.social.npcs.target.home)
	check(sim.command("inventory", "add", {"id":"lockpick"}).ok, "acquire a direct burglary tool")
	var before := snapshot(sim)
	var rng_before: int = sim.rng.state
	var plan: Dictionary = sim.services.security.preview("burglary", {"npc":"target"})
	check(plan.ok and plan.data.blocked.is_empty() and plan.data.chance_min == plan.data.chance_max and plan.data.minutes == 30, "direct burglary preview gives its roll chance and time")
	check(snapshot(sim) == before and sim.rng.state == rng_before, "direct burglary preview leaves snapshot and RNG untouched")
	var minute := int(sim.state.clock.total_minutes)
	var result: Dictionary = sim.command("security", "burglary", {"npc":"target"})
	check(result.ok and is_equal_approx(float(result.data.chance), float(plan.data.chance_min)), "direct burglary uses the previewed chance")
	check(int(sim.state.clock.total_minutes) == minute + int(plan.data.minutes) and not sim.state.inventory.items.has("lockpick"), "direct burglary spends previewed time and tool")

func _interactive_burglary() -> void:
	var sim = fresh()
	sim.state.world.location = str(sim.state.social.npcs.target.home)
	var plan: Dictionary = sim.services.security.preview("begin_burglary", {"npc":"target"})
	check(plan.ok and plan.data.blocked == "insufficient_items", "lock preview explains a missing tool")
	check(sim.command("inventory", "add", {"id":"lockpick"}).ok, "acquire a real lockpick")
	var before := snapshot(sim)
	var rng_before: int = sim.rng.state
	plan = sim.services.security.preview("begin_burglary", {"npc":"target"})
	check(plan.ok and plan.data.blocked.is_empty() and plan.data.chance_min == 0.0 and plan.data.chance_max == 1.0 and plan.data.chance_model == "player_input", "interactive success range depends on player inputs")
	check(plan.data.minutes == 15 and plan.data.tool_cost == 1 and plan.data.fine_on_failure == 50 and plan.data.heat_on_failure == 30.0, "lock preview lists time, tool and failure costs")
	check(snapshot(sim) == before and sim.rng.state == rng_before, "lock preview leaves snapshot and RNG untouched")
	var minute := int(sim.state.clock.total_minutes)
	check(sim.command("security", "begin_burglary", {"npc":"target"}).ok, "previewed lock attempt starts")
	check(int(sim.state.clock.total_minutes) == minute and not sim.state.inventory.items.has("lockpick"), "start consumes the tool before the timed outcome")
	for i in range(5):
		if sim.state.encounters.game.status != "active": break
		var wrong := (int(sim.state.encounters.game.pins[int(sim.state.encounters.game.pin)]) + 1) % 3
		check(sim.command("encounters", "game_input", {"value":wrong}).ok, "wrong lock input is accepted as a real attempt")
	check(sim.state.encounters.game.status == "lost" and int(sim.state.clock.total_minutes) == minute + int(plan.data.minutes), "failed lock attempt spends previewed time")
	check(int(sim.state.security.fine) == int(plan.data.fine_on_failure) and is_equal_approx(float(sim.state.world.heat), float(plan.data.heat_on_failure)), "failed lock attempt applies previewed fine and heat: %s / %s" % [str(sim.state.security.fine), str(sim.state.world.heat)])
