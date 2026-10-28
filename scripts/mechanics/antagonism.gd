extends "res://scripts/mechanics/core/module.gd"
## Motive, opportunity, warning, response and consequence. Main-game only.
const Check = preload("res://scripts/mechanics/core/validation.gd")
var forecast_mode := false

static func defaults() -> Dictionary:
	return {"version":1,"serial":0,"next_check":0,"actors":{},"cases":{},"history":[]}

func initialize() -> void:
	if not sim.state.has("antagonism"): sim.state.antagonism = defaults()
func rules() -> Dictionary: return sim.catalog.antagonism_rules
func _state() -> Dictionary: return sim.state.antagonism
func _now() -> int: return int(sim.state.clock.total_minutes)
func enabled() -> bool: return sim.services.npc_agency.enabled() and sim.state.world.flags.get("chapter_one_complete",false)
func _npc(id: String) -> Dictionary: return sim.state.social.npcs.get(id,{})
func _location(id: String) -> String: return str(sim.state.world.location) if id == "player" else str(_npc(id).get("location",""))
func _memory(id: String) -> Dictionary:
	if not _state().actors.has(id): _state().actors[id] = {"impunity":0.0,"deterrence":0.0,"cooldown":0,"exposed":0}
	return _state().actors[id]
func _facet(id: String, key: String) -> float: return sim.services.npc_personalities.f(_npc(id),key)
func _bond(a: String,b: String) -> Dictionary: return sim.services.npc_relationships.view(a,b)
func _eligible(id: String) -> bool:
	var npc := _npc(id)
	return npc.has("mind") and npc.has("psychology") and int(npc.age) >= 18 and float(npc.health) > 25

func disposition(id: String, target: String = "player") -> Dictionary:
	if not _eligible(id): return {}
	var memory: Dictionary = _state().actors.get(id,{})
	var grievance := float(_bond(id,target).grievance)/100.0
	return {"profit":(1.0-_facet(id,"fairness"))*0.45+(1.0-_facet(id,"greed_avoidance"))*0.45+(0.10 if float(_npc(id).money)<30 else 0.0),
		"dominance":(1.0-_facet(id,"gentleness"))*0.45+(1.0-_facet(id,"fairness"))*0.30+_facet(id,"social_boldness")*0.25,
		"resentment":grievance*0.55+(1.0-_facet(id,"forgivingness"))*0.25+(1.0-_facet(id,"sincerity"))*0.20,
		"ambition":sim.services.npc_personalities.v(_npc(id),"achievement")*0.40+(1.0-_facet(id,"fairness"))*0.35+(1.0-_facet(id,"sincerity"))*0.25,
		"impunity":float(memory.get("impunity",0)),"deterrence":float(memory.get("deterrence",0))}

func _power(id: String) -> float:
	if id == "player": return sim.services.character.effective_stat("strength")*3.0+float(sim.state.player.needs.energy)*0.2
	return float(_npc(id).stats.get("strength",5))*3.0+float(_npc(id).needs.energy)*0.2+float(_npc(id).mind.get("career_level",0))*2.0

func _project() -> String:
	for id in sim.state.computer.projects:
		if sim.state.computer.projects[id].status == "active": return str(id)
	return ""

