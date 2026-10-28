extends "res://scripts/gameplay/city_agency.gd"
## Keep ordinary autonomy authoritative; observe genuine accepted social reservations.

func _start(npc: Dictionary, action: String, destination: String, partner: String, reason: String) -> void:
	var tracked: bool = action == "connect" and sim.services.events.trackable_pair(str(npc.id),partner)
	if tracked and npc.location == destination:
		if not sim.services.events.pair_available(str(npc.id),partner,action_minutes(npc,action)+int(rules().decision_minutes)-1):
			return
		var willingness: Dictionary = sim.services.npc_relationships.forecast(str(npc.id),partner,action)
		if not str(willingness.blocked).is_empty() or sim.rng.randf() >= float(willingness.chance):
			return
	super._start(npc,action,destination,partner,reason)
	if tracked and npc.mind.active.get("phase","") == "action":
		sim.services.events.visit_started(str(npc.id),partner,npc.mind.active)

func _cancel(npc: Dictionary, reason: String) -> void:
	var active: Dictionary = npc.mind.active.duplicate(true)
	super._cancel(npc,reason)
	if not active.is_empty() and not str(active.get("partner","")).is_empty():
		sim.services.events.visit_cancelled(str(npc.id),str(active.partner),int(active.started),reason)

func _social_outcome(npc: Dictionary, active: Dictionary) -> bool:
	var accepted := super._social_outcome(npc,active)
	sim.services.events.visit_finished(str(npc.id),str(active.partner),int(active.started),accepted)
	return accepted

func begin_event_visit(a: String, b: String, instance: String) -> bool:
	var duration: int = sim.services.events.visit_horizon()
	if not sim.services.events.pair_available(a,b,duration): return false
	var npc: Dictionary = sim.state.social.npcs[a]
	_cancel(npc,"agreed_event_visit")
	_cancel(sim.state.social.npcs[b],"agreed_event_visit")
	# Both participants already agreed in the timed proposal; do not roll consent twice.
	super._start(npc,"connect",str(npc.location),b,"agreed_event_visit")
	if npc.mind.active.get("partner","") != b: return false
	sim.services.events.visit_started(a,b,npc.mind.active,instance)
	return true
