extends RefCounted
## Small authored exploration graphs. Goals guide; looking around never consumes a resource.
const PLACES := {
	"bedroom":{"title":"Спальня","background":"res://assets/textures/backgrounds/location_pack_v1/bedroom_night.png","exits":["apartment_hall"],"objects":{"clock":"Часы","wardrobe":"Шкаф","photo":"Фотография","bed":"Кровать"}},
	"apartment_hall":{"title":"Прихожая","background":"res://assets/textures/backgrounds/location_pack_v1/hallway_night.png","exits":["bedroom","bathroom","kitchen","student_home"],"objects":{"switch":"Выключатель","door":"Входная дверь"}},
	"bathroom":{"title":"Ванная","background":"res://assets/textures/backgrounds/location_pack_v1/bathroom_night.png","exits":["apartment_hall"],"objects":{"sink":"Умывальник","mirror":"Зеркало","washer":"Стиральная машина"}},
	"kitchen":{"title":"Кухня","background":"res://assets/textures/locations/apartment/kitchen_16x9.png","exits":["apartment_hall"],"objects":{"kettle":"Чайник","window":"Окно","fridge":"Холодильник"}},
	"student_home":{"title":"У дома","background":"res://assets/textures/backgrounds/location_pack_v1/home_street_day.png","exits":["apartment_hall"],"objects":{"sign":"Дорога к университету"}},
	"campus_courtyard":{"title":"Двор университета","background":"res://assets/textures/backgrounds/location_pack_v1/home_street_day.png","exits":["campus_hall"],"objects":{"notice":"Объявления","entrance":"Главный вход"}},
	"campus_hall":{"title":"Холл университета","background":"res://assets/textures/locations/apartment/hallway_16x9.png","exits":["campus_courtyard","campus_corridor"],"objects":{"notice":"Указатель аудиторий","bear":"Дежурный"}},
	"campus_corridor":{"title":"Второй этаж · левое крыло","background":"res://assets/textures/locations/apartment/hallway_16x9.png","exits":["campus_hall"],"objects":{"club":"Косплейный клуб","classroom":"Аудитория 213","bathroom_door":"Мужской туалет"}}
}
static func background(id: String) -> String:
	var campus := {"campus_courtyard":"courtyard","campus_hall":"hall","campus_corridor":"corridor"}
	if campus.has(id): return "res://assets/textures/backgrounds/campus_v1/%s.tres" % campus[id]
	return str(PLACES[id].background)
