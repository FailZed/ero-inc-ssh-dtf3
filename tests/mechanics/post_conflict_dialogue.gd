extends RefCounted
var t
var _world: Callable

func _init(runner, world_factory: Callable) -> void:
	t = runner
	_world = world_factory

func offered_world():
	var sim = _world.call()
	t.command(sim,"clock","advance",{"minutes":15})
	t._check(sim.services.npc_dialogue.offers().size()==1,"post-conflict fixture begins with a real autonomous offer")
	return sim

func run() -> void:
	var sim = offered_world()
	var offer: Dictionary = sim.services.npc_dialogue.offers()[0]
	t.command(sim,"combat","start",{"npc":"d0"})
	t._check(sim.services.npc_dialogue.offers().is_empty(),"an active fight hides earlier NPC approaches")
	sim.state.player.stats.agility = 100
	for attempt in range(30):
		if sim.state.encounters.combat.status != "active": break
		t.command(sim,"combat","action",{"action":"guard" if sim.state.encounters.combat.phase == "defence" else "escape"})
	t._check(not sim.command("npc_dialogue","open",{"id":"d0","initiative":str(offer.initiative)}).ok,"an old approach cannot be revived after the fight ends")
	sim = offered_world()
	var npc: Dictionary = sim.state.social.npcs.d0
	npc.pinned_until = int(sim.state.clock.total_minutes)+60
	offer = sim.services.npc_dialogue.offers()[0]
	t.command(sim,"world","travel",{"id":"apartment_hall"})
	t._check(sim.services.npc_dialogue.offers().is_empty(),"local offer is hidden while the player is elsewhere")
	t.command(sim,"world","travel",{"id":"global_map"})
	t._check(not sim.command("npc_dialogue","open",{"id":"d0","initiative":str(offer.initiative)}).ok,"leaving and returning between initiative ticks cannot revive a stale local offer")
	sim = offered_world()
	t.command(sim,"social","generate",{"id":"d1","template":"speaker"})
	offer = sim.services.npc_dialogue.offers()[0]
	t.command(sim,"npc_dialogue","open",{"id":"d0","initiative":str(offer.initiative)})
	t.command(sim,"combat","start",{"npc":"d1"})
	t._check(sim.state.social.npcs[str(offer.id)].mind.dialogue.pending.is_empty() and sim.state.social.npcs[str(offer.id)].mind.dialogue.node=="end","a fight also interrupts an already opened invitation from another resident")
	post_fight_reunion()
	context_changes()
	departure()

func escape(sim) -> void:
	sim.state.player.stats.agility = 100
	for attempt in range(30):
		if sim.state.encounters.combat.status != "active": break
		t.command(sim,"combat","action",{"action":"guard" if sim.state.encounters.combat.phase == "defence" else "escape"})
	t._check(sim.state.encounters.combat.status=="escaped","post-conflict fixture ends through a real escape action")

