extends "res://scripts/characters/puppet_view.gd"
## Live2D expression, text-paced mouth animation and short conversational gestures.
signal speech_progress(characters: int)
signal speech_finished
const BasePuppet = preload("res://scripts/characters/puppet_view.gd")
var last_load_error := ""

var reactions: Dictionary = {}
var speech_text := ""
var revealed := 0
var speaking := false
var _narrating := false
var expression := "neutral"
var characters_per_second := 38.0
var _reveal := 0.0
var _pause_left := 0.0
var _speech_clock := 0.0
var _idle_clock := 0.0
var _gesture: Dictionary = {}
var _gesture_time := 0.0
var _actor: Dictionary = {}
var _expression_defaults: Dictionary = {}
var _line_serial := 0
var frame_offset := Vector2.ZERO

func _ready() -> void:
	super._ready()
	mouse_default_cursor_shape = Control.CURSOR_ARROW

func _gui_input(_event: InputEvent) -> void:
	# Direct rig editing belongs to the workshop, not the conversation scene.
	pass

func set_framing(magnification: float, offset: Vector2) -> void:
	frame_offset = offset
	set_zoom(magnification)

func _fit() -> void:
	super._fit()
	if is_instance_valid(model): model.position += size*frame_offset

func load_reactions(path: String = "res://data/characters/conversation_reactions.json") -> bool:
	cancel_speech()
	last_load_error = ""
	var parsed: Variant = _read_object(path,"invalid_reaction_json")
	if parsed == null: return false
	if parsed.get("schema") != 1 or not parsed.get("model") is Dictionary or not parsed.get("profile") is String:
		return _reject_load("invalid_reaction_descriptor")
	var bindings: Variant = _read_object(str(parsed.profile),"invalid_binding_json")
	if bindings == null: return false
	var staged: Control = _stage_character(parsed.model,bindings)
	if staged == null: return false
	if not _validate_reactions(parsed,staged.bank):
		staged.free()
		return _reject_load("invalid_reaction_parameters")
	_commit_character(staged,parsed)
	return true

func load_character(item: Dictionary, bindings: Dictionary = {}) -> bool:
	cancel_speech()
	last_load_error = ""
	var staged: Control = _stage_character(item,bindings)
	if staged == null: return false
	var data := reactions.duplicate(true)
	if not data.is_empty():
		data.model = item.duplicate(true)
		if not _validate_reactions(data,staged.bank):
			staged.free()
			return _reject_load("incompatible_reaction_model")
	_commit_character(staged,data)
	return true

func _read_object(path: String, error: String) -> Variant:
	if path.is_empty() or not FileAccess.file_exists(path):
		_reject_load(error)
		return null
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		_reject_load(error)
		return null
	return parser.data

func _reject_load(message: String) -> bool:
	last_load_error = message
	load_failed.emit(message)
	return false

