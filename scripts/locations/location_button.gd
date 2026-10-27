extends Button

@export var target_location_id := ""


func _ready() -> void:
	pressed.connect(_on_pressed)


func _on_pressed() -> void:
	if target_location_id.is_empty():
		push_warning("LocationButton: target_location_id is empty on %s" % get_path())
		return

	LocationManager.go_to(target_location_id)
