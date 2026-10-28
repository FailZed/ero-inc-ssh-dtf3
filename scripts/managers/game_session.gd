extends Node

const GAME_CALENDAR = preload("res://scripts/mechanics/core/calendar.gd")
const TIME_MODE_REALTIME := "realtime"
const TIME_MODE_ACTIONS := "actions"

const GAME_SCENE_PATH := "res://scenes/game/game.tscn"
const MAIN_MENU_SCENE_PATH := "res://scenes/mainMenu/main_menu.tscn"
const DEFAULT_TIMELINE := "timeline"
const AUTO_SLOT_COUNT := 6
const QUICK_SLOT_COUNT := 6
const USER_SLOTS_PER_PAGE := 6
const AUTOSAVE_MIN_MINUTES := 1
const AUTOSAVE_MAX_MINUTES := 30
const AUTOSAVE_DEFAULT_MINUTES := 15
const AUTOSAVE_STEP_MINUTES := 1
const AUTOSAVE_INDEX_KEY := "autosave_slot_index"
const AUTOSAVE_INTERVAL_KEY := "autosave_interval_minutes"
const AUTOSAVE_ENABLED_KEY := "autosave_enabled"
const AUTOSAVE_TIME_ENABLED_KEY := "autosave_time_enabled"
const AUTOSAVE_BEFORE_CHOICE_KEY := "autosave_before_choice"
const TEXT_SPEED_MULTIPLIER_KEY := "text_speed_multiplier"
const INSTANT_TEXT_ENABLED_KEY := "instant_text_enabled"
const LANGUAGE_KEY := "ui_language"
const TIMELINE_TRANSLATION_CSV_PATH := "res://translation/dialogic_timeline_translation.csv"
const CHARACTER_VAR_FOLDER := "Player"
const CHARACTER_NAME_VAR := "%s.full_name" % CHARACTER_VAR_FOLDER
const WORLD_VAR_FOLDER := "World"
const CHARACTER_PROFILE_SCHEMA_VERSION := 2
const CHARACTER_BASE_STAT := 5
const CHARACTER_BONUS_POINTS := 5
const CHARACTER_MIN_STAT := 0
const CHARACTER_MAX_STAT := CHARACTER_BASE_STAT * 5 + CHARACTER_BONUS_POINTS
const CHARACTER_DEFAULT_FULL_NAME_RU := "Алекс Ривер"
const CHARACTER_DEFAULT_FULL_NAME_EN := "Alex River"
const CHARACTER_DEFAULT_GENDER := "male"
const CHARACTER_APPEARANCE_DEFAULTS := {
	"gender": "male",
	"body_type": "slim",
	"face_id": "soft",
	"hair_style": "short",
	"hair_color": "dark",
	"genital_type": "penis",
	"genital_size": "average",
	"censorship_enabled": true,
	"portrait_expression": "neutral",
	"portrait_preset": "base",
}
const CHARACTER_STAT_KEYS := ["strength", "agility", "charisma", "intellect", "luck"]
const CHARACTER_STAT_DEFAULTS := {
	"strength": CHARACTER_BASE_STAT,
	"agility": CHARACTER_BASE_STAT,
	"charisma": CHARACTER_BASE_STAT,
	"intellect": CHARACTER_BASE_STAT,
	"luck": CHARACTER_BASE_STAT,
}

const SLOT_KIND_AUTO := "auto"
const SLOT_KIND_QUICK := "quick"
const SLOT_KIND_USER := "user"
const TEXT_SPEED_MIN := 0.5
const TEXT_SPEED_MAX := 3.0
const TEXT_SPEED_DEFAULT := 1.0
const TEXT_SPEED_STEP := 0.25
const LANGUAGE_RU := "ru"
const LANGUAGE_EN := "en"
const GAME_DAY_LENGTH_KEY := "game_day_length"
const GAME_TIME_START_MINUTE := 23 * 60 + 47
const GAME_DATE_START_DAY := 12
const GAME_TIME_TICK_STEP_MINUTES := 1
const GAME_DAY_LENGTH_SHORT := "short"
const GAME_DAY_LENGTH_MEDIUM := "medium"
const GAME_DAY_LENGTH_LONG := "long"
const GAME_DAY_LENGTH_OPTIONS := [
	{"id": GAME_DAY_LENGTH_SHORT, "label_key": "settings.day_length_short", "real_minutes": 12},
	{"id": GAME_DAY_LENGTH_MEDIUM, "label_key": "settings.day_length_medium", "real_minutes": 24},
	{"id": GAME_DAY_LENGTH_LONG, "label_key": "settings.day_length_long", "real_minutes": 48},
]
const GAME_TIME_PHASES := {
	"dawn": {"start": 5 * 60, "end": 8 * 60},
	"day": {"start": 8 * 60, "end": 18 * 60},
	"evening": {"start": 18 * 60, "end": 22 * 60},
	"night": {"start": 22 * 60, "end": 5 * 60},
}
const GAME_TIME_MONTH_LABELS := ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

const LANGUAGE_OPTIONS := [
	{"code": LANGUAGE_RU, "label_key": "language.russian"},
	{"code": LANGUAGE_EN, "label_key": "language.english"},
]

