extends Area2D

@export var target_location_id := ""


func _ready() -> void:
	input_pickable = true
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


# Assign target_location_id in the Inspector on each DoorArea node.
# Example: bathroom, kitchen, bedroom, or global_map.
func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if target_location_id.is_empty():
			push_warning("DoorArea: target_location_id is empty on %s" % get_path())
			return

		LocationManager.go_to(target_location_id)


func _on_mouse_entered() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)


func _on_mouse_exited() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