func opportunity(actor: String, target: String, kind: String) -> Dictionary:
	if not enabled() or not _eligible(actor) or (target != "player" and not _eligible(target)) or actor == target: return {"blocked":"unavailable_antagonist","score":0.0}
	if not rules().kinds.has(kind): return {"blocked":"unknown_pressure_kind","score":0.0}
	var spec: Dictionary = rules().kinds[kind]
	if spec.tag in sim.state.preferences.disabled_tags: return {"blocked":"content_disabled","score":0.0}
	if spec.physical and "violence" in sim.state.preferences.disabled_tags: return {"blocked":"content_disabled","score":0.0}
	if not sim.state.encounters.combat.is_empty() and sim.state.encounters.combat.get("status","") == "active": return {"blocked":"active_combat","score":0.0}
	if _private_location(_location(actor)) or _location(actor) != _location(target): return {"blocked":"no_opportunity","score":0.0}
	if _npc(actor).activity in ["sleep","work","study","eat","travel"] or _npc(actor).decision.get("committed",false) or float(_npc(actor).needs.energy)<30 or int(_npc(actor).pinned_until) > _now(): return {"blocked":"actor_busy","score":0.0}
	if target == "player" and (not sim.state.livelihood.pending.is_empty() or not sim.state.companion.active.is_empty()): return {"blocked":"target_busy","score":0.0}
	if kind == "sabotage" and (target != "player" or _project().is_empty() or not actor in sim.state.social.contacts): return {"blocked":"no_known_project","score":0.0}
	if kind == "slander" and float(_bond(actor,target).closeness) < 1 and float(_bond(actor,target).grievance) < 1: return {"blocked":"no_social_history","score":0.0}
	if kind == "slander" and _witnesses(actor,target).is_empty(): return {"blocked":"pressure_no_audience","score":0.0}
	if int(_state().actors.get(actor,{}).get("cooldown",0)) > _now(): return {"blocked":"antagonist_cooldown","score":0.0}
	var active := 0
	for c in _state().cases.values():
		if c.status == "open":
			active += 1
			if c.actor == actor or c.target == target: return {"blocked":"pressure_already_active","score":0.0}
	if active >= int(rules().active_limit): return {"blocked":"pressure_capacity","score":0.0}
	if _state().cases.size() >= int(rules().case_limit): return {"blocked":"pressure_capacity","score":0.0}
	var traits := disposition(actor,target)
	var score := float(traits[spec.motive])+float(traits.impunity)*0.002-float(traits.deterrence)*0.003
	if spec.physical: score += clampf((_power(actor)-_power(target))/100.0,-0.30,0.20)
	return {"blocked":"" if score >= float(rules().threshold) else "insufficient_motive","score":score,"motive":spec.motive}

func _witnesses(actor: String,target: String) -> Array:
	var result: Array = []
	var ids: Array = sim.state.social.npcs.keys(); ids.sort()
	for id in ids:
		if id in [actor,target] or not _eligible(id) or _location(id) != _location(actor) or _npc(id).activity == "sleep": continue
		var care: float = sim.services.npc_personalities.v(_npc(id),"benevolence")
		var courage := _facet(id,"social_boldness")
		var stance := "silent"
		if care >= 0.6 and courage+clampf((_power(id)-_power(actor))/100.0,-0.4,0.4) >= 0.55: stance = "support"
		elif care < 0.3 and float(_bond(id,actor).trust) >= 15: stance = "complicit"
		result.append({"id":str(id),"stance":stance})
		if result.size() == 8: break
	return result

func _notify(c: Dictionary,text: String) -> void:
	if c.target != "player" and not c.observed: return
	var contact := str(c.actor)
	if not contact in sim.state.social.contacts: sim.state.social.contacts.append(contact)
	sim.services.npc_dialogue._message(_npc(contact),"Событие: "+text,"npc_reply")
	emit_event("pressure_notice",{"id":c.id,"actor":contact,"text":text})

func _start(actor: String,target: String,kind: String) -> Dictionary:
	var possible := opportunity(actor,target,kind)
	if not str(possible.blocked).is_empty(): return Rules.fail(possible.blocked)
	_state().serial += 1
	var id := "pressure_%d" % int(_state().serial)
	var spec: Dictionary = rules().kinds[kind]
	var witnesses := _witnesses(actor,target)
	var support := 0
	for w in witnesses:
		if w.stance == "support": support += 1
	var c := {"id":id,"actor":actor,"target":target,"kind":kind,"motive":spec.motive,"location":_location(actor),"created":_now(),"deadline":_now()+int(spec.deadline),"status":"open","evidence":mini(1,support),"documented":false,"investigated":false,"ally":"","used":[],"witnesses":witnesses,"observed":_location("player")==_location(actor),"project":_project() if kind == "sabotage" else "","loss":0,"result":"","ended":0,"rumor_until":0}
	_state().cases[id] = c
	sim.services.npc_agency._cancel(_npc(actor),"hostile_intent")
	_npc(actor).pinned_until = _now()+30
	_npc(actor).needs.energy = maxf(0,float(_npc(actor).needs.energy)-5)
	_memory(actor).cooldown = _now()+int(rules().actor_cooldown)
	_state().next_check = _now()+int(rules().global_cooldown)
	_notify(c,"%s: %s %s" % [spec.label,"Угроза направлена на вас." if target == "player" else "Угроза направлена на "+str(_npc(target).name)+".",spec.text])
	emit_event("pressure_started",{"id":id,"actor":actor,"target":target,"kind":kind})
	return Rules.ok({"id":id})