const TRANSLATIONS := {
	LANGUAGE_RU: {
		"language.russian": "Русский",
		"language.english": "English",
		"menu.main": "Главное меню",
		"menu.pause": "Пауза",
		"menu.overview_start": "Выберите действие в меню слева. Aside переиспользуется для настроек, галлереи и панели сохранений.",
		"menu.overview_pause": "Продолжите игру или откройте нужный раздел через меню слева.",
		"menu.load_title": "Загрузить игру",
		"menu.load_desc": "Автосохранения и страницы пользовательских сохранений доступны ниже.",
		"menu.save_title": "Сохранить игру",
		"menu.save_desc": "Выберите слот для сохранения, удаления или перезаписи существующего состояния.",
		"menu.settings_title": "Настройки",
		"menu.settings_desc": "Эта секция использует то же Aside-меню и готова к подключению реальных параметров игры.",
		"menu.gallery_title": "Галлерея",
		"menu.gallery_desc": "Открытые воспоминания и изображения текущего прохождения.",
		"button.new_game": "Новая игра",
		"button.continue": "Продолжить",
		"button.load_game": "Загрузить игру",
		"button.save_game": "Сохранить игру",
		"button.settings": "Настройки",
		"button.gallery": "Галлерея",
		"button.return_to_main_menu": "В главное меню",
		"button.exit": "Выход",
		"button.load": "Загрузить",
		"button.save": "Сохранить",
		"button.delete": "Удалить",
		"button.overwrite": "Перезаписать",
		"button.auto": "Auto",
		"button.manual": "Manual",
		"button.open_logs": "Открыть логи",
		"button.hide_window": "Скрыть окно",
		"button.show_window": "Показать окно",
		"button.menu": "Меню",
		"button.dialog_save": "Сохранение",
		"button.dialog_load": "Загрузка",
		"settings.autosaves": "Автосохранения",
		"settings.autosave_enabled": "Включить автосохранения",
		"settings.autosave_time": "Автосохранение по времени",
		"settings.autosave_choice": "Автосохранение перед выбором",
		"settings.autosave_interval": "Интервал автосохранения",
		"settings.autosave_hint": "Диапазон: от 1 до 30 минут. Значение по умолчанию: 15 минут.",
		"settings.text": "Текст",
		"settings.instant_text": "Моментальный текст",
		"settings.instant_text_hint": "Когда включено, вся реплика появляется сразу без печатающего эффекта.",
		"settings.text_speed": "Скорость текста",
		"settings.text_speed_hint": "Ниже 100% текст идет медленнее, выше 100% быстрее.",
		"settings.language": "Язык",
		"settings.language_hint": "Переключает язык системного интерфейса между русским и английским.",
		"settings.time": "Время",
		"settings.day_length": "Длина игрового дня",
		"settings.day_length_hint": "Определяет, сколько реальных минут длится полный игровой день.",
		"settings.day_length_short": "Короткий",
		"settings.day_length_medium": "Средний",
		"settings.day_length_long": "Длинный",
		"load.subtitle": "Auto и manual страницы сохранений.",
		"load.empty": "Для выбранного раздела пока нет сохранений.",
		"load.page": "Страница {index}",
		"load.page_fallback": "Страница",
		"slot.empty": "Пустой слот",
		"slot.no_data": "Нет данных",
		"slot.auto_title": "Auto Save {index}",
		"slot.quick_title": "Quick Save {index}",
		"slot.user_title": "Страница {page} Слот {slot}",
		"time.minutes": "{value} мин",
		"feedback.scene_missing": "Сцена игры пока не найдена по пути {path}.",
		"feedback.new_game_failed": "Не удалось запустить новую игру: {error}.",
		"feedback.no_continue": "Нет доступного сохранения для продолжения.",
		"feedback.return_failed": "Не удалось вернуться в главное меню: {error}.",
		"feedback.save_updated": "Сохранение обновлено: {slot}.",
		"feedback.save_failed": "Не удалось сохранить слот {slot}: {error}.",
		"feedback.load_failed": "Не удалось загрузить слот {slot}: {error}.",
		"feedback.delete_ok": "Слот {slot} удален.",
		"feedback.delete_failed": "Не удалось удалить слот {slot}: {error}.",
		"feedback.overwrite_ok": "Слот {slot} перезаписан.",
		"feedback.overwrite_failed": "Не удалось перезаписать слот {slot}: {error}.",
		"gallery.text": "Раздел галлереи подключен как отдельная правая панель. Слева остается тот же Aside Menu, что упрощает повторное использование навигации.",
		"overview.text": "[b]Структура Main Menu[/b]\n\n- Слева: переиспользуемый Aside Menu.\n- Справа: активный раздел, который можно переключать без смены layout.\n- Панель сохранений поддерживает режимы Load и Save.",
		"character.short_name": "ГГ",
		"character.creation_title": "Создание персонажа",
		"character.creation_description": "Введи полное имя ГГ и распредели характеристики. Базовое значение каждого параметра равно 5.",
		"character.creation_step_appearance": "Шаг 1 из 3: внешность",
		"character.creation_step_identity": "Шаг 2 из 3: имя и характеристики",
		"character.creation_step_confirm": "Шаг 3 из 3: подтверждение",
		"character.creation_appearance_description": "Выбери пол, внешность и режим цензуры.",
		"character.creation_identity_description": "Введи имя персонажа и распредели свободные очки характеристик.",
		"character.creation_confirm_description": "Проверь итоговую конфигурацию. При необходимости можно вернуться на предыдущий шаг.",
		"character.creation_name_label": "Полное имя ГГ",
		"character.creation_name_placeholder": "Например, Алекс Ривер",
		"character.creation_points": "Свободные очки:",
		"character.creation_back": "Назад",
		"character.creation_next": "Далее",
		"character.creation_confirm": "Подтвердить персонажа",
		"character.creation_preview": "Превью",
		"character.creation_appearance_section": "Внешность",
		"character.creation_identity_section": "Личность и характеристики",
		"character.creation_gender": "Пол",
		"character.creation_body_type": "Тип тела",
		"character.creation_face": "Лицо",
		"character.creation_hair_style": "Прическа",
		"character.creation_hair_color": "Цвет волос",
		"character.creation_genital_type": "Тип гениталий",
		"character.creation_genital_size": "Размер гениталий",
		"character.creation_censorship": "Цензура",
		"character.creation_summary": "Итоговая конфигурация",
		"character.creation_censored_on": "Цензура включена",
		"character.creation_censored_off": "Цензура выключена",
		"character.option.gender.male": "Мужской",
		"character.option.gender.female": "Женский",
		"character.option.body_type.slim": "Стройное",
		"character.option.body_type.athletic": "Атлетичное",
		"character.option.face.soft": "Мягкие черты",
		"character.option.face.sharp": "Резкие черты",
		"character.option.hair_style.short": "Короткая",
		"character.option.hair_style.long": "Длинная",
		"character.option.hair_color.dark": "Темные",
		"character.option.hair_color.light": "Светлые",
		"character.option.genital_type.penis": "Пенис",
		"character.option.genital_type.vulva": "Вульва",
		"character.option.genital_size.small": "Маленький",
		"character.option.genital_size.average": "Средний",
		"character.option.genital_size.full": "Крупный",
		"character.stat.strength": "Сила",
		"character.stat.agility": "Ловкость",
		"character.stat.charisma": "Харизма",
		"character.stat.intellect": "Интеллект",
		"character.stat.luck": "Удача",
	},
	LANGUAGE_EN: {
		"language.russian": "Russian",
		"language.english": "English",
		"menu.main": "Main Menu",
		"menu.pause": "Pause",
		"menu.overview_start": "Choose an action from the menu on the left. Aside is reused for settings, gallery, and save panels.",
		"menu.overview_pause": "Resume the game or open the needed section from the menu on the left.",
		"menu.load_title": "Load Game",
		"menu.load_desc": "Autosaves and user save pages are available below.",
		"menu.save_title": "Save Game",
		"menu.save_desc": "Choose a slot to save, delete, or overwrite an existing state.",
		"menu.settings_title": "Settings",
		"menu.settings_desc": "This section reuses the same Aside menu and is ready for real game settings.",
		"menu.gallery_title": "Gallery",
		"menu.gallery_desc": "Unlocked memories and images from the current playthrough.",
		"button.new_game": "New Game",
		"button.continue": "Continue",
		"button.load_game": "Load Game",
		"button.save_game": "Save Game",
		"button.settings": "Settings",
		"button.gallery": "Gallery",
		"button.return_to_main_menu": "Main Menu",
		"button.exit": "Exit",
		"button.load": "Load",
		"button.save": "Save",
		"button.delete": "Delete",
		"button.overwrite": "Overwrite",
		"button.auto": "Auto",
		"button.manual": "Manual",
		"button.open_logs": "Open Logs",
		"button.hide_window": "Hide Window",
		"button.show_window": "Show Window",
		"button.menu": "Menu",
		"button.dialog_save": "Save",
		"button.dialog_load": "Load",
		"settings.autosaves": "Autosaves",
		"settings.autosave_enabled": "Enable autosaves",
		"settings.autosave_time": "Time-based autosave",
		"settings.autosave_choice": "Autosave before choices",
		"settings.autosave_interval": "Autosave interval",
		"settings.autosave_hint": "Range: 1 to 30 minutes. Default value: 15 minutes.",
		"settings.text": "Text",
		"settings.instant_text": "Instant text",
		"settings.instant_text_hint": "When enabled, the whole line appears immediately without the typing effect.",
		"settings.text_speed": "Text speed",
		"settings.text_speed_hint": "Below 100% the text is slower, above 100% it is faster.",
		"settings.language": "Language",
		"settings.language_hint": "Switches the system interface language between Russian and English.",
		"settings.time": "Time",
		"settings.day_length": "Game day length",
		"settings.day_length_hint": "Controls how many real minutes a full in-game day takes.",
		"settings.day_length_short": "Short",
		"settings.day_length_medium": "Medium",
		"settings.day_length_long": "Long",
		"load.subtitle": "Auto and manual save pages.",
		"load.empty": "There are no saves in this section yet.",
		"load.page": "Page {index}",
		"load.page_fallback": "Page",
		"slot.empty": "Empty slot",
		"slot.no_data": "No data",
		"slot.auto_title": "Auto Save {index}",
		"slot.quick_title": "Quick Save {index}",
		"slot.user_title": "Page {page} Slot {slot}",
		"time.minutes": "{value} min",
		"feedback.scene_missing": "Game scene not found at {path}.",
		"feedback.new_game_failed": "Failed to start a new game: {error}.",
		"feedback.no_continue": "No save available to continue.",
		"feedback.return_failed": "Failed to return to the main menu: {error}.",
		"feedback.save_updated": "Save updated: {slot}.",
		"feedback.save_failed": "Failed to save slot {slot}: {error}.",
		"feedback.load_failed": "Failed to load slot {slot}: {error}.",
		"feedback.delete_ok": "Slot {slot} deleted.",
		"feedback.delete_failed": "Failed to delete slot {slot}: {error}.",
		"feedback.overwrite_ok": "Slot {slot} overwritten.",
		"feedback.overwrite_failed": "Failed to overwrite slot {slot}: {error}.",
		"gallery.text": "The gallery section is connected as a separate right-side panel. The same Aside menu stays on the left for easier reuse.",
		"overview.text": "[b]Main Menu Structure[/b]\n\n- Left: a reusable Aside Menu.\n- Right: the active section that can be switched without changing the layout.\n- The save panel supports both Load and Save modes.",
		"character.short_name": "GG",
		"character.creation_title": "Character Creation",
		"character.creation_description": "Enter the protagonist's full name and distribute attributes. Every stat starts at 5.",
		"character.creation_step_appearance": "Step 1 of 3: appearance",
		"character.creation_step_identity": "Step 2 of 3: name and stats",
		"character.creation_step_confirm": "Step 3 of 3: confirmation",
		"character.creation_appearance_description": "Choose gender, appearance, and censorship mode.",
		"character.creation_identity_description": "Enter the character name and distribute free stat points.",
		"character.creation_confirm_description": "Review the final configuration. You can go back to any previous step if needed.",
		"character.creation_name_label": "GG full name",
		"character.creation_name_placeholder": "For example, Alex River",
		"character.creation_points": "Free points:",
		"character.creation_back": "Back",
		"character.creation_next": "Next",
		"character.creation_confirm": "Confirm character",
		"character.creation_preview": "Preview",
		"character.creation_appearance_section": "Appearance",
		"character.creation_identity_section": "Identity and stats",
		"character.creation_gender": "Gender",
		"character.creation_body_type": "Body Type",
		"character.creation_face": "Face",
		"character.creation_hair_style": "Hair Style",
		"character.creation_hair_color": "Hair Color",
		"character.creation_genital_type": "Genital Type",
		"character.creation_genital_size": "Genital Size",
		"character.creation_censorship": "Censorship",
		"character.creation_summary": "Current build",
		"character.creation_censored_on": "Censorship enabled",
		"character.creation_censored_off": "Censorship disabled",
		"character.option.gender.male": "Male",
		"character.option.gender.female": "Female",
		"character.option.body_type.slim": "Slim",
		"character.option.body_type.athletic": "Athletic",
		"character.option.face.soft": "Soft",
		"character.option.face.sharp": "Sharp",
		"character.option.hair_style.short": "Short",
		"character.option.hair_style.long": "Long",
		"character.option.hair_color.dark": "Dark",
		"character.option.hair_color.light": "Light",
		"character.option.genital_type.penis": "Penis",
		"character.option.genital_type.vulva": "Vulva",
		"character.option.genital_size.small": "Small",
		"character.option.genital_size.average": "Average",
		"character.option.genital_size.full": "Full",
		"character.stat.strength": "Strength",
		"character.stat.agility": "Agility",
		"character.stat.charisma": "Charisma",
		"character.stat.intellect": "Intellect",
		"character.stat.luck": "Luck",
	},
}

