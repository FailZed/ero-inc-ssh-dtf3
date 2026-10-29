extends RefCounted
const Life = preload("res://scripts/mechanics/npc_life_simulation.gd")
const Human = preload("res://scripts/mechanics/core/human_validation.gd")
const Validate = preload("res://scripts/mechanics/core/dialogue_validation.gd")
var t

func _init(runner) -> void:
	t = runner

func world(count: int = 1):
	var template := {"age": 25, "home": "global_map", "role": "worker", "money": 100,
		"personalities": ["calm"], "goals": ["community"], "schedule": [], "activities": [],
		"gender": "female", "attracted_to": ["female"], "traits": {"sociability": 50}}
	var sim = Life.new(551, {"settings": {"start_minutes": 480}, "npc_templates": {"speaker": template}})
	t._check(sim.configuration_error.is_empty(), "dialogue catalog validates: " + sim.configuration_error)
	t.command(sim, "npc_agency", "enable")
	sim.state.world.location = "global_map"
	for i in range(count):
		var id := "d%d" % i
		t.command(sim, "social", "generate", {"id": id, "template": "speaker"})
		var facets := {}
		for key in Human.FACETS: facets[key] = 50
		t.command(sim, "npc_personalities", "configure", {"id": id, "facets": facets})
		var npc: Dictionary = sim.state.social.npcs[id]
		sim.services.npc_agency._cancel(npc, "test_dialogue")
		npc.location = "global_map"
		npc.activity = "idle"
		npc.decision = {"committed": false}
		npc.needs.merge({"energy": 100, "satiety": 100, "hygiene": 100, "fun": 80, "social": 60}, true)
		npc.mind.aspiration = {"id": "community", "stage": 0, "milestones": 0, "progress": 0, "completed": false}
		sim.state.social.contacts.append(id)
		sim.services.npc_relationships._bond(id, "player").trust = 20.0
	return sim

func open(sim, id: String = "d0", channel: String = "face", token: String = "") -> Dictionary:
	return t.command(sim, "npc_dialogue", "open", {"id": id, "channel": channel, "initiative": token}).get("data", {})

func choose(sim, key: String, id: String = "d0") -> Dictionary:
	return t.command(sim, "npc_dialogue", "choose", {"id": id, "choice": key, "turn": sim.state.social.npcs[id].mind.dialogue.turn}).get("data", {})

func pool(reply: Dictionary, prefix: String) -> bool:
	for id in reply.get("utterance", {}).get("ids", []):
		if str(id).begins_with(prefix + "."): return true
	return false

func run() -> void:
	preload("res://tests/mechanics/conversation_options.gd").new(t).run()
	preload("res://tests/mechanics/conversation_conflict.gd").new(t).run()
	preload("res://tests/mechanics/post_conflict_dialogue.gd").new(t,world).run()
	context_and_voice()
	causal_memory_and_repair()
	branching_and_costs()
	expanded_topics()
	adult_relationships()
	initiatives_and_messages()
	validation_and_replay()

