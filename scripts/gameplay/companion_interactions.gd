extends "res://scripts/mechanics/core/module.gd"
## Shared social outcomes for pointer, touch and keyboard character interactions.
const GESTURES := {
	"hand": {"label":"Взять за руку", "zones":["hand_l","hand_r"], "trust":10.0,"closeness":5.0},
	"head": {"label":"Погладить по голове", "zones":["head"], "trust":25.0,"closeness":20.0},
	"face": {"label":"Коснуться щеки", "zones":["face"], "trust":35.0,"closeness":25.0}
}
const COOLDOWN := 180

func _init(simulation) -> void:
	super(simulation)
	sim.state_restored.connect(initialize)
	initialize()

func initialize() -> void:
	if not sim.state.has("companion"):
		sim.state.companion = {"serial":0,"active":{},"recent":{}}

func preview(id: String, gesture: String) -> Dictionary:
	var npc: Dictionary = sim.state.social.npcs.get(id,{})
	var reason := ""
	if npc.is_empty() or not npc.has("mind"): reason = "unknown_npc"
	elif not GESTURES.has(gesture): reason = "unknown_companion_gesture"
	elif int(npc.age) < 18: reason = "adult_required"
	elif int(sim.state.healthcare.records.get("player",{}).get("unconscious_until",0)) > int(sim.state.clock.total_minutes): reason = "recover_from_exhaustion"
	elif npc.location != sim.state.world.location: reason = "npc_not_present"
	elif not npc.mind.boundaries.contact: reason = "contact_boundary"
	else:
		var bond: Dictionary = sim.services.npc_relationships.view(id,"player")
		var spec: Dictionary = GESTURES[gesture]
		if float(bond.grievance) >= 10 or float(bond.comfort) < 0: reason = "unresolved_harm"
		elif float(bond.trust) < float(spec.trust) or float(bond.closeness) < float(spec.closeness): reason = "companion_needs_trust"
		elif gesture == "face" and (not npc.mind.boundaries.romance or "romance" in sim.state.preferences.disabled_tags): reason = "romantic_boundary"
		elif gesture == "face" and not sim.services.social_rules.compatibility("player",id).data.mutual_attraction: reason = "incompatible_attraction"
		elif int(sim.state.companion.recent.get(id,-COOLDOWN)) + COOLDOWN > int(sim.state.clock.total_minutes): reason = "companion_cooldown"
		else:
			var available: Dictionary = sim.services.social_rules.availability(id,true)
			if not available.ok: reason = str(available.error)
			elif npc.mind.active.get("phase","") == "receiving" or not str(npc.mind.active.get("partner","")).is_empty(): reason = "npc_busy"
	var chance := 0.0
	if reason.is_empty(): chance = float(sim.services.npc_relationships.forecast("player",id,"support").chance)
	return {"blocked":reason,"chance":chance}

