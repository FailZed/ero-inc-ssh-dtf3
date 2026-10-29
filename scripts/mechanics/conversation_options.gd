extends "res://scripts/mechanics/core/module.gd"
## Independently authored social encounters; physical escalation uses the combat runtime.

static func catalog_error(catalog: Dictionary) -> String:
	for id: String in catalog.get("conversation_options",{}):
		var spec: Dictionary = catalog.conversation_options[id]
		if not (spec.get("minutes") is int or spec.get("minutes") is float) or not is_finite(float(spec.minutes)) or float(spec.minutes)!=int(spec.minutes) or int(spec.minutes)<1 or int(spec.minutes)>120: return "invalid_conversation_duration"
		if not spec.get("kind","") in ["topic","question","romance","activity","hostile","finance"]: return "invalid_conversation_kind"
		for field: String in ["chance","fear","damage","counter_damage","cost","money","cooldown","trust","closeness","energy"]:
			if not spec.has(field): continue
			var value: Variant = spec[field]
			var limit := 1.0 if field=="chance" else 10080.0 if field=="cooldown" else 1000000.0 if field in ["money","cost"] else 100.0
			if not (value is int or value is float) or not is_finite(float(value)) or float(value)<0 or float(value)>limit: return "invalid_conversation_parameter:"+field
		if not spec.get("effect","") in ["","take_money","take_item","steal","borrow","repay","give_money","drive_away","shave","separate","combat"]: return "invalid_conversation_effect"
		if not catalog.dialogue_pools.has("option."+id) or not catalog.dialogue_choices.has(id): return "missing_conversation_content"
		if spec.get("effect","") == "combat" and not str(spec.get("opening","")) in ["","heavy","thrust"]: return "invalid_conversation_attack"
		if spec.has("opening") and not catalog.combat_moves.has(str(spec.opening)): return "invalid_conversation_attack"
		for changes: Dictionary in [spec.get("changes",{}),spec.get("rejected",{})]:
			for key: String in changes:
				if not key in ["trust","affection","respect","comfort","closeness","interest","grievance","care_balance"] or not is_finite(float(changes[key])) or absf(float(changes[key]))>100: return "invalid_conversation_matrix"
	return ""

func _spec(id: String) -> Dictionary:
	return definition("conversation_options",id)