func _stage_character(item: Dictionary, bindings: Dictionary) -> Control:
	if not item.get("model") is String or not str(item.model).ends_with(".model3.json"):
		_reject_load("invalid_model_descriptor")
		return null
	var model_data: Variant = _read_object(str(item.model),"invalid_model_json")
	if model_data == null: return null
	if model_data.get("Version") != 3 or not model_data.get("FileReferences") is Dictionary:
		_reject_load("invalid_model_references")
		return null
	var references: Dictionary = model_data.FileReferences
	var directory := str(item.model).get_base_dir()
	if not references.get("Moc") is String or str(references.Moc).is_empty() or not FileAccess.file_exists(directory.path_join(str(references.Moc))):
		_reject_load("missing_model_moc")
		return null
	if not references.get("Textures") is Array or references.Textures.is_empty():
		_reject_load("missing_model_textures")
		return null
	for texture in references.Textures:
		if not texture is String or not ResourceLoader.exists(directory.path_join(str(texture))):
			_reject_load("missing_model_texture")
			return null
	if references.has("Physics"):
		if not references.Physics is String:
			_reject_load("invalid_model_physics")
			return null
		if _read_object(directory.path_join(str(references.Physics)),"invalid_model_physics") == null: return null
	if not BasePuppet.validate_profile(bindings):
		_reject_load("invalid_binding_shape")
		return null
	for entry: Dictionary in bindings.get("palette",[]):
		if not entry.get("color", "ffffff") is String or Color.from_string(str(entry.get("color","ffffff")),Color(-1,-1,-1,-1)) == Color(-1,-1,-1,-1):
			_reject_load("invalid_binding_color")
			return null
	var staged := BasePuppet.new()
	staged.visible = false
	staged.size = size
	add_child(staged)
	staged.set_process(false)
	var errors: Array[String] = []
	staged.load_failed.connect(func(message: String): errors.append(message))
	if not staged.load_character(item,bindings):
		staged.free()
		_reject_load(errors[0] if not errors.is_empty() else "native_model_load_failed")
		return null
	if not _validate_bindings(bindings,staged.bank,staged._parts):
		staged.free()
		_reject_load("invalid_binding_parameters")
		return null
	return staged

func _commit_character(staged: Control, data: Dictionary) -> void:
	# Candidate owns its native model until all reaction and binding checks have passed.
	release_grab(true)
	clip.stop()
	var previous := model
	model = staged.model
	model.reparent(self)
	bank.configure(staged.bank.definitions.values())
	bank.values = staged.bank.values
	bank.targets = staged.bank.targets
	bank.velocities = staged.bank.velocities
	bank.channels = staged.bank.channels
	for field: String in ["descriptor","profile","_parameters","_parts","_part_defaults","part_values","_meshes","_zone_meshes"]:
		set(field,staged.get(field))
	staged.free()
	if is_instance_valid(previous): previous.free()
	reactions = data.duplicate(true)
	_expression_defaults.clear()
	for pose: Dictionary in reactions.get("expressions",{}).values():
		for id: String in pose: _expression_defaults[id] = bank.definitions[id].default
	memory.reset()
	speech_text = ""
	revealed = 0
	_reveal = 0.0
	_pause_left = 0.0
	_speech_clock = 0.0
	_idle_clock = 0.0
	_clock = 0.0
	_blink_clock = 0.0
	if not reactions.is_empty():
		characters_per_second = float(reactions.characters_per_second)
		set_expression("attentive")
	_fit()
	_apply_parameters(0.016)
	model_loaded.emit(descriptor)

func _validate_bindings(data: Dictionary, parameters: RefCounted, parts: Dictionary) -> bool:
	for group: String in ["initial","expressions","poses","outfits"]:
		var poses: Array = [data.get(group,{})] if group == "initial" else data.get(group,{}).values()
		for pose: Dictionary in poses:
			for id: String in pose:
				if not _valid_parameter(id,pose[id],parameters): return false
	if data.has("blink") and not parameters.has_parameter(str(data.blink)): return false
	for axis: String in ["x","y"]:
		for id in data.get("gaze",{}).get(axis,[]):
			if not id is String or not parameters.has_parameter(id): return false
	for zone: Dictionary in data.get("zones",[]):
		for id: String in zone.get("press",{}):
			if not _valid_parameter(id,zone.press[id],parameters): return false
		for key: String in ["move_x","move_y"]:
			if not str(zone.get(key,"")).is_empty() and not parameters.has_parameter(str(zone[key])): return false
	if not data.get("parts",{}) is Dictionary: return false
	for id: String in data.get("parts",{}):
		if not parts.has(id) or not _valid_number(data.parts[id]) or float(data.parts[id])<0 or float(data.parts[id])>1: return false
	return true

