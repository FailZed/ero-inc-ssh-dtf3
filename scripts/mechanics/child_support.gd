extends "res://scripts/mechanics/core/module.gd"
## Game contracts, not jurisdiction-specific law. Kinship, custody and debt are separate.
const CHECK = preload("res://scripts/mechanics/core/human_validation.gd")

static func defaults() -> Dictionary:
	return {"version":1, "obligations":{}, "history":[]}

func _now() -> int:
	return int(sim.state.clock.total_minutes)

func rules() -> Dictionary:
	return sim.catalog.child_support_rules.simulation

func _log(kind: String, id: String, amount: int = 0) -> void:
	var entry := {"kind":kind,"id":id,"minute":_now(),"amount":amount}
	sim.state.child_support.history.append(entry)
	while sim.state.child_support.history.size() > 128: sim.state.child_support.history.pop_front()
	emit_event("child_support_" + kind, entry)

func _available(id: String) -> int:
	if id == "player": return int(sim.state.economy.cash) + int(sim.state.economy.bank)
	return int(sim.state.social.npcs[id].money)

func _transfer(obligation: Dictionary, amount: int) -> void:
	if obligation.payer == "player":
		var cash := mini(amount, int(sim.state.economy.cash))
		sim.state.economy.cash -= cash
		sim.state.economy.bank -= amount - cash
	else: sim.state.social.npcs[obligation.payer].money -= amount
	if obligation.recipient == "player": sim.state.economy.cash += amount
	elif obligation.recipient != "public_care": sim.state.social.npcs[obligation.recipient].money += amount
	obligation.arrears -= amount
	obligation.paid += amount
	_log("payment", str(obligation.id), amount)

func synchronize() -> void:
	for o in sim.state.child_support.obligations.values():
		var member: Dictionary = sim.state.family.members[o.member]
		var guardians: Array = member.get("guardians", member.parents)
		var recipient := "public_care" if guardians.is_empty() else str(guardians[0])
		var liable: bool = not o.payer in guardians and member.get("custody", "parents") != "adoption" and _now() < int(o.ends_at)
		var active: bool = liable and recipient == o.recipient
		if active and not o.active: o.next_due = sim.calendar.add_months(_now(),1)
		o.active = active
	for member in sim.state.family.members.values():
		var guardians: Array = member.get("guardians", member.parents)
		for payer in member.parents:
			var recipient := "public_care" if guardians.is_empty() else str(guardians[0])
			var id := str(member.id) + ":" + str(payer) + ":" + recipient
			var liable: bool = not payer in guardians and member.get("custody", "parents") != "adoption" and _now() < sim.calendar.add_months(int(member.born), int(rules().adult_months))
			if liable and not sim.state.child_support.obligations.has(id):
				sim.state.child_support.obligations[id] = {"id":id,"member":member.id,"payer":payer,"recipient":recipient,
					"monthly":int(rules().monthly_amount),"arrears":0,"paid":0,"billed":0,"next_due":sim.calendar.add_months(_now(),1),
					"ends_at":sim.calendar.add_months(int(member.born), int(rules().adult_months)),"active":true,"enforcement_due":0,"order":false,"autopay":payer!="player"}
				_log("opened", id)

func execute(operation: String, args: Dictionary) -> Dictionary:
	if operation == "inspect": return Rules.ok(sim.state.child_support.duplicate(true))
	synchronize()
	var id := str(args.get("id", ""))
	var o: Dictionary = sim.state.child_support.obligations.get(id, {})
	if o.is_empty(): return Rules.fail("unknown_support_obligation")
	match operation:
		"autopay":
			if str(args.get("actor", "player")) != str(o.payer): return Rules.fail("support_payer_required")
			if not args.get("enabled") is bool: return Rules.fail("invalid_support_payment")
			o.autopay = args.enabled
		"pay":
			if str(args.get("actor", "player")) != str(o.payer): return Rules.fail("support_payer_required")
			var value: Variant = args.get("amount", o.arrears)
			if not CHECK.integer(value, 1, 100000000) or int(value) > int(o.arrears): return Rules.fail("invalid_support_payment")
			if _available(str(o.payer)) < int(value): return Rules.fail("insufficient_funds")
			_transfer(o, int(value))
		"agreement":
			if args.get("confirm", false) != true: return Rules.fail("confirmation_required")
			if not args.get("accepted_by") is Array or not o.payer in args.accepted_by or not o.recipient in args.accepted_by: return Rules.fail("support_agreement_requires_both")
			if not CHECK.integer(args.get("monthly"), 1, 1000000): return Rules.fail("invalid_support_amount")
			o.monthly = int(args.monthly)
			_log("agreement", id, int(o.monthly))
		"file_enforcement":
			if str(args.get("actor", "player")) != str(o.recipient): return Rules.fail("support_recipient_required")
			if int(o.arrears) <= 0: return Rules.fail("no_support_arrears")
			if o.order or int(o.enforcement_due) > 0: return Rules.fail("support_enforcement_pending")
			var actor: String = str(o.recipient)
			if actor == "public_care": return Rules.fail("support_recipient_required")
			if not sim.services.reproduction._pay(actor, int(rules().filing_cost)): return Rules.fail("insufficient_funds")
			o.enforcement_due = _now() + int(rules().enforcement_delay)
			_log("enforcement_filed", id)
		_: return Rules.fail("unknown_operation")
	return Rules.ok(o.duplicate(true))

func tick(minute: int) -> void:
	if minute % 60 != 0: return
	synchronize()
	for o in sim.state.child_support.obligations.values():
		# Catch up every missed calendar due date exactly once. Debt survives adulthood/custody changes.
		while o.active and int(o.next_due) <= minute and int(o.next_due) < int(o.ends_at):
			o.arrears += int(o.monthly)
			o.billed += int(o.monthly)
			o.next_due = sim.calendar.add_months(int(o.next_due), 1)
			_log("billed", str(o.id), int(o.monthly))
		if int(o.enforcement_due) > 0 and minute >= int(o.enforcement_due):
			o.order = true
			o.enforcement_due = 0
			_log("order", str(o.id))
		if (o.order or o.autopay) and int(o.arrears) > 0 and o.recipient != o.payer:
			var amount := mini(int(o.arrears), _available(str(o.payer)))
			if amount > 0: _transfer(o, amount)