func preview(npc: Dictionary, id: String) -> Dictionary:
	var spec := _spec(id)
	if spec.is_empty(): return {"blocked":"unknown_dialogue_choice","chance":0.0}
	var bond: Dictionary = sim.services.npc_relationships.view(str(npc.id),"player")
	var blocked := ""
	for tag: String in spec.get("tags",[]):
		if tag in sim.state.preferences.disabled_tags: blocked = "content_disabled"
	if not spec.get("message",false) and npc.mind.dialogue.channel == "message": blocked = "npc_not_present"
	if (float(npc.health)<=0 and spec.get("effect","") != "shave") or sim.services.health.hp("player")<=0: blocked = "combatant_incapacitated"
	if not sim.state.encounters.combat.is_empty() and sim.state.encounters.combat.status == "active": blocked = "finish_active_combat"
	if float(bond.trust)<float(spec.get("trust",-100)) or float(bond.closeness)<float(spec.get("closeness",0)): blocked = "insufficient_closeness"
	if spec.kind == "romance":
		blocked = sim.services.npc_relationships.blocked("player",str(npc.id),"court") if blocked.is_empty() else blocked
		if float(bond.fear)>=15: blocked = "unresolved_harm"
	if spec.get("hostile",false) and int(sim.state.clock.total_minutes)-int(bond.recent.get(id,-10080))<int(spec.get("cooldown",60)): blocked = "conversation_cooldown"
	if spec.has("weapon"):
		var item: String = str(sim.state.inventory.equipped.get("weapon",""))
		var weapon: String = str(definition("items",item).get("weapon","unarmed"))
		if str(definition("weapons",weapon).get("class","unarmed")) != str(spec.weapon): blocked = "required_equipment"
	if spec.has("item") and int(sim.state.inventory.items.get(str(spec.item),0))<1: blocked = "required_equipment"
	if spec.get("effect","") == "take_item" and npc.inventory.is_empty(): blocked = "target_item_missing"
	if spec.get("effect","") == "shave":
		var previous: Dictionary = sim.state.encounters.combat
		if previous.get("npc","") != npc.id or not previous.get("status","") in ["won","surrendered"]: blocked = "target_not_subdued"
		if npc.appearance.get("hair","") == "bald": blocked = "already_shaved"
	if spec.get("effect","") in ["take_money","borrow"] and int(npc.money)<=0: blocked = "target_has_no_money"
	if spec.get("effect","") == "give_money" and int(sim.state.economy.cash)<int(spec.get("money",25)): blocked = "insufficient_funds"
	if int(sim.state.economy.cash)<int(spec.get("cost",0)): blocked = "insufficient_funds"
	if spec.get("effect","") == "borrow" and int(bond.get("loan",0))>0: blocked = "personal_loan_outstanding"
	if spec.get("effect","") == "repay":
		if int(bond.get("loan",0))<=0: blocked = "no_personal_loan"
		elif int(sim.state.economy.cash)<int(bond.loan): blocked = "insufficient_funds"
	if spec.get("effect","") == "separate" and not bond.consent: blocked = "not_in_relationship"
	if float(sim.state.player.needs.energy)<float(spec.get("energy",0)): blocked = "insufficient_energy"
	var p = sim.services.npc_personalities
	var chance := float(spec.get("chance",0.65))
	chance += float(bond.trust)*0.002+float(bond.comfort)*0.001-float(bond.grievance)*0.004-float(bond.fear)*0.003
	chance += (p.f(npc,"sociability")-0.5)*0.12
	if spec.has("interest"): chance += (float(npc.psychology.interests[str(spec.interest)])/100.0-0.5)*0.3
	if spec.kind == "hostile":
		chance = float(spec.get("chance",0.55))+(sim.services.character.effective_stat("authority")-float(npc.stats.authority))*0.025+float(bond.fear)*0.003
		if spec.get("effect","") == "steal":
			var theft: Dictionary = sim.services.security.preview("steal", {"npc":str(npc.id)})
			chance = float(theft.data.chance_min)
			if blocked.is_empty(): blocked = str(theft.data.blocked)
	if spec.get("effect","") != "steal":
		chance = 1.0 if spec.get("certain",false) or spec.get("effect","") == "combat" else clampf(chance,0.05,0.95)
	return {"blocked":blocked,"chance":chance,"changes":spec.get("changes",{}).duplicate(),"rejected":spec.get("rejected",{}).duplicate(),"hostile":bool(spec.get("hostile",false)),"combat":spec.get("effect","") == "combat","fine":int(spec.get("fine",0)),"witnesses":_witnesses(npc),"cost":int(spec.get("cost",0)),"fear":float(spec.get("fear",0)),"repeat":int(sim.state.clock.total_minutes)-int(bond.recent.get(id,-10080))<180}

