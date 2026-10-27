extends RefCounted
## One information architecture for the HUD, screen rail and section browser.
const GROUPS := [
	{"title":"МОЙ ПЕРСОНАЖ", "screens":[["profile","Персонаж","profile","C"], ["inventory","Сумка","inventory","I"], ["health","Самочувствие","health",""], ["family","Семья","home",""]]},
	{"title":"ГОРОД И ЛЮДИ", "screens":[["map","Карта города","map","M"], ["people","Отношения","people","R"], ["phone","Телефон","phone","P"], ["home","Мой дом","home",""]]},
	{"title":"ДЕЛА И ИСТОРИИ", "screens":[["journal","Журнал","journal","J"], ["activities","Занятия","desk",""], ["work","Работа и деньги","wallet",""], ["club","Мой клуб","people",""], ["digital","Цифровой мир","desk",""], ["collection","Воспоминания","eye",""]]}]

static func title(id: String) -> String:
	for group in GROUPS:
		for screen in group.screens:
			if screen[0] == id: return screen[1]
	return {"place":"Здесь и сейчас", "npc":"Знакомство", "gathering":"Встреча", "interface":"Интерфейс и управление"}.get(id, "EroInc")

static func parent(id: String) -> String:
	return "people" if id in ["npc", "gathering"] else id
