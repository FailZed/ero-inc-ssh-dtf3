extends RefCounted
const Factory = preload("res://scripts/mechanics/conversation_room.gd")
var t
func _init(runner) -> void: t = runner

func prepared() -> Dictionary:
	var room := Factory.create()
	var sim: RefCounted = room.simulation
	var npc: Dictionary = sim.state.social.npcs[room.config.npc_id]
	var bond: Dictionary = sim.services.npc_relationships._bond(str(npc.id),"player")
	bond.merge({"trust":80.0,"comfort":60.0,"closeness":60.0,"interest":50.0},true)
	sim.state.economy.cash = 1000
	room.session.open()
	return room

func choose(room: Dictionary, id: String) -> Dictionary:
	return room.session.choose(id,int(room.session.present().turn),true)

func run() -> void:
	var catalog_room := prepared()
	var catalog: Dictionary = catalog_room.simulation.catalog.conversation_options
	t._check(catalog.size()==73,"complete authored non-explicit conversation catalog")
	for id: String in catalog:
		var room := prepared()
		var sim: RefCounted = room.simulation
		var npc: Dictionary = room.session.actor()
		var bond: Dictionary = sim.services.npc_relationships._bond(str(npc.id),"player")
		var spec: Dictionary = sim.catalog.conversation_options[id]
		spec.certain = true
		spec.erase("weapon")
		if id=="hg_stab":
			sim.services.inventory.change("knife",1)
			sim.services.inventory.execute("equip",{"id":"knife"})
		npc.inventory[str(sim.catalog.items.keys()[0])] = 1
		if id=="hg_shave":
			# Start through dialogue so the combat outcome restores its answer node.
			if not choose(room,"hg_fight").ok: t._check(false,"shave fixture starts a dialogue fight")
			sim.state.encounters.combat.status = "surrendered"
			sim.services.combat._update_outcome()
		if id=="fn_repay": bond.loan = 25
		if id=="rq_separate":
			bond.consent = true
			sim.services.social.relationship(str(npc.id),"player").status = "partner"
		var before := int(sim.state.clock.total_minutes)
		var result := choose(room,id)
		t._check(result.get("ok",false),"option executes through authoritative dialogue: "+id+" "+str(result.get("error","")))
		if not result.get("ok",false): continue
		t._check(int(sim.state.clock.total_minutes)==before+int(spec.minutes),"option charges its time exactly once: "+id)
		t._check(sim.validate_state(sim.state).ok,"option leaves valid serializable state: "+id)
		if spec.get("hostile",false) and id!="hg_steal":
			t._check(float(room.session.bond().affection)<=12 and not room.session.bond().consent,"hostility never grants affection or relationship agreement: "+id)
	var room := prepared()
	var sim: RefCounted = room.simulation
	var before: Dictionary = sim.export_snapshot()
	sim.services.npc_relationships.matrix(str(room.session.npc_id))
	sim.services.npc_dialogue.menu(str(room.session.npc_id))
	t._check(sim.export_snapshot()==before,"matrix and chance forecasts do not mutate state or RNG")
	var weapon_result := choose(room,"hg_stab")
	t._check(not weapon_result.ok and sim.export_snapshot()==before,"missing weapon rejects without time or consequences")
	sim.catalog.conversation_options.fn_borrow.certain = true
	var cash := int(sim.state.economy.cash)
	t._check(choose(room,"fn_borrow").ok and int(room.session.bond().loan)==25,"personal loan records the actual obligation")
	var restored := Factory.create()
	restored.simulation.catalog.conversation_options.fn_borrow.certain = true
	t._check(restored.simulation.restore_snapshot(sim.export_snapshot()).ok and int(restored.simulation.services.npc_relationships.view(str(room.session.npc_id),"player").loan)==25,"personal debt survives snapshot round trip")
	var loan_state: Dictionary = sim.export_snapshot()
	t._check(not choose(room,"fn_borrow").ok and sim.export_snapshot()==loan_state,"outstanding personal loan cannot be duplicated")
	t._check(choose(room,"fn_repay").ok and int(room.session.bond().loan)==0 and int(sim.state.economy.cash)==cash,"repayment conserves money and clears debt")
	room = prepared()
	sim = room.simulation
	sim.catalog.conversation_options.hg_threat.certain = true
	t._check(choose(room,"hg_threat").ok and float(room.session.bond().fear)>0,"threat creates directed fear separately from affection")
	var harmed: Dictionary = sim.export_snapshot()
	t._check(not choose(room,"hg_threat").ok and sim.export_snapshot()==harmed,"hostile repetition respects cooldown atomically")
	var victim: Dictionary = sim.services.npc_relationships._bond(str(room.session.npc_id),"player")
	victim.trust = 80
	victim.comfort = 60
	victim.grievance = 0
	victim.recent.erase("hg_threat")
	sim.state.social.npcs[str(room.session.npc_id)].mind.fears["person:player"].strength = 30
	var fearful: Dictionary = sim.export_snapshot()
	t._check(not choose(room,"rq_kiss").ok and sim.export_snapshot()==fearful,"fear cannot be converted into romantic consent")
	room = prepared()
	sim = room.simulation
	sim.catalog.conversation_options.ct_music.certain = true
	t._check(choose(room,"ct_music").ok,"first conversation can create a bounded gain")
	var affection := float(room.session.bond().affection)
	t._check(choose(room,"ct_music").ok and float(room.session.bond().affection)==affection,"repeating a topic does not farm relationship gains")
