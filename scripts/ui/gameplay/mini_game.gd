extends VBoxContainer
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const W = preload("res://scripts/ui/gameplay/game_widgets.gd")
const Art = preload("res://scripts/ui/gameplay/item_art.gd")
const Timing = preload("res://scripts/ui/gameplay/work_timing_meter.gd")
var _meter
var _target: float
var _timer_label: Label
func _ready() -> void:
	var sim = Gameplay.simulation
	var game: Dictionary = sim.state.encounters.game
	_target = float(game.target)
	UI.label(self,"Навык: %s · помощь %.0f%%" % [preload("res://scripts/gameplay/presentation.gd").title(str(game.assistance.skill)),float(game.assistance.help)*100],19,UI.BLUE)
	match str(game.type):
		"blackjack":
			var table := UI.row(self,48)
			var own := UI.column(table,16)
			own.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			UI.label(own,"Ваши карты · %d очков" % sim.services.encounters.score(game.hand),26)
			var hand := UI.row(own,12)
			for rank in game.hand: _playing_card(hand,rank)
			var other := UI.column(table,16)
			UI.label(other,"Соперник",24,UI.MUTED)
			var dealer := UI.row(other,12)
			_playing_card(dealer,game.dealer[0])
			_playing_card(dealer,0)
			if float(game.assistance.help) > 0.02:
				var bust := 0
				for rank in game.deck:
					if sim.services.encounters.score(game.hand+[rank]) > 21: bust += 1
				UI.label(self,"Оценка риска перебора при доборе: %.0f%%" % (100.0*bust/maxi(1,game.deck.size())),20,UI.BLUE)
			var actions := UI.row(self)
			W.primary(actions,"Ещё карту",_input_game.bind({"action":"hit"}))
			UI.button(actions,"Хватит",_input_game.bind({"action":"stand"}))
		"guess":
			UI.label(self,"Загадано число от 1 до 10. Осталось попыток: %d" % (int(game.limit)-int(game.attempts)),26)
			if game.has("hint"): UI.label(self,"Попробуйте больше" if game.hint == "higher" else "Попробуйте меньше",22,UI.BLUE)
			var row := UI.row(self)
			for n in range(1,11): UI.button(row,str(n),_input_game.bind({"value":n}))
		"lockpick":
			W.illustration(self,Art.texture("lockpick"),160)
			var burglary: bool = game.get("context",{}).get("kind","") == "burglary"
			UI.label(self,("Дверной замок" if burglary else "Учебный замок") + " · штифт %d из 3 · попыток %d" % [int(game.pin)+1,int(game.limit)-int(game.attempts)],26)
			for n in range(3): UI.button(self,["НИЖЕ","ПОСЕРЕДИНЕ","ВЫШЕ"][n],_input_game.bind({"value":n}))
		"strength":
			UI.label(self,"Усилие: %d / 30" % game.progress,30)
			var effort := ProgressBar.new()
			effort.max_value = 30
			effort.value = game.progress
			effort.custom_minimum_size.y = 34
			add_child(effort)
			UI.button(self,"ПРИЛОЖИТЬ УСИЛИЕ",_input_game.bind({"value":1.0}))
		"reaction","timing","pushups":
			UI.label(self,"Отжимания: нажимайте с усилием" if game.type == "pushups" else "Остановите бегунок рядом с отметкой %d%%" % (_target*100),28)
			if game.type == "pushups": _meter = ProgressBar.new()
			else:
				_meter = Timing.new()
				_meter.target = _target
				_meter.tolerance = float(game.assistance.get("window",0.1))
			_meter.custom_minimum_size.y = 52
			add_child(_meter)
			_timer_label = UI.label(self,"",23,UI.BLUE)
			UI.button(self,"НАЖАТЬ",_timed_press).grab_focus()
			set_process(true)
	UI.button(self,"ПРЕКРАТИТЬ ПОПЫТКУ · РИСК ШТРАФА" if game.get("context",{}).get("kind","") == "burglary" else "ПРЕКРАТИТЬ · СТАВКА НЕ ВЕРНЁТСЯ" if int(game.stake) > 0 else "ПРЕКРАТИТЬ ИСПЫТАНИЕ",_cancel_game)
	UI.button(self,"Меню · Esc",func():
		var node := get_parent()
		while node != null:
			if node.has_signal("menu_requested"): node.emit_signal("menu_requested"); return
			node = node.get_parent())

func _playing_card(parent: Node, rank: int) -> void:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(100,154)
	var paint := StyleBoxTexture.new()
	paint.texture = preload("res://assets/textures/ui/windows-v2/card_face.png")
	paint.set_content_margin_all(18)
	card.add_theme_stylebox_override("panel",paint)
	card.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	parent.add_child(card)
	var value := UI.label(card,"?" if rank == 0 else str({1:"Т",11:"В",12:"Д",13:"К"}.get(rank,str(rank))),42,Color("173b51"))
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _input_game(args: Dictionary) -> void:
	Gameplay.execute("encounters","game_input",args)

func _process(_delta: float) -> void:
	if _meter == null: return
	var game: Dictionary = Gameplay.simulation.state.encounters.game
	Gameplay.mini_elapsed_ms += _delta * 1000.0
	var elapsed := int(Gameplay.mini_elapsed_ms)
	var value := fposmod(float(elapsed)/1000.0,1.0)
	_meter.value = game.get("reps",0) if game.type == "pushups" else value
	if _meter is ProgressBar: _meter.max_value = game.get("required_reps",1) if game.type == "pushups" else 1
	_meter.queue_redraw()
	if game.type == "pushups": _timer_label.text = "Повторов: %d / %d" % [game.get("reps",0),game.get("required_reps",1)]
	elif game.has("duration_ms"): _timer_label.text = "Осталось %.1f сек" % maxf(0,(float(game.duration_ms)-elapsed)/1000.0)
	else: _timer_label.text = "Поймайте нужный момент."
	if game.has("duration_ms") and elapsed >= int(game.duration_ms):
		set_process(false)
		_input_game({"elapsed_ms":elapsed})

func _timed_press() -> void:
	var elapsed := int(Gameplay.mini_elapsed_ms)
	var game: Dictionary = Gameplay.simulation.state.encounters.game
	_input_game({"value":fposmod(float(elapsed)/1000.0,1.0)} if game.type == "reaction" else {"elapsed_ms":elapsed})

func _cancel_game() -> void:
	Gameplay.execute("encounters","cancel_game")