signal save_slots_changed
signal autosave_interval_changed(minutes: int)
signal autosave_settings_changed
signal text_settings_changed
signal language_changed
signal player_profile_changed(profile: Dictionary)
signal game_time_changed(snapshot: Dictionary)
signal game_time_settings_changed
signal game_time_advanced(previous_minutes: int, current_minutes: int)
signal game_time_reset(snapshot: Dictionary)
signal game_hour_changed(snapshot: Dictionary)
signal game_day_changed(snapshot: Dictionary)
signal game_month_changed(snapshot: Dictionary)

var _pending_load_slot := ""
var last_load_error := ""
var _autosave_timer := Timer.new()
var _autosave_runtime_paused := true
var _choice_autosave_pending := false
var _autosave_progress_dirty := false
var _runtime_translations: Array[Translation] = []
var _game_time_total_minutes := GAME_TIME_START_MINUTE
var _game_time_accumulator := 0.0
var _game_time_mode := TIME_MODE_REALTIME
var _game_time_locks: Dictionary = {}
var player_full_name := CHARACTER_DEFAULT_FULL_NAME_RU
var player_strength := CHARACTER_BASE_STAT
var player_agility := CHARACTER_BASE_STAT
var player_charisma := CHARACTER_BASE_STAT
var player_intellect := CHARACTER_BASE_STAT
var player_luck := CHARACTER_BASE_STAT
var player_unspent_points := CHARACTER_BONUS_POINTS
var player_profile_schema_version := CHARACTER_PROFILE_SCHEMA_VERSION
var player_appearance: Dictionary = CHARACTER_APPEARANCE_DEFAULTS.duplicate(true)
var player_character_created := false


func _ready() -> void:
	Dialogic.Save.autosave_enabled = false
	_autosave_timer.name = "GameSessionAutosaveTimer"
	_autosave_timer.one_shot = false
	_autosave_timer.process_callback = Timer.TIMER_PROCESS_IDLE
	_autosave_timer.timeout.connect(_on_autosave_timer_timeout)
	add_child(_autosave_timer)
	if Dialogic.has_subsystem("Choices"):
		Dialogic.Choices.question_shown.connect(_on_question_shown)
		Dialogic.Choices.choice_selected.connect(_on_choice_selected)
	if Dialogic.has_subsystem("Text"):
		Dialogic.Text.about_to_show_text.connect(_on_about_to_show_text)
	_register_runtime_translations()
	_apply_autosave_interval(get_autosave_interval_minutes())
	_apply_text_settings()
	_apply_runtime_language()
	_ensure_character_profile_initialized()
	_sync_game_time_from_dialogic()
	_emit_game_time_changed()


func _process(delta: float) -> void:
	if not is_game_time_runtime_active() or get_tree().paused or is_game_time_blocked() or _game_time_mode != TIME_MODE_REALTIME:
		return

	_game_time_accumulator += delta * get_game_minutes_per_real_second()
	var whole_minutes := int(floor(_game_time_accumulator))
	if whole_minutes < GAME_TIME_TICK_STEP_MINUTES:
		return

	_game_time_accumulator -= float(whole_minutes)
	advance_game_time(whole_minutes)


func start_new_game() -> Error:
	last_load_error = ""
	_pending_load_slot = ""
	_reset_autosave_progress()
	Dialogic.clear(DialogicGameHandler.ClearFlags.FULL_CLEAR)
	reset_game_time()
	reset_character_profile()
	return get_tree().change_scene_to_file(GAME_SCENE_PATH)


func return_to_main_menu() -> Error:
	_pending_load_slot = ""
	_reset_autosave_progress()
	if Dialogic != null:
		Dialogic.end_timeline(true)
		if Dialogic.has_subsystem("Styles"):
			var layout: Node = Dialogic.Styles.get_layout_node()
			if layout != null and is_instance_valid(layout):
				if layout.get_parent() != null:
					layout.get_parent().remove_child(layout)
				layout.queue_free()
	Dialogic.clear(DialogicGameHandler.ClearFlags.FULL_CLEAR)
	return get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


func continue_latest_game() -> Error:
	var latest_slot: String = Dialogic.Save.get_latest_slot()
	if latest_slot.is_empty():
		return ERR_FILE_NOT_FOUND

	return request_load_slot(latest_slot)


func request_load_slot(slot_id: String) -> Error:
	if not has_slot(slot_id):
		return ERR_FILE_NOT_FOUND

	_pending_load_slot = slot_id

	if is_game_scene_active():
		return apply_pending_load()

	return get_tree().change_scene_to_file(GAME_SCENE_PATH)


func apply_pending_load() -> Error:
	if _pending_load_slot.is_empty():
		return ERR_INVALID_PARAMETER

	var slot_id := _pending_load_slot
	_pending_load_slot = ""
	last_load_error = ""
	var load_error: Error = Dialogic.Save.load(slot_id)
	if load_error == OK:
		_sync_character_profile_from_dialogic()
		_sync_game_time_from_dialogic()
		if _has_gameplay_restore_error():
			load_error = ERR_INVALID_DATA
			last_load_error = load("res://scripts/gameplay/presentation.gd").error(str(get_node("/root/Gameplay").restore_error))
		else:
			_reset_autosave_progress()
	if load_error != OK:
		if last_load_error.is_empty(): last_load_error = localize("feedback.load_failed", {"slot":slot_id,"error":error_string(load_error)})
		pause_autosave_runtime()
		return_to_main_menu.call_deferred()
	return load_error