func _finish(c: Dictionary,result: String,deterrence: float = 0.0) -> void:
	c.status = "resolved"; c.result = result; c.ended = _now()
	var memory := _memory(str(c.actor))
	memory.deterrence = clampf(float(memory.deterrence)+deterrence,0,100)
	if deterrence > 0: memory.impunity = maxf(0,float(memory.impunity)-10)
	_state().history.append({"id":c.id,"minute":_now(),"result":result,"loss":c.loss})
	while _state().history.size() > 64: _state().history.pop_front()
	_notify(c,result)
	emit_event("pressure_resolved",{"id":c.id,"result":result,"loss":c.loss})

func _consequence(c: Dictionary) -> void:
	var spec: Dictionary = rules().kinds[c.kind]
	if spec.tag in sim.state.preferences.disabled_tags or (spec.physical and "violence" in sim.state.preferences.disabled_tags):
		c.status = "cancelled"; c.result = "Событие отключено настройками содержания."; c.ended = _now(); return
	if spec.physical:
		if _location(str(c.actor)) != _location(str(c.target)) or _private_location(_location(str(c.target))):
			_finish(c,"Нападающий не нашёл удобного момента: встреча сорвалась."); return
		var protection := 5 if not str(c.ally).is_empty() and _location(c.ally) == _location(c.target) else 0
		var accomplices := 0
		for w in c.witnesses:
			if w.stance == "support" and _location(w.id) == _location(c.target): protection += 3
			if w.stance == "complicit" and _location(w.id) == _location(c.target): accomplices += 1
		var damage := clampi(int(spec.damage)+accomplices*2-protection,0,20)
		if damage > 0: sim.services.health.injure(str(c.target),"body",damage)
		c.loss = damage
		if c.target != "player": sim.services.npc_relationships.harm(str(c.target),str(c.actor),20,"intimidation")
	elif c.kind == "sabotage":
		var project: Dictionary = sim.state.computer.projects.get(c.project,{})
		if project.is_empty() or project.status != "active":
			_finish(c,"Заказ уже закрыт: сорвать его сдачу не удалось."); return
		c.loss = mini(12,int(project.quality))
		project.quality = maxf(0,float(project.quality)-12); project.bugs = mini(6,int(project.bugs)+1)
	else:
		c.rumor_until = _now()+10080
		c.loss = c.witnesses.size()
	_memory(str(c.actor)).impunity = minf(100,float(_memory(str(c.actor)).impunity)+15)
	_finish(c,"Угроза реализована: "+str(spec.label)+". Последствия сохранены; свидетельства ещё можно собрать и предъявить.")

func rumor_penalty(observer: String,target: String) -> float:
	var penalty := 0.0
	for c in _state().cases.values():
		if c.kind != "slander" or c.target != target or int(c.rumor_until) <= _now(): continue
		for w in c.witnesses:
			if w.id == observer: penalty += 0.08*(1.0-_facet(observer,"prudence")*0.5)
	return minf(0.16,penalty)