func context_and_voice() -> void:
	var sim = world()
	var npc: Dictionary = sim.state.social.npcs.d0
	var d = sim.services.npc_dialogue
	var original: Dictionary = sim.export_snapshot()
	d.context(npc)
	d.present("d0")
	d.offers()
	t._check(sim.export_snapshot() == original, "reading dialogue, context and initiatives is pure")
	var cases := {
		"direct": {"gentleness": 0, "patience": 0, "sincerity": 100},
		"warm": {"sentimentality": 100, "gentleness": 100},
		"reserved": {"sociability": 0, "social_boldness": 0, "prudence": 100},
		"playful": {"liveliness": 100, "creativity": 100, "flexibility": 100},
		"practical": {"diligence": 100, "organization": 100, "prudence": 100},
		"reflective": {"inquisitiveness": 100, "aesthetic_appreciation": 100, "liveliness": 0},
		"outgoing": {"sociability": 100, "social_boldness": 100, "liveliness": 100}}
	for key in cases:
		for facet in Human.FACETS: npc.psychology.facets[facet] = 50
		npc.psychology.values.benevolence = 100 if key == "warm" else 50
		npc.psychology.facets.merge(cases[key], true)
		var reply := open(sim)
		t._check(d.voice(npc) == key and pool(reply, "greeting." + str(key)), "contrasting continuous personalities produce a distinct speaking voice: " + str(key))
	var random_state := str(sim.rng.state)
	var a := open(sim)
	var b := open(sim)
	t._check(a.utterance.text != b.utterance.text, "consecutive greetings avoid repeating the same line")
	t._check(str(sim.rng.state) == random_state, "line variety does not consume world RNG")
	npc.needs.energy = 20
	t._check(pool(open(sim), "mood.tired"), "low energy affects the actual greeting")
	npc.needs.energy = 100
	npc.mind.emotion.id = "happy"
	t._check(pool(open(sim), "mood.happy"), "a good mood changes the actual greeting")
	npc.psychology.interests.science = 100
	var interest := choose(sim, "interests")
	t._check(pool(interest, "interest.science") and not str(interest.utterance.text).contains("{plan}"), "hobby answer uses this resident's own interests and resolves variables")
	for goal in sim.catalog.agency_aspirations:
		t.command(sim, "npc_agency", "set_aspiration", {"id": "d0", "goal": goal})
		sim.services.npc_agency._cancel(npc, "test_goal")
		npc.location = "global_map"
		npc.activity = "idle"
		open(sim)
		var answer := choose(sim, "goal")
		t._check(pool(answer, "goal." + str(goal)), "goal answer describes the resident's actual aspiration: " + str(goal))
		var step := choose(sim, "plan")
		t._check(pool(step, "plan." + str(sim.catalog.agency_aspirations[goal].stages[0].action)), "follow-up describes the actual next action: " + str(goal))
	npc.mind.aspiration = {"id": "creativity", "stage": 3, "milestones": 3, "progress": 0, "completed": true}
	npc.mind.completed_at = int(sim.state.clock.total_minutes)
	open(sim)
	t._check(pool(choose(sim, "goal"), "goal.completed"), "a completed ambition is not described as unfinished")

func causal_memory_and_repair() -> void:
	var sim = world(3)
	var victim: Dictionary = sim.state.social.npcs.d0
	var witness: Dictionary = sim.state.social.npcs.d1
	var absent: Dictionary = sim.state.social.npcs.d2
	absent.location = "bedroom"
	# The actual observation route, also used by caught theft, gives evidence only to witnesses.
	sim.services.social.remember("d0", "crime", {"actor": "player"})
	t._check(sim.services.npc_dialogue.memory(victim) == "crime", "victim remembers the player action actually observed")
	t._check(sim.services.npc_dialogue.memory(witness) == "witness", "witness does not claim to be the victim")
	t._check(sim.services.npc_dialogue.memory(absent) == "none", "absent resident has no knowledge of the incident")
	var reply := open(sim)
	t._check(pool(reply, "memory.crime") and not pool(reply, "greeting.warm"), "harmful action replaces a friendly welcome with a consistent confrontation")
	choose(sim, "feelings")
	var minute := int(sim.state.clock.total_minutes)
	var old_trust := float(sim.services.npc_relationships.view("d0", "player").trust)
	var apology := choose(sim, "apologize")
	t._check(pool(apology, "answer.apologize") and int(sim.state.clock.total_minutes) == minute + 30, "dialogue apology is an actual timed social action")
	var bond: Dictionary = sim.services.npc_relationships.view("d0", "player")
	t._check(bond.acknowledged and float(bond.grievance) > 0 and float(bond.trust) == old_trust, "recognizing harm does not erase grievance or restore trust for free")
	t._check(pool(open(sim), "memory.acknowledged"), "the next meeting remembers the apology without claiming forgiveness")
	sim.services.npc_agency._cancel(victim, "test_repair")
	victim.location = "global_map"
	choose(sim, "goal")
	choose(sim, "help")
	t._check(sim.services.npc_dialogue.memory(victim) == "repair", "help after an apology changes the remembered repair stage")

