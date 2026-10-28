extends RefCounted
const Factory = preload("res://scripts/mechanics/conversation_room.gd")
const Options = preload("res://scripts/mechanics/conversation_options.gd")
var t

func _init(runner) -> void: t = runner

func room() -> Dictionary:
	var result := Factory.create()
	result.session.open()
	return result

func choose(context: Dictionary, id: String) -> Dictionary:
	return context.session.choose(id,int(context.session.present().turn),true)

func run() -> void:
	preload("res://tests/mechanics/advanced.gd").new(t).combat_and_health()
	preload("res://tests/mechanics/parity.gd").new(t).formulas_and_turns()
	var context := room()
	var session: RefCounted = context.session
	var sim: RefCounted = context.simulation
	var before: Dictionary = sim.export_snapshot()
	var forecast := Options.new(sim).preview(session.actor(),"hg_fight")
	t._check(forecast.combat and sim.export_snapshot()==before,"combat preview is read only and describes a battle rather than a success roll")
	t._check(choose(context,"hg_fight").ok and session.combat_active(),"dialogue fight enters actual combat")
	t._check(session.combat().log.is_empty() and session.actor().health==100,"fight does not deduct invented fixed damage")
	t._check(int(sim.state.clock.total_minutes)==int(before.state.clock.total_minutes)+1,"starting dialogue combat charges one minute")
	before = sim.export_snapshot()
	t._check(not session.choose("day",int(session.present().turn),true).ok and sim.export_snapshot()==before,"social actions cannot interrupt combat or duplicate effects")
	session.close()
	t._check(session.active and session.combat_active(),"closing the session cannot discard an unfinished fight")
	t._check(not sim.services.combat.start(session.npc_id).ok,"starting a second fight cannot overwrite the encounter")
	t._check(not session.fight({"action":"guard","part":"head"}).ok,"guard requires an opponent response")
	var minute := int(sim.state.clock.total_minutes)
	t._check(session.fight({"action":"end_turn"}).ok and int(sim.state.clock.total_minutes)==minute,"passing the turn waits without advancing time")
	while session.combat().phase == "defence": session.fight({"action":"guard","part":"head"})
	t._check(int(sim.state.clock.total_minutes)==minute+1,"dialogue combat advances one minute per completed round")
	t._check(not session.combat().log.is_empty(),"NPC actually counterattacks")
	var saved: Dictionary = sim.export_snapshot()
	var restored := room()
	t._check(restored.simulation.restore_snapshot(saved).ok and restored.session.combat_active(),"active conversation battle restores in the existing snapshot")
	# Finish by actual attacks against an exhausted target; every strike still uses combat rules.
	sim.services.health.set_hp(session.npc_id,1)
	sim.state.player.stats.strength = 30
	for attempt in range(12):
		if not session.combat_active(): break
		var action := "attack" if int(session.combat().ap)>=2 and float(session.combat().stamina.player)>=8 else "recover"
		session.fight({"action":"guard" if session.combat().phase == "defence" else action,"move":"jab","part":"body"})
	t._check(session.combat().status=="won" and str(session.present().utterance.ids[0]).begins_with("conflict.won."),"victory produces a causal dialogue ending")
	t._check(sim.services.npc_dialogue.memory(session.actor())=="violence","next conversation remembers violence")
	before = sim.export_snapshot()
	t._check(not session.fight({"action":"attack"}).ok and sim.export_snapshot()==before,"resolved combat cannot award experience or damage twice")
	sim.catalog.conversation_options.hg_shave.certain = true
	sim.services.inventory.change("knife",1)
	sim.services.inventory.execute("equip",{"id":"knife"})
	var shaved := choose(context,"hg_shave")
	t._check(shaved.ok and session.actor().appearance.get("hair","")=="bald","post-fight action changes actual NPC appearance: "+str(shaved.get("error","")))
	before = sim.export_snapshot()
	t._check(not choose(context,"hg_shave").ok and sim.export_snapshot()==before,"shaving cannot be repeated on a bald NPC")
	for id: String in ["hg_beat","hg_stab"]:
		context = room()
		sim = context.simulation
		if id == "hg_stab":
			sim.services.inventory.change("knife",1)
			sim.services.inventory.execute("equip",{"id":"knife"})
		t._check(choose(context,id).ok and context.session.combat_active(),"physical dialogue action uses combat: "+id)
		t._check(context.session.combat().log.size()==1 and context.session.combat().log[0].move==("heavy" if id=="hg_beat" else "thrust"),"opening attack uses an actual combat move: "+id)
	context = room()
	sim = context.simulation
	before = sim.export_snapshot()
	t._check(not choose(context,"hg_stab").ok and sim.export_snapshot()==before,"unarmed knife attack rejects atomically")
	t._check(not choose(context,"hg_shave").ok and sim.export_snapshot()==before,"a resisting NPC cannot be shaved by selecting a menu entry")
	sim.state.social.contacts.append(context.session.npc_id)
	context.session.open("message")
	before = sim.export_snapshot()
	t._check(not choose(context,"hg_fight").ok and sim.export_snapshot()==before,"a message cannot start a physical fight")
	# A bold, impatient target answers a failed demand with force.
	context = room()
	sim = context.simulation
	var npc: Dictionary = context.session.actor()
	sim.services.npc_personalities.execute("configure",{"id":str(npc.id),"facets":{"social_boldness":100,"patience":0}})
	npc.stats.authority = 100
	sim.state.player.stats.authority = 1
	sim.rng.seed = 123
	var result := choose(context,"hg_extort")
	t._check(result.ok and not result.data.accepted and context.session.combat_active(),"resisted extortion may escalate according to NPC personality")
	# Fearful targets can leave; personality itself is not rewritten by pressure.
	context = room()
	sim = context.simulation
	npc = context.session.actor()
	sim.services.npc_personalities.execute("configure",{"id":str(npc.id),"facets":{"social_boldness":0,"patience":100}})
	npc.stats.authority = 100
	sim.state.player.stats.authority = 1
	npc.mind.fears["person:player"] = {"strength":60.0,"expires":int(sim.state.clock.total_minutes)+1440}
	# The minimal room has no residential district; provide a distinct known home.
	npc.home = "training_center"
	var personality: Dictionary = npc.psychology.duplicate(true)
	sim.rng.seed = 123
	result = choose(context,"hg_pressure")
	t._check(result.ok and result.data.outcome.reaction=="leave" and npc.location!=sim.state.world.location and context.session.present().node=="end","a frightened NPC can end contact and leave the scene")
	t._check(npc.psychology==personality and float(context.session.bond().grievance)>0,"psychological aggression creates remembered harm rather than replacing the character")
	# Witnesses react through the existing directed relationship rules.
	context = room()
	sim = context.simulation
	sim.command("social","generate",{"id":"witness","template":"live2d_speaker"})
	var witness: Dictionary = sim.state.social.npcs.witness
	witness.location = sim.state.world.location
	witness.activity = "idle"
	witness.pinned_until = int(sim.state.clock.total_minutes)+100
	sim.catalog.conversation_options.hg_threat.certain = true
	result = choose(context,"hg_threat")
	t._check(result.ok and result.data.outcome.witnesses==1 and sim.state.security.fine>=20,"witnessed aggression uses actual fines and witness count")
	t._check(float(sim.services.npc_relationships.view("witness","player").grievance)>0,"witnesses remember observed aggression")
	var grievance := float(sim.services.npc_relationships.view("witness","player").grievance)
	var fine := int(sim.state.security.fine)
	sim.catalog.conversation_options.hg_taunt.certain = true
	result = choose(context,"hg_taunt")
	t._check(result.ok and float(sim.services.npc_relationships.view("witness","player").grievance)>grievance and int(sim.state.security.fine)==fine,"witnesses also remember insults that carry no legal fine")
	context = room()
	sim = context.simulation
	npc = context.session.actor()
	sim.services.npc_personalities.execute("configure",{"id":str(npc.id),"facets":{"social_boldness":100,"patience":0}})
	sim.rng.seed = 123
	result = choose(context,"hg_steal")
	t._check(result.ok and not result.data.accepted and context.session.combat_active(),"a caught theft can provoke the target's actual counterattack")
	var opening_finished := false
	for seed_value in range(1,8):
		context = room()
		sim = context.simulation
		sim.services.health.set_hp(context.session.npc_id,11)
		sim.state.player.stats.strength = 30
		sim.state.player.stats.agility = 30
		sim.rng.seed = seed_value
		result = choose(context,"hg_beat")
		if result.ok and context.session.combat().status == "won":
			opening_finished = str(context.session.present().utterance.ids[0]).begins_with("conflict.won.") and context.session.present().utterance.get("narrated",false)
			break
	t._check(opening_finished,"an opening knockout keeps the final narrated reply instead of overwriting it with the attack introduction")
	for ending: String in ["escaped","lost","surrendered"]:
		context = room()
		sim = context.simulation
		session = context.session
		choose(context,"hg_fight")
		if ending == "lost":
			sim.services.health.set_hp("player",1)
			sim.state.social.npcs[session.npc_id].stats.strength = 30
		else:
			sim.state.player.stats["agility" if ending == "escaped" else "authority"] = 100
		for attempt in range(20):
			if not session.combat_active(): break
			session.fight({"action":"guard" if session.combat().phase == "defence" else "escape" if ending == "escaped" else "intimidate" if ending == "surrendered" else "end_turn"})
		t._check(session.combat().status==ending and str(session.present().utterance.ids[0]).begins_with("conflict."+ending+"."),"combat ending returns its own reply: "+ending)
		t._check(sim.validate_state(sim.state).ok,"combat ending leaves valid state: "+ending)
		var final_reply: Dictionary = session.present()
		session.combat().npc_hp = 0
		sim.services.combat._update_outcome()
		t._check(session.combat().status==ending and session.present()==final_reply,"later health synchronization cannot rewrite an already resolved outcome: "+ending)