func _validate_reactions(data: Dictionary, parameters: RefCounted) -> bool:
	if data.get("schema") != 1 or not data.get("expressions") is Dictionary: return false
	if not data.expressions.has("neutral") or not data.expressions.has("attentive"): return false
	if not _valid_number(data.get("characters_per_second")) or float(data.characters_per_second)<5 or float(data.characters_per_second)>150: return false
	var mouth := str(data.get("mouth",""))
	if not parameters.has_parameter(mouth): return false
	for pose in data.expressions.values():
		if not pose is Dictionary: return false
		for id: String in pose:
			if id == mouth or not _valid_parameter(id,pose[id],parameters): return false
	if not data.get("gestures") is Dictionary or not data.get("line_gestures") is Dictionary: return false
	for motion in data.gestures.values():
		if not motion is Dictionary or not parameters.has_parameter(str(motion.get("parameter",""))): return false
		for key: String in ["amplitude","duration","cycles"]:
			if not _valid_number(motion.get(key)) or float(motion[key])<=0: return false
		var limits: Dictionary = parameters.definitions[str(motion.parameter)]
		if float(motion.amplitude)>minf(float(limits.max)-float(limits.default),float(limits.default)-float(limits.min)) or float(motion.duration)>5 or float(motion.cycles)>6: return false
	for key: String in data.line_gestures:
		if not data.expressions.has(key) or not data.gestures.has(data.line_gestures[key]): return false
	if not data.get("speech") is Dictionary or not data.speech.get("expressions") is Dictionary: return false
	var speech: Dictionary = data.speech
	if not _valid_parameter(mouth,speech.get("closed"),parameters): return false
	for key: String in ["punctuation_pause","comma_pause"]:
		if not _valid_number(speech.get(key)) or float(speech[key])<0 or float(speech[key])>2: return false
	for style in [speech]+speech.expressions.values():
		if not style is Dictionary: return false
		if not _valid_number(style.get("amplitude")) or float(style.amplitude)<=0 or not _valid_parameter(mouth,float(speech.closed)+float(style.amplitude),parameters): return false
		if not _valid_number(style.get("frequency")) or float(style.frequency)<=0: return false
	for key: String in speech.expressions:
		if not data.expressions.has(key): return false
	if not data.get("idle") is Dictionary: return false
	var idle: Dictionary = data.idle
	if not parameters.has_parameter(str(idle.get("parameter",""))) or not _valid_number(idle.get("amplitude")) or not _valid_number(idle.get("period")): return false
	var limits: Dictionary = parameters.definitions[str(idle.parameter)]
	return float(idle.period)>0 and float(idle.amplitude)>=0 and float(idle.amplitude)<=minf(float(limits.max)-float(limits.default),float(limits.default)-float(limits.min))

func _valid_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _valid_parameter(id: String, value: Variant, parameters: RefCounted) -> bool:
	return parameters.has_parameter(id) and _valid_number(value) and float(value)>=float(parameters.definitions[id].min) and float(value)<=float(parameters.definitions[id].max)

func set_actor(actor: Dictionary) -> void:
	_actor = actor

func set_expression(value: String) -> bool:
	if not reactions.get("expressions",{}).has(value): return false
	expression = value
	bank.set_targets(_expression_defaults.merged(reactions.expressions[value],true),"dialogue_expression",45)
	return true

func present_line(text: String, emotion: String = "attentive", instant: bool = false, narrated: bool = false) -> bool:
	if not set_expression(emotion): return false
	cancel_speech()
	var serial := _line_serial
	_narrating = narrated
	speech_text = text
	_reveal = 0.0
	revealed = 0
	_pause_left = 0.0
	_speech_clock = 0.0
	speaking = not text.is_empty()
	speech_progress.emit(0)
	if serial != _line_serial: return true
	if instant or not is_instance_valid(model): finish_speech()
	elif speaking and not narrated: gesture(str(reactions.get("line_gestures",{}).get(emotion,"")))
	return true

