extends SceneTree
## Focused, in-memory furniture and emergency-home regression checks.
const Simulation = preload("res://scripts/mechanics/simulation.gd")
const MainSimulation = preload("res://scripts/gameplay/main_simulation.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	for test_name in ["sale_and_reentry", "lease_and_reentry", "capacity_is_atomic", "emergency_is_once"]:
		if call(test_name) != true:
			failures.append(test_name + " did not finish")
	print("HOUSING_LIFECYCLE_RESULT ", JSON.stringify({"checks": checks, "failed": failures.size()}))
	for failure in failures: printerr("FAIL: ", failure)
	quit(1 if not failures.is_empty() else 0)

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func sale_and_reentry() -> bool:
	var sim = Simulation.new(41)
	sim.state.economy.cash = 5000
	check(sim.command("housing", "buy", {"id":"apartment"}).ok, "buy apartment")
	check(sim.command("inventory", "add", {"id":"stove"}).ok, "acquire stove")
	check(sim.command("housing", "furnish", {"id":"apartment", "item":"stove"}).ok, "install stove")
	check(not sim.state.inventory.items.has("stove"), "installed stove leaves inventory")
	check(sim.command("housing", "sell", {"id":"apartment"}).ok, "sell furnished apartment")
	check(int(sim.state.inventory.items.get("stove", 0)) == 1 and not sim.state.housing.properties.has("apartment"), "sale returns one stove")
	var after_sale: Dictionary = sim.state.duplicate(true)
	check(not sim.command("housing", "sell", {"id":"apartment"}).ok and sim.state == after_sale, "repeat sale cannot duplicate furniture or proceeds")
	check(sim.command("housing", "buy", {"id":"apartment"}).ok, "buy again")
	check(sim.command("housing", "move_in", {"id":"apartment"}).ok, "enter bought home")
	check(sim.command("housing", "furnish", {"id":"apartment", "item":"stove"}).ok, "reinstall returned stove")
	check(not sim.state.inventory.items.has("stove") and "stove" in sim.state.world.equipment, "reentry uses same stove exactly once")
	return true

func lease_and_reentry() -> bool:
	var sim = Simulation.new(42)
	sim.state.economy.cash = 5000
	check(sim.command("housing", "rent", {"id":"apartment"}).ok, "rent apartment")
	check(sim.command("inventory", "add", {"id":"computer"}).ok, "acquire computer")
	check(sim.command("housing", "furnish", {"id":"apartment", "item":"computer"}).ok, "install computer")
	check(sim.command("housing", "move_in", {"id":"apartment"}).ok, "enter rented home")
	check(sim.command("housing", "end_lease", {"id":"apartment"}).ok, "end furnished lease")
	check(int(sim.state.inventory.items.get("computer", 0)) == 1 and sim.state.housing.residence.is_empty() and sim.state.world.equipment.is_empty(), "lease return clears old residence and equipment")
	var after_lease: Dictionary = sim.state.duplicate(true)
	check(not sim.command("housing", "end_lease", {"id":"apartment"}).ok and sim.state == after_lease, "repeat lease exit cannot duplicate furniture")
	check(sim.command("housing", "rent", {"id":"apartment"}).ok, "rent again")
	check(sim.command("housing", "move_in", {"id":"apartment"}).ok, "reenter rented home")
	check(sim.command("housing", "furnish", {"id":"apartment", "item":"computer"}).ok, "reinstall returned computer")
	check(not sim.state.inventory.items.has("computer") and "computer" in sim.state.world.equipment, "reentry uses same computer exactly once")
	return true

func capacity_is_atomic() -> bool:
	var sim = Simulation.new(43)
	sim.state.economy.cash = 5000
	check(sim.command("housing", "buy", {"id":"apartment"}).ok, "capacity buy")
	check(sim.command("inventory", "add", {"id":"stove"}).ok, "capacity add stove")
	check(sim.command("housing", "furnish", {"id":"apartment", "item":"stove"}).ok, "capacity furnish")
	var capacity: float = sim.services.inventory.capacity()
	var amount: int = int(floor(capacity / 3.0))
	check(sim.command("inventory", "add", {"id":"computer", "quantity":amount}).ok, "fill inventory with computers")
	var before: Dictionary = sim.state.duplicate(true)
	var blocked: Dictionary = sim.command("housing", "sell", {"id":"apartment"})
	check(not blocked.ok and blocked.error == "inventory_capacity" and sim.state == before, "full inventory blocks sale atomically")
	check(sim.command("inventory", "remove", {"id":"computer", "quantity":amount}).ok, "make room for furniture")
	check(sim.command("housing", "sell", {"id":"apartment"}).ok and int(sim.state.inventory.items.get("stove", 0)) == 1, "sale succeeds when furniture fits")
	return true

func emergency_is_once() -> bool:
	var sim = MainSimulation.new(44)
	check(sim.configuration_error.is_empty(), "main catalog validates")
	sim.state.clock = sim.calendar.snapshot(1440 + 12 * 60)
	sim.state.world.location = "real_estate_agency"
	sim.state.world.flags.student_home_lost = true
	sim.state.economy.cash = 0
	check(sim.command("housing", "emergency", {"id":"social_housing"}).ok, "first emergency grant")
	check(bool(sim.state.world.flags.get("social_housing_granted", false)), "grant records one-time entitlement")
	check(sim.command("housing", "end_lease", {"id":"social_housing"}).ok, "end social lease")
	check(int(sim.state.inventory.items.get("stove", 0)) == 1, "social lease returns supplied stove under current ownership model")
	var after_exit: Dictionary = sim.state.duplicate(true)
	check(not sim.command("housing", "emergency", {"id":"social_housing"}).ok and sim.state == after_exit, "second emergency grant rejected atomically")
	var restored = MainSimulation.new(44)
	check(restored.restore_snapshot(sim.export_snapshot()).ok, "one-time social grant survives snapshot restore")
	check(not restored.command("housing", "emergency", {"id":"social_housing"}).ok and int(restored.state.inventory.items.get("stove", 0)) == 1, "restored grant cannot duplicate supplied furniture")
	var older = MainSimulation.new(45)
	check(older.restore_snapshot(sim.export_snapshot()).ok, "older social housing fixture restores")
	older.state.housing.properties.social_housing = {"owned":false, "equipment":{"stove":1}, "tenants":[], "next_bill":999999, "arrears":0, "rent_income":0, "tenant_arrears":{}, "original_homes":{}}
	older.state.inventory.items.erase("stove")
	older.state.world.flags.erase("social_housing_granted")
	check(older.command("housing", "end_lease", {"id":"social_housing"}).ok, "existing grant without flag can end lease")
	check(not older.command("housing", "emergency", {"id":"social_housing"}).ok and int(older.state.inventory.items.get("stove", 0)) == 1, "lease exit stamps one-time flag for existing grant")
	return true