const STAGES := {
	"night":{"title":"Прийти в себя","objective":"Пройдите в ванную и умойтесь.","hint":"Из спальни выйдите в прихожую. Дверь ванной находится рядом.","start":"bedroom","allowed":["bedroom","apartment_hall","bathroom","kitchen"],"goal_place":"bathroom","goal":"sink","action":"УМЫТЬСЯ","timeline":"scene_05_mirror_and_photo/"},
	"return_to_bed":{"title":"Пора снова спать","objective":"Вернитесь в спальню и возьмите сухую подушку из шкафа.","hint":"Шкаф стоит в спальне. Старую подушку вы оставили в ванной.","start":"bathroom","allowed":["bedroom","apartment_hall","bathroom","kitchen"],"goal_place":"bedroom","goal":"wardrobe","action":"ВЗЯТЬ СУХУЮ ПОДУШКУ","next":"photo"},
	"photo":{"title":"Знакомое лицо","objective":"Осмотрите фотографию на прикроватной тумбочке.","hint":"Фотография стоит возле кровати.","start":"bedroom","allowed":["bedroom","apartment_hall","bathroom","kitchen"],"goal_place":"bedroom","goal":"photo","action":"РАССМОТРЕТЬ ФОТОГРАФИЮ","timeline":"scene_05_mirror_and_photo/photo"},
	"morning_dress":{"title":"Первый учебный день","objective":"Откройте шкаф и оденьтесь.","hint":"В шкафу есть белая футболка и чёрные джинсы.","start":"bedroom","allowed":["bedroom","apartment_hall","bathroom","kitchen"],"goal_place":"bedroom","goal":"wardrobe","action":"ОДЕТЬСЯ","next":"morning_wash"},
	"morning_wash":{"title":"Собраться в университет","objective":"Зайдите в ванную и приведите себя в порядок.","hint":"Ванная рядом со спальней, через прихожую.","start":"bedroom","allowed":["bedroom","apartment_hall","bathroom","kitchen"],"goal_place":"bathroom","goal":"sink","action":"УМЫТЬСЯ И УЛОЖИТЬ ВОЛОСЫ","next":"morning_leave"},
	"morning_leave":{"title":"Не опоздать","objective":"Выйдите из квартиры через входную дверь.","hint":"Входная дверь находится в прихожей.","start":"bathroom","allowed":["bedroom","apartment_hall","bathroom","kitchen"],"goal_place":"apartment_hall","goal":"door","action":"ОТПРАВИТЬСЯ В УНИВЕРСИТЕТ","timeline":"chapter_one/arrival"},
	"campus":{"title":"Найти свою аудиторию","objective":"Найдите аудиторию 213 в левом крыле второго этажа.","hint":"Дежурный объяснит нумерацию. Поднимитесь в коридор левого крыла.","start":"campus_hall","allowed":["campus_hall","campus_corridor","campus_courtyard"],"goal_place":"campus_corridor","goal":"classroom","action":"ПОЙТИ К АУДИТОРИИ 213","timeline":"chapter_one/club"},
	"classroom":{"title":"Знакомство с группой","objective":"Зайдите в аудиторию 213.","hint":"После случившегося пора на встречу с куратором.","start":"campus_corridor","allowed":["campus_hall","campus_corridor","campus_courtyard"],"goal_place":"campus_corridor","goal":"classroom","action":"ВОЙТИ В АУДИТОРИЮ","timeline":"chapter_one/classroom"},
	"homecoming":{"title":"Длинный первый день","objective":"Вернитесь в квартиру.","hint":"Вход в ваш дом — через прихожую.","start":"student_home","allowed":["student_home","apartment_hall","bedroom","kitchen","bathroom"],"goal_place":"apartment_hall","goal":"door","action":"ЗАКОНЧИТЬ ПЕРВЫЙ ДЕНЬ","timeline":"chapter_one/end"}
}
const INSPECTIONS := {
	"clock":"На часах 03:20. За окном ещё темно. Стоит умыться и попробовать снова уснуть.",
	"wardrobe":"Немного одежды, чистая наволочка и запасная подушка. Всё на своих местах.",
	"photo":"Пожелтевшая фотография в старой рамке. При одном взгляде на неё становится теплее.",
	"bed":"После кошмара постель сбилась. Сейчас лучше сначала привести себя в порядок.",
	"switch":"Свет включается не с первого раза. Нужно будет вызвать мастера.",
	"door":"Сегодня лучше не уходить далеко: впереди первый день учёбы.",
	"sink":"Холодная вода помогает окончательно проснуться.",
	"mirror":"Знакомое лицо смотрит из глубины зеркала.",
	"washer":"На стиральной машине лежит мокрая подушка.",
	"kettle":"Пока не хочется чая. На кухне тихо.",
	"window":"Город не спит даже ночью. Где-то за домами ещё горят окна.",
	"fridge":"Еда есть. Сейчас мысли заняты другим.",
	"notice":"Первая цифра номера — этаж. Нечётные аудитории расположены слева, чётные — справа.",
	"bear":"Дежурный: «213 — на втором этаже в левом крыле. Если потеряешься, не бойся попросить помощи».",
	"club":"Ребята обсуждают костюмы для анимефеста. Чуть дальше находится нужная аудитория.",
	"bathroom_door":"Из-за двери слышны голоса. Лучше подойти ближе по пути к аудитории.",
	"entrance":"Студенты постепенно расходятся по аудиториям.",
	"sign":"От дома до университета примерно пятнадцать минут пешком."
}
