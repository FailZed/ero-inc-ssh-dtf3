extends "res://scripts/mechanics/encounters.gd"

func _game_start(args: Dictionary) -> Dictionary:
	var result := super._game_start(args)
	if not result.ok: return result
	var game: Dictionary = sim.state.encounters.game
	game.assistance = sim.services.growth.game_assistance(str(game.type))
	if game.type in ["guess","lockpick"]: game.limit = mini(12,int(game.limit)+int(game.assistance.extra_attempts))
	if game.has("duration_ms"): game.duration_ms = clampi(roundi(float(game.duration_ms)*float(game.assistance.time_factor)),1000,60000)
	return result

func _game_input(args: Dictionary) -> Dictionary:
	var game: Dictionary = sim.state.encounters.game
	if game.is_empty() or game.status != "active": return Rules.fail("no_active_game")
	if not game.type in ["reaction","strength"]: return super._game_input(args)
	var value := float(args.get("value",0))
	if value < 0 or value > 1 or (game.type == "strength" and value <= 0): return Rules.fail("invalid_effort")
	var help := float(game.assistance.help)
	if game.type == "reaction":
		var tolerance := float(game.assistance.window)
		_finish_game(game,"won" if absf(value-float(game.target)) <= tolerance else "lost")
	else:
		# Even a very strong expert needs at least three deliberate inputs.
		var effort := minf(12.0,(sim.services.character.effective_stat("strength")+5)*(1+help))
		game.progress += value*effort
		game.attempts += 1
		if game.progress >= 30: _finish_game(game,"won")
		elif game.attempts >= game.limit: _finish_game(game,"lost")
	return Rules.ok({"status":game.status})

func _timed_input(game: Dictionary, args: Dictionary) -> Dictionary:
	var elapsed := int(args.get("elapsed_ms",-1))
	if elapsed < int(game.elapsed_ms): return Rules.fail("non_monotonic_game_time")
	var delta := elapsed-int(game.elapsed_ms)
	game.elapsed_ms = elapsed
	if elapsed >= int(game.duration_ms): _finish_game(game,"lost"); return Rules.ok({"status":game.status})
	if elapsed-int(game.last_input_ms) < 100: return Rules.fail("input_debounce")
	game.last_input_ms = elapsed
	var help := float(game.assistance.help)
	if game.type == "timing":
		game.phase = fposmod(float(elapsed)/1000.0,1.0)
		var distance := absf(float(game.phase)-float(game.target))
		if minf(distance,1.0-distance) <= float(game.assistance.window): game.reps += 1
		else: game.reps = maxi(0,int(game.reps)-1)
	else:
		game.progress -= delta*(0.001+int(game.reps)*0.0003)
		if game.progress <= -15 or sim.state.player.needs.energy <= 0: _finish_game(game,"lost"); return Rules.ok({"status":game.status})
		game.progress += minf(25,5+sim.services.character.effective_stat("strength")*0.5+help*10)
		if game.progress >= 100:
			game.progress -= 100
			game.reps += 1
			sim.services.character.adjust_need("energy",-1)
	if game.reps >= game.required_reps:
		_finish_game(game,"won")
		sim.services.character.execute("train",{"skill":"fighting","xp":int(game.reps)*2})
	return Rules.ok({"status":game.status,"reps":game.reps,"progress":game.progress})
