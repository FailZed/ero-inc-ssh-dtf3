extends RefCounted

const Rules = preload("res://scripts/mechanics/core/rules.gd")
var _simulation: WeakRef
var sim:
	get: return _simulation.get_ref()

func _init(simulation) -> void:
	_simulation = weakref(simulation)

func execute(_operation: String, _args: Dictionary) -> Dictionary:
	return Rules.fail("unknown_operation")

func tick(_minute: int) -> void:
	pass

func definition(group: String, id: String) -> Dictionary:
	return sim.catalog.get(group, {}).get(id, {})

func emit_event(kind: String, data: Dictionary = {}) -> void:
	sim.pending_events.append({"kind": kind, "minute": sim.state.clock.total_minutes, "data": data.duplicate(true)})