func _response_block(c: Dictionary,choice: String,ally: String = "") -> String:
	if not rules().responses.has(choice): return "unknown_pressure_response"
	if c.status == "cancelled" or _now() > int(c.deadline)+10080: return "pressure_case_closed"
	var spec: Dictionary = rules().kinds[c.kind]
	if spec.tag in sim.state.preferences.disabled_tags or (spec.physical and "violence" in sim.state.preferences.disabled_tags): return "content_disabled"
	if c.status != "open" and not choice in ["document","investigate","report","expose"]: return "pressure_case_closed"
	if choice in c.used: return "pressure_response_used"
	if choice == "pay" and (c.kind != "extortion" or c.target != "player"): return "pressure_payment_unavailable"
	if choice == "pay" and int(sim.state.economy.cash) < int(rules().kinds[c.kind].amount): return "insufficient_funds"
	if choice == "secure" and (c.kind != "sabotage" or (not sim.is_player_home_location(str(sim.state.world.location)) or sim.room_kind(str(sim.state.world.location)) != "bedroom") or not "computer" in sim.state.world.equipment): return "computer_desk_required"
	if choice in ["report","expose"] and int(c.evidence) < 2: return "pressure_evidence_required"
	if choice == "expose" and c.witnesses.is_empty(): return "pressure_no_audience"
	if choice == "refuse" and not rules().kinds[c.kind].physical: return "pressure_response_unavailable"
	if choice == "evade" and (not rules().kinds[c.kind].physical or _location(str(c.target)) == _location(str(c.actor))): return "leave_threat_location_first"
	if choice == "ally":
		if not _eligible(ally) or ally in [c.actor,c.target] or not ally in sim.state.social.contacts: return "unknown_supporter"
		if float(_bond(ally,"player").trust) < 10 or sim.services.npc_personalities.v(_npc(ally),"benevolence") < 0.55: return "supporter_unwilling"
		if _facet(ally,"social_boldness") < 0.35 and _power(ally) < _power(str(c.actor)): return "supporter_afraid"
	var minutes := int(rules().responses[choice].minutes)
	if c.status == "open" and _now()+minutes >= int(c.deadline): return "pressure_deadline_too_close"
	return ""

func response_view(c: Dictionary) -> Array:
	var result: Array = []
	for choice in rules().responses:
		if choice == "ally": continue
		result.append({"id":choice,"text":rules().responses[choice].label,"minutes":rules().responses[choice].minutes,"blocked":_response_block(c,choice)})
	return result

func inspect() -> Dictionary:
	var cases: Array = []
	for c in _state().cases.values():
		if not c.observed and c.target != "player": continue
		var row: Dictionary = c.duplicate(true)
		row.label = rules().kinds[c.kind].label; row.description = rules().kinds[c.kind].text
		row.responses = response_view(c)
		row.allies = []
		for id in sim.state.social.contacts:
			if _eligible(id) and not id in [c.actor,c.target]: row.allies.append({"id":id,"name":_npc(id).name,"blocked":_response_block(c,"ally",id)})
		cases.append(row)
	return {"enabled":enabled(),"cases":cases,"history":_state().history.duplicate(true)}

