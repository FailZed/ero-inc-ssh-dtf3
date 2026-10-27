extends RefCounted
## One owner for each model parameter. Sources are mixed by priority before smoothing.
signal changed(id: String, value: float)

var definitions: Dictionary = {}
var values: Dictionary = {}
var targets: Dictionary = {}
var velocities: Dictionary = {}
var channels: Dictionary = {}
var smoothing := 0.12
var mode := "smooth"

func configure(specifications: Array) -> void:
	definitions.clear()
	values.clear()
	targets.clear()
	velocities.clear()
	channels.clear()
	for item: Dictionary in specifications:
		var id := str(item.get("id", ""))
		if id.is_empty(): continue
		var minimum := float(item.get("min", -1.0))
		var maximum := float(item.get("max", 1.0))
		if not is_finite(minimum) or not is_finite(maximum) or maximum < minimum: continue
		var initial := clampf(float(item.get("default", 0.0)), minimum, maximum)
		if not is_finite(initial): continue
		definitions[id] = {"id":id, "min":minimum, "max":maximum, "default":initial}
		values[id] = initial
		targets[id] = initial
		velocities[id] = 0.0

func has_parameter(id: String) -> bool:
	return definitions.has(id)

func normalized_value(id: String, amount: float) -> float:
	if not definitions.has(id): return 0.0
	var spec: Dictionary = definitions[id]
	return lerpf(float(spec.default), float(spec.max if amount >= 0.0 else spec.min), clampf(absf(amount), 0.0, 1.0))

func set_target(id: String, value: float, channel: String = "manual", priority: int = 100, blend: String = "replace") -> bool:
	if not definitions.has(id) or not is_finite(value): return false
	if not channels.has(channel): channels[channel] = {"priority":priority, "blend":blend, "parameters":{}}
	channels[channel].priority = priority
	channels[channel].blend = blend
	channels[channel].parameters[id] = clampf(value, definitions[id].min, definitions[id].max) if blend == "replace" else value
	return true

func set_normalized(id: String, amount: float, channel: String = "pointer", priority: int = 60) -> bool:
	return set_target(id, normalized_value(id, amount), channel, priority)

func set_targets(parameters: Dictionary, channel: String, priority: int = 100, blend: String = "replace") -> void:
	clear_channel(channel)
	for id in parameters:
		var value: Variant = parameters[id]
		if value is int or value is float: set_target(str(id), float(value), channel, priority, blend)

func clear_channel(channel: String) -> void:
	channels.erase(channel)

func reset() -> void:
	channels.clear()
	for id in definitions:
		values[id] = definitions[id].default
		targets[id] = definitions[id].default
		velocities[id] = 0.0

func target_for(id: String) -> float:
	if not definitions.has(id): return 0.0
	var order: Array = channels.keys()
	order.sort_custom(func(a, b): return int(channels[a].priority) < int(channels[b].priority) if channels[a].priority != channels[b].priority else str(a) < str(b))
	var result := float(definitions[id].default)
	for key in order:
		var source: Dictionary = channels[key]
		if not source.parameters.has(id): continue
		if source.blend == "add": result += float(source.parameters[id])
		else: result = float(source.parameters[id])
	return clampf(result, definitions[id].min, definitions[id].max)

func advance(delta: float) -> void:
	if delta <= 0.0 or not is_finite(delta): return
	var duration := maxf(smoothing, 0.001)
	for id in definitions:
		var target := target_for(id)
		targets[id] = target
		var current := float(values[id])
		var next := current
		match mode:
			"linear":
				next = move_toward(current, target, float(definitions[id].max - definitions[id].min) * delta / duration)
			"spring":
				# Exact critically damped spring step, stable across render frame rates.
				var omega := 4.0 / duration
				var offset := current - target
				var velocity := float(velocities[id])
				var common := velocity + omega * offset
				var decay := exp(-omega * delta)
				next = target + (offset + common * delta) * decay
				velocities[id] = (velocity - omega * common * delta) * decay
			_:
				next = lerpf(current, target, 1.0 - exp(-delta / duration))
		next = clampf(next, definitions[id].min, definitions[id].max)
		if absf(next - target) < 0.00001: next = target
		values[id] = next
		if not is_equal_approx(next, current): changed.emit(str(id), next)

func snapshot() -> Dictionary:
	return values.duplicate(true)

func restore(parameters: Dictionary, channel: String = "manual") -> void:
	set_targets(parameters, channel, 100)

func inspect(id: String) -> Dictionary:
	if not definitions.has(id): return {}
	var result: Dictionary = definitions[id].duplicate(true)
	result.value = values[id]
	result.target = target_for(id)
	return result
