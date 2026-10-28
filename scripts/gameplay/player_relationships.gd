extends "res://scripts/mechanics/npc_relationships.gd"
## Temporary personal comfort changes reception, without inventing moral harm.
func response_bias(actor: String, target: String, action: String) -> float:
	var npc: Dictionary = sim.state.social.npcs.get(target, {})
	if not npc.has("psychology"): return 0.0
	var result := super.response_bias(actor, target, action)
	if sim.services.has("antagonism"): result -= sim.services.antagonism.rumor_penalty(target,actor)
	if actor != "player": return result
	if npc.get("location", "") != sim.state.world.location: return result
	var hygiene := float(sim.state.player.needs.hygiene)
	if hygiene < 25.0 and action in ["connect", "court", "joke", "share_values"]:
		result -= (1.0 - hygiene / 25.0) * 0.10
	return clampf(result, -0.50, 0.30)
