extends RefCounted
## Derived rendering state. Reading a portrait never mutates the simulation or RNG.
static func describe(actor: Dictionary) -> Dictionary:
	var needs: Dictionary = actor.get("needs",{})
	var injuries: Dictionary = actor.get("injuries",{})
	var health := float(needs.get("health", actor.get("health",100)))
	var tired := float(needs.get("energy",100)) < 25 or float(needs.get("rested",100)) < 25
	var dirty := clampf((35.0-float(needs.get("hygiene",100)))/35.0,0,1)
	var wounded := health < 45
	for severity in injuries.values():
		if float(severity) > 0: wounded = true; break
	var expression := "neutral"
	if tired or wounded or float(needs.get("mood",60)) < 25: expression = "concern"
	elif float(needs.get("mood",60)) >= 80: expression = "smile"
	var pregnancy := clampi(int(actor.get("appearance",{}).get("pregnancy_stage",0)),0,4)
	var labels: Array[String] = []
	if tired: labels.append("Усталость")
	if wounded: labels.append("Восстановление после травмы")
	if dirty > 0: labels.append("Нужен душ")
	if pregnancy > 0: labels.append("Беременность · этап %d" % pregnancy)
	return {"expression":expression,"tired":tired,"dirty":dirty,"wounded":wounded,"pregnancy":pregnancy,"labels":labels}
