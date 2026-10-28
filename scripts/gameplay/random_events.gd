extends "res://scripts/mechanics/events.gd"
## Two original, main-game events. No generic scene interpreter or second simulation.
const PHONE := "re_phone_message_tone"
const DISTANCE := "re_npc_life_friend_distance"
const Check = preload("res://scripts/mechanics/core/validation.gd")

func initialize() -> void:
	sim.state.journal.random_events = {"version":1,"serial":0,"next_phone":0,"next_npc":0,
		"phone":{},"visits":{},"pairs":{},"npc_cases":{}}

func book() -> Dictionary:
	return sim.state.journal.random_events

func now() -> int:
	return int(sim.state.clock.total_minutes)

func enabled() -> bool:
	return sim.services.npc_agency.enabled() and int(sim.state.player.age)>=18

func _person(id: String) -> Dictionary:
	return sim.state.social.npcs.get(id,{})

func _adult(id: String) -> bool:
	var npc := _person(id)
	return npc.has("mind") and int(npc.age)>=18 and bool(npc.mind.boundaries.contact)

func _phone_available(id: String) -> bool:
	return _adult(id) and id in sim.state.social.contacts and sim.services.npc_dialogue.availability(_person(id),"message").is_empty()

func _serial(prefix: String) -> String:
	book().serial += 1
	return prefix+str(book().serial)

func _message(id: int) -> Dictionary:
	for message: Dictionary in sim.state.social.messages:
		if int(message.id)==id: return message
	return {}

func execute(operation: String, args: Dictionary) -> Dictionary:
	if operation == "random_inspect": return Rules.ok({"offers":random_offers(str(args.get("id","")))})
	if operation != "random_choose": return super.execute(operation,args)
	if not enabled(): return Rules.fail("random_event_unavailable")
	var key := str(args.get("id",""))
	var choice := str(args.get("choice",""))
	if not book().phone.has(key): return Rules.fail("random_event_unavailable")
	var event: Dictionary = book().phone[key]
	if event.status not in ["offered","replied"] or now()>=int(event.expires): return Rules.fail("random_event_unavailable")
	if not choice in ["a","b","leave"]: return Rules.fail("invalid_event_choice")
	if choice=="leave":
		event.status = "dismissed"
		return Rules.ok({"instance":key,"status":event.status})
	var reply: bool = event.status=="replied"
	var source := _message(int(event.reply if reply else event.source))
	if source.is_empty() or source.npc!=event.npc or source.get("event_instance","")!=key: return Rules.fail("event_source_unavailable")
	if not _phone_available(str(event.npc)): return Rules.fail("contact_unavailable")
	var minutes := (5 if choice=="a" else 3) if reply else (4 if choice=="a" else 2)
	event.status = "committing"
	var elapsed: Dictionary = sim.advance(minutes)
	if not elapsed.ok: return elapsed
	if not _phone_available(str(event.npc)) or _message(int(source.id)).is_empty(): return Rules.fail("contact_unavailable")
	if choice=="b":
		event.status = "deferred" if not reply else "completed"
		return Rules.ok({"instance":key,"status":event.status})
	var text := "Спасибо, теперь понял. Вернёмся к разговору, когда будет удобно." if reply else "Я не совсем понял тон сообщения. Ты сейчас занят или что-то не так?"
	var sent: Dictionary = sim.services.social.event_message(str(event.npc),text,false,key,int(source.id))
	if not sent.ok: return sent
	source.read = true
	if reply:
		event.status = "completed"
	else:
		event.outgoing = int(sent.data.message_id)
		event.status = "awaiting_reply"
		event.due = now()+sim.rng.randi_range(10,30)
		event.expires = now()+1440
	return Rules.ok({"instance":key,"message_id":sent.data.message_id,"status":event.status})

