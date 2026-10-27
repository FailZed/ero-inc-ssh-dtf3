extends Node
## Optional implementation of Quest Weaver's SimpleInventoryAdapter contract.
## Bind before its initialize(), or reinitialize the adapter after binding.

signal inventory_changed
signal operation_failed(reason: String)
var _simulation

func bind(simulation) -> void:
	if _simulation != null and _simulation.committed.is_connected(_on_committed):
		_simulation.committed.disconnect(_on_committed)
	_simulation = simulation
	if _simulation != null:
		_simulation.committed.connect(_on_committed)
		add_to_group("inventory_controller")
	else:
		remove_from_group("inventory_controller")

func _exit_tree() -> void:
	bind(null)

func count_item(item_id: String) -> int:
	return int(_simulation.state.inventory.items.get(item_id, 0)) if _simulation != null else 0

func check_item(item_id: String, amount: int) -> bool:
	return amount > 0 and count_item(item_id) >= amount

func give_item(item_id: String, amount: int) -> void:
	if _simulation == null:
		operation_failed.emit("inventory_unbound")
		return
	var result: Dictionary = _simulation.command("inventory", "add", {"id": item_id, "quantity": amount})
	if not result.ok: operation_failed.emit(str(result.error))

func take_item(item_id: String, amount: int) -> bool:
	if _simulation == null: return false
	return bool(_simulation.command("inventory", "remove", {"id": item_id, "quantity": amount}).ok)

func _on_committed(_module_id: String, _operation: String, _result: Dictionary) -> void:
	inventory_changed.emit()
