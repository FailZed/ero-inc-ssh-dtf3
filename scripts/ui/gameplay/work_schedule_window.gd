extends Control
signal confirmed
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const Frame = preload("res://scripts/ui/gameplay/game_window.gd")
const Names = preload("res://scripts/gameplay/presentation.gd")
var conflicts: Array = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var window := Frame.new()
	window.title = "Работа пересекается с учёбой"
	window.subtitle = "Выберите, как распорядиться этим временем"
	window.preferred_size = Vector2(1080,650)
	window.back_requested.connect(queue_free)
	add_child(window)
	UI.label(window.body,"Смена и дорога до кампуса не помещаются до выбранных занятий:",22,UI.ORANGE)
	for lesson in conflicts:
		UI.label(window.body,"%s · %02d:%02d–%02d:%02d · дорога %d мин" % [Names.title(str(lesson.id)),int(lesson.start)%1440/60,int(lesson.start)%60,int(lesson.end)%1440/60,int(lesson.end)%60,lesson.commute],20)
	UI.label(window.body,"Если выйти сейчас, занятия можно пропустить. Посещаемость и успеваемость изменятся по обычным правилам; повторные пропуски могут привести к отчислению.",20,UI.MUTED)
	UI.button(window.body,"ОСТАТЬСЯ С УЧЁБОЙ",queue_free).grab_focus()
	var proceed := UI.button(window.body,"ВЫЙТИ НА РАБОТУ С ПРОПУСКОМ ЗАНЯТИЙ",func(): confirmed.emit(); queue_free())
	proceed.set_meta("confirm_work_skip",true)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"): get_viewport().set_input_as_handled(); queue_free()