func execute(operation: String, args: Dictionary) -> Dictionary:
	if operation != "choose": return Rules.fail("unknown_operation")
	var id := str(args.get("choice",""))
	var npc: Dictionary = sim.state.social.npcs.get(str(args.get("id","")),{})
	if not npc.has("mind"): return Rules.fail("unknown_npc")
	var info := preview(npc,id)
	if not str(info.blocked).is_empty(): return Rules.fail(str(info.blocked))
	if npc.location != sim.state.world.location and npc.mind.dialogue.channel != "message": return Rules.fail("npc_not_present")
	var spec := _spec(id)
	var bond: Dictionary = sim.services.npc_relationships._bond(str(npc.id),"player")
	if spec.get("effect","") == "steal":
		var previous_pin := int(npc.pinned_until)
		npc.pinned_until = maxi(previous_pin,int(sim.state.clock.total_minutes)+11)
		var theft: Dictionary = sim.services.security.execute("steal",{"npc":str(npc.id)})
		if not theft.ok: return theft
		npc.pinned_until = previous_pin
		bond.recent[id] = int(sim.state.clock.total_minutes)
		var response := "unnoticed" if theft.data.success else _reaction(npc,false,"steal")
		if response == "fight":
			var started := _start_fight(npc,id,previous_pin)
			if not started.ok: return started
		elif response == "leave": _depart(npc)
		emit_event("conversation_outcome",{"npc":str(npc.id),"choice":id,"accepted":bool(theft.data.success),"money":int(theft.data.money)})
		return Rules.ok({"accepted":bool(theft.data.success),"chance":float(theft.data.chance),"pool":"conflict.escalated" if response == "fight" else "conflict.left" if response == "leave" else "option."+id if theft.data.success else "option.theft_failed","money":int(theft.data.money),"hostile":true,"reaction":response,"combat_started":response == "fight","ended":response == "leave","witnesses":int(theft.data.witnesses)})
	var pinned := int(npc.pinned_until)
	npc.pinned_until = maxi(pinned,int(sim.state.clock.total_minutes)+int(spec.minutes)+1)
	var elapsed: Dictionary = sim.advance(int(spec.minutes))
	if not elapsed.ok: return elapsed
	npc.pinned_until = pinned
	var accepted: bool = sim.rng.randf()<float(info.chance)
	var effect := str(spec.get("effect",""))
	var money := 0
	var repeated := bool(info.repeat)
	var reaction := ""
	var witnesses := _witnesses(npc)
	var changes: Dictionary = spec.get("changes",{}).duplicate() if accepted else spec.get("rejected",{}).duplicate()
	if spec.get("hostile",false):
		# A failed attack/threat still causes harm. Fear never grants affection or consent.
		changes = spec.get("changes",{}).duplicate()
		bond.acknowledged = false
		bond.good_days.clear()
		bond.consent = false
		bond.recent[id] = int(sim.state.clock.total_minutes)
		var fear := float(spec.get("fear",0))*(1.0 if accepted else 0.5)
		if fear>0: npc.mind.fears["person:player"] = {"strength":minf(100,float(sim.services.npc_relationships.view(str(npc.id),"player").fear)+fear),"expires":int(sim.state.clock.total_minutes)+2880}
		sim.services.npc_agency.record_social_experience(npc,"conflict","player")
		sim.services.social.remember(str(npc.id),"hostile_conversation",{"actor":"player","action":id,"accepted":accepted})
		if effect != "steal": _incident(npc,id,accepted,int(spec.get("fine",0)))
		reaction = _reaction(npc,accepted,effect)
		npc.mind.emotion = {"id":"angry" if reaction == "fight" or not accepted else "tense","strength":80.0}
	else:
		var maximum := 0.0
		for value in changes.values(): maximum = maxf(maximum,float(value))
		var gain: float = sim.services.npc_relationships._gain(bond,id,maximum) if maximum>0 else 0.0
		for key: String in changes:
			if float(changes[key])>0: changes[key] = float(changes[key])*(gain/maximum if maximum>0 else 0.0)
		# Kind words and money cannot erase harm or replace days of reliable behaviour.
		if float(bond.grievance)>0: changes["trust"] = minf(0,float(changes.get("trust",0)))
		if accepted: sim.services.npc_agency.record_social_experience(npc,"friendship","player")
	sim.services.npc_relationships._change(bond,changes)
	bond.last_contact = int(sim.state.clock.total_minutes)
	sim.state.player.needs.energy = maxf(0,float(sim.state.player.needs.energy)-float(spec.get("energy",0)))
	if accepted:
		sim.state.economy.cash -= int(spec.get("cost",0))
		if effect == "take_money" or effect == "borrow":
			money = mini(int(npc.money),int(spec.get("money",25)))
			npc.money -= money
			sim.state.economy.cash += money
			if effect == "borrow": bond.loan = money
		elif effect == "give_money":
			money = int(spec.get("money",25))
			npc.money += money
			sim.state.economy.cash -= money
		elif effect == "repay":
			money = int(bond.loan)
			npc.money += money
			sim.state.economy.cash -= money
			bond.loan = 0
		elif effect == "take_item":
			var item: String = str(npc.inventory.keys()[0])
			var added: Dictionary = sim.services.inventory.change(item,1)
			if not added.ok: return added
			npc.inventory[item] -= 1
			if npc.inventory[item]<=0: npc.inventory.erase(item)
			if str(npc.weapon)==item and not npc.inventory.has(item): npc.weapon = ""
			sim.services.security._clear_unowned_equipment(npc)
		elif effect == "drive_away":
			_depart(npc)
		elif effect == "shave":
			var styled: Dictionary = sim.services.appearance.execute("customize",{"target":str(npc.id),"features":{"hair":"bald"}})
			if not styled.ok: return styled
		elif effect == "separate": sim.services.npc_relationships.execute("separate",{"id":str(npc.id)})
		if spec.has("restore"):
			for key: String in spec.restore:
				if npc.needs.has(key): npc.needs[key] = clampf(float(npc.needs[key])+float(spec.restore[key]),0,100)
				if sim.state.player.needs.has(key): sim.state.player.needs[key] = clampf(float(sim.state.player.needs[key])+float(spec.restore[key]),0,100)
		if spec.has("skill"):
			var trained: Dictionary = sim.services.character.execute("train",{"skill":str(spec.skill),"xp":3})
			if not trained.ok: return trained
	sim.services.npc_relationships._project(str(npc.id),"player")
	var combat_started := effect == "combat" or reaction == "fight"
	if combat_started:
		var started := _start_fight(npc,id,pinned,str(spec.get("opening","")))
		if not started.ok: return started
	var pool := "option."+id if accepted else "option.hostile_resisted" if spec.get("hostile",false) else "option.declined"
	if combat_started: pool = "conflict.escalated" if effect != "combat" else "option."+id
	elif reaction == "leave":
		_depart(npc)
		pool = "conflict.left"
	if accepted and repeated and not spec.get("hostile",false): pool = "answer.repeat"
	emit_event("conversation_outcome",{"npc":str(npc.id),"choice":id,"accepted":accepted,"money":money})
	return Rules.ok({"accepted":accepted,"chance":info.chance,"pool":pool,"money":money,"hostile":bool(spec.get("hostile",false)),"combat_started":combat_started,"ended":reaction == "leave" or effect == "drive_away" and accepted,"reaction":reaction,"witnesses":witnesses})