func random_offers(npc_id: String = "") -> Array:
	var result: Array = []
	if not enabled(): return result
	for key in book().phone:
		var event: Dictionary = book().phone[key]
		if not npc_id.is_empty() and event.npc!=npc_id: continue
		if event.status not in ["offered","replied","awaiting_reply"] or now()>=int(event.expires): continue
		var choices: Array = []
		if event.status!="awaiting_reply":
			var reply: bool = event.status=="replied"
			choices = [{"id":"a","text":"Принять объяснение и ответить" if reply else "Спокойно уточнить смысл","minutes":5 if reply else 4},
				{"id":"b","text":"Вернуться к разговору позже" if reply else "Подождать удобного момента","minutes":3 if reply else 2},
				{"id":"leave","text":"Оставить как есть","minutes":0}]
		result.append({"id":key,"event":PHONE,"npc":event.npc,"status":event.status,
			"title":"Смысл прояснился" if event.status=="replied" else "Сообщение без интонации",
			"text":"Уточнение отправлено. Собеседник ответит, когда будет готов." if event.status=="awaiting_reply" else "Короткий ответ легко понять неверно. Можно уточнить или дать человеку время.","choices":choices})
	return result

func _prune(values: Dictionary, limit: int, active: Array) -> void:
	while values.size()>=limit:
		var victim := ""
		for key in values:
			if not values[key].status in active: victim=str(key); break
		if victim.is_empty(): return
		values.erase(victim)

func offer_phone(id: String) -> bool:
	if not enabled() or not _phone_available(id): return false
	for entry in book().phone.values():
		if entry.npc==id and (now()-int(entry.created)<2880 or entry.status in ["offered","awaiting_reply","replied","committing"]): return false
	_prune(book().phone,32,["offered","awaiting_reply","replied","committing"])
	if book().phone.size()>=32: return false
	var key := _serial("phone:")
	# The message is an authored NPC initiative with explicit intent, not sentiment guessed from arbitrary chat.
	var sent: Dictionary = sim.services.social.event_message(id,"Ладно. Давай потом.",true,key,0,"busy_short_reply")
	if not sent.ok: return false
	book().phone[key] = {"status":"offered","npc":id,"created":now(),"expires":now()+60,
		"source":int(sent.data.message_id),"outgoing":0,"reply":0,"due":0}
	book().next_phone = now()+720
	emit_event("random_event_offered",{"id":key,"event":PHONE,"npc":id})
	return true

func _tick_phone() -> void:
	for key in book().phone:
		var event: Dictionary = book().phone[key]
		if event.status=="committing": continue
		if event.status in ["offered","replied","awaiting_reply"] and now()>=int(event.expires): event.status="expired"
		if event.status!="awaiting_reply" or now()<int(event.due): continue
		if _message(int(event.source)).is_empty() or _message(int(event.outgoing)).is_empty(): event.status="expired"; continue
		if not _phone_available(str(event.npc)): event.due=now()+15; continue
		var readiness: float = 0.35+sim.services.npc_personalities.f(_person(str(event.npc)),"sociability")*0.5
		if sim.rng.randf()>=readiness: event.due=now()+30; continue
		var sent: Dictionary = sim.services.social.event_message(str(event.npc),"Я просто торопился и ответил слишком коротко. С тобой всё в порядке; сейчас могу спокойно поговорить.",true,str(key),int(event.outgoing),"clarification")
		if not sent.ok: event.due=now()+15; continue
		event.reply = int(sent.data.message_id)
		event.status = "replied"
		event.expires = now()+120
		emit_event("random_event_reply",{"id":key,"event":PHONE,"npc":event.npc,"message_id":event.reply})
	if now()%120!=0 or now()<int(book().next_phone) or int(sim.state.clock.hour)<9 or int(sim.state.clock.hour)>21: return
	if random_offers().size()>=2 or sim.rng.randf()>=0.3: return
	var ids: Array = sim.state.social.contacts.duplicate(); ids.sort()
	if ids.is_empty(): return
	var offset: int = sim.rng.randi_range(0,ids.size()-1)
	for index in ids.size():
		if offer_phone(str(ids[(index+offset)%ids.size()])): break

func _pair_key(a: String,b: String) -> String:
	var ids := [a,b]; ids.sort()
	return str(ids[0])+"|"+str(ids[1])

