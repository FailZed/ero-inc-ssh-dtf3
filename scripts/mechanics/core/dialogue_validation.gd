extends RefCounted
const Human = preload("res://scripts/mechanics/core/human_validation.gd")
const Options = preload("res://scripts/mechanics/conversation_options.gd")
const NODES := ["root", "day", "goal", "plan", "interests", "feelings", "answer", "initiative", "end", "more", "everyday", "personal", "work", "study", "home", "money", "past", "family", "fears", "news", "romance", "attraction", "expectations", "jealousy", "adult", "desire", "intimacy", "boundaries", "privacy", "safer_intimacy"]

static func line_ids(catalog: Dictionary) -> Array:
	var ids: Array = []
	for pool in catalog.dialogue_pools.values():
		for line in pool.variants: ids.append(str(line.id))
	return ids

static func catalog_error(catalog: Dictionary) -> String:
	if not catalog.has("dialogue_rules"): return ""
	for key in ["dialogue_rules", "dialogue_pools", "dialogue_labels", "dialogue_choices", "dialogue_nodes", "dialogue_goals", "dialogue_values", "dialogue_biography"]:
		if not catalog.get(key) is Dictionary or catalog[key].is_empty(): return "invalid_dialogue_catalog"
	var rules: Variant = catalog.dialogue_rules.get("simulation")
	if not rules is Dictionary: return "invalid_dialogue_rules"
	for key in ["history_limit", "recent_lines", "topic_limit", "global_cooldown", "npc_cooldown", "refusal_cooldown", "stop_cooldown", "offer_duration", "session_duration", "message_limit"]:
		if not Human.integer(rules.get(key), 1, 10080): return "invalid_dialogue_rule"
	if int(rules.history_limit) > 32 or int(rules.recent_lines) > 32 or int(rules.topic_limit) > 64 or int(rules.message_limit) > 128: return "invalid_dialogue_memory_limit"
	if int(rules.topic_limit) < NODES.size(): return "invalid_dialogue_topic_limit"
	var seen: Array = []
	for key in catalog.dialogue_pools:
		var pool: Variant = catalog.dialogue_pools[key]
		if not pool is Dictionary or not pool.get("variants") is Array or pool.variants.is_empty(): return "invalid_dialogue_pool"
		for line in pool.variants:
			if not line is Dictionary or not line.get("id") is String or not line.get("ru") is String: return "invalid_dialogue_line"
			if line.id.is_empty() or line.id in seen or line.ru.is_empty() or line.ru.length() > 1000: return "invalid_dialogue_line_id"
			seen.append(line.id)
	var required := ["goodbye", "gone", "plan.generic", "goal.completed", "topic.boundaries.closed"]
	for voice in ["direct", "warm", "reserved", "playful", "practical", "reflective", "outgoing"]:
		required.append("greeting." + voice)
		required.append("voice." + voice)
		required.append("strained." + voice)
	for mood in ["tired", "hungry", "angry", "anxious", "lonely", "inspired", "happy", "neutral"]: required.append("mood." + mood)
	for memory in ["crime", "violence", "promise", "missed", "witness", "harm", "repair", "acknowledged", "help", "gift", "none"]: required.append("memory." + memory)
	for goal in catalog.agency_aspirations:
		required.append("goal." + str(goal))
		if not catalog.dialogue_goals.get(goal, {}).get("intent") is String: return "missing_dialogue_goal"
	for interest in catalog.human_interests: required.append("interest." + str(interest))
	for value in catalog.human_values:
		if not catalog.dialogue_values.get(value, {}).get("text") is String: return "missing_dialogue_value"
	for answer in ["help", "support", "joke", "apologize", "court", "invite_relationship", "share_values", "connect", "decline", "repeat", "space"]: required.append("answer." + answer)
	for kind in ["goal", "gratitude", "lonely", "concern", "message", "romance"]: required.append("initiative." + kind)
	for kind in ["sleep", "eat", "work", "study", "social", "generic", "boundary"]: required.append("busy." + kind)
	for kind in ["close", "positive", "distant"]: required.append("feelings." + kind)
	for kind in ["more", "everyday", "personal", "work.worker", "work.learner", "work.other", "study.learner", "study.other", "home", "money.low", "money.stable", "past", "family", "fears.rejection", "fears.stagnation", "fears.poverty", "fears.general", "news.none", "news.occupation", "news.achievement", "romance.distant", "romance.interested", "romance.partner", "attraction.yes", "attraction.no", "expectations.security", "expectations.autonomy", "expectations.care", "jealousy.anxious", "jealousy.calm", "adult", "intimacy.ready", "intimacy.slow", "privacy", "safer_intimacy"]: required.append("topic." + kind)
	for topic in ["desire", "boundaries"]:
		for style in ["reserved", "direct", "warm"]: required.append("topic." + topic + "." + style)
	for field in ["origins", "homes", "roles", "occupations"]:
		if not catalog.dialogue_biography.get(field) is Dictionary: return "invalid_dialogue_lexicon"
		for value in catalog.dialogue_biography[field].values():
			if not value is String or value.is_empty(): return "invalid_dialogue_biography_label"
	for key in required:
		if not catalog.dialogue_pools.has(key): return "missing_dialogue_pool:" + str(key)
	for node in NODES:
		if not catalog.dialogue_nodes.get(node) is Dictionary or not catalog.dialogue_nodes[node].get("choices") is Array: return "invalid_dialogue_node"
		for choice in catalog.dialogue_nodes[node].choices:
			if not catalog.dialogue_choices.has(choice): return "invalid_dialogue_edge"
	for choice in catalog.dialogue_choices.values():
		if not choice is Dictionary or not choice.get("to") in NODES or not choice.get("action") is String: return "invalid_dialogue_choice"
		if not Human.integer(choice.get("minutes"), 0, 120) or not catalog.dialogue_labels.get(choice.get("label"), {}).get("ru") is String: return "invalid_dialogue_choice_label"
		if not choice.action.is_empty() and (not catalog.agency_actions.has(choice.action) or not catalog.agency_actions[choice.action].get("social", false)): return "invalid_dialogue_action"
		for key in ["min_trust", "min_closeness", "min_interest"]:
			if choice.has(key) and not Human.number(choice[key], -100 if key == "min_trust" else 0, 100): return "invalid_dialogue_requirement"
		for key in ["mutual", "private", "gossip"]:
			if choice.has(key) and not choice[key] is bool: return "invalid_dialogue_condition"
		if not choice.get("tags", []) is Array: return "invalid_dialogue_tags"
		for tag in choice.get("tags", []):
			if not tag in ["romance", "adult"]: return "invalid_dialogue_tag"
	return Options.catalog_error(catalog)