func has_pending_load() -> bool:
	return not _pending_load_slot.is_empty()


func has_continue_slot() -> bool:
	return not Dialogic.Save.get_latest_slot().is_empty()


func has_slot(slot_id: String) -> bool:
	return Dialogic.Save.has_slot(slot_id)


func is_game_scene_active() -> bool:
	var current_scene := get_tree().current_scene
	return current_scene != null and current_scene.scene_file_path == GAME_SCENE_PATH


func is_game_time_runtime_active() -> bool:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return false

	var scene_path := current_scene.scene_file_path
	return scene_path == GAME_SCENE_PATH or scene_path.begins_with("res://scenes/hub/")


func pause_autosave_runtime() -> void:
	_autosave_runtime_paused = true
	_autosave_timer.stop()


func resume_autosave_runtime() -> void:
	_autosave_runtime_paused = false
	_apply_autosave_interval(get_autosave_interval_minutes())


func capture_thumbnail() -> void:
	if DisplayServer.get_name() == "headless":
		return

	var save_system: Node = Dialogic.Save
	if save_system == null:
		return

	var viewport: Viewport = save_system.get_viewport()
	if viewport == null:
		return

	var viewport_texture: ViewportTexture = viewport.get_texture()
	if viewport_texture == null:
		return

	var image: Image = viewport_texture.get_image()
	if image == null:
		return

	save_system.latest_thumbnail = image


func _has_gameplay_restore_error() -> bool:
	var gameplay := get_node_or_null("/root/Gameplay")
	return gameplay != null and not str(gameplay.get("restore_error")).is_empty()


func save_slot(slot_id: String) -> Error:
	if _has_gameplay_restore_error(): return ERR_INVALID_DATA
	var slot_ref := _decode_slot_reference(slot_id)
	if slot_ref.is_empty():
		return ERR_INVALID_PARAMETER
	if str(slot_ref.get("kind", "")) == SLOT_KIND_AUTO:
		return ERR_UNAUTHORIZED

	var thumbnail_mode: int = Dialogic.Save.ThumbnailMode.TAKE_AND_STORE
	if Dialogic.Save.latest_thumbnail != null:
		thumbnail_mode = Dialogic.Save.ThumbnailMode.STORE_ONLY

	var save_info := {
		"title": _build_slot_title(slot_ref),
		"saved_at_text": _format_now(),
		"kind": slot_ref["kind"],
		"page_index": slot_ref["page_index"],
		"slot_index": slot_ref["slot_index"],
	}

	var save_error: Error = Dialogic.Save.save(slot_id, false, thumbnail_mode, save_info)
	if save_error == OK:
		save_slots_changed.emit()

	return save_error


func delete_slot(slot_id: String) -> Error:
	if not has_slot(slot_id):
		return ERR_FILE_NOT_FOUND
	if slot_id.begins_with("auto_"):
		return ERR_UNAUTHORIZED

	var delete_error: Error = Dialogic.Save.delete_slot(slot_id)
	if delete_error == OK:
		save_slots_changed.emit()

	return delete_error


func build_slot_collections(is_save_mode: bool = false) -> Dictionary:
	var auto_entries: Array = []
	for slot_index in range(AUTO_SLOT_COUNT):
		auto_entries.append(_build_slot_entry(_auto_slot_id(slot_index), SLOT_KIND_AUTO, 0, slot_index, is_save_mode))

	# Quick slots are disabled in UI for now, but the helpers remain in code
	# so the section can be restored later without rebuilding slot ids/history.
	var quick_entries: Array = []
	# for slot_index in range(QUICK_SLOT_COUNT):
	# 	quick_entries.append(_build_slot_entry(_quick_slot_id(slot_index), SLOT_KIND_QUICK, 0, slot_index, is_save_mode))

	var user_page_count := _get_user_page_count()
	var user_pages: Array = []
	for page_index in range(user_page_count):
		var page_entries: Array = []
		for slot_index in range(USER_SLOTS_PER_PAGE):
			page_entries.append(_build_slot_entry(_user_slot_id(page_index, slot_index), SLOT_KIND_USER, page_index, slot_index, is_save_mode))
		user_pages.append(page_entries)

	return {
		"auto_entries": auto_entries,
		"quick_entries": quick_entries,
		"user_pages": user_pages,
	}


func _build_slot_entry(slot_id: String, kind: String, page_index: int, slot_index: int, is_save_mode: bool) -> Dictionary:
	var exists := has_slot(slot_id)
	var slot_ref := {
		"id": slot_id,
		"kind": kind,
		"page_index": page_index,
		"slot_index": slot_index,
	}
	var slot_info: Dictionary = Dialogic.Save.get_slot_info(slot_id) if exists else {}
	var is_auto_slot := kind == SLOT_KIND_AUTO
	var can_primary_action := (not is_auto_slot and is_save_mode and not exists) or (exists and not is_save_mode)
	var localized_title := _build_slot_title(slot_ref)
	if exists and kind == SLOT_KIND_USER:
		localized_title = str(slot_info.get("title", localized_title))

	return {
		"id": slot_id,
		"title": localized_title,
		"saved_at_text": str(slot_info.get("saved_at_text", "")),
		"preview_texture": Dialogic.Save.get_slot_thumbnail(slot_id) if exists else null,
		"preview_color": _preview_color(kind, exists),
		"is_empty": not exists,
		"kind": kind,
		"page_index": page_index,
		"slot_index": slot_index,
		"can_primary_action": can_primary_action,
		"can_delete": exists and not is_auto_slot,
		"can_overwrite": exists and not is_auto_slot,
	}


func get_autosave_interval_minutes() -> int:
	var stored := int(Dialogic.Save.get_global_info(AUTOSAVE_INTERVAL_KEY, AUTOSAVE_DEFAULT_MINUTES))
	return _normalize_autosave_minutes(stored)


func set_autosave_interval_minutes(minutes: int) -> void:
	var normalized := _normalize_autosave_minutes(minutes)
	Dialogic.Save.set_global_info(AUTOSAVE_INTERVAL_KEY, normalized)
	_apply_autosave_interval(normalized)
	autosave_interval_changed.emit(normalized)


func get_autosave_interval_bounds() -> Dictionary:
	return {
		"min": AUTOSAVE_MIN_MINUTES,
		"max": AUTOSAVE_MAX_MINUTES,
		"step": AUTOSAVE_STEP_MINUTES,
	}


func get_text_speed_multiplier() -> float:
	var stored := float(Dialogic.Save.get_global_info(TEXT_SPEED_MULTIPLIER_KEY, TEXT_SPEED_DEFAULT))
	return _normalize_text_speed_multiplier(stored)


func set_text_speed_multiplier(multiplier: float) -> void:
	var normalized := _normalize_text_speed_multiplier(multiplier)
	Dialogic.Save.set_global_info(TEXT_SPEED_MULTIPLIER_KEY, normalized)
	_apply_text_settings()
	text_settings_changed.emit()


func get_text_speed_bounds() -> Dictionary:
	return {
		"min": TEXT_SPEED_MIN,
		"max": TEXT_SPEED_MAX,
		"step": TEXT_SPEED_STEP,
	}


func get_language_code() -> String:
	var stored := str(Dialogic.Save.get_global_info(LANGUAGE_KEY, LANGUAGE_RU))
	return stored if TRANSLATIONS.has(stored) else LANGUAGE_RU


func set_language_code(language_code: String) -> void:
	var previous_language := get_language_code()
	var normalized := language_code if TRANSLATIONS.has(language_code) else LANGUAGE_RU
	if normalized == previous_language:
		return
	Dialogic.Save.set_global_info(LANGUAGE_KEY, normalized)
	_update_default_character_name_for_language(previous_language, normalized)
	_apply_runtime_language()
	save_slots_changed.emit()
	language_changed.emit()


func get_language_options() -> Array:
	return LANGUAGE_OPTIONS.duplicate(true)


func get_game_day_length_options() -> Array:
	return GAME_DAY_LENGTH_OPTIONS.duplicate(true)


