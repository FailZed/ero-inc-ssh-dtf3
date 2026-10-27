extends RefCounted
const ERRORS := {"practice_location":"Для этой практики нужно другое место.","practice_daily_limit":"Эту практику можно выполнять до четырёх раз за день.","habit_max":"Привычка уже развита до третьей ступени.","habit_practice_required":"Сначала наберите больше практики в одном из связанных навыков.","invalid_need_setting":"Не удалось изменить эту потребность."}
static var _labels: Dictionary = {}
static func label(id: String) -> String:
	if _labels.is_empty():
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/mechanics/growth.json"))
		for key in data.skills: _labels[key] = str(data.skills[key].label)
	return str(_labels.get(id,""))
