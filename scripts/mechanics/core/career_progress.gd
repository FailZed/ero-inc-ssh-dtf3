extends RefCounted
## Shared skill curve and automatic career gates for players and NPCs.
const SKILL_GATES := [0,2,4,6,8]
const RANK_PAY := 0.08

static func skill_level(raw: float) -> int:
	return clampi(int(sqrt(maxf(0.0,raw)/10.0)),0,10)

static func rank(raw: float, gates: Array = SKILL_GATES) -> int:
	var level := skill_level(raw)
	var result := 1
	for gate in gates.slice(1):
		if level < int(gate): break
		result += 1
	return result

static func pay_factor(rank_level: int) -> float:
	return 1.0+RANK_PAY*(clampi(rank_level,1,5)-1)

static func work_rank(raw: float, xp: int, automatic: bool, gates: Array, experience: Array) -> int:
	var skill := skill_level(raw)
	var result := 1
	for index in range(1,gates.size()):
		if skill<int(gates[index]) or (not automatic and xp<int(experience[index])): break
		result = index+1
	return result