func get_game_day_length_id() -> String:
	var stored := str(Dialogic.Save.get_global_info(GAME_DAY_LENGTH_KEY, GAME_DAY_LENGTH_MEDIUM))
	for option in GAME_DAY_LENGTH_OPTIONS:
		if str(option.get("id", "")) == stored:
			return stored
	return GAME_DAY_LENGTH_MEDIUM


func set_game_day_length_id(day_length_id: String) -> void:
	var normalized := GAME_DAY_LENGTH_MEDIUM
	for option in GAME_DAY_LENGTH_OPTIONS:
		if str(option.get("id", "")) == day_length_id:
			normalized = day_length_id
			break
	if normalized == get_game_day_length_id():
		return
	Dialogic.Save.set_global_info(GAME_DAY_LENGTH_KEY, normalized)
	game_time_settings_changed.emit()
	_emit_game_time_changed()


func get_game_minutes_per_real_second() -> float:
	var real_minutes := 24
	var day_length_id := get_game_day_length_id()
	for option in GAME_DAY_LENGTH_OPTIONS:
		if str(option.get("id", "")) == day_length_id:
			real_minutes = int(option.get("real_minutes", real_minutes))
			break
	return float(24 * 60) / float(real_minutes * 60)


func reset_game_time() -> void:
	_game_time_total_minutes = GAME_TIME_START_MINUTE
	_game_time_accumulator = 0.0
	_game_time_locks.clear()
	_sync_game_time_to_dialogic()
	_emit_game_time_changed()
	game_time_reset.emit(get_game_time_snapshot())


func advance_game_time(minutes: int) -> void:
	if minutes <= 0:
		return
	var previous_minutes := _game_time_total_minutes
	_game_time_total_minutes += minutes
	_sync_game_time_to_dialogic()
	_emit_game_time_changed()
	game_time_advanced.emit(previous_minutes, _game_time_total_minutes)
	for hour_index in range(int(previous_minutes / 60) + 1, int(_game_time_total_minutes / 60) + 1):
		var boundary := GAME_CALENDAR.snapshot(hour_index * 60)
		game_hour_changed.emit(boundary)
		if hour_index % 24 == 0:
			game_day_changed.emit(boundary)
			if int(boundary.day) == 1:
				game_month_changed.emit(boundary)


func set_game_time_total_minutes(total_minutes: int) -> void:
	# Explicit restoration, never used to simulate elapsed time.
	_game_time_total_minutes = maxi(0, total_minutes)
	_game_time_accumulator = 0.0
	_sync_game_time_to_dialogic()
	_emit_game_time_changed()
	game_time_reset.emit(get_game_time_snapshot())


func set_game_time_mode(mode: String) -> bool:
	if mode not in [TIME_MODE_REALTIME, TIME_MODE_ACTIONS]:
		return false
	_game_time_mode = mode
	_game_time_accumulator = 0.0
	return true


func get_game_time_mode() -> String:
	return _game_time_mode


func acquire_game_time_lock(owner_id: StringName) -> void:
	_game_time_locks[owner_id] = true


func release_game_time_lock(owner_id: StringName) -> void:
	_game_time_locks.erase(owner_id)


func is_game_time_blocked() -> bool:
	return not _game_time_locks.is_empty()


func get_game_time_snapshot() -> Dictionary:
	var snapshot := GAME_CALENDAR.snapshot(_game_time_total_minutes)
	snapshot["capabilities"] = get_time_capabilities(str(snapshot.phase))
	return snapshot


func get_time_capabilities(phase: String = "") -> Dictionary:
	var normalized_phase := phase if not phase.is_empty() else str(get_game_time_snapshot().get("phase", "night"))
	match normalized_phase:
		"dawn":
			return {"exploration": true, "social": false, "stealth": true, "rest": false, "warehouse_gate": false}
		"day":
			return {"exploration": true, "social": true, "stealth": false, "rest": false, "warehouse_gate": false}
		"evening":
			return {"exploration": true, "social": true, "stealth": true, "rest": false, "warehouse_gate": true}
		_:
			return {"exploration": false, "social": false, "stealth": true, "rest": true, "warehouse_gate": true}


func is_time_capability_available(capability: String) -> bool:
	var capabilities: Dictionary = get_game_time_snapshot().get("capabilities", {})
	return bool(capabilities.get(capability, false))


func get_character_profile() -> Dictionary:
	return {
		"schema_version": player_profile_schema_version,
		"identity": {
			"full_name": player_full_name,
			"short_name": get_protagonist_short_name(),
		},
		"appearance": player_appearance.duplicate(true),
		"rules": {
			"base_stat": CHARACTER_BASE_STAT,
			"bonus_points": CHARACTER_BONUS_POINTS,
			"min_stat": CHARACTER_MIN_STAT,
			"max_stat": CHARACTER_MAX_STAT,
		},
		"meta": {
			"is_character_created": player_character_created,
		},
		"full_name": player_full_name,
		"stats": {
			"strength": player_strength,
			"agility": player_agility,
			"charisma": player_charisma,
			"intellect": player_intellect,
			"luck": player_luck,
		},
		"unspent_points": player_unspent_points,
		"base_stat": CHARACTER_BASE_STAT,
		"bonus_points": CHARACTER_BONUS_POINTS,
		"min_stat": CHARACTER_MIN_STAT,
		"max_stat": CHARACTER_MAX_STAT,
	}


func get_default_character_full_name(language_code: String = "") -> String:
	var normalized_language := language_code if TRANSLATIONS.has(language_code) else get_language_code()
	if normalized_language == LANGUAGE_EN:
		return CHARACTER_DEFAULT_FULL_NAME_EN
	return CHARACTER_DEFAULT_FULL_NAME_RU


func get_protagonist_short_name() -> String:
	return localize("character.short_name")


func get_character_stat_labels() -> Dictionary:
	return {
		"strength": localize("character.stat.strength"),
		"agility": localize("character.stat.agility"),
		"charisma": localize("character.stat.charisma"),
		"intellect": localize("character.stat.intellect"),
		"luck": localize("character.stat.luck"),
	}


func get_character_creation_texts() -> Dictionary:
	return {
		"title": localize("character.creation_title"),
		"description": localize("character.creation_description"),
		"step_appearance": localize("character.creation_step_appearance"),
		"step_identity": localize("character.creation_step_identity"),
		"step_confirm": localize("character.creation_step_confirm"),
		"appearance_description": localize("character.creation_appearance_description"),
		"identity_description": localize("character.creation_identity_description"),
		"confirm_description": localize("character.creation_confirm_description"),
		"preview_title": localize("character.creation_preview"),
		"appearance_section_title": localize("character.creation_appearance_section"),
		"identity_section_title": localize("character.creation_identity_section"),
		"name_label": localize("character.creation_name_label"),
		"name_placeholder": localize("character.creation_name_placeholder"),
		"points_label": localize("character.creation_points"),
		"back_label": localize("character.creation_back"),
		"next_label": localize("character.creation_next"),
		"confirm_label": localize("character.creation_confirm"),
		"summary_label": localize("character.creation_summary"),
		"censorship_on": localize("character.creation_censored_on"),
		"censorship_off": localize("character.creation_censored_off"),
	}


