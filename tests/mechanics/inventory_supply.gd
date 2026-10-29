extends SceneTree

const Simulation = preload("res://scripts/mechanics/simulation.gd")
const Main = preload("res://scripts/gameplay/main_simulation.gd")
const Presentation = preload("res://scripts/gameplay/presentation.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL: ", label)

func _fresh(main_game: bool):
	return Main.new(1729, Presentation.extensions()) if main_game else Simulation.new(1729)

func _run() -> void:
	_exercise_supply(false)
	_exercise_supply(true)
	print("INVENTORY_SUPPLY_RESULT ", JSON.stringify({"checks": checks, "failed": failures.size(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _exercise_supply(main_game: bool) -> void:
	var sim = _fresh(main_game)
	var label := "main" if main_game else "standalone"
	var shop := "market"
	var initial := int(sim.catalog.shops[shop].stock.lockpick)
	sim.state.world.location = str(sim.catalog.shops[shop].location)
	sim.state.clock = sim.calendar.snapshot(600)
	sim.state.economy.cash = 1000
	_check(sim.command("inventory", "buy", {"id": "lockpick", "shop": shop, "quantity": initial}).ok, label + " can buy the available lockpicks")
	_check(int(sim.state.economy.shop_stock[shop].lockpick) == 0, label + " depletes the consumable supply")
	var rejected: Dictionary = sim.export_snapshot()
	_check(not sim.command("inventory", "buy", {"id": "lockpick", "shop": shop}).ok and sim.export_snapshot() == rejected, label + " refuses an empty shelf without changing state or RNG")
	_check(sim.command("inventory", "buy", {"id": "book", "shop": shop, "quantity": int(sim.catalog.shops[shop].stock.book)}).ok, label + " can buy a durable item")
	sim.state.clock = sim.calendar.snapshot(1439)
	_check(sim.command("clock", "advance", {"minutes": 1}).ok, label + " reaches the next supply day")
	_check(int(sim.state.economy.shop_stock[shop].lockpick) == initial, label + " replenishes consumable lockpicks at midnight")
	_check(int(sim.state.economy.shop_stock[shop].book) == 0, label + " keeps durable stock finite")
	var checkpoint: Dictionary = JSON.parse_string(JSON.stringify(sim.export_snapshot()))
	var replay = _fresh(main_game)
	_check(replay.restore_snapshot(checkpoint).ok, label + " restores the replenished supply from JSON")
	for world in [sim, replay]:
		world.state.clock = world.calendar.snapshot(2040)
		_check(world.command("inventory", "buy", {"id": "lockpick", "shop": shop}).ok, label + " can buy again after restock")
	_check(JSON.parse_string(JSON.stringify(sim.export_snapshot())) == JSON.parse_string(JSON.stringify(replay.export_snapshot())), label + " resumed purchase matches uninterrupted play")
