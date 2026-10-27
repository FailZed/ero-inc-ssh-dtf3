extends "res://scripts/mechanics/core/module.gd"

func execute(operation: String, args: Dictionary) -> Dictionary:
	match operation:
		"combat_start": return _combat_start(str(args.get("npc", "")))
		"combat_action": return _combat_action(args)
		"game_start": return _game_start(args)
		"game_input": return _game_input(args)
		"cancel_game":
			var game: Dictionary = sim.state.encounters.game
			if game.is_empty() or game.status != "active": return Rules.fail("no_active_game")
			_finish_game(game, "lost")
			return Rules.ok({"status":"lost"})
		"steal", "burglary": return _crime(operation, args)
	return Rules.fail("unknown_operation")

func _combat_start(id: String) -> Dictionary:
	return sim.services.combat.start(id)

func _combat_action(args: Dictionary) -> Dictionary:
	return sim.services.combat.action(args)

func _game_start(args: Dictionary) -> Dictionary:
	var current: Dictionary = sim.state.encounters.game
	if not current.is_empty() and current.status == "active": return Rules.fail("game_active")
	var type := str(args.get("type", "reaction"))
	if not type in ["blackjack", "reaction", "strength", "guess", "lockpick", "timing", "pushups"]: return Rules.fail("unknown_game")
	var stake := int(args.get("stake", 0))
	if stake < 0 or stake > sim.state.economy.cash: return Rules.fail("invalid_stake")
	sim.state.economy.cash -= stake
	var game := {"type": type, "status": "active", "stake": stake, "progress": 0.0,
		"attempts": 0, "limit": int(args.get("limit", 5)), "target": sim.rng.randf_range(0.2, 0.8)}
	if int(game.limit) < 1 or int(game.limit) > 100: return Rules.fail("invalid_game_limit")
	if type == "blackjack":
		var deck: Array = []
		for suit in range(4):
			for rank in range(1, 14): deck.append(rank)
		for i in range(deck.size() - 1, 0, -1):
			var j: int = sim.rng.randi_range(0, i)
			var temp: int = deck[i]
			deck[i] = deck[j]
			deck[j] = temp
		game.deck = deck
		game.hand = [deck.pop_back(), deck.pop_back()]
		game.dealer = [deck.pop_back(), deck.pop_back()]
	elif type == "guess":
		game.secret = sim.rng.randi_range(1, 10)
	elif type == "lockpick":
		game.pins = [sim.rng.randi_range(0, 2), sim.rng.randi_range(0, 2), sim.rng.randi_range(0, 2)]
		game.pin = 0
	elif type in ["timing", "pushups"]:
		game.elapsed_ms = 0
		game.last_input_ms = 0
		game.duration_ms = int(args.get("duration_ms", 30000 if type == "pushups" else 10000))
		game.reps = 0
		game.required_reps = int(args.get("required_reps", 3))
		game.phase = 0.0
		if game.duration_ms < 1000 or game.duration_ms > 60000 or game.required_reps < 1 or game.required_reps > 50: return Rules.fail("invalid_timed_game")
	sim.state.encounters.game = game
	return Rules.ok({"type": type})