func branching_and_costs() -> void:
	var sim = world()
	var before: Dictionary = sim.services.npc_relationships.view("d0", "player")
	var root := open(sim)
	var minute := int(sim.state.clock.total_minutes)
	choose(sim, "goal")
	t._check(int(sim.state.clock.total_minutes) == minute + 3 and sim.services.npc_relationships.view("d0", "player") == before, "a short question consumes only its time and grants no free relationship reward")
	var snapshot: Dictionary = sim.export_snapshot()
	var stale: Dictionary = sim.command("npc_dialogue", "choose", {"id": "d0", "choice": "goal", "turn": root.turn})
	t._check(not stale.ok and stale.error == "stale_dialogue_turn" and snapshot == sim.export_snapshot(), "stale UI choice fails atomically without consuming time or RNG")
	var helped := choose(sim, "help")
	t._check(helped.accepted and pool(helped, "answer.help"), "help branches to a real contextual NPC response")
	t._check(int(sim.state.clock.total_minutes) == minute + 63 and float(sim.services.npc_relationships.view("d0", "player").trust) > float(before.trust), "help uses the shared social rules and actual duration")
	before = sim.services.npc_relationships.view("d0", "player")
	choose(sim, "goal")
	t._check(pool(choose(sim, "help"), "answer.repeat"), "repeated gesture is recognized in speech")
	t._check(float(sim.services.npc_relationships.view("d0", "player").trust) == float(before.trust), "repeated gesture cannot farm trust through dialogue")
	choose(sim, "back")
	choose(sim, "leave")
	t._check(sim.services.npc_dialogue.present("d0").choices.is_empty(), "conversation has a terminal node")
	open(sim)
	t.command(sim, "npc_relationships", "boundary", {"id": "d0", "boundary": "contact", "allowed": false})
	before = sim.export_snapshot()
	t._check(not sim.command("npc_dialogue", "choose", {"id": "d0", "choice": "day", "turn": sim.state.social.npcs.d0.mind.dialogue.turn}).ok and sim.export_snapshot() == before, "new boundary takes effect on an already open conversation")
	# Genuine stale sessions also reject replay after time passes.
	sim = world()
	open(sim)
	sim.state.social.npcs.d0.pinned_until = 2000
	t.command(sim, "clock", "advance", {"minutes": 90})
	before = sim.export_snapshot()
	var expired: Dictionary = sim.command("npc_dialogue", "choose", {"id": "d0", "choice": "day", "turn": sim.state.social.npcs.d0.mind.dialogue.turn})
	t._check(not expired.ok and expired.error == "dialogue_expired" and before == sim.export_snapshot(), "expired sessions cannot be replayed")

func initiatives_and_messages() -> void:
	var sim = world()
	t.command(sim, "clock", "advance", {"minutes": 15})
	var offers: Array = sim.services.npc_dialogue.offers()
	t._check(offers.size() == 1 and offers[0].channel == "face", "an available NPC initiates a local conversation during real world advancement")
	if offers.is_empty(): return
	var offer: Dictionary = offers[0]
	var before: Dictionary = sim.services.npc_relationships.view("d0", "player")
	open(sim, "d0", "face", str(offer.initiative))
	choose(sim, "stop")
	var npc: Dictionary = sim.state.social.npcs.d0
	t._check(int(npc.mind.dialogue.quiet_until) == int(sim.state.clock.total_minutes) + 10080, "requesting space stops new approaches for seven game days")
	t._check(sim.services.npc_relationships.view("d0", "player") == before and sim.services.npc_dialogue.offers().is_empty(), "declining does not punish the player or keep the offer visible")
	t.command(sim, "clock", "advance", {"minutes": 120})
	t._check(sim.services.npc_dialogue.offers().is_empty(), "world advancement respects the initiative refusal")
	# A known, trusted contact elsewhere sends a real phone message, not a teleport.
	sim = world()
	sim.state.world.location = "bedroom"
	t.command(sim, "clock", "advance", {"minutes": 15})
	offers = sim.services.npc_dialogue.offers()
	t._check(offers.size() == 1 and offers[0].channel == "message" and sim.state.social.messages.size() == 1, "remote initiative becomes an incoming phone message")
	if offers.is_empty(): return
	var location := str(sim.state.social.npcs.d0.location)
	open(sim, "d0", "message", str(offers[0].initiative))
	var reply := choose(sim, "accept")
	t._check(reply.channel == "message" and reply.node == "goal" and sim.state.social.npcs.d0.location == location, "accepting a message keeps channel and location while answering about the actual goal")
	t._check(sim.state.social.messages.size() == 3 and not sim.state.social.messages[1].incoming and sim.state.social.messages[2].incoming, "phone stores both the player's chosen reply and NPC answer")
	var blocked_help := false
	for choice in reply.choices:
		if choice.id == "help": blocked_help = choice.blocked == "npc_not_present"
	t._check(blocked_help, "phone conversation cannot perform physical help remotely")
	for i in range(40):
		choose(sim, "back")
		choose(sim, "goal")
	t._check(sim.state.social.npcs.d0.mind.dialogue.history.size() == 16 and sim.state.social.npcs.d0.mind.dialogue.recent.size() <= 12 and sim.state.social.messages.size() == 64, "conversation and automatic phone history remain bounded after prolonged play")
	# Accepted grievance approaches should lead to the grievance, not an unrelated ambition.
	sim = world()
	sim.services.npc_relationships.harm("d0", "player", 40, "test")
	t.command(sim, "clock", "advance", {"minutes": 15})
	offers = sim.services.npc_dialogue.offers()
	if not offers.is_empty():
		open(sim, "d0", "face", str(offers[0].initiative))
		t._check(choose(sim, "accept").node == "feelings", "a confrontation opens the unresolved relationship topic")
	else: t._check(false, "grievance produces an available initiative")
	# No remote contact and no daytime availability means no invented message.
	sim = world()
	sim.state.social.contacts.clear()
	sim.state.world.location = "bedroom"
	t.command(sim, "clock", "advance", {"minutes": 15})
	t._check(sim.services.npc_dialogue.offers().is_empty() and sim.state.social.messages.is_empty(), "NPCs do not acquire the player's phone number implicitly")
	sim = world()
	t.command(sim, "clock", "advance", {"minutes": 15})
	var token := str(sim.services.npc_dialogue.offers()[0].initiative)
	sim.state.world.location = "bedroom"
	before = sim.export_snapshot()
	t._check(not sim.command("npc_dialogue", "open", {"id": "d0", "initiative": token}).ok and sim.export_snapshot() == before, "a local invitation is rechecked when the player has left")

