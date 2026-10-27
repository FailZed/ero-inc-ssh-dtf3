extends RefCounted
## Pure presentation profile; the authoritative weather and clock live in Simulation.
const PERIODS := {"morning":"Утро", "day":"День", "sunset":"Закат", "night":"Ночь"}
const WEATHER := {"clear":"Солнечно", "cloudy":"Пасмурно", "rain":"Дождь", "snow":"Снег"}

static func profile(clock: Dictionary, weather: String, indoors: bool = false) -> Dictionary:
	var minute := int(clock.minute_of_day)
	var period := "morning" if minute >= 300 and minute < 480 else "day" if minute >= 480 and minute < 1080 else "sunset" if minute >= 1080 and minute < 1320 else "night"
	var shade := {"clear":1.0,"cloudy":0.76,"rain":0.64,"snow":0.87}
	return {"period":period,"weather":weather,"indoors":indoors,"brightness":lerpf(1.0,float(shade.get(weather,1.0)),0.4 if indoors else 1.0),"saturation":1.0 if weather == "clear" else 0.68,"precipitation":0 if indoors else 1 if weather == "rain" else 2 if weather == "snow" else 0,"label":str(PERIODS[period]) + " · " + ("Ясно" if weather == "clear" and period == "night" else str(WEATHER.get(weather,"Ясно")))}
