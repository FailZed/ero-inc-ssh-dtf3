extends "res://scripts/mechanics/preferences.gd"
func rule(key: String, fallback: Variant = 1.0) -> Variant:
	if key == "satiety_enabled" and sim.state.has("growth") and sim.state.growth.need_overrides.has("satiety"): return bool(sim.state.growth.need_overrides.satiety)
	return super.rule(key,fallback)