func validation_and_replay() -> void:
	var sim = world()
	t.command(sim, "clock", "advance", {"minutes": 15})
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(sim.export_snapshot()))
	var restored = Life.new(551, {"settings": {"start_minutes": 480}, "npc_templates": {"speaker": sim.catalog.npc_templates.speaker}})
	t._check(restored.restore_snapshot(snapshot).ok, "JSON save restores pending NPC dialogue")
	t._check(restored.services.npc_dialogue.offers() == sim.services.npc_dialogue.offers(), "saved initiative retains its speaker, channel and actual line")
	var token := str(sim.services.npc_dialogue.offers()[0].initiative)
	open(sim, "d0", "face", token)
	open(restored, "d0", "face", token)
	t._check(choose(sim, "accept") == choose(restored, "accept"), "save restoration continues the same dialogue deterministically")
	var current: Dictionary = sim.export_snapshot()
	t._check(restored.restore_snapshot(current).ok and restored.services.npc_dialogue.present("d0") == sim.services.npc_dialogue.present("d0"), "an in-progress branching conversation survives snapshot restoration")
	t.command(sim, "clock", "advance", {"minutes": 180})
	for i in range(12): t.command(restored, "clock", "advance", {"minutes": 15})
	t._check(sim.export_snapshot() == restored.export_snapshot(), "initiative scheduling is identical for bulk and split world time")
	var bad: Dictionary = current.duplicate(true)
	bad.state.social.npcs.d0.mind.dialogue.history.append({"text": "invented"})
	var before: Dictionary = restored.export_snapshot()
	t._check(not restored.restore_snapshot(bad).ok and restored.export_snapshot() == before, "malformed saved dialogue is rejected without damaging the running world")
	var malformed: Dictionary = sim.catalog.duplicate(true)
	malformed.dialogue_nodes.goal.choices.append("missing")
	t._check(not Validate.catalog_error(malformed).is_empty(), "broken authoring graph cannot enter the runtime")
	malformed = sim.catalog.duplicate(true)
	malformed.dialogue_pools["greeting.warm"].variants[0].id = "goodbye.0"
	t._check(not Validate.catalog_error(malformed).is_empty(), "duplicate localized line IDs are rejected")