func trackable_pair(a: String,b: String) -> bool:
	if a==b or not _adult(a) or not _adult(b): return false
	for pair in [[a,b],[b,a]]:
		if not _person(pair[0]).mind.bonds.has(pair[1]): return false
		if sim.services.npc_relationships.view(pair[0],pair[1]).stage not in ["friend","close_friend"]: return false
	return true

func visit_horizon() -> int:
	return int(sim.catalog.agency_actions.connect.minutes)+int(sim.services.npc_agency.rules().decision_minutes)-1

func pair_available(a: String,b: String,minutes: int) -> bool:
	if not trackable_pair(a,b) or _person(a).location!=_person(b).location: return false
	for id in [a,b]:
		var npc := _person(id)
		if npc.mind.active.get("phase","")=="travel" or not str(npc.mind.active.get("partner","")).is_empty(): return false
		if npc.activity in ["sleep","eat","recover","work","study"] or npc.decision.get("committed",false) or int(npc.pinned_until)>now(): return false
		if not sim.services.npc_planner.active_owner(id).is_empty(): return false
		if not sim.services.npc_agency._urgent(npc).is_empty(): return false
		if not sim.services.npc_planner.calendar.conflict(id,str(npc.location),minutes).is_empty(): return false
		if not sim.services.npc_planner.calendar.site_open(str(npc.location),now(),now()+minutes,id): return false
		if not sim.services.npc_relationships.blocked(a,b,"connect").is_empty() or not sim.services.npc_relationships.blocked(b,a,"connect").is_empty(): return false
	return true

func visit_started(a: String,b: String,active: Dictionary,instance: String = "") -> void:
	if not trackable_pair(a,b): return
	var other := _person(b)
	if other.mind.active.get("partner","")!=a: return
	var key := _pair_key(a,b)+":"+str(int(active.started))
	if book().visits.has(key): return
	book().visits[key] = {"id":_serial("visit:"),"status":"active","a":a,"b":b,"started":int(active.started),"due":int(active.due),"instance":instance}

func visit_cancelled(a: String,b: String,started: int,reason: String) -> void:
	var key := _pair_key(a,b)+":"+str(started)
	if not book().visits.has(key): return
	var visit: Dictionary = book().visits[key]
	book().visits.erase(key)
	var pair := _pair_key(a,b)
	if not book().pairs.has(pair):
		if book().pairs.size()>=64: return
		book().pairs[pair] = {"a":a,"b":b,"cancellations":[],"cooldown":0,"handled":""}
	var history: Array = book().pairs[pair].cancellations
	history.append({"id":str(visit.id),"minute":now(),"reason":reason})
	while history.size()>4: history.pop_front()
	if not str(visit.instance).is_empty(): _finish_case(str(visit.instance),"interrupted")

func visit_finished(a: String,b: String,started: int,accepted: bool) -> void:
	var key := _pair_key(a,b)+":"+str(started)
	if not book().visits.has(key): return
	var visit: Dictionary = book().visits[key]
	book().visits.erase(key)
	if not str(visit.instance).is_empty(): _finish_case(str(visit.instance),"completed" if accepted else "declined")

func _private_log(id: String,instance: String,status: String,other: String) -> void:
	var history: Array = _person(id).mind.history
	history.append({"kind":"random_event","minute":now(),"data":{"event":DISTANCE,"instance":instance,"status":status,"other":other,"visibility":"participants"}})
	while history.size()>int(sim.services.npc_agency.rules().history_limit): history.pop_front()

func _finish_case(key: String,status: String) -> void:
	if not book().npc_cases.has(key): return
	var event: Dictionary = book().npc_cases[key]
	if event.status in ["completed","declined","interrupted","acknowledged","left"]: return
	event.status=status
	for ids in [[event.a,event.b],[event.b,event.a]]: _private_log(str(ids[0]),key,status,str(ids[1]))

