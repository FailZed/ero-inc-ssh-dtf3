extends "res://scripts/ui/gameplay/game_window.gd"
const Social = preload("res://scripts/gameplay/social_presentation.gd")
const Names = preload("res://scripts/gameplay/presentation.gd")
const Companion = preload("res://scripts/gameplay/companion_interactions.gd")
var npc_id := ""
var puppet: Control
var _choices: VBoxContainer
var _summary: Label
var _profile: Dictionary = {}
var _session: Dictionary = {}
var _closing := false

func _ready() -> void:
	var npc: Dictionary = Gameplay.simulation.state.social.npcs.get(npc_id,{})
	if npc.is_empty(): queue_free(); return
	title = "Время вместе · " + str(npc.name)
	subtitle = "Предложите жест и дождитесь ответа. Встречу можно остановить в любой момент."
	super()
	back_requested.connect(_close_moment)
	var columns := UI.row(body,24)
	var picture := UI.column(columns,8)
	picture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The current study rig represents a female human/semi-human. Other bodies keep
	# their actual portrait and use the equivalent accessible action controls.
	var animated: bool = ClassDB.class_exists("GDCubismUserModel") and npc.gender == "female" and npc.appearance.get("morphology","human") in ["human","semi_furry"]
	if animated:
		puppet = preload("res://scripts/characters/puppet_view.gd").new()
		puppet.custom_minimum_size = Vector2(320,430)
		puppet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picture.add_child(puppet)
		_profile = JSON.parse_string(FileAccess.get_file_as_string("res://data/characters/interaction_profile.json"))
		var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/characters/study_catalog.json"))
		if not puppet.load_character(catalog.models[0],_profile):
			puppet.queue_free()
			puppet = null
		else:
			puppet.profile.zones = []
			puppet.interaction_finished.connect(_gesture_finished)
			UI.label(picture,"Временный анимированный образ",15,UI.MUTED)
	if not is_instance_valid(puppet):
		var portrait := preload("res://scripts/ui/gameplay/resident_preview.gd").new()
		portrait.custom_minimum_size = Vector2(320,430)
		portrait.set_actor(npc)
		picture.add_child(portrait)
	var details := UI.column(columns,16)
	details.custom_minimum_size.x = 340
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary = UI.label(details,"",20,UI.BLUE)
	_choices = UI.column(details,12)
	var active: Dictionary = Gameplay.simulation.state.companion.active
	if active.get("npc","") == npc_id: _session = active.duplicate(true)
	_refresh_moment()

func _refresh_moment() -> void:
	UI.clear(_choices)
	var bond := Social.bond(Gameplay.simulation,npc_id)
	_summary.text = "%s\nДоверие %d · Комфорт %d\n%s" % [bond.status_text,roundi(bond.trust),roundi(bond.comfort),Social.life(Gameplay.simulation,npc_id).emotion]
	if is_instance_valid(puppet):
		puppet.profile.zones = []
		puppet.choose_preset("expressions","Улыбка" if float(bond.comfort) >= 20 else "Нейтрально")
	if not _session.is_empty():
		var gesture := str(_session.gesture)
		UI.label(_choices,"Собеседник согласился: " + str(Companion.GESTURES[gesture].label),23)
		if is_instance_valid(puppet):
			puppet.profile.zones = _profile.zones.filter(func(zone): return zone.id in Companion.GESTURES[gesture].zones)
			UI.label(_choices,"Нажмите на выбранную область персонажа, удерживайте немного и отпустите. Esc отменяет жест.",18,UI.MUTED)
		var complete := UI.button(_choices,"Провести этот момент вместе · 5 мин",_complete_keyboard)
		complete.set_meta("companion_complete",true)
		UI.label(_choices,"Кнопка и прикосновение дают одинаковый результат.",16,UI.MUTED)
		UI.button(_choices,"Остановиться",_cancel_moment)
		_restore.call_deferred()
		return
	for gesture: String in Companion.GESTURES:
		var info: Dictionary = Gameplay.simulation.services.companion.preview(npc_id,gesture)
		var button := UI.button(_choices,str(Companion.GESTURES[gesture].label),_offer_gesture.bind(gesture))
		button.set_meta("companion_gesture",gesture)
		button.disabled = not str(info.blocked).is_empty()
		if button.disabled: UI.label(_choices,Names.error(str(info.blocked)),16,UI.MUTED)
		else: UI.label(_choices,"Предложение · 1 мин. Ответ зависит от собеседника.",16,UI.MUTED)
	_restore.call_deferred()

func _offer_gesture(gesture: String) -> void:
	var result := Gameplay.execute("companion","offer",{"id":npc_id,"gesture":gesture})
	if not result.ok: notice(Names.error(str(result.error))); return
	if result.data.accepted:
		_session = result.data.session.duplicate(true)
		notice("Можно начать. Длительность удержания не увеличивает награду.")
	else: notice("Сейчас собеседник не хочет прикосновений. Дайте ему время.")
	_refresh_moment()

func _gesture_finished(event: Dictionary) -> void:
	if _closing or _session.is_empty(): return
	if event.get("cancelled",false): _cancel_moment(); return
	if float(event.get("duration",0)) < 0.5:
		notice("Короткое касание не завершило жест. Можно повторить или остановиться.")
		return
	_finish(str(event.get("interaction","")),clampf(float(event.duration),0.5,60))

func _complete_keyboard() -> void:
	if not _session.is_empty(): _finish(str(Companion.GESTURES[_session.gesture].zones[0]),1.0)

func _finish(zone: String, duration: float) -> void:
	var before := Social.bond(Gameplay.simulation,npc_id)
	var result := Gameplay.execute("companion","finish",{"token":_session.token,"zone":zone,"duration":duration})
	if not result.ok: notice(Names.error(str(result.error))); return
	_session = {}
	if result.data.get("cancelled",false): notice("Встреча остановлена. " + Names.error(str(result.data.get("reason",""))))
	else:
		var summary := Social.change_summary(before,Social.bond(Gameplay.simulation,npc_id))
		notice("Вы побыли вместе. " + (summary if not summary.is_empty() else "Собеседник запомнил этот момент."))
	_refresh_moment()

func _cancel_moment() -> void:
	if _session.is_empty(): return
	var token: int = _session.token
	_session = {}
	if is_instance_valid(puppet): puppet.release_grab(true)
	Gameplay.execute("companion","cancel",{"token":token})
	if is_inside_tree() and not _closing:
		notice("Вы остановились. Отмена не ухудшает отношения.")
		_refresh_moment()

func _close_moment() -> void:
	_closing = true
	_cancel_moment()
	queue_free()

func _exit_tree() -> void:
	_closing = true
	if is_instance_valid(Gameplay) and Gameplay.simulation != null: _cancel_moment()