func expanded_topics() -> void:
	var sim = world(3)
	var npc: Dictionary = sim.state.social.npcs.d0
	for other in sim.state.social.npcs.values(): other.pinned_until = 2000
	open(sim)
	choose(sim, "more")
	choose(sim, "everyday")
	t._check(pool(choose(sim, "work"), "topic.work.worker"), "work conversation reflects actual employment role")
	choose(sim, "study")
	t._check(pool(sim.services.npc_dialogue.present("d0"), "topic.study.other"), "non-student does not invent university attendance")
	choose(sim, "back")
	choose(sim, "more")
	choose(sim, "everyday")
	npc.money = 4
	t._check(pool(choose(sim, "money"), "topic.money.low"), "money conversation reflects actual NPC resources")
	choose(sim, "back")
	choose(sim, "more")
	choose(sim, "personal")
	t._check(pool(choose(sim, "past"), "topic.past"), "past branch uses the generated biography")
	npc.biography.family.siblings = 2
	var family := choose(sim, "family")
	t._check(str(family.utterance.text).contains("2") and not str(family.utterance.text).contains("{"), "family answer uses actual family data rather than an invented backstory")
	npc.mind.fears.rejection = {"strength": 20.0, "expires": 2000}
	t._check(pool(choose(sim, "fears"), "topic.fears.rejection"), "personal worries follow the resident's remembered fear")
	choose(sim, "back")
	choose(sim, "more")
	t._check(pool(choose(sim, "news"), "topic.news.none"), "resident without evidence does not invent gossip")
	# The claim is unverified, its hidden reference is deliberately different.
	var p = sim.services.npc_personalities
	p._store(npc, "claims", p._fact("d1", "d2", "occupation", "student", false, "worker"), 8)
	choose(sim, "back")
	choose(sim, "more")
	var news := choose(sim, "news")
	t._check(str(news.utterance.text).contains("учится") and str(news.utterance.text).contains("не проверено") and str(news.utterance.text).contains(str(sim.state.social.npcs.d2.name)), "unverified news preserves its known value and source and warns of uncertainty")
	t._check(not str(news.utterance.text).contains("работает"), "dialogue cannot read a claim's hidden ground truth")
	p._store(npc, "knowledge", p._fact("d1", "d2", "achievement", 2, true, 2), 16)
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(sim.export_snapshot()))
	var restored = Life.new(551, {"settings": {"start_minutes": 480}, "npc_templates": {"speaker": sim.catalog.npc_templates.speaker}})
	t._check(restored.restore_snapshot(snapshot).ok, "public news survives JSON serialization")
	choose(sim, "back"); choose(restored, "back")
	choose(sim, "more"); choose(restored, "more")
	t._check(choose(sim, "news").utterance.text == choose(restored, "news").utterance.text, "numeric achievements keep the same spoken form after loading")

func blocked_choice(sim, id: String, reason: String) -> bool:
	for choice in sim.services.npc_dialogue.present("d0").choices:
		if choice.id == id: return str(choice.blocked) == reason
	return false