static func utterance_error(value: Variant, ids: Array, npc_id: String, now: int) -> bool:
	if not value is Dictionary or not value.get("text") is String or value.text.is_empty() or value.text.length() > 2500: return true
	if value.get("speaker") != npc_id or not value.get("topic") in NODES or not value.get("expression") in ["neutral", "attentive", "smile", "concern", "angry"]: return true
	if not Human.integer(value.get("minute"), 0, now) or not value.get("ids") is Array or value.ids.is_empty() or value.ids.size() > 3: return true
	for key in value.ids:
		if not key in ids: return true
	for key in ["voice", "mood", "memory"]:
		if not value.get(key) is String: return true
	return false

static func state_error(state: Dictionary, catalog: Dictionary) -> String:
	if not catalog.has("dialogue_rules") or not state.world.flags.get("npc_agency_enabled", false): return ""
	var now := int(state.clock.total_minutes)
	var rules: Dictionary = catalog.dialogue_rules.simulation
	var world: Variant = state.social.get("dialogue")
	if not world is Dictionary or not Human.integer(world.get("serial"), 0, 2147483647) or not Human.integer(world.get("next_contact"), 0, 2147483647): return "invalid_dialogue_world"
	var ids := line_ids(catalog)
	var pending_count := 0
	for npc in state.social.npcs.values():
		var d: Variant = npc.mind.get("dialogue")
		if not d is Dictionary or d.get("version") != 1: return "invalid_npc_dialogue"
		if not d.get("node") in NODES or not d.get("channel") in ["face", "message"] or not Human.integer(d.get("turn"), 0, 2147483647): return "invalid_dialogue_cursor"
		for field in ["expires", "quiet_until"]:
			if not Human.integer(d.get(field), 0, 2147483647): return "invalid_dialogue_time"
		if not Human.integer(d.get("last_initiative"), -1440, now): return "invalid_dialogue_initiative_time"
		if not d.get("utterance") is Dictionary or (not d.utterance.is_empty() and utterance_error(d.utterance, ids, str(npc.id), now)): return "invalid_dialogue_utterance"
		if not d.get("recent") is Array or d.recent.size() > int(rules.recent_lines): return "invalid_dialogue_recency"
		for id in d.recent:
			if not id in ids: return "unknown_dialogue_line"
		if not d.get("history") is Array or d.history.size() > int(rules.history_limit): return "invalid_dialogue_history"
		for line in d.history:
			if utterance_error(line, ids, str(npc.id), now): return "invalid_dialogue_history_line"
		if not d.get("topics") is Dictionary or d.topics.size() > int(rules.topic_limit): return "invalid_dialogue_topics"
		for key in d.topics:
			if not key in NODES or not Human.integer(d.topics[key], 0, 2147483647): return "invalid_dialogue_topic"
		if not d.get("pending") is Dictionary: return "invalid_dialogue_initiative"
		if d.pending.is_empty(): continue
		pending_count += 1
		var p: Dictionary = d.pending
		if not p.get("token") is String or not str(p.token).begins_with(str(npc.id) + ":") or not p.get("kind") in ["goal", "gratitude", "lonely", "concern", "romance"] or not p.get("channel") in ["face", "message"]: return "invalid_dialogue_offer"
		if not Human.integer(p.get("created"), 0, now) or not Human.integer(p.get("expires"), int(p.get("created", 0)) + 1, 2147483647): return "invalid_dialogue_offer_time"
		if p.kind == "goal" and (not catalog.agency_aspirations.has(p.get("goal_id")) or not Human.integer(p.get("goal_stage"), 0, 11)): return "invalid_dialogue_offer_goal"
		if utterance_error(p.get("utterance"), ids, str(npc.id), now): return "invalid_dialogue_offer_line"
	if pending_count > 1: return "too_many_dialogue_offers"
	return ""
