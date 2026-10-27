extends "res://scripts/mechanics/social.gd"

func execute(operation: String, args: Dictionary) -> Dictionary:
	if sim.services.npc_agency.enabled() and operation in ["gift", "invite", "message", "call", "appointment"]:
		var npc: Dictionary = sim.state.social.npcs.get(str(args.get("id", "")), {})
		if npc.has("mind") and not npc.mind.boundaries.contact: return Rules.fail("contact_boundary")
	return super.execute(operation, args)

func change_relationship(a: String, b: String, changes: Dictionary) -> void:
	if not sim.services.npc_agency.enabled():
		super.change_relationship(a, b, changes)
		return
	sim.services.npc_relationships.legacy_change(a, b, changes)

func _interact(id: String, action_id: String) -> Dictionary:
	if not sim.services.npc_agency.enabled(): return super._interact(id, action_id)
	return sim.services.npc_relationships.execute("interact", {"id": id, "action": action_id})