func post_fight_reunion() -> void:
	var sim = offered_world()
	var npc: Dictionary = sim.state.social.npcs.d0
	var old_token := str(npc.mind.dialogue.pending.token)
	t.command(sim,"npc_dialogue","open",{"id":"d0"})
	t._check(npc.mind.dialogue.pending.is_empty(),"opening a new ordinary conversation consumes the old approach")
	t.command(sim,"npc_dialogue","choose_menu",{"id":"d0","choice":"hg_fight","turn":int(npc.mind.dialogue.turn)})
	escape(sim)
	var completed: Dictionary = sim.state.encounters.combat.duplicate(true)
	var fine := int(sim.state.security.fine)
	var until := int(sim.services.npc_dialogue.conflict_space_until(npc))
	t._check(until>int(sim.state.clock.total_minutes),"recent violence gives the NPC time to keep their distance")
	var snapshot: Dictionary = sim.export_snapshot()
	sim.services.npc_dialogue.offers()
	sim.services.npc_dialogue.availability(npc)
	sim.services.npc_dialogue.conflict_space_until(npc)
	t._check(sim.export_snapshot()==snapshot,"post-fight availability and offers remain read only including RNG")
	npc.pinned_until = int(sim.state.clock.total_minutes)+60
	t.command(sim,"world","travel",{"id":"apartment_hall"})
	t.command(sim,"world","travel",{"id":"global_map"})
	var greeting: Dictionary = t.command(sim,"npc_dialogue","open",{"id":"d0"}).data
	t._check(greeting.node=="end" and greeting.utterance.ids[0]=="busy.boundary.0" and greeting.utterance.memory=="violence","the next actual meeting shows a refusal connected to the remembered fight")
	t._check(greeting.utterance.ids.size()==2 and str(greeting.utterance.ids[1]).begins_with("memory.violence."),"the refusal explains the conflict instead of claiming unrelated business")
	t._check(sim.state.encounters.combat==completed and int(sim.state.security.fine)==fine,"meeting again neither reopens combat nor repeats its fine or final outcome")
	snapshot = sim.export_snapshot()
	t._check(not sim.command("npc_dialogue","open",{"id":"d0","initiative":old_token}).ok and sim.export_snapshot()==snapshot,"old proposal cannot bypass the NPC's post-fight refusal")
	t._check(not sim.command("npc_dialogue","open",{"id":"d0","channel":"message"}).ok,"phone contact cannot bypass the same temporary boundary")
	npc = sim.state.social.npcs.d0
	var bond: Dictionary = sim.services.npc_relationships._bond("d0","player")
	var grievance := float(bond.grievance)
	t.command(sim,"npc_personalities","configure",{"id":"d0","facets":{"social_boldness":0}})
	var reserved_until := int(sim.services.npc_dialogue.conflict_space_until(npc))
	t.command(sim,"npc_personalities","configure",{"id":"d0","facets":{"social_boldness":100}})
	t._check(int(sim.services.npc_dialogue.conflict_space_until(npc))<reserved_until,"distance depends on the NPC's current character rather than a permanent hard-coded refusal")
	# Advance through the existing per-NPC/global initiative delays, without clearing harm.
	var resume := maxi(until,maxi(int(npc.mind.dialogue.last_initiative)+int(sim.services.npc_dialogue.rules().npc_cooldown),int(sim.state.social.dialogue.next_contact)))
	t.command(sim,"clock","advance",{"minutes":maxi(1,resume-int(sim.state.clock.total_minutes))})
	sim.services.npc_agency._cancel(npc,"test_reunion")
	npc.location = sim.state.world.location
	npc.activity = "idle"
	npc.decision = {"committed":false}
	npc.pinned_until = 0
	npc.needs.merge({"energy":100.0,"satiety":100.0,"hygiene":100.0,"social":60.0},true)
	t.command(sim,"clock","advance",{"minutes":15-posmod(int(sim.state.clock.total_minutes),15)})
	var offers: Array = sim.services.npc_dialogue.offers()
	t._check(offers.size()==1 and str(offers[0].initiative)!=old_token and npc.mind.dialogue.pending.get("kind","")=="concern","later voluntary contact receives a new token and addresses the current grievance")
	t._check(float(bond.grievance)>0 and not bond.consent and float(bond.grievance)<=grievance,"waiting and initiating contact do not forgive the aggression or create relationship agreement")
	if not offers.is_empty():
		t.command(sim,"npc_dialogue","open",{"id":"d0","initiative":str(offers[0].initiative)})
		var before := float(bond.grievance)
		var reply: Dictionary = t.command(sim,"npc_dialogue","choose",{"id":"d0","choice":"accept","turn":int(npc.mind.dialogue.turn)}).data
		t._check(reply.node=="feelings" and reply.utterance.memory=="violence" and is_equal_approx(float(bond.grievance),before),"accepting a new concern opens the existing memory branch without automatic reconciliation")

