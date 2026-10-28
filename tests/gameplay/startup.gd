extends SceneTree
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, description: String) -> void:
	checks += 1
	if not value: failures.append(description); printerr("FAIL: ",description)

func _run() -> void:
	root.get_node("GameSession").pause_autosave_runtime()
	for identifier in ["god?","Асука","Лира","ГГ"]:
		var character = DialogicResourceUtil.get_resource_from_identifier(identifier,"dch")
		check(character is DialogicCharacter,"authored speaker survives clean import: " + identifier)
	check(DialogicResourceUtil.get_resource_path_from_identifier("prolog/prolog","dtl") == "res://TimeLine/prolog/prolog.dtl","intro jump keeps authored timeline identifier")
	var first := ConditionResource.new()
	first.is_true = true
	var second := ConditionResource.new()
	second.is_true = false
	var compound := ConditionResource.new()
	compound.type = ConditionResource.ConditionType.COMPOUND
	compound.sub_conditions.assign([first,second])
	check(not compound.check({}),"compound AND evaluates children")
	compound.logic_operator = ConditionResource.LogicOperator.OR
	check(compound.check({}),"compound OR evaluates children")
	var restored := ConditionResource.new()
	restored.from_dictionary(compound.to_dictionary())
	check(restored.sub_conditions.size() == 2 and restored.check({}),"compound conditions roundtrip")
	var copied = load("res://addons/quest_weaver/editor/qw_clipboard.gd").new()
	var duplicated: ConditionResource = copied._deep_duplicate_condition_recursively(compound)
	check(duplicated != compound and duplicated.sub_conditions[0] != first and duplicated.check({}),"editor clipboard preserves deep condition copy")
	print("STARTUP_RESULT ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