func _game_input(args: Dictionary) -> Dictionary:
	var game: Dictionary = sim.state.encounters.game
	if game.is_empty() or game.status != "active": return Rules.fail("no_active_game")
	var value := float(args.get("value", 0))
	match str(game.type):
		"timing", "pushups": return _timed_input(game, args)
		"blackjack":
			var action := str(args.get("action", "hit"))
			if action == "hit":
				game.hand.append(game.deck.pop_back())
				if score(game.hand) > 21: _finish_game(game, "lost")
			elif action == "stand":
				while score(game.dealer) < 17: game.dealer.append(game.deck.pop_back())
				var player_score := score(game.hand)
				var dealer_score := score(game.dealer)
				_finish_game(game, "won" if dealer_score > 21 or player_score > dealer_score else ("draw" if player_score == dealer_score else "lost"))
			else: return Rules.fail("invalid_card_action")
		"reaction":
			if value < 0.0 or value > 1.0: return Rules.fail("invalid_reaction_value")
			_finish_game(game, "won" if absf(value - float(game.target)) <= 0.12 else "lost")
		"strength":
			if value <= 0.0 or value > 1.0: return Rules.fail("invalid_effort")
			game.progress += value * (sim.services.character.effective_stat("strength") + 5.0)
			game.attempts += 1
			if game.progress >= 30.0: _finish_game(game, "won")
			elif game.attempts >= game.limit: _finish_game(game, "lost")
		"guess":
			if value != int(value) or value < 1 or value > 10: return Rules.fail("invalid_guess")
			game.attempts += 1
			game.hint = "higher" if value < int(game.secret) else "lower"
			if int(value) == int(game.secret): _finish_game(game, "won")
			elif game.attempts >= game.limit: _finish_game(game, "lost")
		"lockpick":
			if value != int(value) or value < 0 or value > 2: return Rules.fail("invalid_pin")
			game.attempts += 1
			if int(value) == int(game.pins[int(game.pin)]): game.pin += 1
			if game.pin >= game.pins.size(): _finish_game(game, "won")
			elif game.attempts >= game.limit: _finish_game(game, "lost")
	return Rules.ok({"status": game.status})

func score(hand: Array) -> int:
	var total := 0
	var aces := 0
	for rank in hand:
		if int(rank) == 1:
			total += 11
			aces += 1
		else: total += mini(10, int(rank))
	while total > 21 and aces > 0:
		total -= 10
		aces -= 1
	return total

func _finish_game(game: Dictionary, status: String) -> void:
	game.status = status
	if status == "won": sim.state.economy.cash += int(game.stake) * 2
	elif status == "draw": sim.state.economy.cash += int(game.stake)
	if game.has("context") and game.context.get("kind", "") == "burglary": sim.services.security.resolve_burglary(game.context, status)
	elif game.has("elapsed_ms"): sim.advance(maxi(1, int(ceil(float(game.elapsed_ms) / 60000.0))))
	emit_event("game_finished", {"type": game.type, "status": status})

func _timed_input(game: Dictionary, args: Dictionary) -> Dictionary:
	var elapsed := int(args.get("elapsed_ms", -1))
	if elapsed < int(game.elapsed_ms): return Rules.fail("non_monotonic_game_time")
	var delta := elapsed - int(game.elapsed_ms)
	game.elapsed_ms = elapsed
	if elapsed >= int(game.duration_ms):
		_finish_game(game, "lost")
		return Rules.ok({"status": game.status})
	if elapsed - int(game.last_input_ms) < 100: return Rules.fail("input_debounce")
	game.last_input_ms = elapsed
	if game.type == "timing":
		game.phase = fposmod(float(elapsed) / 1000.0, 1.0)
		var distance := absf(float(game.phase) - float(game.target))
		if minf(distance, 1.0 - distance) <= 0.12: game.reps += 1
		else: game.reps = maxi(0, int(game.reps) - 1)
	else:
		game.progress -= delta * (0.001 + int(game.reps) * 0.0003)
		if game.progress <= -15.0 or sim.state.player.needs.energy <= 0:
			_finish_game(game, "lost")
			return Rules.ok({"status": game.status})
		game.progress += 5.0 + sim.services.character.effective_stat("strength") * 0.5
		if game.progress >= 100.0:
			game.progress -= 100.0
			game.reps += 1
			sim.services.character.adjust_need("energy", -1.0)
	if game.reps >= game.required_reps:
		_finish_game(game, "won")
		sim.services.character.execute("train", {"skill": "fighting", "xp": int(game.reps) * 2})
	return Rules.ok({"status": game.status, "reps": game.reps, "progress": game.progress})

func _crime(operation: String, args: Dictionary) -> Dictionary:
	return sim.services.security.execute(operation, args)
