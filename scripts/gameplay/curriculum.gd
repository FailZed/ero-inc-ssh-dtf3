extends RefCounted
const SUBJECTS := {
	"computing":{"title":"Основы программирования","skill":"computing","days":[2,4],"hours":[600,660]},
	"physics":{"title":"Прикладная физика","skill":"study","days":[2,4],"hours":[660,720]},
	"statistics":{"title":"Генетическая статистика","skill":"study","days":[3,5],"hours":[600,660]},
	"genetics":{"title":"Генная инженерия","skill":"study","days":[3,5],"hours":[660,720]},
	"bioengineering":{"title":"Биоинженерия","skill":"study","days":[2,4],"hours":[720,780]},
	"behavior":{"title":"Поведенческая биология","skill":"study","days":[3,5],"hours":[720,780]}
}
const SPORTS := {"running":"Бег", "strength":"Силовая подготовка", "combat":"Самооборона"}
static func lessons() -> Dictionary:
	var result := {"common_day":{"location":"training_center","hours":[600,660],"weekdays":[1],"minutes":60,"skill":"study","xp":15,"grade":2,"absence_penalty":1}}
	for id in SUBJECTS:
		var entry: Dictionary = SUBJECTS[id]
		result["computing_class" if id == "computing" else id+"_class"] = {"location":"training_center","hours":entry.hours,"weekdays":entry.days,"minutes":60,"skill":entry.skill,"xp":20,"grade":3,"absence_penalty":1,"requirements":{"path":"world.flags.subject_"+id,"value":true}}
	return result
