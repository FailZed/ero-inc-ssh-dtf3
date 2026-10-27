extends "res://scripts/mechanics/character.gd"
## Main-game learning includes the protagonist's actual sleep and hydration.
const SUBSTANCE_PRICES := {"stimulant":15}

func execute(operation: String, args: Dictionary) -> Dictionary:
	if operation != "substance": return super.execute(operation, args)
	var id := str(args.get("id", ""))
	if not SUBSTANCE_PRICES.has(id): return Rules.fail("unknown_substance")
	if sim.state.world.location != "global_map": return Rules.fail("tonic_vendor_required")
	if not sim.services.world.is_open(sim.catalog.shops.market): return Rules.fail("shop_closed")
	var price := int(SUBSTANCE_PRICES[id])
	if int(sim.state.economy.cash) < price: return Rules.fail("insufficient_funds")
	sim.state.economy.cash -= price
	var consumed := super.execute(operation, args)
	if not consumed.ok: return consumed
	var elapsed: Dictionary = sim.advance(2)
	return consumed if elapsed.ok else elapsed

func xp_multiplier() -> float:
	return super.xp_multiplier() * sim.services.needs.learning_factor()

func need_decay_per_minute(id: String) -> float:
	return 0.0 if id == "energy" else super.need_decay_per_minute(id)

func rest_energy_per_minute() -> float:
	# The main-game needs module owns stamina, including rest, at the actual bounds.
	return 0.0


func adjust_need(id: String, delta: float) -> void:
	if sim.services.has("growth") and id in sim.services.growth.NEED_IDS:
		if not sim.services.growth.enabled(id): sim.state.player.needs[id] = 100.0; return
		if delta < 0: delta *= sim.services.growth.decay_factor(id)
	super.adjust_need(id,delta)

func tick(minute: int) -> void:
	sim.services.growth.work_care()
	var before := float(sim.state.player.needs.health)
	super.tick(minute)
	if float(sim.state.player.needs.satiety) <= 0 and sim.services.growth.enabled("satiety"):
		var lost := maxf(0,before-float(sim.state.player.needs.health))
		super.adjust_need("health",minf(lost,0.05*(1-sim.services.growth.penalty_factor("satiety"))))
