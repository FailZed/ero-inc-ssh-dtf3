extends "res://scripts/mechanics/lifecycle.gd"
## A completed condition must not permanently prevent later family events.
func execute(operation: String, args: Dictionary) -> Dictionary:
	if operation == "start" and args.get("id", "") == "pregnancy" and "pregnancy" in sim.state.preferences.disabled_tags: return Rules.fail("content_disabled")
	var key := "%s:%s" % [str(args.get("target", "player")), str(args.get("id", ""))]
	if operation == "start" and sim.state.conditions.get(key, {}).get("status", "") == "completed": sim.state.conditions.erase(key)
	return super.execute(operation, args)