func context_changes() -> void:
	var sim = offered_world()
	var npc: Dictionary = sim.state.social.npcs.d0
	var token := str(npc.mind.dialogue.pending.token)
	t.command(sim,"npc_dialogue","open",{"id":"d0","initiative":token})
	npc.pinned_until = int(sim.state.clock.total_minutes)+60
	t.command(sim,"world","travel",{"id":"apartment_hall"})
	t.command(sim,"clock","advance",{"minutes":1})
	t._check(npc.mind.dialogue.node=="end" and npc.mind.dialogue.pending.is_empty(),"an opened invitation also ends when its in-person context disappears")
	var snapshot: Dictionary = sim.export_snapshot()
	t._check(not sim.command("npc_dialogue","choose",{"id":"d0","choice":"accept","turn":int(npc.mind.dialogue.turn)}).ok and sim.export_snapshot()==snapshot,"an old accept button cannot revive the ended invitation")
	sim = offered_world()
	npc = sim.state.social.npcs.d0
	token = str(npc.mind.dialogue.pending.token)
	sim.services.npc_relationships.harm("d0","player",25,"test_offer_context")
	snapshot = sim.export_snapshot()
	t._check(sim.services.npc_dialogue.offers().is_empty() and sim.export_snapshot()==snapshot,"new social harm invalidates an old friendly goal without read-side mutations")
	t._check(not sim.command("npc_dialogue","decline",{"id":"d0","initiative":token}).ok and sim.export_snapshot()==snapshot,"declining an outdated offer cannot resurrect a line or change cooldowns")
	npc = sim.state.social.npcs.d0
	t.command(sim,"clock","advance",{"minutes":1})
	t._check(npc.mind.dialogue.pending.is_empty(),"invalid context is pruned on the next world minute, not only at a fifteen-minute initiative tick")
	sim = _world.call()
	npc = sim.state.social.npcs.d0
	sim.state.world.location = "bedroom"
	t.command(sim,"clock","advance",{"minutes":15})
	t._check(sim.services.npc_dialogue.offers().size()==1,"remote context fixture creates a real phone approach")
	token = str(npc.mind.dialogue.pending.token)
	npc.pinned_until = int(sim.state.clock.total_minutes)+60
	t.command(sim,"world","travel",{"id":"apartment_hall"})
	t.command(sim,"world","travel",{"id":"global_map"})
	t._check(sim.services.npc_dialogue.offers().is_empty(),"an old remote invitation is not presented as current after an in-person meeting becomes possible")
	t.command(sim,"world","travel",{"id":"apartment_hall"})
	snapshot = sim.export_snapshot()
	t._check(not sim.command("npc_dialogue","open",{"id":"d0","channel":"message","initiative":token}).ok and sim.export_snapshot()==snapshot,"returning to a remote location cannot revive that phone token")
	t._check(not sim.state.social.messages.is_empty(),"invalidating an invitation preserves the actual phone message history")

func departure() -> void:
	var sim = offered_world()
	var npc: Dictionary = sim.state.social.npcs.d0
	var pending: Dictionary = npc.mind.dialogue.pending.duplicate(true)
	t.command(sim,"npc_dialogue","open",{"id":"d0"})
	# Recreate a restored in-progress cursor that still has an older pending card.
	npc.mind.dialogue.pending = pending
	npc.home = "training_center"
	sim.catalog.conversation_options.hg_drive.certain = true
	t.command(sim,"npc_dialogue","choose_menu",{"id":"d0","choice":"hg_drive","turn":int(npc.mind.dialogue.turn)})
	t._check(npc.location=="training_center" and npc.mind.dialogue.pending.is_empty() and npc.mind.dialogue.node=="end","a departure ends the contact and drops its old invitation")
	npc.location = sim.state.world.location
	var snapshot: Dictionary = sim.export_snapshot()
	t._check(not sim.command("npc_dialogue","open",{"id":"d0","initiative":str(pending.token)}).ok and sim.export_snapshot()==snapshot,"a later meeting cannot bring back the departed NPC's old proposal")
