extends SceneTree
## Focused sandbox regression for resident homes, city access and real shop stock.
const Setup = preload("res://scripts/mechanics/setup_config.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		printerr("FAIL: ", description)

func _run() -> void:
	var gameplay = root.get_node("Gameplay")
	var session = root.get_node("GameSession")
	var dialogic = root.get_node("Dialogic")
	session.pause_autosave_runtime()
	var config: Dictionary = Setup.defaults()
	config.mode = "sandbox"
	config.population.count = 8
	gameplay._pending_configuration = config
	dialogic.clear(DialogicGameHandler.ClearFlags.FULL_CLEAR)
	session.reset_game_time()
	session.reset_character_profile()
	var profile: Dictionary = session.get_character_profile()
	profile.identity.full_name = "Тестовый житель"
	check(session.apply_character_profile_v2(profile), "mirror accepts the sandbox character")
	gameplay._on_profile_changed(session.get_character_profile())
	check(gameplay.open_sandbox().ok, "mirror opens sandbox")
	var sim = gameplay.simulation
	check(gameplay.phase == "free_roam" and sim.configuration_error.is_empty(), "sandbox runtime is ready")
	check(sim.state.social.npcs.size() == 8, "configured population is created once")
	var homes := {}
	var independent_homes := true
	for npc: Dictionary in sim.state.social.npcs.values():
		var home := str(npc.home)
		if home == "bedroom" or home == "apartment_hall" or not sim.catalog.locations.has(home): independent_homes = false
		homes[home] = true
	check(independent_homes and homes.size() == 8, "residents have eight distinct homes outside the player's apartment")
	check(sim.services.world.route("residential_district").ok, "home connects to the residential streets")
	var market_route: Dictionary = sim.services.world.route("south_market")
	check(market_route.ok and int(market_route.get("data", {}).get("minutes", 0)) > 0, "open city market is reachable from the bedroom")
	var before: Dictionary = sim.export_snapshot()
	check(not gameplay.execute("inventory", "buy", {"id":"desk", "shop":"market"}).ok and before == sim.export_snapshot(), "buying from home is rejected atomically")
	var departure := int(sim.state.clock.total_minutes)
	var journey: Dictionary = gameplay.execute("world", "journey", {"id":"south_market"})
	check(journey.ok and sim.state.world.location == "south_market" and int(sim.state.clock.total_minutes) == departure + int(market_route.get("data", {}).get("minutes", 0)), "city journey reaches the shop and advances time once")
	var cash := int(sim.state.economy.cash)
	var desk: Dictionary = gameplay.execute("inventory", "buy", {"id":"desk", "shop":"market"})
	var bandage: Dictionary = gameplay.execute("inventory", "buy", {"id":"bandage", "shop":"market"})
	check(desk.ok and bandage.ok and int(sim.state.inventory.items.get("desk", 0)) == 1 and int(sim.state.inventory.items.get("bandage", 0)) == 1, "furniture and medicine can be bought from the live catalog")
	check(int(sim.state.economy.cash) == cash - int(desk.get("data", {}).get("total", 0)) - int(bandage.get("data", {}).get("total", 0)), "both purchases charge their catalog prices once")
	print("SANDBOX_WORLD_ECONOMY_RESULT ", JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