func _release(event: Dictionary) -> void:
	for index in 2:
		var npc := _person(str(event.a if index==0 else event.b))
		if int(npc.pinned_until)==int(event.due): npc.pinned_until=int(event.pins[index])

func _tick_npc() -> void:
	for key in book().npc_cases:
		var event: Dictionary = book().npc_cases[key]
		if event.status!="proposal" or now()<int(event.due): continue
		_release(event)
		if not pair_available(str(event.a),str(event.b),visit_horizon() if event.choice=="a" else 0): _finish_case(str(key),"interrupted"); continue
		if event.choice=="b": _finish_case(str(key),"acknowledged"); continue
		event.status="visiting"
		if not sim.services.npc_agency.begin_event_visit(str(event.a),str(event.b),str(key)): _finish_case(str(key),"interrupted")
	if now()%15!=0 or now()<int(book().next_npc): return
	for pair in book().pairs:
		var facts: Dictionary = book().pairs[pair]
		if now()<int(facts.cooldown): continue
		var recent: Array = facts.cancellations.filter(func(item): return now()-int(item.minute)<=10080)
		var signature := str(recent[-2].id)+"|"+str(recent[-1].id) if recent.size()>=2 else ""
		if signature==facts.handled: continue
		if recent.size()<2 or not pair_available(str(facts.a),str(facts.b),6+visit_horizon()): continue
		_prune(book().npc_cases,32,["proposal","visiting"])
		if book().npc_cases.size()>=32: return
		var key := _serial("npc:")
		var a := str(facts.a); var b := str(facts.b)
		var npc := _person(a)
		var eagerness: float = sim.services.npc_personalities.f(npc,"sociability")+sim.services.npc_personalities.f(npc,"sentimentality")
		var roll: float = sim.rng.randf()*(eagerness+1.0)
		var choice := "a" if roll<eagerness else "b" if roll<eagerness+0.7 else "leave"
		var duration := 6 if choice=="a" else 8 if choice=="b" else 0
		var event := {"status":"proposal","a":a,"b":b,"choice":choice,"created":now(),"due":now()+duration,
			"pins":[int(_person(a).pinned_until),int(_person(b).pinned_until)],"source_ids":[recent[-2].id,recent[-1].id]}
		book().npc_cases[key]=event
		facts.cooldown=now()+4320
		facts.handled=signature
		book().next_npc=now()+180
		if choice=="leave": _finish_case(key,"left"); return
		var response: Dictionary = sim.services.npc_relationships.forecast(a,b,"connect")
		if sim.rng.randf()>=float(response.chance): _finish_case(key,"declined"); return
		for id in [a,b]:
			sim.services.npc_agency._cancel(_person(id),"agreed_optional_conversation")
			_person(id).pinned_until=event.due
		_private_log(a,key,"proposal_accepted",b)
		_private_log(b,key,"proposal_accepted",a)
		return

func tick(minute: int) -> void:
	super.tick(minute)
	if not enabled(): return
	_tick_phone()
	_tick_npc()