func execute(operation: String,args: Dictionary) -> Dictionary:
	if operation == "inspect": return Rules.ok(inspect())
	if operation == "stage": return _start(str(args.get("id","")),str(args.get("target","player")),str(args.get("kind","")))
	if operation != "respond": return Rules.fail("unknown_operation")
	var c: Dictionary = _state().cases.get(str(args.get("id","")),{})
	if c.is_empty() or (not c.observed and c.target != "player"): return Rules.fail("unknown_pressure_case")
	var choice := str(args.get("choice","")); var ally := str(args.get("ally",""))
	var blocked := _response_block(c,choice,ally)
	if not blocked.is_empty(): return Rules.fail(blocked)
	var minutes := int(rules().responses[choice].minutes)
	if float(sim.state.player.needs.energy) < minutes*0.1: return Rules.fail("insufficient_energy")
	sim.services.character.adjust_need("energy",-minutes*0.1)
	var advanced: Dictionary = sim.advance(minutes)
	if not advanced.ok: return advanced
	c.used.append(choice)
	var text := ""
	match choice:
		"document":
			c.documented = true; c.evidence = mini(3,int(c.evidence)+1); text = "Угроза зафиксирована: сохранены время, участники и содержание."
		"investigate":
			c.investigated = true; c.evidence = mini(3,int(c.evidence)+1); text = "Хронология и противоречия сопоставлены. Собрано дополнительное подтверждение."
		"ally":
			c.ally = ally
			for w in c.witnesses:
				if w.id == ally: c.evidence = mini(3,int(c.evidence)+1)
			text = "Союзник согласился поддержать вас. Поддержка уменьшает риск, но не делает угрозу безвредной."
		"pay":
			var amount := int(rules().kinds[c.kind].amount)
			sim.state.economy.cash -= amount; _npc(str(c.actor)).money += amount; c.loss = amount
			_memory(str(c.actor)).impunity = minf(100,float(_memory(str(c.actor)).impunity)+20)
			_finish(c,"Деньги переданы. Получена передышка; вымогатель убедился, что давление приносит доход.")
		"secure": _finish(c,"Авторство и материалы защищены. Попытка сорвать этот заказ пресечена.",10)
		"evade": _finish(c,"Вы разорвали контакт и избежали этой встречи.",0)
		"refuse":
			var strength := _power("player") if c.target == "player" else _power(str(c.target))
			var chance := clampf(0.45+(strength-_power(str(c.actor)))/150.0+(0.20 if not str(c.ally).is_empty() else 0.0)-float(_memory(str(c.actor)).impunity)*0.003,0.10,0.90)
			if sim.rng.randf() < chance: _finish(c,"Агрессор отступил: открытое давление оказалось слишком рискованным.",25)
			else: text = "Отказ не остановил агрессора. Угроза остаётся; используйте оставшееся время для другого ответа."
		"report":
			var chance := clampf(0.20+int(c.evidence)*0.18+(0.10 if not str(c.ally).is_empty() else 0.0)-float(_memory(str(c.actor)).impunity)*0.003,0.15,0.90)
			if sim.rng.randf() < chance:
				c.rumor_until = 0; _memory(str(c.actor)).exposed += 1
				_npc(str(c.actor)).money = maxi(0,int(_npc(str(c.actor)).money)-25)
				_finish(c,"Свидетельства приняты. Агрессор получил взыскание; уже причинённый ущерб не исчезает.",40)
			else:
				_memory(str(c.actor)).impunity = minf(100,float(_memory(str(c.actor)).impunity)+10)
				text = "Заявление оставили без действенного ответа. Оно сохранено, но защиты пока нет. Можно предъявить свидетельства окружению."
		"expose":
			for w in c.witnesses: sim.services.npc_relationships.harm(w.id,str(c.actor),12,"exposed_abuse")
			c.rumor_until = 0; _memory(str(c.actor)).exposed += 1
			_finish(c,"Свидетельства предъявлены. Присутствовавшие узнали источник давления; клевета опровергнута.",30)
	if text.is_empty(): text = str(c.result)
	else: _notify(c,text)
	return Rules.ok({"description":text,"id":c.id,"resolved":c.status != "open","evidence":c.evidence})

func tick(minute: int) -> void:
	for c in _state().cases.values():
		if c.status == "open" and minute >= int(c.deadline): _consequence(c)
	if minute % 1440 == 0:
		for id in _state().cases.keys():
			var c: Dictionary = _state().cases[id]
			if c.status != "open" and minute > int(c.deadline)+10080: _state().cases.erase(id)
		for memory in _state().actors.values(): memory.deterrence = maxf(0,float(memory.deterrence)-1)
	if forecast_mode or not enabled() or minute % int(rules().interval) != 0 or minute < int(_state().next_check): return
	var ids: Array = sim.state.social.npcs.keys(); ids.sort()
	var best := {}; var score := -1.0
	for actor in ids:
		if not _eligible(actor): continue
		var targets: Array = ["player"]
		# Only local bystanders are considered; no omniscient targeting across the city.
		for other in ids:
			if other != actor and _location(other) == _location(actor): targets.append(other)
			if targets.size() >= 9: break
		for target in targets:
			for kind in rules().kinds:
				var possible := opportunity(actor,target,kind)
				if str(possible.blocked).is_empty() and float(possible.score) > score:
					score = float(possible.score); best = {"actor":actor,"target":target,"kind":kind}
	if not best.is_empty() and sim.rng.randf() < float(rules().chance): _start(best.actor,best.target,best.kind)

func _private_location(location: String) -> bool:
	return not bool(sim.catalog.locations.get(location,{}).get("public",false))
