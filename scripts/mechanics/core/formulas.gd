extends RefCounted
## Behavioral formulas researched in School. Inputs use EroInc's 0..100 scales.

static func dialogue_fatigue(trust: float, erudition: float, sociability: float, difficulty: float) -> float:
	var base := clampf((3.6 - trust * 0.003 - erudition * 0.01) * difficulty, 1.0, 4.0)
	return base * (2.0 - clampf(sociability, 0.0, 100.0) / 100.0)

static func auto_defence(experience: float) -> float:
	var xp := maxf(0.0, experience)
	return minf(74.0, 5.0 + xp * 0.38 / (1.0 + xp * 0.003)) / 100.0

static func target_switch(experience: float) -> float:
	var xp := maxf(0.0, experience)
	return minf(65.0, 10.0 + xp * 0.33 / (1.0 + xp * 0.0038)) / 100.0

static func mood_xp(mood: float) -> float:
	if mood >= 85: return 1.2
	if mood >= 75: return 1.1
	if mood < 20: return 0.7
	if mood < 40: return 0.9
	return 1.0

static func combat(strength: float, agility: float, defender_agility: float, _luck: float, move: Dictionary, weapon_damage: float, power: float, rules: Dictionary) -> Dictionary:
	var scale := float(rules.get("stat_scale", 4.0))
	var coefficient := float(move.get("damage", 1.0))
	var hit := float(rules.get("base_accuracy", 25.0)) + agility * scale * (1.0 - coefficient * 0.2) - defender_agility * scale * 0.1 + float(move.get("accuracy", 0.0)) * 100.0
	var damage := maxf(0.5, roundf(strength * scale / 4.0 * coefficient) + weapon_damage) * power
	return {"accuracy": hit / 100.0, "damage": damage,
		"critical": clampf((strength * scale + hit) * coefficient / 1000.0 + float(move.get("critical", 0)), 0.0, 0.5),
		"knockdown": clampf((strength * scale + hit) * 0.000125 * coefficient + float(move.get("knockdown", 0)), 0.0, 0.75)}
static func mastery(skill: float, scale: float = 200.0) -> float:
	var value := maxf(0, skill)
	return value / (value + maxf(1, scale))

static func career_pay(level: int, rules: Dictionary) -> float:
	return minf(float(rules.get("pay_cap", 2.5)), 1.0 + maxf(0, level - 1) * float(rules.get("pay_growth", 0.15)))

