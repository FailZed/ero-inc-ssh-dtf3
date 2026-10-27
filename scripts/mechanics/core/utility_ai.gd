extends RefCounted
## Pure, normalized response curves. No RNG and no mutation during inspection.

static func curve(value: float, kind: String = "linear", power: float = 2.0) -> float:
	var x := clampf(value, 0.0, 1.0)
	match kind:
		"quadratic", "exponential": return pow(x, maxf(0.01, power))
		"sigmoid": return x * x * (3.0 - 2.0 * x)
		"inverse": return 1.0 - x
	return x

static func combine(considerations: Array, weights: Array = []) -> float:
	if considerations.is_empty(): return 0.0
	var total := 0.0
	var mass := 0.0
	for i in range(considerations.size()):
		var weight := maxf(0.0, float(weights[i])) if i < weights.size() else 1.0
		total += clampf(float(considerations[i]), 0.0, 1.0) * weight
		mass += weight
	return total / mass if mass > 0.0 else 0.0

static func choose(candidates: Array, current: String = "", hysteresis: float = 0.04) -> Dictionary:
	var winner: Dictionary = {}
	var best := -1.0
	# Strict comparison gives stable tie-breaking in catalog order.
	for candidate in candidates:
		if not candidate.get("available", true): continue
		var score := clampf(float(candidate.get("score", 0.0)), 0.0, 1.0)
		if candidate.id == current: score += maxf(0.0, hysteresis)
		if score > best:
			winner = candidate
			best = score
	return winner.duplicate(true)
