extends Control
signal confirmed(subjects: Array, sport: String)
signal menu_requested
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const W = preload("res://scripts/ui/gameplay/game_widgets.gd")
const GameFrame = preload("res://scripts/ui/gameplay/game_window.gd")
const Curriculum = preload("res://scripts/gameplay/curriculum.gd")
var _selected: Array = ["computing","physics","statistics"]
var _sport := "running"
var _button: Button
var _status: Label
var _checks: Dictionary = {}
var _window: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_window = GameFrame.new()
	_window.title = "Моё расписание"
	_window.subtitle = "Выберите 2–4 дисциплины и спортивную секцию. Понедельник — общий день группы."
	_window.back_requested.connect(menu_requested.emit)
	add_child(_window)
	_window._close.text = "Меню · Esc"
	var grid := W.grid(_window.body,2)
	for id in Curriculum.SUBJECTS:
		var spec: Dictionary = Curriculum.SUBJECTS[id]
		var card := W.panel(grid,18)
		var check := CheckBox.new()
		check.text = str(spec.title)
		check.button_pressed = id in _selected
		check.custom_minimum_size.y = 48
		check.set_meta("subject_id",id)
		check.toggled.connect(func(v):
			if v and not id in _selected: _selected.append(id)
			elif not v: _selected.erase(id)
			_refresh())
		card.add_child(check)
		_checks[id] = check
		UI.label(card,"%s · %02d:00–%02d:00" % ["Вт, чт" if spec.days == [2,4] else "Ср, пт",int(spec.hours[0])/60,int(spec.hours[1])/60],17,UI.MUTED)
	var row := UI.row(_window.body)
	UI.label(row,"Спортивная секция",23)
	var sport := OptionButton.new()
	for id in Curriculum.SPORTS:
		sport.add_item(Curriculum.SPORTS[id])
		sport.set_item_metadata(sport.item_count-1,id)
	sport.custom_minimum_size = Vector2(300,50)
	sport.item_selected.connect(func(i): _sport = str(sport.get_item_metadata(i)))
	row.add_child(sport)
	_status = UI.label(_window.footer,"",19,UI.BLUE)
	_button = W.primary(_window.footer,"Подтвердить расписание",func(): confirmed.emit(_selected.duplicate(),_sport))
	_refresh()
	_checks.values()[0].grab_focus.call_deferred()

func _refresh() -> void:
	if _button == null: return
	_button.disabled = _selected.size() < 2 or _selected.size() > 4
	_status.text = "Выбрано %d / 4" % _selected.size()
	for id in _checks: _checks[id].disabled = _selected.size() >= 4 and not id in _selected