func get_character_appearance_options(profile: Dictionary = {}) -> Dictionary:
	var appearance := (profile.get("appearance", {}) as Dictionary) if not profile.is_empty() else player_appearance
	var gender := str(appearance.get("gender", CHARACTER_DEFAULT_GENDER))
	var genital_type_options := [
		{"id": "penis", "label": localize("character.option.genital_type.penis")}
	] if gender == "male" else [
		{"id": "vulva", "label": localize("character.option.genital_type.vulva")}
	]
	var genital_size_options := [
		{"id": "small", "label": localize("character.option.genital_size.small")},
		{"id": "average", "label": localize("character.option.genital_size.average")},
	] if gender == "male" else [
		{"id": "small", "label": localize("character.option.genital_size.small")},
		{"id": "full", "label": localize("character.option.genital_size.full")},
	]

	return {
		"gender": {
			"label": localize("character.creation_gender"),
			"options": [
				{"id": "male", "label": localize("character.option.gender.male")},
				{"id": "female", "label": localize("character.option.gender.female")},
			],
		},
		"body_type": {
			"label": localize("character.creation_body_type"),
			"options": [
				{"id": "slim", "label": localize("character.option.body_type.slim")},
				{"id": "athletic", "label": localize("character.option.body_type.athletic")},
			],
		},
		"face_id": {
			"label": localize("character.creation_face"),
			"options": [
				{"id": "soft", "label": localize("character.option.face.soft")},
				{"id": "sharp", "label": localize("character.option.face.sharp")},
			],
		},
		"hair_style": {
			"label": localize("character.creation_hair_style"),
			"options": [
				{"id": "short", "label": localize("character.option.hair_style.short")},
				{"id": "long", "label": localize("character.option.hair_style.long")},
			],
		},
		"hair_color": {
			"label": localize("character.creation_hair_color"),
			"options": [
				{"id": "dark", "label": localize("character.option.hair_color.dark")},
				{"id": "light", "label": localize("character.option.hair_color.light")},
			],
		},
		"genital_type": {
			"label": localize("character.creation_genital_type"),
			"options": genital_type_options,
		},
		"genital_size": {
			"label": localize("character.creation_genital_size"),
			"options": genital_size_options,
		},
		"censorship_enabled": {
			"label": localize("character.creation_censorship"),
		},
	}


func reset_character_profile() -> void:
	player_profile_schema_version = CHARACTER_PROFILE_SCHEMA_VERSION
	player_full_name = ""
	player_strength = CHARACTER_BASE_STAT
	player_agility = CHARACTER_BASE_STAT
	player_charisma = CHARACTER_BASE_STAT
	player_intellect = CHARACTER_BASE_STAT
	player_luck = CHARACTER_BASE_STAT
	player_unspent_points = CHARACTER_BONUS_POINTS
	player_appearance = CHARACTER_APPEARANCE_DEFAULTS.duplicate(true)
	player_character_created = false
	_sync_character_profile_to_dialogic()
	player_profile_changed.emit(get_character_profile())
	_refresh_runtime_speaker_label()


func apply_character_profile(full_name: String, stats: Dictionary) -> bool:
	var profile: Dictionary = get_character_profile()
	profile["identity"] = {"full_name": full_name.strip_edges(), "short_name": get_protagonist_short_name()}
	profile["stats"] = stats.duplicate(true)
	return apply_character_profile_v2(profile)


func apply_character_profile_v2(profile: Dictionary) -> bool:
	var identity: Dictionary = profile.get("identity", {})
	var normalized_name := str(identity.get("full_name", "")).strip_edges()
	if normalized_name.is_empty():
		return false

	var normalized_appearance := _normalize_character_appearance(profile.get("appearance", {}))
	var normalized_stats := _normalize_character_stats(profile.get("stats", {}))
	var spent_points := 0
	for stat_key in CHARACTER_STAT_KEYS:
		var stat_value := int(normalized_stats.get(stat_key, CHARACTER_BASE_STAT))
		if stat_value < CHARACTER_MIN_STAT or stat_value > CHARACTER_MAX_STAT:
			return false
		spent_points += stat_value - CHARACTER_BASE_STAT

	var creation_budget := CHARACTER_BONUS_POINTS
	var gameplay := get_node_or_null("/root/Gameplay")
	if gameplay != null: creation_budget = int(gameplay.creation_budget())
	if spent_points < 0 or spent_points > creation_budget:
		return false

	player_profile_schema_version = CHARACTER_PROFILE_SCHEMA_VERSION
	player_full_name = normalized_name
	player_strength = int(normalized_stats["strength"])
	player_agility = int(normalized_stats["agility"])
	player_charisma = int(normalized_stats["charisma"])
	player_intellect = int(normalized_stats["intellect"])
	player_luck = int(normalized_stats["luck"])
	player_unspent_points = creation_budget - spent_points
	player_appearance = normalized_appearance
	player_character_created = true
	_sync_character_profile_to_dialogic()
	player_profile_changed.emit(get_character_profile())
	_refresh_runtime_speaker_label()
	return true


func localize(key: String, replacements: Dictionary = {}) -> String:
	var language_code := get_language_code()
	var table: Dictionary = TRANSLATIONS.get(language_code, TRANSLATIONS[LANGUAGE_RU])
	var fallback_table: Dictionary = TRANSLATIONS[LANGUAGE_RU]
	var text := str(table.get(key, fallback_table.get(key, key)))
	for replacement_key in replacements.keys():
		text = text.replace("{%s}" % replacement_key, str(replacements[replacement_key]))
	return text


func _emit_game_time_changed() -> void:
	game_time_changed.emit(get_game_time_snapshot())


func _get_time_phase(minute_of_day: int) -> String:
	for phase in ["dawn", "day", "evening"]:
		var bounds: Dictionary = GAME_TIME_PHASES[phase]
		if minute_of_day >= int(bounds["start"]) and minute_of_day < int(bounds["end"]):
			return phase
	return "night"


func _ensure_character_profile_initialized() -> void:
	if Dialogic == null or not Dialogic.has_subsystem("VAR"):
		return

	if not Dialogic.VAR.has(CHARACTER_NAME_VAR):
		reset_character_profile()
		return

	_sync_character_profile_from_dialogic()


func _update_default_character_name_for_language(previous_language: String, new_language: String) -> void:
	if not player_character_created or player_full_name.is_empty():
		return
	var previous_default := get_default_character_full_name(previous_language)
	if player_full_name != previous_default:
		return

	player_full_name = get_default_character_full_name(new_language)
	_sync_character_profile_to_dialogic()
	player_profile_changed.emit(get_character_profile())
	_refresh_runtime_speaker_label()


func _apply_runtime_language() -> void:
	TranslationServer.set_locale(get_language_code())

	var dialogic := DialogicUtil.autoload()
	if dialogic == null:
		return

	if dialogic.has_subsystem("Text"):
		var current_speaker: DialogicCharacter = dialogic.Text.get_current_speaker()
		dialogic.Text.update_name_label(current_speaker, true)

		var current_event := _get_current_dialogic_event(dialogic)
		if current_event is DialogicTextEvent:
			var translated_text := (current_event as DialogicTextEvent)._get_property_original_translation("text")
			if get_language_code() != LANGUAGE_RU:
				translated_text = (current_event as DialogicTextEvent).get_property_translated("text")
			if not translated_text.is_empty():
				dialogic.Text.update_dialog_text(dialogic.Text.parse_text(translated_text, 0), true)

	if dialogic.has_subsystem("Choices") and dialogic.current_state == DialogicGameHandler.States.AWAITING_CHOICE:
		dialogic.Choices.show_current_question(true)


func _get_current_dialogic_event(dialogic: DialogicGameHandler) -> DialogicEvent:
	if dialogic.current_event_idx < 0 or dialogic.current_event_idx >= dialogic.current_timeline_events.size():
		return null
	return dialogic.current_timeline_events[dialogic.current_event_idx]


func _register_runtime_translations() -> void:
	for translation in _runtime_translations:
		TranslationServer.remove_translation(translation)
	_runtime_translations.clear()

	for translation in _load_translations_from_csv(TIMELINE_TRANSLATION_CSV_PATH):
		TranslationServer.add_translation(translation)
		_runtime_translations.append(translation)


func _sync_character_profile_to_dialogic() -> void:
	if Dialogic == null or not Dialogic.has_subsystem("VAR"):
		return

	var profile := get_character_profile()
	var stats := (profile.get("stats", {}) as Dictionary).duplicate(true)
	var identity := (profile.get("identity", {}) as Dictionary).duplicate(true)
	var appearance := (profile.get("appearance", {}) as Dictionary).duplicate(true)
	var meta := (profile.get("meta", {}) as Dictionary).duplicate(true)
	var rules := (profile.get("rules", {}) as Dictionary).duplicate(true)
	Dialogic.VAR.var_storage[CHARACTER_VAR_FOLDER] = {
		"schema_version": player_profile_schema_version,
		"full_name": player_full_name,
		"identity": identity,
		"appearance": appearance,
		"stats": stats,
		"unspent_points": player_unspent_points,
		"rules": rules,
		"meta": meta,
		"is_character_created": player_character_created,
	}