func execute(operation: String, args: Dictionary) -> Dictionary:
	if operation == "offer":
		if not sim.state.companion.active.is_empty(): return Rules.fail("finish_companion_moment")
		var id := str(args.get("id",""))
		var gesture := str(args.get("gesture",""))
		var info := preview(id,gesture)
		if not str(info.blocked).is_empty(): return Rules.fail(info.blocked)
		var npc: Dictionary = sim.state.social.npcs[id]
		var elapsed := _advance(npc,1)
		if not elapsed.ok: return elapsed
		var accepted: bool = sim.rng.randf() < float(info.chance)
		if not accepted:
			sim.state.companion.recent[id] = int(sim.state.clock.total_minutes)
			_record(id,gesture,"declined")
			return Rules.ok({"accepted":false})
		sim.state.companion.serial += 1
		sim.state.companion.active = {"token":int(sim.state.companion.serial),"npc":id,"gesture":gesture,"offered_at":int(sim.state.clock.total_minutes)}
		return Rules.ok({"accepted":true,"session":sim.state.companion.active.duplicate(true)})
	if not operation in ["finish","cancel"]: return Rules.fail("unknown_operation")
	var session: Dictionary = sim.state.companion.active
	if session.is_empty() or args.get("token") != session.token: return Rules.fail("stale_companion_moment")
	var id := str(session.npc)
	var gesture := str(session.gesture)
	if operation == "cancel":
		sim.state.companion.active = {}
		_record(id,gesture,"cancelled")
		return Rules.ok({"cancelled":true})
	var elapsed_seconds: Variant = args.get("duration")
	if not elapsed_seconds is float and not elapsed_seconds is int: return Rules.fail("invalid_companion_duration")
	if not is_finite(float(elapsed_seconds)) or float(elapsed_seconds) < 0.5 or float(elapsed_seconds) > 60: return Rules.fail("invalid_companion_duration")
	if not str(args.get("zone","")) in GESTURES[gesture].zones: return Rules.fail("unagreed_companion_gesture")
	var info := preview(id,gesture)
	if not str(info.blocked).is_empty():
		sim.state.companion.active = {}
		_record(id,gesture,"interrupted")
		return Rules.ok({"cancelled":true,"reason":info.blocked})
	var npc: Dictionary = sim.state.social.npcs[id]
	var elapsed := _advance(npc,5)
	if not elapsed.ok: return elapsed
	info = preview(id,gesture)
	if not str(info.blocked).is_empty():
		sim.state.companion.active = {}
		_record(id,gesture,"interrupted")
		return Rules.ok({"cancelled":true,"reason":info.blocked})
	var relationships = sim.services.npc_relationships
	var bond: Dictionary = relationships._bond(id,"player")
	# Uses the same daily budget and repetition limit as ordinary support.
	var gain: float = relationships._gain(bond,"support",2.0)
	relationships._change(bond,{"comfort":gain,"affection":gain*0.5,"trust":gain*0.25,"closeness":gain*0.5})
	bond.last_contact = int(sim.state.clock.total_minutes)
	relationships._project(id,"player")
	if gain > 0:
		npc.needs.mood = minf(100,float(npc.needs.mood)+2)
		npc.needs.social = minf(100,float(npc.needs.social)+5)
		sim.services.npc_agency.record_social_experience(npc,"supported","player")
	sim.state.companion.recent[id] = int(sim.state.clock.total_minutes)
	sim.state.companion.active = {}
	_record(id,gesture,"completed")
	return Rules.ok({"accepted":true,"completed":true,"gain":gain})

func _advance(npc: Dictionary, minutes: int) -> Dictionary:
	sim.services.npc_agency._cancel(npc,"player_companion_moment")
	var pin := int(npc.pinned_until)
	npc.pinned_until = maxi(pin,int(sim.state.clock.total_minutes)+minutes+1)
	var result: Dictionary = sim.advance(minutes)
	npc.pinned_until = pin
	return result

func _record(id: String, gesture: String, outcome: String) -> void:
	var data := {"gesture":gesture,"outcome":outcome,"other":"player"}
	sim.services.npc_agency._log(sim.state.social.npcs[id],"companion",data)
	emit_event("companion_moment",{"npc":id,"gesture":gesture,"outcome":outcome})

static func state_error(state: Dictionary) -> String:
	var value: Variant = state.get("companion")
	if not value is Dictionary: return "invalid_companion_state"
	var serial: Variant = value.get("serial")
	if not _integer(serial,0,2147483647): return "invalid_companion_serial"
	if not value.get("recent") is Dictionary or not value.get("active") is Dictionary: return "invalid_companion_state"
	for id in value.recent:
		if not state.social.npcs.has(id) or not _integer(value.recent[id],0,int(state.clock.total_minutes)): return "invalid_companion_cooldown"
	var active: Dictionary = value.active
	if not active.is_empty():
		if not state.social.npcs.has(active.get("npc","")) or not GESTURES.has(active.get("gesture","")): return "invalid_companion_session"
		if not _integer(active.get("token"),1,int(serial)) or not _integer(active.get("offered_at"),0,int(state.clock.total_minutes)): return "invalid_companion_session"
	return ""

static func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) == int(value) and float(value) >= low and float(value) <= high