static func state_error(state: Dictionary) -> String:
	var data: Variant = state.journal.get("random_events")
	if not Check.fields(data,{"version":"n","serial":"n","next_phone":"n","next_npc":"n","phone":"d","visits":"d","pairs":"d","npc_cases":"d"}) or data.version!=1: return "invalid_random_events"
	for key in ["serial","next_phone","next_npc"]:
		if not _integer(data[key]): return "invalid_random_event_counter"
	if data.phone.size()>32 or data.visits.size()>100 or data.pairs.size()>64 or data.npc_cases.size()>32: return "unbounded_random_events"
	var now: int = state.clock.total_minutes
	for event in data.phone.values():
		if not Check.fields(event,{"status":"s","npc":"s","created":"n","expires":"n","source":"n","outgoing":"n","reply":"n","due":"n"}) or not state.social.npcs.has(event.npc): return "invalid_random_phone"
		if event.status not in ["offered","committing","awaiting_reply","replied","deferred","dismissed","completed","expired"]: return "invalid_random_phone_status"
		for key in ["created","expires","source","outgoing","reply","due"]:
			if not _integer(event[key]): return "invalid_random_phone_time"
		for key in ["outgoing","reply"]:
			if int(event[key])>=int(state.social.next_message_id): return "invalid_random_message_identity"
		if int(event.created)>now or int(event.expires)<int(event.created) or int(event.source)<1 or int(event.source)>=int(state.social.next_message_id): return "invalid_random_phone_source"
		if event.status=="committing": return "unfinished_random_event_commit"
		if event.status in ["awaiting_reply","replied","completed"] and int(event.outgoing)<1: return "missing_random_event_outgoing"
		if event.status=="replied" and int(event.reply)<1: return "missing_random_event_reply"
	for key in data.visits:
		var visit: Variant = data.visits[key]
		if not Check.fields(visit,{"id":"s","status":"s","a":"s","b":"s","started":"n","due":"n","instance":"s"}): return "invalid_random_visit"
		if not state.social.npcs.has(visit.a) or not state.social.npcs.has(visit.b) or visit.a==visit.b or visit.status!="active": return "invalid_random_visit_actors"
		if not _integer(visit.started) or not _integer(visit.due) or int(visit.started)>now or int(visit.due)<int(visit.started): return "invalid_random_visit_time"
		var ids: Array = [str(visit.a),str(visit.b)]; ids.sort()
		if key!=str(ids[0])+"|"+str(ids[1])+":"+str(int(visit.started)): return "invalid_random_visit_identity"
		var active: Dictionary = state.social.npcs[visit.a].mind.active
		if active.get("partner","")!=visit.b or int(active.get("started",-1))!=int(visit.started) or active.get("action","")!="connect": return "orphan_random_visit"
		if not str(visit.instance).is_empty() and not data.npc_cases.has(visit.instance): return "missing_random_visit_case"
	for key in data.pairs:
		var pair: Variant = data.pairs[key]
		if not Check.fields(pair,{"a":"s","b":"s","cancellations":"a","cooldown":"n","handled":"s"}): return "invalid_random_pair_history"
		if not state.social.npcs.has(pair.a) or not state.social.npcs.has(pair.b) or pair.a==pair.b or pair.cancellations.size()>4 or not _integer(pair.cooldown): return "invalid_random_pair_history"
		var ids: Array = [str(pair.a),str(pair.b)]; ids.sort()
		if key!=str(ids[0])+"|"+str(ids[1]): return "invalid_random_pair_identity"
		var seen: Array = []
		for fact in pair.cancellations:
			if not Check.fields(fact,{"id":"s","minute":"n","reason":"s"}) or not _integer(fact.minute) or int(fact.minute)>now or fact.id in seen: return "invalid_random_cancellation_fact"
			seen.append(fact.id)
	for case_id in data.npc_cases:
		var event: Variant = data.npc_cases[case_id]
		if not Check.fields(event,{"status":"s","a":"s","b":"s","choice":"s","created":"n","due":"n","pins":"a","source_ids":"a"}): return "invalid_random_npc_event"
		if not state.social.npcs.has(event.a) or not state.social.npcs.has(event.b) or event.a==event.b or event.pins.size()!=2 or event.source_ids.size()!=2: return "invalid_random_npc_pair"
		if event.choice not in ["a","b","leave"] or event.status not in ["proposal","visiting","completed","declined","interrupted","acknowledged","left"]: return "invalid_random_npc_status"
		if not _integer(event.created) or not _integer(event.due) or int(event.created)>now or int(event.due)<int(event.created) or event.source_ids[0]==event.source_ids[1]: return "invalid_random_npc_source"
		for pin in event.pins:
			if not _integer(pin) or int(pin)>int(event.created): return "invalid_random_npc_pin"
		if event.status=="visiting":
			var linked := 0
			for visit in data.visits.values():
				if visit.instance==case_id: linked+=1
			if event.choice!="a" or linked!=1: return "orphan_random_event_visit"
	return ""

static func _integer(value: Variant) -> bool:
	return Check.number(value) and float(value)>=0 and float(value)==int(value)