func gesture(id: String) -> bool:
	_stop_gesture()
	if not reactions.get("gestures",{}).has(id): return false
	_gesture = reactions.gestures[id].duplicate(true)
	_gesture_time = 0.0
	return true

func _stop_gesture() -> void:
	_gesture = {}
	_gesture_time = 0.0
	bank.clear_channel("dialogue_gesture")

func _close_mouth() -> void:
	bank.clear_channel("speech")
	var id := str(reactions.get("mouth",""))
	if not bank.has_parameter(id): return
	var closed := float(reactions.get("speech",{}).get("closed",bank.definitions[id].default))
	bank.values[id] = closed
	bank.targets[id] = closed
	bank.velocities[id] = 0.0
	if _parameters.has(id): _parameters[id].set("value",closed)

func finish_speech() -> void:
	_close_mouth()
	_stop_gesture()
	if not speaking: return
	var serial := _line_serial
	speaking = false
	revealed = speech_text.length()
	_reveal = revealed
	speech_progress.emit(revealed)
	if serial == _line_serial: speech_finished.emit()

func cancel_speech() -> void:
	_line_serial += 1
	speaking = false
	_narrating = false
	_close_mouth()
	_stop_gesture()

func _process(delta: float) -> void:
	if not is_instance_valid(model): return
	_idle_clock += delta
	var idle: Dictionary = reactions.get("idle",{})
	bank.set_target(str(idle.get("parameter","")),sin(_idle_clock*TAU/maxf(float(idle.get("period",4.6)),0.1))*float(idle.get("amplitude",0.025)),"dialogue_idle",15,"add")
	if not _gesture.is_empty():
		_gesture_time += delta
		var duration := maxf(float(_gesture.get("duration",0.7)),0.01)
		var phase := clampf(_gesture_time/duration,0.0,1.0)
		var value := sin(phase*TAU*float(_gesture.get("cycles",1)))*sin(phase*PI)*float(_gesture.get("amplitude",0.15))
		bank.set_target(str(_gesture.get("parameter","")),value,"dialogue_gesture",55,"add")
		if phase >= 1.0:
			_gesture = {}
			bank.clear_channel("dialogue_gesture")
	if speaking:
		_step_speech(delta)
	super._process(delta)

func _step_speech(delta: float) -> void:
	var serial := _line_serial
	var previous := revealed
	_speech_clock += delta
	var budget := maxf(0.0,delta)
	var speech: Dictionary = reactions.speech
	while budget>0 and revealed<speech_text.length():
		var pause := minf(_pause_left,budget)
		_pause_left -= pause
		budget -= pause
		if budget<=0: break
		var until_next := (float(revealed+1)-_reveal)/characters_per_second
		if budget<until_next:
			_reveal += budget*characters_per_second
			break
		budget -= until_next
		revealed += 1
		_reveal = float(revealed)
		var letter := speech_text[revealed-1]
		if letter in [".","!","?","…"]: _pause_left = float(speech.get("punctuation_pause",0.14))
		elif letter in [",",":",";"]: _pause_left = float(speech.get("comma_pause",0.08))
	if revealed != previous:
		speech_progress.emit(revealed)
		if serial != _line_serial or not speaking: return
	if revealed>=speech_text.length():
		finish_speech()
		return
	if _narrating: return
	var style: Dictionary = speech.merged(speech.get("expressions",{}).get(expression,{}),true)
	var mouth := float(speech.closed)
	if revealed>0 and _pause_left<=0:
		var letter := speech_text[revealed-1].to_lower()
		if not letter in [" ","\n","\t",".",",","!","?",":",";","…"]:
			var strength := 1.0 if letter in "аеиоуыэюяaeiou" else 0.45
			mouth += float(style.amplitude)*strength*(0.18+absf(sin(_speech_clock*float(style.frequency)))*0.82)
	bank.set_target(str(reactions.mouth),mouth,"speech",70)

func _exit_tree() -> void:
	cancel_speech()
