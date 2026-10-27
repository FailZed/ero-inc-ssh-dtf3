class_name ProtagonistAppearanceAssembler
extends RefCounted

const PROTAGONIST_IDENTIFIER := "ГГ"

static func build_dialogic_extra_data(profile: Dictionary) -> String:
	var appearance: Dictionary = profile.get("appearance", {})
	var gender := _capitalize(str(appearance.get("gender", "male")))
	var other_gender := "Female" if gender == "Male" else "Male"
	var body_type := _capitalize(str(appearance.get("body_type", "slim")))
	var face_id := _capitalize(str(appearance.get("face_id", "soft")))
	var hair_style := _capitalize(str(appearance.get("hair_style", "short")))
	var hair_color := _capitalize(str(appearance.get("hair_color", "dark")))
	var censorship_enabled := bool(appearance.get("censorship_enabled", true))
	var commands: Array[String] = [
		"show Variants/Body/%s" % gender,
		"hide Variants/Body/%s" % other_gender,
		"set Variants/Body/%s/%s" % [gender, body_type],
		"set Variants/Face/%s" % face_id,
		"set Variants/Hair/Style/%s" % hair_style,
		"set Variants/Hair/Color/%s" % hair_color,
		"hide Variants/Genitals/Penis",
		"hide Variants/Genitals/Vulva",
	]

	if censorship_enabled:
		commands.append("show Variants/Censor/Underwear%s" % gender)
		commands.append("hide Variants/Censor/Underwear%s" % other_gender)
	else:
		commands.append("hide Variants/Censor/UnderwearMale")
		commands.append("hide Variants/Censor/UnderwearFemale")

	return ", ".join(commands)


static func build_preview_summary(profile: Dictionary, ui_texts: Dictionary, appearance_options: Dictionary, stat_labels: Dictionary) -> String:
	var appearance: Dictionary = profile.get("appearance", {})
	var stats: Dictionary = profile.get("stats", {})
	var identity: Dictionary = profile.get("identity", {})
	var lines := [
		str(ui_texts.get("summary_label", "Summary")),
		"",
		"%s: %s" % [str(ui_texts.get("name_label", "Name")), str(identity.get("full_name", "") if not str(identity.get("full_name", "")).is_empty() else "—")],
		"%s: %s" % [str(appearance_options.get("gender", {}).get("label", "Gender")), _find_option_label(appearance_options, "gender", str(appearance.get("gender", "")))],
		"%s: %s" % [str(appearance_options.get("body_type", {}).get("label", "Body")), _find_option_label(appearance_options, "body_type", str(appearance.get("body_type", "")))],
		"%s: %s" % [str(appearance_options.get("face_id", {}).get("label", "Face")), _find_option_label(appearance_options, "face_id", str(appearance.get("face_id", "")))],
		"%s: %s" % [str(appearance_options.get("hair_style", {}).get("label", "Hair")), _find_option_label(appearance_options, "hair_style", str(appearance.get("hair_style", "")))],
		"%s: %s" % [str(appearance_options.get("hair_color", {}).get("label", "Color")), _find_option_label(appearance_options, "hair_color", str(appearance.get("hair_color", "")))],
		"%s: %s" % [str(appearance_options.get("genital_type", {}).get("label", "Type")), _find_option_label(appearance_options, "genital_type", str(appearance.get("genital_type", "")))],
		"%s: %s" % [str(appearance_options.get("genital_size", {}).get("label", "Size")), _find_option_label(appearance_options, "genital_size", str(appearance.get("genital_size", "")))],
		str(ui_texts.get("censorship_on", "Censorship enabled")) if bool(appearance.get("censorship_enabled", true)) else str(ui_texts.get("censorship_off", "Censorship disabled")),
		"",
	]

	for stat_key in stat_labels.keys():
		lines.append("%s: %s" % [str(stat_labels[stat_key]), str(stats.get(stat_key, 0))])

	return "\n".join(lines)


static func _find_option_label(appearance_options: Dictionary, field: String, option_id: String) -> String:
	var options: Array = appearance_options.get(field, {}).get("options", [])
	for option in options:
		if str(option.get("id", "")) == option_id:
			return str(option.get("label", option_id))
	return option_id


static func _capitalize(value: String) -> String:
	if value.is_empty():
		return value
	return value.substr(0, 1).to_upper() + value.substr(1)
