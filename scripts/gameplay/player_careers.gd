extends "res://scripts/mechanics/careers.gd"
## All non-interactive profession ranks follow the relevant skill in the main game.

func synchronize() -> void:
	for id in sim.catalog.livelihood_rules.profession_skills: _promote(str(id),0)

func _promote(id: String, _xp: int) -> void:
	var skill: String = sim.catalog.livelihood_rules.profession_skills[id]
	var progress: Dictionary = sim.state.careers.professions.get(id,{"level":1,"xp":0,"reputation":0})
	var before := int(progress.level)
	progress.level = sim.services.livelihood.skill_rank(skill)
	progress.xp = 0
	sim.state.careers.professions[id] = progress
	if int(progress.level) > before: emit_event("profession_promoted",{"id":id,"level":progress.level})

func _shift(id: String) -> Dictionary:
	if not sim.catalog.professions.has(id): return Rules.fail("shift_unavailable")
	synchronize()
	return super._shift(id)
