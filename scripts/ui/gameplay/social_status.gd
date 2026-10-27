extends RefCounted
## Native widgets; callers refresh from Gameplay.changed, never from _process.
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const Social = preload("res://scripts/gameplay/social_presentation.gd")
const Names = preload("res://scripts/gameplay/presentation.gd")

static func life(parent: Node, sim, id: String) -> void:
	var view := Social.life(sim, id)
	if view.is_empty(): return
	UI.label(parent, str(view.emotion), 20, UI.BLUE)
	UI.label(parent, "Сейчас: " + str(view.activity), 19, UI.MUTED)
	var row := UI.row(parent)
	UI.label(row, "Личная цель: " + str(view.goal), 22)
	var percent := UI.label(row, "%d%%" % roundi(view.progress), 22, UI.ORANGE)
	percent.autowrap_mode = TextServer.AUTOWRAP_OFF
	percent.size_flags_horizontal = Control.SIZE_SHRINK_END
	var bar := ProgressBar.new()
	bar.name = "AspirationProgress"
	bar.value = float(view.progress)
	bar.show_percentage = false
	bar.custom_minimum_size.y = 7
	parent.add_child(bar)
	UI.label(parent, "Цель достигнута. Позже появится новая." if view.completed else "Этап %d из %d · результат складывается из настоящих занятий" % [view.stage, view.stages], 17, UI.MUTED)

static func relationship(parent: Node, sim, id: String) -> void:
	var view := Social.bond(sim, id)
	UI.label(parent, "ОТНОШЕНИЕ К ВАМ · " + str(view.status_text), 22, UI.BLUE)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 10)
	parent.add_child(grid)
	for key in Social.SCALES:
		var row := UI.row(grid, 8)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UI.label(row, str(Social.SCALES[key]), 18, UI.MUTED)
		var amount := float(view[key])
		var number := UI.label(row, "%d" % roundi(amount), 22, UI.ORANGE if (amount < 0 or key == "grievance" and amount > 0) else UI.BLUE)
		number.autowrap_mode = TextServer.AUTOWRAP_OFF
		number.size_flags_horizontal = Control.SIZE_SHRINK_END
	if float(view.grievance) > 0:
		UI.label(parent, "Вред признан. Доверие возвращают поступки в разные дни." if view.acknowledged else "Осталась обида. Сначала стоит признать причинённый вред.", 18, UI.ORANGE)
	var boundaries: Dictionary = sim.state.social.npcs[id].mind.boundaries
	var limits: Array[String] = []
	if not boundaries.contact: limits.append("не хочет общаться")
	if not boundaries.romance: limits.append("не принимает романтические инициативы")
	if not boundaries.gossip: limits.append("не обсуждает чужие новости")
	if not limits.is_empty(): UI.label(parent, "Личные границы: " + "; ".join(limits), 18, UI.ORANGE)

static func network(parent: Node, sim, id: String) -> void:
	var npc: Dictionary = sim.state.social.npcs[id]
	UI.label(parent, "С ДРУГИМИ ЛЮДЬМИ", 22, UI.BLUE)
	var peers: Array = npc.mind.bonds.keys()
	peers.erase("player")
	peers.sort_custom(func(a, b): return float(npc.mind.bonds[a].closeness) + float(npc.mind.bonds[a].grievance) > float(npc.mind.bonds[b].closeness) + float(npc.mind.bonds[b].grievance))
	for other in peers.slice(0, 6):
		var outgoing := Social.bond(sim, id, str(other))
		var incoming := Social.bond(sim, str(other), id)
		var card := UI.card(parent)
		UI.label(card, Social.actor_name(sim, str(other)), 21)
		UI.label(card, "%s → %s: %s · доверие %d" % [npc.name, Social.actor_name(sim, str(other)), outgoing.status_text, outgoing.trust], 18, UI.MUTED)
		UI.label(card, "В ответ: %s · доверие %d" % [incoming.status_text, incoming.trust], 18, UI.MUTED)
	if peers.is_empty(): UI.label(parent, "Близкие знакомства ещё появятся во встречах и общих делах.", 18, UI.MUTED)

static func recent(parent: Node, sim, id: String) -> void:
	UI.label(parent, "ЧТО ПРОИЗОШЛО", 22, UI.BLUE)
	var entries := Social.history(sim, id)
	for entry in entries:
		UI.label(parent, str(entry.text), 19)
		UI.label(parent, str(entry.time), 16, UI.MUTED)
	if entries.is_empty(): UI.label(parent, "История появится по мере жизни в городе.", 18, UI.MUTED)