func adult_relationships() -> void:
	var sim = world(2)
	var npc: Dictionary = sim.state.social.npcs.d0
	for other in sim.state.social.npcs.values(): other.pinned_until = 2000
	open(sim)
	choose(sim, "more")
	choose(sim, "adult")
	t._check(blocked_choice(sim, "desire", "insufficient_closeness"), "personal attraction is not disclosed to a stranger on demand")
	choose(sim, "boundaries")
	t._check(not sim.services.npc_dialogue.present("d0").utterance.text.is_empty(), "adult boundary conversation has actual authored lines")
	var bond: Dictionary = sim.services.npc_relationships._bond("d0", "player")
	bond.trust = 60
	bond.closeness = 50
	bond.interest = 40
	npc.attracted_to = ["male"]
	choose(sim, "back")
	choose(sim, "more")
	choose(sim, "adult")
	t._check(blocked_choice(sim, "desire", "private_conversation_required"), "sensitive attraction topic is unavailable with witnesses nearby")
	sim.state.social.npcs.d1.location = "bedroom"
	t._check(blocked_choice(sim, "desire", ""), "private conversation becomes available with trust and mutual interest")
	var before: Dictionary = sim.services.npc_relationships.view("d0", "player")
	var desire := choose(sim, "desire")
	t._check(pool(desire, "topic.desire.direct") or pool(desire, "topic.desire.warm") or pool(desire, "topic.desire.reserved"), "adult attraction has a personality-dependent spoken response")
	t._check(sim.services.npc_relationships.view("d0", "player") == before, "discussing desire does not manufacture attraction or consent")
	npc.psychology.facets.prudence = 100
	t._check(pool(choose(sim, "intimacy"), "topic.intimacy.slow"), "a cautious NPC asks to slow down despite strong affection")
	choose(sim, "boundaries")
	choose(sim, "safer_intimacy")
	var state: Dictionary = sim.export_snapshot()
	t._check(not str(sim.services.npc_dialogue.present("d0").utterance.text).is_empty() and state.state.conditions.is_empty(), "discussion of sexual health has no automatic physical or lifecycle outcome")
	choose(sim, "back")
	choose(sim, "more")
	choose(sim, "romance")
	t._check(pool(choose(sim, "attraction"), "topic.attraction.yes"), "attraction answer agrees with actual mutual romantic interest")
	choose(sim, "expectations")
	choose(sim, "jealousy")
	t._check(pool(sim.services.npc_dialogue.present("d0"), "topic.jealousy.calm"), "jealousy topic discusses attitude without inventing a player betrayal")
	choose(sim, "back")
	choose(sim, "more")
	choose(sim, "romance")
	sim.rng.seed = 42
	t._check(choose(sim, "partner").accepted and sim.services.npc_dialogue._is_partner(npc), "relationship proposal in dialogue reaches the shared mutual-agreement rules")
	# Respect live NPC boundaries and current content filters even in an open menu.
	open(sim)
	choose(sim, "more")
	choose(sim, "adult")
	t.command(sim, "npc_relationships", "boundary", {"id": "d0", "boundary": "romance", "allowed": false})
	t._check(blocked_choice(sim, "desire", "romantic_boundary"), "a live romantic boundary blocks intimate follow-ups")
	t._check(pool(choose(sim, "boundaries"), "topic.boundaries.closed"), "NPC explicitly voices its current refusal of romantic intimacy")
	choose(sim, "back")
	choose(sim, "more")
	t.command(sim, "preferences", "content_tag", {"id": "adult", "enabled": false})
	t._check(not blocked_choice(sim, "adult", ""), "disabled adult category is absent from current choices")
	state = sim.export_snapshot()
	t._check(not sim.command("npc_dialogue", "choose", {"id": "d0", "choice": "adult", "turn": npc.mind.dialogue.turn}).ok and sim.export_snapshot() == state, "hidden adult topic cannot be opened through a forged command")
	t.command(sim, "preferences", "content_tag", {"id": "romance", "enabled": false})
	t._check(not blocked_choice(sim, "romance", ""), "romance category respects the independent world filter")
	# Safety is part of the world schema too, not just a hidden button.
	state = sim.export_snapshot()
	var invalid := state.duplicate(true)
	invalid.state.player.age = 17
	t._check(not sim.restore_snapshot(invalid).ok and sim.export_snapshot() == state, "adult protagonist requirement is validated on restored worlds")
	# NPCs may express romantic interest, but a changed boundary invalidates the offer.
	sim = world()
	npc = sim.state.social.npcs.d0
	npc.attracted_to = ["male"]
	bond = sim.services.npc_relationships._bond("d0", "player")
	bond.merge({"trust": 60, "closeness": 50, "interest": 40}, true)
	npc.mind.aspiration = {"id": "relationship", "stage": 0, "milestones": 0, "progress": 0, "completed": false}
	t.command(sim, "clock", "advance", {"minutes": 15})
	var offers: Array = sim.services.npc_dialogue.offers()
	t._check(offers.size() == 1 and npc.mind.dialogue.pending.kind == "romance", "a resident with an actual relationship goal and mutual interest can initiate romantic conversation")
	if not offers.is_empty():
		var pending_state: Dictionary = sim.export_snapshot()
		t.command(sim, "preferences", "content_tag", {"id": "romance", "enabled": false})
		t._check(sim.services.npc_dialogue.offers().is_empty(), "disabling romance immediately hides an already pending romantic initiative")
		t._check(sim.restore_snapshot(pending_state).ok, "pending romantic initiative can be restored for continuation")
		open(sim, "d0", "face", str(offers[0].initiative))
		t._check(choose(sim, "accept").node == "romance" and not sim.services.npc_dialogue._is_partner(npc), "accepting romantic conversation is separate from agreeing to a relationship")
	# An invitation about an old goal must not keep claiming the old intention.
	sim = world()
	t.command(sim, "clock", "advance", {"minutes": 15})
	npc = sim.state.social.npcs.d0
	var token := str(npc.mind.dialogue.pending.token)
	t.command(sim, "npc_agency", "set_aspiration", {"id": "d0", "goal": "creativity"})
	t._check(sim.services.npc_dialogue.offers().is_empty(), "changed personal goal invalidates the old invitation before it is displayed")
	state = sim.export_snapshot()
	t._check(not sim.command("npc_dialogue", "open", {"id": "d0", "initiative": token}).ok and sim.export_snapshot() == state, "outdated goal invitation cannot be accepted from a stale UI")