func _start_fight(npc: Dictionary, id: String, pinned: int, opening: String = "") -> Dictionary:
	var started: Dictionary = sim.services.combat.start(str(npc.id))
	if not started.ok: return started
	sim.state.encounters.combat.conversation = {"choice":id,"pinned_until":pinned}
	npc.pinned_until = maxi(pinned,int(sim.state.clock.total_minutes)+1440)
	if not opening.is_empty(): return sim.services.combat.action({"action":"attack","move":opening,"part":"body"})
	return Rules.ok()

func _reaction(npc: Dictionary, accepted: bool, effect: String) -> String:
	if effect == "combat": return "fight"
	if effect in ["drive_away","shave"]: return "comply" if accepted else "refuse"
	var boldness: float = sim.services.npc_personalities.f(npc,"social_boldness")
	var patience: float = sim.services.npc_personalities.f(npc,"patience")
	var fear: float = sim.services.npc_relationships.view(str(npc.id),"player").fear
	if not accepted and boldness>=0.65 and patience<0.4 and fear<35: return "fight"
	if not accepted and fear>=20 and boldness<0.45: return "leave"
	return "comply" if accepted else "refuse"

func _depart(npc: Dictionary) -> void:
	var destination := str(npc.home)
	if destination == npc.location:
		for location: String in definition("locations",str(npc.location)).get("routes",{}):
			if not sim.catalog.locations[location].get("public",false): continue
			if sim.services.world.actor_availability(location,str(npc.id),int(sim.state.clock.total_minutes)).ok: destination = location; break
	sim.services.npc_agency._cancel(npc,"conflict_exit")
	sim.services.npc_dialogue.interrupt_contact(str(npc.id))
	npc.location = destination
	npc.pinned_until = 0

func _witnesses(npc: Dictionary) -> int:
	var count := 0
	for other: Dictionary in sim.state.social.npcs.values():
		if other.id != npc.id and other.location == npc.location and other.activity != "sleep": count += 1
	return count

func _incident(npc: Dictionary, id: String, success: bool, fine: int) -> void:
	for other: Dictionary in sim.state.social.npcs.values():
		if other.id == npc.id or other.location != npc.location or other.activity == "sleep": continue
		sim.services.npc_agency.record_social_experience(other,"witnessed_harm","player")
		sim.services.npc_relationships.harm(str(other.id),"player",5,"witnessed_conversation")
	if fine<=0: return
	var witnesses := _witnesses(npc)
	sim.state.world.heat = minf(100,float(sim.state.world.heat)+5+witnesses*3)
	sim.state.security.fine += fine+witnesses*5
	sim.state.security.incidents.append({"operation":id,"target":str(npc.id),"success":success,"minute":int(sim.state.clock.total_minutes)})
	while sim.state.security.incidents.size()>64: sim.state.security.incidents.pop_front()