func _sync_game_time_to_dialogic() -> void:
	if Dialogic == null or not Dialogic.has_subsystem("VAR"):
		return
	var stored: Variant = Dialogic.VAR.var_storage.get(WORLD_VAR_FOLDER, {})
	var world_data: Dictionary = stored.duplicate(true) if stored is Dictionary else {}
	world_data["time_total_minutes"] = _game_time_total_minutes
	world_data["day_length"] = get_game_day_length_id()
	Dialogic.VAR.var_storage[WORLD_VAR_FOLDER] = world_data


func _sync_game_time_from_dialogic() -> void:
	if Dialogic == null or not Dialogic.has_subsystem("VAR"):
		return

	var world_data: Variant = Dialogic.VAR.var_storage.get(WORLD_VAR_FOLDER, {})
	if not (world_data is Dictionary):
		_sync_game_time_to_dialogic()
		return

	_game_time_total_minutes = maxi(int((world_data as Dictionary).get("time_total_minutes", GAME_TIME_START_MINUTE)), 0)
	_game_time_accumulator = 0.0
	_emit_game_time_changed()
	game_time_reset.emit(get_game_time_snapshot())


func _sync_character_profile_from_dialogic() -> void:
	if Dialogic == null or not Dialogic.has_subsystem("VAR"):
		return

	var player_data: Variant = Dialogic.VAR.var_storage.get(CHARACTER_VAR_FOLDER, {})
	if not (player_data is Dictionary):
		reset_character_profile()
		return

	player_profile_schema_version = int(player_data.get("schema_version", 1))
	var identity: Dictionary = player_data.get("identity", {})
	var normalized_stats := _normalize_character_stats(player_data.get("stats", {}))
	var normalized_appearance := _normalize_character_appearance(player_data.get("appearance", {}))
	var meta: Dictionary = player_data.get("meta", {})
	var inferred_created := bool(meta.get("is_character_created", player_data.get("is_character_created", false)))
	if player_profile_schema_version < CHARACTER_PROFILE_SCHEMA_VERSION:
		inferred_created = inferred_created or int(player_data.get("unspent_points", CHARACTER_BONUS_POINTS)) != CHARACTER_BONUS_POINTS
	var normalized_name := str(identity.get("full_name", player_data.get("full_name", ""))).strip_edges()
	if not inferred_created:
		normalized_name = ""

	player_character_created = inferred_created
	player_full_name = normalized_name
	player_strength = int(normalized_stats["strength"])
	player_agility = int(normalized_stats["agility"])
	player_charisma = int(normalized_stats["charisma"])
	player_intellect = int(normalized_stats["intellect"])
	player_luck = int(normalized_stats["luck"])
	player_appearance = normalized_appearance

	var spent_points := 0
	for stat_key in CHARACTER_STAT_KEYS:
		spent_points += int(normalized_stats[stat_key]) - CHARACTER_BASE_STAT
	player_unspent_points = clampi(CHARACTER_BONUS_POINTS - spent_points, 0, CHARACTER_BONUS_POINTS)

	if player_profile_schema_version < CHARACTER_PROFILE_SCHEMA_VERSION:
		player_profile_schema_version = CHARACTER_PROFILE_SCHEMA_VERSION
	_sync_character_profile_to_dialogic()
	player_profile_changed.emit(get_character_profile())
	_refresh_runtime_speaker_label()


func _normalize_character_stats(stats: Variant) -> Dictionary:
	var source: Dictionary = stats if stats is Dictionary else {}
	var normalized := CHARACTER_STAT_DEFAULTS.duplicate(true)
	for stat_key in CHARACTER_STAT_KEYS:
		normalized[stat_key] = clampi(int(source.get(stat_key, CHARACTER_BASE_STAT)), CHARACTER_MIN_STAT, CHARACTER_MAX_STAT)
	return normalized


func _normalize_character_appearance(appearance: Variant) -> Dictionary:
	var source: Dictionary = appearance if appearance is Dictionary else {}
	var normalized := CHARACTER_APPEARANCE_DEFAULTS.duplicate(true)
	var gender := str(source.get("gender", normalized["gender"]))
	if gender != "female":
		gender = "male"
	normalized["gender"] = gender
	normalized["body_type"] = _pick_allowed_value(str(source.get("body_type", normalized["body_type"])), ["slim", "athletic"], str(normalized["body_type"]))
	normalized["face_id"] = _pick_allowed_value(str(source.get("face_id", normalized["face_id"])), ["soft", "sharp"], str(normalized["face_id"]))
	normalized["hair_style"] = _pick_allowed_value(str(source.get("hair_style", normalized["hair_style"])), ["short", "long"], str(normalized["hair_style"]))
	normalized["hair_color"] = _pick_allowed_value(str(source.get("hair_color", normalized["hair_color"])), ["dark", "light"], str(normalized["hair_color"]))
	normalized["genital_type"] = _pick_allowed_value(str(source.get("genital_type", "penis" if gender == "male" else "vulva")), ["penis"] if gender == "male" else ["vulva"], "penis" if gender == "male" else "vulva")
	normalized["genital_size"] = _pick_allowed_value(str(source.get("genital_size", "average" if gender == "male" else "full")), ["small", "average"] if gender == "male" else ["small", "full"], "average" if gender == "male" else "full")
	normalized["censorship_enabled"] = bool(source.get("censorship_enabled", normalized["censorship_enabled"]))
	normalized["portrait_expression"] = str(source.get("portrait_expression", normalized["portrait_expression"]))
	normalized["portrait_preset"] = str(source.get("portrait_preset", normalized["portrait_preset"]))
	return normalized


func _pick_allowed_value(value: String, allowed: Array, fallback: String) -> String:
	return value if value in allowed else fallback


func _refresh_runtime_speaker_label() -> void:
	if Dialogic == null or not Dialogic.has_subsystem("Text"):
		return
	var current_speaker: DialogicCharacter = Dialogic.Text.get_current_speaker()
	Dialogic.Text.update_name_label(current_speaker, true)


func _load_translations_from_csv(csv_path: String) -> Array[Translation]:
	if not FileAccess.file_exists(csv_path):
		return []

	var file := FileAccess.open(csv_path, FileAccess.READ)
	if file == null:
		return []

	var header := file.get_csv_line()
	if header.size() < 3:
		return []

	var locale_columns: Array[String] = []
	var translations_by_locale: Dictionary = {}
	for index in range(1, header.size()):
		var locale_code := str(header[index]).strip_edges()
		if locale_code.is_empty():
			continue
		locale_columns.append(locale_code)
		translations_by_locale[locale_code] = Translation.new()
		(translations_by_locale[locale_code] as Translation).locale = locale_code

	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.is_empty():
			continue

		var key := str(row[0]).strip_edges()
		if key.is_empty():
			continue

		for locale_index in range(locale_columns.size()):
			var value_index := locale_index + 1
			if value_index >= row.size():
				continue

			var translated_text := str(row[value_index])
			if translated_text.is_empty():
				continue

			var locale_code := locale_columns[locale_index]
			var translation: Translation = translations_by_locale.get(locale_code)
			if translation != null:
				translation.add_message(key, translated_text)

	var result: Array[Translation] = []
	for locale_code in locale_columns:
		var translation: Translation = translations_by_locale.get(locale_code)
		if translation != null:
			result.append(translation)
	return result


func is_instant_text_enabled() -> bool:
	return bool(Dialogic.Save.get_global_info(INSTANT_TEXT_ENABLED_KEY, false))


func set_instant_text_enabled(enabled: bool) -> void:
	Dialogic.Save.set_global_info(INSTANT_TEXT_ENABLED_KEY, enabled)
	_apply_text_settings()
	text_settings_changed.emit()


func is_autosave_enabled() -> bool:
	return bool(Dialogic.Save.get_global_info(AUTOSAVE_ENABLED_KEY, true))


func set_autosave_enabled(enabled: bool) -> void:
	Dialogic.Save.set_global_info(AUTOSAVE_ENABLED_KEY, enabled)
	_apply_autosave_interval(get_autosave_interval_minutes())
	autosave_settings_changed.emit()


func is_time_autosave_enabled() -> bool:
	return bool(Dialogic.Save.get_global_info(AUTOSAVE_TIME_ENABLED_KEY, true))


