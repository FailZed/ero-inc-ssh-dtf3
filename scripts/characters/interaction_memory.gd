extends RefCounted
## Presentation reactions and short interaction history; independent of world saves.
signal reaction_changed(state: String)

var state := "idle"
var history: Array[Dictionary] = []
var elapsed := 0.0
var attention := 0.0
var fatigue := 0.0
var _held := ""
var _hold_started := 0.0
var _distance := 0.0
var _reaction_left := 0.0

func begin(id: String) -> void:
	_held = id
	_hold_started = elapsed
	_distance = 0.0
	_change("attentive")

func motion(distance: float) -> void:
	if _held.is_empty(): return
	_distance += maxf(distance, 0.0)
	if distance > 0.12: react("surprised", 0.65)

func finish(cancelled: bool = false) -> Dictionary:
	if _held.is_empty(): return {}
	var event := {"interaction":_held, "duration":maxf(0.0, elapsed-_hold_started), "distance":_distance, "cancelled":cancelled, "time":elapsed}
	history.append(event)
	while history.size() > 64: history.pop_front()
	attention = clampf(attention + (0.0 if cancelled else 0.08), 0.0, 1.0)
	fatigue = clampf(fatigue + float(event.duration)*0.006, 0.0, 1.0)
	_held = ""
	react("idle" if cancelled else "comfortable", 1.4)
	return event

func react(value: String, seconds: float) -> void:
	_change(value)
	_reaction_left = maxf(seconds, 0.0)

func advance(delta: float) -> void:
	elapsed += maxf(delta, 0.0)
	attention = move_toward(attention, 0.0, delta*0.015)
	fatigue = move_toward(fatigue, 0.0, delta*0.003)
	_reaction_left = maxf(0.0, _reaction_left-delta)
	if _reaction_left == 0.0 and _held.is_empty(): _change("idle")

func _change(value: String) -> void:
	if state == value: return
	state = value
	reaction_changed.emit(state)

func reset() -> void:
	history.clear()
	_held = ""
	elapsed = 0.0
	attention = 0.0
	fatigue = 0.0
	_reaction_left = 0.0
	_change("idle")
