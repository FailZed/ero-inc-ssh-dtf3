extends Control
signal confirmed
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const Frame = preload("res://scripts/ui/gameplay/game_window.gd")
const Names = preload("res://scripts/gameplay/presentation.gd")
const W = preload("res://scripts/ui/gameplay/game_widgets.gd")
var conflicts: Array = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var window := Frame.new()
	window.title = "Работа или занятия?"
	window.subtitle = "Выберите, как распорядиться этим временем"
	window.preferred_size = Vector2(1080,650)
	window.back_requested.connect(queue_free)
	add_child(window)
	UI.label(window.body,"Смена и дорога до кампуса пересекаются с занятиями:",22,UI.ORANGE)
	var lessons := W.grid(window.body,2)
	for lesson in conflicts:
		var card := W.panel(lessons,18)
		UI.label(card,Names.title(str(lesson.id)),24,UI.BLUE)
		UI.label(card,"%02d:%02d–%02d:%02d" % [int(lesson.start)%1440/60,int(lesson.start)%60,int(lesson.end)%1440/60,int(lesson.end)%60],22)
		UI.label(card,Names.study_forecast(lesson),18,UI.MUTED)
	UI.label(window.body,"Прогноз предполагает, что после работы вы сразу отправитесь в кампус. Опоздание до 15 минут снижает награду; позже допуск закрыт. Для посещения нужно прийти и начать занятие. Пропуск учитывается один раз, в конце занятия.",20,UI.MUTED)
	UI.button(window.footer,"Остаться на занятиях",queue_free).grab_focus()
	var proceed := UI.button(window.footer,"Всё равно выйти на работу",func(): confirmed.emit(); queue_free())
	proceed.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	proceed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	proceed.add_theme_stylebox_override("normal",UI.style(Color("241f1a"),UI.ORANGE))
	proceed.set_meta("confirm_work_skip",true)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"): get_viewport().set_input_as_handled(); queue_free()
