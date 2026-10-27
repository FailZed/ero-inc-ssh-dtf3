extends Button

@export var hide_when_unavailable := true


func _ready() -> void:
	pressed.connect(_on_pressed)
	if LocationManager.has_signal("location_changed"):
		LocationManager.location_changed.connect(_refresh_state)
	_refresh_state(LocationManager.current_location_id)


func _exit_tree() -> void:
	if LocationManager.location_changed.is_connected(_refresh_state):
		LocationManager.location_changed.disconnect(_refresh_state)


func _on_pressed() -> void:
	LocationManager.go_back()


func _refresh_state(_location_id: String = "") -> void:
	var can_return := LocationManager.can_go_back()
	disabled = not can_return
	if hide_when_unavailable:
		visible = can_return
