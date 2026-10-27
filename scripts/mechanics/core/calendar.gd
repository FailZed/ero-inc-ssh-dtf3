extends RefCounted
## Keeps the existing game's April 12 epoch and absolute minute representation.
const EPOCH := {"year": 2026, "month": 4, "day": 12, "hour": 0, "minute": 0, "second": 0}
const MONTHS := ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

static func add_months(total_minutes: int, months: int) -> int:
	var current := snapshot(total_minutes)
	var month_index := int(current.year) * 12 + int(current.month_number) - 1 + months
	var year := int(month_index / 12)
	var month := month_index % 12 + 1
	var lengths := [31, 29 if (year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)) else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	var date := {"year": year, "month": month, "day": mini(int(current.day), int(lengths[month - 1])), "hour": current.hour, "minute": current.minute, "second": 0}
	return int((Time.get_unix_time_from_datetime_dict(date) - Time.get_unix_time_from_datetime_dict(EPOCH)) / 60)

static func snapshot(total_minutes: int) -> Dictionary:
	var total := maxi(0, total_minutes)
	var date := Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_datetime_dict(EPOCH)) + total * 60)
	var minute_of_day := total % 1440
	var phase := "night"
	if minute_of_day >= 300 and minute_of_day < 480:
		phase = "dawn"
	elif minute_of_day >= 480 and minute_of_day < 1080:
		phase = "day"
	elif minute_of_day >= 1080 and minute_of_day < 1320:
		phase = "evening"
	return {
		"total_minutes": total, "minute_of_day": minute_of_day,
		"hour": int(date.hour), "minute": int(date.minute),
		"day": int(date.day), "month_number": int(date.month), "month": MONTHS[int(date.month) - 1],
		"year": int(date.year), "weekday": (int(date.weekday) + 6) % 7 + 1,
		"day_index": int(total / 1440), "week_index": int(total / 10080),
		"phase": phase, "time_text": "%02d:%02d" % [date.hour, date.minute],
		"date_text": "%s %02d" % [MONTHS[int(date.month) - 1], date.day],
	}
