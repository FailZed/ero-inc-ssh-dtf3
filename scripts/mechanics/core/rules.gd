extends RefCounted
## Declarative predicates only. No eval, script names or executable expressions.

static func ok(data: Dictionary = {}) -> Dictionary:
	return {"ok": true, "data": data}

static func fail(reason: String) -> Dictionary:
	return {"ok": false, "error": reason}

static func read(state: Dictionary, path: String, fallback: Variant = null) -> Variant:
	var value: Variant = state
	for part in path.split("."):
		if not value is Dictionary or not value.has(part):
			return fallback
		value = value[part]
	return value

static func write(state: Dictionary, path: String, value: Variant) -> void:
	var parts := path.split(".")
	var current := state
	for i in range(parts.size() - 1):
		if not current.has(parts[i]) or not current[parts[i]] is Dictionary:
			current[parts[i]] = {}
		current = current[parts[i]]
	current[parts[-1]] = value

static func check(state: Dictionary, condition: Variant) -> bool:
	if condition is Array:
		for entry in condition:
			if not check(state, entry):
				return false
		return true
	if not condition is Dictionary:
		return false
	if condition.is_empty():
		return true
	if condition.has("all"):
		return check(state, condition.all)
	if condition.has("any"):
		for entry in condition.any:
			if check(state, entry):
				return true
		return false
	if condition.has("not"):
		return not check(state, condition["not"])
	var actual: Variant = read(state, str(condition.get("path", "")))
	var expected: Variant = condition.get("value")
	match str(condition.get("op", "eq")):
		"eq": return actual == expected
		"ne": return actual != expected
		"exists": return actual != null
		"gte": return _number_compare(actual, expected, "gte")
		"lte": return _number_compare(actual, expected, "lte")
		"gt": return _number_compare(actual, expected, "gt")
		"lt": return _number_compare(actual, expected, "lt")
		"in": return _contains(expected, actual)
		"contains": return _contains(actual, expected)
	return false

static func _contains(collection: Variant, value: Variant) -> bool:
	if collection is Dictionary: return collection.has(value)
	if collection is Array:
		for entry in collection:
			if entry == value: return true
	return false

static func _number_compare(a: Variant, b: Variant, op: String) -> bool:
	if not (a is int or a is float) or not (b is int or b is float):
		return false
	match op:
		"gte": return a >= b
		"lte": return a <= b
		"gt": return a > b
		"lt": return a < b
	return false

static func in_window(minute: int, start: int, finish: int) -> bool:
	if start == finish:
		return true
	return minute >= start and minute < finish if start < finish else minute >= start or minute < finish