func set_time_autosave_enabled(enabled: bool) -> void:
	Dialogic.Save.set_global_info(AUTOSAVE_TIME_ENABLED_KEY, enabled)
	_apply_autosave_interval(get_autosave_interval_minutes())
	autosave_settings_changed.emit()


func is_choice_autosave_enabled() -> bool:
	return bool(Dialogic.Save.get_global_info(AUTOSAVE_BEFORE_CHOICE_KEY, false))


func set_choice_autosave_enabled(enabled: bool) -> void:
	Dialogic.Save.set_global_info(AUTOSAVE_BEFORE_CHOICE_KEY, enabled)
	autosave_settings_changed.emit()


func perform_autosave() -> Error:
	if _has_gameplay_restore_error(): return ERR_INVALID_DATA
	if _autosave_runtime_paused or not is_game_scene_active() or get_tree().paused:
		return OK
	if not _autosave_progress_dirty:
		return OK

	var slot_index := _get_next_autosave_index()
	var slot_id := _auto_slot_id(slot_index)
	capture_thumbnail()

	var save_info := {
		"title": _build_slot_title({
			"kind": SLOT_KIND_AUTO,
			"slot_index": slot_index,
		}),
		"saved_at_text": _format_now(),
		"kind": SLOT_KIND_AUTO,
		"page_index": 0,
		"slot_index": slot_index,
	}

	var thumbnail_mode: int = Dialogic.Save.ThumbnailMode.TAKE_AND_STORE
	if Dialogic.Save.latest_thumbnail != null:
		thumbnail_mode = Dialogic.Save.ThumbnailMode.STORE_ONLY

	var save_error: Error = Dialogic.Save.save(slot_id, false, thumbnail_mode, save_info)
	if save_error == OK:
		_set_next_autosave_index((slot_index + 1) % AUTO_SLOT_COUNT)
		_autosave_progress_dirty = false
		save_slots_changed.emit()

	return save_error


func _get_user_page_count() -> int:
	var highest_page_index := -1

	for slot_name in Dialogic.Save.get_slot_names():
		var slot_ref := _decode_slot_reference(slot_name)
		if slot_ref.get("kind", "") == SLOT_KIND_USER:
			highest_page_index = maxi(highest_page_index, int(slot_ref.get("page_index", 0)))

	return maxi(highest_page_index + 2, 1)


func _decode_slot_reference(slot_id: String) -> Dictionary:
	if slot_id.begins_with("auto_"):
		var auto_parts := slot_id.split("_")
		if auto_parts.size() == 2 and auto_parts[1].is_valid_int():
			return {
				"id": slot_id,
				"kind": SLOT_KIND_AUTO,
				"page_index": 0,
				"slot_index": maxi(int(auto_parts[1]) - 1, 0),
			}

	if slot_id.begins_with("quick_"):
		var quick_parts := slot_id.split("_")
		if quick_parts.size() == 2 and quick_parts[1].is_valid_int():
			return {
				"id": slot_id,
				"kind": SLOT_KIND_QUICK,
				"page_index": 0,
				"slot_index": maxi(int(quick_parts[1]) - 1, 0),
			}

	if slot_id.begins_with("user_p"):
		var user_parts := slot_id.split("_")
		if user_parts.size() == 3:
			var page_text := user_parts[1].trim_prefix("p")
			var slot_text := user_parts[2].trim_prefix("s")
			if page_text.is_valid_int() and slot_text.is_valid_int():
				return {
					"id": slot_id,
					"kind": SLOT_KIND_USER,
					"page_index": maxi(int(page_text) - 1, 0),
					"slot_index": maxi(int(slot_text) - 1, 0),
				}

	return {}


func _build_slot_title(slot_ref: Dictionary) -> String:
	var kind := str(slot_ref.get("kind", SLOT_KIND_USER))
	var slot_number := int(slot_ref.get("slot_index", 0)) + 1

	match kind:
		SLOT_KIND_AUTO:
			return localize("slot.auto_title", {"index": "%02d" % slot_number})
		SLOT_KIND_QUICK:
			return localize("slot.quick_title", {"index": "%02d" % slot_number})
		_:
			var page_number := int(slot_ref.get("page_index", 0)) + 1
			return localize("slot.user_title", {"page": page_number, "slot": "%02d" % slot_number})


func _preview_color(kind: String, exists: bool) -> Color:
	if not exists:
		return Color(0.14, 0.15, 0.17)

	match kind:
		SLOT_KIND_AUTO:
			return Color(0.44, 0.56, 0.78)
		SLOT_KIND_QUICK:
			return Color(0.75, 0.45, 0.32)
		_:
			return Color(0.32, 0.62, 0.48)


func _format_now() -> String:
	var now := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d %02d:%02d" % [
		int(now["year"]),
		int(now["month"]),
		int(now["day"]),
		int(now["hour"]),
		int(now["minute"]),
	]


func _apply_autosave_interval(minutes: int) -> void:
	_autosave_timer.wait_time = float(minutes * 60)
	_autosave_timer.stop()
	if is_autosave_enabled() and is_time_autosave_enabled() and not _autosave_runtime_paused:
		_autosave_timer.start()


func _apply_text_settings() -> void:
	var effective_text_speed := 0.0 if is_instant_text_enabled() else 1.0 / get_text_speed_multiplier()

	if Dialogic.has_subsystem("Settings"):
		Dialogic.Settings.set("text_speed", effective_text_speed)

	if Dialogic.has_subsystem("Text"):
		Dialogic.Text.update_text_speed()


func _normalize_autosave_minutes(minutes: int) -> int:
	var clamped := clampi(minutes, AUTOSAVE_MIN_MINUTES, AUTOSAVE_MAX_MINUTES)
	var snapped := int(round(float(clamped) / float(AUTOSAVE_STEP_MINUTES))) * AUTOSAVE_STEP_MINUTES
	return clampi(snapped, AUTOSAVE_MIN_MINUTES, AUTOSAVE_MAX_MINUTES)


func _normalize_text_speed_multiplier(multiplier: float) -> float:
	var clamped := clampf(multiplier, TEXT_SPEED_MIN, TEXT_SPEED_MAX)
	var steps: float = round((clamped - TEXT_SPEED_MIN) / TEXT_SPEED_STEP)
	var snapped: float = TEXT_SPEED_MIN + steps * TEXT_SPEED_STEP
	return clampf(snapped, TEXT_SPEED_MIN, TEXT_SPEED_MAX)


func _get_next_autosave_index() -> int:
	var stored_index := int(Dialogic.Save.get_global_info(AUTOSAVE_INDEX_KEY, 0))
	return clampi(stored_index, 0, AUTO_SLOT_COUNT - 1)


func _set_next_autosave_index(slot_index: int) -> void:
	Dialogic.Save.set_global_info(AUTOSAVE_INDEX_KEY, slot_index)


func _on_autosave_timer_timeout() -> void:
	perform_autosave()


func _on_question_shown(_question_info: Dictionary) -> void:
	if _choice_autosave_pending:
		return
	if not _autosave_runtime_paused and is_autosave_enabled() and is_choice_autosave_enabled() and _autosave_progress_dirty:
		_choice_autosave_pending = true
		call_deferred("_perform_choice_autosave")


func _perform_choice_autosave() -> void:
	await get_tree().process_frame
	_choice_autosave_pending = false
	if not _autosave_runtime_paused and is_autosave_enabled() and is_choice_autosave_enabled() and _autosave_progress_dirty:
		perform_autosave()


func _on_choice_selected(_choice_info: Dictionary) -> void:
	_mark_autosave_progress()


func _on_about_to_show_text(_info: Dictionary) -> void:
	_mark_autosave_progress()


func _mark_autosave_progress() -> void:
	if not is_game_scene_active():
		return
	_autosave_progress_dirty = true


func _reset_autosave_progress() -> void:
	_autosave_progress_dirty = false
	_choice_autosave_pending = false


func _auto_slot_id(slot_index: int) -> String:
	return "auto_%02d" % (slot_index + 1)


func _quick_slot_id(slot_index: int) -> String:
	return "quick_%02d" % (slot_index + 1)


func _user_slot_id(page_index: int, slot_index: int) -> String:
	return "user_p%d_s%02d" % [page_index + 1, slot_index + 1]
