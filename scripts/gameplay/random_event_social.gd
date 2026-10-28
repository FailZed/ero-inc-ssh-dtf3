extends "res://scripts/mechanics/human_social.gd"
## Main-game messaging owner: stable message identities and explicit reply linkage.

func execute(operation: String, args: Dictionary) -> Dictionary:
	if operation == "read" and args.has("message_id"):
		var message_id: Variant = args.message_id
		if not message_id is int or message_id < 1: return Rules.fail("invalid_message")
		for message: Dictionary in sim.state.social.messages:
			if message.id == message_id and message.npc == args.get("id", ""):
				message.read = true
				return Rules.ok({"message_id":message_id})
		return Rules.fail("message_unavailable")
	var next_id := int(sim.state.social.next_message_id)
	var result := super.execute(operation,args)
	if result.ok and operation in ["message","call"]:
		return Rules.ok({"message_id":next_id})
	return result

func event_message(id: String, text: String, incoming: bool, instance: String, in_reply_to: int = 0, meaning: String = "") -> Dictionary:
	var result := execute("message",{"id":id,"text":text,"incoming":incoming})
	if not result.ok: return result
	var message: Dictionary = sim.state.social.messages.back()
	message.read = not incoming
	message.kind = "random_event"
	message.event_instance = instance
	message.in_reply_to = in_reply_to
	message.meaning = meaning
	return result
